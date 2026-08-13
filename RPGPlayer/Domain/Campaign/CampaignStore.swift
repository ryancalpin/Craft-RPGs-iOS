import Foundation

public protocol CampaignStore: Sendable {
    func campaigns() async throws -> [CampaignSummary]

    func append(
        batch: [CampaignEvent],
        assets: [ImportedAsset],
        expectedSequence: Int64
    ) async throws -> [CampaignEvent]

    /// Appends the single canonical resolution for a pending roll. A roll
    /// continues the turn request lineage after the original atomic run, so
    /// stores may apply a stricter, lineage-aware duplicate check here.
    func appendRollResolution(
        batch: [CampaignEvent],
        expectedSequence: Int64
    ) async throws -> [CampaignEvent]

    func events(
        for campaignID: UUID,
        after sequence: Int64,
        limit: Int
    ) async throws -> [CampaignEvent]

    func latestSequence(for campaignID: UUID) async throws -> Int64

    func importedAssets(for campaignID: UUID) async throws -> [ImportedAsset]

    func saveProjectionCheckpoint(
        _ checkpoint: ProjectionCheckpoint
    ) async throws

    func latestProjectionCheckpoint(
        for campaignID: UUID,
        reducerSchemaVersion: Int
    ) async throws -> ProjectionCheckpoint?

    func restoreCampaign(
        events: [CampaignEvent],
        assets: [ImportedAsset]
    ) async throws

    func deleteCampaign(_ campaignID: UUID) async throws
}

public extension CampaignStore {
    func appendRollResolution(
        batch: [CampaignEvent],
        expectedSequence: Int64
    ) async throws -> [CampaignEvent] {
        try await append(
            batch: batch,
            assets: [],
            expectedSequence: expectedSequence
        )
    }

    func append(
        batch: [CampaignEvent],
        expectedSequence: Int64
    ) async throws -> [CampaignEvent] {
        try await append(
            batch: batch,
            assets: [],
            expectedSequence: expectedSequence
        )
    }

    func restoreCampaign(
        events: [CampaignEvent],
        assets: [ImportedAsset]
    ) async throws {
        throw CampaignStoreError.persistenceFailure
    }
}

public struct CampaignSummary: Identifiable, Codable, Equatable, Sendable {
    public let campaignID: UUID
    public let title: String
    public let projectID: String
    public let importedAt: Date

    public var id: UUID { campaignID }

    public init(
        campaignID: UUID,
        title: String,
        projectID: String,
        importedAt: Date
    ) {
        self.campaignID = campaignID
        self.title = title
        self.projectID = projectID
        self.importedAt = importedAt
    }
}

public struct ImportedAsset: Identifiable, Codable, Equatable, Sendable {
    public let assetID: String
    public let sha256: String
    public let appRelativeURL: URL

    public var id: String { assetID }

    public init(assetID: String, sha256: String, appRelativeURL: URL) {
        self.assetID = assetID
        self.sha256 = sha256
        self.appRelativeURL = appRelativeURL
    }
}

public enum CampaignStoreError: Error, Equatable, Sendable {
    case mixedCampaignBatch
    case mixedRequestBatch
    case duplicateEventID(UUID)
    case duplicateRequestID(UUID)
    case expectedSequenceConflict(expected: Int64, actual: Int64)
    case unsupportedSchemaVersion(eventID: UUID, version: Int)
    case invalidPayload(eventID: UUID)
    case invalidStoredPayload(eventID: UUID)
    case invalidProjectionCheckpoint(sourceSequence: Int64)
    case invalidImportedAssetURL(URL)
    case invalidRestoreSequence(expected: Int64, actual: Int64)
    case campaignAlreadyExists(UUID)
    case persistenceFailure
}
