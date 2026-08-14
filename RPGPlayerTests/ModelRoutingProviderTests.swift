import Foundation
import Testing
@testable import RPGPlayer

@Suite(.serialized)
struct ModelRoutingProviderTests {
    @Test
    func retryablePrimaryFailureUsesFallbackProviderAndSelectedModel() async throws {
        let primary = RecordingAIProvider(
            id: .openAI,
            behavior: .failure(.connectivity)
        )
        let fallback = RecordingAIProvider(
            id: .anthropic,
            behavior: .success
        )
        let router = ModelRoutingProvider(
            settings: ModelRoutingSettings(
                primary: TextModelSelection(
                    providerID: .openAI,
                    modelID: "primary-model"
                ),
                fallback: TextModelSelection(
                    providerID: .anthropic,
                    modelID: "fallback-model"
                )
            ),
            providers: [
                .openAI: primary,
                .anthropic: fallback
            ]
        )

        let events = try await collect(
            router.streamTurn(makeRequest())
        )

        #expect(events == [.textDelta("fallback"), .finished(.maximumOutputTokens)])
        #expect(await primary.modelIDs == ["primary-model"])
        #expect(await fallback.modelIDs == ["fallback-model"])
    }

    @Test
    func nonRetryablePrimaryFailureDoesNotSilentlySwitchProviders() async throws {
        let primary = RecordingAIProvider(
            id: .openAI,
            behavior: .failure(.invalidCredential)
        )
        let fallback = RecordingAIProvider(
            id: .anthropic,
            behavior: .success
        )
        let router = ModelRoutingProvider(
            settings: ModelRoutingSettings(
                primary: TextModelSelection(
                    providerID: .openAI,
                    modelID: "primary-model"
                ),
                fallback: TextModelSelection(
                    providerID: .anthropic,
                    modelID: "fallback-model"
                )
            ),
            providers: [
                .openAI: primary,
                .anthropic: fallback
            ]
        )

        do {
            _ = try await collect(router.streamTurn(makeRequest()))
            Issue.record("Expected invalid credentials to be surfaced")
        } catch let error as ProviderError {
            #expect(error == .invalidCredential)
        }

        #expect(await fallback.modelIDs.isEmpty)
    }

    private func makeRequest() -> TurnRequest {
        TurnRequest(
            requestID: UUID(),
            campaignID: UUID(),
            expectedSequence: 0,
            action: PlayerAction(text: "Continue."),
            context: TurnContext(
                contextHash: try! ContextHash(
                    rawValue: String(repeating: "a", count: 64)
                ),
                sections: []
            )
        )
    }

    private func collect(
        _ stream: AsyncThrowingStream<ProviderStreamEvent, Error>
    ) async throws -> [ProviderStreamEvent] {
        var events: [ProviderStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }
}

private actor RecordingAIProvider: AIProvider {
    nonisolated let id: ProviderID
    let behavior: Behavior
    private(set) var modelIDs: [String] = []

    enum Behavior: Sendable {
        case success
        case failure(ProviderError)
    }

    init(id: ProviderID, behavior: Behavior) {
        self.id = id
        self.behavior = behavior
    }

    func models() async throws -> [ProviderModel] {
        CuratedProviderModelCatalog.models(for: id)
    }

    func streamTurn(
        _ request: TurnRequest
    ) async throws -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        modelIDs.append(request.modelID ?? "")
        switch behavior {
        case .success:
            return AsyncThrowingStream<ProviderStreamEvent, Error>(
                bufferingPolicy: .unbounded
            ) { continuation in
                continuation.yield(.textDelta("fallback"))
                continuation.yield(.finished(.maximumOutputTokens))
                continuation.finish()
            }
        case .failure(let error):
            throw error
        }
    }

    func cancel(requestID: UUID) async {}
}
