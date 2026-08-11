import Foundation

public struct ProjectionCheckpoint: Codable, Equatable, Sendable {
    public let campaignID: UUID
    public let sourceSequence: Int64
    public let reducerSchemaVersion: Int
    public let projection: CampaignProjection

    public init(
        sourceSequence: Int64,
        reducerSchemaVersion: Int,
        projection: CampaignProjection
    ) {
        campaignID = projection.campaignID
        self.sourceSequence = sourceSequence
        self.reducerSchemaVersion = reducerSchemaVersion
        self.projection = projection
    }

    init(
        campaignID: UUID,
        sourceSequence: Int64,
        reducerSchemaVersion: Int,
        projection: CampaignProjection
    ) {
        self.campaignID = campaignID
        self.sourceSequence = sourceSequence
        self.reducerSchemaVersion = reducerSchemaVersion
        self.projection = projection
    }

    func isValid(
        for campaignID: UUID,
        latestSequence: Int64,
        reducerSchemaVersion: Int
    ) -> Bool {
        self.campaignID == campaignID
            && projection.campaignID == campaignID
            && sourceSequence == projection.appliedThroughSequence
            && sourceSequence >= 0
            && sourceSequence <= latestSequence
            && self.reducerSchemaVersion == reducerSchemaVersion
    }
}
