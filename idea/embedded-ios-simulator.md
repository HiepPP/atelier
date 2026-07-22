# Embedded iOS Simulator in Atelier

Run a live, interactive iOS Simulator screen directly inside the Atelier window.
Not for App Store distribution, so private frameworks are acceptable.

## Goal

Show a running iOS app inside Atelier and interact with it (tap, swipe, type)
without a separate Simulator.app window. Target the same fidelity and latency as
Apple's own Simulator.app: GPU frame goes straight to a layer, no video codec.

## Feasibility Summary

- No public API embeds the Simulator screen into another app's view.
- Two viable paths exist without the App Store constraint.
- The native, best-performance path is CoreSimulator private framework plus IOSurface.
- Prerequisite for any path: Xcode and an iOS simulator runtime installed.

## Path Comparison

| Factor | CoreSimulator + IOSurface | idb (H264 + gRPC) |
|--------|---------------------------|-------------------|
| Frame flow | GPU to IOSurface to CALayer.contents (zero-copy) | frame to encode to socket to decode to draw |
| Codec | none | encode plus decode per frame |
| Latency | ~1 frame, lowest | plus several frames from codec buffering |
| CPU/GPU cost | near zero for display | VideoToolbox on both ends |
| Fidelity | native pixels | lossy compression |
| Native feel | exact path Apple uses internally | intermediate layer |
| Dependency | none, but private API | one external binary (idb_companion) |
| Stability | symbols shift per Xcode version | more stable across versions |
| Input injection | must send IndigoHID manually | built in (tap, swipe, text) |

## Chosen Approach

Use the private CoreSimulator plus IOSurface path. It is the native route and has
the best performance. Cost: private symbols change per Xcode version and input
must be injected manually. The idb path is the fallback if maintenance becomes
too heavy.

### How IOSurface Wins

- The simulator renders into an IOSurface, GPU-backed memory shared across processes.
- The app receives that surface handle and assigns it directly to layer.contents.
- No copy, no codec. One surface, two processes. True zero-copy.
- Display performance matches Simulator.app because it is the same mechanism.

### CoreSimulator Object Graph

- dlopen `/Library/Developer/PrivateFrameworks/CoreSimulator.framework`.
- `SimServiceContext` to `SimDeviceSet` to `SimDevice`.
- Display: `device.io` returns a `SimDeviceIOClient`; register a consumer on the IO
  port to receive an IOSurface each frame, then assign to `CALayer.contents`.
- Input: send IndigoHID messages through the same `SimDeviceIOClient`.

Note: exact method signatures are private and unverified. Dump real symbols on the
installed Xcode before writing code. There are no public headers.

## Prerequisites

- macOS with Xcode installed. Confirm with `xcodebuild -version`.
- At least one iOS simulator runtime present. Confirm with `xcrun simctl list`.
- Atelier is native macOS, Swift 6.2, SwiftUI plus AppKit bridges. Embed via
  `NSViewRepresentable` with stable identity, matching existing tab-content rules.

## Implementation Roadmap

Each step yields a visible result to keep momentum.

1. Boot a device with `xcrun simctl boot <udid>`; print udid and state.
2. Dump CoreSimulator symbols on the installed Xcode; produce a real signature map.
3. Fetch one IOSurface from the booted device; assign to a CALayer; confirm a static frame appears. This is the milestone moment.
4. Stream frames continuously for a live screen.
5. Inject one tap via IndigoHID; confirm the app responds. Interaction begins here.
6. Map mouse and keyboard from the embedded view to HID tap, swipe, and text.

## Verification

- Follow the repo SwiftUI and AppKit crash rules for the embedded surface.
- Keep the representable mounted with stable identity; do not swap it in and out on
  tab or panel changes. Toggle width, opacity, hit testing, and accessibility instead.
- After the surface is live, run the native tab switch smoke at full window size.
- Check idle CPU stays in the 0.2 to 2 percent range when the stream is idle.
- Confirm no new reports in `~/Library/Logs/DiagnosticReports/` after driving input.

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Private symbols change per Xcode | Re-dump symbols after each Xcode upgrade; a few hours, not a rewrite |
| No public headers | Build a verified signature map before coding; wrap in one isolated bridge |
| Input mapping complexity | Isolate coordinate mapping (view to device) behind a tested layer |
| Layout reentrancy crashes | Defer any layout-derived mutation off the current pass; keep pane mounted |

## Fallback Path (idb)

If private maintenance is too heavy, switch to idb.

- Install: `brew install idb-companion`.
- Boot: `xcrun simctl boot <udid>`.
- Run: `idb_companion --udid <udid> --grpc-port 10882`.
- Video: stream H264 over gRPC, decode with `VTDecompressionSession`, draw to CALayer.
- Input: gRPC hid channel provides tap, swipe, key, and text.

Trade: extra latency and CPU for stability and built-in input.

## Status

Planning only. No code written yet. Resume at roadmap step 1.
