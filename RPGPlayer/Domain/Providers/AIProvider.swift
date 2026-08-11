import Foundation

public protocol AIProvider: Sendable {
    var id: ProviderID { get }

    func models() async throws -> [ProviderModel]

    func streamTurn(
        _ request: TurnRequest
    ) async throws -> AsyncThrowingStream<ProviderStreamEvent, Error>

    func cancel(requestID: UUID) async
}

public struct PlayerAction: Codable, Equatable, Sendable {
    public let text: String
    public let additionalContext: String?

    public init(text: String, additionalContext: String? = nil) {
        self.text = text
        self.additionalContext = additionalContext
    }
}

public struct ContextHash: Codable, Equatable, Sendable {
    public enum ValidationError: Error, Equatable, Sendable {
        case invalidFormat
    }

    public let rawValue: String

    public init(rawValue: String) throws {
        guard rawValue.utf8.count == 64,
              rawValue.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (97...102).contains(byte)
              }) else {
            throw ValidationError.invalidFormat
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ContextSection: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case systemContract
        case playerCharacter
        case currentScene
        case pendingDecision
        case toolResults
        case recentTranscript
        case referencedRecords
        case unresolvedThreads
        case worldRecords
    }

    public struct Item: Codable, Equatable, Sendable {
        public let id: String?
        public let name: String?
        public let text: String

        public init(
            id: String? = nil,
            name: String? = nil,
            text: String
        ) {
            self.id = id
            self.name = name
            self.text = text
        }
    }

    public let kind: Kind
    public let items: [Item]

    public init(kind: Kind, items: [Item]) {
        self.kind = kind
        self.items = items
    }
}

public struct TurnContext: Codable, Equatable, Sendable {
    public let contextHash: ContextHash
    public let sections: [ContextSection]

    public init(contextHash: ContextHash, sections: [ContextSection]) {
        self.contextHash = contextHash
        self.sections = sections
    }
}

public struct TurnRequest: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let campaignID: UUID
    public let expectedSequence: Int64
    public let action: PlayerAction
    public let context: TurnContext

    public init(
        requestID: UUID,
        campaignID: UUID,
        expectedSequence: Int64,
        action: PlayerAction,
        context: TurnContext
    ) {
        self.requestID = requestID
        self.campaignID = campaignID
        self.expectedSequence = expectedSequence
        self.action = action
        self.context = context
    }
}
