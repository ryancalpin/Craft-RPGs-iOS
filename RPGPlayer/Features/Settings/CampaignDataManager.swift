import Foundation

protocol CampaignAudioCacheDeleting: Sendable {
    func deleteAudioCache(for campaignID: UUID) async throws
}

protocol CampaignKeyReferenceDeleting: Sendable {
    /// Removes only campaign-to-key associations. Provider credentials are
    /// shared configuration and are never owned by campaign deletion.
    func deleteCampaignAssociations(for campaignID: UUID) async throws
}

struct NoOpCampaignAudioCacheDeleter: CampaignAudioCacheDeleting {
    func deleteAudioCache(for campaignID: UUID) async throws {}
}

struct NoOpCampaignKeyReferenceDeleter: CampaignKeyReferenceDeleting {
    func deleteCampaignAssociations(for campaignID: UUID) async throws {}
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
        audioCache: any CampaignAudioCacheDeleting = NoOpCampaignAudioCacheDeleter(),
        keyReferences: any CampaignKeyReferenceDeleting = NoOpCampaignKeyReferenceDeleter()
    ) {
        self.store = store
        self.campaignDirectory = campaignDirectory
        self.audioCache = audioCache
        self.keyReferences = keyReferences
    }

    func deleteCampaign(_ campaignID: UUID) async throws {
        let directoryURL = campaignDirectory.campaignURL(for: campaignID)
        guard campaignDirectory.isExactCampaignURL(
            directoryURL,
            for: campaignID
        ) else {
            throw CampaignDataError.invalidCampaignDirectory
        }

        try await store.deleteCampaign(campaignID)

        if FileManager.default.fileExists(atPath: directoryURL.path) {
            do {
                try FileManager.default.removeItem(at: directoryURL)
            } catch {
                throw CampaignDataError.unableToDeleteCampaignDirectory
            }
        }
        try await audioCache.deleteAudioCache(for: campaignID)
        try await keyReferences.deleteCampaignAssociations(for: campaignID)
    }
}
