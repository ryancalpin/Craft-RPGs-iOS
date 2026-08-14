import Foundation

/// Routes narration to Apple Speech or ElevenLabs, with the configured
/// provider fallback used only when the preferred provider fails.
public actor SpeechRoutingProvider: SpeechSynthesizer {
    public nonisolated let providerID: VoiceProviderID = .appleSpeech

    private var settings: VoiceRoutingSettings
    private let providers: [VoiceProviderID: any SpeechSynthesizer]

    public init(
        settings: VoiceRoutingSettings = .default,
        providers: [VoiceProviderID: any SpeechSynthesizer]
    ) {
        self.settings = settings
        self.providers = providers
    }

    public func update(settings: VoiceRoutingSettings) {
        self.settings = settings
    }

    public func synthesize(
        _ request: SpeechSynthesisRequest
    ) async throws -> SpeechSynthesisResult {
        let routes = routeCandidates(preferred: request.providerID)
        guard let primary = providers[routes[0]] else {
            throw SpeechSynthesisError.failed
        }

        do {
            return try await primary.synthesize(request)
        } catch {
            guard settings.automaticFallbackEnabled,
                  routes.count > 1,
                  Self.isFallbackEligible(error),
                  let fallback = providers[routes[1]] else {
                throw error
            }
            var fallbackRequest = request
            fallbackRequest = SpeechSynthesisRequest(
                text: request.text,
                providerID: routes[1],
                voiceID: request.voiceID,
                language: request.language,
                modelID: request.modelID,
                outputFormat: request.outputFormat,
                settings: request.settings
            )
            return try await fallback.synthesize(fallbackRequest)
        }
    }

    private func routeCandidates(
        preferred: VoiceProviderID?
    ) -> [VoiceProviderID] {
        var result: [VoiceProviderID] = []
        for provider in [preferred, settings.provider, settings.fallback]
        where provider != nil {
            if let provider, result.contains(provider) == false {
                result.append(provider)
            }
        }
        return result.isEmpty ? [.appleSpeech] : result
    }

    private static func isFallbackEligible(_ error: Error) -> Bool {
        guard let error = error as? SpeechSynthesisError else {
            return true
        }
        switch error {
        case SpeechSynthesisError.blankText,
             SpeechSynthesisError.missingVoiceID,
             SpeechSynthesisError.missingModelID,
             SpeechSynthesisError.cancelled:
            return false
        default:
            return true
        }
    }
}
