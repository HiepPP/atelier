import AppKit
import Testing
@testable import Atelier

@Suite("Material file icon theme")
struct MaterialFileIconThemeTests {
    private func resolver() throws -> MaterialFileIconThemeResolver {
        try #require(MaterialFileIconThemeResolver.bundled())
    }

    @Test("Exact file names beat compound and simple extensions")
    func fileMatchingPrecedence() throws {
        let resolver = try resolver()

        #expect(
            resolver.fileDescriptor(forPath: "Sources/package.json").darkResourcePath
                == "icons/nodejs.svg"
        )
        #expect(
            resolver.fileDescriptor(forPath: "Sources/example.d.ts").darkResourcePath
                == "icons/typescript-def.svg"
        )
        #expect(
            resolver.fileDescriptor(forPath: "Sources/example.ts").darkResourcePath
                == "icons/typescript.svg"
        )
    }

    @Test("Parent path associations beat base-name associations")
    func parentPathMatching() throws {
        let resolver = try resolver()

        #expect(
            resolver.fileDescriptor(
                forPath: "/workspace/.github/labeler.yml"
            ).darkResourcePath == "icons/label.svg"
        )
    }

    @Test("Folder names resolve closed and expanded icons")
    func folderMatching() throws {
        let descriptors = try resolver().folderDescriptors(forPath: "Sources")

        #expect(descriptors.closed.darkResourcePath == "icons/folder-src.svg")
        #expect(descriptors.expanded.darkResourcePath == "icons/folder-src-open.svg")
    }

    @Test("Unknown files use the default icon")
    func fallbackMatching() throws {
        #expect(
            try resolver().fileDescriptor(forPath: "unknown.atelier-no-icon").darkResourcePath
                == "icons/file.svg"
        )
    }

    @Test("Rasterized icons fill their display frame")
    @MainActor
    func rasterizedIconCoverage() throws {
        let image = MaterialFileIconStore.shared.prewarmFile(path: "Example.swift")
        var proposedRect = NSRect(x: 0, y: 0, width: 16, height: 16)
        let cgImage = try #require(
            image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        )
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        var minimumX = bitmap.pixelsWide
        var maximumX = -1
        var minimumY = bitmap.pixelsHigh
        var maximumY = -1

        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0 > 0.05 else { continue }
                minimumX = min(minimumX, x)
                maximumX = max(maximumX, x)
                minimumY = min(minimumY, y)
                maximumY = max(maximumY, y)
            }
        }

        #expect(maximumX - minimumX + 1 >= bitmap.pixelsWide / 2)
        #expect(maximumY - minimumY + 1 >= bitmap.pixelsHigh / 2)
    }
}
