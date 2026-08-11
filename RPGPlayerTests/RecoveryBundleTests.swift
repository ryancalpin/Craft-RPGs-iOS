import CryptoKit
import Foundation
import SwiftData
import Testing
import ZIPFoundation
@testable import RPGPlayer

struct RecoveryBundleTests {
    @Test
    func campaignDirectoryUsesOnlyTheExactLowercaseCampaignUUIDPath() throws {
        let supportURL = URL(fileURLWithPath: "/tmp/RPGPlayerRecoveryTests/Support")
        let campaignID = try #require(
            UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        )
        let directory = CampaignDirectory(
            applicationSupportDirectory: supportURL
        )
        let expected = supportURL
            .appendingPathComponent("Campaigns", isDirectory: true)
            .appendingPathComponent(
                "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                isDirectory: true
            )
            .standardizedFileURL

        #expect(directory.campaignURL(for: campaignID) == expected)
        #expect(directory.isExactCampaignURL(expected, for: campaignID))
        #expect(
            directory.isExactCampaignURL(
                supportURL.appendingPathComponent("Outside", isDirectory: true),
                for: campaignID
            ) == false
        )
        #expect(
            directory.isExactCampaignURL(
                expected.appendingPathComponent("assets", isDirectory: true),
                for: campaignID
            ) == false
        )
    }

    @Test
    func recoveryBundleVersionOneUsesTheFrozenRequiredEntryPaths() {
        #expect(RecoveryBundle.schemaVersion == 1)
        #expect(
            RecoveryBundle.requiredEntryPaths == [
                "manifest.json",
                "events.jsonl",
                "manual-voice-mappings.json",
                "campaign/normalized-project.json"
            ]
        )
    }

    @Test
    func storeRestorePreservesExactSequencesAcrossMultipleRequestRunsAndAssets() async throws {
        let store = try makeRecoveryStore()
        let campaignID = try recoveryUUID(1)
        let firstRequestID = try recoveryUUID(101)
        let secondRequestID = try recoveryUUID(102)
        let events = [
            try recoveryEvent(
                campaignID: campaignID,
                eventID: 201,
                requestID: firstRequestID,
                sequence: 1,
                payload: .campaignImported(
                    CampaignImportedPayload(
                        projectID: "project-recovery",
                        campaignTitle: "Recovery Fixture",
                        manifestHash: "sha256:manifest"
                    )
                )
            ),
            try recoveryEvent(
                campaignID: campaignID,
                eventID: 202,
                requestID: secondRequestID,
                sequence: 2,
                payload: .playerActionSubmitted(
                    PlayerActionSubmittedPayload(action: "Open the sealed gate")
                )
            ),
            try recoveryEvent(
                campaignID: campaignID,
                eventID: 203,
                requestID: secondRequestID,
                sequence: 3,
                payload: .gmStatusChanged(
                    GMStatusChangedPayload(phase: .planning)
                )
            )
        ]
        let asset = ImportedAsset(
            assetID: "asset-map",
            sha256: "0123456789abcdef",
            appRelativeURL: try #require(
                URL(
                    string: "Campaigns/\(campaignID.uuidString.lowercased())/assets/map.txt"
                )
            )
        )

        try await store.restoreCampaign(events: events, assets: [asset])

        #expect(
            try await store.events(for: campaignID, after: 0, limit: 10)
                == events
        )
        #expect(try await store.latestSequence(for: campaignID) == 3)
        #expect(try await store.importedAssets(for: campaignID) == [asset])
    }

    @Test
    func invalidRestoreSequenceWritesNoEventsOrAssets() async throws {
        let store = try makeRecoveryStore()
        let campaignID = try recoveryUUID(2)
        let requestID = try recoveryUUID(103)
        let events = [
            try recoveryEvent(
                campaignID: campaignID,
                eventID: 211,
                requestID: requestID,
                sequence: 1
            ),
            try recoveryEvent(
                campaignID: campaignID,
                eventID: 212,
                requestID: requestID,
                sequence: 3
            )
        ]
        let asset = ImportedAsset(
            assetID: "must-not-persist",
            sha256: "fedcba9876543210",
            appRelativeURL: try #require(
                URL(
                    string: "Campaigns/\(campaignID.uuidString.lowercased())/assets/rollback.txt"
                )
            )
        )

        await #expect(
            throws: CampaignStoreError.invalidRestoreSequence(
                expected: 2,
                actual: 3
            )
        ) {
            try await store.restoreCampaign(events: events, assets: [asset])
        }

        #expect(try await store.latestSequence(for: campaignID) == 0)
        #expect(
            try await store.events(for: campaignID, after: 0, limit: 10)
                .isEmpty
        )
        #expect(try await store.importedAssets(for: campaignID).isEmpty)
    }

    @Test
    func writerCreatesDeterministicBundleWithOnlyRecoveryDataAndDeclaredAssets() async throws {
        let workspace = try RecoveryWriterWorkspace()
        defer { workspace.remove() }
        let store = try makeRecoveryStore()
        let campaignID = try recoveryUUID(3)
        let directory = CampaignDirectory(
            applicationSupportDirectory: workspace.applicationSupportURL
        )
        let campaignURL = directory.campaignURL(for: campaignID)
        try FileManager.default.createDirectory(
            at: campaignURL.appendingPathComponent("assets", isDirectory: true),
            withIntermediateDirectories: true
        )
        let normalizedProject = Data(
            "{\"project\":\"recovery-fixture\"}".utf8
        )
        let mapAsset = Data("a real map asset".utf8)
        let credentialSentinel = "PRIVATE_PROVIDER_KEY_DO_NOT_EXPORT"
        try normalizedProject.write(
            to: campaignURL.appendingPathComponent("normalized-project.json")
        )
        try mapAsset.write(
            to: campaignURL.appendingPathComponent("assets/map.txt")
        )
        try Data(credentialSentinel.utf8).write(
            to: campaignURL.appendingPathComponent("provider-credentials.txt")
        )

        let events = [
            try recoveryEvent(
                campaignID: campaignID,
                eventID: 221,
                requestID: try recoveryUUID(301),
                sequence: 1,
                payload: .campaignImported(
                    CampaignImportedPayload(
                        projectID: "project-recovery",
                        campaignTitle: "Recovery Fixture",
                        manifestHash: "sha256:manifest"
                    )
                )
            ),
            try recoveryEvent(
                campaignID: campaignID,
                eventID: 222,
                requestID: try recoveryUUID(302),
                sequence: 2,
                payload: .voiceAssignmentChanged(
                    VoiceAssignmentChangedPayload(
                        characterID: "guide",
                        voiceID: "voice-manual",
                        source: .manual
                    )
                )
            ),
            try recoveryEvent(
                campaignID: campaignID,
                eventID: 223,
                requestID: try recoveryUUID(303),
                sequence: 3,
                payload: .voiceAssignmentChanged(
                    VoiceAssignmentChangedPayload(
                        characterID: "merchant",
                        voiceID: "voice-suggested",
                        source: .acceptedSuggestion
                    )
                )
            )
        ]
        let asset = ImportedAsset(
            assetID: "asset-map",
            sha256: FileHashing.hexadecimal(SHA256.hash(data: mapAsset)),
            appRelativeURL: try #require(
                URL(
                    string: "Campaigns/\(campaignID.uuidString.lowercased())/assets/map.txt"
                )
            )
        )
        try await store.restoreCampaign(events: events, assets: [asset])
        let writer = RecoveryBundleWriter(
            store: store,
            campaignDirectory: directory
        )
        let firstURL = workspace.rootURL.appendingPathComponent("first.zip")
        let secondURL = workspace.rootURL.appendingPathComponent("second.zip")

        try await writer.write(campaignID: campaignID, to: firstURL)
        try await writer.write(campaignID: campaignID, to: secondURL)

        #expect(try Data(contentsOf: firstURL) == Data(contentsOf: secondURL))
        let contents = try recoveryArchiveContents(at: firstURL)
        #expect(
            contents.keys.sorted() == [
                "campaign/assets/map.txt",
                "campaign/normalized-project.json",
                "events.jsonl",
                "manifest.json",
                "manual-voice-mappings.json"
            ]
        )
        #expect(contents["campaign/normalized-project.json"] == normalizedProject)
        #expect(contents["campaign/assets/map.txt"] == mapAsset)
        let mappings = try #require(contents["manual-voice-mappings.json"])
        #expect(String(decoding: mappings, as: UTF8.self).contains("voice-manual"))
        #expect(
            String(decoding: mappings, as: UTF8.self)
                .contains("voice-suggested") == false
        )
        let exportedText = contents.values.reduce(into: "") { result, data in
            result += String(decoding: data, as: UTF8.self)
        }
        #expect(exportedText.contains(credentialSentinel) == false)
    }

    @Test
    func readerRejectsAMissingDeclaredEntryBeforeStoreOrDestinationMutation() async throws {
        let workspace = try RecoveryWriterWorkspace()
        defer { workspace.remove() }
        let campaignID = try recoveryUUID(4)
        let validURL = workspace.rootURL.appendingPathComponent("valid.zip")
        try await makeValidRecoveryArchive(
            at: validURL,
            campaignID: campaignID,
            applicationSupportURL: workspace.applicationSupportURL
        )
        var contents = try recoveryArchiveContents(at: validURL)
        contents["campaign/assets/map.txt"] = nil
        let missingURL = workspace.rootURL.appendingPathComponent("missing.zip")
        try writeRecoveryArchive(contents: contents, to: missingURL)
        let destinationSupport = workspace.rootURL.appendingPathComponent(
            "RestoreSupport",
            isDirectory: true
        )
        let store = try makeRecoveryStore()
        let reader = RecoveryBundleReader(
            store: store,
            applicationSupportDirectory: destinationSupport
        )

        await #expect(
            throws: RecoveryBundleError.missingDeclaredEntry(
                "campaign/assets/map.txt"
            )
        ) {
            _ = try await reader.restore(from: missingURL)
        }

        #expect(try await store.latestSequence(for: campaignID) == 0)
        #expect(try await store.importedAssets(for: campaignID).isEmpty)
        #expect(
            FileManager.default.fileExists(
                atPath: CampaignDirectory(
                    applicationSupportDirectory: destinationSupport
                ).campaignURL(for: campaignID).path
            ) == false
        )
    }

    @Test
    func readerRejectsATamperedDeclaredEntryBeforeStoreOrDestinationMutation() async throws {
        let workspace = try RecoveryWriterWorkspace()
        defer { workspace.remove() }
        let campaignID = try recoveryUUID(5)
        let validURL = workspace.rootURL.appendingPathComponent("valid.zip")
        try await makeValidRecoveryArchive(
            at: validURL,
            campaignID: campaignID,
            applicationSupportURL: workspace.applicationSupportURL
        )
        var contents = try recoveryArchiveContents(at: validURL)
        var tamperedEvents = try #require(contents[RecoveryBundle.eventsPath])
        tamperedEvents[tamperedEvents.startIndex] ^= 0x01
        contents[RecoveryBundle.eventsPath] = tamperedEvents
        let tamperedURL = workspace.rootURL.appendingPathComponent("tampered.zip")
        try writeRecoveryArchive(contents: contents, to: tamperedURL)
        let destinationSupport = workspace.rootURL.appendingPathComponent(
            "RestoreSupport",
            isDirectory: true
        )
        let store = try makeRecoveryStore()
        let reader = RecoveryBundleReader(
            store: store,
            applicationSupportDirectory: destinationSupport
        )

        await #expect(
            throws: RecoveryBundleError.entryHashMismatch(
                RecoveryBundle.eventsPath
            )
        ) {
            _ = try await reader.restore(from: tamperedURL)
        }

        #expect(try await store.latestSequence(for: campaignID) == 0)
        #expect(try await store.importedAssets(for: campaignID).isEmpty)
        #expect(
            FileManager.default.fileExists(
                atPath: CampaignDirectory(
                    applicationSupportDirectory: destinationSupport
                ).campaignURL(for: campaignID).path
            ) == false
        )
    }

    @Test
    func importAppendExportRestoreRoundTripsEventsAssetsFilesProjectionAndArchive() async throws {
        let workspace = try RecoveryWriterWorkspace()
        defer { workspace.remove() }
        let importSourceURL = try makeRecoveryImportSource(
            in: workspace.rootURL
        )
        let sourceStore = try makeRecoveryStore()
        let sourcePipeline = ImportPipeline(
            store: sourceStore,
            applicationSupportDirectory: workspace.applicationSupportURL
        )
        let source = ImportSource.folder(importSourceURL)
        let staged = try await sourcePipeline.stage(source)
        let inspected = try await sourcePipeline.inspect(staged, source: source)
        let parsed = try await sourcePipeline.parse(inspected)
        let validated = await sourcePipeline.validate(parsed)
        let prepared = try await sourcePipeline.prepareReview(validated)
        let campaignID = try await sourcePipeline.commit(prepared)
        let gameplayRequestID = try recoveryUUID(401)
        _ = try await sourceStore.append(
            batch: [
                try recoveryEvent(
                    campaignID: campaignID,
                    eventID: 251,
                    requestID: gameplayRequestID,
                    sequence: 0,
                    payload: .sceneChanged(
                        SceneChangedPayload(
                            sceneID: "scene-gate",
                            title: "The Sealed Gate",
                            summary: "The party reaches the old lock."
                        )
                    )
                ),
                try recoveryEvent(
                    campaignID: campaignID,
                    eventID: 252,
                    requestID: gameplayRequestID,
                    sequence: 0,
                    payload: .voiceAssignmentChanged(
                        VoiceAssignmentChangedPayload(
                            characterID: "guide",
                            voiceID: "voice-manual",
                            source: .manual
                        )
                    )
                )
            ],
            expectedSequence: 1
        )
        let sourceDirectory = CampaignDirectory(
            applicationSupportDirectory: workspace.applicationSupportURL
        )
        let sourceCampaignURL = sourceDirectory.campaignURL(for: campaignID)
        let originalEvents = try await sourceStore.events(
            for: campaignID,
            after: 0,
            limit: 100
        )
        let originalAssets = try await sourceStore.importedAssets(
            for: campaignID
        )
        let originalProjection = try await ProjectionLoader(
            store: sourceStore
        ).load(campaignID: campaignID)
        let originalNormalized = try Data(
            contentsOf: sourceCampaignURL.appendingPathComponent(
                "normalized-project.json"
            )
        )
        let originalAsset = try Data(
            contentsOf: sourceCampaignURL.appendingPathComponent(
                "assets/map.txt"
            )
        )
        let archiveURL = workspace.rootURL.appendingPathComponent("round-trip.zip")
        try await RecoveryBundleWriter(
            store: sourceStore,
            campaignDirectory: sourceDirectory
        ).write(campaignID: campaignID, to: archiveURL)

        let restoreSupport = workspace.rootURL.appendingPathComponent(
            "RestoreSupport",
            isDirectory: true
        )
        let restoredStore = try makeRecoveryStore()
        let restoredID = try await RecoveryBundleReader(
            store: restoredStore,
            applicationSupportDirectory: restoreSupport
        ).restore(from: archiveURL)

        #expect(restoredID == campaignID)
        #expect(
            try await restoredStore.events(
                for: campaignID,
                after: 0,
                limit: 100
            ) == originalEvents
        )
        #expect(
            try await restoredStore.importedAssets(for: campaignID)
                == originalAssets
        )
        let restoredDirectory = CampaignDirectory(
            applicationSupportDirectory: restoreSupport
        )
        let restoredCampaignURL = restoredDirectory.campaignURL(for: campaignID)
        #expect(
            try Data(
                contentsOf: restoredCampaignURL.appendingPathComponent(
                    "normalized-project.json"
                )
            ) == originalNormalized
        )
        #expect(
            try Data(
                contentsOf: restoredCampaignURL.appendingPathComponent(
                    "assets/map.txt"
                )
            ) == originalAsset
        )
        let restoredProjection = try await ProjectionLoader(
            store: restoredStore
        ).load(campaignID: campaignID)
        #expect(restoredProjection.projection == originalProjection.projection)
        #expect(restoredProjection.diagnostics == originalProjection.diagnostics)

        let reexportURL = workspace.rootURL.appendingPathComponent("reexport.zip")
        try await RecoveryBundleWriter(
            store: restoredStore,
            campaignDirectory: restoredDirectory
        ).write(campaignID: campaignID, to: reexportURL)
        #expect(
            try Data(contentsOf: reexportURL)
                == Data(contentsOf: archiveURL)
        )
    }

    @Test
    func deletingOneCampaignRemovesOnlyItsRowsDirectoryAndCleanupAssociations() async throws {
        let workspace = try RecoveryWriterWorkspace()
        defer { workspace.remove() }
        let store = try makeRecoveryStore()
        let campaignA = try recoveryUUID(6)
        let campaignB = try recoveryUUID(7)
        let directory = CampaignDirectory(
            applicationSupportDirectory: workspace.applicationSupportURL
        )
        let eventA = try recoveryEvent(
            campaignID: campaignA,
            eventID: 261,
            requestID: try recoveryUUID(361),
            sequence: 1
        )
        let eventB = try recoveryEvent(
            campaignID: campaignB,
            eventID: 262,
            requestID: try recoveryUUID(362),
            sequence: 1
        )
        let assetA = ImportedAsset(
            assetID: "asset-a",
            sha256: "aaaaaaaa",
            appRelativeURL: try #require(
                URL(
                    string: "Campaigns/\(campaignA.uuidString.lowercased())/assets/a.txt"
                )
            )
        )
        let assetB = ImportedAsset(
            assetID: "asset-b",
            sha256: "bbbbbbbb",
            appRelativeURL: try #require(
                URL(
                    string: "Campaigns/\(campaignB.uuidString.lowercased())/assets/b.txt"
                )
            )
        )
        try await store.restoreCampaign(events: [eventA], assets: [assetA])
        try await store.restoreCampaign(events: [eventB], assets: [assetB])
        try await store.saveProjectionCheckpoint(
            ProjectionCheckpoint(
                sourceSequence: 1,
                reducerSchemaVersion: CampaignReducer.reducerSchemaVersion,
                projection: CampaignReducer().reduce(
                    CampaignProjection(campaignID: campaignA),
                    events: [eventA]
                ).projection
            )
        )
        let campaignAURL = directory.campaignURL(for: campaignA)
        let campaignBURL = directory.campaignURL(for: campaignB)
        try FileManager.default.createDirectory(
            at: campaignAURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: campaignBURL,
            withIntermediateDirectories: true
        )
        try Data("campaign a".utf8).write(
            to: campaignAURL.appendingPathComponent("owned.txt")
        )
        let campaignBData = Data("campaign b must remain".utf8)
        try campaignBData.write(
            to: campaignBURL.appendingPathComponent("owned.txt")
        )
        let audioCache = RecordingAudioCacheDeleter()
        let keyReferences = RecordingKeyReferenceDeleter()
        let manager = CampaignDataManager(
            store: store,
            campaignDirectory: directory,
            audioCache: audioCache,
            keyReferences: keyReferences
        )

        try await manager.deleteCampaign(campaignA)

        #expect(try await store.latestSequence(for: campaignA) == 0)
        #expect(try await store.importedAssets(for: campaignA).isEmpty)
        #expect(
            try await store.latestProjectionCheckpoint(
                for: campaignA,
                reducerSchemaVersion: CampaignReducer.reducerSchemaVersion
            ) == nil
        )
        #expect(FileManager.default.fileExists(atPath: campaignAURL.path) == false)
        #expect(
            try await store.events(for: campaignB, after: 0, limit: 10)
                == [eventB]
        )
        #expect(try await store.importedAssets(for: campaignB) == [assetB])
        #expect(
            try Data(
                contentsOf: campaignBURL.appendingPathComponent("owned.txt")
            ) == campaignBData
        )
        #expect(await audioCache.deletedCampaignIDs() == [campaignA])
        #expect(await keyReferences.deletedCampaignIDs() == [campaignA])
    }
}

