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
    let transcript: [TranscriptBlock]
    let actionCount: Int
    let finalQuestion: String
    let beats: [VisualNovelBeat]

    init(
        id: UUID,
        prose: [String],
        dialogue: [DialogueBlock],
        actionCount: Int,
        finalQuestion: String,
        beats: [VisualNovelBeat],
        transcript: [TranscriptBlock]? = nil
    ) {
        self.id = id
        self.prose = prose
        self.dialogue = dialogue
        self.transcript = transcript ?? TranscriptBlock.legacy(
            prose: prose,
            dialogue: dialogue
        )
        self.actionCount = actionCount
        self.finalQuestion = finalQuestion
        self.beats = beats
    }
}

struct TranscriptBlock: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case narration
        case dialogue
    }

    let id: UUID
    let kind: Kind
    let speaker: String?
    let mood: String?
    let text: String

    static func legacy(
        prose: [String],
        dialogue: [DialogueBlock]
    ) -> [TranscriptBlock] {
        let narration = prose.enumerated().map { index, text in
            TranscriptBlock(
                id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index))!,
                kind: .narration,
                speaker: nil,
                mood: nil,
                text: text
            )
        }
        return narration + dialogue.map {
            TranscriptBlock(
                id: $0.id,
                kind: .dialogue,
                speaker: $0.speaker,
                mood: $0.mood,
                text: $0.text
            )
        }
    }
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
