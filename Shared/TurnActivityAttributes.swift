import ActivityKit
import Foundation

struct TurnActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        let phase: GenerationPhase
        let status: String
        let startedAt: Date
        let canCancel: Bool
    }

    let campaignID: UUID
    let campaignTitle: String
    let turnID: String

    var deepLinkURL: URL? {
        let unreserved = CharacterSet(
            charactersIn:
                "ABCDEFGHIJKLMNOPQRSTUVWXYZ" +
                "abcdefghijklmnopqrstuvwxyz" +
                "0123456789-._~"
        )
        guard let encodedTurnID = turnID.addingPercentEncoding(
            withAllowedCharacters: unreserved
        ) else {
            return nil
        }

        return URL(
            string:
                "rpgplayer://campaign/" +
                campaignID.uuidString.lowercased() +
                "/turn/" + encodedTurnID
        )
    }
}
