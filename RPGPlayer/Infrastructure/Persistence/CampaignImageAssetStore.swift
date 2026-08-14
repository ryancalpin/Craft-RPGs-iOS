import CryptoKit
import Foundation

public enum CampaignImageAssetStoreError: Error, Equatable, Sendable {
    case emptyImageData
    case campaignDirectoryMissing(UUID)
    case invalidCampaignDirectory(UUID)
    case invalidAssetDirectory(URL)
    case existingAssetCorrupted(URL)
    case unableToCreateAssetDirectory
    case unableToWriteAsset
}

public actor CampaignImageAssetStore: CampaignImageAssetStoring {
    private let campaignDirectory: CampaignDirectory

    public init() {
        campaignDirectory = CampaignDirectory()
    }

    init(campaignDirectory: CampaignDirectory) {
        self.campaignDirectory = campaignDirectory
    }

    public func store(
        data: Data,
        for campaignID: UUID,
        targetRecordID: String,
        fieldID: String,
        format: GeneratedImageFormat
    ) async throws -> StoredCampaignImageAsset {
        guard data.isEmpty == false else {
            throw CampaignImageAssetStoreError.emptyImageData
        }

        let fileManager = FileManager.default
        let campaignURL = campaignDirectory.campaignURL(for: campaignID)
        guard campaignDirectory.isExactCampaignURL(
            campaignURL,
            for: campaignID
        ) else {
            throw CampaignImageAssetStoreError.invalidCampaignDirectory(
                campaignID
            )
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: campaignURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw CampaignImageAssetStoreError.campaignDirectoryMissing(
                campaignID
            )
        }
        guard campaignURL.resolvingSymlinksInPath().standardizedFileURL
            == campaignURL.standardizedFileURL else {
            throw CampaignImageAssetStoreError.invalidCampaignDirectory(
                campaignID
            )
        }

        let sha256 = Self.sha256(of: data)
        let generatedDirectoryURL = campaignURL
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("generated", isDirectory: true)
        do {
            try fileManager.createDirectory(
                at: generatedDirectoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw CampaignImageAssetStoreError.unableToCreateAssetDirectory
        }

        guard generatedDirectoryURL.resolvingSymlinksInPath()
            .standardizedFileURL == generatedDirectoryURL.standardizedFileURL
        else {
            throw CampaignImageAssetStoreError.invalidAssetDirectory(
                generatedDirectoryURL
            )
        }

        let fileName = "\(sha256).\(format.rawValue)"
        let fileURL = generatedDirectoryURL.appendingPathComponent(
            fileName,
            isDirectory: false
        )
        guard fileURL.resolvingSymlinksInPath().standardizedFileURL
            == fileURL.standardizedFileURL else {
            throw CampaignImageAssetStoreError.invalidAssetDirectory(fileURL)
        }

        if fileManager.fileExists(atPath: fileURL.path) {
            guard let existingData = try? Data(contentsOf: fileURL),
                  Self.sha256(of: existingData) == sha256 else {
                throw CampaignImageAssetStoreError.existingAssetCorrupted(
                    fileURL
                )
            }
        } else {
            do {
                try data.write(to: fileURL, options: .atomic)
            } catch {
                throw CampaignImageAssetStoreError.unableToWriteAsset
            }
        }

        let relativePath = "Campaigns/\(campaignID.uuidString.lowercased())/"
            + "assets/generated/\(fileName)"
        let asset = ImportedAsset(
            assetID: "generated-image-\(sha256)",
            sha256: sha256,
            appRelativeURL: URL(string: relativePath)!
        )
        let attachment = AssetAttachedPayload(
            assetID: asset.assetID,
            targetRecordID: targetRecordID,
            fieldID: fieldID
        )
        return StoredCampaignImageAsset(
            asset: asset,
            attachment: attachment,
            fileURL: fileURL
        )
    }

    private static func sha256(of data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
