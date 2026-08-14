import Foundation
import Testing
@testable import RPGPlayer

@Suite(.serialized)
struct SpeechSynthesisTests {
    @Test
    func elevenLabsSynthesisEncodesRequestAndReturnsAudio() async throws {
        let fixture = try await makeElevenLabsSynthesizer(
            response: Data([0x49, 0x44, 0x33])
        )
        let request = SpeechSynthesisRequest(
            text: "A bell rings in the fog.",
            voiceID: "voice-1",
            modelID: "eleven_multilingual_v2",
            outputFormat: .mp3_44100_128,
            settings: SpeechVoiceSettings(
                stability: 0.42,
                similarityBoost: 0.81,
                style: 0.13,
                useSpeakerBoost: true
            )
        )

        let result = try await fixture.synthesizer.synthesize(request)

        #expect(result.providerID == .elevenLabs)
        #expect(result.output == .audio(
            data: Data([0x49, 0x44, 0x33]),
            mimeType: "audio/mpeg"
        ))

        let snapshot = try #require(
            await fixture.registration.diagnosticSnapshot()
        )
        #expect(snapshot.method == "POST")
        #expect(snapshot.path == "/v1/text-to-speech/voice-1")
        #expect(snapshot.queryItemNames == ["output_format"])
        #expect(snapshot.headers["Xi-Api-Key"] == "<redacted>"
            || snapshot.headers["xi-api-key"] == "<redacted>")

        let body = try #require(snapshot.bodyData)
        let object = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(object["text"] as? String == "A bell rings in the fog.")
        #expect(object["model_id"] as? String == "eleven_multilingual_v2")
        let settings = try #require(
            object["voice_settings"] as? [String: Any]
        )
        #expect(settings["stability"] as? Double == 0.42)
        #expect(settings["similarity_boost"] as? Double == 0.81)
        #expect(settings["style"] as? Double == 0.13)
        #expect(settings["use_speaker_boost"] as? Bool == true)
    }

    @Test
    func elevenLabsSynthesisNormalizesRateLimitsWithoutLeakingCredential()
        async throws {
        let sentinel = "sk_fixture_speech_secret_123456"
        let fixture = try await makeElevenLabsSynthesizer(
            response: Data(),
            statusCode: 429,
            sentinel: sentinel
        )

        await #expect(throws: ProviderError.rateLimited(retryAfter: nil)) {
            _ = try await fixture.synthesizer.synthesize(
                SpeechSynthesisRequest(
                    text: "The hidden password is " + sentinel + ".",
                    voiceID: "voice-1"
                )
            )
        }

        let snapshot = try #require(
            await fixture.registration.diagnosticSnapshot()
        )
        #expect(snapshot.headers.values.contains(sentinel) == false)
    }

    @Test
    func elevenLabsSynthesisRejectsMissingVoiceBeforeMakingARequest()
        async throws {
        let fixture = try await makeElevenLabsSynthesizer(
            response: Data([0x01])
        )
        let before = await fixture.registration.diagnosticSnapshot()

        await #expect(throws: SpeechSynthesisError.missingVoiceID) {
            _ = try await fixture.synthesizer.synthesize(
                SpeechSynthesisRequest(text: "A voice without an ID.")
            )
        }

        #expect(
            await fixture.registration.diagnosticSnapshot() == before
        )
    }

    @MainActor
    @Test
    func appleSpeechUsesInjectedDriverAndReturnsPlatformPlayback()
        async throws {
        let driver = RecordingAppleSpeechDriver()
        let synthesizer = AppleSpeechSynthesizer(driver: driver)
        let request = SpeechSynthesisRequest(
            text: "Speak this locally.",
            voiceID: "com.apple.voice.compact.en-US.Samantha",
            language: "en-US"
        )

        let result = try await synthesizer.synthesize(request)

        #expect(driver.text == request.text)
        #expect(driver.voiceIdentifier == request.voiceID)
        #expect(driver.language == request.language)
        #expect(result.providerID == .appleSpeech)
        #expect(result.output == .platformPlayback)
    }

    private func makeElevenLabsSynthesizer(
        response: Data,
        statusCode: Int = 200,
        sentinel: String = "sk_fixture_speech_safe_123456"
    ) async throws -> ElevenLabsFixture {
        let url = try #require(
            URL(string: "https://fixture.invalid/v1/speech")
        )
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

        return ElevenLabsFixture(
            synthesizer: ElevenLabsSpeechSynthesizer(
                credentialReader: SpeechFixtureCredentialReader(
                    value: sentinel
                ),
                baseRequest: registration.request,
                httpClient: StreamingHTTPClient(
                    session: URLSession(configuration: configuration)
                )
            ),
            registration: registration
        )
    }
}

private struct ElevenLabsFixture: Sendable {
    let synthesizer: ElevenLabsSpeechSynthesizer
    let registration: RedactingURLProtocol.Registration
}

private struct SpeechFixtureCredentialReader: VoiceCredentialReader, Sendable {
    let value: String

    func credentialData(
        for reference: VoiceCredentialReference
    ) async throws -> Data {
        Data(value.utf8)
    }
}

@MainActor
private final class RecordingAppleSpeechDriver: AppleSpeechSynthesizerDriver {
    var text: String?
    var voiceIdentifier: String?
    var language: String?

    func speak(
        text: String,
        voiceIdentifier: String?,
        language: String?,
        settings: SpeechVoiceSettings,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        self.text = text
        self.voiceIdentifier = voiceIdentifier
        self.language = language
        completion(.success(()))
    }

    func stop() {}
}
