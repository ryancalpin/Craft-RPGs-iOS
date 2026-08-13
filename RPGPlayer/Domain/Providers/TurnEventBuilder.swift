import Foundation

public enum TurnEventBuilderError: Error, Equatable, Sendable {
    case requestIDMismatch
    case duplicateEventID(UUID)
}

/// Converts a validated turn into one store-ready, sequence-zero batch.
/// CampaignStore assigns canonical sequences during its atomic append.
public struct TurnEventBuilder: Sendable {
    public typealias IDGenerator = @Sendable () -> UUID

    private let idGenerator: IDGenerator

    public init(idGenerator: @escaping IDGenerator = { UUID() }) {
        self.idGenerator = idGenerator
    }

    public func build(
        request: TurnRequest,
        envelope: VersionedTurnEnvelope,
        timestamp: Date = Date()
    ) throws -> [CampaignEvent] {
        guard envelope.envelope.requestID == request.requestID else {
            throw TurnEventBuilderError.requestIDMismatch
        }
        var events: [CampaignEvent] = []
        var eventIDs = Set<UUID>()

        func append(_ payload: CampaignEventPayload) throws {
            let eventID = idGenerator()
            guard eventIDs.insert(eventID).inserted else {
                throw TurnEventBuilderError.duplicateEventID(eventID)
            }
            events.append(
                CampaignEvent(
                    id: eventID,
                    campaignID: request.campaignID,
                    sequence: 0,
                    requestID: request.requestID,
                    timestamp: timestamp,
                    schemaVersion: 1,
                    payload: payload
                )
            )
        }

        try append(
            .playerActionSubmitted(
                PlayerActionSubmittedPayload(
                    action: request.action.text,
                    additionalContext: request.action.additionalContext
                )
            )
        )

        for proposal in envelope.envelope.proposedEvents {
            switch proposal {
            case .recordPatch(let recordID, let fields):
                try append(
                    .recordPatched(
                        RecordPatchedPayload(recordID: recordID, changes: fields)
                    )
                )
            case .rollRequest(let rollID, let expression, let prompt):
                try append(
                    .rollRequested(
                        RollRequestedPayload(
                            rollID: rollID,
                            expression: expression,
                            prompt: prompt
                        )
                    )
                )
            case .sceneChange(let sceneRecordID, let title, let summary):
                try append(
                    .sceneChanged(
                        SceneChangedPayload(
                            sceneID: sceneRecordID,
                            title: title,
                            summary: summary
                        )
                    )
                )
            case .clockUpdate(let clockRecordID, let current, let maximum):
                try append(
                    .clockUpdated(
                        ClockUpdatedPayload(
                            clockRecordID: clockRecordID,
                            current: current,
                            maximum: maximum
                        )
                    )
                )
            case .voiceSuggestion(let characterRecordID, let styleDescription):
                try append(
                    .voiceSuggestionProposed(
                        VoiceSuggestionProposedPayload(
                            characterID: characterRecordID,
                            styleDescription: styleDescription
                        )
                    )
                )
            case .assetAttachment(let assetID, let targetRecordID, let fieldID):
                try append(
                    .assetAttached(
                        AssetAttachedPayload(
                            assetID: assetID,
                            targetRecordID: targetRecordID,
                            fieldID: fieldID
                        )
                    )
                )
            }
        }
        // The terminal message follows interruption proposals in the same
        // atomic request run.
        let message = makeMessagePayload(from: envelope.envelope)
        try append(.gmMessageCommitted(message))
        return events
    }

    public func buildCancellation(
        request: TurnRequest,
        reason: String?,
        timestamp: Date = Date()
    ) throws -> [CampaignEvent] {
        var events: [CampaignEvent] = []
        var eventIDs = Set<UUID>()

        func append(_ payload: CampaignEventPayload) throws {
            let eventID = idGenerator()
            guard eventIDs.insert(eventID).inserted else {
                throw TurnEventBuilderError.duplicateEventID(eventID)
            }
            events.append(
                CampaignEvent(
                    id: eventID,
                    campaignID: request.campaignID,
                    sequence: 0,
                    requestID: request.requestID,
                    timestamp: timestamp,
                    schemaVersion: 1,
                    payload: payload
                )
            )
        }

        try append(
            .playerActionSubmitted(
                PlayerActionSubmittedPayload(
                    action: request.action.text,
                    additionalContext: request.action.additionalContext
                )
            )
        )
        try append(.turnCancelled(TurnCancelledPayload(reason: reason)))
        return events
    }

    private func makeMessagePayload(
        from envelope: TurnEnvelope
    ) -> GMMessageCommittedPayload {
        let narration = envelope.narration.compactMap { block -> String? in
            block.kind == .narration ? block.text : nil
        }
        let dialogue = envelope.narration.compactMap { block -> CampaignDialogueBlock? in
            guard block.kind == .dialogue else { return nil }
            return CampaignDialogueBlock(
                id: block.id,
                speaker: block.speakerName ?? "Narrator",
                mood: block.mood,
                text: block.text
            )
        }
        let orderedTranscript = envelope.narration.map { block in
            CampaignTranscriptBlock(
                id: block.id,
                kind: block.kind == .narration ? .narration : .dialogue,
                speaker: block.speakerName,
                mood: block.mood,
                text: block.text
            )
        }
        let beats = envelope.beats.map {
            CampaignStoryBeat(
                id: $0.id,
                kind: CampaignStoryBeat.Kind(rawValue: $0.kind.rawValue) ?? .narration,
                title: $0.title,
                subtitle: $0.subtitle,
                speaker: $0.speaker,
                mood: $0.mood,
                text: $0.text
            )
        }
        return GMMessageCommittedPayload(
            messageID: envelope.narration.first?.id
                ?? envelope.beats.first?.id
                ?? idGenerator(),
            narration: narration,
            dialogue: dialogue,
            orderedTranscript: orderedTranscript,
            beats: beats,
            finalQuestion: envelope.pendingDecision?.prompt ?? ""
        )
    }
}
