import CryptoKit
import Foundation
import Testing
@testable import RPGPlayer

struct CampaignImageAssetStoreTests {
    @Test
    func storesBytesInsideTheExactCampaignScopedGeneratedDirectory() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = CampaignImageAssetStore(
            campaignDirectory: fixture.campaignDirectory
        )

        let result = try await store.store(
            data: fixture.imageData,
            for: fixture.campaignID,
            targetRecordID: "scene-1",
            fieldID: "portrait",
            format: .png
        )

        let hash = SHA256.hash(data: fixture.imageData)
            .map { String(format: "%02x", $0) }
            .joined()
        let expectedRelativePath = URL(
            string:
                "Campaigns/\(fixture.campaignID.uuidString.lowercased())/assets/generated/\(hash).png"
        )!
        let expectedFileURL = fixture.campaignURL
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("generated", isDirectory: true)
            .appendingPathComponent("\(hash).png", isDirectory: false)

        #expect(result.asset.appRelativeURL == expectedRelativePath)
        #expect(result.fileURL == expectedFileURL)
        #expect(result.asset.appRelativeURL.scheme == nil)
        #expect(result.asset.appRelativeURL.path.hasPrefix("/") == false)
        #expect(result.asset.appRelativeURL.pathComponents.contains("..") == false)
        #expect(FileManager.default.fileExists(atPath: result.fileURL.path))
        #expect(try Data(contentsOf: result.fileURL) == fixture.imageData)
    }

    @Test
    func storesTheSameContentAtTheSameDeterministicPath() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = CampaignImageAssetStore(
            campaignDirectory: fixture.campaignDirectory
        )

        let first = try await store.store(
            data: fixture.imageData,
            for: fixture.campaignID,
            targetRecordID: "scene-1",
            fieldID: "portrait",
            format: .png
        )
        let second = try await store.store(
            data: fixture.imageData,
            for: fixture.campaignID,
            targetRecordID: "character-1",
            fieldID: "portrait",
            format: .png
        )

        #expect(first.asset == second.asset)
        #expect(first.fileURL == second.fileURL)
        #expect(first.attachment != second.attachment)
        #expect(
            try FileManager.default.contentsOfDirectory(
                at: fixture.campaignURL.appendingPathComponent(
                    "assets/generated",
                    isDirectory: true
                ),
                includingPropertiesForKeys: nil
            ).count == 1
        )
    }

    @Test
    func returnsImportedAssetAndAssetAttachedEventMetadata() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = CampaignImageAssetStore(
            campaignDirectory: fixture.campaignDirectory
        )

        let result = try await store.store(
            data: fixture.imageData,
            for: fixture.campaignID,
            targetRecordID: "scene-1",
            fieldID: "mapAsset",
            format: .webp
        )

        #expect(result.asset.assetID.hasPrefix("generated-image-"))
        #expect(result.asset.sha256.count == 64)
        #expect(result.asset.sha256.allSatisfy { $0.isHexDigit })
        #expect(
            result.attachment == AssetAttachedPayload(
                assetID: result.asset.assetID,
                targetRecordID: "scene-1",
                fieldID: "mapAsset"
            )
        )
        #expect(
            result.eventPayload == .assetAttached(result.attachment)
        )
        #expect(result.asset.appRelativeURL.pathExtension == "webp")
    }

    @Test
    func doesNotCreateAPathForAnUnknownCampaign() async throws {
        let fixture = try Fixture(createCampaignDirectory: false)
        defer { fixture.remove() }
        let store = CampaignImageAssetStore(
            campaignDirectory: fixture.campaignDirectory
        )

        await #expect(
            throws: CampaignImageAssetStoreError.campaignDirectoryMissing(
                fixture.campaignID
            )
        ) {
            _ = try await store.store(
                data: fixture.imageData,
                for: fixture.campaignID,
                targetRecordID: "scene-1",
                fieldID: "portrait",
                format: .png
            )
        }

        #expect(
            FileManager.default.fileExists(
                atPath: fixture.campaignDirectory.campaignURL(
                    for: fixture.campaignID
                ).path
            ) == false
        )
    }
}

private struct Fixture {
    let rootURL: URL
    let applicationSupportURL: URL
    let campaignID: UUID
    let campaignDirectory: CampaignDirectory
    let campaignURL: URL
    let imageData = Data([0x89, 0x50, 0x4e, 0x47, 0x00, 0x01])

    init(createCampaignDirectory: Bool = true) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CampaignImageAssetStoreTests-\(UUID().uuidString)",
                isDirectory: true
            )
        applicationSupportURL = rootURL.appendingPathComponent(
            "ApplicationSupport",
            isDirectory: true
        )
        campaignID = UUID()
        campaignDirectory = CampaignDirectory(
            applicationSupportDirectory: applicationSupportURL
        )
        campaignURL = campaignDirectory.campaignURL(for: campaignID)

        try FileManager.default.createDirectory(
            at: applicationSupportURL,
            withIntermediateDirectories: true
        )
        if createCampaignDirectory {
            try FileManager.default.createDirectory(
                at: campaignURL,
                withIntermediateDirectories: true
            )
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
