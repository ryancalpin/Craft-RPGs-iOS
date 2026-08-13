import Foundation

public struct CampaignEvent: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let campaignID: UUID
    public let sequence: Int64
    public let requestID: UUID
    public let timestamp: Date
    public let schemaVersion: Int
    public let payload: CampaignEventPayload

    public init(
        id: UUID,
        campaignID: UUID,
        sequence: Int64,
        requestID: UUID,
        timestamp: Date,
        schemaVersion: Int,
        payload: CampaignEventPayload
    ) {
        self.id = id
        self.campaignID = campaignID
        self.sequence = sequence
        self.requestID = requestID
        self.timestamp = timestamp
        self.schemaVersion = schemaVersion
        self.payload = payload
    }
}

public enum CampaignEventPayload: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case campaignImported
        case playerActionSubmitted
        case gmStatusChanged
        case gmMessageCommitted
        case recordPatched
        case clockUpdated
        case assetAttached
        case rollRequested
        case rollResolved
        case sceneChanged
        case voiceAssignmentChanged
        case voiceSuggestionProposed
        case turnCancelled
        case turnFailed
    }

    case campaignImported(CampaignImportedPayload)
    case playerActionSubmitted(PlayerActionSubmittedPayload)
    case gmStatusChanged(GMStatusChangedPayload)
    case gmMessageCommitted(GMMessageCommittedPayload)
    case recordPatched(RecordPatchedPayload)
    case clockUpdated(ClockUpdatedPayload)
    case assetAttached(AssetAttachedPayload)
    case rollRequested(RollRequestedPayload)
    case rollResolved(RollResolvedPayload)
    case sceneChanged(SceneChangedPayload)
    case voiceAssignmentChanged(VoiceAssignmentChangedPayload)
    case voiceSuggestionProposed(VoiceSuggestionProposedPayload)
    case turnCancelled(TurnCancelledPayload)
    case turnFailed(TurnFailedPayload)

    public var kind: Kind {
        switch self {
        case .campaignImported: .campaignImported
        case .playerActionSubmitted: .playerActionSubmitted
        case .gmStatusChanged: .gmStatusChanged
        case .gmMessageCommitted: .gmMessageCommitted
        case .recordPatched: .recordPatched
        case .clockUpdated: .clockUpdated
        case .assetAttached: .assetAttached
        case .rollRequested: .rollRequested
        case .rollResolved: .rollResolved
        case .sceneChanged: .sceneChanged
        case .voiceAssignmentChanged: .voiceAssignmentChanged
        case .voiceSuggestionProposed: .voiceSuggestionProposed
        case .turnCancelled: .turnCancelled
        case .turnFailed: .turnFailed
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)

        self = switch kind {
        case .campaignImported:
            .campaignImported(
                try container.decode(CampaignImportedPayload.self, forKey: .data)
            )
        case .playerActionSubmitted:
            .playerActionSubmitted(
                try container.decode(PlayerActionSubmittedPayload.self, forKey: .data)
            )
        case .gmStatusChanged:
            .gmStatusChanged(
                try container.decode(GMStatusChangedPayload.self, forKey: .data)
            )
        case .gmMessageCommitted:
            .gmMessageCommitted(
                try container.decode(GMMessageCommittedPayload.self, forKey: .data)
            )
        case .recordPatched:
            .recordPatched(
                try container.decode(RecordPatchedPayload.self, forKey: .data)
            )
        case .clockUpdated:
            .clockUpdated(
                try container.decode(ClockUpdatedPayload.self, forKey: .data)
            )
        case .assetAttached:
            .assetAttached(
                try container.decode(AssetAttachedPayload.self, forKey: .data)
            )
        case .rollRequested:
            .rollRequested(
                try container.decode(RollRequestedPayload.self, forKey: .data)
            )
        case .rollResolved:
            .rollResolved(
                try container.decode(RollResolvedPayload.self, forKey: .data)
            )
        case .sceneChanged:
            .sceneChanged(
                try container.decode(SceneChangedPayload.self, forKey: .data)
            )
        case .voiceAssignmentChanged:
            .voiceAssignmentChanged(
                try container.decode(VoiceAssignmentChangedPayload.self, forKey: .data)
            )
        case .voiceSuggestionProposed:
            .voiceSuggestionProposed(
                try container.decode(VoiceSuggestionProposedPayload.self, forKey: .data)
            )
        case .turnCancelled:
            .turnCancelled(
                try container.decode(TurnCancelledPayload.self, forKey: .data)
            )
        case .turnFailed:
            .turnFailed(
                try container.decode(TurnFailedPayload.self, forKey: .data)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .type)

        switch self {
        case .campaignImported(let payload):
            try container.encode(payload, forKey: .data)
        case .playerActionSubmitted(let payload):
            try container.encode(payload, forKey: .data)
        case .gmStatusChanged(let payload):
            try container.encode(payload, forKey: .data)
        case .gmMessageCommitted(let payload):
            try container.encode(payload, forKey: .data)
        case .recordPatched(let payload):
            try container.encode(payload, forKey: .data)
        case .clockUpdated(let payload):
            try container.encode(payload, forKey: .data)
        case .assetAttached(let payload):
            try container.encode(payload, forKey: .data)
        case .rollRequested(let payload):
            try container.encode(payload, forKey: .data)
        case .rollResolved(let payload):
            try container.encode(payload, forKey: .data)
        case .sceneChanged(let payload):
            try container.encode(payload, forKey: .data)
        case .voiceAssignmentChanged(let payload):
            try container.encode(payload, forKey: .data)
        case .voiceSuggestionProposed(let payload):
            try container.encode(payload, forKey: .data)
        case .turnCancelled(let payload):
            try container.encode(payload, forKey: .data)
        case .turnFailed(let payload):
            try container.encode(payload, forKey: .data)
        }
    }
}

