import Foundation
import SwiftData
import Testing
@testable import RPGPlayer

struct CampaignStoreTests {
    @Test
    func campaignCatalogIsEmptyBeforeAnyImport() async throws {
        let store = try makeStore()

        #expect(try await store.campaigns().isEmpty)
    }

    @Test
    func campaignCatalogReturnsNewestImportedCampaignFirst() async throws {
        let store = try makeStore()
        let olderCampaignID = try fixtureUUID(401)
        let newerCampaignID = try fixtureUUID(402)

        _ = try await store.append(
            batch: [
                try makeImportedEvent(
                    campaignID: olderCampaignID,
                    eventID: 501,
                    requestID: 601,
                    title: "Older Campaign",
                    projectID: "project-older",
                    timestamp: Date(timeIntervalSince1970: 100)
                )
            ],
            expectedSequence: 0
        )
        _ = try await store.append(
            batch: [
                try makeImportedEvent(
                    campaignID: newerCampaignID,
                    eventID: 502,
                    requestID: 602,
                    title: "Newer Campaign",
                    projectID: "project-newer",
                    timestamp: Date(timeIntervalSince1970: 200)
                )
            ],
            expectedSequence: 0
        )

        #expect(
            try await store.campaigns() == [
                CampaignSummary(
                    campaignID: newerCampaignID,
                    title: "Newer Campaign",
                    projectID: "project-newer",
                    importedAt: Date(timeIntervalSince1970: 200)
                ),
                CampaignSummary(
                    campaignID: olderCampaignID,
                    title: "Older Campaign",
                    projectID: "project-older",
                    importedAt: Date(timeIntervalSince1970: 100)
                )
            ]
        )
    }

    @Test
    func deletingCampaignRemovesItFromCampaignCatalog() async throws {
        let store = try makeStore()
        let campaignID = try fixtureUUID(403)
        _ = try await store.append(
            batch: [
                try makeImportedEvent(
                    campaignID: campaignID,
                    eventID: 503,
                    requestID: 603,
                    title: "Delete Me",
                    projectID: "project-delete",
                    timestamp: Date(timeIntervalSince1970: 300)
                )
            ],
            expectedSequence: 0
        )

        try await store.deleteCampaign(campaignID)

        #expect(try await store.campaigns().isEmpty)
    }

    @Test
    func batchAppendAllowsSharedRequestIDAndPreservesTheFrozenEnvelope() async throws {
        let store = try makeStore()
        let campaignID = try fixtureUUID(1)
        let first = try makeEvent(
            campaignID: campaignID,
            eventID: 101,
            requestID: 201,
            proposedSequence: 44
        )
        let second = try makeEvent(
            campaignID: campaignID,
            eventID: 102,
            requestID: 201,
            proposedSequence: 99
        )

        let appended = try await store.append(
            batch: [first, second],
            expectedSequence: 0
        )

        #expect(appended.map(\.sequence) == [1, 2])
        #expect(appended[0].id == first.id)
        #expect(appended[0].campaignID == first.campaignID)
        #expect(appended[0].requestID == first.requestID)
        #expect(appended[0].timestamp == first.timestamp)
        #expect(appended[0].schemaVersion == first.schemaVersion)
        #expect(appended[0].payload == first.payload)
        #expect(
            try await store.events(for: campaignID, after: 0, limit: 10)
                == appended
        )
    }

    @Test
    func sequencesContinueMonotonicallyAcrossBatches() async throws {
        let store = try makeStore()
        let campaignID = try fixtureUUID(2)

        _ = try await store.append(
            batch: [try makeEvent(campaignID: campaignID, eventID: 111, requestID: 211)],
            expectedSequence: 0
        )
        let appended = try await store.append(
            batch: [
                try makeEvent(campaignID: campaignID, eventID: 112, requestID: 212),
                try makeEvent(campaignID: campaignID, eventID: 113, requestID: 212)
            ],
            expectedSequence: 1
        )

        #expect(appended.map(\.sequence) == [2, 3])
        #expect(try await store.latestSequence(for: campaignID) == 3)
    }

    @Test
    func duplicateEventIDRejectsTheWholeBatch() async throws {
        let store = try makeStore()
        let campaignID = try fixtureUUID(3)
        let existing = try makeEvent(
            campaignID: campaignID,
            eventID: 121,
            requestID: 221
        )
        _ = try await store.append(batch: [existing], expectedSequence: 0)

        let duplicate = try makeEvent(
            campaignID: campaignID,
            eventID: 121,
            requestID: 222
        )
        await expectError(.duplicateEventID(existing.id)) {
            _ = try await store.append(
                batch: [
                    duplicate,
                    try makeEvent(campaignID: campaignID, eventID: 122, requestID: 222)
                ],
                expectedSequence: 1
            )
        }

        #expect(try await store.latestSequence(for: campaignID) == 1)
        #expect(
            try await store.events(for: campaignID, after: 0, limit: 10).count
                == 1
        )
    }

    @Test
    func duplicateRequestIDRejectsTheWholeBatch() async throws {
        let store = try makeStore()
        let campaignID = try fixtureUUID(4)
        let existing = try makeEvent(
            campaignID: campaignID,
            eventID: 131,
            requestID: 231
        )
        _ = try await store.append(batch: [existing], expectedSequence: 0)

        await expectError(.duplicateRequestID(existing.requestID)) {
            _ = try await store.append(batch: [existing], expectedSequence: 1)
        }

        #expect(try await store.latestSequence(for: campaignID) == 1)
    }

    @Test
    func staleExpectedSequenceRejectsTheWholeBatch() async throws {
        let store = try makeStore()
        let campaignID = try fixtureUUID(5)
        _ = try await store.append(
            batch: [try makeEvent(campaignID: campaignID, eventID: 141, requestID: 241)],
            expectedSequence: 0
        )

        await expectError(
            .expectedSequenceConflict(expected: 0, actual: 1)
        ) {
            _ = try await store.append(
                batch: [
                    try makeEvent(campaignID: campaignID, eventID: 142, requestID: 242),
                    try makeEvent(campaignID: campaignID, eventID: 143, requestID: 242)
                ],
                expectedSequence: 0
            )
        }

        #expect(try await store.latestSequence(for: campaignID) == 1)
    }

    @Test
    func invalidPayloadRollsBackEveryRowInTheBatch() async throws {
        let store = try makeStore()
        let campaignID = try fixtureUUID(6)
        let invalidID = try fixtureUUID(152)
        let invalid = CampaignEvent(
            id: invalidID,
            campaignID: campaignID,
            sequence: 0,
            requestID: try fixtureUUID(252),
            timestamp: Date(timeIntervalSince1970: 1_726_000_152),
            schemaVersion: 1,
            payload: .recordPatched(
                RecordPatchedPayload(
                    recordID: "record-invalid",
                    changes: ["notJSON": .number(.nan)]
                )
            )
        )
        let assetURL = try #require(URL(string: "ImportedAssets/maps/rollback.png"))
        let asset = ImportedAsset(
            assetID: "asset-must-rollback",
            sha256: "f47ac10b58cc4372a5670e02b2c3d479",
            appRelativeURL: assetURL
        )

        await expectError(.invalidPayload(eventID: invalidID)) {
            _ = try await store.append(
                batch: [
                    try makeEvent(campaignID: campaignID, eventID: 151, requestID: 252),
                    invalid
                ],
                assets: [asset],
                expectedSequence: 0
            )
        }

        #expect(try await store.latestSequence(for: campaignID) == 0)
        #expect(
            try await store.events(for: campaignID, after: 0, limit: 10)
                .isEmpty
        )
        #expect(try await store.importedAssets(for: campaignID).isEmpty)
    }

    @Test
    func unsupportedEventSchemaWritesNoRows() async throws {
        let store = try makeStore()
        let campaignID = try fixtureUUID(61)
        let event = try makeEvent(
            campaignID: campaignID,
            eventID: 153,
            requestID: 253,
            schemaVersion: 2
        )

        await expectError(
            .unsupportedSchemaVersion(eventID: event.id, version: 2)
        ) {
            _ = try await store.append(batch: [event], expectedSequence: 0)
        }

        #expect(try await store.latestSequence(for: campaignID) == 0)
        #expect(
            try await store.events(for: campaignID, after: 0, limit: 10)
                .isEmpty
        )
    }

    @Test
    func eventsAfterSequenceAreOrderedAndLimited() async throws {
        let store = try makeStore()
        let campaignID = try fixtureUUID(7)
        let batch = try (1...4).map { offset in
            try makeEvent(
                campaignID: campaignID,
                eventID: 160 + offset,
                requestID: 261
            )
        }
        _ = try await store.append(batch: batch, expectedSequence: 0)

        let page = try await store.events(
            for: campaignID,
            after: 1,
            limit: 2
        )

        #expect(page.map(\.sequence) == [2, 3])
        #expect(page.map(\.id) == Array(batch[1...2]).map(\.id))
    }

    @Test
    func latestSequenceUsesZeroForAStoredCampaignWithoutEvents() async throws {
        let store = try makeStore()
        let campaignID = try fixtureUUID(8)

        #expect(try await store.latestSequence(for: campaignID) == 0)

        _ = try await store.append(
            batch: [try makeEvent(campaignID: campaignID, eventID: 171, requestID: 271)],
            expectedSequence: 0
        )

        #expect(try await store.latestSequence(for: campaignID) == 1)
    }

    @Test
    func importedAssetsPersistOnlyHashAndAppOwnedRelativeURL() async throws {
        let store = try makeStore()
        let campaignID = try fixtureUUID(9)
        let relativeURL = try #require(URL(string: "ImportedAssets/maps/castle.png"))
        let asset = ImportedAsset(
            assetID: "asset-map-castle",
            sha256: "3a7bd3e2360a3d80d15d2f0b01fda75a",
            appRelativeURL: relativeURL
        )

        _ = try await store.append(
            batch: [
                try makeEvent(
                    campaignID: campaignID,
                    eventID: 181,
                    requestID: 281
                )
            ],
            assets: [asset],
            expectedSequence: 0
        )

        let persisted = try await store.importedAssets(for: campaignID)
        #expect(persisted == [asset])
        #expect(persisted[0].appRelativeURL.scheme == nil)
        #expect(persisted[0].appRelativeURL.path.hasPrefix("/") == false)
    }

    @Test
    func deleteCampaignRemovesEventsAndImportedAssets() async throws {
        let store = try makeStore()
        let campaignID = try fixtureUUID(10)
        let otherCampaignID = try fixtureUUID(11)
        let relativeURL = try #require(URL(string: "ImportedAssets/portraits/hero.png"))
        _ = try await store.append(
            batch: [
                try makeEvent(
                    campaignID: campaignID,
                    eventID: 191,
                    requestID: 291
                )
            ],
            assets: [
                ImportedAsset(
                    assetID: "asset-portrait-hero",
                    sha256: "b94d27b9934d3e08a52e52d7da7dabfa",
                    appRelativeURL: relativeURL
                )
            ],
            expectedSequence: 0
        )
        let otherURL = try #require(URL(string: "ImportedAssets/maps/survivor.png"))
        _ = try await store.append(
            batch: [
                try makeEvent(
                    campaignID: otherCampaignID,
                    eventID: 193,
                    requestID: 293
                )
            ],
            assets: [
                ImportedAsset(
                    assetID: "asset-other-campaign",
                    sha256: "9e107d9d372bb6826bd81d3542a419d6",
                    appRelativeURL: otherURL
                )
            ],
            expectedSequence: 0
        )

        try await store.deleteCampaign(campaignID)

        #expect(try await store.latestSequence(for: campaignID) == 0)
        #expect(
            try await store.events(for: campaignID, after: 0, limit: 10)
                .isEmpty
        )
        #expect(try await store.importedAssets(for: campaignID).isEmpty)
        #expect(try await store.latestSequence(for: otherCampaignID) == 1)
        #expect(
            try await store.events(
                for: otherCampaignID,
                after: 0,
                limit: 10
            ).count == 1
        )
        #expect(
            try await store.importedAssets(for: otherCampaignID).map(\.assetID)
                == ["asset-other-campaign"]
        )
    }
}

