import SwiftUI
import AppKit
import SwiftUIX

struct FileViewer: View {
    let content: FileContent

    private static let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)

    private let displayText: String
    private let contentIdentity: FileViewerContentIdentity
    private let contentSize: CGSize

    init(content: FileContent) {
        self.content = content
        displayText = content.displayText
        contentIdentity = FileViewerContentIdentity(content)
        contentSize = FileViewerMeasurementCache.size(
            for: displayText,
            identity: contentIdentity,
            font: Self.font
        )
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            TextView(displayText)
                .editable(false)
                .isSelectable(true)
                .font(Self.font)
                .foregroundColor(AtelierNativePalette.foreground)
                .textContainerInset(NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16))
                .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
        }
        .id(contentIdentity)
        .background(Color(nsColor: AtelierNativePalette.code))
        .atelierScrollChrome(backgroundColor: AtelierNativePalette.code)
    }
}

private struct FileViewerContentIdentity: Hashable {
    private let kind: Int
    private let byteCount: Int
    private let fingerprint: Int

    init(_ content: FileContent) {
        switch content {
        case .text(let text):
            kind = 0
            byteCount = text.utf8.count
            fingerprint = text.hashValue
        case .binary:
            kind = 1
            byteCount = 0
            fingerprint = 0
        case .tooLarge(let bytes):
            kind = 2
            byteCount = bytes
            fingerprint = bytes.hashValue
        case .error(let message):
            kind = 3
            byteCount = message.utf8.count
            fingerprint = message.hashValue
        }
    }

    var cacheKey: NSString {
        "\(kind):\(byteCount):\(fingerprint)" as NSString
    }
}

private final class FileViewerMeasurement: NSObject {
    let text: String
    let size: CGSize

    init(text: String, size: CGSize) {
        self.text = text
        self.size = size
    }
}

private enum FileViewerMeasurementCache {
    private static let cache: NSCache<NSString, FileViewerMeasurement> = {
        let cache = NSCache<NSString, FileViewerMeasurement>()
        cache.countLimit = 8
        return cache
    }()

    static func size(
        for text: String,
        identity: FileViewerContentIdentity,
        font: NSFont
    ) -> CGSize {
        if let cached = cache.object(forKey: identity.cacheKey), cached.text == text {
            return cached.size
        }

        let text = NSAttributedString(
            string: text,
            attributes: [.font: font]
        )
        let bounds = text.boundingRect(
            with: NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let size = NSSize(
            width: max(1, ceil(bounds.width) + 32),
            height: max(1, ceil(bounds.height) + 28)
        )
        cache.setObject(
            FileViewerMeasurement(text: text.string, size: size),
            forKey: identity.cacheKey
        )
        return size
    }
}
