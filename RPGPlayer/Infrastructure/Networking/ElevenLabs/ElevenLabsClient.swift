import Foundation

public actor ElevenLabsClient: VoiceCatalogProviding {
    public static let defaultBaseURL = URL(
        string: "https://api.elevenlabs.io"
    )!

    private let credentialReader: any VoiceCredentialReader
    private let credentialReference: VoiceCredentialReference
    private let endpointBaseURL: URL
    private let baseRequest: URLRequest?
    private let httpClient: StreamingHTTPClient

    public init(
        credentialReader: any VoiceCredentialReader,
        credentialReference: VoiceCredentialReference? = nil,
        baseURL: URL = ElevenLabsClient.defaultBaseURL
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

    public func validate() async throws {
        let credential = try await credential()
        var request = makeRequest(path: "user")
        authenticate(credential, request: &request)
        do {
            _ = try await httpClient.boundedData(for: request)
        } catch {
            throw ProviderAdapterSupport.normalized(error)
        }
    }

    public func voices() async throws -> [VoiceDescriptor] {
        let credential = try await credential()
        var pageToken: String?
        var result: [VoiceDescriptor] = []

        for _ in 0..<10 {
            var request = makeRequest(path: "voices")
            if let pageToken {
                var components = URLComponents(
                    url: request.url!,
                    resolvingAgainstBaseURL: false
                )!
                components.queryItems = [
                    URLQueryItem(name: "page_token", value: pageToken)
                ]
                request.url = components.url
            }
            authenticate(credential, request: &request)

            do {
                let data = try await httpClient.boundedData(for: request)
                let page = try JSONDecoder().decode(
                    ElevenLabsWire.VoicesResponse.self,
                    from: data
                )
                result.append(contentsOf: page.voices.map(Self.descriptor))
                guard page.hasMore,
                      let next = page.nextPageToken,
                      next.isEmpty == false else {
                    break
                }
                pageToken = next
            } catch let error as ProviderError {
                throw error
            } catch {
                throw ProviderAdapterSupport.normalized(error)
            }
        }
        return result
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

    private func makeRequest(path: String) -> URLRequest {
        var request = baseRequest ?? URLRequest(
            url: endpointBaseURL.appendingPathComponent(path)
        )
        if baseRequest != nil {
            request.url = endpointBaseURL.appendingPathComponent(path)
        }
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func authenticate(
        _ credential: String,
        request: inout URLRequest
    ) {
        request.setValue(credential, forHTTPHeaderField: "xi-api-key")
    }

    private static func descriptor(
        _ voice: ElevenLabsWire.Voice
    ) -> VoiceDescriptor {
        VoiceDescriptor(
            providerID: .elevenLabs,
            id: voice.voiceID,
            displayName: voice.name,
            language: voice.labels?["language"]
                ?? voice.labels?["lang"],
            category: voice.category,
            previewURL: voice.previewURL,
            supportsStreaming: true
        )
    }

    private static let defaultReference: VoiceCredentialReference = {
        try! VoiceCredentialReference(providerID: .elevenLabs)
    }()
}

private enum ElevenLabsWire {
    struct VoicesResponse: Decodable {
        let voices: [Voice]
        let hasMore: Bool
        let nextPageToken: String?

        private enum CodingKeys: String, CodingKey {
            case voices
            case hasMore = "has_more"
            case nextPageToken = "next_page_token"
        }
    }

    struct Voice: Decodable {
        let voiceID: String
        let name: String
        let category: String?
        let labels: [String: String]?
        let previewURL: URL?

        private enum CodingKeys: String, CodingKey {
            case voiceID = "voice_id"
            case name
            case category
            case labels
            case previewURL = "preview_url"
        }
    }
}
