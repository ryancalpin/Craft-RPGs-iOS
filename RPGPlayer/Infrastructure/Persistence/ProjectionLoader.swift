import Foundation
import SwiftData

@Model
final class ProjectionCheckpointRecord {
    #Unique<ProjectionCheckpointRecord>(
        [\.campaignID, \.sourceSequence, \.reducerSchemaVersion]
    )

    #Index<ProjectionCheckpointRecord>(
        [\.campaignID, \.reducerSchemaVersion, \.sourceSequence]
    )

    var campaignID: UUID
    var sourceSequence: Int64
    var reducerSchemaVersion: Int
    var projectionData: Data

    init(checkpoint: ProjectionCheckpoint, projectionData: Data) {
        campaignID = checkpoint.campaignID
        sourceSequence = checkpoint.sourceSequence
        reducerSchemaVersion = checkpoint.reducerSchemaVersion
        self.projectionData = projectionData
    }
}

public struct ProjectionLoadResult: Equatable, Sendable {
    public let projection: CampaignProjection
    public let diagnostics: [CampaignReplayDiagnostic]
    public let checkpointSourceSequence: Int64?

    public init(
        projection: CampaignProjection,
        diagnostics: [CampaignReplayDiagnostic],
        checkpointSourceSequence: Int64?
    ) {
        self.projection = projection
        self.diagnostics = diagnostics
        self.checkpointSourceSequence = checkpointSourceSequence
    }
}

public struct ProjectionLoader: Sendable {
    private let store: any CampaignStore
    private let reducer: CampaignReducer
    private let pageSize: Int
    private let checkpointInterval: Int64

    public init(
        store: any CampaignStore,
        reducer: CampaignReducer = CampaignReducer(),
        pageSize: Int = 256,
        checkpointInterval: Int64 = 200
    ) {
        self.store = store
        self.reducer = reducer
        self.pageSize = max(1, pageSize)
        self.checkpointInterval = max(1, checkpointInterval)
    }

    public func load(campaignID: UUID) async throws -> ProjectionLoadResult {
        let latestSequence = try await store.latestSequence(for: campaignID)
        var projection = CampaignProjection(campaignID: campaignID)
        var diagnostics: [CampaignReplayDiagnostic] = []
        var checkpointSourceSequence: Int64?

        do {
            if let checkpoint = try await store.latestProjectionCheckpoint(
                for: campaignID,
                reducerSchemaVersion: CampaignReducer.reducerSchemaVersion
            ) {
                if checkpoint.isValid(
                    for: campaignID,
                    latestSequence: latestSequence,
                    reducerSchemaVersion: CampaignReducer.reducerSchemaVersion
                ) {
                    projection = checkpoint.projection
                    checkpointSourceSequence = checkpoint.sourceSequence
                } else {
                    diagnostics.append(
                        .invalidCheckpoint(
                            sourceSequence: checkpoint.sourceSequence
                        )
                    )
                }
            }
        } catch CampaignStoreError.invalidProjectionCheckpoint(
            let sourceSequence
        ) {
            diagnostics.append(
                .invalidCheckpoint(sourceSequence: sourceSequence)
            )
        }

        var cursor = checkpointSourceSequence ?? 0
        var replayHalted = false
        var fetchLimit = pageSize
        while cursor < latestSequence {
            let events: [CampaignEvent]
            do {
                events = try await store.events(
                    for: campaignID,
                    after: cursor,
                    limit: fetchLimit
                )
            } catch CampaignStoreError.invalidStoredPayload(let eventID) {
                if fetchLimit > 1 {
                    fetchLimit = 1
                    continue
                }
                diagnostics.append(
                    .storedEventCorruption(eventID: eventID)
                )
                break
            }
            guard let lastEvent = events.last else {
                break
            }

            for event in events {
                let previousSequence = projection.appliedThroughSequence
                let result = reducer.reduce(projection, events: [event])
                projection = result.projection
                diagnostics.append(contentsOf: result.diagnostics)

                if projection.appliedThroughSequence == previousSequence,
                   result.diagnostics.isEmpty == false {
                    replayHalted = true
                    break
                }

                if projection.appliedThroughSequence != previousSequence,
                   projection.appliedThroughSequence.isMultiple(
                       of: checkpointInterval
                   ) {
                    try await store.saveProjectionCheckpoint(
                        ProjectionCheckpoint(
                            sourceSequence: projection.appliedThroughSequence,
                            reducerSchemaVersion: CampaignReducer.reducerSchemaVersion,
                            projection: projection
                        )
                    )
                }
            }
            if replayHalted {
                break
            }
            cursor = lastEvent.sequence
        }

        return ProjectionLoadResult(
            projection: projection,
            diagnostics: diagnostics,
            checkpointSourceSequence: checkpointSourceSequence
        )
    }
}
