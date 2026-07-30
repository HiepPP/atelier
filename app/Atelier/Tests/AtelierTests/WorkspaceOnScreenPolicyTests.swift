import Foundation
import Testing
@testable import Atelier

@Suite("Workspace on-screen policy")
struct WorkspaceOnScreenPolicyTests {
    @Test("A visible window keeps repeating work running")
    func visibleWindowIsOnScreen() {
        #expect(
            WorkspaceOnScreenPolicy.isOnScreen(
                isApplicationHidden: false,
                windows: [window(isVisible: true, isOcclusionVisible: true)]
            )
        )
    }

    @Test("A fully covered window stops repeating work")
    func occludedWindowIsOffScreen() {
        #expect(
            !WorkspaceOnScreenPolicy.isOnScreen(
                isApplicationHidden: false,
                windows: [window(isVisible: true, isOcclusionVisible: false)]
            )
        )
    }

    /// Occlusion state desyncs: AppKit can report a maximized key window the
    /// user is driving as occluded. Trusting the bit alone would stall the
    /// thread list on screen, which is the terminal freeze failure mode.
    @Test("A key window counts as on screen despite a missing visible bit")
    func keyWindowOverridesOcclusionDesync() {
        #expect(
            WorkspaceOnScreenPolicy.isOnScreen(
                isApplicationHidden: false,
                windows: [
                    window(isVisible: true, isKeyWindow: true, isOcclusionVisible: false)
                ]
            )
        )
    }

    @Test("Hiding the application stops repeating work")
    func hiddenApplicationIsOffScreen() {
        #expect(
            !WorkspaceOnScreenPolicy.isOnScreen(
                isApplicationHidden: true,
                windows: [
                    window(isVisible: true, isKeyWindow: true, isOcclusionVisible: true)
                ]
            )
        )
    }

    @Test("A minimized or closed window is not on screen")
    func invisibleWindowIsOffScreen() {
        #expect(
            !WorkspaceOnScreenPolicy.isOnScreen(
                isApplicationHidden: false,
                windows: [window(isVisible: false, isOcclusionVisible: true)]
            )
        )
    }

    @Test("No windows means nothing to poll for")
    func noWindowsIsOffScreen() {
        #expect(!WorkspaceOnScreenPolicy.isOnScreen(isApplicationHidden: false, windows: []))
    }

    @Test("One visible window is enough when others are covered")
    func anyVisibleWindowIsOnScreen() {
        #expect(
            WorkspaceOnScreenPolicy.isOnScreen(
                isApplicationHidden: false,
                windows: [
                    window(isVisible: true, isOcclusionVisible: false),
                    window(isVisible: true, isOcclusionVisible: true)
                ]
            )
        )
    }

    private func window(
        isVisible: Bool,
        isKeyWindow: Bool = false,
        isOcclusionVisible: Bool
    ) -> WorkspaceWindowVisibility {
        WorkspaceWindowVisibility(
            isVisible: isVisible,
            isKeyWindow: isKeyWindow,
            isOcclusionVisible: isOcclusionVisible
        )
    }
}
