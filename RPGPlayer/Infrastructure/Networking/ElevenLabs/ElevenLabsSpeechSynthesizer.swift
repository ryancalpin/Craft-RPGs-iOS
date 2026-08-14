import Foundation

public actor ElevenLabsSpeechSynthesizer: SpeechSynthesizer {
    public static let defaultBaseURL = URL(
        string: "https://api.elevenlabs.io"
    )!

    public nonisolated let providerID: VoiceProviderID = .elevenLabs

    private let credentialReader: any VoiceCredentialReader
    private let credentialReference: VoiceCredentialReference
    private let endpointBaseURL: URL
    private let baseRequest: URLRequest?
    private let httpClient: StreamingHTTPClient

    public init(
        credentialReader: any VoiceCredentialReader,
        credentialReference: VoiceCredentialReference? = nil,
        baseURL: URL = ElevenLabsSpeechSynthesizer.defaultBaseURL
    ) {
        self.credentialReader = credentialReader
        self.credentialReference = credentialReference ?? Self.defaultReference
        endpointBaseURL = baseURL.appendingPathComponent("v1")
        baseRequest = nil
        httpClient = .live()
    }

    init(
        credentialReader: any VoiceCredentialReader,
        credentialReference: VoiceCredentialReference? = nil,
        baseRequest: URLRequest,
        httpClient: StreamingHTTPClient
    ) {
        self.credentialReader = credentialReader
        self.credentialReference = credentialReference ?? Self.defaultReference
        endpointBaseURL = baseRequest.url?.deletingLastPathComponent()
            ?? Self.defaultBaseURL.appendingPathComponent("v1")
        self.baseRequest = baseRequest
        self.httpClient = httpClient
    }

    public func synthesize(
        _ request: SpeechSynthesisRequest
    ) async throws -> SpeechSynthesisResult {
        guard request.text.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false else {
            throw SpeechSynthesisError.blankText
        }
        guard let voiceID = request.voiceID?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), voiceID.isEmpty == false else {
            throw SpeechSynthesisError.missingVoiceID
        }
        guard request.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false else {
            throw SpeechSynthesisError.missingModelID
        }

        let credential = try await credential()
        var urlRequest = makeRequest(
            voiceID: voiceID,
            outputFormat: request.outputFormat
        )
        urlRequest.httpBody = try Self.requestBody(for: request)
        urlRequest.setValue(credential, forHTTPHeaderField: "xi-api-key")

        do {
            let data = try await httpClient.boundedData(
                for: urlRequest,
                maximumBytes: Self.maximumAudioBytes
            )
            guard data.isEmpty == false else {
                throw SpeechSynthesisError.emptyAudio
            }
            return SpeechSynthesisResult(
                providerID: .elevenLabs,
                output: .audio(
                    data: data,
                    mimeType: Self.mimeType(for: request.outputFormat)
                )
            )
        } catch let error as SpeechSynthesisError {
            throw error
        } catch {
            throw ProviderAdapterSupport.normalized(error)
        }
    }

    private func credential() async throws -> String {
        do {
            let data = try await credentialReader.credentialData(
                for: credentialReference
            )
            guard let value = String(data: data, encoding: .utf8),
                  value.trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty == false else {
                throw ProviderError.invalidCredential
            }
            return value
        } catch let error as ProviderError {
            throw error
        } catch is CancellationError {
            throw ProviderError.cancelled
        } catch {
            if Task.isCancelled {
                throw ProviderError.cancelled
            }
            throw ProviderError.invalidCredential
        }
    }

    private func makeRequest(
        voiceID: String,
        outputFormat: SpeechAudioFormat
    ) -> URLRequest {
        var request = baseRequest ?? URLRequest(
            url: endpointBaseURL
                .appendingPathComponent("text-to-speech")
                .appendingPathComponent(voiceID)
        )
        if baseRequest != nil {
            request.url = endpointBaseURL
                .appendingPathComponent("text-to-speech")
                .appendingPathComponent(voiceID)
        }
        if let url = request.url,
           var components = URLComponents(
               url: url,
               resolvingAgainstBaseURL: false
           ) {
            components.queryItems = [
                URLQueryItem(
                    name: "output_format",
                    value: outputFormat.rawValue
                )
            ]
            request.url = components.url
        }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        return request
    }

    private static func requestBody(
        for request: SpeechSynthesisRequest
    ) throws -> Data {
        let body = ElevenLabsSpeechWire.Request(
            text: request.text,
            modelID: request.modelID,
            voiceSettings: ElevenLabsSpeechWire.VoiceSettings(
                stability: request.settings.stability,
                similarityBoost: request.settings.similarityBoost,
                style: request.settings.style,
                useSpeakerBoost: request.settings.useSpeakerBoost
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(body)
    }

    private static func mimeType(for format: SpeechAudioFormat) -> String {
        switch format {
        case .pcm_16000:
            "audio/pcm"
        case .mp3_44100_128, .mp3_22050_32:
            "audio/mpeg"
        }
    }

    private static let maximumAudioBytes = 10_000_000

    private static let defaultReference: VoiceCredentialReference = {
        try! VoiceCredentialReference(providerID: .elevenLabs)
    }()
}
