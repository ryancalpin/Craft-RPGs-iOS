import Foundation
import SwiftData
import Testing
@testable import RPGPlayer

@MainActor
struct PlayerSessionModelTests {
    @Test
    func freshImportedCampaignBuildsDeterministicOpeningFromRealProjectData() async throws {
        let harness = try await PlayerSessionHarness.make()
        defer { harness.removeFiles() }

        let first = harness.makeModel()
        try await first.load()
        let firstState = try #require(first.state)

        #expect(firstState.campaignTitle == "Imported Greyhaven")
        #expect(firstState.mode == .visualNovel)
        #expect(firstState.beatIndex == 0)
        #expect(firstState.choices.isEmpty)
        #expect(firstState.messages.count == 1)
        #expect(firstState.latestMessage.beats.count == 2)
        #expect(firstState.latestMessage.beats[0].text == "Fog Over Greyhaven")
        #expect(
            firstState.latestMessage.beats[1].text
                == "The Fogbound Harbor\n\nLanterns blur along the rain-black quay."
        )

        let renderedText = (
            firstState.latestMessage.prose
                + firstState.latestMessage.beats.map(\.text)
        ).joined(separator: " ")
        #expect(renderedText.contains("Ascendant Road") == false)
        #expect(renderedText.contains("Mara Vey") == false)
        #expect(
            firstState.latestMessage.id
                != UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        )

        let reconstructed = harness.makeModel()
        try await reconstructed.load()
        let reconstructedState = try #require(reconstructed.state)
        #expect(reconstructedState == firstState)
    }

    @Test
    func committedGMMessageMapsOneToOneIntoPlayerState() async throws {
        let messageID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let dialogueID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let titleBeatID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let dialogueBeatID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let requestID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let payload = GMMessageCommittedPayload(
            messageID: messageID,
            narration: ["The bell sounds once."],
            dialogue: [
                CampaignDialogueBlock(
                    id: dialogueID,
                    speaker: "Elias Grey",
                    mood: "Calm",
                    text: "The harbor remembers."
                )
            ],
            beats: [
                CampaignStoryBeat(
                    id: titleBeatID,
                    kind: .title,
                    title: "THE HARBOR",
                    subtitle: "One bell in the fog",
                    text: "The Harbor"
                ),
                CampaignStoryBeat(
                    id: dialogueBeatID,
                    kind: .dialogue,
                    speaker: "Elias Grey",
                    mood: "Calm",
                    text: "The harbor remembers."
                )
            ],
            finalQuestion: "Do you follow the sound?"
        )
        let harness = try await PlayerSessionHarness.make(
            eventsAfterImport: [
                CampaignEvent(
                    id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
                    campaignID: PlayerSessionHarness.campaignID,
                    sequence: 0,
                    requestID: requestID,
                    timestamp: Date(timeIntervalSince1970: 2),
                    schemaVersion: 1,
                    payload: .playerActionSubmitted(
                        PlayerActionSubmittedPayload(action: "Follow the bell")
                    )
                ),
                CampaignEvent(
                    id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
                    campaignID: PlayerSessionHarness.campaignID,
                    sequence: 0,
                    requestID: requestID,
                    timestamp: Date(timeIntervalSince1970: 3),
                    schemaVersion: 1,
                    payload: .gmMessageCommitted(payload)
                )
            ]
        )
        defer { harness.removeFiles() }

        let model = harness.makeModel()
        try await model.load()
        let state = try #require(model.state)

        #expect(
            state.messages == [
                GMMessage(
                    id: messageID,
                    prose: ["The bell sounds once."],
                    dialogue: [
                        DialogueBlock(
                            id: dialogueID,
                            speaker: "Elias Grey",
                            mood: "Calm",
                            text: "The harbor remembers."
                        )
                    ],
                    actionCount: 1,
                    finalQuestion: "Do you follow the sound?",
                    beats: [
                        VisualNovelBeat(
                            id: titleBeatID,
                            kind: .title,
                            title: "THE HARBOR",
                            subtitle: "One bell in the fog",
                            speaker: nil,
                            mood: nil,
                            text: "The Harbor"
                        ),
                        VisualNovelBeat(
                            id: dialogueBeatID,
                            kind: .dialogue,
                            title: nil,
                            subtitle: nil,
                            speaker: "Elias Grey",
                            mood: "Calm",
                            text: "The harbor remembers."
                        )
                    ]
                )
            ]
        )
    }

    @Test
    func orderedTranscriptSurvivesPersistenceProjectionAndUIReconstruction() async throws {
        let messageID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let narrationOneID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let dialogueID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        let narrationTwoID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
        let requestID = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
        let payload = GMMessageCommittedPayload(
            messageID: messageID,
            narration: ["The bell sounds once.", "Fog closes over the quay."],
            dialogue: [
                CampaignDialogueBlock(
                    id: dialogueID,
                    speaker: "Elias Grey",
                    mood: "Calm",
                    text: "The harbor remembers."
                )
            ],
            orderedTranscript: [
                CampaignTranscriptBlock(id: narrationOneID, kind: .narration, text: "The bell sounds once."),
                CampaignTranscriptBlock(id: dialogueID, kind: .dialogue, speaker: "Elias Grey", mood: "Calm", text: "The harbor remembers."),
                CampaignTranscriptBlock(id: narrationTwoID, kind: .narration, text: "Fog closes over the quay.")
            ],
            beats: [
                CampaignStoryBeat(id: narrationOneID, kind: .narration, text: "The bell sounds once."),
                CampaignStoryBeat(id: dialogueID, kind: .dialogue, speaker: "Elias Grey", mood: "Calm", text: "The harbor remembers."),
                CampaignStoryBeat(id: narrationTwoID, kind: .narration, text: "Fog closes over the quay.")
            ],
            finalQuestion: "What do you do?"
        )
        let encoded = try JSONEncoder().encode(payload)
        #expect(try JSONDecoder().decode(GMMessageCommittedPayload.self, from: encoded) == payload)

        let harness = try await PlayerSessionHarness.make(
            eventsAfterImport: [
                CampaignEvent(
                    id: UUID(uuidString: "66666666-6666-4666-8666-666666666666")!,
                    campaignID: PlayerSessionHarness.campaignID,
                    sequence: 0,
                    requestID: requestID,
                    timestamp: Date(timeIntervalSince1970: 2),
                    schemaVersion: 1,
                    payload: .playerActionSubmitted(PlayerActionSubmittedPayload(action: "Listen"))
                ),
                CampaignEvent(
                    id: UUID(uuidString: "77777777-7777-4777-8777-777777777777")!,
                    campaignID: PlayerSessionHarness.campaignID,
                    sequence: 0,
                    requestID: requestID,
                    timestamp: Date(timeIntervalSince1970: 3),
                    schemaVersion: 1,
                    payload: .gmMessageCommitted(payload)
                )
            ]
        )
        defer { harness.removeFiles() }

        let model = harness.makeModel()
        try await model.load()
        let state = try #require(model.state)

        #expect(state.latestMessage.transcript.map(\.text) == [
            "The bell sounds once.",
            "The harbor remembers.",
            "Fog closes over the quay."
        ])
        #expect(state.latestMessage.transcript.map { block in
            switch block.kind {
            case .narration: "narration"
            case .dialogue: "dialogue"
            }
        } == ["narration", "dialogue", "narration"])
    }

    @Test
    func advancingBeatRestoresExactlyFromPresentationStore() async throws {
        let harness = try await PlayerSessionHarness.make()
        defer { harness.removeFiles() }
        let original = harness.makeModel()
        try await original.load()

        try await original.send(.nextBeat)
        let advancedState = try #require(original.state)
        #expect(advancedState.beatIndex == 1)

        let reconstructed = harness.makeModel()
        try await reconstructed.load()

        #expect(reconstructed.state == advancedState)
    }

    @Test
    func failedPresentationWriteDoesNotPublishBeatAdvance() async throws {
        let harness = try await PlayerSessionHarness.make()
        defer { harness.removeFiles() }
        let model = harness.makeModel(
            presentationStore: FailingPresentationStore()
        )
        try await model.load()

        await #expect(throws: PresentationStoreTestError.writeFailed) {
            try await model.send(.nextBeat)
        }

        #expect(model.state?.beatIndex == 0)
    }

    @Test
    func presentationForAnOlderMessageDoesNotOverrideFreshOpeningDefaults() async throws {
        let harness = try await PlayerSessionHarness.make()
        defer { harness.removeFiles() }
        let presentationStore = PlayerPresentationStore(
            fileURL: harness.presentationFileURL
        )
        try await presentationStore.savePresentation(
            PlayerPresentationState(
                campaignID: PlayerSessionHarness.campaignID,
                mode: .transcript,
                latestMessageID: UUID(
                    uuidString: "99999999-9999-9999-9999-999999999999"
                )!,
                beatIndex: 1
            )
        )

        let model = harness.makeModel(
            presentationStore: presentationStore
        )
        try await model.load()

        #expect(model.state?.mode == .visualNovel)
        #expect(model.state?.beatIndex == 0)
    }

    @Test
    func projectedSceneOverridesImmutableImportedSceneInOpening() async throws {
        let requestID = UUID(
            uuidString: "88888888-8888-8888-8888-888888888888"
        )!
        let harness = try await PlayerSessionHarness.make(
            eventsAfterImport: [
                CampaignEvent(
                    id: UUID(
                        uuidString: "12121212-1212-1212-1212-121212121212"
                    )!,
                    campaignID: PlayerSessionHarness.campaignID,
                    sequence: 0,
                    requestID: requestID,
                    timestamp: Date(timeIntervalSince1970: 2),
                    schemaVersion: 1,
                    payload: .sceneChanged(
                        SceneChangedPayload(
                            sceneID: "scene-projected",
                            title: "After the Bell",
                            summary: "The tide turns beneath the watchtower."
                        )
                    )
                )
            ]
        )
        defer { harness.removeFiles() }

        let model = harness.makeModel()
        try await model.load()

        #expect(
            model.state?.latestMessage.beats[1].text
                == "After the Bell\n\nThe tide turns beneath the watchtower."
        )
    }

    @Test
    func projectedRecordFieldsOverrideImportedCurrentSceneFields() async throws {
        let requestID = UUID(
            uuidString: "13131313-1313-1313-1313-131313131313"
        )!
        let harness = try await PlayerSessionHarness.make(
            eventsAfterImport: [
                CampaignEvent(
                    id: UUID(
                        uuidString: "14141414-1414-1414-1414-141414141414"
                    )!,
                    campaignID: PlayerSessionHarness.campaignID,
                    sequence: 0,
                    requestID: requestID,
                    timestamp: Date(timeIntervalSince1970: 2),
                    schemaVersion: 1,
                    payload: .recordPatched(
                        RecordPatchedPayload(
                            recordID: "record-scene",
                            changes: [
                                "title": .string("Harbor at Dawn"),
                                "description": .string(
                                    "Sunlight reaches the wet stones."
                                )
                            ]
                        )
                    )
                )
            ]
        )
        defer { harness.removeFiles() }

        let model = harness.makeModel()
        try await model.load()

        #expect(
            model.state?.latestMessage.beats[1].text
                == "Harbor at Dawn\n\nSunlight reaches the wet stones."
        )
    }

    @Test
    func resolvingPendingRollAppendsOnceAndReconstructsCanonicalResult() async throws {
        let requestID = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!
        let rollID = UUID(uuidString: "99999999-9999-4999-8999-999999999999")!
        let harness = try await PlayerSessionHarness.make(
            eventsAfterImport: [
                CampaignEvent(
                    id: UUID(uuidString: "12121212-1212-4121-8121-121212121212")!,
                    campaignID: PlayerSessionHarness.campaignID,
                    sequence: 0,
                    requestID: requestID,
                    timestamp: Date(timeIntervalSince1970: 2),
                    schemaVersion: 1,
                    payload: .playerActionSubmitted(
                        PlayerActionSubmittedPayload(action: "Cross the bridge")
                    )
                ),
                CampaignEvent(
                    id: UUID(uuidString: "13131313-1313-4131-8131-131313131313")!,
                    campaignID: PlayerSessionHarness.campaignID,
                    sequence: 0,
                    requestID: requestID,
                    timestamp: Date(timeIntervalSince1970: 3),
                    schemaVersion: 1,
                    payload: .rollRequested(
                        RollRequestedPayload(
                            rollID: rollID,
                            expression: "1d20+4",
                            prompt: "Cross unseen"
                        )
                    )
                ),
                CampaignEvent(
                    id: UUID(uuidString: "14141414-1414-4141-8141-141414141414")!,
                    campaignID: PlayerSessionHarness.campaignID,
                    sequence: 0,
                    requestID: requestID,
                    timestamp: Date(timeIntervalSince1970: 4),
                    schemaVersion: 1,
                    payload: .gmMessageCommitted(
                        GMMessageCommittedPayload(
                            messageID: UUID(uuidString: "15151515-1515-4151-8151-151515151515")!,
                            narration: ["The bridge waits in the rain."],
                            dialogue: [],
                            beats: [],
                            finalQuestion: ""
                        )
                    )
                )
            ]
        )
        defer { harness.removeFiles() }

        let model = harness.makeModel()
        try await model.load()
        #expect(model.state?.pendingRoll?.rollID == rollID)

        let result = try await model.resolveRoll(rollID: rollID)

        #expect(result.rollID == rollID)
        #expect(result.results.count == 1)
        #expect(result.total == result.results[0] + result.modifier)
        #expect(model.state?.pendingRoll == nil)
        #expect(model.state?.lastResolvedRoll == result)
        #expect(model.projection?.pendingRolls[rollID] == nil)
        #expect(model.projection?.resolvedRolls[rollID] == result)
        #expect(
            (try await harness.store.events(
                for: PlayerSessionHarness.campaignID,
                after: 0,
                limit: 32
            )).filter {
                if case .rollResolved = $0.payload { return true }
                return false
            }.count == 1
        )

        await #expect(throws: PlayerSessionModelError.rollNotPending) {
            _ = try await model.resolveRoll(rollID: rollID)
        }
        #expect(
            (try await harness.store.events(
                for: PlayerSessionHarness.campaignID,
                after: 0,
                limit: 32
            )).filter {
                if case .rollResolved = $0.payload { return true }
                return false
            }.count == 1
        )
    }

    @Test
    func duplicateResolutionConflictReloadsAndReturnsCanonicalResult() async throws {
        let roll = PlayerSessionRollFixtures.firstRoll
        let harness = try await PlayerSessionHarness.make(
            eventsAfterImport: PlayerSessionRollFixtures.events(
                rolls: [roll]
            )
        )
        defer { harness.removeFiles() }

        let model = harness.makeModel()
        try await model.load()

        let canonical = RollResolvedPayload(
            rollID: roll.rollID,
            results: [10],
            modifier: 4,
            total: 14
        )
        _ = try await harness.store.appendRollResolution(
            batch: [
                CampaignEvent(
                    id: PlayerSessionRollFixtures.externalResolutionEventID,
                    campaignID: PlayerSessionHarness.campaignID,
                    sequence: 0,
                    requestID: PlayerSessionRollFixtures.requestID,
                    timestamp: Date(timeIntervalSince1970: 10),
                    schemaVersion: 1,
                    payload: .rollResolved(canonical)
                )
            ],
            expectedSequence: 4
        )

        let result = try await model.resolveRoll(rollID: roll.rollID)

        #expect(result == canonical)
        #expect(model.state?.pendingRoll == nil)
        #expect(model.state?.resolvedRolls[roll.rollID] == canonical)
        #expect(model.projection?.resolvedRolls[roll.rollID] == canonical)
        #expect(
            (try await harness.store.events(
                for: PlayerSessionHarness.campaignID,
                after: 0,
                limit: 32
            )).filter {
                if case .rollResolved = $0.payload { return true }
                return false
            }.count == 1
        )
    }

    @Test
    func expectedSequenceConflictReloadsAndReportsRollNoLongerPending() async throws {
        let roll = PlayerSessionRollFixtures.firstRoll
        let harness = try await PlayerSessionHarness.make(
            eventsAfterImport: PlayerSessionRollFixtures.events(
                rolls: [roll]
            )
        )
        defer { harness.removeFiles() }

        let model = harness.makeModel()
        try await model.load()

        _ = try await harness.store.append(
            batch: [
                CampaignEvent(
                    id: PlayerSessionRollFixtures.externalActionEventID,
                    campaignID: PlayerSessionHarness.campaignID,
                    sequence: 0,
                    requestID: PlayerSessionRollFixtures.externalRequestID,
                    timestamp: Date(timeIntervalSince1970: 11),
                    schemaVersion: 1,
                    payload: .playerActionSubmitted(
                        PlayerActionSubmittedPayload(action: "Take another path")
                    )
                )
            ],
            expectedSequence: 4
        )

        await #expect(throws: PlayerSessionModelError.rollNotPending) {
            _ = try await model.resolveRoll(rollID: roll.rollID)
        }

        #expect(model.state?.pendingRoll == nil)
        #expect(model.state?.activeRequestID == PlayerSessionRollFixtures.externalRequestID.uuidString)
        #expect(
            (try await harness.store.events(
                for: PlayerSessionHarness.campaignID,
                after: 0,
                limit: 32
            )).contains {
                if case .rollResolved = $0.payload { return true }
                return false
            } == false
        )
    }

    @Test
    func multipleRollResultsStayKeyedToTheirRollIDsAndLatestResolution() async throws {
        let earlierRoll = PlayerSessionRollFixtures.firstRoll
        let laterRoll = PlayerSessionRollFixtures.secondRoll
        let harness = try await PlayerSessionHarness.make(
            eventsAfterImport: PlayerSessionRollFixtures.events(
                rolls: [earlierRoll, laterRoll]
            )
        )
        defer { harness.removeFiles() }

        let model = harness.makeModel()
        try await model.load()
        #expect(model.state?.pendingRoll?.rollID == earlierRoll.rollID)

        let laterResult = try await model.resolveRoll(rollID: laterRoll.rollID)
        #expect(model.state?.pendingRoll?.rollID == earlierRoll.rollID)
        #expect(model.state?.resolvedRolls[laterRoll.rollID] == laterResult)
        #expect(model.state?.lastResolvedRoll == laterResult)

        let earlierResult = try await model.resolveRoll(rollID: earlierRoll.rollID)
        #expect(model.state?.pendingRoll == nil)
        #expect(model.state?.resolvedRolls[earlierRoll.rollID] == earlierResult)
        #expect(model.state?.resolvedRolls[laterRoll.rollID] == laterResult)
        #expect(model.state?.lastResolvedRoll == earlierResult)
        #expect(model.projection?.latestResolvedRollID == earlierRoll.rollID)
    }
}

