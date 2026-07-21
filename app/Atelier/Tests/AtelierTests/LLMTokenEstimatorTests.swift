import Testing
@testable import Atelier

@Suite("LLM token estimator")
struct LLMTokenEstimatorTests {
    @Test("Returns zero for empty content")
    func emptyContent() {
        #expect(LLMTokenEstimator.estimate(byteCount: 0) == 0)
    }

    @Test("Rounds partial tokens upward")
    func roundsUp() {
        #expect(LLMTokenEstimator.estimate(byteCount: 1) == 1)
        #expect(LLMTokenEstimator.estimate(byteCount: 4) == 1)
        #expect(LLMTokenEstimator.estimate(byteCount: 5) == 2)
    }

    @Test("Handles loaded file size without scanning content")
    func loadedFileSize() {
        #expect(LLMTokenEstimator.estimate(byteCount: 2_000_000) == 500_000)
    }
}
