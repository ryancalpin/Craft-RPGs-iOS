import XCTest
@testable import RPGPlayer

final class TurnSimulationTests: XCTestCase {
    func testSimulationEndsWithExactlyOneMessage() async throws {
        let service = SimulatedTurnStreaming(delay: .zero)
        var phases: [GenerationPhase] = []
        var messages: [GMMessage] = []

        for try await event in await service.events(
            for: PlayerSubmission(action: "Wait", additionalContext: "")
        ) {
            if case .phase(let phase) = event {
                phases.append(phase)
            }
            if case .completed(let message) = event {
                messages.append(message)
            }
        }

        XCTAssertEqual(
            phases,
            [
                .readingWorld,
                .planning,
                .updatingWorld,
                .writingScene,
                .voicing
            ]
        )
        XCTAssertEqual(messages.count, 1)
    }

    func testSimulationEmitsOneSanitizedStepPerPhase() async throws {
        let service = SimulatedTurnStreaming(delay: .zero)
        let submission = PlayerSubmission(
            action: "PRIVATE_ACTION_MARKER",
            additionalContext: "PRIVATE_CONTEXT_MARKER"
        )
        var steps: [String] = []

        let events = await service.events(for: submission)
        for try await event in events {
            if case .step(let step) = event {
                steps.append(step)
            }
        }

        XCTAssertEqual(steps.count, 5)
        XCTAssertTrue(
            steps.allSatisfy {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        )
        XCTAssertFalse(steps.contains { $0.contains(submission.action) })
        XCTAssertFalse(
            steps.contains { $0.contains(submission.additionalContext) }
        )
    }
}
