import Foundation
import Testing
@testable import RPGPlayer

struct ModelRoutingTests {
    @Test
    func routingPreferencesPersistAcrossStoreInstances() async throws {
        let suiteName = "model-routing-(UUID().uuidString)"
        let store = UserDefaultsModelRoutingStore(suiteName: suiteName)
        let settings = ModelRoutingSettings(
            primary: TextModelSelection(
                providerID: .anthropic,
                modelID: "claude-custom"
            ),
            fallback: TextModelSelection(
                providerID: .openRouter,
                modelID: "provider/fallback"
            ),
            automaticFallbackEnabled: false
        )

        try await store.save(settings)

        let reloaded = try await UserDefaultsModelRoutingStore(
            suiteName: suiteName
        ).load()

        #expect(reloaded == settings)
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(
            forName: suiteName
        )
    }

    @Test
    func defaultRoutingUsesACompatibleCuratedPrimaryAndFallback() async throws {
        let settings = ModelRoutingSettings.default

        #expect(settings.primary.providerID == .openAI)
        #expect(settings.primary.modelID.isEmpty == false)
        #expect(settings.fallback?.providerID == .anthropic)

        let primary = try #require(
            CuratedProviderModelCatalog.models(
                for: settings.primary.providerID
            ).first(where: { $0.id == settings.primary.modelID })
        )
        #expect(primary.supportsTools)
        #expect(primary.supportsStructuredOutput)
    }

    @Test
    func routeValidationRejectsModelsThatCannotRunTheGMContract() throws {
        let route = TextModelSelection(
            providerID: .openAI,
            modelID: "plain-text-only"
        )
        let model = try ProviderModel(
            providerID: .openAI,
            id: route.modelID,
            displayName: "Plain text only",
            contextWindowTokens: 8_000,
            maximumOutputTokens: 1_000,
            supportsTools: false,
            supportsStructuredOutput: true
        )

        #expect(
            throws: ModelRoutingError.incompatibleModel(
                providerID: .openAI,
                modelID: route.modelID
            )
        ) {
            try ModelRouteValidator.validateGMModel(model)
        }
    }

    @Test
    func selectedModelRoundTripsInTurnRequest() throws {
        let request = TurnRequest(
            requestID: UUID(),
            campaignID: UUID(),
            expectedSequence: 0,
            action: PlayerAction(text: "Look around."),
            context: TurnContext(
                contextHash: try ContextHash(
                    rawValue: String(repeating: "a", count: 64)
                ),
                sections: []
            ),
            modelID: "gpt-selected"
        )

        let decoded = try JSONDecoder().decode(
            TurnRequest.self,
            from: JSONEncoder().encode(request)
        )

        #expect(decoded == request)
        #expect(decoded.modelID == "gpt-selected")
    }

    @Test
    func modelCatalogFallsBackToCuratedModelsWhenDiscoveryFails() async throws {
        let service = ProviderModelCatalogService(
            providers: [
                .openAI: FailingModelProvider(id: .openAI)
            ]
        )

        let models = await service.models(for: .openAI)

        #expect(models == CuratedProviderModelCatalog.models(for: .openAI))
    }
}

private struct FailingModelProvider: AIProvider {
    let id: ProviderID

    func models() async throws -> [ProviderModel] {
        throw ProviderError.connectivity
    }

    func streamTurn(
        _ request: TurnRequest
    ) async throws -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        throw ProviderError.connectivity
    }

    func cancel(requestID: UUID) async {}
}
