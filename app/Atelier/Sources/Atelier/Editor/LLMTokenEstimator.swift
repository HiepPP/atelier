import Foundation

nonisolated enum LLMTokenEstimator {
    private static let estimatedBytesPerToken = 4

    static func estimate(byteCount: Int) -> Int {
        guard byteCount > 0 else { return 0 }
        return 1 + ((byteCount - 1) / estimatedBytesPerToken)
    }
}