private enum PlayerSessionRollFixtures {
    static let requestID = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!
    static let externalRequestID = UUID(uuidString: "99999999-9999-4999-8999-999999999999")!
    static let firstRoll = RollRequestedPayload(
        rollID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
        expression: "1d20+4",
        prompt: "Cross unseen"
    )
    static let secondRoll = RollRequestedPayload(
        rollID: UUID(uuidString: "ffffffff-ffff-4fff-8fff-ffffffffffff")!,
        expression: "1d20+1",
        prompt: "Read the current"
    )
    static let externalResolutionEventID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1")!
    static let externalActionEventID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2")!

    static func events(rolls: [RollRequestedPayload]) -> [CampaignEvent] {
        var events = [
            CampaignEvent(
                id: UUID(uuidString: "12121212-1212-4121-8121-121212121212")!,
                campaignID: PlayerSessionHarness.campaignID,
                sequence: 0,
                requestID: requestID,
                timestamp: Date(timeIntervalSince1970: 2),
                schemaVersion: 1,
                payload: .playerActionSubmitted(
                    PlayerActionSubmittedPayload(action: "Cross the bridge")
                )
            )
        ]
        for (index, roll) in rolls.enumerated() {
            let eventID = index == 0
                ? UUID(uuidString: "13131313-1313-4131-8131-131313131313")!
                : UUID(uuidString: "14141414-1414-4141-8141-141414141414")!
            events.append(
                CampaignEvent(
                    id: eventID,
                    campaignID: PlayerSessionHarness.campaignID,
                    sequence: 0,
                    requestID: requestID,
                    timestamp: Date(timeIntervalSince1970: 3 + Double(index)),
                    schemaVersion: 1,
                    payload: .rollRequested(roll)
                )
            )
        }
        events.append(
            CampaignEvent(
                id: UUID(uuidString: "15151515-1515-4151-8151-151515151515")!,
                campaignID: PlayerSessionHarness.campaignID,
                sequence: 0,
                requestID: requestID,
                timestamp: Date(timeIntervalSince1970: 5),
                schemaVersion: 1,
                payload: .gmMessageCommitted(
                    GMMessageCommittedPayload(
                        messageID: UUID(uuidString: "16161616-1616-4161-8161-161616161616")!,
                        narration: ["The crossing waits."],
                        dialogue: [],
                        beats: [],
                        finalQuestion: "What do you do?"
                    )
                )
            )
        )
        return events
    }
}

