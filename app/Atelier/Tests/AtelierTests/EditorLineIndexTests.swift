import AppKit
import Foundation
import Testing
@testable import Atelier

@Suite("Editor line index")
struct EditorLineIndexTests {
    // The incremental result must equal a full rebuild of the edited text.
    private func expectIncrementalMatchesRebuild(
        original: String,
        range: NSRange,
        replacement: String
    ) {
        var index = EditorLineIndex(text: original)
        let edited = (original as NSString).replacingCharacters(in: range, with: replacement)
        let applied = index.applyEdit(range: range, replacement: replacement)
        #expect(applied)
        #expect(index == EditorLineIndex(text: edited))
    }

    @Test("Full build covers empty, plain, and trailing-newline documents")
    func fullBuild() {
        #expect(EditorLineIndex(text: "").lineStartOffsets == [0])
        #expect(EditorLineIndex(text: "").utf16Length == 0)
        #expect(EditorLineIndex(text: "abc").lineStartOffsets == [0])
        #expect(EditorLineIndex(text: "a\nb\nc").lineStartOffsets == [0, 2, 4])
        #expect(EditorLineIndex(text: "a\n").lineStartOffsets == [0, 2])
        #expect(EditorLineIndex(text: "\n\n").lineStartOffsets == [0, 1, 2])
    }

    @Test("Incremental edits at start, middle, and end")
    func incrementalEdits() {
        expectIncrementalMatchesRebuild(
            original: "a\nb\nc", range: NSRange(location: 0, length: 0), replacement: "x\n"
        )
        expectIncrementalMatchesRebuild(
            original: "a\nb\nc", range: NSRange(location: 2, length: 0), replacement: "mid"
        )
        expectIncrementalMatchesRebuild(
            original: "a\nb\nc", range: NSRange(location: 5, length: 0), replacement: "\n"
        )
        expectIncrementalMatchesRebuild(
            original: "a\nb\nc", range: NSRange(location: 1, length: 2), replacement: ""
        )
        expectIncrementalMatchesRebuild(
            original: "ab\ncd\nef", range: NSRange(location: 1, length: 5), replacement: "X\nY\nZ"
        )
        expectIncrementalMatchesRebuild(
            original: "a\nb\nc", range: NSRange(location: 0, length: 5), replacement: ""
        )
        expectIncrementalMatchesRebuild(
            original: "", range: NSRange(location: 0, length: 0), replacement: "a"
        )
        expectIncrementalMatchesRebuild(
            original: "a\n", range: NSRange(location: 2, length: 0), replacement: "b"
        )
    }

    @Test("Incremental edits with multi-scalar characters")
    func unicodeEdits() {
        let original = "😀a\n🇻🇳b\nc"
        let insertAt = (original as NSString).range(of: "b").location
        expectIncrementalMatchesRebuild(
            original: original,
            range: NSRange(location: insertAt, length: 0),
            replacement: "🎉\n"
        )
        expectIncrementalMatchesRebuild(
            original: original,
            range: (original as NSString).range(of: "🇻🇳"),
            replacement: "x\ny"
        )
        expectIncrementalMatchesRebuild(
            original: original,
            range: NSRange(location: 0, length: 2),
            replacement: ""
        )
    }

    @Test("Sequential single-character edits stay consistent")
    func sequentialTyping() {
        var index = EditorLineIndex(text: "")
        var text = ""
        var location = 0
        for character in ["h", "i", "\n", "t", "\n", "\n", "x"] {
            let range = NSRange(location: location, length: 0)
            let applied = index.applyEdit(range: range, replacement: character)
            #expect(applied)
            text = (text as NSString).replacingCharacters(in: range, with: character)
            location += (character as NSString).length
            #expect(index == EditorLineIndex(text: text))
        }
        #expect(index.lineCount == 4)
    }

    @Test("Out-of-bounds edit is rejected without mutating the index")
    func rejectsInvalidRange() {
        var index = EditorLineIndex(text: "abc")
        let applied = index.applyEdit(range: NSRange(location: 2, length: 5), replacement: "x")
        #expect(!applied)
        #expect(index.lineStartOffsets == [0])
        #expect(index.utf16Length == 3)
    }

    @Test("Line range matches the selection reference policy")
    func lineRangeParity() {
        let text = "first\nsecond\nthird\n"
        let index = EditorLineIndex(text: text)
        let selections = [
            NSRange(location: 0, length: 0),
            NSRange(location: 0, length: 5),
            NSRange(location: 3, length: 10),
            NSRange(location: 6, length: 6),
            NSRange(location: 13, length: 5),
            NSRange(location: 18, length: 1),
            NSRange(location: 40, length: 2),
            NSRange(location: NSNotFound, length: 2)
        ]
        for selection in selections {
            #expect(
                index.lineRange(for: selection)
                    == EditorSelectionReferencePolicy.lineRange(in: text, selection: selection)
            )
        }
    }
}

@Suite("Native editor autosave")
struct NativeEditorAutosaveTests {
    @Test("stop() flushes a pending debounced save")
    func stopFlushesPendingSave() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("draft.txt")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)

        let scrollView = NSScrollView()
        let textView = NSTextView()
        scrollView.documentView = textView
        let controller = FileViewer.NativeEditorController()
        controller.attach(scrollView: scrollView, textView: textView)
        controller.open(EditorDocument(url: fileURL))

        textView.string = "edited within debounce"
        controller.textDidChange(
            Notification(name: NSText.didChangeNotification, object: textView)
        )
        // stop() arrives before the 350 ms debounce fires; the pending edit
        // must still reach disk.
        controller.stop()

        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "edited within debounce")
    }
}
