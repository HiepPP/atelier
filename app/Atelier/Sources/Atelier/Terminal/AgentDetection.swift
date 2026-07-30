import Darwin
import Foundation

nonisolated enum AgentDetectionPolicy {
    static let defaultAgentNames = [
        "claude",
        "codex",
        "aider",
        "gemini",
        "cursor-agent"
    ]

    static func agentName(
        in arguments: [String],
        agentNames: [String] = defaultAgentNames
    ) -> String? {
        let names = Set(agentNames)
        for argument in arguments {
            if names.contains(argument) {
                return argument
            }
            let executableName = URL(fileURLWithPath: argument).lastPathComponent
            if names.contains(executableName) {
                return executableName
            }
        }
        return nil
    }
}

/// PTY identity for one terminal, captured on the main actor so the `sysctl`
/// probe it feeds can run off the main actor.
nonisolated struct TerminalForegroundAgentProbe: Sendable, Equatable {
    let ptyFileDescriptor: Int32
    let shellPID: pid_t

    func resolveAgentName() -> String? {
        ForegroundProcessAgentReader.agentName(
            ptyFileDescriptor: ptyFileDescriptor,
            shellPID: shellPID
        )
    }
}

/// `nonisolated` so the two `sysctl` round trips and the argument-buffer parse
/// never run on the main actor: the thread poll calls this once per open
/// terminal on a repeating cadence.
nonisolated enum ForegroundProcessAgentReader {
    static func agentName(
        ptyFileDescriptor: Int32,
        shellPID: pid_t
    ) -> String? {
        guard ptyFileDescriptor != -1 else { return nil }
        let foregroundPID = tcgetpgrp(ptyFileDescriptor)
        guard foregroundPID > 0, foregroundPID != shellPID else { return nil }
        guard let arguments = arguments(for: foregroundPID) else { return nil }
        return AgentDetectionPolicy.agentName(in: arguments)
    }

    private static func arguments(for processID: pid_t) -> [String]? {
        var query = [CTL_KERN, KERN_PROCARGS2, processID]
        var byteCount = 0
        let sizeResult = query.withUnsafeMutableBufferPointer { buffer in
            sysctl(
                buffer.baseAddress,
                u_int(buffer.count),
                nil,
                &byteCount,
                nil,
                0
            )
        }
        guard sizeResult == 0, byteCount > MemoryLayout<Int32>.size else { return nil }

        var bytes = [UInt8](repeating: 0, count: byteCount)
        let readResult = query.withUnsafeMutableBufferPointer { queryBuffer in
            bytes.withUnsafeMutableBytes { byteBuffer in
                sysctl(
                    queryBuffer.baseAddress,
                    u_int(queryBuffer.count),
                    byteBuffer.baseAddress,
                    &byteCount,
                    nil,
                    0
                )
            }
        }
        guard readResult == 0 else { return nil }
        // `byteCount` is the written length, which can be shorter than the
        // allocation. Pass it as a bound instead of copying the whole buffer
        // again: KERN_PROCARGS2 returns argv plus the environment block, so a
        // second copy is kilobytes per call on a repeating cadence.
        return parseArguments(bytes, count: byteCount)
    }

    private static func parseArguments(_ bytes: [UInt8], count: Int) -> [String]? {
        let integerSize = MemoryLayout<Int32>.size
        let end = min(count, bytes.count)
        guard end > integerSize else { return nil }

        var argumentCount: Int32 = 0
        withUnsafeMutableBytes(of: &argumentCount) { destination in
            bytes.withUnsafeBytes { source in
                destination.copyBytes(from: source.prefix(integerSize))
            }
        }
        guard argumentCount > 0 else { return nil }

        var index = integerSize
        while index < end, bytes[index] != 0 { index += 1 }
        while index < end, bytes[index] == 0 { index += 1 }

        var arguments: [String] = []
        arguments.reserveCapacity(Int(argumentCount))
        while index < end, arguments.count < Int(argumentCount) {
            let start = index
            while index < end, bytes[index] != 0 { index += 1 }
            if index > start,
               let argument = String(bytes: bytes[start..<index], encoding: .utf8) {
                arguments.append(argument)
            }
            while index < end, bytes[index] == 0 { index += 1 }
        }
        return arguments
    }
}
