import Foundation
import HighlightSwift

actor SyntaxHighlightService {
    private let highlighter = Highlight()

    func highlight(
        _ text: String,
        languageName: String?,
        usesDarkAppearance: Bool
    ) async throws -> AttributedString {
        let mode: HighlightMode
        if let languageName, let language = HighlightLanguage(rawValue: languageName) {
            mode = .language(language)
        } else {
            mode = .automatic
        }
        return try await highlighter.request(
            text,
            mode: mode,
            colors: usesDarkAppearance ? .dark(.xcode) : .light(.xcode)
        ).attributedText
    }
}
