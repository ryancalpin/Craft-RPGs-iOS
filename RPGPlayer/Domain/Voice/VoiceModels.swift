import Foundation

public enum VoiceProviderID: String, Codable, CaseIterable, Hashable, Sendable {
    case appleSpeech
    case elevenLabs
}

public enum VoiceTarget: Codable, Equatable, Hashable, Sendable {
    case narrator
    case gm
    case player
    case character(String)

    public var storageKey: String {
        switch self {
        case .narrator:
            "narrator"
        case .gm:
            "gm"
        case .player:
            "player"
        case .character(let id):
            id
        }
    }

    public var displayName: String {
        switch self {
        case .narrator:
            "Narrator"
        case .gm:
            "GM"
        case .player:
            "Player character"
        case .character(let id):
            id
        }
    }
}

public struct VoiceDescriptor: Codable, Identifiable, Equatable, Sendable {
    public let providerID: VoiceProviderID
    public let id: String
    public let displayName: String
    public let language: String?
    public let category: String?
    public let previewURL: URL?
    public let supportsStreaming: Bool

    public init(
        providerID: VoiceProviderID,
        id: String,
        displayName: String,
        language: String? = nil,
        category: String? = nil,
        previewURL: URL? = nil,
        supportsStreaming: Bool = false
    ) {
        self.providerID = providerID
        self.id = id
        self.displayName = displayName
        self.language = language
        self.category = category
        self.previewURL = previewURL
        self.supportsStreaming = supportsStreaming
    }
}

public struct VoiceAssignment: Codable, Equatable, Sendable {
    public let target: VoiceTarget
    public let providerID: VoiceProviderID
    public let voiceID: String
    public let displayName: String
    public let source: VoiceAssignmentSource

    public init(
        target: VoiceTarget,
        providerID: VoiceProviderID,
        voiceID: String,
        displayName: String,
        source: VoiceAssignmentSource
    ) {
        self.target = target
        self.providerID = providerID
        self.voiceID = voiceID
        self.displayName = displayName
        self.source = source
    }
}

public enum VoiceAssignmentEventFactory {
    public static func manualEvent(
        campaignID: UUID,
        target: VoiceTarget,
        providerID: VoiceProviderID? = nil,
        voiceID: String?,
        requestID: UUID = UUID(),
        timestamp: Date = Date()
    ) -> CampaignEvent {
        CampaignEvent(
            id: UUID(),
            campaignID: campaignID,
            sequence: 0,
            requestID: requestID,
            timestamp: timestamp,
            schemaVersion: 1,
            payload: .voiceAssignmentChanged(
                VoiceAssignmentChangedPayload(
                    characterID: target.storageKey,
                    providerID: providerID,
                    voiceID: voiceID,
                    source: .manual
                )
            )
        )
    }
}

public enum VoiceAssignmentPolicy {
    public static func accept(
        _ candidate: VoiceAssignment,
        existing: VoiceAssignment?
    ) -> VoiceAssignment {
        guard let existing,
              existing.source == .manual,
              candidate.source == .acceptedSuggestion else {
            return candidate
        }
        return existing
    }
}

public struct VoiceRoutingSettings: Codable, Equatable, Sendable {
    public var provider: VoiceProviderID
    public var fallback: VoiceProviderID?
    public var modelID: String
    public var automaticFallbackEnabled: Bool

    public init(
        provider: VoiceProviderID,
        fallback: VoiceProviderID? = nil,
        modelID: String = "eleven_multilingual_v2",
        automaticFallbackEnabled: Bool = true
    ) {
        self.provider = provider
        self.fallback = fallback == provider ? nil : fallback
        self.modelID = modelID
        self.automaticFallbackEnabled = automaticFallbackEnabled
    }

    public static let `default` = VoiceRoutingSettings(
        provider: .appleSpeech,
        fallback: nil
    )
}

public enum VoiceModelCatalog {
    public static let elevenLabs: [(id: String, displayName: String)] = [
        ("eleven_multilingual_v2", "Multilingual v2"),
        ("eleven_turbo_v2_5", "Turbo v2.5")
    ]
}

public protocol VoiceRoutingSettingsStore: Sendable {
    func load() async throws -> VoiceRoutingSettings
    func save(_ settings: VoiceRoutingSettings) async throws
}

public struct UserDefaultsVoiceRoutingStore: VoiceRoutingSettingsStore,
    Sendable
{
    public static let key = "rpgplayer.voice-routing.v1"

    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    public func load() async throws -> VoiceRoutingSettings {
        guard let data = defaults.data(forKey: Self.key) else {
            return .default
        }
        do {
            return try JSONDecoder().decode(VoiceRoutingSettings.self, from: data)
        } catch {
            throw ModelRoutingStoreError.corruptSettings
        }
    }

    public func save(_ settings: VoiceRoutingSettings) async throws {
        defaults.set(try JSONEncoder().encode(settings), forKey: Self.key)
    }

    private var defaults: UserDefaults {
        if let suiteName, let suite = UserDefaults(suiteName: suiteName) {
            return suite
        }
        return .standard
    }
}
