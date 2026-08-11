import Foundation

public enum CampaignReplayDiagnostic: Codable, Equatable, Sendable {
    case mixedCampaign(eventID: UUID, expected: UUID, actual: UUID)
    case unsupportedSchema(eventID: UUID, version: Int)
    case sequenceGap(eventID: UUID, expected: Int64, actual: Int64)
    case outOfOrder(eventID: UUID, expected: Int64, actual: Int64)
    case duplicateRequestLineage(eventID: UUID, requestID: UUID)
    case invalidCheckpoint(sourceSequence: Int64)
    case storedEventCorruption(eventID: UUID)
}

public struct CampaignReductionResult: Equatable, Sendable {
    public let projection: CampaignProjection
    public let diagnostics: [CampaignReplayDiagnostic]

    public init(
        projection: CampaignProjection,
        diagnostics: [CampaignReplayDiagnostic]
    ) {
        self.projection = projection
        self.diagnostics = diagnostics
    }
}

/// Deterministically projects campaign state without performing I/O.
public struct CampaignReducer: Sendable {
    public static let reducerSchemaVersion = 1

    public init() {}

    public func reduce(
        _ initialProjection: CampaignProjection,
        events: [CampaignEvent]
    ) -> CampaignReductionResult {
        var projection = initialProjection
        var diagnostics: [CampaignReplayDiagnostic] = []

        for event in events {
            if projection.appliedEventIDs.contains(event.id) {
                continue
            }

            guard event.campaignID == projection.campaignID else {
                diagnostics.append(
                    .mixedCampaign(
                        eventID: event.id,
                        expected: projection.campaignID,
                        actual: event.campaignID
                    )
                )
                break
            }

            guard event.schemaVersion == 1 else {
                diagnostics.append(
                    .unsupportedSchema(
                        eventID: event.id,
                        version: event.schemaVersion
                    )
                )
                break
            }

            let expectedSequence = projection.appliedThroughSequence + 1
            guard event.sequence == expectedSequence else {
                let diagnostic: CampaignReplayDiagnostic =
                    if event.sequence > expectedSequence {
                        .sequenceGap(
                            eventID: event.id,
                            expected: expectedSequence,
                            actual: event.sequence
                        )
                    } else {
                        .outOfOrder(
                            eventID: event.id,
                            expected: expectedSequence,
                            actual: event.sequence
                        )
                    }
                diagnostics.append(diagnostic)
                break
            }

            if event.requestID == projection.currentRequestRunID {
                if projection.currentRequestRunDisposition == nil {
                    projection.currentRequestRunDisposition = .accepted
                }
                if projection.currentRequestRunDisposition == .rejectedDuplicate {
                    consume(event, in: &projection)
                    continue
                }
            } else if projection.appliedRequestIDs.contains(event.requestID) {
                projection.currentRequestRunID = event.requestID
                projection.currentRequestRunDisposition = .rejectedDuplicate
                diagnostics.append(
                    .duplicateRequestLineage(
                        eventID: event.id,
                        requestID: event.requestID
                    )
                )
                consume(event, in: &projection)
                continue
            } else {
                projection.appliedRequestIDs.insert(event.requestID)
                projection.currentRequestRunID = event.requestID
                projection.currentRequestRunDisposition = .accepted
            }

            projection.appliedEventIDs.insert(event.id)
            apply(event, to: &projection)
            projection.appliedThroughSequence = event.sequence
        }

        return CampaignReductionResult(
            projection: projection,
            diagnostics: diagnostics
        )
    }

    private func consume(
        _ event: CampaignEvent,
        in projection: inout CampaignProjection
    ) {
        projection.appliedEventIDs.insert(event.id)
        projection.appliedThroughSequence = event.sequence
    }

    private func apply(
        _ event: CampaignEvent,
        to projection: inout CampaignProjection
    ) {
        switch event.payload {
        case .campaignImported(let payload):
            projection.campaignTitle = payload.campaignTitle
            projection.importedProjectID = payload.projectID
            projection.importManifestHash = payload.manifestHash
            projection.approvedHandoffCheckpoint = payload.handoffCheckpoint

        case .playerActionSubmitted(let payload):
            projection.activeTurnRequestID = event.requestID
            projection.pendingDecision = nil
            projection.gmStatus = nil
            projection.pendingRolls.removeAll()
            projection.submittedActions.append(
                ProjectedPlayerAction(
                    requestID: event.requestID,
                    action: payload.action,
                    additionalContext: payload.additionalContext
                )
            )

        case .gmStatusChanged(let payload):
            projection.gmStatus = payload

        case .gmMessageCommitted(let payload):
            projection.gmMessages.append(payload)
            projection.pendingDecision = payload.finalQuestion
            finishTurn(clearingPendingDecision: false, in: &projection)

        case .recordPatched(let payload):
            projection.records[payload.recordID, default: [:]].merge(
                payload.changes,
                uniquingKeysWith: { _, replacement in replacement }
            )

        case .rollRequested(let payload):
            projection.pendingRolls[payload.rollID] = payload

        case .rollResolved(let payload):
            projection.pendingRolls[payload.rollID] = nil
            projection.resolvedRolls[payload.rollID] = payload

        case .sceneChanged(let payload):
            projection.currentScene = payload

        case .voiceAssignmentChanged(let payload):
            if projection.voiceAssignments[payload.characterID]?.source == .manual,
               payload.source == .acceptedSuggestion {
                break
            }
            projection.voiceAssignments[payload.characterID] = payload

        case .turnCancelled(let payload):
            let outcome = ProjectedTurnOutcome.cancelled(
                requestID: event.requestID,
                reason: payload.reason
            )
            projection.turnOutcomes.append(outcome)
            projection.lastTurnOutcome = outcome
            finishTurn(clearingPendingDecision: true, in: &projection)

        case .turnFailed(let payload):
            let outcome = ProjectedTurnOutcome.failed(
                requestID: event.requestID,
                category: payload.category,
                message: payload.message,
                isRetryable: payload.isRetryable
            )
            projection.turnOutcomes.append(outcome)
            projection.lastTurnOutcome = outcome
            finishTurn(clearingPendingDecision: true, in: &projection)
        }
    }

    private func finishTurn(
        clearingPendingDecision: Bool,
        in projection: inout CampaignProjection
    ) {
        projection.activeTurnRequestID = nil
        projection.gmStatus = nil
        projection.pendingRolls.removeAll()
        if clearingPendingDecision {
            projection.pendingDecision = nil
        }
    }
}
