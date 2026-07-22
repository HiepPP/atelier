import AppKit
import Foundation

nonisolated struct MaterialFileIconDescriptor: Hashable, Sendable {
    let darkResourcePath: String
    let lightResourcePath: String
}

nonisolated struct MaterialFolderIconDescriptors: Equatable, Sendable {
    let closed: MaterialFileIconDescriptor
    let expanded: MaterialFileIconDescriptor
}

nonisolated struct MaterialFileIconThemeResolver: Sendable {
    private struct Manifest: Decodable {
        struct IconDefinition: Decodable {
            let iconPath: String
        }

        struct AppearanceOverrides: Decodable {
            let fileExtensions: [String: String]?
            let fileNames: [String: String]?
            let folderNames: [String: String]?
            let folderNamesExpanded: [String: String]?
        }

        let iconDefinitions: [String: IconDefinition]
        let fileExtensions: [String: String]
        let fileNames: [String: String]
        let folderNames: [String: String]
        let folderNamesExpanded: [String: String]
        let light: AppearanceOverrides?
        let file: String
        let folder: String
        let folderExpanded: String
    }

    private let iconResourcePaths: [String: String]
    private let fileExtensions: [String: String]
    private let fileNames: [String: String]
    private let folderNames: [String: String]
    private let folderNamesExpanded: [String: String]
    private let lightFileExtensions: [String: String]
    private let lightFileNames: [String: String]
    private let lightFolderNames: [String: String]
    private let lightFolderNamesExpanded: [String: String]
    private let defaultFileIcon: String
    private let defaultFolderIcon: String
    private let defaultExpandedFolderIcon: String

    init?(data: Data) {
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
            return nil
        }
        iconResourcePaths = manifest.iconDefinitions.reduce(into: [:]) { result, entry in
            guard let range = entry.value.iconPath.range(of: "icons/", options: .backwards) else {
                return
            }
            result[entry.key] = String(entry.value.iconPath[range.lowerBound...])
        }
        fileExtensions = Self.normalized(manifest.fileExtensions)
        fileNames = Self.normalized(manifest.fileNames)
        folderNames = Self.normalized(manifest.folderNames)
        folderNamesExpanded = Self.normalized(manifest.folderNamesExpanded)
        lightFileExtensions = fileExtensions.merging(
            Self.normalized(manifest.light?.fileExtensions ?? [:])
        ) { _, light in light }
        lightFileNames = fileNames.merging(
            Self.normalized(manifest.light?.fileNames ?? [:])
        ) { _, light in light }
        lightFolderNames = folderNames.merging(
            Self.normalized(manifest.light?.folderNames ?? [:])
        ) { _, light in light }
        lightFolderNamesExpanded = folderNamesExpanded.merging(
            Self.normalized(manifest.light?.folderNamesExpanded ?? [:])
        ) { _, light in light }
        defaultFileIcon = manifest.file
        defaultFolderIcon = manifest.folder
        defaultExpandedFolderIcon = manifest.folderExpanded
    }

    @MainActor
    static func bundled() -> MaterialFileIconThemeResolver? {
        guard let url = Bundle.module.url(
            forResource: "material-icons",
            withExtension: "json",
            subdirectory: "MaterialIconTheme"
        ), let data = try? Data(contentsOf: url) else {
            return nil
        }
        return MaterialFileIconThemeResolver(data: data)
    }

    func fileDescriptor(forPath path: String) -> MaterialFileIconDescriptor {
        let keys = Self.pathKeys(path)
        let darkIcon = Self.fileIcon(
            keys: keys,
            fileNames: fileNames,
            fileExtensions: fileExtensions
        ) ?? defaultFileIcon
        let lightIcon = Self.fileIcon(
            keys: keys,
            fileNames: lightFileNames,
            fileExtensions: lightFileExtensions
        ) ?? defaultFileIcon
        return descriptor(darkIcon: darkIcon, lightIcon: lightIcon)
    }

    func folderDescriptors(forPath path: String) -> MaterialFolderIconDescriptors {
        let keys = Self.pathKeys(path)
        let darkClosed = Self.namedIcon(keys: keys, associations: folderNames)
            ?? defaultFolderIcon
        let darkExpanded = Self.namedIcon(keys: keys, associations: folderNamesExpanded)
            ?? defaultExpandedFolderIcon
        let lightClosed = Self.namedIcon(keys: keys, associations: lightFolderNames)
            ?? defaultFolderIcon
        let lightExpanded = Self.namedIcon(keys: keys, associations: lightFolderNamesExpanded)
            ?? defaultExpandedFolderIcon
        return MaterialFolderIconDescriptors(
            closed: descriptor(
                darkIcon: darkClosed,
                lightIcon: lightClosed,
                fallbackIcon: defaultFolderIcon
            ),
            expanded: descriptor(
                darkIcon: darkExpanded,
                lightIcon: lightExpanded,
                fallbackIcon: defaultExpandedFolderIcon
            )
        )
    }

    private func descriptor(
        darkIcon: String,
        lightIcon: String,
        fallbackIcon: String? = nil
    ) -> MaterialFileIconDescriptor {
        let fallback = iconResourcePaths[fallbackIcon ?? defaultFileIcon] ?? "icons/file.svg"
        return MaterialFileIconDescriptor(
            darkResourcePath: iconResourcePaths[darkIcon] ?? fallback,
            lightResourcePath: iconResourcePaths[lightIcon] ?? iconResourcePaths[darkIcon] ?? fallback
        )
    }

    private static func fileIcon(
        keys: PathKeys,
        fileNames: [String: String],
        fileExtensions: [String: String]
    ) -> String? {
        if let icon = namedIcon(keys: keys, associations: fileNames) {
            return icon
        }
        for fileExtension in keys.extensions {
            for parent in keys.parents {
                if let icon = fileExtensions["\(parent)/\(fileExtension)"] {
                    return icon
                }
            }
            if let icon = fileExtensions[fileExtension] {
                return icon
            }
        }
        return nil
    }

    private static func namedIcon(
        keys: PathKeys,
        associations: [String: String]
    ) -> String? {
        for parent in keys.parents {
            if let icon = associations["\(parent)/\(keys.name)"] {
                return icon
            }
        }
        return associations[keys.name]
    }

    private static func pathKeys(_ path: String) -> PathKeys {
        let components = path
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
        let name = components.last.map(String.init)?.lowercased() ?? ""
        let parentComponents = components.dropLast().map { $0.lowercased() }
        let parents = parentComponents.indices.map { index in
            parentComponents[index...].joined(separator: "/")
        }
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        let extensions: [String]
        if parts.count > 1 {
            extensions = (1..<parts.count).map { index in
                parts[index...].joined(separator: ".")
            }
        } else {
            extensions = []
        }
        return PathKeys(name: name, parents: parents, extensions: extensions)
    }

    private static func normalized(_ source: [String: String]) -> [String: String] {
        source.reduce(into: [:]) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }
    }

    private struct PathKeys: Sendable {
        let name: String
        let parents: [String]
        let extensions: [String]
    }
}

