import Foundation
import SwiftData

@Model
final class CampaignEventRecord {
    #Unique<CampaignEventRecord>(
        [\.campaignID, \.sequence],
        [\.campaignID, \.eventID]
    )

    #Index<CampaignEventRecord>(
        [\.campaignID, \.sequence],
        [\.campaignID, \.eventID],
        [\.campaignID, \.requestID],
        [\.payloadType]
    )

    var eventID: UUID
    var campaignID: UUID
    var sequence: Int64
    var requestID: UUID
    var timestamp: Date
    var schemaVersion: Int
    var payloadType: String
    var payloadData: Data

    init(event: CampaignEvent, payloadData: Data) {
        eventID = event.id
        campaignID = event.campaignID
        sequence = event.sequence
        requestID = event.requestID
        timestamp = event.timestamp
        schemaVersion = event.schemaVersion
        payloadType = event.payload.kind.rawValue
        self.payloadData = payloadData
    }
}
