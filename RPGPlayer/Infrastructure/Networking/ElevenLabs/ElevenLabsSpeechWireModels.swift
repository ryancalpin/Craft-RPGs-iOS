import Foundation

enum ElevenLabsSpeechWire {
    struct Request: Encodable {
        let text: String
        let modelID: String
        let voiceSettings: VoiceSettings

        private enum CodingKeys: String, CodingKey {
            case text
            case modelID = "model_id"
            case voiceSettings = "voice_settings"
        }
    }

    struct VoiceSettings: Encodable {
        let stability: Double
        let similarityBoost: Double
        let style: Double
        let useSpeakerBoost: Bool

        private enum CodingKeys: String, CodingKey {
            case stability
            case similarityBoost = "similarity_boost"
            case style
            case useSpeakerBoost = "use_speaker_boost"
        }
    }
}
