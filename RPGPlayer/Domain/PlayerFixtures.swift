import Foundation

extension PlayerSessionState {
    static let fixture = PlayerSessionState(
        campaignTitle: "The Ascendant Road",
        mode: .transcript,
        drawer: .none,
        beatIndex: 0,
        messages: [
            .fixture(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        ],
        choices: [
            PlayerChoice(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
                title: "Stay in the shadow",
                detail: "Watch the lantern road and learn who is following you."
            ),
            PlayerChoice(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
                title: "Call out to the rider",
                detail: "Risk being seen in exchange for a direct answer."
            ),
            PlayerChoice(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000203")!,
                title: "Take the ridge path",
                detail: "Trade speed for a better view of the valley."
            )
        ],
        isTurnSheetPresented: false,
        generation: nil,
        activeRequestID: nil,
        completedRequestIDs: []
    )
}

extension GMMessage {
    static func fixture(id: UUID) -> GMMessage {
        let openingNarration = "Rain threads through the pines as the old road climbs toward the high pass, dark with water and old ash. Far below, a single lantern moves against the wind, vanishing behind each switchback before appearing again. Mara watches it climb and knows now that whoever carries it is following their trail."

        return GMMessage(
            id: id,
            prose: [
                openingNarration,
                "Mara studies the light, one hand resting on the weathered map tucked beneath her cloak."
            ],
            dialogue: [
                DialogueBlock(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                    speaker: "Mara Vey",
                    mood: "Wary",
                    text: "That lantern has followed every turn we have made since dusk."
                )
            ],
            actionCount: 3,
            finalQuestion: "The lantern pauses on the road below. What do you do?",
            beats: [
                VisualNovelBeat(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
                    kind: .title,
                    title: "THE ASCENDANT ROAD",
                    subtitle: "A light where no traveler should be",
                    speaker: nil,
                    mood: nil,
                    text: "The Ascendant Road"
                ),
                VisualNovelBeat(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
                    kind: .narration,
                    title: nil,
                    subtitle: nil,
                    speaker: "Narrator",
                    mood: "Neutral",
                    text: openingNarration
                ),
                VisualNovelBeat(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
                    kind: .dialogue,
                    title: nil,
                    subtitle: nil,
                    speaker: "Mara Vey",
                    mood: "Wary",
                    text: "That lantern has followed every turn we have made since dusk."
                )
            ]
        )
    }
}
