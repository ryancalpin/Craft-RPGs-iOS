import Foundation

enum TurnStreamEvent: Equatable, Sendable {
    case phase(GenerationPhase)
    case step(String)
    case completed(GMMessage)
}

protocol TurnStreaming: Sendable {
    func events(for submission: PlayerSubmission)
        -> AsyncThrowingStream<TurnStreamEvent, Error>
}

struct SimulatedTurnStreaming: TurnStreaming {
    let delay: Duration

    func events(
        for submission: PlayerSubmission
    ) -> AsyncThrowingStream<TurnStreamEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(
            of: TurnStreamEvent.self,
            throwing: Error.self
        )

        let producer = Task {
            do {
                for phase in Self.orderedPhases {
                    try Task.checkCancellation()
                    if delay != .zero {
                        try await Task<Never, Never>.sleep(for: delay)
                    }
                    continuation.yield(.phase(phase))
                    continuation.yield(.step(Self.sanitizedStep(for: phase)))
                }

                try Task.checkCancellation()
                continuation.yield(
                    .completed(GMMessage.fixture(id: UUID()))
                )
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { @Sendable _ in
            producer.cancel()
        }

        return stream
    }

    private static let orderedPhases: [GenerationPhase] = [
        .readingWorld,
        .planning,
        .updatingWorld,
        .writingScene,
        .voicing
    ]

    private static func sanitizedStep(
        for phase: GenerationPhase
    ) -> String {
        switch phase {
        case .readingWorld:
            "Loaded the latest campaign state."
        case .planning:
            "Prepared the next scene outline."
        case .updatingWorld:
            "Applied the player action to the world state."
        case .writingScene:
            "Drafted the next story beat."
        case .voicing:
            "Prepared dialogue and narration."
        case .queued, .ready, .needsAttention:
            "Updated the generation status."
        }
    }
}
