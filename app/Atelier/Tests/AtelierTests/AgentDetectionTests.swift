import Testing
@testable import Atelier

@Suite("Agent detection")
struct AgentDetectionTests {
    @Test("Known agent executable names match")
    func knownAgentsMatch() {
        #expect(AgentDetectionPolicy.agentName(in: ["claude"]) == "claude")
        #expect(
            AgentDetectionPolicy.agentName(in: ["node", "/x/claude", "run"])
                == "claude"
        )
    }

    @Test("Shell and regular commands do not match")
    func regularCommandsDoNotMatch() {
        #expect(AgentDetectionPolicy.agentName(in: ["zsh"]) == nil)
        #expect(AgentDetectionPolicy.agentName(in: ["git", "status"]) == nil)
    }
}
