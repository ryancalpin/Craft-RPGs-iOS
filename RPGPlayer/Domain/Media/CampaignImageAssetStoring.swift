import Foundation

public enum GeneratedImageFormat: String, Codable, CaseIterable, Sendable {
    case png
    case jpeg
    case webp
    case gif
    case heic
    case heif
    case avif
}

public struct StoredCampaignImageAsset: Equatable, Sendable {
    public let asset: ImportedAsset
    public let attachment: AssetAttachedPayload
    public let fileURL: URL

    public var eventPayload: CampaignEventPayload {
        .assetAttached(attachment)
    }

    public init(
        asset: ImportedAsset,
        attachment: AssetAttachedPayload,
        fileURL: URL
    ) {
        self.asset = asset
        self.attachment = attachment
        self.fileURL = fileURL
    }
}

public protocol CampaignImageAssetStoring: Sendable {
    func store(
        data: Data,
        for campaignID: UUID,
        targetRecordID: String,
        fieldID: String,
        format: GeneratedImageFormat
    ) async throws -> StoredCampaignImageAsset
}
