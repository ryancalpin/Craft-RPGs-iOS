import Foundation

public struct ProjectedPlayerAction: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let action: String
    public let additionalContext: String?

    public init(
        requestID: UUID,
        action: String,
        additionalContext: String? = nil
    ) {
        self.requestID = requestID
        self.action = action
        self.additionalContext = additionalContext
    }
}

public enum ProjectedTurnOutcome: Codable, Equatable, Sendable {
    case cancelled(requestID: UUID, reason: String?)
    case failed(
        requestID: UUID,
        category: TurnFailureCategory,
        message: String,
        isRetryable: Bool
    )
}

public enum ProjectedRequestRunDisposition: String, Codable, Equatable, Sendable {
    case accepted
    case rejectedDuplicate
}

public struct CampaignProjection: Codable, Equatable, Sendable {
    public let campaignID: UUID
    public var appliedThroughSequence: Int64
    public var campaignTitle: String?
    public var importedProjectID: String?
    public var importManifestHash: String?
    public var approvedHandoffCheckpoint: ApprovedHandoffCheckpoint?
    public var submittedActions: [ProjectedPlayerAction]
    public var gmStatus: GMStatusChangedPayload?
    public var gmMessages: [GMMessageCommittedPayload]
    public var pendingDecision: String?
    public var records: [String: [String: JSONValue]]
    public var clocks: [String: ClockUpdatedPayload]
    public var assetAttachments: [String: AssetAttachedPayload]
    public var pendingRolls: [UUID: RollRequestedPayload]
    public var resolvedRolls: [UUID: RollResolvedPayload]
    public var latestResolvedRollID: UUID?
    public var currentScene: SceneChangedPayload?
    public var voiceAssignments: [String: VoiceAssignmentChangedPayload]
    public var voiceSuggestions: [String: VoiceSuggestionProposedPayload]
    public var turnOutcomes: [ProjectedTurnOutcome]
    public var lastTurnOutcome: ProjectedTurnOutcome?
    public var appliedEventIDs: Set<UUID>
    public var appliedRequestIDs: Set<UUID>
    public var currentRequestRunID: UUID?
    public var currentRequestRunDisposition: ProjectedRequestRunDisposition?
    public var activeTurnRequestID: UUID?

    public init(
        campaignID: UUID,
        appliedThroughSequence: Int64 = 0,
        campaignTitle: String? = nil,
        importedProjectID: String? = nil,
        importManifestHash: String? = nil,
        approvedHandoffCheckpoint: ApprovedHandoffCheckpoint? = nil,
        submittedActions: [ProjectedPlayerAction] = [],
        gmStatus: GMStatusChangedPayload? = nil,
        gmMessages: [GMMessageCommittedPayload] = [],
        pendingDecision: String? = nil,
        records: [String: [String: JSONValue]] = [:],
        clocks: [String: ClockUpdatedPayload] = [:],
        assetAttachments: [String: AssetAttachedPayload] = [:],
        pendingRolls: [UUID: RollRequestedPayload] = [:],
        resolvedRolls: [UUID: RollResolvedPayload] = [:],
        latestResolvedRollID: UUID? = nil,
        currentScene: SceneChangedPayload? = nil,
        voiceAssignments: [String: VoiceAssignmentChangedPayload] = [:],
        voiceSuggestions: [String: VoiceSuggestionProposedPayload] = [:],
        turnOutcomes: [ProjectedTurnOutcome] = [],
        lastTurnOutcome: ProjectedTurnOutcome? = nil,
        appliedEventIDs: Set<UUID> = [],
        appliedRequestIDs: Set<UUID> = [],
        currentRequestRunID: UUID? = nil,
        currentRequestRunDisposition: ProjectedRequestRunDisposition? = nil,
        activeTurnRequestID: UUID? = nil
    ) {
        self.campaignID = campaignID
        self.appliedThroughSequence = appliedThroughSequence
        self.campaignTitle = campaignTitle
        self.importedProjectID = importedProjectID
        self.importManifestHash = importManifestHash
        self.approvedHandoffCheckpoint = approvedHandoffCheckpoint
        self.submittedActions = submittedActions
        self.gmStatus = gmStatus
        self.gmMessages = gmMessages
        self.pendingDecision = pendingDecision
        self.records = records
        self.clocks = clocks
        self.assetAttachments = assetAttachments
        self.pendingRolls = pendingRolls
        self.resolvedRolls = resolvedRolls
        self.latestResolvedRollID = latestResolvedRollID
        self.currentScene = currentScene
        self.voiceAssignments = voiceAssignments
        self.voiceSuggestions = voiceSuggestions
        self.turnOutcomes = turnOutcomes
        self.lastTurnOutcome = lastTurnOutcome
        self.appliedEventIDs = appliedEventIDs
        self.appliedRequestIDs = appliedRequestIDs
        self.currentRequestRunID = currentRequestRunID
        self.currentRequestRunDisposition = currentRequestRunDisposition
        self.activeTurnRequestID = activeTurnRequestID
    }

