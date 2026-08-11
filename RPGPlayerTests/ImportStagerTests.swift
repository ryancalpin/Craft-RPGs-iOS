import Foundation
import Testing
import ZIPFoundation
@testable import RPGPlayer

struct ImportStagerTests {
    @Test(arguments: [
        UnsafePathCase(
            path: "../escape",
            expectedError: .pathTraversal("../escape")
        ),
        UnsafePathCase(
            path: "/private/escape",
            expectedError: .absolutePath("/private/escape")
        ),
        UnsafePathCase(
            path: "records/bad\0name.json",
            expectedError: .nullByte("records/bad\0name.json")
        )
    ])
    func rejectsUnsafeLexicalPaths(_ unsafePath: UnsafePathCase) {
        do {
            _ = try CanonicalPath(
                unsafePath.path,
                maximumDepth: 30
            )
            Issue.record("Expected the unsafe path to be rejected.")
        } catch let error as ImportValidationError {
            #expect(error == unsafePath.expectedError)
        } catch {
            Issue.record("Wrong error thrown: \(error)")
        }
    }

    @Test
    func rejectsCaseFoldedDuplicateCanonicalPaths() {
        let inspector = ArchiveInspector(limits: .standard)
        let entries = [
            entry(path: "Records/Hero.json"),
            entry(path: "records/hero.JSON")
        ]

        #expect(
            throws: ImportValidationError.duplicateCanonicalPath(
                "records/hero.JSON"
            )
        ) {
            try inspector.validate(entries)
        }
    }

    @Test
    func rejectsSymlinkWhoseResolvedTargetEscapesTheImportRoot() {
        let inspector = ArchiveInspector(limits: .standard)
        let escapingLink = ArchiveEntryDescriptor(
            path: "assets/current-map",
            kind: .symbolicLink(destination: "../../../outside.png"),
            uncompressedSize: 20,
            compressedSize: 20,
            unixMode: 0o777
        )

        #expect(
            throws: ImportValidationError.escapingSymbolicLink(
                "assets/current-map"
            )
        ) {
            try inspector.validate([escapingLink])
        }
    }

    @Test
    func rejectsAFileOverTheConfiguredPerFileLimit() {
        let inspector = ArchiveInspector(
            limits: limits(maximumFileBytes: 10)
        )

        #expect(
            throws: ImportValidationError.fileTooLarge("large.dat")
        ) {
            try inspector.validate([
                entry(
                    path: "large.dat",
                    uncompressedSize: 11,
                    compressedSize: 11
                )
            ])
        }
    }

    @Test
    func rejectsMoreThanTheConfiguredEntryLimit() {
        let inspector = ArchiveInspector(
            limits: limits(maximumEntryCount: 1)
        )

        #expect(throws: ImportValidationError.tooManyEntries) {
            try inspector.validate([
                entry(path: "one.json"),
                entry(path: "two.json")
            ])
        }
    }

    @Test
    func rejectsAnArchiveOverTheConfiguredExpansionRatio() {
        let inspector = ArchiveInspector(
            limits: limits(maximumArchiveExpansionRatio: 20)
        )

        #expect(throws: ImportValidationError.archiveExpansionRatioExceeded) {
            try inspector.validate([
                entry(
                    path: "compressed.json",
                    uncompressedSize: 21,
                    compressedSize: 1
                )
            ])
        }
    }

    @Test
    func rejectsEntriesWithExecutableModeBits() {
        let inspector = ArchiveInspector(limits: .standard)

        #expect(
            throws: ImportValidationError.executableEntry("script.sh")
        ) {
            try inspector.validate([
                entry(path: "script.sh", unixMode: 0o755)
            ])
        }
    }

    @Test
    func ignoresMacOSMetadataBeforeApplyingEntryLimits() throws {
        let inspector = ArchiveInspector(
            limits: limits(maximumEntryCount: 1)
        )
        let entries = [
            entry(path: ".DS_Store"),
            entry(path: "__MACOSX/._project.json"),
            entry(path: "records/._hero.json"),
            entry(path: "project.json")
        ]

        let validated = try inspector.validate(entries)

        #expect(validated.map(\.canonicalPath.string) == ["project.json"])
    }

    @Test
    func rejectsAnActualFolderSymlinkThatResolvesOutsideTheSource() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let source = workspace.appendingPathComponent("Source", isDirectory: true)
        let outside = workspace.appendingPathComponent("outside.json")
        let link = source.appendingPathComponent("escaped.json")
        let support = workspace.appendingPathComponent(
            "ApplicationSupport",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: source,
            withIntermediateDirectories: true
        )
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: outside
        )
        let stager = ImportStager(
            applicationSupportDirectory: support
        )

        do {
            _ = try await stager.stage(.folder(source))
            Issue.record("Expected the escaping source symlink to be rejected.")
        } catch let error as ImportValidationError {
            #expect(error == .escapingSymbolicLink("escaped.json"))
        } catch {
            Issue.record("Wrong error thrown: \(error)")
        }
    }

    @Test
    func rejectsAContainedFolderSymlinkInsteadOfDependingOnTheSource() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let source = workspace.appendingPathComponent("Source", isDirectory: true)
        let target = source.appendingPathComponent("project.json")
        let link = source.appendingPathComponent("current.json")
        try FileManager.default.createDirectory(
            at: source,
            withIntermediateDirectories: true
        )
        try Data("project".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(
            atPath: link.path,
            withDestinationPath: "project.json"
        )
        let stager = ImportStager(
            applicationSupportDirectory: workspace.appendingPathComponent(
                "ApplicationSupport",
                isDirectory: true
            )
        )

        do {
            _ = try await stager.stage(.folder(source))
            Issue.record("Expected source symlinks to be rejected.")
        } catch let error as ImportValidationError {
            #expect(error == .unsupportedSymbolicLink("current.json"))
        } catch {
            Issue.record("Wrong error thrown: \(error)")
        }
    }

    @Test
    func rejectsARealArchiveSymlinkWithoutReadingItsTargetPayload() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let archiveURL = workspace.appendingPathComponent("symlink.zip")
        let target = Data("project.json".utf8)
        let archive = try Archive(url: archiveURL, accessMode: .create)
        try archive.addEntry(
            with: "current.json",
            type: .symlink,
            uncompressedSize: Int64(target.count),
            permissions: 0o777
        ) { position, size in
            let start = Int(position)
            let end = min(start + size, target.count)
            return target.subdata(in: start..<end)
        }
        let stager = ImportStager(
            applicationSupportDirectory: workspace.appendingPathComponent(
                "ApplicationSupport",
                isDirectory: true
            )
        )

        do {
            _ = try await stager.stage(.archive(archiveURL))
            Issue.record("Expected archive symlinks to be rejected.")
        } catch let error as ImportValidationError {
            #expect(error == .unsupportedSymbolicLink("current.json"))
        } catch {
            Issue.record("Wrong error thrown: \(error)")
        }
    }

    @Test
    func streamingCopyEnforcesTheConfiguredByteLimit() throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let source = workspace.appendingPathComponent("actual.dat")
        let destination = workspace.appendingPathComponent("staged.dat")
        try Data(repeating: 0x41, count: 11).write(to: source)

        #expect(throws: ImportValidationError.fileTooLarge("actual.dat")) {
            try FileHashing.copyAndHash(
                from: source,
                to: destination,
                maximumBytes: 10,
                progress: { _ in }
            )
        }
    }

    @Test
    func stagesARealZIPArchiveAfterPreflightValidation() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let archiveURL = workspace.appendingPathComponent("campaign.zip")
        let support = workspace.appendingPathComponent(
            "ApplicationSupport",
            isDirectory: true
        )
        let contents = Data("{\"title\":\"Greyhaven\"}".utf8)
        let archive = try Archive(url: archiveURL, accessMode: .create)
        try archive.addEntry(
            with: "project.json",
            type: .file,
            uncompressedSize: Int64(contents.count),
            permissions: 0o644,
            compressionMethod: .deflate
        ) { position, size in
            let start = Int(position)
            let end = min(start + size, contents.count)
            return contents.subdata(in: start..<end)
        }
        let stager = ImportStager(applicationSupportDirectory: support)

        let staged = try await stager.stage(.archive(archiveURL))

        #expect(staged.files.map(\.relativePath) == ["project.json"])
        #expect(
            try Data(
                contentsOf: staged.directoryURL
                    .appendingPathComponent("project.json")
            ) == contents
        )
    }

    @Test
    func stagesAValidFolderUnderAnOwnedUUIDAndHashesItsFiles() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let source = workspace.appendingPathComponent("Source", isDirectory: true)
        let support = workspace.appendingPathComponent(
            "ApplicationSupport",
            isDirectory: true
        )
        let identifier = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000222")
        )
        let contents = Data("Greyhaven".utf8)
        try FileManager.default.createDirectory(
            at: source,
            withIntermediateDirectories: true
        )
        try contents.write(to: source.appendingPathComponent("project.json"))
        let expectedHash =
            "acd1055dea632e69b051eb6f0a2a5eb9e4157406f5d25ae5edef240051ec7301"
        let stager = ImportStager(
            applicationSupportDirectory: support,
            identifierProvider: { identifier }
        )

        let staged = try await stager.stage(.folder(source))

        #expect(staged.identifier == identifier)
        #expect(
            staged.directoryURL
                == support
                    .appendingPathComponent("ImportStaging", isDirectory: true)
                    .appendingPathComponent(
                        identifier.uuidString.lowercased(),
                        isDirectory: true
                    )
        )
        #expect(staged.files.count == 1)
        #expect(staged.files.first?.relativePath == "project.json")
        #expect(staged.files.first?.sha256 == expectedHash)
        #expect(
            try Data(
                contentsOf: staged.directoryURL
                    .appendingPathComponent("project.json")
            ) == contents
        )
    }

    @Test
    func cancellationRemovesOnlyItsUUIDAndLeavesTheSourceUnchanged() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let source = workspace.appendingPathComponent("Source", isDirectory: true)
        let support = workspace.appendingPathComponent(
            "ApplicationSupport",
            isDirectory: true
        )
        let stagingParent = support.appendingPathComponent(
            "ImportStaging",
            isDirectory: true
        )
        let sibling = stagingParent.appendingPathComponent(
            "keep-me.txt",
            isDirectory: false
        )
        let identifier = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000333")
        )
        let ownedStage = stagingParent.appendingPathComponent(
            identifier.uuidString.lowercased(),
            isDirectory: true
        )
        let sourceFile = source.appendingPathComponent("large-enough.dat")
        let sourceContents = Data(repeating: 0x5A, count: 192 * 1_024)
        try FileManager.default.createDirectory(
            at: source,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: stagingParent,
            withIntermediateDirectories: true
        )
        try Data("sibling".utf8).write(to: sibling)
        try sourceContents.write(to: sourceFile)
        let sourceHashBefore = try FileHashing.sha256(of: sourceFile)
        let stager = ImportStager(
            applicationSupportDirectory: support,
            identifierProvider: { identifier }
        )

        let task = Task {
            try await stager.stage(.folder(source)) { _ in
                withUnsafeCurrentTask { task in
                    task?.cancel()
                }
            }
        }

        do {
            _ = try await task.value
            Issue.record("Expected staging to be cancelled.")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Wrong error thrown: \(error)")
        }

        #expect(FileManager.default.fileExists(atPath: stagingParent.path))
        #expect(FileManager.default.fileExists(atPath: sibling.path))
        #expect(FileManager.default.fileExists(atPath: ownedStage.path) == false)
        #expect(try Data(contentsOf: sourceFile) == sourceContents)
        #expect(try FileHashing.sha256(of: sourceFile) == sourceHashBefore)
    }

    private func entry(
        path: String,
        uncompressedSize: Int64 = 1,
        compressedSize: Int64 = 1,
        unixMode: UInt16 = 0o644
    ) -> ArchiveEntryDescriptor {
        ArchiveEntryDescriptor(
            path: path,
            kind: .file,
            uncompressedSize: uncompressedSize,
            compressedSize: compressedSize,
            unixMode: unixMode
        )
    }

    private func limits(
        maximumTotalExpandedBytes: Int64 = 1_000,
        maximumEntryCount: Int = 100,
        maximumFileBytes: Int64 = 100,
        maximumPathDepth: Int = 30,
        maximumArchiveExpansionRatio: Int = 20
    ) -> ImportLimits {
        ImportLimits(
            maximumTotalExpandedBytes: maximumTotalExpandedBytes,
            maximumEntryCount: maximumEntryCount,
            maximumFileBytes: maximumFileBytes,
            maximumPathDepth: maximumPathDepth,
            maximumArchiveExpansionRatio: maximumArchiveExpansionRatio
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }
}

struct UnsafePathCase: Sendable {
    let path: String
    let expectedError: ImportValidationError
}
