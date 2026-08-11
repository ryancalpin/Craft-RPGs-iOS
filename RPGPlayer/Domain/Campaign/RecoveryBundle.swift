import Foundation

enum RecoveryBundle {
    static let schemaVersion = 1

    static let manifestPath = "manifest.json"
    static let eventsPath = "events.jsonl"
    static let manualVoiceMappingsPath = "manual-voice-mappings.json"
    static let normalizedProjectPath = "campaign/normalized-project.json"

    static let requiredEntryPaths = [
        manifestPath,
        eventsPath,
        manualVoiceMappingsPath,
        normalizedProjectPath
    ]
}

struct RecoveryBundleManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let campaignID: UUID
    let entries: [RecoveryBundleEntryDescriptor]

    init(
        schemaVersion: Int = RecoveryBundle.schemaVersion,
        campaignID: UUID,
        entries: [RecoveryBundleEntryDescriptor]
    ) {
        self.schemaVersion = schemaVersion
        self.campaignID = campaignID
        self.entries = entries
    }
}

struct RecoveryBundleEntryDescriptor: Codable, Equatable, Sendable {
    let path: String
    let byteCount: Int64
    let sha256: String
    let assetID: String?

    init(
        path: String,
        byteCount: Int64,
        sha256: String,
        assetID: String? = nil
    ) {
        self.path = path
        self.byteCount = byteCount
        self.sha256 = sha256
        self.assetID = assetID
    }
}

struct RecoveryVoiceMapping: Codable, Equatable, Sendable {
    let characterID: String
    let voiceID: String
}

enum RecoveryBundleError: Error, Equatable, Sendable {
    case campaignHasNoEvents(UUID)
    case missingCampaignFile(String)
    case invalidAssetPath(String)
    case assetHashMismatch(String)
    case unableToCreateArchive
    case invalidManifest
    case missingDeclaredEntry(String)
    case unexpectedEntry(String)
    case entryByteCountMismatch(String)
    case entryHashMismatch(String)
    case invalidEventLog
    case destinationAlreadyExists(UUID)
    case unableToMoveCampaign
    case persistenceFailed
}
