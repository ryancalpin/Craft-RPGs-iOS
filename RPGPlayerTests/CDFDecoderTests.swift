import Foundation
import Testing
@testable import RPGPlayer

/// The fixture contract is an explicit RPGPlayer-owned CDF v2 subset. It is
/// project/world content for import review, never a claim of live-save recovery.
struct CDFDecoderTests {
    @Test
    func minimalFixtureDecodesThroughTheRealStager() async throws {
        let result = try await decodeFixture("minimal")

        #expect(result.project.cdfVersion == 2)
        #expect(result.project.importScope == .projectWorldContent)
        #expect(result.project.id == "project-minimal")
        #expect(result.project.title == "Minimal Adventure")
        #expect(result.project.folders.map(\.id) == ["folder-root"])
        #expect(result.project.records.map(\.id) == ["record-intro"])
        #expect(result.report.projectTitle == "Minimal Adventure")
        #expect(result.report.warnings.isEmpty)
        requireSendable(result)
    }

    @Test
    func fullFixtureMatchesTheHandCheckedNormalizedSnapshot() async throws {
        let result = try await decodeFixture("full")
        let actual = try normalizedJSON(encoder.encode(result.project))
        let expected = try normalizedJSON(
            Data(contentsOf: snapshotURL("full-normalized.json"))
        )

        #expect(actual == expected)
        #expect(
            result.project.manifest.files.map(\.relativePath)
                == result.project.manifest.files.map(\.relativePath).sorted()
        )
        #expect(
            result.project.manifest.recordIDs
                == result.project.manifest.recordIDs.sorted()
        )
    }

    @Test
    func unknownKeysAtEveryObjectBoundarySurviveNormalization() async throws {
        let result = try await decodeFixture("unknown-fields")
        let project = result.project
        let schema = try #require(project.schemas.first)
        let descriptor = try #require(schema.fields.first)
        let content = project.content
        let folder = try #require(project.folders.first)
        let record = try #require(project.records.first)
        let field = try #require(record.fields.first)
        let relationship = try #require(project.relationships.first)
        let asset = try #require(project.assets.first)
        let map = try #require(project.maps.first)
        let character = try #require(project.characters.first)

        #expect(
            project.extensionPayload["futureDocument"]
                == .object(["format": .string("v3-preview")])
        )
        #expect(
            project.projectExtensionPayload["futureProject"]
                == .object(["edition": .integer(3)])
        )
        #expect(schema.extensionPayload["futureFileType"] == .bool(true))
        #expect(
            descriptor.extensionPayload["futureDescriptor"]
                == .string("keep")
        )
        #expect(content.extensionPayload["futureContent"] == .bool(true))
        #expect(folder.extensionPayload["futureFolder"] == .integer(1))
        #expect(record.extensionPayload["futureRecord"] == .integer(2))
        #expect(field.extensionPayload["futureField"] == .integer(3))
        #expect(
            relationship.extensionPayload["futureRelationship"]
                == .integer(4)
        )
        #expect(asset.extensionPayload["futureAsset"] == .integer(5))
        #expect(map.extensionPayload["futureMap"] == .integer(6))
        #expect(
            character.extensionPayload["futureCharacter"] == .integer(7)
        )
    }

    @Test
    func projectMetadataIsValidatedBeforeContent() async throws {
        try await withFixtureCopy("minimal") { fixture in
            try mutateDocument(at: fixture) { document in
                document["project"] = "invalid-project"
                document["content"] = "invalid-content"
            }

            try await withStagedSource(fixture) { staged in
                #expect(throws: CDFDecodingError.invalidMetadata) {
                    try CDFDecoder().decode(staged)
                }
            }
        }
    }

    @Test
    func fileTypeDefinitionsAreValidatedBeforeContent() async throws {
        try await withFixtureCopy("minimal") { fixture in
            try mutateDocument(at: fixture) { document in
                document["fileTypes"] = "invalid-file-types"
                document["content"] = "invalid-content"
            }

            try await withStagedSource(fixture) { staged in
                #expect(throws: CDFDecodingError.invalidFileTypes) {
                    try CDFDecoder().decode(staged)
                }
            }
        }
    }

    @Test
    func versionsOutsideThePlanOwnedCDFv2ContractAreRejected() async throws {
        try await withFixtureCopy("minimal") { fixture in
            try mutateDocument(at: fixture) { document in
                document["cdfVersion"] = 1
            }

            try await withStagedSource(fixture) { staged in
                #expect(
                    throws: CDFDecodingError.unsupportedCDFVersion(1)
                ) {
                    try CDFDecoder().decode(staged)
                }
            }
        }
    }

    @Test
    func nonRootBrokenReferencesBecomeDeterministicReviewWarnings() async throws {
        let result = try await decodeFixture("broken-refs")
        let codes = result.report.warnings.map(\.code)

        #expect(codes == codes.sorted())
        #expect(codes.contains("broken-folder-reference"))
        #expect(codes.contains("broken-record-reference"))
        #expect(result.report.canCommit)
    }

    @Test
    func duplicateRecordIdentifiersRejectTheImport() async throws {
        try await withStagedFixture("duplicate-ids") { staged in
            #expect(
                throws: CDFDecodingError.duplicateIdentifier(
                    kind: "record",
                    id: "record-duplicate"
                )
            ) {
                try CDFDecoder().decode(staged)
            }
        }
    }

    @Test
    func missingAssetsBecomeDeterministicReviewWarnings() async throws {
        let result = try await decodeFixture("missing-assets")

        #expect(
            result.report.warnings.map(\.code)
                == ["missing-asset-file", "missing-asset-reference"]
        )
        #expect(result.report.canCommit)
    }

    @Test
    func unknownRecordKindsRemainReviewable() async throws {
        let result = try await decodeFixture("unsupported-record-types")

        #expect(result.project.records.map(\.id) == ["record-future"])
        #expect(
            result.report.warnings.map(\.code)
                == ["unsupported-record-kind"]
        )
    }

    @Test
    func aMissingRootFolderMakesTheProjectUnreadable() async throws {
        try await withFixtureCopy("minimal") { fixture in
            try mutateDocument(at: fixture) { document in
                var project = document["project"] as? [String: Any] ?? [:]
                project["rootFolderID"] = "folder-does-not-exist"
                document["project"] = project
            }

            try await withStagedSource(fixture) { staged in
                #expect(
                    throws: CDFDecodingError.unreadableRoot(
                        "Missing root folder folder-does-not-exist"
                    )
                ) {
                    try CDFDecoder().decode(staged)
                }
            }
        }
    }

    @Test
    func invalidAssetPathsRejectTheImport() async throws {
        try await withFixtureCopy("missing-assets") { fixture in
            try mutateDocument(at: fixture) { document in
                var content = document["content"] as? [String: Any] ?? [:]
                var assets = content["assets"] as? [[String: Any]] ?? []
                assets[0]["relativePath"] = "../escape.png"
                content["assets"] = assets
                document["content"] = content
            }

            try await withStagedSource(fixture) { staged in
                #expect(
                    throws: CDFDecodingError.invalidAssetPath("../escape.png")
                ) {
                    try CDFDecoder().decode(staged)
                }
            }
        }
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private func decodeFixture(_ name: String) async throws -> CDFDecodeResult {
        try await withStagedFixture(name) { staged in
            try CDFDecoder().decode(staged)
        }
    }

    private func withStagedFixture<Result>(
        _ name: String,
        operation: (StagedImport) throws -> Result
    ) async throws -> Result {
        try await withStagedSource(sourceURL(name), operation: operation)
    }

    private func withStagedSource<Result>(
        _ source: URL,
        operation: (StagedImport) throws -> Result
    ) async throws -> Result {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("cdf-staging-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: support) }
        let staged = try await ImportStager(
            applicationSupportDirectory: support
        ).stage(.folder(source))
        return try operation(staged)
    }

    private func withFixtureCopy<Result>(
        _ name: String,
        operation: (URL) async throws -> Result
    ) async throws -> Result {
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("cdf-source-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: sourceURL(name), to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        return try await operation(copy)
    }

    private func mutateDocument(
        at fixture: URL,
        mutation: (inout [String: Any]) -> Void
    ) throws {
        let url = fixture.appendingPathComponent("project.json")
        var document = try #require(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: url)
            ) as? [String: Any]
        )
        mutation(&document)
        try JSONSerialization.data(
            withJSONObject: document,
            options: [.sortedKeys]
        ).write(to: url)
    }

    private func sourceURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("RPGPlayer/Fixtures/Imports/CDFv2/Sources")
            .appendingPathComponent(name, isDirectory: true)
    }

    private func snapshotURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("RPGPlayer/Fixtures/Imports/CDFv2/Snapshots")
            .appendingPathComponent(name)
    }

    private func normalizedJSON(_ data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data)
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
    }

    private func requireSendable<T: Sendable>(_ value: T) {
        _ = value
    }
}
