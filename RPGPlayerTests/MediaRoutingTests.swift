import Foundation
import Testing
@testable import RPGPlayer

@Suite(.serialized)
struct MediaRoutingTests {
    @Test
    func imageRoutingFallsBackAfterRetryableFailure() async throws {
        let primary = RecordingImageProvider(
            id: .openAI,
            behavior: .failure(.quotaExceeded)
        )
        let fallback = RecordingImageProvider(
            id: .openRouter,
            behavior: .success
        )
        let router = ImageRoutingProvider(
            settings: ImageRoutingSettings(
                primary: ImageModelSelection(
                    providerID: .openAI,
                    modelID: "primary-image"
                ),
                fallback: ImageModelSelection(
                    providerID: .openRouter,
                    modelID: "fallback-image"
                )
            ),
            providers: [
                .openAI: primary,
                .openRouter: fallback
            ]
        )

        let result = try await router.generateImage(
            try ImageGenerationRequest(prompt: "A lantern in the rain")
        )

        #expect(result.providerID == .openRouter)
        #expect(result.modelID == "fallback-image")
        #expect(await primary.modelIDs == ["primary-image"])
        #expect(await fallback.modelIDs == ["fallback-image"])
    }

    @Test
    func imageRoutingDoesNotFallbackForInvalidCredentials() async throws {
        let primary = RecordingImageProvider(
            id: .openAI,
            behavior: .failure(.invalidCredential)
        )
        let fallback = RecordingImageProvider(
            id: .openRouter,
            behavior: .success
        )
        let router = ImageRoutingProvider(
            settings: ImageRoutingSettings(
                primary: ImageModelSelection(
                    providerID: .openAI,
                    modelID: "primary-image"
                ),
                fallback: ImageModelSelection(
                    providerID: .openRouter,
                    modelID: "fallback-image"
                )
            ),
            providers: [
                .openAI: primary,
                .openRouter: fallback
            ]
        )

        await #expect(throws: ProviderError.invalidCredential) {
            _ = try await router.generateImage(
                try ImageGenerationRequest(prompt: "A locked door")
            )
        }

        #expect(await fallback.modelIDs.isEmpty)
    }
}

private actor RecordingImageProvider: ImageProvider {
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

    func models() async throws -> [ImageGenerationModel] {
        []
    }

    func generateImage(
        _ request: ImageGenerationRequest
    ) async throws -> ImageGenerationResult {
        modelIDs.append(request.modelID ?? "")
        switch behavior {
        case .success:
            return ImageGenerationResult(
                providerID: id,
                modelID: request.modelID ?? "fallback-image",
                images: [ImageGenerationAsset(data: Data([1, 2, 3]))]
            )
        case .failure(let error):
            throw error
        }
    }
}