private actor RecordingAudioCacheDeleter: CampaignAudioCacheDeleting {
    private var campaignIDs: [UUID] = []

    func deleteAudioCache(for campaignID: UUID) {
        campaignIDs.append(campaignID)
    }

    func deletedCampaignIDs() -> [UUID] {
        campaignIDs
    }
}

private actor RecordingKeyReferenceDeleter: CampaignKeyReferenceDeleting {
    private var campaignIDs: [UUID] = []

    func deleteCampaignAssociations(for campaignID: UUID) {
        campaignIDs.append(campaignID)
    }

    func deletedCampaignIDs() -> [UUID] {
        campaignIDs
    }
}

private struct RecoveryWriterWorkspace {
    let rootURL: URL
    let applicationSupportURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RecoveryWriterTests-\(UUID().uuidString)",
            isDirectory: true
        )
        applicationSupportURL = rootURL.appendingPathComponent(
            "ApplicationSupport",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: applicationSupportURL,
            withIntermediateDirectories: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private func recoveryArchiveContents(at url: URL) throws -> [String: Data] {
    let archive = try Archive(
        url: url,
        accessMode: .read,
        pathEncoding: nil
    )
    return try archive.reduce(into: [:]) { contents, entry in
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        contents[entry.path] = data
    }
}

private func makeValidRecoveryArchive(
    at archiveURL: URL,
    campaignID: UUID,
    applicationSupportURL: URL
) async throws {
    let directory = CampaignDirectory(
        applicationSupportDirectory: applicationSupportURL
    )
    let campaignURL = directory.campaignURL(for: campaignID)
    try FileManager.default.createDirectory(
        at: campaignURL.appendingPathComponent("assets", isDirectory: true),
        withIntermediateDirectories: true
    )
    try Data("{\"project\":\"reader-fixture\"}".utf8).write(
        to: campaignURL.appendingPathComponent("normalized-project.json")
    )
    let assetData = Data("reader map asset".utf8)
    try assetData.write(
        to: campaignURL.appendingPathComponent("assets/map.txt")
    )
    let store = try makeRecoveryStore()
    let event = try recoveryEvent(
        campaignID: campaignID,
        eventID: 244,
        requestID: try recoveryUUID(344),
        sequence: 1,
        payload: .campaignImported(
            CampaignImportedPayload(
                projectID: "project-reader",
                campaignTitle: "Reader Fixture",
                manifestHash: "sha256:reader"
            )
        )
    )
    let asset = ImportedAsset(
        assetID: "asset-map",
        sha256: FileHashing.hexadecimal(SHA256.hash(data: assetData)),
        appRelativeURL: try #require(
            URL(
                string: "Campaigns/\(campaignID.uuidString.lowercased())/assets/map.txt"
            )
        )
    )
    try await store.restoreCampaign(events: [event], assets: [asset])
    try await RecoveryBundleWriter(
        store: store,
        campaignDirectory: directory
    ).write(campaignID: campaignID, to: archiveURL)
}

