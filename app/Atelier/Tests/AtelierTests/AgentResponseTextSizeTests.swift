import Foundation
import Testing

@testable import Atelier

@Suite("Agent response text size")
struct AgentResponseTextSizeTests {
    @Test("Steps stay on a two-decimal grid")
    func stepsStayOnGrid() {
        var scale = AgentResponseTextSizePolicy.minimumScale
        for _ in 0..<3 {
            scale = AgentResponseTextSizePolicy.increased(scale)
        }
        #expect(scale == 1.1)

        for _ in 0..<3 {
            scale = AgentResponseTextSizePolicy.decreased(scale)
        }
        #expect(scale == AgentResponseTextSizePolicy.minimumScale)
    }

    @Test("The default scale is a reachable step inside the range")
    func defaultScaleIsReachable() {
        let scale = AgentResponseTextSizePolicy.defaultScale
        #expect(scale == 1.3)
        #expect(AgentResponseTextSizePolicy.clamped(scale) == scale)
        #expect(AgentResponseTextSizePolicy.canIncrease(scale))
        #expect(AgentResponseTextSizePolicy.canDecrease(scale))
    }

    @Test("Stepping stops at both bounds")
    func steppingStopsAtBounds() {
        var scale = AgentResponseTextSizePolicy.defaultScale
        for _ in 0..<20 {
            scale = AgentResponseTextSizePolicy.increased(scale)
        }
        #expect(scale == AgentResponseTextSizePolicy.maximumScale)
        #expect(!AgentResponseTextSizePolicy.canIncrease(scale))
        #expect(AgentResponseTextSizePolicy.canDecrease(scale))

        for _ in 0..<20 {
            scale = AgentResponseTextSizePolicy.decreased(scale)
        }
        #expect(scale == AgentResponseTextSizePolicy.minimumScale)
        #expect(!AgentResponseTextSizePolicy.canDecrease(scale))
        #expect(AgentResponseTextSizePolicy.canIncrease(scale))
    }

    @Test("Restored values are clamped and unusable values fall back")
    func restoredValuesAreClamped() {
        #expect(AgentResponseTextSizePolicy.clamped(4) == AgentResponseTextSizePolicy.maximumScale)
        #expect(AgentResponseTextSizePolicy.clamped(0) == AgentResponseTextSizePolicy.minimumScale)
        #expect(AgentResponseTextSizePolicy.clamped(1.15) == 1.15)
        #expect(
            AgentResponseTextSizePolicy.clamped(.nan)
                == AgentResponseTextSizePolicy.defaultScale
        )
    }
}
