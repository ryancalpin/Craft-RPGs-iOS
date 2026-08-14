import AVFoundation
import Foundation

@MainActor
final class NarrationPlaybackCoordinator: NSObject, AVAudioPlayerDelegate {
    private let synthesizer: any SpeechSynthesizer
    private let cache: any SpeechAudioCaching
    private let routingStore: (any VoiceRoutingSettingsStore)?
    private var audioPlayer: AVAudioPlayer?
    private var playbackContinuation: CheckedContinuation<Void, Error>?
    private var task: Task<Void, Never>?

    init(
        synthesizer: any SpeechSynthesizer,
        cache: any SpeechAudioCaching,
        routingStore: (any VoiceRoutingSettingsStore)? = nil
    ) {
        self.synthesizer = synthesizer
        self.cache = cache
        self.routingStore = routingStore
    }

    func play(
        text: String,
        campaignID: UUID,
        providerID: VoiceProviderID? = nil,
        voiceID: String? = nil,
        language: String? = nil,
        modelID: String = "eleven_multilingual_v2"
    ) {
        stop()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await playNow(
                    text: trimmed,
                    campaignID: campaignID,
                    providerID: providerID,
                    voiceID: voiceID,
                    language: language,
                    modelID: modelID
                )
            } catch is CancellationError {
                return
            } catch {
                // Narration is supplemental and must never interrupt play.
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        audioPlayer?.stop()
        audioPlayer = nil
        if let continuation = playbackContinuation {
            playbackContinuation = nil
            continuation.resume(throwing: CancellationError())
        }
    }

    private func playNow(
        text: String,
        campaignID: UUID,
        providerID: VoiceProviderID?,
        voiceID: String?,
        language: String?,
        modelID: String
    ) async throws {
        let format: SpeechAudioFormat = .mp3_44100_128
        if let providerID {
            let requestedKey = SpeechCacheKey(
                text: text,
                providerID: providerID,
                voiceID: voiceID,
                modelID: modelID,
                outputFormat: format
            )
            if let cached = try await cache.audio(
                for: requestedKey,
                campaignID: campaignID
            ) {
                try await playAudio(cached)
                return
            }
        }
        if let routingStore,
           let settings = try? await routingStore.load(),
           let routing = synthesizer as? SpeechRoutingProvider {
            await routing.update(settings: settings)
        }
        let request = SpeechSynthesisRequest(
            providerID: providerID,
            text: text,
            voiceID: voiceID,
            language: language,
            modelID: modelID,
            outputFormat: format
        )
        let result = try await synthesizer.synthesize(request)
        try Task.checkCancellation()

        switch result.output {
        case .platformPlayback:
            return
        case .audio(let data, _):
            let key = SpeechCacheKey(
                text: text,
                providerID: result.providerID,
                voiceID: voiceID,
                modelID: modelID,
                outputFormat: format
            )
            if let cached = try await cache.audio(
                for: key,
                campaignID: campaignID
            ) {
                try await playAudio(cached)
                return
            }
            try await cache.store(data, for: key, campaignID: campaignID)
            try await playAudio(data)
        }
    }

    private func playAudio(_ data: Data) async throws {
        guard data.isEmpty == false else {
            throw SpeechSynthesisError.emptyAudio
        }
        try Task.checkCancellation()
        let player = try AVAudioPlayer(data: data)
        player.delegate = self
        player.prepareToPlay()
        guard player.play() else {
            throw SpeechSynthesisError.failed
        }
        audioPlayer = player
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                playbackContinuation = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.stop() }
        }
        audioPlayer = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        Task { @MainActor [weak self] in
            guard let self, let continuation = playbackContinuation else {
                return
            }
            playbackContinuation = nil
            continuation.resume(
                returning: flag ? () : ()
            )
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(
        _ player: AVAudioPlayer,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self, let continuation = playbackContinuation else {
                return
            }
            playbackContinuation = nil
            continuation.resume(throwing: error ?? SpeechSynthesisError.failed)
        }
    }
}