@MainActor
struct MaterialFolderImages {
    let closed: NSImage
    let expanded: NSImage
}

@MainActor
final class MaterialFileIconStore {
    static let shared = MaterialFileIconStore()

    private static let appearanceNames: [NSAppearance.Name] = [.aqua, .darkAqua]
    private static let maximumPathCacheCount = 16_384

    private let resolver: MaterialFileIconThemeResolver?
    private let resourceRootURL: URL?
    private let fallbackFileImage: NSImage
    private let fallbackFolderImages: MaterialFolderImages
    private var imagesByDescriptor: [MaterialFileIconDescriptor: NSImage] = [:]
    private var fileImagesByPath: [String: NSImage] = [:]
    private var folderImagesByPath: [String: MaterialFolderImages] = [:]

    private init() {
        let resolver = MaterialFileIconThemeResolver.bundled()
        let resourceRootURL = Bundle.module.resourceURL?.appendingPathComponent(
            "MaterialIconTheme",
            isDirectory: true
        )
        self.resolver = resolver
        self.resourceRootURL = resourceRootURL

        let fallbackFileDescriptor = resolver?.fileDescriptor(forPath: "file")
        let fallbackFolderDescriptors = resolver?.folderDescriptors(forPath: "folder")
        let fileImage = fallbackFileDescriptor.flatMap {
            Self.loadImage(for: $0, resourceRootURL: resourceRootURL)
        } ?? Self.systemImage(named: "doc")
        let closedFolderImage = fallbackFolderDescriptors.flatMap {
            Self.loadImage(for: $0.closed, resourceRootURL: resourceRootURL)
        } ?? Self.systemImage(named: "folder")
        let expandedFolderImage = fallbackFolderDescriptors.flatMap {
            Self.loadImage(for: $0.expanded, resourceRootURL: resourceRootURL)
        } ?? closedFolderImage
        fallbackFileImage = fileImage
        fallbackFolderImages = MaterialFolderImages(
            closed: closedFolderImage,
            expanded: expandedFolderImage
        )
        if let fallbackFileDescriptor {
            imagesByDescriptor[fallbackFileDescriptor] = fileImage
        }
        if let fallbackFolderDescriptors {
            imagesByDescriptor[fallbackFolderDescriptors.closed] = closedFolderImage
            imagesByDescriptor[fallbackFolderDescriptors.expanded] = expandedFolderImage
        }
    }

