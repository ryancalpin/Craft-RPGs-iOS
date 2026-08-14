import Foundation
import Testing
@testable import RPGPlayer

struct SpeechAudioCacheTests {
    @Test
    func storesReadsAndDeletesCampaignScopedNarration() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeechAudioCacheTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = CampaignDirectory(
            applicationSupportDirectory: root
        )
        let campaignID = UUID()
        try FileManager.default.createDirectory(
            at: directory.campaignURL(for: campaignID),
            withIntermediateDirectories: true
        )
        let cache = FileSpeechAudioCache(campaignDirectory: directory)
        let key = SpeechCacheKey(
            text: "The bell answers.",
            providerID: .elevenLabs,
            voiceID: "voice-1",
            modelID: "eleven_multilingual_v2",
            outputFormat: .mp3_44100_128
        )
        let data = Data([0x49, 0x44, 0x33])

        try await cache.store(data, for: key, campaignID: campaignID)
        #expect(try await cache.audio(for: key, campaignID: campaignID) == data)

        try await cache.deleteAudioCache(for: campaignID)
        #expect(try await cache.audio(for: key, campaignID: campaignID) == nil)
    }
}
