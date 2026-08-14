import Foundation

public actor OpenAIImageProvider: ImageProvider {
    public nonisolated let id: ProviderID = .openAI

    public static let defaultBaseURL = URL(string: "https://api.openai.com/v1")!

    private let credentialReader: any ProviderCredentialReader
    private let credentialReference: ProviderCredentialReference
    private let baseURL: URL
    private let baseRequest: URLRequest?
    private let httpClient: StreamingHTTPClient

    public init(
        credentialReader: any ProviderCredentialReader,
        credentialReference: ProviderCredentialReference? = nil,
        baseURL: URL = OpenAIImageProvider.defaultBaseURL
    ) {
        self.credentialReader = credentialReader
        self.credentialReference = credentialReference ?? Self.defaultReference
        self.baseURL = baseURL
        baseRequest = nil
        httpClient = .live()
    }

    init(
        credentialReader: any ProviderCredentialReader,
        credentialReference: ProviderCredentialReference? = nil,
        baseRequest: URLRequest,
        httpClient: StreamingHTTPClient
    ) {
        self.credentialReader = credentialReader
        self.credentialReference = credentialReference ?? Self.defaultReference
        self.baseURL = baseRequest.url?
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            ?? Self.defaultBaseURL
        self.baseRequest = baseRequest
        self.httpClient = httpClient
    }

    public func models() async throws -> [ImageGenerationModel] {
        Self.curatedModels
    }

    public func generateImage(
        _ request: ImageGenerationRequest
    ) async throws -> ImageGenerationResult {
        let credential = try await credential()
        let modelID = request.modelID ?? Self.curatedModels[0].id

        var urlRequest = makeRequest(path: "images/generations")
        urlRequest.setValue(
            "Bearer \(credential)",
            forHTTPHeaderField: "Authorization"
        )
        urlRequest.httpBody = try Self.requestBody(
            for: request,
            modelID: modelID
        )

        do {
            let data = try await httpClient.boundedData(for: urlRequest)
            return try Self.result(from: data, modelID: modelID)
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

    private func makeRequest(path: String) -> URLRequest {
        var request = baseRequest ?? URLRequest(
            url: baseURL.appendingPathComponent(path)
        )
        if baseRequest != nil {
            request.url = baseURL.appendingPathComponent(path)
        }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func requestBody(
        for request: ImageGenerationRequest,
        modelID: String
    ) throws -> Data {
        let body = OpenAIWire.GenerationRequest(
            model: modelID,
            prompt: request.prompt,
            n: request.count,
            size: request.size,
            quality: request.quality
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(body)
    }

    private static func result(
        from data: Data,
        modelID: String
    ) throws -> ImageGenerationResult {
        do {
            let response = try JSONDecoder().decode(
                OpenAIWire.GenerationResponse.self,
                from: data
            )
            guard response.data.isEmpty == false else {
                throw ProviderError.malformedResponse
            }

            let images = try response.data.map { image in
                if let encoded = image.base64JSON {
                    guard let decoded = Data(base64Encoded: encoded) else {
                        throw ProviderError.malformedResponse
                    }
                    return ImageGenerationAsset(
                        data: decoded,
                        revisedPrompt: image.revisedPrompt
                    )
                }
                if let url = image.url {
                    return ImageGenerationAsset(
                        url: url,
                        revisedPrompt: image.revisedPrompt
                    )
                }
                throw ProviderError.malformedResponse
            }
            return ImageGenerationResult(
                providerID: .openAI,
                modelID: modelID,
                images: images
            )
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.malformedResponse
        }
    }

    private static let defaultReference: ProviderCredentialReference = {
        try! ProviderCredentialReference(providerID: .openAI)
    }()

    private static let curatedModels: [ImageGenerationModel] = [
        ImageGenerationModel(
            providerID: .openAI,
            id: "gpt-image-1",
            displayName: "GPT Image 1"
        ),
        ImageGenerationModel(
            providerID: .openAI,
            id: "dall-e-3",
            displayName: "DALL·E 3"
        )
    ]

    private enum OpenAIWire {
        struct GenerationRequest: Encodable {
            let model: String
            let prompt: String
            let n: Int
            let size: String?
            let quality: String?
        }

        struct GenerationResponse: Decodable {
            let data: [GeneratedImage]
        }

        struct GeneratedImage: Decodable {
            let base64JSON: String?
            let url: URL?
            let revisedPrompt: String?

            private enum CodingKeys: String, CodingKey {
                case base64JSON = "b64_json"
                case url
                case revisedPrompt = "revised_prompt"
            }
        }
    }
}