    @discardableResult
    func prewarmFile(path: String) -> NSImage {
        if let cached = fileImagesByPath[path] { return cached }
        trimPathCachesIfNeeded(adding: 1)
        guard let resolver else {
            fileImagesByPath[path] = fallbackFileImage
            return fallbackFileImage
        }
        let image = image(for: resolver.fileDescriptor(forPath: path), fallback: fallbackFileImage)
        fileImagesByPath[path] = image
        return image
    }

    @discardableResult
    func prewarmFolder(path: String) -> MaterialFolderImages {
        if let cached = folderImagesByPath[path] { return cached }
        trimPathCachesIfNeeded(adding: 1)
        guard let resolver else {
            folderImagesByPath[path] = fallbackFolderImages
            return fallbackFolderImages
        }
        let descriptors = resolver.folderDescriptors(forPath: path)
        let images = MaterialFolderImages(
            closed: image(for: descriptors.closed, fallback: fallbackFolderImages.closed),
            expanded: image(for: descriptors.expanded, fallback: fallbackFolderImages.expanded)
        )
        folderImagesByPath[path] = images
        return images
    }

    func prewarmGitPaths(_ paths: [String]) {
        trimPathCachesIfNeeded(adding: paths.count * 2)
        for path in paths {
            if path.hasSuffix("/") {
                prewarmFolder(path: path)
            } else {
                prewarmFile(path: path)
            }
            let components = path.split(separator: "/", omittingEmptySubsequences: true)
            guard components.count > 1 else { continue }
            for endIndex in 1..<components.count {
                prewarmFolder(path: components[..<endIndex].joined(separator: "/"))
            }
        }
    }

    func cachedFileImage(forPath path: String) -> NSImage {
        fileImagesByPath[path] ?? fallbackFileImage
    }

    func cachedFolderImage(forPath path: String, isExpanded: Bool) -> NSImage {
        let images = folderImagesByPath[path] ?? fallbackFolderImages
        return isExpanded ? images.expanded : images.closed
    }

    private func image(for descriptor: MaterialFileIconDescriptor, fallback: NSImage) -> NSImage {
        if let cached = imagesByDescriptor[descriptor] { return cached }
        let image = Self.loadImage(for: descriptor, resourceRootURL: resourceRootURL) ?? fallback
        imagesByDescriptor[descriptor] = image
        return image
    }

    private func trimPathCachesIfNeeded(adding count: Int) {
        guard fileImagesByPath.count + folderImagesByPath.count + count
            > Self.maximumPathCacheCount else { return }
        fileImagesByPath.removeAll(keepingCapacity: true)
        folderImagesByPath.removeAll(keepingCapacity: true)
    }

    private static func loadImage(
        for descriptor: MaterialFileIconDescriptor,
        resourceRootURL: URL?
    ) -> NSImage? {
        guard let resourceRootURL,
              let darkImage = rasterizedImage(
                  at: resourceRootURL.appendingPathComponent(descriptor.darkResourcePath)
              ) else {
            return nil
        }
        guard descriptor.lightResourcePath != descriptor.darkResourcePath,
              let lightImage = rasterizedImage(
                  at: resourceRootURL.appendingPathComponent(descriptor.lightResourcePath)
              ) else {
            return darkImage
        }
        let size = darkImage.size
        return NSImage(size: size, flipped: false) { rect in
            let appearance = NSAppearance.currentDrawing()
            let image = appearance.bestMatch(from: Self.appearanceNames) == .darkAqua
                ? darkImage
                : lightImage
            image.draw(
                in: rect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
            return true
        }
    }

    private static func rasterizedImage(at url: URL) -> NSImage? {
        guard let source = NSImage(contentsOf: url) else { return nil }
        let logicalSize = source.size
        let pixelSize = 96
        guard logicalSize.width > 0,
              logicalSize.height > 0,
              let representation = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: pixelSize,
                  pixelsHigh: pixelSize,
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .deviceRGB,
                  bitmapFormat: [],
                  bytesPerRow: 0,
                  bitsPerPixel: 0
              ),
              let context = NSGraphicsContext(bitmapImageRep: representation) else {
            return nil
        }
        representation.size = logicalSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        source.draw(
            in: NSRect(
                x: 0,
                y: 0,
                width: pixelSize,
                height: pixelSize
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: logicalSize)
        image.addRepresentation(representation)
        return image
    }

    private static func systemImage(named name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: 16, height: 16))
    }
}
