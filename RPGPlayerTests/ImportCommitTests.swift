import Foundation
import Testing
@testable import RPGPlayer

struct ImportCommitTests {
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
