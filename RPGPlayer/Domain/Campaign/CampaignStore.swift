import Foundation

public protocol CampaignStore: Sendable {
    func append(
        batch: [CampaignEvent],
        assets: [ImportedAsset],
        expectedSequence: Int64
    ) async throws -> [CampaignEvent]

    func events(
        for campaignID: UUID,
        after sequence: Int64,
        limit: Int
    ) async throws -> [CampaignEvent]

    func latestSequence(for campaignID: UUID) async throws -> Int64

    func importedAssets(for campaignID: UUID) async throws -> [ImportedAsset]

    func deleteCampaign(_ campaignID: UUID) async throws
}

public extension CampaignStore {
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
    case invalidImportedAssetURL(URL)
    case persistenceFailure
}
