import CryptoKit
import Foundation
import ZIPFoundation

public struct StagedFile: Equatable, Sendable {
    public let relativePath: String
    public let byteCount: Int64
    public let sha256: String
}

public struct StagedImport: Equatable, Sendable {
    public let identifier: UUID
    public let directoryURL: URL
    public let files: [StagedFile]
}

public struct ImportStager: Sendable {
    private let applicationSupportDirectory: URL
    private let limits: ImportLimits
    private let identifierProvider: @Sendable () -> UUID
    private let fileSizeProvider: @Sendable (URL, Int64) -> Int64

    public init(
        applicationSupportDirectory: URL? = nil,
        limits: ImportLimits = .standard,
        identifierProvider: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.applicationSupportDirectory = applicationSupportDirectory
            ?? FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
        self.limits = limits
        self.identifierProvider = identifierProvider
        fileSizeProvider = { _, recordedSize in recordedSize }
    }

    init(
        applicationSupportDirectory: URL,
        limits: ImportLimits,
        identifierProvider: @escaping @Sendable () -> UUID,
        fileSizeProvider: @escaping @Sendable (URL, Int64) -> Int64
    ) {
        self.applicationSupportDirectory = applicationSupportDirectory
        self.limits = limits
        self.identifierProvider = identifierProvider
        self.fileSizeProvider = fileSizeProvider
    }

    public func stage(
        _ source: ImportSource,
        progress: @escaping @Sendable (Int64) -> Void = { _ in }
    ) async throws -> StagedImport {
        let sourceURL = source.url
        let scopedAccessStarted = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if scopedAccessStarted {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        switch source {
        case .folder(let url):
            return try stageFolder(at: url, progress: progress)
        case .archive(let url):
            return try stageArchive(at: url, progress: progress)
        case .handoffDocument(let url):
            return try stageDocument(at: url, progress: progress)
        }
    }

    private func stageFolder(
        at sourceRoot: URL,
        progress: @Sendable (Int64) -> Void
    ) throws -> StagedImport {
        let sourceItems = try inspectFolder(at: sourceRoot)
        let validated = try ArchiveInspector(limits: limits).validate(
            sourceItems.map(\.descriptor)
        )
        let itemsByPath = Dictionary(
            uniqueKeysWithValues: sourceItems.map { ($0.descriptor.path, $0) }
        )
        return try withOwnedStagingDirectory { identifier, stageRoot in
            var files: [StagedFile] = []
            var actualTotalBytes: Int64 = 0
            for entry in validated {
                try Task.checkCancellation()
                guard let item = itemsByPath[entry.descriptor.path] else {
                    throw ImportValidationError.invalidArchive
                }
                let destination = try entry.canonicalPath.url(under: stageRoot)
                switch entry.descriptor.kind {
                case .directory:
                    try FileManager.default.createDirectory(
                        at: destination,
                        withIntermediateDirectories: true
                    )
                case .symbolicLink(let linkDestination):
                    _ = linkDestination
                    throw ImportValidationError.unsupportedSymbolicLink(
                        entry.descriptor.path
                    )
                case .file:
                    let digest = try FileHashing.copyAndHash(
                        from: item.sourceURL,
                        to: destination,
                        maximumBytes: limits.maximumFileBytes,
                        maximumAggregateBytesRemaining: try remainingTotalBytes(
                            after: actualTotalBytes
                        ),
                        progress: progress
                    )
                    try addToActualTotal(
                        digest.byteCount,
                        total: &actualTotalBytes
                    )
                    files.append(
                        StagedFile(
                            relativePath: entry.canonicalPath.string,
                            byteCount: digest.byteCount,
                            sha256: digest.sha256
                        )
                    )
                }
            }
            return StagedImport(
                identifier: identifier,
                directoryURL: stageRoot,
                files: files.sorted { $0.relativePath < $1.relativePath }
            )
        }
    }

    private func stageArchive(
        at archiveURL: URL,
        progress: @Sendable (Int64) -> Void
    ) throws -> StagedImport {
        let archive = try Archive(url: archiveURL, accessMode: .read)
        let archiveEntries = Array(archive)
        let descriptors = try archiveEntries.map {
            try descriptor(for: $0, in: archive)
        }
        let validated = try ArchiveInspector(limits: limits).validate(descriptors)
        let entriesByPath = Dictionary(
            uniqueKeysWithValues: archiveEntries.map { ($0.path, $0) }
        )

        return try withOwnedStagingDirectory { identifier, stageRoot in
            var files: [StagedFile] = []
            var actualTotalBytes: Int64 = 0
            for validatedEntry in validated {
                try Task.checkCancellation()
                guard let archiveEntry = entriesByPath[
                    validatedEntry.descriptor.path
                ] else {
                    throw ImportValidationError.invalidArchive
                }
                let destination = try validatedEntry.canonicalPath.url(
                    under: stageRoot
                )
                switch validatedEntry.descriptor.kind {
                case .directory:
                    try FileManager.default.createDirectory(
                        at: destination,
                        withIntermediateDirectories: true
                    )
                case .symbolicLink(let linkDestination):
                    _ = linkDestination
                    throw ImportValidationError.unsupportedSymbolicLink(
                        validatedEntry.descriptor.path
                    )
                case .file:
                    let digest = try extractAndHash(
                        archiveEntry,
                        from: archive,
                        to: destination,
                        maximumBytes: limits.maximumFileBytes,
                        maximumAggregateBytesRemaining: try remainingTotalBytes(
                            after: actualTotalBytes
                        ),
                        progress: progress
                    )
                    try addToActualTotal(
                        digest.byteCount,
                        total: &actualTotalBytes
                    )
                    files.append(
                        StagedFile(
                            relativePath: validatedEntry.canonicalPath.string,
                            byteCount: digest.byteCount,
                            sha256: digest.sha256
                        )
                    )
                }
            }

            return StagedImport(
                identifier: identifier,
                directoryURL: stageRoot,
                files: files.sorted { $0.relativePath < $1.relativePath }
            )
        }
    }

    private func stageDocument(
        at sourceURL: URL,
        progress: @Sendable (Int64) -> Void
    ) throws -> StagedImport {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: sourceURL.path
        )
        let recordedSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let size = fileSizeProvider(sourceURL, recordedSize)
        let mode = (attributes[.posixPermissions] as? NSNumber)?.uint16Value
            ?? 0o644
        let descriptor = ArchiveEntryDescriptor(
            path: sourceURL.lastPathComponent,
            kind: .file,
            uncompressedSize: size,
            compressedSize: size,
            unixMode: mode
        )
        let validated = try ArchiveInspector(limits: limits).validate([descriptor])
        guard let entry = validated.first else {
            throw ImportValidationError.unsupportedSource
        }
        return try withOwnedStagingDirectory { identifier, stageRoot in
            let destination = try entry.canonicalPath.url(under: stageRoot)
            let digest = try FileHashing.copyAndHash(
                from: sourceURL,
                to: destination,
                maximumBytes: limits.maximumFileBytes,
                maximumAggregateBytesRemaining: limits.maximumTotalExpandedBytes,
                progress: progress
            )
            var actualTotalBytes: Int64 = 0
            try addToActualTotal(
                digest.byteCount,
                total: &actualTotalBytes
            )
            return StagedImport(
                identifier: identifier,
                directoryURL: stageRoot,
                files: [
                    StagedFile(
                        relativePath: entry.canonicalPath.string,
                        byteCount: digest.byteCount,
                        sha256: digest.sha256
                    )
                ]
            )
        }
    }

