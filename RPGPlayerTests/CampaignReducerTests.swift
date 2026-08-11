import Foundation
import Testing
@testable import RPGPlayer

struct CampaignReducerTests {
    @Test(arguments: ReducerPayloadFixture.allCases)
    func everyPayloadFamilyMutatesItsOwnedProjectionState(
        _ fixture: ReducerPayloadFixture
    ) throws {
        let campaignID = try reducerUUID(100)
        let event = try reducerEvent(
            campaignID: campaignID,
            eventID: fixture.eventID,
            requestID: fixture.requestID,
            sequence: 1,
            payload: fixture.payload
        )

        let result = CampaignReducer().reduce(
            CampaignProjection(campaignID: campaignID),
            events: [event]
        )

        #expect(result.diagnostics.isEmpty)
        #expect(result.projection.appliedThroughSequence == 1)
        #expect(result.projection.appliedEventIDs == [event.id])

        switch fixture {
        case .campaignImported:
            #expect(result.projection.campaignTitle == "Fog Over Greyhaven")
            #expect(result.projection.importedProjectID == "project-alpha")
            #expect(result.projection.importManifestHash == "sha256:manifest")
        case .playerActionSubmitted:
            #expect(
                result.projection.submittedActions
                    == [
                        ProjectedPlayerAction(
                            requestID: event.requestID,
                            action: "Follow the lantern trail.",
                            additionalContext: "Stay out of sight."
                        )
                    ]
            )
        case .gmStatusChanged:
            #expect(
                result.projection.gmStatus
                    == GMStatusChangedPayload(
                        phase: .writingScene,
                        sanitizedDetail: "Prepared the next beat."
                    )
            )
        case .gmMessageCommitted:
            #expect(result.projection.gmMessages.count == 1)
            #expect(result.projection.gmMessages[0].finalQuestion == "What do you do?")
        case .recordPatched:
            #expect(
                result.projection.records["character-guide"]
                    == [
                        "trust": .integer(2),
                        "present": .bool(true)
                    ]
            )
        case .rollRequested:
            let rollID = try reducerUUID(401)
            #expect(
                result.projection.pendingRolls[rollID]
                    == RollRequestedPayload(
                        rollID: rollID,
                        expression: "1d20+3",
                        prompt: "Slip past the sentry"
                    )
            )
        case .rollResolved:
            let rollID = try reducerUUID(401)
            #expect(
                result.projection.resolvedRolls[rollID]
                    == RollResolvedPayload(
                        rollID: rollID,
                        results: [14],
                        modifier: 3,
                        total: 17
                    )
            )
        case .sceneChanged:
            #expect(
                result.projection.currentScene
                    == SceneChangedPayload(
                        sceneID: "old-arch",
                        title: "The Old Arch",
                        summary: "A rain-dark arch."
                    )
            )
        case .voiceAssignmentChanged:
            #expect(
                result.projection.voiceAssignments["character-guide"]
                    == VoiceAssignmentChangedPayload(
                        characterID: "character-guide",
                        voiceID: "voice-warm-01",
                        source: .manual
                    )
            )
        case .turnCancelled:
            #expect(
                result.projection.lastTurnOutcome
                    == .cancelled(
                        requestID: event.requestID,
                        reason: "Stopped by player"
                    )
            )
        case .turnFailed:
            #expect(
                result.projection.lastTurnOutcome
                    == .failed(
                        requestID: event.requestID,
                        category: .connectivity,
                        message: "The turn could not finish while offline.",
                        isRetryable: true
                    )
            )
        }
    }

    @Test
    func reducingCombinedEventsEqualsReducingEachContiguousPart() throws {
        let campaignID = try reducerUUID(110)
        let firstRequest = try reducerUUID(210)
        let secondRequest = try reducerUUID(211)
        let events = try [
            reducerEvent(
                campaignID: campaignID,
                eventID: 11,
                requestID: 210,
                sequence: 1,
                payload: ReducerPayloadFixture.campaignImported.payload
            ),
            reducerEvent(
                campaignID: campaignID,
                eventID: 12,
                requestID: 211,
                sequence: 2,
                payload: ReducerPayloadFixture.playerActionSubmitted.payload
            ),
            reducerEvent(
                campaignID: campaignID,
                eventID: 13,
                requestID: 211,
                sequence: 3,
                payload: ReducerPayloadFixture.gmStatusChanged.payload
            ),
            reducerEvent(
                campaignID: campaignID,
                eventID: 14,
                requestID: 211,
                sequence: 4,
                payload: ReducerPayloadFixture.gmMessageCommitted.payload
            )
        ]
        #expect(events[0].requestID == firstRequest)
        #expect(events[1].requestID == secondRequest)

        let reducer = CampaignReducer()
        let initial = CampaignProjection(campaignID: campaignID)
        let combined = reducer.reduce(initial, events: events)
        let firstPart = reducer.reduce(initial, events: Array(events.prefix(2)))
        let secondPart = reducer.reduce(
            firstPart.projection,
            events: Array(events.suffix(2))
        )

        #expect(combined.projection == secondPart.projection)
        #expect(combined.diagnostics == firstPart.diagnostics + secondPart.diagnostics)
    }

    @Test
    func sameRequestEventsApplyContiguouslyAndExactBatchReplayIsIdempotent() throws {
        let campaignID = try reducerUUID(120)
        let events = try [
            reducerEvent(
                campaignID: campaignID,
                eventID: 21,
                requestID: 220,
                sequence: 1,
                payload: ReducerPayloadFixture.playerActionSubmitted.payload
            ),
            reducerEvent(
                campaignID: campaignID,
                eventID: 22,
                requestID: 220,
                sequence: 2,
                payload: ReducerPayloadFixture.gmStatusChanged.payload
            ),
            reducerEvent(
                campaignID: campaignID,
                eventID: 23,
                requestID: 220,
                sequence: 3,
                payload: ReducerPayloadFixture.gmMessageCommitted.payload
            )
        ]
        let reducer = CampaignReducer()

        let firstPass = reducer.reduce(
            CampaignProjection(campaignID: campaignID),
            events: events
        )
        let replay = reducer.reduce(firstPass.projection, events: events)

        #expect(firstPass.diagnostics.isEmpty)
        #expect(firstPass.projection.appliedThroughSequence == 3)
        #expect(firstPass.projection.submittedActions.count == 1)
        #expect(firstPass.projection.gmMessages.count == 1)
        #expect(replay.projection == firstPass.projection)
        #expect(replay.diagnostics.isEmpty)
    }

    @Test
    func laterDuplicateRequestRunConsumesSequencesWithoutApplyingPayloads() throws {
        let campaignID = try reducerUUID(130)
        let first = try reducerEvent(
            campaignID: campaignID,
            eventID: 31,
            requestID: 230,
            sequence: 1,
            payload: ReducerPayloadFixture.sceneChanged.payload
        )
        let second = try reducerEvent(
            campaignID: campaignID,
            eventID: 32,
            requestID: 231,
            sequence: 2,
            payload: ReducerPayloadFixture.gmStatusChanged.payload
        )
        let reused = try reducerEvent(
            campaignID: campaignID,
            eventID: 33,
            requestID: 230,
            sequence: 3,
            payload: .sceneChanged(
                SceneChangedPayload(sceneID: "wrong", title: "Wrong")
            )
        )
        let reusedSibling = try reducerEvent(
            campaignID: campaignID,
            eventID: 34,
            requestID: 230,
            sequence: 4,
            payload: ReducerPayloadFixture.gmMessageCommitted.payload
        )
        let followingRequest = try reducerEvent(
            campaignID: campaignID,
            eventID: 35,
            requestID: 232,
            sequence: 5,
            payload: .sceneChanged(
                SceneChangedPayload(sceneID: "safe", title: "Safe")
            )
        )

        let result = CampaignReducer().reduce(
            CampaignProjection(campaignID: campaignID),
            events: [first, second, reused, reusedSibling, followingRequest]
        )

        #expect(result.projection.appliedThroughSequence == 5)
        #expect(result.projection.currentScene?.sceneID == "safe")
        #expect(result.projection.gmMessages.isEmpty)
        #expect(
            result.diagnostics
                == [
                    .duplicateRequestLineage(
                        eventID: reused.id,
                        requestID: reused.requestID
                    )
                ]
        )
    }

    @Test
    func recordPatchesMergeFieldsAndNewestValuesReplaceOlderValues() throws {
        let campaignID = try reducerUUID(131)
        let events = try [
            reducerEvent(
                campaignID: campaignID,
                eventID: 36,
                requestID: 233,
                sequence: 1,
                payload: .recordPatched(
                    RecordPatchedPayload(
                        recordID: "character-guide",
                        changes: [
                            "trust": .integer(1),
                            "present": .bool(true)
                        ]
                    )
                )
            ),
            reducerEvent(
                campaignID: campaignID,
                eventID: 37,
                requestID: 234,
                sequence: 2,
                payload: .recordPatched(
                    RecordPatchedPayload(
                        recordID: "character-guide",
                        changes: [
                            "trust": .integer(3),
                            "location": .string("old-arch")
                        ]
                    )
                )
            )
        ]

        let result = CampaignReducer().reduce(
            CampaignProjection(campaignID: campaignID),
            events: events
        )

        #expect(
            result.projection.records["character-guide"]
                == [
                    "trust": .integer(3),
                    "present": .bool(true),
                    "location": .string("old-arch")
                ]
        )
    }

    @Test
    func acceptedVoiceSuggestionCannotOverwriteAManualAssignment() throws {
        let campaignID = try reducerUUID(132)
        let events = try [
            reducerEvent(
                campaignID: campaignID,
                eventID: 38,
                requestID: 235,
                sequence: 1,
                payload: .voiceAssignmentChanged(
                    VoiceAssignmentChangedPayload(
                        characterID: "character-guide",
                        voiceID: "voice-manual",
                        source: .manual
                    )
                )
            ),
            reducerEvent(
                campaignID: campaignID,
                eventID: 39,
                requestID: 236,
                sequence: 2,
                payload: .voiceAssignmentChanged(
                    VoiceAssignmentChangedPayload(
                        characterID: "character-guide",
                        voiceID: "voice-suggested",
                        source: .acceptedSuggestion
                    )
                )
            )
        ]

        let result = CampaignReducer().reduce(
            CampaignProjection(campaignID: campaignID),
            events: events
        )

        #expect(
            result.projection.voiceAssignments["character-guide"]?.voiceID
                == "voice-manual"
        )
    }

    @Test
    func committedGMMessageExposesThePendingPlayerDecision() throws {
        let campaignID = try reducerUUID(133)
        let event = try reducerEvent(
            campaignID: campaignID,
            eventID: 45,
            requestID: 237,
            sequence: 1,
            payload: ReducerPayloadFixture.gmMessageCommitted.payload
        )

        let result = CampaignReducer().reduce(
            CampaignProjection(campaignID: campaignID),
            events: [event]
        )

        #expect(result.projection.pendingDecision == "What do you do?")
    }

    @Test
    func turnLifecycleKeepsReplayRunMetadataSeparateFromTransientPlayerState() throws {
        let campaignID = try reducerUUID(134)
        let firstRequestID = try reducerUUID(260)
        let rollID = try reducerUUID(460)
        var projection = CampaignProjection(
            campaignID: campaignID,
            pendingDecision: "Prior decision"
        )
        let reducer = CampaignReducer()

        projection = reducer.reduce(
            projection,
            events: [
                try reducerEvent(
                    campaignID: campaignID,
                    eventID: 60,
                    requestID: 260,
                    sequence: 1,
                    payload: ReducerPayloadFixture.playerActionSubmitted.payload
                )
            ]
        ).projection

        #expect(projection.activeTurnRequestID == firstRequestID)
        #expect(projection.currentRequestRunID == firstRequestID)
        #expect(projection.pendingDecision == nil)

        projection = reducer.reduce(
            projection,
            events: [
                try reducerEvent(
                    campaignID: campaignID,
                    eventID: 61,
                    requestID: 260,
                    sequence: 2,
                    payload: ReducerPayloadFixture.gmStatusChanged.payload
                ),
                try reducerEvent(
                    campaignID: campaignID,
                    eventID: 62,
                    requestID: 260,
                    sequence: 3,
                    payload: .rollRequested(
                        RollRequestedPayload(
                            rollID: rollID,
                            expression: "1d20+3",
                            prompt: "Slip past the sentry"
                        )
                    )
                ),
                try reducerEvent(
                    campaignID: campaignID,
                    eventID: 63,
                    requestID: 260,
                    sequence: 4,
                    payload: ReducerPayloadFixture.gmMessageCommitted.payload
                )
            ]
        ).projection

        #expect(projection.activeTurnRequestID == nil)
        #expect(projection.currentRequestRunID == firstRequestID)
        #expect(projection.gmStatus == nil)
        #expect(projection.pendingRolls.isEmpty)
        #expect(projection.pendingDecision == "What do you do?")

        projection = reducer.reduce(
            projection,
            events: [
                try reducerEvent(
                    campaignID: campaignID,
                    eventID: 64,
                    requestID: 261,
                    sequence: 5,
                    payload: ReducerPayloadFixture.playerActionSubmitted.payload
                ),
                try reducerEvent(
                    campaignID: campaignID,
                    eventID: 65,
                    requestID: 261,
                    sequence: 6,
                    payload: ReducerPayloadFixture.turnCancelled.payload
                ),
                try reducerEvent(
                    campaignID: campaignID,
                    eventID: 66,
                    requestID: 262,
                    sequence: 7,
                    payload: ReducerPayloadFixture.playerActionSubmitted.payload
                ),
                try reducerEvent(
                    campaignID: campaignID,
                    eventID: 67,
                    requestID: 262,
                    sequence: 8,
                    payload: ReducerPayloadFixture.turnFailed.payload
                )
            ]
        ).projection

        let finalRequestID = try reducerUUID(262)
        #expect(projection.activeTurnRequestID == nil)
        #expect(projection.currentRequestRunID == finalRequestID)
        #expect(projection.pendingDecision == nil)
        #expect(projection.turnOutcomes.count == 2)
    }

    @Test(arguments: ReducerDiagnosticFixture.allCases)
    func invalidEnvelopeOrderingIsRecoverableAndDoesNotMutateState(
        _ fixture: ReducerDiagnosticFixture
    ) throws {
        let campaignID = try reducerUUID(140)
        let reducer = CampaignReducer()
        var startingProjection = CampaignProjection(campaignID: campaignID)
        if fixture == .outOfOrder {
            let accepted = try reducerEvent(
                campaignID: campaignID,
                eventID: 40,
                requestID: 240,
                sequence: 1,
                payload: ReducerPayloadFixture.sceneChanged.payload
            )
            startingProjection = reducer.reduce(
                startingProjection,
                events: [accepted]
            ).projection
        }
        let invalid = try fixture.event(campaignID: campaignID)
        let eventAfterInvalid = try fixture.eventAfterInvalid(
            campaignID: campaignID
        )

        let result = reducer.reduce(
            startingProjection,
            events: [invalid, eventAfterInvalid]
        )

        #expect(result.projection == startingProjection)
        #expect(result.diagnostics == [fixture.expectedDiagnostic(for: invalid)])
    }
}

