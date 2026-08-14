import CryptoKit
import Foundation

actor FileSpeechAudioCache: SpeechAudioCaching {
    private let campaignDirectory: CampaignDirectory

    init(campaignDirectory: CampaignDirectory) {
        self.campaignDirectory = campaignDirectory
    }

    func audio(
        for key: SpeechCacheKey,
        campaignID: UUID
    ) throws -> Data? {
        let url = try fileURL(for: key, campaignID: campaignID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try Data(contentsOf: url)
    }

    func store(
        _ data: Data,
        for key: SpeechCacheKey,
        campaignID: UUID
    ) throws {
        guard data.isEmpty == false else { return }
        let url = try fileURL(for: key, campaignID: campaignID)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    func deleteAudioCache(for campaignID: UUID) throws {
        let url = try cacheDirectory(for: campaignID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }

    private func fileURL(
        for key: SpeechCacheKey,
        campaignID: UUID
    ) throws -> URL {
        let directory = try cacheDirectory(for: campaignID)
        let digest = SHA256.hash(data: Data(canonicalKey(key).utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let extensionName: String = switch key.outputFormat {
        case .pcm_16000: "pcm"
        case .mp3_44100_128, .mp3_22050_32: "mp3"
        }
        return directory
            .appendingPathComponent(digest + "." + extensionName)
            .standardizedFileURL
    }

    private func cacheDirectory(for campaignID: UUID) throws -> URL {
        let campaignURL = campaignDirectory.campaignURL(for: campaignID)
        guard campaignDirectory.isExactCampaignURL(
            campaignURL,
            for: campaignID
        ) else {
            throw CampaignDataError.invalidCampaignDirectory
        }
        return campaignURL
            .appendingPathComponent("NarrationCache", isDirectory: true)
            .standardizedFileURL
    }

    private func canonicalKey(_ key: SpeechCacheKey) -> String {
        [
            key.text,
            key.providerID.rawValue,
            key.voiceID ?? "",
            key.modelID,
            key.outputFormat.rawValue
        ].joined(separator: "\u{1f}")
    }
}
