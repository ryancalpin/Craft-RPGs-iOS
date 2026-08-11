import Foundation
import SwiftData
import Testing
import ZIPFoundation
@testable import RPGPlayer

struct ImportCommitTests {
    @Test
    func validCDFv2ZIPCommitsTheSameSemanticOutcomeAsFolderImport() async throws {
        let fixture = try ArchiveImportAcceptanceFixture()
        defer { fixture.remove() }
        let archiveURL = try fixture.makeArchive()

        let folderOutcome = try await importAcceptanceOutcome(
            source: .folder(fixture.fullSourceURL),
            applicationSupportURL: fixture.folderApplicationSupportURL
        )
        let archiveOutcome = try await importAcceptanceOutcome(
            source: .archive(archiveURL),
            applicationSupportURL: fixture.archiveApplicationSupportURL
        )

        #expect(
            archiveOutcome.stagedRelativePaths
                == [
                    "assets/greyhaven.txt",
                    "assets/guide.txt",
                    "assets/hero.txt",
                    "project.json"
                ]
        )
        #expect(archiveOutcome.project == folderOutcome.project)
        #expect(archiveOutcome.project.id == "project-greyhaven")
        #expect(archiveOutcome.project.title == "Fog Over Greyhaven")
        #expect(archiveOutcome.report == folderOutcome.report)
        #expect(archiveOutcome.report.canCommit)
        #expect(archiveOutcome.review == folderOutcome.review)
        #expect(archiveOutcome.review.canCommit)
        #expect(archiveOutcome.manifestHash == folderOutcome.manifestHash)
        #expect(archiveOutcome.manifestHash.hasPrefix("sha256:"))
        #expect(archiveOutcome.persistedEventCount == 1)
        #expect(archiveOutcome.persistedEventSequence == 1)
        #expect(archiveOutcome.importedPayload == folderOutcome.importedPayload)
        #expect(archiveOutcome.importedPayload?.projectID == "project-greyhaven")
        #expect(
            archiveOutcome.importedPayload?.campaignTitle
                == "Fog Over Greyhaven"
        )
        #expect(
            archiveOutcome.normalizedProjectData
                == folderOutcome.normalizedProjectData
        )
        #expect(archiveOutcome.persistedProject == archiveOutcome.project)
        #expect(archiveOutcome.assets == folderOutcome.assets)
        #expect(
            archiveOutcome.assets.map(\.assetID)
                == ["asset-guide", "asset-hero", "asset-scene"]
        )
        #expect(archiveOutcome.catalogCount == 1)
        #expect(archiveOutcome.catalogTitle == "Fog Over Greyhaven")
        #expect(archiveOutcome.catalogProjectID == "project-greyhaven")
        #expect(archiveOutcome.campaignDirectoryExists)
        #expect(archiveOutcome.stageExistsAfterCommit == false)
    }

    @Test
    func displayedProjectPhasesOwnTheirNamedArtifacts() async throws {
        let fixture = try ImportCommitFixture()
        defer { fixture.remove() }
        let store = RecordingImportStore(shouldFailAppend: false)
        let pipeline = ImportPipeline(
            store: store,
            applicationSupportDirectory: fixture.applicationSupportURL
        )
        let documentURL = try fixture.makeJSONDocument(
            named: "greyhaven-export.json"
        )
        let source = ImportSource.handoffDocument(documentURL)

        let staged = try await pipeline.stage(source)
        #expect(staged.files.map(\.relativePath) == ["greyhaven-export.json"])
        #expect(normalizedProjectExists(in: staged) == false)

        let inspected = try await pipeline.inspect(staged, source: source)
        #expect(inspected.stagedImport.files.map(\.relativePath) == ["project.json"])
        #expect(normalizedProjectExists(in: inspected.stagedImport) == false)

        let parsed = try await pipeline.parse(inspected)
        #expect(parsed.project.title == "Commit Fixture")
        #expect(normalizedProjectExists(in: parsed.stagedImport) == false)

        let validated = await pipeline.validate(parsed)
        #expect(validated.canCommit)
        #expect(validated.report.fatalErrors.isEmpty)
        #expect(normalizedProjectExists(in: validated.stagedImport) == false)

        let prepared = try await pipeline.prepareReview(validated)
        #expect(normalizedProjectExists(in: prepared.stagedImport))
        #expect(prepared.manifestHash.hasPrefix("sha256:"))
        #expect(prepared.review.title == "Commit Fixture")
    }

    @Test
    func stagingFailureMapsToSafeCodeMessageAndRelativePath() {
        let issue = ImportPipeline.safeIssue(
            for: ImportValidationError.fileTooLarge("assets/map.png")
        )

        #expect(issue.code == "file_too_large")
        #expect(issue.message == "A file exceeds the import size limit.")
        #expect(issue.relativePath == "assets/map.png")
    }

    @Test
    func successfulCommitRenamesStageAndAppendsEventWithAssets() async throws {
        let fixture = try ImportCommitFixture()
        defer { fixture.remove() }
        let store = RecordingImportStore(shouldFailAppend: false)
        let pipeline = ImportPipeline(
            store: store,
            applicationSupportDirectory: fixture.applicationSupportURL
        )
        let staged = try await pipeline.stage(.folder(fixture.sourceURL))
        let prepared = try await prepareProject(
            pipeline: pipeline,
            staged: staged,
            source: .folder(fixture.sourceURL)
        )

        let campaignID = try await pipeline.commit(prepared)

        let destination = fixture.applicationSupportURL
            .appendingPathComponent("Campaigns", isDirectory: true)
            .appendingPathComponent(
                campaignID.uuidString.lowercased(),
                isDirectory: true
            )
        #expect(FileManager.default.fileExists(atPath: staged.directoryURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: destination.path))
        #expect(
            FileManager.default.fileExists(
                atPath: destination
                    .appendingPathComponent("normalized-project.json")
                    .path
            )
        )
        let snapshot = await store.snapshot()
        #expect(snapshot.events.count == 1)
        #expect(snapshot.events.first?.campaignID == campaignID)
        if case .campaignImported(let payload) = snapshot.events.first?.payload {
            #expect(payload.manifestHash.hasPrefix("sha256:"))
        } else {
            Issue.record("Expected the initial campaignImported payload")
        }
        #expect(snapshot.assets.map(\.assetID) == ["asset-map"])
        #expect(
            snapshot.assets.first?.appRelativeURL.relativeString
                == "Campaigns/\(campaignID.uuidString.lowercased())/assets/map.txt"
        )
    }

    @Test
    func failedStoreAppendMovesCampaignBackToExactStageAndWritesZeroRows() async throws {
        let fixture = try ImportCommitFixture()
        defer { fixture.remove() }
        let store = RecordingImportStore(shouldFailAppend: true)
        let pipeline = ImportPipeline(
            store: store,
            applicationSupportDirectory: fixture.applicationSupportURL
        )
        let staged = try await pipeline.stage(.folder(fixture.sourceURL))
        let prepared = try await prepareProject(
            pipeline: pipeline,
            staged: staged,
            source: .folder(fixture.sourceURL)
        )
        let destination = fixture.applicationSupportURL
            .appendingPathComponent("Campaigns", isDirectory: true)
            .appendingPathComponent(
                prepared.campaignID.uuidString.lowercased(),
                isDirectory: true
            )

        await #expect(throws: CampaignImportCommitError.persistenceFailed) {
            _ = try await pipeline.commit(prepared)
        }

        #expect(FileManager.default.fileExists(atPath: staged.directoryURL.path))
        #expect(FileManager.default.fileExists(atPath: destination.path) == false)
        let snapshot = await store.snapshot()
        #expect(snapshot.events.isEmpty)
        #expect(snapshot.assets.isEmpty)
    }
}

