import Foundation

protocol CampaignAudioCacheDeleting: Sendable {
    func deleteAudioCache(for campaignID: UUID) async throws
}

protocol CampaignKeyReferenceDeleting: Sendable {
    /// Removes only campaign-to-key associations. Provider credentials are
    /// shared configuration and are never owned by campaign deletion.
    func deleteCampaignAssociations(for campaignID: UUID) async throws
}

extension FileSpeechAudioCache: CampaignAudioCacheDeleting {}

struct FileCampaignKeyReferenceDeleter: CampaignKeyReferenceDeleting {
    private let campaignDirectory: CampaignDirectory

    init(campaignDirectory: CampaignDirectory) {
        self.campaignDirectory = campaignDirectory
    }

    func deleteCampaignAssociations(for campaignID: UUID) async throws {
        let campaignURL = campaignDirectory.campaignURL(for: campaignID)
        guard campaignDirectory.isExactCampaignURL(
            campaignURL,
            for: campaignID
        ) else {
            throw CampaignDataError.invalidCampaignDirectory
        }

        let referenceURL = campaignURL.appendingPathComponent(
            "key-references.json",
            isDirectory: false
        )
        guard FileManager.default.fileExists(atPath: referenceURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: referenceURL)
    }
}

enum CampaignDataError: Error, Equatable, Sendable {
    case invalidCampaignDirectory
    case unableToDeleteCampaignDirectory
}

struct CampaignDataManager: Sendable {
    private let store: any CampaignStore
    private let campaignDirectory: CampaignDirectory
    private let audioCache: any CampaignAudioCacheDeleting
    private let keyReferences: any CampaignKeyReferenceDeleting

    init(
        store: any CampaignStore,
        campaignDirectory: CampaignDirectory = CampaignDirectory(),
        audioCache: (any CampaignAudioCacheDeleting)? = nil,
        keyReferences: (any CampaignKeyReferenceDeleting)? = nil
    ) {
        self.store = store
        self.campaignDirectory = campaignDirectory
        self.audioCache = audioCache ?? FileSpeechAudioCache(
            campaignDirectory: campaignDirectory
        )
        self.keyReferences = keyReferences ?? FileCampaignKeyReferenceDeleter(
            campaignDirectory: campaignDirectory
        )
    }

    func deleteCampaign(_ campaignID: UUID) async throws {
        let directoryURL = campaignDirectory.campaignURL(for: campaignID)
        guard campaignDirectory.isExactCampaignURL(
            directoryURL,
            for: campaignID
        ) else {
            throw CampaignDataError.invalidCampaignDirectory
        }

        try await audioCache.deleteAudioCache(for: campaignID)
        try await keyReferences.deleteCampaignAssociations(for: campaignID)
        try await store.deleteCampaign(campaignID)

        if FileManager.default.fileExists(atPath: directoryURL.path) {
            do {
                try FileManager.default.removeItem(at: directoryURL)
            } catch {
                throw CampaignDataError.unableToDeleteCampaignDirectory
            }
        }
    }
}
