import Foundation

public struct StoryBlock: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case narration
        case dialogue
    }

    public let id: UUID
    public let kind: Kind
    public let speakerRecordID: String?
    public let speakerName: String?
    public let mood: String?
    public let text: String

    public init(
        id: UUID,
        kind: Kind,
        speakerRecordID: String? = nil,
        speakerName: String? = nil,
        mood: String? = nil,
        text: String
    ) {
        self.id = id
        self.kind = kind
        self.speakerRecordID = speakerRecordID
        self.speakerName = speakerName
        self.mood = mood
        self.text = text
    }
}

public struct PlayerDecision: Codable, Identifiable, Equatable, Sendable {
    public struct Option: Codable, Equatable, Sendable {
        public let title: String
        public let detail: String

        public init(title: String, detail: String) {
            self.title = title
            self.detail = detail
        }
    }

    public let id: UUID
    public let prompt: String
    public let options: [Option]

    public init(id: UUID, prompt: String, options: [Option]) {
        self.id = id
        self.prompt = prompt
        self.options = options
    }
}

public struct VoiceSegment: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sourceStoryBlockID: UUID
    public let speakerRecordID: String?
    public let speakerName: String
    public let text: String

    public init(
        id: UUID,
        sourceStoryBlockID: UUID,
        speakerRecordID: String? = nil,
        speakerName: String,
        text: String
    ) {
        self.id = id
        self.sourceStoryBlockID = sourceStoryBlockID
        self.speakerRecordID = speakerRecordID
        self.speakerName = speakerName
        self.text = text
    }
}

public enum ProposedCampaignEvent: Codable, Equatable, Sendable {
    case recordPatch(recordID: String, fields: [String: JSONValue])
    case rollRequest(rollID: UUID, expression: String, prompt: String)
    case sceneChange(sceneRecordID: String, title: String, summary: String?)
    case clockUpdate(clockRecordID: String, current: Int, maximum: Int)
    case voiceSuggestion(
        characterRecordID: String,
        styleDescription: String
    )
    case assetAttachment(
        assetID: String,
        targetRecordID: String,
        fieldID: String
    )

    private enum CodingKeys: String, CodingKey {
        case type
        case data
    }

    private enum Kind: String, Codable {
        case recordPatch
        case rollRequest
        case sceneChange
        case clockUpdate
        case voiceSuggestion
        case assetAttachment
    }

    private struct RecordPatchData: Codable {
        let recordID: String
        let fields: [String: JSONValue]
    }

    private struct RollRequestData: Codable {
        let rollID: UUID
        let expression: String
        let prompt: String
    }

    private struct SceneChangeData: Codable {
        let sceneRecordID: String
        let title: String
        let summary: String?
    }

    private struct ClockUpdateData: Codable {
        let clockRecordID: String
        let current: Int
        let maximum: Int
    }

    private struct VoiceSuggestionData: Codable {
        let characterRecordID: String
        let styleDescription: String
    }

    private struct AssetAttachmentData: Codable {
        let assetID: String
        let targetRecordID: String
        let fieldID: String
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)

        self = switch kind {
        case .recordPatch:
            try Self.recordPatch(
                container.decode(RecordPatchData.self, forKey: .data)
            )
        case .rollRequest:
            try Self.rollRequest(
                container.decode(RollRequestData.self, forKey: .data)
            )
        case .sceneChange:
            try Self.sceneChange(
                container.decode(SceneChangeData.self, forKey: .data)
            )
        case .clockUpdate:
            try Self.clockUpdate(
                container.decode(ClockUpdateData.self, forKey: .data)
            )
        case .voiceSuggestion:
            try Self.voiceSuggestion(
                container.decode(VoiceSuggestionData.self, forKey: .data)
            )
        case .assetAttachment:
            try Self.assetAttachment(
                container.decode(AssetAttachmentData.self, forKey: .data)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .recordPatch(let recordID, let fields):
            try container.encode(Kind.recordPatch, forKey: .type)
            try container.encode(
                RecordPatchData(recordID: recordID, fields: fields),
                forKey: .data
            )
        case .rollRequest(let rollID, let expression, let prompt):
            try container.encode(Kind.rollRequest, forKey: .type)
            try container.encode(
                RollRequestData(
                    rollID: rollID,
                    expression: expression,
                    prompt: prompt
                ),
                forKey: .data
            )
        case .sceneChange(let sceneRecordID, let title, let summary):
            try container.encode(Kind.sceneChange, forKey: .type)
            try container.encode(
                SceneChangeData(
                    sceneRecordID: sceneRecordID,
                    title: title,
                    summary: summary
                ),
                forKey: .data
            )
        case .clockUpdate(let clockRecordID, let current, let maximum):
            try container.encode(Kind.clockUpdate, forKey: .type)
            try container.encode(
                ClockUpdateData(
                    clockRecordID: clockRecordID,
                    current: current,
                    maximum: maximum
                ),
                forKey: .data
            )
        case .voiceSuggestion(let characterRecordID, let styleDescription):
            try container.encode(Kind.voiceSuggestion, forKey: .type)
            try container.encode(
                VoiceSuggestionData(
                    characterRecordID: characterRecordID,
                    styleDescription: styleDescription
                ),
                forKey: .data
            )
        case .assetAttachment(let assetID, let targetRecordID, let fieldID):
            try container.encode(Kind.assetAttachment, forKey: .type)
            try container.encode(
                AssetAttachmentData(
                    assetID: assetID,
                    targetRecordID: targetRecordID,
                    fieldID: fieldID
                ),
                forKey: .data
            )
        }
    }