private func writeRecoveryArchive(
    contents: [String: Data],
    to url: URL
) throws {
    let archive = try Archive(
        url: url,
        accessMode: .create,
        pathEncoding: nil
    )
    for path in contents.keys.sorted() {
        let data = try #require(contents[path])
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(data.count),
            modificationDate: Date(timeIntervalSince1970: 315_532_800),
            permissions: 0o644,
            compressionMethod: .deflate
        ) { position, size in
            let start = Int(position)
            let end = min(start + size, data.count)
            return data.subdata(in: start..<end)
        }
    }
}

private func makeRecoveryImportSource(in rootURL: URL) throws -> URL {
    let sourceURL = rootURL.appendingPathComponent(
        "ImportSource",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: sourceURL.appendingPathComponent("assets", isDirectory: true),
        withIntermediateDirectories: true
    )
    try Data("round-trip map asset".utf8).write(
        to: sourceURL.appendingPathComponent("assets/map.txt")
    )
    let projectJSON = """
    {
      "cdfVersion": 2,
      "project": {
        "id": "project-round-trip",
        "title": "Recovery Round Trip",
        "summary": "A complete recovery fixture.",
        "system": "Rules Light",
        "rootFolderID": "folder-root",
        "currentSceneRecordID": "scene-gate"
      },
      "fileTypes": [
        {
          "id": "scene",
          "name": "Scene",
          "recordKind": "scene",
          "fields": [
            { "id": "title", "name": "Title", "valueType": "string", "required": true }
          ]
        }
      ],
      "content": {
        "folders": [
          { "id": "folder-root", "name": "World" }
        ],
        "records": [
          {
            "id": "scene-gate",
            "fileTypeID": "scene",
            "folderID": "folder-root",
            "fields": [
              { "id": "title", "value": "The Sealed Gate" }
            ]
          }
        ],
        "relationships": [],
        "assets": [
          { "id": "asset-map", "relativePath": "assets/map.txt", "mediaType": "text/plain" }
        ],
        "maps": [],
        "characters": []
      }
    }
    """
    try Data(projectJSON.utf8).write(
        to: sourceURL.appendingPathComponent("project.json")
    )
    return sourceURL
}

private func makeRecoveryStore() throws -> SwiftDataCampaignStore {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: CampaignEventRecord.self,
        ImportedAssetRecord.self,
        ProjectionCheckpointRecord.self,
        configurations: configuration
    )
    return SwiftDataCampaignStore(modelContainer: container)
}

private func recoveryUUID(_ value: Int) throws -> UUID {
    try #require(
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                value
            )
        )
    )
}

private func recoveryEvent(
    campaignID: UUID,
    eventID: Int,
    requestID: UUID,
    sequence: Int64,
    payload: CampaignEventPayload = .gmStatusChanged(
        GMStatusChangedPayload(phase: .queued)
    )
) throws -> CampaignEvent {
    CampaignEvent(
        id: try recoveryUUID(eventID),
        campaignID: campaignID,
        sequence: sequence,
        requestID: requestID,
        timestamp: Date(timeIntervalSince1970: 1_728_000_000 + Double(eventID)),
        schemaVersion: 1,
        payload: payload
    )
}
