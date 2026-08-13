import XCTest
@testable import RPGPlayer

final class PlayerSessionStateTests: XCTestCase {
    func testOpeningRightDrawerReplacesLeftDrawer() {
        var state = makeState()
        state.reduce(.openDrawer(.project))
        state.reduce(.openDrawer(.overview))
        XCTAssertEqual(state.drawer, .overview)
    }

    func testBeatNavigationClampsToMessageBounds() {
        var state = makeState()
        state.reduce(.setMode(.visualNovel))
        state.reduce(.previousBeat)
        XCTAssertEqual(state.beatIndex, 0)
        for _ in 0..<20 {
            state.reduce(.nextBeat)
        }
        XCTAssertEqual(state.beatIndex, state.latestMessage.beats.count - 1)
    }

    func testClosingVisualNovelPreservesCurrentBeat() {
        var state = makeState()
        state.reduce(.setMode(.visualNovel))
        state.reduce(.nextBeat)

        state.reduce(.setMode(.transcript))
        XCTAssertEqual(state.beatIndex, 1)

        state.reduce(.setMode(.visualNovel))
        XCTAssertEqual(state.beatIndex, 1)
    }

    func testFinishingVisualNovelAtomicallyEntersPlayerTurn() {
        var state = makeState()
        state.reduce(.setMode(.visualNovel))
        state.reduce(.nextBeat)
        let finalBeat = state.beatIndex

        state.reduce(.finishVisualNovel)

        XCTAssertEqual(state.mode, .transcript)
        XCTAssertEqual(state.beatIndex, finalBeat)
        XCTAssertTrue(state.isTurnSheetPresented)
    }

    func testCompletedGenerationInstallsMessageOnce() {
        var state = makeState()
        let message = makeMessage(id: UUID())
        state.reduce(.generationStarted(requestID: "request-1"))
        state.reduce(.generationCompleted(requestID: "request-1", message: message))
        state.reduce(.generationCompleted(requestID: "request-1", message: message))
        XCTAssertEqual(state.messages.filter { $0.id == message.id }.count, 1)
        XCTAssertEqual(state.mode, .visualNovel)
    }

    func testFailedGenerationRejectsLateCompletion() {
        var state = makeState()
        let initialMessageCount = state.messages.count
        let lateMessage = makeMessage(id: UUID())

        state.reduce(.generationStarted(requestID: "request-1"))
        state.reduce(.generationFailed)
        state.reduce(
            .generationCompleted(
                requestID: "request-1",
                message: lateMessage
            )
        )

        XCTAssertNil(state.activeRequestID)
        XCTAssertEqual(state.generation, .needsAttention)
        XCTAssertEqual(state.messages.count, initialMessageCount)
        XCTAssertEqual(state.mode, .transcript)
    }

    func testPendingRollBlocksVisualNovelProgressionUntilResolution() {
        var state = makeState()
        state.pendingRoll = RollRequestedPayload(
            rollID: UUID(),
            expression: "1d20",
            prompt: "Test the bridge"
        )
        state.reduce(.setMode(.visualNovel))
        state.reduce(.nextBeat)
        state.reduce(.finishVisualNovel)

        XCTAssertEqual(state.mode, .transcript)
        XCTAssertEqual(state.beatIndex, 0)
        XCTAssertFalse(state.isTurnSheetPresented)
    }

    private func makeState() -> PlayerSessionState {
        PlayerSessionState(
            campaignTitle: "Test Campaign",
            mode: .transcript,
            drawer: .none,
            beatIndex: 0,
            messages: [makeMessage(id: UUID())],
            choices: [],
            isTurnSheetPresented: false,
            generation: nil,
            activeRequestID: nil,
            completedRequestIDs: []
        )
    }

    private func makeMessage(id: UUID) -> GMMessage {
        GMMessage(
            id: id,
            prose: ["Test narration"],
            dialogue: [],
            actionCount: 0,
            finalQuestion: "What do you do?",
            beats: [
                VisualNovelBeat(
                    id: UUID(),
                    kind: .narration,
                    title: nil,
                    subtitle: nil,
                    speaker: "Narrator",
                    mood: nil,
                    text: "First"
                ),
                VisualNovelBeat(
                    id: UUID(),
                    kind: .dialogue,
                    title: nil,
                    subtitle: nil,
                    speaker: "Guide",
                    mood: "Calm",
                    text: "Second"
                )
            ]
        )
    }
}
