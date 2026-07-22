import AppKit
import HighlightSwift

actor SyntaxHighlightService {
    private struct Key: Hashable {
        let contentHash: Int
        let byteCount: Int
        let languageName: String?
        let isDark: Bool
    }

    private let highlighter = Highlight()
    private var entries: [Key: AttributedString] = [:]
    private var order: [Key] = []
    private let maximumEntries = 16

    func highlight(
        _ text: String,
        languageName: String?,
        usesDarkAppearance: Bool
    ) async throws -> AttributedString {
        var hasher = Hasher()
        hasher.combine(text)
        let key = Key(
            contentHash: hasher.finalize(),
            byteCount: text.utf8.count,
            languageName: languageName,
            isDark: usesDarkAppearance
        )
        if let cached = value(for: key) { return cached }

        let mode: HighlightMode
        if let languageName, let language = HighlightLanguage(rawValue: languageName) {
            mode = .language(language)
        } else {
            mode = .automatic
        }
        let result = try await highlighter.request(
            text,
            mode: mode,
            colors: usesDarkAppearance ? .dark(.xcode) : .light(.xcode)
        ).attributedText
        store(result, for: key)
        return result
    }

    func highlightPreservingWhitespace(
        _ text: String,
        languageName: String?,
        usesDarkAppearance: Bool
    ) async throws -> AttributedString {
        let highlighted = try await highlight(
            text,
            languageName: languageName,
            usesDarkAppearance: usesDarkAppearance
        )
        let nativeHighlight = NSAttributedString(highlighted)
        let highlightedRange = (text as NSString).range(of: nativeHighlight.string)
        guard highlightedRange.location != NSNotFound else {
            return AttributedString(text)
        }

        let result = NSMutableAttributedString(string: text)
        nativeHighlight.enumerateAttribute(
            .foregroundColor,
            in: NSRange(location: 0, length: nativeHighlight.length)
        ) { value, range, _ in
            guard let value else { return }
            let target = NSRange(
                location: highlightedRange.location + range.location,
                length: range.length
            )
            guard NSMaxRange(target) <= result.length else { return }
            result.addAttribute(.foregroundColor, value: value, range: target)
        }
        return AttributedString(result)
    }

    private func value(for key: Key) -> AttributedString? {
        guard let value = entries[key] else { return nil }
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
            order.append(key)
        }
        return value
    }

    private func store(_ value: AttributedString, for key: Key) {
        if entries[key] == nil { order.append(key) }
        entries[key] = value
        while entries.count > maximumEntries {
            guard let oldest = order.first else { break }
            order.removeFirst()
            entries.removeValue(forKey: oldest)
        }
    }
}
