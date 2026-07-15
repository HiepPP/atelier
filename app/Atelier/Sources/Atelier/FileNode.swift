import Foundation

final class FileNode {
    let url: URL
    let isDirectory: Bool
    var children: [FileNode]?

    var name: String {
        url.lastPathComponent
    }

    init(url: URL, isDirectory: Bool) {
        self.url = url
        self.isDirectory = isDirectory
    }
}