    private func inspectFolder(at sourceRoot: URL) throws -> [SourceItem] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in false }
        ) else {
            throw ImportValidationError.unsupportedSource
        }

        var items: [SourceItem] = []
        for case let itemURL as URL in enumerator {
            let relativePath = itemURL.path
                .dropFirst(sourceRoot.path.hasSuffix("/")
                    ? sourceRoot.path.count
                    : sourceRoot.path.count + 1)
            let attributes = try FileManager.default.attributesOfItem(
                atPath: itemURL.path
            )
            let itemType = attributes[.type] as? FileAttributeType
            let mode = (attributes[.posixPermissions] as? NSNumber)?.uint16Value
                ?? 0o644
            let recordedSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let kind: ArchiveEntryDescriptor.Kind
            if itemType == .typeSymbolicLink {
                guard CanonicalPath.resolvesInside(itemURL, root: sourceRoot) else {
                    throw ImportValidationError.escapingSymbolicLink(
                        String(relativePath)
                    )
                }
                throw ImportValidationError.unsupportedSymbolicLink(
                    String(relativePath)
                )
            } else if itemType == .typeDirectory {
                kind = .directory
            } else {
                kind = .file
            }
            let size = kind == .directory
                ? 0
                : fileSizeProvider(itemURL, recordedSize)
            items.append(
                SourceItem(
                    sourceURL: itemURL,
                    descriptor: ArchiveEntryDescriptor(
                        path: String(relativePath),
                        kind: kind,
                        uncompressedSize: kind == .directory ? 0 : size,
                        compressedSize: kind == .directory ? 0 : size,
                        unixMode: mode
                    )
                )
            )
        }
        return items
    }

    private func descriptor(
        for entry: Entry,
        in archive: Archive
    ) throws -> ArchiveEntryDescriptor {
        guard entry.uncompressedSize <= UInt64(Int64.max),
              entry.compressedSize <= UInt64(Int64.max) else {
            throw ImportValidationError.fileTooLarge(entry.path)
        }
        let mode = (entry.fileAttributes[.posixPermissions] as? NSNumber)?
            .uint16Value ?? 0o644
        let kind: ArchiveEntryDescriptor.Kind
        switch entry.type {
        case .file:
            kind = .file
        case .directory:
            kind = .directory
        case .symlink:
            kind = .symbolicLink(destination: "")
        }
        return ArchiveEntryDescriptor(
            path: entry.path,
            kind: kind,
            uncompressedSize: Int64(entry.uncompressedSize),
            compressedSize: Int64(entry.compressedSize),
            unixMode: mode
        )
    }

    private func extractAndHash(
        _ entry: Entry,
        from archive: Archive,
        to destination: URL,
        maximumBytes: Int64,
        maximumAggregateBytesRemaining: Int64,
        progress: @Sendable (Int64) -> Void
    ) throws -> StreamedFileDigest {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard FileManager.default.createFile(
            atPath: destination.path,
            contents: nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var hasher = SHA256()
        var extractedBytes: Int64 = 0
        _ = try archive.extract(
            entry,
            bufferSize: FileHashing.chunkSize
        ) { chunk in
            try Task.checkCancellation()
            let (nextByteCount, overflow) = extractedBytes
                .addingReportingOverflow(Int64(chunk.count))
            guard overflow == false, nextByteCount <= maximumBytes else {
                throw ImportValidationError.fileTooLarge(entry.path)
            }
            guard nextByteCount <= maximumAggregateBytesRemaining else {
                throw ImportValidationError.totalExpandedSizeExceeded
            }
            try output.write(contentsOf: chunk)
            hasher.update(data: chunk)
            extractedBytes = nextByteCount
            progress(Int64(chunk.count))
        }
        try Task.checkCancellation()
        return StreamedFileDigest(
            sha256: FileHashing.hexadecimal(hasher.finalize()),
            byteCount: extractedBytes
        )
    }

    private func remainingTotalBytes(after actualTotalBytes: Int64) throws -> Int64 {
        let (remaining, overflow) = limits.maximumTotalExpandedBytes
            .subtractingReportingOverflow(actualTotalBytes)
        guard overflow == false, remaining >= 0 else {
            throw ImportValidationError.totalExpandedSizeExceeded
        }
        return remaining
    }

    private func addToActualTotal(
        _ byteCount: Int64,
        total: inout Int64
    ) throws {
        let (nextTotal, overflow) = total.addingReportingOverflow(byteCount)
        guard overflow == false,
              nextTotal <= limits.maximumTotalExpandedBytes else {
            throw ImportValidationError.totalExpandedSizeExceeded
        }
        total = nextTotal
    }

    private func withOwnedStagingDirectory<Result>(
        _ body: (UUID, URL) throws -> Result
    ) throws -> Result {
        let identifier = identifierProvider()
        let parent = applicationSupportDirectory.appendingPathComponent(
            "ImportStaging",
            isDirectory: true
        )
        let stageRoot = parent.appendingPathComponent(
            identifier.uuidString.lowercased(),
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
        guard FileManager.default.fileExists(atPath: stageRoot.path) == false else {
            throw ImportValidationError.stagingDirectoryAlreadyExists(identifier)
        }
        try FileManager.default.createDirectory(
            at: stageRoot,
            withIntermediateDirectories: false
        )
        var succeeded = false
        defer {
            if succeeded == false {
                removeOwnedStage(stageRoot, identifier: identifier, parent: parent)
            }
        }
        let result = try body(identifier, stageRoot)
        succeeded = true
        return result
    }

    private func removeOwnedStage(
        _ stageRoot: URL,
        identifier: UUID,
        parent: URL
    ) {
        guard stageRoot.deletingLastPathComponent().standardizedFileURL
                == parent.standardizedFileURL,
              UUID(uuidString: stageRoot.lastPathComponent) == identifier else {
            return
        }
        try? FileManager.default.removeItem(at: stageRoot)
    }
}

private struct SourceItem: Sendable {
    let sourceURL: URL
    let descriptor: ArchiveEntryDescriptor
}
