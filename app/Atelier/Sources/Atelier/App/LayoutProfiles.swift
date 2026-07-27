import CoreGraphics
import Foundation
import Observation

nonisolated enum LayoutProfileID: String, CaseIterable, Codable, Identifiable, Sendable {
    case laptop
    case desktop

    var id: Self { self }

    var title: String {
        switch self {
        case .laptop: "Laptop"
        case .desktop: "Desktop"
        }
    }
}

nonisolated enum LayoutProfileFocusMode: String, Codable, Sendable {
    case off
    case manual
    case automatic

    var isFocused: Bool { self != .off }
}

nonisolated struct LayoutProfileZoomState: Codable, Equatable, Sendable {
    var sizingMode: DisplaySizingMode
    var manualScale: CGFloat
    var focusMode: LayoutProfileFocusMode
}

nonisolated struct LayoutProfilePanelState: Codable, Equatable, Sendable {
    var showsSidebar: Bool
    var showsInspector: Bool
    var restoresSidebarAfterInspector: Bool
    var selectedSidebarTab: WorkspaceSidebarTab

    func presentation(for layout: WorkspaceLayoutMode) -> WorkspacePanelPresentation {
        guard layout != .compact else { return .initial(for: .compact) }
        if layout == .standard, showsSidebar, showsInspector {
            return WorkspacePanelPresentation(
                showsSidebar: false,
                showsInspector: true,
                restoresSidebarAfterInspector: true
            )
        }
        return WorkspacePanelPresentation(
            showsSidebar: showsSidebar,
            showsInspector: showsInspector,
            restoresSidebarAfterInspector: restoresSidebarAfterInspector
        )
    }
}

nonisolated struct LayoutProfileSnapshot: Codable, Equatable, Sendable {
    var windowWidth: CGFloat
    var windowHeight: CGFloat
    var zoom: LayoutProfileZoomState
    var sidebarWidth: CGFloat
    var inspectorWidth: CGFloat
    var panels: LayoutProfilePanelState

    var windowContentSize: CGSize {
        CGSize(width: windowWidth, height: windowHeight)
    }

    func normalized() -> LayoutProfileSnapshot {
        LayoutProfileSnapshot(
            windowWidth: windowWidth.rounded(),
            windowHeight: windowHeight.rounded(),
            zoom: LayoutProfileZoomState(
                sizingMode: zoom.sizingMode,
                manualScale: (zoom.manualScale * 100).rounded() / 100,
                focusMode: zoom.focusMode
            ),
            sidebarWidth: sidebarWidth.rounded(),
            inspectorWidth: inspectorWidth.rounded(),
            panels: panels
        )
    }

    @MainActor
    static func initial(for id: LayoutProfileID) -> LayoutProfileSnapshot {
        switch id {
        case .laptop:
            LayoutProfileSnapshot(
                windowWidth: 1_200,
                windowHeight: 800,
                zoom: LayoutProfileZoomState(
                    sizingMode: .compact,
                    manualScale: 1,
                    focusMode: .off
                ),
                sidebarWidth: 320,
                inspectorWidth: AtelierMetrics.inspectorIdealWidth,
                panels: LayoutProfilePanelState(
                    showsSidebar: true,
                    showsInspector: false,
                    restoresSidebarAfterInspector: true,
                    selectedSidebarTab: .explorer
                )
            )
        case .desktop:
            LayoutProfileSnapshot(
                windowWidth: 1_720,
                windowHeight: 1_000,
                zoom: LayoutProfileZoomState(
                    sizingMode: .large,
                    manualScale: 1,
                    focusMode: .off
                ),
                sidebarWidth: AtelierMetrics.workspaceSidebarIdealWidth,
                inspectorWidth: AtelierMetrics.inspectorIdealWidth,
                panels: LayoutProfilePanelState(
                    showsSidebar: true,
                    showsInspector: true,
                    restoresSidebarAfterInspector: true,
                    selectedSidebarTab: .explorer
                )
            )
        }
    }
}

nonisolated struct LayoutProfile: Codable, Equatable, Identifiable, Sendable {
    let id: LayoutProfileID
    var snapshot: LayoutProfileSnapshot

    var title: String { id.title }

    @MainActor
    static func initial(for id: LayoutProfileID) -> LayoutProfile {
        LayoutProfile(id: id, snapshot: .initial(for: id))
    }
}

