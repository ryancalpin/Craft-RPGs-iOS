import Foundation
import Testing
@testable import RPGPlayer

@Suite(.serialized)
struct ElevenLabsClientTests {
    @Test
    func voiceDiscoveryDecodesUserVoicesAndRedactsTheVoiceKey() async throws {
        let fixture = try await makeClient(
            response: Data(
                """
                {"voices":[{"voice_id":"voice-1","name":"Sable","category":"premade","labels":{"language":"en"},"preview_url":"https://cdn.example.invalid/sable.mp3"}],"has_more":false}
                """.utf8
            )
        )

        let voices = try await fixture.client.voices()

        #expect(voices == [
            VoiceDescriptor(
                providerID: .elevenLabs,
                id: "voice-1",
                displayName: "Sable",
                language: "en",
                category: "premade",
                previewURL: URL(string: "https://cdn.example.invalid/sable.mp3"),
                supportsStreaming: true
            )
        ])
        let snapshot = try #require(
            await fixture.registration.diagnosticSnapshot()
        )
        #expect(snapshot.headers["Xi-Api-Key"] == "<redacted>"
            || snapshot.headers["xi-api-key"] == "<redacted>")
    }

    @Test
    func voiceDiscoveryNormalizesRateLimits() async throws {
        let fixture = try await makeClient(
            response: Data("{}".utf8),
            statusCode: 429
        )

        await #expect(throws: ProviderError.rateLimited(retryAfter: nil)) {
            _ = try await fixture.client.voices()
        }
    }

    private func makeClient(
        response: Data,
        statusCode: Int = 200,
        sentinel: String = "sk_fixture_voice_secret_123456"
    ) async throws -> FixtureClient {
        let url = try #require(URL(string: "https://fixture.invalid/v1/voices"))
        let registration = await RedactingURLProtocol.register(
            scenario: RedactingURLProtocol.Scenario(
                response: .http(statusCode: statusCode),
                steps: [.chunk(response)]
            ),
            for: URLRequest(url: url)
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedactingURLProtocol.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let client = ElevenLabsClient(
            credentialReader: FixtureCredentialReader(value: sentinel),
            baseRequest: registration.request,
            httpClient: StreamingHTTPClient(
                session: URLSession(configuration: configuration)
            )
        )
        return FixtureClient(client: client, registration: registration)
    }
}

private struct FixtureClient: Sendable {
    let client: ElevenLabsClient
    let registration: RedactingURLProtocol.Registration
}

private struct FixtureCredentialReader: VoiceCredentialReader, Sendable {
    let value: String

    func credentialData(
        for reference: VoiceCredentialReference
    ) async throws -> Data {
        Data(value.utf8)
    }
}
