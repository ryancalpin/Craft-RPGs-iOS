import Foundation
import SwiftData

@ModelActor
public actor SwiftDataCampaignStore: CampaignStore {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public func campaigns() throws -> [CampaignSummary] {
        let importedKind = CampaignEventPayload.Kind.campaignImported.rawValue
        let descriptor = FetchDescriptor<CampaignEventRecord>(
            predicate: #Predicate {
                $0.sequence == 1 && $0.payloadType == importedKind
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        return try modelContext.fetch(descriptor).map { record in
            guard case .campaignImported(let payload) = try decodeEvent(record).payload
            else {
                throw CampaignStoreError.invalidStoredPayload(
                    eventID: record.eventID
                )
            }
            return CampaignSummary(
                campaignID: record.campaignID,
                title: payload.campaignTitle,
                projectID: payload.projectID,
                importedAt: record.timestamp
            )
        }
    }

    /// A request ID identifies one atomic append operation. Phase 3 must place
    /// the submitted action and its terminal/final events in the same batch;
    /// every event in that batch intentionally carries the same request ID.
    public func append(
        batch: [CampaignEvent],
        assets: [ImportedAsset],
        expectedSequence: Int64
    ) throws -> [CampaignEvent] {
        guard let first = batch.first else {
            return []
        }

        guard batch.allSatisfy({ $0.campaignID == first.campaignID }) else {
            throw CampaignStoreError.mixedCampaignBatch
        }
        guard batch.allSatisfy({ $0.requestID == first.requestID }) else {
            throw CampaignStoreError.mixedRequestBatch
        }
        if let unsupported = batch.first(where: { $0.schemaVersion != 1 }) {
            throw CampaignStoreError.unsupportedSchemaVersion(
                eventID: unsupported.id,
                version: unsupported.schemaVersion
            )
        }
        for asset in assets {
            guard Self.isAppRelative(asset.appRelativeURL) else {
                throw CampaignStoreError.invalidImportedAssetURL(
                    asset.appRelativeURL
                )
            }
        }

        var eventIDs = Set<UUID>()
        for event in batch where eventIDs.insert(event.id).inserted == false {
            throw CampaignStoreError.duplicateEventID(event.id)
        }

        let payloads = try batch.map { event in
            do {
                return try encoder.encode(event.payload)
            } catch {
                throw CampaignStoreError.invalidPayload(eventID: event.id)
            }
        }

        var appended: [CampaignEvent] = []
        do {
            try modelContext.transaction {
                let existing = try eventRecords(for: first.campaignID)
                if existing.contains(where: {
                    $0.requestID == first.requestID
                }) {
                    throw CampaignStoreError.duplicateRequestID(first.requestID)
                }

                let existingEventIDs = Set(existing.map(\.eventID))
                if let duplicate = batch.first(where: {
                    existingEventIDs.contains($0.id)
                }) {
                    throw CampaignStoreError.duplicateEventID(duplicate.id)
                }

                let latest = existing.map(\.sequence).max() ?? 0
                guard latest == expectedSequence else {
                    throw CampaignStoreError.expectedSequenceConflict(
                        expected: expectedSequence,
                        actual: latest
                    )
                }

                appended = zip(batch.indices, batch).map { index, event in
                    CampaignEvent(
                        id: event.id,
                        campaignID: event.campaignID,
                        sequence: latest + Int64(index) + 1,
                        requestID: event.requestID,
                        timestamp: event.timestamp,
                        schemaVersion: event.schemaVersion,
                        payload: event.payload
                    )
                }

                for (event, payloadData) in zip(appended, payloads) {
                    modelContext.insert(
                        CampaignEventRecord(
                            event: event,
                            payloadData: payloadData
                        )
                    )
                }
                for asset in assets {
                    modelContext.insert(
                        ImportedAssetRecord(
                            asset: asset,
                            campaignID: first.campaignID
                        )
                    )
                }
                try modelContext.save()
            }
        } catch let error as CampaignStoreError {
            modelContext.rollback()
            throw error
        } catch {
            modelContext.rollback()
            throw CampaignStoreError.persistenceFailure
        }
        return appended
    }

    public func events(
        for campaignID: UUID,
        after sequence: Int64,
        limit: Int
    ) throws -> [CampaignEvent] {
        guard limit > 0 else {
            return []
        }

        var descriptor = FetchDescriptor<CampaignEventRecord>(
            predicate: #Predicate {
                $0.campaignID == campaignID && $0.sequence > sequence
            },
            sortBy: [SortDescriptor(\.sequence)]
        )
        descriptor.fetchLimit = limit

        return try modelContext.fetch(descriptor).map(decodeEvent)
    }

    public func latestSequence(for campaignID: UUID) throws -> Int64 {
        var descriptor = FetchDescriptor<CampaignEventRecord>(
            predicate: #Predicate { $0.campaignID == campaignID },
            sortBy: [SortDescriptor(\.sequence, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.sequence ?? 0
    }

    public func importedAssets(for campaignID: UUID) throws -> [ImportedAsset] {
        let descriptor = FetchDescriptor<ImportedAssetRecord>(
            predicate: #Predicate { $0.campaignID == campaignID },
            sortBy: [SortDescriptor(\.appRelativeURL)]
        )

        return try modelContext.fetch(descriptor).map { record in
            guard let relativeURL = URL(string: record.appRelativeURL),
                  Self.isAppRelative(relativeURL) else {
                throw CampaignStoreError.invalidImportedAssetURL(
                    URL(string: record.appRelativeURL) ?? URL(fileURLWithPath: "/")
                )
            }
            return ImportedAsset(
                assetID: record.assetID,
                sha256: record.sha256,
                appRelativeURL: relativeURL
            )
        }
    }

    public func saveProjectionCheckpoint(
        _ checkpoint: ProjectionCheckpoint
    ) throws {
        let projectionData: Data
        do {
            projectionData = try encoder.encode(checkpoint.projection)
        } catch {
            throw CampaignStoreError.invalidProjectionCheckpoint(
                sourceSequence: checkpoint.sourceSequence
            )
        }

        do {
            try modelContext.transaction {
                let campaignID = checkpoint.campaignID
                let sourceSequence = checkpoint.sourceSequence
                let reducerSchemaVersion = checkpoint.reducerSchemaVersion
                var descriptor = FetchDescriptor<ProjectionCheckpointRecord>(
                    predicate: #Predicate {
                        $0.campaignID == campaignID
                            && $0.sourceSequence == sourceSequence
                            && $0.reducerSchemaVersion == reducerSchemaVersion
                    }
                )
                descriptor.fetchLimit = 1

                if let existing = try modelContext.fetch(descriptor).first {
                    existing.projectionData = projectionData
                } else {
                    modelContext.insert(
                        ProjectionCheckpointRecord(
                            checkpoint: checkpoint,
                            projectionData: projectionData
                        )
                    )
                }
                try modelContext.save()
            }
        } catch let error as CampaignStoreError {
            modelContext.rollback()
            throw error
        } catch {
            modelContext.rollback()
            throw CampaignStoreError.persistenceFailure
        }
    }

    public func latestProjectionCheckpoint(
        for campaignID: UUID,
        reducerSchemaVersion: Int
    ) throws -> ProjectionCheckpoint? {
        var descriptor = FetchDescriptor<ProjectionCheckpointRecord>(
            predicate: #Predicate {
                $0.campaignID == campaignID
                    && $0.reducerSchemaVersion == reducerSchemaVersion
            },
            sortBy: [SortDescriptor(\.sourceSequence, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        guard let record = try modelContext.fetch(descriptor).first else {
            return nil
        }

        do {
            let projection = try decoder.decode(
                CampaignProjection.self,
                from: record.projectionData
            )
            return ProjectionCheckpoint(
                campaignID: record.campaignID,
                sourceSequence: record.sourceSequence,
                reducerSchemaVersion: record.reducerSchemaVersion,
                projection: projection
            )
        } catch {
            throw CampaignStoreError.invalidProjectionCheckpoint(
                sourceSequence: record.sourceSequence
            )
        }
    }

    public func restoreCampaign(
        events: [CampaignEvent],
        assets: [ImportedAsset]
    ) async throws {
        guard let first = events.first else {
            return
        }

        guard events.allSatisfy({ $0.campaignID == first.campaignID }) else {
            throw CampaignStoreError.mixedCampaignBatch
        }
        if let unsupported = events.first(where: { $0.schemaVersion != 1 }) {
            throw CampaignStoreError.unsupportedSchemaVersion(
                eventID: unsupported.id,
                version: unsupported.schemaVersion
            )
        }
        for (index, event) in events.enumerated() {
            let expected = Int64(index) + 1
            guard event.sequence == expected else {
                throw CampaignStoreError.invalidRestoreSequence(
                    expected: expected,
                    actual: event.sequence
                )
            }
        }
        for asset in assets {
            guard Self.isAppRelative(asset.appRelativeURL) else {
                throw CampaignStoreError.invalidImportedAssetURL(
                    asset.appRelativeURL
                )
            }
        }

        var eventIDs = Set<UUID>()
        for event in events where eventIDs.insert(event.id).inserted == false {
            throw CampaignStoreError.duplicateEventID(event.id)
        }

        let payloads = try events.map { event in
            do {
                return try encoder.encode(event.payload)
            } catch {
                throw CampaignStoreError.invalidPayload(eventID: event.id)
            }
        }

        do {
            try modelContext.transaction {
                let campaignID = first.campaignID
                let existingEvents = try eventRecords(for: campaignID)
                let assetDescriptor = FetchDescriptor<ImportedAssetRecord>(
                    predicate: #Predicate { $0.campaignID == campaignID }
                )
                guard existingEvents.isEmpty,
                      try modelContext.fetchCount(assetDescriptor) == 0
                else {
                    throw CampaignStoreError.campaignAlreadyExists(campaignID)
                }

                for (event, payloadData) in zip(events, payloads) {
                    modelContext.insert(
                        CampaignEventRecord(
                            event: event,
                            payloadData: payloadData
                        )
                    )
                }
                for asset in assets {
                    modelContext.insert(
                        ImportedAssetRecord(
                            asset: asset,
                            campaignID: campaignID
                        )
                    )
                }
                try modelContext.save()
            }
        } catch let error as CampaignStoreError {
            modelContext.rollback()
            throw error
        } catch {
            modelContext.rollback()
            throw CampaignStoreError.persistenceFailure
        }
    }

    public func deleteCampaign(_ campaignID: UUID) throws {
        do {
            try modelContext.transaction {
                for event in try eventRecords(for: campaignID) {
                    modelContext.delete(event)
                }
                let assetDescriptor = FetchDescriptor<ImportedAssetRecord>(
                    predicate: #Predicate { $0.campaignID == campaignID }
                )
                for asset in try modelContext.fetch(assetDescriptor) {
                    modelContext.delete(asset)
                }
                let checkpointDescriptor =
                    FetchDescriptor<ProjectionCheckpointRecord>(
                        predicate: #Predicate {
                            $0.campaignID == campaignID
                        }
                    )
                for checkpoint in try modelContext.fetch(
                    checkpointDescriptor
                ) {
                    modelContext.delete(checkpoint)
                }
                try modelContext.save()
            }
        } catch {
            modelContext.rollback()
            throw CampaignStoreError.persistenceFailure
        }
    }

    private func eventRecords(
        for campaignID: UUID
    ) throws -> [CampaignEventRecord] {
        try modelContext.fetch(
            FetchDescriptor<CampaignEventRecord>(
                predicate: #Predicate { $0.campaignID == campaignID }
            )
        )
    }

    private func decodeEvent(_ record: CampaignEventRecord) throws -> CampaignEvent {
        let payload: CampaignEventPayload
        do {
            payload = try decoder.decode(
                CampaignEventPayload.self,
                from: record.payloadData
            )
        } catch {
            throw CampaignStoreError.invalidStoredPayload(
                eventID: record.eventID
            )
        }

        guard payload.kind.rawValue == record.payloadType else {
            throw CampaignStoreError.invalidStoredPayload(
                eventID: record.eventID
            )
        }

        return CampaignEvent(
            id: record.eventID,
            campaignID: record.campaignID,
            sequence: record.sequence,
            requestID: record.requestID,
            timestamp: record.timestamp,
            schemaVersion: record.schemaVersion,
            payload: payload
        )
    }

    private static func isAppRelative(_ url: URL) -> Bool {
        url.scheme == nil
            && url.relativeString.hasPrefix("/") == false
            && url.pathComponents.contains("..") == false
    }
}
