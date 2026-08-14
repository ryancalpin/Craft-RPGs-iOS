import Foundation

public enum SpeechAudioFormat: String, Codable, CaseIterable, Sendable {
    case mp3_44100_128
    case mp3_22050_32
    case pcm_16000
}

public struct SpeechVoiceSettings: Codable, Equatable, Sendable {
    public let stability: Double
    public let similarityBoost: Double
    public let style: Double
    public let useSpeakerBoost: Bool
    public let rate: Float
    public let pitchMultiplier: Float
    public let volume: Float

    public init(
        stability: Double = 0.5,
        similarityBoost: Double = 0.75,
        style: Double = 0,
        useSpeakerBoost: Bool = true,
        rate: Float = 0.5,
        pitchMultiplier: Float = 1,
        volume: Float = 1
    ) {
        self.stability = stability
        self.similarityBoost = similarityBoost
        self.style = style
        self.useSpeakerBoost = useSpeakerBoost
        self.rate = rate
        self.pitchMultiplier = pitchMultiplier
        self.volume = volume
    }

    public static let `default` = SpeechVoiceSettings()
}

public struct SpeechSynthesisRequest: Codable, Equatable, Sendable {
    /// Campaign assignments can select a concrete provider. When nil, the
    /// global voice routing settings choose the provider.
    public let providerID: VoiceProviderID?
    public let text: String
    public let voiceID: String?
    public let language: String?
    public let modelID: String
    public let outputFormat: SpeechAudioFormat
    public let settings: SpeechVoiceSettings

    public init(
        text: String,
        providerID: VoiceProviderID? = nil,
        voiceID: String? = nil,
        language: String? = nil,
        modelID: String = "eleven_multilingual_v2",
        outputFormat: SpeechAudioFormat = .mp3_44100_128,
        settings: SpeechVoiceSettings = .default
    ) {
        self.providerID = providerID
        self.text = text
        self.voiceID = voiceID
        self.language = language
        self.modelID = modelID
        self.outputFormat = outputFormat
        self.settings = settings
    }

    public init(
        providerID: VoiceProviderID?,
        text: String,
        voiceID: String? = nil,
        language: String? = nil,
        modelID: String = "eleven_multilingual_v2",
        outputFormat: SpeechAudioFormat = .mp3_44100_128,
        settings: SpeechVoiceSettings = .default
    ) {
        self.init(
            text: text,
            providerID: providerID,
            voiceID: voiceID,
            language: language,
            modelID: modelID,
            outputFormat: outputFormat,
            settings: settings
        )
    }
}

public enum SpeechSynthesisOutput: Equatable, Sendable {
    case audio(data: Data, mimeType: String)
    case platformPlayback
}

public struct SpeechSynthesisResult: Equatable, Sendable {
    public let providerID: VoiceProviderID
    public let output: SpeechSynthesisOutput

    public init(
        providerID: VoiceProviderID,
        output: SpeechSynthesisOutput
    ) {
        self.providerID = providerID
        self.output = output
    }
}

public enum SpeechSynthesisError: Error, Equatable, Sendable {
    case blankText
    case missingVoiceID
    case missingModelID
    case emptyAudio
    case cancelled
    case failed
}

public protocol SpeechSynthesizer: Sendable {
    var providerID: VoiceProviderID { get }

    func synthesize(
        _ request: SpeechSynthesisRequest
    ) async throws -> SpeechSynthesisResult
}

public enum SpeechPlaybackPreferences {
    public static let automaticPlaybackKey =
        "rpgplayer.voice-automatic-playback.v1"

    public static var automaticallyPlayNarration: Bool {
        if UserDefaults.standard.object(
            forKey: automaticPlaybackKey
        ) == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: automaticPlaybackKey)
    }

    public static func setAutomaticallyPlayNarration(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: automaticPlaybackKey)
    }
}