private func makeStore() throws -> SwiftDataCampaignStore {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: CampaignEventRecord.self,
        ImportedAssetRecord.self,
        ProjectionCheckpointRecord.self,
        configurations: configuration
    )
    return SwiftDataCampaignStore(modelContainer: container)
}

private func makeEvent(
    campaignID: UUID,
    eventID: Int,
    requestID: Int,
    proposedSequence: Int64 = 0,
    schemaVersion: Int = 1
) throws -> CampaignEvent {
    CampaignEvent(
        id: try fixtureUUID(eventID),
        campaignID: campaignID,
        sequence: proposedSequence,
        requestID: try fixtureUUID(requestID),
        timestamp: Date(timeIntervalSince1970: 1_726_000_000 + Double(eventID)),
        schemaVersion: schemaVersion,
        payload: .sceneChanged(
            SceneChangedPayload(
                sceneID: "scene-\(eventID)",
                title: "Scene \(eventID)",
                summary: "Deterministic fixture"
            )
        )
    )
}

private func makeImportedEvent(
    campaignID: UUID,
    eventID: Int,
    requestID: Int,
    title: String,
    projectID: String,
    timestamp: Date
) throws -> CampaignEvent {
    CampaignEvent(
        id: try fixtureUUID(eventID),
        campaignID: campaignID,
        sequence: 0,
        requestID: try fixtureUUID(requestID),
        timestamp: timestamp,
        schemaVersion: 1,
        payload: .campaignImported(
            CampaignImportedPayload(
                projectID: projectID,
                campaignTitle: title,
                manifestHash: "sha256:catalog"
            )
        )
    )
}

private func fixtureUUID(_ value: Int) throws -> UUID {
    let suffix = String(format: "%012d", value)
    guard let value = UUID(uuidString: "00000000-0000-0000-0000-\(suffix)") else {
        throw CampaignStoreTestFixtureError.invalidUUID
    }
    return value
}

private func expectError(
    _ expected: CampaignStoreError,
    operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected \(expected) to be thrown")
    } catch let error as CampaignStoreError {
        #expect(error == expected)
    } catch {
        Issue.record("Expected \(expected), got \(error)")
    }
}

private enum CampaignStoreTestFixtureError: Error {
    case invalidUUID
}
