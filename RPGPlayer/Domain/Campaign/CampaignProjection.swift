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
    public var pendingRolls: [UUID: RollRequestedPayload]
    public var resolvedRolls: [UUID: RollResolvedPayload]
    public var currentScene: SceneChangedPayload?
    public var voiceAssignments: [String: VoiceAssignmentChangedPayload]
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
        pendingRolls: [UUID: RollRequestedPayload] = [:],
        resolvedRolls: [UUID: RollResolvedPayload] = [:],
        currentScene: SceneChangedPayload? = nil,
        voiceAssignments: [String: VoiceAssignmentChangedPayload] = [:],
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
        self.pendingRolls = pendingRolls
        self.resolvedRolls = resolvedRolls
        self.currentScene = currentScene
        self.voiceAssignments = voiceAssignments
        self.turnOutcomes = turnOutcomes
        self.lastTurnOutcome = lastTurnOutcome
        self.appliedEventIDs = appliedEventIDs
        self.appliedRequestIDs = appliedRequestIDs
        self.currentRequestRunID = currentRequestRunID
        self.currentRequestRunDisposition = currentRequestRunDisposition
        self.activeTurnRequestID = activeTurnRequestID
    }
}
