import Foundation

enum PlayerMode: String, Codable, Equatable, Sendable {
    case transcript
    case visualNovel
}

enum PlayerDrawer: Equatable, Sendable {
    case none
    case project
    case overview
}

struct DialogueBlock: Identifiable, Equatable, Sendable {
    let id: UUID
    let speaker: String
    let mood: String?
    let text: String
}

public struct VisualNovelBeat: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case title
        case narration
        case dialogue
    }

    public let id: UUID
    public let kind: Kind
    public let title: String?
    public let subtitle: String?
    public let speaker: String?
    public let mood: String?
    public let text: String

    public init(
        id: UUID,
        kind: Kind,
        title: String?,
        subtitle: String?,
        speaker: String?,
        mood: String?,
        text: String
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.speaker = speaker
        self.mood = mood
        self.text = text
    }
}

struct GMMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let prose: [String]
    let dialogue: [DialogueBlock]
    let actionCount: Int
    let finalQuestion: String
    let beats: [VisualNovelBeat]
}

struct PlayerChoice: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let detail: String
}

struct PlayerSubmission: Equatable, Sendable {
    let action: String
    let additionalContext: String
}