enum ReducerPayloadFixture: CaseIterable, Sendable {
    case campaignImported
    case playerActionSubmitted
    case gmStatusChanged
    case gmMessageCommitted
    case recordPatched
    case rollRequested
    case rollResolved
    case sceneChanged
    case voiceAssignmentChanged
    case turnCancelled
    case turnFailed

    var eventID: Int { 1 + Self.allCases.firstIndex(of: self)! }
    var requestID: Int { 300 + eventID }

    var payload: CampaignEventPayload {
        switch self {
        case .campaignImported:
            .campaignImported(
                CampaignImportedPayload(
                    projectID: "project-alpha",
                    campaignTitle: "Fog Over Greyhaven",
                    manifestHash: "sha256:manifest"
                )
            )
        case .playerActionSubmitted:
            .playerActionSubmitted(
                PlayerActionSubmittedPayload(
                    action: "Follow the lantern trail.",
                    additionalContext: "Stay out of sight."
                )
            )
        case .gmStatusChanged:
            .gmStatusChanged(
                GMStatusChangedPayload(
                    phase: .writingScene,
                    sanitizedDetail: "Prepared the next beat."
                )
            )
        case .gmMessageCommitted:
            .gmMessageCommitted(
                GMMessageCommittedPayload(
                    messageID: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
                    narration: ["The lantern turns beneath the old arch."],
                    dialogue: [],
                    beats: [],
                    finalQuestion: "What do you do?"
                )
            )
        case .recordPatched:
            .recordPatched(
                RecordPatchedPayload(
                    recordID: "character-guide",
                    changes: ["trust": .integer(2), "present": .bool(true)]
                )
            )
        case .rollRequested:
            .rollRequested(
                RollRequestedPayload(
                    rollID: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
                    expression: "1d20+3",
                    prompt: "Slip past the sentry"
                )
            )
        case .rollResolved:
            .rollResolved(
                RollResolvedPayload(
                    rollID: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
                    results: [14],
                    modifier: 3,
                    total: 17
                )
            )
        case .sceneChanged:
            .sceneChanged(
                SceneChangedPayload(
                    sceneID: "old-arch",
                    title: "The Old Arch",
                    summary: "A rain-dark arch."
                )
            )
        case .voiceAssignmentChanged:
            .voiceAssignmentChanged(
                VoiceAssignmentChangedPayload(
                    characterID: "character-guide",
                    voiceID: "voice-warm-01",
                    source: .manual
                )
            )
        case .turnCancelled:
            .turnCancelled(TurnCancelledPayload(reason: "Stopped by player"))
        case .turnFailed:
            .turnFailed(
                TurnFailedPayload(
                    category: .connectivity,
                    message: "The turn could not finish while offline.",
                    isRetryable: true
                )
            )
        }
    }
}

