import Foundation
import Testing
@testable import Atelier

@Suite("Gemma sidecar context block")
struct GemmaSidecarContextTests {
    @Test("No tab yields no context block and an unchanged prompt")
    func noContext() {
        #expect(GemmaSidecarContextComposer.contextBlock(for: nil) == nil)
        #expect(GemmaSidecarContextComposer.compose(prompt: "Explain", context: nil) == "Explain")
    }

    @Test("File context carries the path and identity")
    func fileContext() {
        let context = GemmaSidecarTabContext(
            kind: .file,
            title: "WorkspaceSession.swift",
            status: "120 lines",
            systemImage: "doc.text",
            filePath: "/repo/Sources/WorkspaceSession.swift"
        )
        let block = GemmaSidecarContextComposer.contextBlock(for: context)
        #expect(block?.contains("File: /repo/Sources/WorkspaceSession.swift") == true)
        #expect(block?.contains("File - WorkspaceSession.swift (120 lines)") == true)
        #expect(block?.contains("Working directory:") == false)
    }

    @Test("Git diff context carries the diff target path")
    func gitDiffContext() {
        let context = GemmaSidecarTabContext(
            kind: .gitDiff,
            title: "main.swift [Unstaged]",
            status: "Ready",
            systemImage: "doc.text.magnifyingglass",
            gitDiffPath: "Sources/main.swift"
        )
        let block = GemmaSidecarContextComposer.contextBlock(for: context)
        #expect(block?.contains("Git diff target: Sources/main.swift") == true)
    }

    @Test("Terminal context carries the working directory")
    func terminalContext() {
        let context = GemmaSidecarTabContext(
            kind: .terminal,
            title: "Terminal 1",
            status: "Running",
            systemImage: "terminal",
            workingDirectory: "/repo"
        )
        let block = GemmaSidecarContextComposer.contextBlock(for: context)
        #expect(block?.contains("Working directory: /repo") == true)
    }

    @Test("Editor selection is included only when present")
    func editorSelection() {
        let withSelection = GemmaSidecarTabContext(
            kind: .file,
            title: "main.swift",
            status: "10 lines",
            systemImage: "doc.text",
            filePath: "/repo/main.swift",
            editorSelection: "let needle = 1"
        )
        let block = GemmaSidecarContextComposer.contextBlock(for: withSelection)
        #expect(block?.contains("Editor selection:") == true)
        #expect(block?.contains("let needle = 1") == true)

        let blank = GemmaSidecarTabContext(
            kind: .file,
            title: "main.swift",
            status: "10 lines",
            systemImage: "doc.text",
            filePath: "/repo/main.swift",
            editorSelection: "   \n  "
        )
        #expect(GemmaSidecarContextComposer.contextBlock(for: blank)?.contains("Editor selection:") == false)
    }

    @Test("Compose prepends the block above the user prompt")
    func composePrepends() {
        let context = GemmaSidecarTabContext(
            kind: .file,
            title: "main.swift",
            status: "10 lines",
            systemImage: "doc.text",
            filePath: "/repo/main.swift"
        )
        let composed = GemmaSidecarContextComposer.compose(prompt: "Explain this", context: context)
        #expect(composed.hasPrefix("[Atelier context]"))
        #expect(composed.hasSuffix("\n\nExplain this"))
    }
}