    private enum CodingKeys: String, CodingKey {
        case campaignID, appliedThroughSequence, campaignTitle,
             importedProjectID, importManifestHash, approvedHandoffCheckpoint,
             submittedActions, gmStatus, gmMessages, pendingDecision, records,
             clocks, assetAttachments,
             pendingRolls, resolvedRolls, latestResolvedRollID, currentScene,
             voiceAssignments,
             voiceSuggestions, turnOutcomes, lastTurnOutcome, appliedEventIDs,
             appliedRequestIDs, currentRequestRunID, currentRequestRunDisposition,
             activeTurnRequestID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            campaignID: try container.decode(UUID.self, forKey: .campaignID),
            appliedThroughSequence: try container.decode(Int64.self, forKey: .appliedThroughSequence),
            campaignTitle: try container.decodeIfPresent(String.self, forKey: .campaignTitle),
            importedProjectID: try container.decodeIfPresent(String.self, forKey: .importedProjectID),
            importManifestHash: try container.decodeIfPresent(String.self, forKey: .importManifestHash),
            approvedHandoffCheckpoint: try container.decodeIfPresent(ApprovedHandoffCheckpoint.self, forKey: .approvedHandoffCheckpoint),
            submittedActions: try container.decodeIfPresent([ProjectedPlayerAction].self, forKey: .submittedActions) ?? [],
            gmStatus: try container.decodeIfPresent(GMStatusChangedPayload.self, forKey: .gmStatus),
            gmMessages: try container.decodeIfPresent([GMMessageCommittedPayload].self, forKey: .gmMessages) ?? [],
            pendingDecision: try container.decodeIfPresent(String.self, forKey: .pendingDecision),
            records: try container.decodeIfPresent([String: [String: JSONValue]].self, forKey: .records) ?? [:],
            clocks: try container.decodeIfPresent([String: ClockUpdatedPayload].self, forKey: .clocks) ?? [:],
            assetAttachments: try container.decodeIfPresent([String: AssetAttachedPayload].self, forKey: .assetAttachments) ?? [:],
            pendingRolls: try container.decodeIfPresent([UUID: RollRequestedPayload].self, forKey: .pendingRolls) ?? [:],
            resolvedRolls: try container.decodeIfPresent([UUID: RollResolvedPayload].self, forKey: .resolvedRolls) ?? [:],
            latestResolvedRollID: try container.decodeIfPresent(UUID.self, forKey: .latestResolvedRollID),
            currentScene: try container.decodeIfPresent(SceneChangedPayload.self, forKey: .currentScene),
            voiceAssignments: try container.decodeIfPresent([String: VoiceAssignmentChangedPayload].self, forKey: .voiceAssignments) ?? [:],
            voiceSuggestions: try container.decodeIfPresent([String: VoiceSuggestionProposedPayload].self, forKey: .voiceSuggestions) ?? [:],
            turnOutcomes: try container.decodeIfPresent([ProjectedTurnOutcome].self, forKey: .turnOutcomes) ?? [],
            lastTurnOutcome: try container.decodeIfPresent(ProjectedTurnOutcome.self, forKey: .lastTurnOutcome),
            appliedEventIDs: try container.decodeIfPresent(Set<UUID>.self, forKey: .appliedEventIDs) ?? [],
            appliedRequestIDs: try container.decodeIfPresent(Set<UUID>.self, forKey: .appliedRequestIDs) ?? [],
            currentRequestRunID: try container.decodeIfPresent(UUID.self, forKey: .currentRequestRunID),
            currentRequestRunDisposition: try container.decodeIfPresent(ProjectedRequestRunDisposition.self, forKey: .currentRequestRunDisposition),
            activeTurnRequestID: try container.decodeIfPresent(UUID.self, forKey: .activeTurnRequestID)
        )
    }
}
