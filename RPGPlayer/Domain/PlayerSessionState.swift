import Foundation

struct PlayerSessionState: Equatable, Sendable {
    var campaignTitle: String
    var mode: PlayerMode
    var drawer: PlayerDrawer
    var beatIndex: Int
    var messages: [GMMessage]
    var choices: [PlayerChoice]
    var isTurnSheetPresented: Bool
    var generation: GenerationPhase?
    var activeRequestID: String?
    var completedRequestIDs: Set<String>

    var latestMessage: GMMessage {
        messages[messages.count - 1]
    }

    mutating func reduce(_ action: PlayerAction) {
        switch action {
        case .openDrawer(let value):
            drawer = value
        case .closeDrawer:
            drawer = .none
        case .setMode(let value):
            mode = value
            beatIndex = min(beatIndex, max(0, latestMessage.beats.count - 1))
        case .previousBeat:
            beatIndex = max(0, beatIndex - 1)
        case .nextBeat:
            beatIndex = min(max(0, latestMessage.beats.count - 1), beatIndex + 1)
        case .finishVisualNovel:
            mode = .transcript
            beatIndex = min(beatIndex, max(0, latestMessage.beats.count - 1))
            isTurnSheetPresented = true
        case .presentTurnSheet:
            isTurnSheetPresented = true
        case .dismissTurnSheet:
            isTurnSheetPresented = false
        case .generationStarted(let requestID):
            activeRequestID = requestID
            generation = .queued
            isTurnSheetPresented = false
        case .generationPhaseChanged(let phase):
            generation = phase
        case .generationCompleted(let requestID, let message):
            guard activeRequestID == requestID,
                  completedRequestIDs.insert(requestID).inserted else {
                return
            }
            if !messages.contains(where: { $0.id == message.id }) {
                messages.append(message)
            }
            generation = nil
            activeRequestID = nil
            beatIndex = 0
            mode = .visualNovel
        case .generationFailed:
            activeRequestID = nil
            generation = .needsAttention
        }
    }
}

enum PlayerAction: Equatable, Sendable {
    case openDrawer(PlayerDrawer)
    case closeDrawer
    case setMode(PlayerMode)
    case previousBeat
    case nextBeat
    case finishVisualNovel
    case presentTurnSheet
    case dismissTurnSheet
    case generationStarted(requestID: String)
    case generationPhaseChanged(GenerationPhase)
    case generationCompleted(requestID: String, message: GMMessage)
    case generationFailed
}
