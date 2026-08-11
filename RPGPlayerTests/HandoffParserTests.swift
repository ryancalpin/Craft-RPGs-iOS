import Foundation
import Testing
@testable import RPGPlayer

struct HandoffParserTests {
    @Test
    func markdownHeadingsPopulateOnlyTheirNamedEditableFields() {
        let handoff = """
        # Greyhaven handoff

        ## Summary
        The party escaped the flooded archive.

        ## Current Scene
        Under the bell tower at dawn.

        ## Player Character
        Mara Voss

        ## Unresolved Threads
        - Find the missing archivist
        - Repay Orin's favor

        ## Inventory Deltas
        - Moon key: +1
        - Torch: -2

        ## Last Known Player Choice
        Trust the ferryman.
        """

        let draft = HandoffParser().parse(handoff)

        #expect(draft.summary == "The party escaped the flooded archive.")
        #expect(draft.currentScene == "Under the bell tower at dawn.")
        #expect(draft.playerCharacter == "Mara Voss")
        #expect(
            draft.unresolvedThreads
                == ["Find the missing archivist", "Repay Orin's favor"]
        )
        #expect(draft.inventoryDeltas == ["Moon key": 1, "Torch": -2])
        #expect(draft.lastKnownPlayerChoice == "Trust the ferryman.")
        #expect(draft.detectedSpeakers.isEmpty)
        #expect(draft.reviewFlags.isEmpty)
    }

    @Test
    func speakerPrefixedDialogueExposesCandidatesWithoutGuessingThePlayer() throws {
        let handoff = """
        Mara: We should take the north road.
        Mara: The bridge will not hold until morning.
        """

        let draft = HandoffParser().parse(handoff)

        #expect(draft.detectedSpeakers == ["Mara"])
        #expect(draft.playerCharacter.isEmpty)
        #expect(draft.summary.isEmpty)
        #expect(draft.reviewFlags == [.speakerMappingRequired])

        let checkpoint = try draft.approvedCheckpoint(
            confirmingUserApproval: true
        )
        let encoded = try JSONEncoder().encode(checkpoint)
        let stored = String(decoding: encoded, as: UTF8.self)

        #expect(stored.contains("north road") == false)
        #expect(stored.contains("bridge will not hold") == false)
    }

    @Test
    func plainTextBecomesAnEditableSummaryMarkedForReview() {
        let draft = HandoffParser().parse(
            "  We reached Greyhaven. The gate remains sealed.  "
        )

        #expect(
            draft.summary
                == "We reached Greyhaven. The gate remains sealed."
        )
        #expect(draft.currentScene.isEmpty)
        #expect(draft.playerCharacter.isEmpty)
        #expect(draft.reviewFlags == [.unstructuredText])
    }

    @Test
    func emptyInputProducesAnEmptyDraftInsteadOfClaimingRecovery() {
        let draft = HandoffParser().parse(" \n\n ")

        #expect(draft.summary.isEmpty)
        #expect(draft.currentScene.isEmpty)
        #expect(draft.playerCharacter.isEmpty)
        #expect(draft.unresolvedThreads.isEmpty)
        #expect(draft.inventoryDeltas.isEmpty)
        #expect(draft.lastKnownPlayerChoice.isEmpty)
        #expect(draft.detectedSpeakers.isEmpty)
        #expect(draft.reviewFlags == [.emptyInput])
    }

    @Test
    func multipleSpeakerNamesRemainAnExplicitAmbiguity() {
        let handoff = """
        Rowan: We should wait for the watch to pass.
        Mara: Open the gate.
        """

        let draft = HandoffParser().parse(handoff)

        #expect(draft.detectedSpeakers == ["Mara", "Rowan"])
        #expect(draft.playerCharacter.isEmpty)
        #expect(
            draft.reviewFlags
                == [.speakerMappingRequired, .ambiguousSpeakerNames]
        )
    }

    @Test
    func originalBytesProduceAStableSHA256ReferenceBeforeTextParsing() throws {
        let originalData = Data("hello".utf8)
        let draft = try HandoffParser().parse(data: originalData)

        #expect(
            draft.originalHandoffSHA256
                == "sha256:2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
    }

    @Test
    func lineEndingNormalizationDoesNotChangeFieldsButDoesChangeSourceHash() throws {
        let lineFeed = """
        ## Summary
        We reached Greyhaven.
        ## Current Scene
        Outside the western gate.
        """
        let carriageReturnLineFeed = lineFeed.replacingOccurrences(
            of: "\n",
            with: "\r\n"
        )

        let lineFeedDraft = try HandoffParser().parse(
            data: Data(lineFeed.utf8)
        )
        let carriageReturnLineFeedDraft = try HandoffParser().parse(
            data: Data(carriageReturnLineFeed.utf8)
        )

        #expect(lineFeedDraft.summary == carriageReturnLineFeedDraft.summary)
        #expect(
            lineFeedDraft.currentScene
                == carriageReturnLineFeedDraft.currentScene
        )
        #expect(
            lineFeedDraft.originalHandoffSHA256
                != carriageReturnLineFeedDraft.originalHandoffSHA256
        )
    }

    @Test
    func checkpointCreationRequiresExplicitApproval() {
        let draft = HandoffParser().parse("A short campaign summary.")

        #expect(throws: HandoffApprovalError.explicitApprovalRequired) {
            try draft.approvedCheckpoint(confirmingUserApproval: false)
        }
    }

    @Test
    func approvedUserEditsMapIntoTheCampaignImportedPayload() throws {
        var draft = HandoffParser().parse("An incomplete handoff.")
        draft.summary = "Edited campaign summary"
        draft.currentScene = "The western gate"
        draft.playerCharacter = "Mara Voss"
        draft.unresolvedThreads = ["Find Rowan", "Decode the moon key"]
        draft.inventoryDeltas = ["Moon key": 1, "Torch": -2]
        draft.lastKnownPlayerChoice = "Wait for the watch to pass"

        let checkpoint = try draft.approvedCheckpoint(
            confirmingUserApproval: true
        )
        let originalPayload = CampaignImportedPayload(
            projectID: "project-greyhaven",
            campaignTitle: "Fog Over Greyhaven",
            manifestHash: "sha256:manifest",
            extensionPayload: ["preserveMe": .bool(true)]
        )
        let mappedPayload = checkpoint.applying(to: originalPayload)

        #expect(checkpoint.originalHandoffSHA256 == draft.originalHandoffSHA256)
        #expect(checkpoint.summary == "Edited campaign summary")
        #expect(checkpoint.currentScene == "The western gate")
        #expect(checkpoint.playerCharacter == "Mara Voss")
        #expect(
            checkpoint.unresolvedThreads
                == ["Find Rowan", "Decode the moon key"]
        )
        #expect(checkpoint.inventoryDeltas == ["Moon key": 1, "Torch": -2])
        #expect(
            checkpoint.lastKnownPlayerChoice
                == "Wait for the watch to pass"
        )
        #expect(mappedPayload.extensionPayload["preserveMe"] == .bool(true))
        #expect(
            mappedPayload.extensionPayload["handoffCheckpoint"]?.objectValue?["schemaVersion"]
                == .integer(1)
        )
        #expect(mappedPayload.handoffCheckpoint == checkpoint)

        let encodedPayload = try JSONEncoder().encode(mappedPayload)
        let decodedPayload = try JSONDecoder().decode(
            CampaignImportedPayload.self,
            from: encodedPayload
        )

        #expect(decodedPayload.extensionPayload["preserveMe"] == .bool(true))
        #expect(decodedPayload.handoffCheckpoint == checkpoint)
    }
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }
}