public struct CampaignImportedPayload: Codable, Equatable, Sendable {
    public let projectID: String
    public let campaignTitle: String
    public let manifestHash: String
    public let extensionPayload: [String: JSONValue]

    public init(
        projectID: String,
        campaignTitle: String,
        manifestHash: String,
        extensionPayload: [String: JSONValue] = [:]
    ) {
        self.projectID = projectID
        self.campaignTitle = campaignTitle
        self.manifestHash = manifestHash
        self.extensionPayload = extensionPayload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        projectID = try container.decode(String.self, forKey: .projectID)
        campaignTitle = try container.decode(String.self, forKey: .campaignTitle)
        manifestHash = try container.decode(String.self, forKey: .manifestHash)

        extensionPayload = try container.allKeys.reduce(into: [:]) {
            payload, key in
            guard Self.knownKeys.contains(key.stringValue) == false else {
                return
            }
            payload[key.stringValue] = try container.decode(
                JSONValue.self,
                forKey: key
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(projectID, forKey: .projectID)
        try container.encode(campaignTitle, forKey: .campaignTitle)
        try container.encode(manifestHash, forKey: .manifestHash)

        for (key, value) in extensionPayload
        where Self.knownKeys.contains(key) == false {
            try container.encode(value, forKey: DynamicCodingKey(key))
        }
    }

    private static let knownKeys: Set<String> = [
        DynamicCodingKey.projectID.stringValue,
        DynamicCodingKey.campaignTitle.stringValue,
        DynamicCodingKey.manifestHash.stringValue
    ]
}

public struct PlayerActionSubmittedPayload: Codable, Equatable, Sendable {
    public let action: String
    public let additionalContext: String?

    public init(action: String, additionalContext: String? = nil) {
        self.action = action
        self.additionalContext = additionalContext
    }
}

public enum CampaignGenerationPhase: String, Codable, Sendable {
    case queued
    case readingWorld
    case planning
    case updatingWorld
    case writingScene
    case voicing
    case ready
    case needsAttention
}

public struct GMStatusChangedPayload: Codable, Equatable, Sendable {
    public let phase: CampaignGenerationPhase
    public let sanitizedDetail: String?

    public init(
        phase: CampaignGenerationPhase,
        sanitizedDetail: String? = nil
    ) {
        self.phase = phase
        self.sanitizedDetail = sanitizedDetail
    }
}

public struct CampaignDialogueBlock: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let speaker: String
    public let mood: String?
    public let text: String

    public init(id: UUID, speaker: String, mood: String? = nil, text: String) {
        self.id = id
        self.speaker = speaker
        self.mood = mood
        self.text = text
    }
}

public struct CampaignStoryBeat: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case title
        case narration
        case dialogue
    }

    public let id: UUID
    public let kind: Kind
    public let title: String?
    public let subtitle: String?
    public let speaker: String?
    public let mood: String?
    public let text: String

    public init(
        id: UUID,
        kind: Kind,
        title: String? = nil,
        subtitle: String? = nil,
        speaker: String? = nil,
        mood: String? = nil,
        text: String
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.speaker = speaker
        self.mood = mood
        self.text = text
    }
}

public struct GMMessageCommittedPayload: Codable, Equatable, Sendable {
    public let messageID: UUID
    public let narration: [String]
    public let dialogue: [CampaignDialogueBlock]
    /// The canonical order of narration and dialogue. Older payloads omit this
    /// field and continue to use the legacy arrays above.
    public let orderedTranscript: [CampaignTranscriptBlock]?
    public let beats: [CampaignStoryBeat]
    public let finalQuestion: String

