import Foundation

enum GenerationPhase: String, Codable, Hashable, Sendable {
    case queued
    case readingWorld
    case planning
    case updatingWorld
    case writingScene
    case voicing
    case ready
    case needsAttention

    var displayText: String {
        switch self {
        case .queued: "Getting ready…"
        case .readingWorld: "Consulting the lore…"
        case .planning: "Connecting the dots…"
        case .updatingWorld: "Updating the world…"
        case .writingScene: "Weaving the story…"
        case .voicing: "Giving everyone a voice…"
        case .ready: "Ready"
        case .needsAttention: "Needs attention"
        }
    }
}
