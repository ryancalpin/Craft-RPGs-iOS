import Foundation
import Testing
@testable import RPGPlayer

struct VoiceContractTests {
    @Test
    func voiceRoutingPreferencesPersistWithoutCredentials() async throws {
        let suiteName = "voice-routing-(UUID().uuidString)"
        let store = UserDefaultsVoiceRoutingStore(suiteName: suiteName)
        let settings = VoiceRoutingSettings(
            provider: .elevenLabs,
            fallback: .appleSpeech,
            modelID: "eleven_multilingual_v2",
            automaticFallbackEnabled: false
        )

        try await store.save(settings)
        let loaded = try await UserDefaultsVoiceRoutingStore(
            suiteName: suiteName
        ).load()

        #expect(loaded == settings)
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(
            forName: suiteName
        )
    }

    @Test
    func voiceTargetsHaveStableCampaignStorageKeys() throws {
        let targets: [VoiceTarget] = [
            .narrator,
            .gm,
            .player,
            .character("npc-42")
        ]

        for target in targets {
            let data = try JSONEncoder().encode(target)
            let decoded = try JSONDecoder().decode(VoiceTarget.self, from: data)
            #expect(decoded == target)
            #expect(target.storageKey.isEmpty == false)
        }

        #expect(VoiceTarget.character("npc-42").storageKey == "npc-42")
    }

    @Test
    func acceptedSuggestionsCannotReplaceManualVoiceAssignments() throws {
        let manual = VoiceAssignment(
            target: .character("npc-42"),
            providerID: .elevenLabs,
            voiceID: "manual-voice",
            displayName: "Manual voice",
            source: .manual
        )
        let suggestion = VoiceAssignment(
            target: .character("npc-42"),
            providerID: .elevenLabs,
            voiceID: "suggested-voice",
            displayName: "Suggested voice",
            source: .acceptedSuggestion
        )

        #expect(
            VoiceAssignmentPolicy.accept(
                suggestion,
                existing: manual
            ) == manual
        )
    }

    @Test
    func voiceCredentialReferenceUsesASeparateNamespace() throws {
        let reference = try VoiceCredentialReference(providerID: .elevenLabs)

        #expect(reference.providerID == .elevenLabs)
        #expect(reference.accountLabel == "primary")
    }
}