private nonisolated struct LayoutProfilePayload: Codable, Sendable {
    let version: Int
    let profiles: [LayoutProfile]
}

@MainActor
@Observable
final class LayoutProfileStore {
    static let profilesKey = "atelier.layoutProfiles.v1"
    static let selectedProfileKey = "atelier.selectedLayoutProfile.v1"

    private(set) var profiles: [LayoutProfile]
    private(set) var selectedID: LayoutProfileID
    private(set) var isApplying = false

    @ObservationIgnored private let defaults: UserDefaults?

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        profiles = Self.loadProfiles(from: defaults)
        selectedID = defaults?
            .string(forKey: Self.selectedProfileKey)
            .flatMap(LayoutProfileID.init(rawValue:)) ?? .laptop
    }

    var selectedProfile: LayoutProfile {
        profile(for: selectedID)
    }

    func profile(for id: LayoutProfileID) -> LayoutProfile {
        profiles.first(where: { $0.id == id }) ?? .initial(for: id)
    }

    func select(_ id: LayoutProfileID) {
        guard selectedID != id else { return }
        selectedID = id
        defaults?.set(id.rawValue, forKey: Self.selectedProfileKey)
    }

    func save(_ snapshot: LayoutProfileSnapshot, to id: LayoutProfileID) {
        let profile = LayoutProfile(id: id, snapshot: snapshot.normalized())
        if let index = profiles.firstIndex(where: { $0.id == id }) {
            guard profiles[index] != profile || selectedID != id else { return }
            profiles[index] = profile
        } else {
            profiles.append(profile)
            profiles.sort { $0.id.rawValue < $1.id.rawValue }
        }
        select(id)
        persistProfiles()
    }

    func isSelectedProfileModified(by snapshot: LayoutProfileSnapshot) -> Bool {
        selectedProfile.snapshot.normalized() != snapshot.normalized()
    }

    func beginApplying() {
        if !isApplying { isApplying = true }
    }

    func endApplying() {
        if isApplying { isApplying = false }
    }

    private static func loadProfiles(from defaults: UserDefaults?) -> [LayoutProfile] {
        guard let data = defaults?.data(forKey: profilesKey),
              let payload = try? JSONDecoder().decode(LayoutProfilePayload.self, from: data),
              payload.version == 1 else {
            return LayoutProfileID.allCases.map(LayoutProfile.initial)
        }

        return LayoutProfileID.allCases.map { id in
            payload.profiles.first(where: { $0.id == id }) ?? .initial(for: id)
        }
    }

    private func persistProfiles() {
        let payload = LayoutProfilePayload(version: 1, profiles: profiles)
        guard let data = try? JSONEncoder().encode(payload) else {
            AppLogger.app.error("Layout profile encoding failed")
            return
        }
        defaults?.set(data, forKey: Self.profilesKey)
    }
}

nonisolated enum LayoutProfileWindowPolicy {
    static func targetFrame(
        currentFrame: CGRect,
        currentContentSize: CGSize,
        requestedContentSize: CGSize,
        minimumContentSize: CGSize,
        visibleFrame: CGRect
    ) -> CGRect {
        let chromeWidth = max(0, currentFrame.width - currentContentSize.width)
        let chromeHeight = max(0, currentFrame.height - currentContentSize.height)
        let maximumContentWidth = max(0, visibleFrame.width - chromeWidth)
        let maximumContentHeight = max(0, visibleFrame.height - chromeHeight)
        let minimumWidth = min(minimumContentSize.width, maximumContentWidth)
        let minimumHeight = min(minimumContentSize.height, maximumContentHeight)
        let contentWidth = min(
            max(requestedContentSize.width, minimumWidth),
            maximumContentWidth
        )
        let contentHeight = min(
            max(requestedContentSize.height, minimumHeight),
            maximumContentHeight
        )
        let targetSize = CGSize(
            width: contentWidth + chromeWidth,
            height: contentHeight + chromeHeight
        )
        let preferredOrigin = CGPoint(
            x: currentFrame.minX,
            y: currentFrame.maxY - targetSize.height
        )
        let maximumX = visibleFrame.maxX - targetSize.width
        let maximumY = visibleFrame.maxY - targetSize.height
        let targetOrigin = CGPoint(
            x: min(max(preferredOrigin.x, visibleFrame.minX), maximumX),
            y: min(max(preferredOrigin.y, visibleFrame.minY), maximumY)
        )
        return CGRect(origin: targetOrigin, size: targetSize)
    }
}
