import Foundation

public enum ProviderID: String, Codable, CaseIterable, Sendable {
    case openAI
    case openRouter
    case anthropic
    case gemini
}

public struct ProviderModel: Codable, Identifiable, Equatable, Sendable {
    public enum ValidationError: Error, Equatable, Sendable {
        case blankModelID
        case nonpositiveContextWindow
        case nonpositiveMaximumOutputTokens
        case maximumOutputExceedsContextWindow
    }

    public let providerID: ProviderID
    public let id: String
    public let displayName: String
    public let contextWindowTokens: Int
    public let maximumOutputTokens: Int
    public let supportsTools: Bool
    public let supportsStructuredOutput: Bool

    private enum CodingKeys: String, CodingKey {
        case providerID
        case id
        case displayName
        case contextWindowTokens
        case maximumOutputTokens
        case supportsTools
        case supportsStructuredOutput
    }

    public init(
        providerID: ProviderID,
        id: String,
        displayName: String,
        contextWindowTokens: Int,
        maximumOutputTokens: Int,
        supportsTools: Bool,
        supportsStructuredOutput: Bool
    ) throws {
        guard id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            == false else {
            throw ValidationError.blankModelID
        }
        guard contextWindowTokens > 0 else {
            throw ValidationError.nonpositiveContextWindow
        }
        guard maximumOutputTokens > 0 else {
            throw ValidationError.nonpositiveMaximumOutputTokens
        }
        guard maximumOutputTokens <= contextWindowTokens else {
            throw ValidationError.maximumOutputExceedsContextWindow
        }

        self.providerID = providerID
        self.id = id
        self.displayName = displayName
        self.contextWindowTokens = contextWindowTokens
        self.maximumOutputTokens = maximumOutputTokens
        self.supportsTools = supportsTools
        self.supportsStructuredOutput = supportsStructuredOutput
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            providerID: container.decode(ProviderID.self, forKey: .providerID),
            id: container.decode(String.self, forKey: .id),
            displayName: container.decode(String.self, forKey: .displayName),
            contextWindowTokens: container.decode(
                Int.self,
                forKey: .contextWindowTokens
            ),
            maximumOutputTokens: container.decode(
                Int.self,
                forKey: .maximumOutputTokens
            ),
            supportsTools: container.decode(Bool.self, forKey: .supportsTools),
            supportsStructuredOutput: container.decode(
                Bool.self,
                forKey: .supportsStructuredOutput
            )
        )
    }
}