    public init(
        messageID: UUID,
        narration: [String],
        dialogue: [CampaignDialogueBlock],
        orderedTranscript: [CampaignTranscriptBlock]? = nil,
        beats: [CampaignStoryBeat],
        finalQuestion: String
    ) {
        self.messageID = messageID
        self.narration = narration
        self.dialogue = dialogue
        self.orderedTranscript = orderedTranscript
        self.beats = beats
        self.finalQuestion = finalQuestion
    }
}

public struct CampaignTranscriptBlock: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case narration
        case dialogue
    }

    public let id: UUID
    public let kind: Kind
    public let speaker: String?
    public let mood: String?
    public let text: String

    public init(
        id: UUID,
        kind: Kind,
        speaker: String? = nil,
        mood: String? = nil,
        text: String
    ) {
        self.id = id
        self.kind = kind
        self.speaker = speaker
        self.mood = mood
        self.text = text
    }
}

public struct RecordPatchedPayload: Codable, Equatable, Sendable {
    public let recordID: String
    public let changes: [String: JSONValue]

    public init(recordID: String, changes: [String: JSONValue]) {
        self.recordID = recordID
        self.changes = changes
    }
}

public struct ClockUpdatedPayload: Codable, Equatable, Sendable {
    public let clockRecordID: String
    public let current: Int
    public let maximum: Int

    public init(clockRecordID: String, current: Int, maximum: Int) {
        self.clockRecordID = clockRecordID
        self.current = current
        self.maximum = maximum
    }
}

public struct AssetAttachedPayload: Codable, Equatable, Sendable {
    public let assetID: String
    public let targetRecordID: String
    public let fieldID: String

    public init(assetID: String, targetRecordID: String, fieldID: String) {
        self.assetID = assetID
        self.targetRecordID = targetRecordID
        self.fieldID = fieldID
    }
}

public struct RollRequestedPayload: Codable, Equatable, Sendable {
    public let rollID: UUID
    public let expression: String
    public let prompt: String

    public init(rollID: UUID, expression: String, prompt: String) {
        self.rollID = rollID
        self.expression = expression
        self.prompt = prompt
    }
}

public struct RollResolvedPayload: Codable, Equatable, Sendable {
    public let rollID: UUID
    public let results: [Int]
    public let modifier: Int
    public let total: Int

    public init(rollID: UUID, results: [Int], modifier: Int, total: Int) {
        self.rollID = rollID
        self.results = results
        self.modifier = modifier
        self.total = total
    }
}

public struct SceneChangedPayload: Codable, Equatable, Sendable {
    public let sceneID: String
    public let title: String
    public let summary: String?

    public init(sceneID: String, title: String, summary: String? = nil) {
        self.sceneID = sceneID
        self.title = title
        self.summary = summary
    }
}

public enum VoiceAssignmentSource: String, Codable, Sendable {
    case manual
    case acceptedSuggestion
}

public struct VoiceAssignmentChangedPayload: Codable, Equatable, Sendable {
    public let characterID: String
    public let voiceID: String?
    public let source: VoiceAssignmentSource

    public init(
        characterID: String,
        voiceID: String?,
        source: VoiceAssignmentSource
    ) {
        self.characterID = characterID
        self.voiceID = voiceID
        self.source = source
    }
}

public struct VoiceSuggestionProposedPayload: Codable, Equatable, Sendable {
    public let characterID: String
    public let styleDescription: String

    public init(characterID: String, styleDescription: String) {
        self.characterID = characterID
        self.styleDescription = styleDescription
    }
}

public struct TurnCancelledPayload: Codable, Equatable, Sendable {
    public let reason: String?

    public init(reason: String? = nil) {
        self.reason = reason
    }
}

public enum TurnFailureCategory: String, Codable, Sendable {
    case connectivity
    case provider
    case validation
    case unknown
}

public struct TurnFailedPayload: Codable, Equatable, Sendable {
    public let category: TurnFailureCategory
    public let message: String
    public let isRetryable: Bool

    public init(
        category: TurnFailureCategory,
        message: String,
        isRetryable: Bool
    ) {
        self.category = category
        self.message = message
        self.isRetryable = isRetryable
    }
}

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case integer(Int64)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

private struct DynamicCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }

    static let projectID = DynamicCodingKey("projectID")
    static let campaignTitle = DynamicCodingKey("campaignTitle")
    static let manifestHash = DynamicCodingKey("manifestHash")
}