private struct PlayerSessionHarness {
    static let campaignID = UUID(
        uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    )!

    let supportDirectory: URL
    let store: SwiftDataCampaignStore
    let campaignDirectory: CampaignDirectory
    let presentationFileURL: URL

    static func make(
        eventsAfterImport: [CampaignEvent] = []
    ) async throws -> PlayerSessionHarness {
        let supportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "player-session-model-\(UUID().uuidString.lowercased())",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true
        )

        let project = try await normalizedFullProject(
            stagingSupport: supportDirectory.appendingPathComponent(
                "FixtureStaging",
                isDirectory: true
            )
        )
        let campaignDirectory = CampaignDirectory(
            applicationSupportDirectory: supportDirectory
        )
        let campaignURL = campaignDirectory.campaignURL(for: campaignID)
        try FileManager.default.createDirectory(
            at: campaignURL,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(project).write(
            to: campaignURL.appendingPathComponent("normalized-project.json"),
            options: .atomic
        )

        let container = try ModelContainer(
            for: CampaignEventRecord.self,
            ImportedAssetRecord.self,
            ProjectionCheckpointRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = SwiftDataCampaignStore(modelContainer: container)
        _ = try await store.append(
            batch: [
                CampaignEvent(
                    id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
                    campaignID: campaignID,
                    sequence: 0,
                    requestID: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
                    timestamp: Date(timeIntervalSince1970: 1),
                    schemaVersion: 1,
                    payload: .campaignImported(
                        CampaignImportedPayload(
                            projectID: project.id,
                            campaignTitle: "Imported Greyhaven",
                            manifestHash: "sha256:model-test"
                        )
                    )
                )
            ],
            expectedSequence: 0
        )
        if eventsAfterImport.isEmpty == false {
            _ = try await store.append(
                batch: eventsAfterImport,
                expectedSequence: 1
            )
        }

        return PlayerSessionHarness(
            supportDirectory: supportDirectory,
            store: store,
            campaignDirectory: campaignDirectory,
            presentationFileURL: supportDirectory.appendingPathComponent(
                "player-presentation.json",
                isDirectory: false
            )
        )
    }

    @MainActor
    func makeModel(
        presentationStore: (any PlayerPresentationPersisting)? = nil
    ) -> PlayerSessionModel {
        PlayerSessionModel(
            campaignID: Self.campaignID,
            projectionLoader: ProjectionLoader(store: store),
            campaignDirectory: campaignDirectory,
            presentationStore: presentationStore
                ?? PlayerPresentationStore(fileURL: presentationFileURL),
            campaignStore: store
        )
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: supportDirectory)
    }

    private static func normalizedFullProject(
        stagingSupport: URL
    ) async throws -> NormalizedProject {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "RPGPlayer/Fixtures/Imports/CDFv2/Sources/full",
                isDirectory: true
            )
        let staged = try await ImportStager(
            applicationSupportDirectory: stagingSupport
        ).stage(.folder(source))
        return try CDFDecoder().decodeProject(staged)
    }
}

private actor FailingPresentationStore: PlayerPresentationPersisting {
    func presentation(
        for campaignID: UUID
    ) throws -> PlayerPresentationState? {
        nil
    }

    func savePresentation(_ presentation: PlayerPresentationState) throws {
        throw PresentationStoreTestError.writeFailed
    }
}

private enum PresentationStoreTestError: Error, Equatable {
    case writeFailed
}
