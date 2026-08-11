import Foundation
import SwiftData

@Model
final class ImportedAssetRecord {
    #Unique<ImportedAssetRecord>([\.campaignID, \.assetID])

    #Index<ImportedAssetRecord>(
        [\.campaignID],
        [\.campaignID, \.sha256]
    )

    var assetID: String
    var campaignID: UUID
    var sha256: String
    var appRelativeURL: String

    init(asset: ImportedAsset, campaignID: UUID) {
        assetID = asset.assetID
        self.campaignID = campaignID
        sha256 = asset.sha256
        appRelativeURL = asset.appRelativeURL.relativeString
    }
}
