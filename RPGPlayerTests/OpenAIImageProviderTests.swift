import Foundation
import Testing
@testable import RPGPlayer

@Suite(.serialized)
struct OpenAIImageProviderTests {
    @Test
    func curatedCatalogIsDeterministicAndOpenAIScoped() async throws {
        let provider = try await makeProvider()

        let first = try await provider.adapter.models()
        let second = try await provider.adapter.models()

        #expect(first == second)
        #expect(first.map(\.id) == ["gpt-image-1", "dall-e-3"])
        #expect(first.allSatisfy { $0.providerID == .openAI })
    }

    @Test
    func generationDecodesBase64AndURLAssetsAndUsesSelectedModel() async throws {
        let provider = try await makeProvider(fixture: "successful-generation.json")
        let request = try ImageGenerationRequest(
            prompt: "A moonlit bell tower",
            modelID: "dall-e-3",
            size: "1024x1024",
            quality: "hd",
            count: 2
        )

        let result = try await provider.adapter.generateImage(request)

        #expect(result.modelID == "dall-e-3")
        #expect(result.images.count == 2)
        #expect(result.images[0].data == Data([0x89, 0x50, 0x4e, 0x47]))
        #expect(result.images[0].url == nil)
        #expect(result.images[0].revisedPrompt == "A detailed moonlit bell tower")
        #expect(result.images[1].data == nil)
        #expect(result.images[1].url == URL(string: "https://cdn.example.invalid/image.png"))

        let snapshot = try #require(await provider.registration.diagnosticSnapshot())
        #expect(snapshot.method == "POST")
        #expect(snapshot.path == "/v1/images/generations")
        #expect(snapshot.headers["Authorization"] == "<redacted>")
        let body = try #require(snapshot.bodyData)
        let object = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(object["model"] as? String == "dall-e-3")
        #expect(object["prompt"] as? String == "A moonlit bell tower")
        #expect(object["size"] as? String == "1024x1024")
        #expect(object["quality"] as? String == "hd")
        #expect(object["n"] as? Int == 2)
    }

    @Test
    func generationNormalizesRateLimitAndDoesNotLeakCredential() async throws {
        let provider = try await makeProvider(
            fixture: "successful-generation.json",
            sentinel: "sk-fixture-image-secret-123456",
            response: .http(statusCode: 429)
        )

        do {
            _ = try await provider.adapter.generateImage(
                try ImageGenerationRequest(prompt: "A hidden crypt")
            )
            Issue.record("Expected image generation to fail")
        } catch let error as ProviderError {
            #expect(error == .rateLimited(retryAfter: nil))
        } catch {
            Issue.record("Wrong normalized error: \(error)")
        }

        let snapshot = try #require(await provider.registration.diagnosticSnapshot())
        #expect(snapshot.headers.values.contains { $0.contains("sk-fixture-image-secret-123456") } == false)
    }

    @Test
    func generationRejectsBlankPromptBeforeMakingARequest() async throws {
        let provider = try await makeProvider(fixture: "successful-generation.json")
        let snapshotBefore = await provider.registration.diagnosticSnapshot()

        #expect(throws: ImageGenerationRequest.ValidationError.blankPrompt) {
            _ = try ImageGenerationRequest(prompt: " \n\t")
        }
        #expect(
            await provider.registration.diagnosticSnapshot() == snapshotBefore
        )
    }

    private func makeProvider(
        fixture: String? = nil,
        sentinel: String = "sk-fixture-openai-image-safe-123456",
        response: RedactingURLProtocol.Response = .http(statusCode: 200)
    ) async throws -> FixtureOpenAIImageProvider {
        let url = try #require(
            URL(string: "https://fixture.invalid/v1/images/generations")
        )
        let request = URLRequest(url: url)
        let bytes: Data
        if let fixture {
            let fixtureURL = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("RPGPlayer/Fixtures/Providers/OpenAIImages")
                .appendingPathComponent(fixture)
            bytes = try Data(contentsOf: fixtureURL)
        } else {
            bytes = Data(#"{"data":[]}"#.utf8)
        }
        let registration = await RedactingURLProtocol.register(
            scenario: RedactingURLProtocol.Scenario(
                response: response,
                steps: [.chunk(bytes)]
            ),
            for: request
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedactingURLProtocol.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        return FixtureOpenAIImageProvider(
            adapter: OpenAIImageProvider(
                credentialReader: FixtureCredentialReader(value: sentinel),
                baseRequest: registration.request,
                httpClient: StreamingHTTPClient(
                    session: URLSession(configuration: configuration)
                )
            ),
            registration: registration
        )
    }
}

private struct FixtureCredentialReader: ProviderCredentialReader, Sendable {
    let value: String

    func credentialData(
        for reference: ProviderCredentialReference
    ) async throws -> Data {
        Data(value.utf8)
    }
}

private struct FixtureOpenAIImageProvider: Sendable {
    let adapter: OpenAIImageProvider
    let registration: RedactingURLProtocol.Registration
}