enum ReducerDiagnosticFixture: CaseIterable, Sendable {
    case mixedCampaign
    case unsupportedSchema
    case gap
    case outOfOrder

    func event(campaignID: UUID) throws -> CampaignEvent {
        switch self {
        case .mixedCampaign:
            try reducerEvent(
                campaignID: reducerUUID(999),
                eventID: 41,
                requestID: 241,
                sequence: 1,
                payload: ReducerPayloadFixture.sceneChanged.payload
            )
        case .unsupportedSchema:
            try reducerEvent(
                campaignID: campaignID,
                eventID: 42,
                requestID: 242,
                sequence: 1,
                schemaVersion: 2,
                payload: ReducerPayloadFixture.sceneChanged.payload
            )
        case .gap:
            try reducerEvent(
                campaignID: campaignID,
                eventID: 43,
                requestID: 243,
                sequence: 2,
                payload: ReducerPayloadFixture.sceneChanged.payload
            )
        case .outOfOrder:
            try reducerEvent(
                campaignID: campaignID,
                eventID: 44,
                requestID: 244,
                sequence: 1,
                payload: ReducerPayloadFixture.gmStatusChanged.payload
            )
        }
    }

    func expectedDiagnostic(
        for event: CampaignEvent
    ) -> CampaignReplayDiagnostic {
        switch self {
        case .mixedCampaign:
            .mixedCampaign(
                eventID: event.id,
                expected: UUID(uuidString: "00000000-0000-0000-0000-000000000140")!,
                actual: event.campaignID
            )
        case .unsupportedSchema:
            .unsupportedSchema(
                eventID: event.id,
                version: 2
            )
        case .gap:
            .sequenceGap(eventID: event.id, expected: 1, actual: 2)
        case .outOfOrder:
            .outOfOrder(eventID: event.id, expected: 2, actual: 1)
        }
    }