    private static func recordPatch(
        _ data: RecordPatchData
    ) -> ProposedCampaignEvent {
        .recordPatch(recordID: data.recordID, fields: data.fields)
    }

    private static func rollRequest(
        _ data: RollRequestData
    ) -> ProposedCampaignEvent {
        .rollRequest(
            rollID: data.rollID,
            expression: data.expression,
            prompt: data.prompt
        )
    }

    private static func sceneChange(
        _ data: SceneChangeData
    ) -> ProposedCampaignEvent {
        .sceneChange(
            sceneRecordID: data.sceneRecordID,
            title: data.title,
            summary: data.summary
        )
    }

    private static func clockUpdate(
        _ data: ClockUpdateData
    ) -> ProposedCampaignEvent {
        .clockUpdate(
            clockRecordID: data.clockRecordID,
            current: data.current,
            maximum: data.maximum
        )
    }

    private static func voiceSuggestion(
        _ data: VoiceSuggestionData
    ) -> ProposedCampaignEvent {
        .voiceSuggestion(
            characterRecordID: data.characterRecordID,
            styleDescription: data.styleDescription
        )
    }

    private static func assetAttachment(
        _ data: AssetAttachmentData
    ) -> ProposedCampaignEvent {
        .assetAttachment(
            assetID: data.assetID,
            targetRecordID: data.targetRecordID,
            fieldID: data.fieldID
        )
    }
}

public struct TurnEnvelope: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let narration: [StoryBlock]
    public let beats: [VisualNovelBeat]
    public let proposedEvents: [ProposedCampaignEvent]
    public let pendingDecision: PlayerDecision?
    public let voiceSegments: [VoiceSegment]
    public let usage: ProviderUsage?

    public init(
        requestID: UUID,
        narration: [StoryBlock],
        beats: [VisualNovelBeat],
        proposedEvents: [ProposedCampaignEvent],
        pendingDecision: PlayerDecision?,
        voiceSegments: [VoiceSegment],
        usage: ProviderUsage?
    ) {
        self.requestID = requestID
        self.narration = narration
        self.beats = beats
        self.proposedEvents = proposedEvents
        self.pendingDecision = pendingDecision
        self.voiceSegments = voiceSegments
        self.usage = usage
    }
}

public struct VersionedTurnEnvelope: Codable, Equatable, Sendable {
    public enum CodingError: Error, Equatable, Sendable {
        case unsupportedSchemaVersion(Int)
        case payloadTooLarge(maximumBytes: Int, actualBytes: Int)
    }

    public static let maximumEncodedBytes = 8_000_000

    public let schemaVersion: Int
    public let envelope: TurnEnvelope

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case envelope
    }

    public init(envelope: TurnEnvelope) {
        schemaVersion = 1
        self.envelope = envelope
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(
            Int.self,
            forKey: .schemaVersion
        )
        guard schemaVersion == 1 else {
            throw CodingError.unsupportedSchemaVersion(schemaVersion)
        }
        self.schemaVersion = schemaVersion
        envelope = try container.decode(TurnEnvelope.self, forKey: .envelope)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(envelope, forKey: .envelope)
    }

    public static func decode(from data: Data) throws -> Self {
        guard data.count <= maximumEncodedBytes else {
            throw CodingError.payloadTooLarge(
                maximumBytes: maximumEncodedBytes,
                actualBytes: data.count
            )
        }
        return try JSONDecoder().decode(Self.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumEncodedBytes else {
            throw CodingError.payloadTooLarge(
                maximumBytes: Self.maximumEncodedBytes,
                actualBytes: data.count
            )
        }
        return data
    }
}
