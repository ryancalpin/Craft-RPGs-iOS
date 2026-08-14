import Foundation

public protocol ImageProvider: Sendable {
    var id: ProviderID { get }

    func models() async throws -> [ImageGenerationModel]

    func generateImage(
        _ request: ImageGenerationRequest
    ) async throws -> ImageGenerationResult
}

public struct ImageGenerationModel: Codable, Identifiable, Equatable, Sendable {
    public let providerID: ProviderID
    public let id: String
    public let displayName: String

    public init(
        providerID: ProviderID,
        id: String,
        displayName: String
    ) {
        self.providerID = providerID
        self.id = id
        self.displayName = displayName
    }
}

public struct ImageGenerationRequest: Codable, Equatable, Sendable {
    public enum ValidationError: Error, Equatable, Sendable {
        case blankPrompt
        case invalidCount
    }

    public let prompt: String
    public let modelID: String?
    public let size: String?
    public let quality: String?
    public let count: Int

    public init(
        prompt: String,
        modelID: String? = nil,
        size: String? = nil,
        quality: String? = nil,
        count: Int = 1
    ) throws {
        guard prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false else {
            throw ValidationError.blankPrompt
        }
        guard (1...10).contains(count) else {
            throw ValidationError.invalidCount
        }

        self.prompt = prompt
        self.modelID = modelID
        self.size = size
        self.quality = quality
        self.count = count
    }
}

public struct ImageGenerationAsset: Codable, Equatable, Sendable {
    public let data: Data?
    public let url: URL?
    public let revisedPrompt: String?

    public init(
        data: Data? = nil,
        url: URL? = nil,
        revisedPrompt: String? = nil
    ) {
        self.data = data
        self.url = url
        self.revisedPrompt = revisedPrompt
    }
}

public struct ImageGenerationResult: Codable, Equatable, Sendable {
    public let providerID: ProviderID
    public let modelID: String
    public let images: [ImageGenerationAsset]

    public init(
        providerID: ProviderID,
        modelID: String,
        images: [ImageGenerationAsset]
    ) {
        self.providerID = providerID
        self.modelID = modelID
        self.images = images
    }
}
