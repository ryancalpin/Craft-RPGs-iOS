import Foundation

public struct SpeechCacheKey: Codable, Equatable, Hashable, Sendable {
    public let text: String
    public let providerID: VoiceProviderID
    public let voiceID: String?
    public let modelID: String
    public let outputFormat: SpeechAudioFormat

    public init(
        text: String,
        providerID: VoiceProviderID,
        voiceID: String?,
        modelID: String,
        outputFormat: SpeechAudioFormat
    ) {
        self.text = text
        self.providerID = providerID
        self.voiceID = voiceID
        self.modelID = modelID
        self.outputFormat = outputFormat
    }
}

public protocol SpeechAudioCaching: Sendable {
    func audio(
        for key: SpeechCacheKey,
        campaignID: UUID
    ) async throws -> Data?

    func store(
        _ data: Data,
        for key: SpeechCacheKey,
        campaignID: UUID
    ) async throws

    func deleteAudioCache(for campaignID: UUID) async throws
}