    func eventAfterInvalid(campaignID: UUID) throws -> CampaignEvent {
        let sequence: Int64 = self == .outOfOrder ? 2 : 1
        return try reducerEvent(
            campaignID: campaignID,
            eventID: 50 + Self.allCases.firstIndex(of: self)!,
            requestID: 250 + Self.allCases.firstIndex(of: self)!,
            sequence: sequence,
            payload: .sceneChanged(
                SceneChangedPayload(
                    sceneID: "must-not-apply",
                    title: "Must Not Apply"
                )
            )
        )
    }
}

private func reducerEvent(
    campaignID: UUID,
    eventID: Int,
    requestID: Int,
    sequence: Int64,
    schemaVersion: Int = 1,
    payload: CampaignEventPayload
) throws -> CampaignEvent {
    CampaignEvent(
        id: try reducerUUID(eventID),
        campaignID: campaignID,
        sequence: sequence,
        requestID: try reducerUUID(requestID),
        timestamp: Date(timeIntervalSince1970: 1_726_000_000 + Double(eventID)),
        schemaVersion: schemaVersion,
        payload: payload
    )
}

private func reducerUUID(_ value: Int) throws -> UUID {
    let suffix = String(format: "%012d", value)
    guard let uuid = UUID(uuidString: "00000000-0000-0000-0000-\(suffix)") else {
        throw ReducerFixtureError.invalidUUID
    }
    return uuid
}

private enum ReducerFixtureError: Error {
    case invalidUUID
}
