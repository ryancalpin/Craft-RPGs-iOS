import Foundation

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
    public enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
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
