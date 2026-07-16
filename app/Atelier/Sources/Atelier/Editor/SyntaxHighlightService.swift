import Foundation
import HighlightSwift

actor SyntaxHighlightService {
    private let highlighter = Highlight()

    func highlight(_ text: String, languageName: String?) async throws -> AttributedString {
        let mode: HighlightMode
        if let languageName, let language = HighlightLanguage(rawValue: languageName) {
            mode = .language(language)
        } else {
            mode = .automatic
        }
        return try await highlighter.request(
            text,
            mode: mode,
            colors: .light(.xcode)
        ).attributedText
    }
}
