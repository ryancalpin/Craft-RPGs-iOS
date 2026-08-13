import Foundation
import SwiftData
import Testing
@testable import RPGPlayer

struct ProjectionLoaderTests {
    @Test
    func loaderStoresACompatibleCheckpointAtEachTwoHundredEventBoundary() async throws {
        let fixture = try makeLoaderFixture()
        let campaignID = try loaderUUID(500)
        _ = try await fixture.store.append(
            batch: try loaderEvents(
                campaignID: campaignID,
                eventRange: 1...200,
                requestID: 600
            ),
            expectedSequence: 0
        )

        let firstLoad = try await fixture.loader.load(campaignID: campaignID)
        let checkpoint200 = try await fixture.store.latestProjectionCheckpoint(
            for: campaignID,
            reducerSchemaVersion: CampaignReducer.reducerSchemaVersion
        )

        #expect(firstLoad.projection.appliedThroughSequence == 200)
        #expect(checkpoint200?.sourceSequence == 200)

        _ = try await fixture.store.append(
            batch: try loaderEvents(
                campaignID: campaignID,
                eventRange: 201...400,
                requestID: 601
            ),
            expectedSequence: 200
        )

        let secondLoad = try await fixture.loader.load(campaignID: campaignID)
        let checkpoint400 = try await fixture.store.latestProjectionCheckpoint(
            for: campaignID,
            reducerSchemaVersion: CampaignReducer.reducerSchemaVersion
        )

        #expect(secondLoad.checkpointSourceSequence == 200)
        #expect(secondLoad.projection.appliedThroughSequence == 400)
        #expect(checkpoint400?.sourceSequence == 400)
    }

    @Test
    func latestCompatibleCheckpointPlusTailExactlyMatchesFullReplay() async throws {
        let fixture = try makeLoaderFixture()
        let campaignID = try loaderUUID(510)
        let appended = try await fixture.store.append(
            batch: try loaderEvents(
                campaignID: campaignID,
                eventRange: 1...450,
                requestID: 610
            ),
            expectedSequence: 0
        )

        let initialLoad = try await fixture.loader.load(campaignID: campaignID)
        let checkpointLoad = try await fixture.loader.load(campaignID: campaignID)
        let fullReplay = CampaignReducer().reduce(
            CampaignProjection(campaignID: campaignID),
            events: appended
        )

        #expect(initialLoad.checkpointSourceSequence == nil)
        #expect(checkpointLoad.checkpointSourceSequence == 400)
        #expect(checkpointLoad.projection.appliedThroughSequence == 450)
        #expect(checkpointLoad.projection == fullReplay.projection)
        #expect(checkpointLoad.diagnostics.isEmpty)
    }

    @Test
    func legacyCheckpointSchemaFallsBackToFullReplay() async throws {
        #expect(CampaignReducer.reducerSchemaVersion == 3)
        let fixture = try makeLoaderFixture()
        let campaignID = try loaderUUID(520)
        let appended = try await fixture.store.append(
            batch: try loaderEvents(
                campaignID: campaignID,
                eventRange: 1...3,
                requestID: 620
            ),
            expectedSequence: 0
        )
        let incompatibleProjection = CampaignReducer().reduce(
            CampaignProjection(campaignID: campaignID),
            events: Array(appended.prefix(2))
        ).projection
        try await fixture.store.saveProjectionCheckpoint(
            ProjectionCheckpoint(
                sourceSequence: 2,
                reducerSchemaVersion: 1,
                projection: incompatibleProjection
            )
        )

        let loaded = try await fixture.loader.load(campaignID: campaignID)
        let fullReplay = CampaignReducer().reduce(
            CampaignProjection(campaignID: campaignID),
            events: appended
        )

        #expect(loaded.checkpointSourceSequence == nil)
        #expect(loaded.projection == fullReplay.projection)
        #expect(loaded.diagnostics.isEmpty)
    }