private struct ArchiveImportAcceptanceFixture {
    let rootURL: URL
    let folderApplicationSupportURL: URL
    let archiveApplicationSupportURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ArchiveImportAcceptance-\(UUID().uuidString)",
            isDirectory: true
        )
        folderApplicationSupportURL = rootURL.appendingPathComponent(
            "FolderApplicationSupport",
            isDirectory: true
        )
        archiveApplicationSupportURL = rootURL.appendingPathComponent(
            "ArchiveApplicationSupport",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
    }

    var fullSourceURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("RPGPlayer/Fixtures/Imports/CDFv2/Sources/full")
    }

    func makeArchive() throws -> URL {
        let archiveURL = rootURL.appendingPathComponent("full-cdf-v2.zip")
        let archive = try Archive(
            url: archiveURL,
            accessMode: .create,
            pathEncoding: nil
        )
        let relativePaths = [
            "assets/greyhaven.txt",
            "assets/guide.txt",
            "assets/hero.txt",
            "project.json"
        ]
        for relativePath in relativePaths {
            let data = try Data(
                contentsOf: fullSourceURL.appendingPathComponent(relativePath)
            )
            try archive.addEntry(
                with: relativePath,
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
        return archiveURL
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private struct ImportAcceptanceAssetOutcome: Equatable {
    let assetID: String
    let sha256: String
    let relativePath: String
    let contents: Data
}

private struct ImportAcceptanceOutcome {
    let stagedRelativePaths: [String]
    let project: NormalizedProject
    let report: ImportReport
    let review: ImportReviewSummary
    let manifestHash: String
    let persistedEventCount: Int
    let persistedEventSequence: Int64?
    let importedPayload: CampaignImportedPayload?
    let normalizedProjectData: Data
    let persistedProject: NormalizedProject
    let assets: [ImportAcceptanceAssetOutcome]
    let catalogCount: Int
    let catalogTitle: String?
    let catalogProjectID: String?
    let campaignDirectoryExists: Bool
    let stageExistsAfterCommit: Bool
}

private func importAcceptanceOutcome(
    source: ImportSource,
    applicationSupportURL: URL
) async throws -> ImportAcceptanceOutcome {
    let store = try makeImportAcceptanceStore()
    let pipeline = ImportPipeline(
        store: store,
        applicationSupportDirectory: applicationSupportURL
    )
    let staged = try await pipeline.stage(source)
    let stagedRelativePaths = staged.files.map(\.relativePath)
    let inspected = try await pipeline.inspect(staged, source: source)
    let parsed = try await pipeline.parse(inspected)
    let validated = await pipeline.validate(parsed)
    let prepared = try await pipeline.prepareReview(validated)
    let campaignID = try await pipeline.commit(prepared)
    let campaignComponent = campaignID.uuidString.lowercased()
    let campaignURL = applicationSupportURL
        .appendingPathComponent("Campaigns", isDirectory: true)
        .appendingPathComponent(campaignComponent, isDirectory: true)
    let normalizedProjectData = try Data(
        contentsOf: campaignURL.appendingPathComponent("normalized-project.json")
    )
    let persistedProject = try JSONDecoder().decode(
        NormalizedProject.self,
        from: normalizedProjectData
    )
    let events = try await store.events(
        for: campaignID,
        after: 0,
        limit: 10
    )
    let importedPayload: CampaignImportedPayload?
    if case .campaignImported(let payload) = events.first?.payload {
        importedPayload = payload
    } else {
        importedPayload = nil
    }
    let prefix = "Campaigns/\(campaignComponent)/"
    let assets = try await store.importedAssets(for: campaignID).map { asset in
        let appRelativePath = asset.appRelativeURL.relativeString
        let relativePath = appRelativePath.hasPrefix(prefix)
            ? String(appRelativePath.dropFirst(prefix.count))
            : appRelativePath
        return ImportAcceptanceAssetOutcome(
            assetID: asset.assetID,
            sha256: asset.sha256,
            relativePath: relativePath,
            contents: try Data(
                contentsOf: applicationSupportURL.appendingPathComponent(
                    appRelativePath
                )
            )
        )
    }.sorted { $0.assetID < $1.assetID }
    let catalog = try await store.campaigns()

    return ImportAcceptanceOutcome(
        stagedRelativePaths: stagedRelativePaths,
        project: parsed.project,
        report: validated.report,
        review: prepared.review,
        manifestHash: prepared.manifestHash,
        persistedEventCount: events.count,
        persistedEventSequence: events.first?.sequence,
        importedPayload: importedPayload,
        normalizedProjectData: normalizedProjectData,
        persistedProject: persistedProject,
        assets: assets,
        catalogCount: catalog.count,
        catalogTitle: catalog.first?.title,
        catalogProjectID: catalog.first?.projectID,
        campaignDirectoryExists: FileManager.default.fileExists(
            atPath: campaignURL.path
        ),
        stageExistsAfterCommit: FileManager.default.fileExists(
            atPath: staged.directoryURL.path
        )
    )
}

private func makeImportAcceptanceStore() throws -> SwiftDataCampaignStore {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: CampaignEventRecord.self,
        ImportedAssetRecord.self,
        ProjectionCheckpointRecord.self,
        configurations: configuration
    )
    return SwiftDataCampaignStore(modelContainer: container)
}

private struct ImportCommitFixture {
    let rootURL: URL
    let applicationSupportURL: URL
    let sourceURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ImportCommitTests-\(UUID().uuidString)",
            isDirectory: true
        )
        applicationSupportURL = rootURL.appendingPathComponent(
            "ApplicationSupport",
            isDirectory: true
        )
        sourceURL = rootURL.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceURL.appendingPathComponent("assets", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data(Self.projectJSON.utf8).write(
            to: sourceURL.appendingPathComponent("project.json")
        )
        try Data("map fixture".utf8).write(
            to: sourceURL.appendingPathComponent("assets/map.txt")
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func makeJSONDocument(named name: String) throws -> URL {
        let url = rootURL.appendingPathComponent(name, isDirectory: false)
        try Data(Self.projectJSON.utf8).write(to: url)
        return url
    }

    private static let projectJSON = """
    {
      "cdfVersion": 2,
      "project": {
        "id": "commit-project",
        "title": "Commit Fixture",
        "summary": "Atomic commit fixture.",
        "system": "Rules Light",
        "rootFolderID": "folder-root",
        "currentSceneRecordID": "scene-1",
        "playerCharacterRecordID": "hero-1"
      },
      "fileTypes": [
        {
          "id": "scene",
          "name": "Scene",
          "recordKind": "scene",
          "fields": [
            { "id": "title", "name": "Title", "valueType": "string", "required": true }
          ]
        },
        {
          "id": "character",
          "name": "Character",
          "recordKind": "character",
          "fields": [
            { "id": "name", "name": "Name", "valueType": "string", "required": true }
          ]
        }
      ],
      "content": {
        "folders": [
          { "id": "folder-root", "name": "Root" }
        ],
        "records": [
          {
            "id": "scene-1",
            "fileTypeID": "scene",
            "folderID": "folder-root",
            "fields": [
              { "id": "title", "value": "Harbor" }
            ]
          },
          {
            "id": "hero-1",
            "fileTypeID": "character",
            "folderID": "folder-root",
            "fields": [
              { "id": "name", "value": "Mara" }
            ]
          }
        ],
        "relationships": [],
        "assets": [
          { "id": "asset-map", "relativePath": "assets/map.txt", "mediaType": "text/plain" }
        ],
        "maps": [],
        "characters": [
          { "id": "character-hero", "recordID": "hero-1" }
        ]
      }
    }
    """
}

private func normalizedProjectExists(in staged: StagedImport) -> Bool {
    FileManager.default.fileExists(
        atPath: staged.directoryURL
            .appendingPathComponent("normalized-project.json")
            .path
    )
}

private func prepareProject(
    pipeline: ImportPipeline,
    staged: StagedImport,
    source: ImportSource
) async throws -> PreparedCampaignImport {
    let inspected = try await pipeline.inspect(staged, source: source)
    let parsed = try await pipeline.parse(inspected)
    let validated = await pipeline.validate(parsed)
    return try await pipeline.prepareReview(validated)
}

private actor RecordingImportStore: CampaignStore {
    struct Snapshot: Sendable {
        let events: [CampaignEvent]
        let assets: [ImportedAsset]
    }

    private let shouldFailAppend: Bool
    private var events: [CampaignEvent] = []
    private var assets: [ImportedAsset] = []

    init(shouldFailAppend: Bool) {
        self.shouldFailAppend = shouldFailAppend
    }

    func campaigns() -> [CampaignSummary] {
        []
    }

    func append(
        batch: [CampaignEvent],
        assets: [ImportedAsset],
        expectedSequence: Int64
    ) throws -> [CampaignEvent] {
        if shouldFailAppend {
            throw CampaignStoreError.persistenceFailure
        }
        let appended = batch.enumerated().map { index, event in
            CampaignEvent(
                id: event.id,
                campaignID: event.campaignID,
                sequence: expectedSequence + Int64(index) + 1,
                requestID: event.requestID,
                timestamp: event.timestamp,
                schemaVersion: event.schemaVersion,
                payload: event.payload
            )
        }
        events.append(contentsOf: appended)
        self.assets.append(contentsOf: assets)
        return appended
    }

    func events(
        for campaignID: UUID,
        after sequence: Int64,
        limit: Int
    ) -> [CampaignEvent] {
        Array(
            events
                .filter { $0.campaignID == campaignID && $0.sequence > sequence }
                .prefix(limit)
        )
    }

    func latestSequence(for campaignID: UUID) -> Int64 {
        events.filter { $0.campaignID == campaignID }.map(\.sequence).max() ?? 0
    }

    func importedAssets(for campaignID: UUID) -> [ImportedAsset] {
        assets
    }

    func saveProjectionCheckpoint(_ checkpoint: ProjectionCheckpoint) {}

    func latestProjectionCheckpoint(
        for campaignID: UUID,
        reducerSchemaVersion: Int
    ) -> ProjectionCheckpoint? {
        nil
    }

    func deleteCampaign(_ campaignID: UUID) {
        events.removeAll { $0.campaignID == campaignID }
        assets.removeAll()
    }

    func snapshot() -> Snapshot {
        Snapshot(events: events, assets: assets)
    }
}
