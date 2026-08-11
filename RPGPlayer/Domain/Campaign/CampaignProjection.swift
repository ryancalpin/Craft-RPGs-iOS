import Foundation

public struct CampaignProjection: Codable, Equatable, Sendable {
    public let campaignID: UUID
    public var appliedThroughSequence: Int64
    public var campaignTitle: String?

    public init(
        campaignID: UUID,
        appliedThroughSequence: Int64 = 0,
        campaignTitle: String? = nil
    ) {
        self.campaignID = campaignID
        self.appliedThroughSequence = appliedThroughSequence
        self.campaignTitle = campaignTitle
    }
}