    @Test
    func invalidCompatibleCheckpointFallsBackToFullReplayWithDiagnostic() async throws {
        let fixture = try makeLoaderFixture()
        let campaignID = try loaderUUID(530)
        let appended = try await fixture.store.append(
            batch: try loaderEvents(
                campaignID: campaignID,
                eventRange: 1...3,
                requestID: 630
            ),
            expectedSequence: 0
        )
        let projectionThroughOne = CampaignReducer().reduce(
            CampaignProjection(campaignID: campaignID),
            events: Array(appended.prefix(1))
        ).projection
        try await fixture.store.saveProjectionCheckpoint(
            ProjectionCheckpoint(
                sourceSequence: 2,
                reducerSchemaVersion: CampaignReducer.reducerSchemaVersion,
                projection: projectionThroughOne
            )
        )

        let loaded = try await fixture.loader.load(campaignID: campaignID)
        let fullReplay = CampaignReducer().reduce(
            CampaignProjection(campaignID: campaignID),
            events: appended
        )

        #expect(loaded.checkpointSourceSequence == nil)
        #expect(loaded.projection == fullReplay.projection)
        #expect(
            loaded.diagnostics
                == [.invalidCheckpoint(sourceSequence: 2)]
        )
    }

    @Test
    func storedEventCorruptionReturnsTheLastSafeProjection() async throws {
        let fixture = try makeLoaderFixture()
        let campaignID = try loaderUUID(540)
        let appended = try await fixture.store.append(
            batch: try loaderEvents(
                campaignID: campaignID,
                eventRange: 1...3,
                requestID: 640
            ),
            expectedSequence: 0
        )
        let corruptor = CampaignEventRecordCorruptor(
            modelContainer: fixture.container
        )
        try await corruptor.corrupt(
            campaignID: campaignID,
            sequence: 3
        )

        let loaded = try await fixture.loader.load(campaignID: campaignID)

        #expect(loaded.projection.appliedThroughSequence == 2)
        #expect(loaded.projection.currentScene?.sceneID == "scene-2")
        #expect(
            loaded.diagnostics
                == [.storedEventCorruption(eventID: appended[2].id)]
        )
    }
}

private struct LoaderFixture {
    let container: ModelContainer
    let store: SwiftDataCampaignStore
    let loader: ProjectionLoader
}

private func makeLoaderFixture(pageSize: Int = 256) throws -> LoaderFixture {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: CampaignEventRecord.self,
        ImportedAssetRecord.self,
        ProjectionCheckpointRecord.self,
        configurations: configuration
    )
    let store = SwiftDataCampaignStore(modelContainer: container)
    return LoaderFixture(
        container: container,
        store: store,
        loader: ProjectionLoader(store: store, pageSize: pageSize)
    )
}

@ModelActor
private actor CampaignEventRecordCorruptor {
    func corrupt(campaignID: UUID, sequence: Int64) throws {
        var descriptor = FetchDescriptor<CampaignEventRecord>(
            predicate: #Predicate {
                $0.campaignID == campaignID && $0.sequence == sequence
            }
        )
        descriptor.fetchLimit = 1
        let record = try #require(modelContext.fetch(descriptor).first)
        record.payloadData = Data("not-json".utf8)
        try modelContext.save()
    }
}

private func loaderEvents(
    campaignID: UUID,
    eventRange: ClosedRange<Int>,
    requestID: Int
) throws -> [CampaignEvent] {
    try eventRange.map { eventNumber in
        CampaignEvent(
            id: try loaderUUID(10_000 + eventNumber),
            campaignID: campaignID,
            sequence: 0,
            requestID: try loaderUUID(requestID),
            timestamp: Date(
                timeIntervalSince1970: 1_726_100_000 + Double(eventNumber)
            ),
            schemaVersion: 1,
            payload: .sceneChanged(
                SceneChangedPayload(
                    sceneID: "scene-\(eventNumber)",
                    title: "Scene \(eventNumber)",
                    summary: "Deterministic checkpoint fixture"
                )
            )
        )
    }
}

private func loaderUUID(_ value: Int) throws -> UUID {
    let suffix = String(format: "%012d", value)
    guard let uuid = UUID(uuidString: "00000000-0000-0000-0000-\(suffix)") else {
        throw LoaderFixtureError.invalidUUID
    }
    return uuid
}

private enum LoaderFixtureError: Error {
    case invalidUUID
}
