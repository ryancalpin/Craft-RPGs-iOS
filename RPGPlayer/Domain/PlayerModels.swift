import Foundation

enum PlayerMode: Equatable, Sendable {
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

struct VisualNovelBeat: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case title
        case narration
        case dialogue
    }

    let id: UUID
    let kind: Kind
    let title: String?
    let subtitle: String?
    let speaker: String?
    let mood: String?
    let text: String
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
