import Foundation

public struct ArchiveEntryDescriptor: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case file
        case directory
        case symbolicLink(destination: String)
    }

    public let path: String
    public let kind: Kind
    public let uncompressedSize: Int64
    public let compressedSize: Int64
    public let unixMode: UInt16

    public init(
        path: String,
        kind: Kind,
        uncompressedSize: Int64,
        compressedSize: Int64,
        unixMode: UInt16
    ) {
        self.path = path
        self.kind = kind
        self.uncompressedSize = uncompressedSize
        self.compressedSize = compressedSize
        self.unixMode = unixMode
    }
}

public struct ValidatedArchiveEntry: Equatable, Sendable {
    public let descriptor: ArchiveEntryDescriptor
    public let canonicalPath: CanonicalPath
}

public struct ArchiveInspector: Sendable {
    public let limits: ImportLimits

    public init(limits: ImportLimits) {
        self.limits = limits
    }

    public func validate(
        _ entries: [ArchiveEntryDescriptor]
    ) throws -> [ValidatedArchiveEntry] {
        let relevantEntries = entries.filter {
            Self.isMacOSMetadataPath($0.path) == false
        }
        guard relevantEntries.count <= limits.maximumEntryCount else {
            throw ImportValidationError.tooManyEntries
        }

        var seenPaths: Set<String> = []
        var totalExpandedBytes: Int64 = 0
        var totalCompressedBytes: Int64 = 0
        var validated: [ValidatedArchiveEntry] = []
        validated.reserveCapacity(relevantEntries.count)

        for entry in relevantEntries {
            let canonicalPath = try CanonicalPath(
                entry.path,
                maximumDepth: limits.maximumPathDepth
            )
            guard seenPaths.insert(canonicalPath.caseFoldedKey).inserted else {
                throw ImportValidationError.duplicateCanonicalPath(entry.path)
            }

            if case .symbolicLink(let destination) = entry.kind {
                guard destination.isEmpty == false else {
                    throw ImportValidationError.unsupportedSymbolicLink(
                        entry.path
                    )
                }
                try validateSymbolicLink(
                    destination,
                    at: canonicalPath,
                    originalPath: entry.path
                )
            } else if case .file = entry.kind,
                      entry.unixMode & 0o111 != 0 {
                throw ImportValidationError.executableEntry(entry.path)
            }

            if case .directory = entry.kind {
                // Directories contribute no expanded payload bytes.
            } else {
                guard entry.uncompressedSize <= limits.maximumFileBytes else {
                    throw ImportValidationError.fileTooLarge(entry.path)
                }
                let (nextTotal, overflow) = totalExpandedBytes.addingReportingOverflow(
                    entry.uncompressedSize
                )
                guard overflow == false,
                      nextTotal <= limits.maximumTotalExpandedBytes else {
                    throw ImportValidationError.totalExpandedSizeExceeded
                }
                totalExpandedBytes = nextTotal
                totalCompressedBytes += max(0, entry.compressedSize)
            }

            validated.append(
                ValidatedArchiveEntry(
                    descriptor: entry,
                    canonicalPath: canonicalPath
                )
            )
        }

        if totalExpandedBytes > 0 {
            guard totalCompressedBytes > 0 else {
                throw ImportValidationError.archiveExpansionRatioExceeded
            }
            let (maximumExpanded, overflow) = totalCompressedBytes
                .multipliedReportingOverflow(
                    by: Int64(limits.maximumArchiveExpansionRatio)
                )
            if overflow == false, totalExpandedBytes > maximumExpanded {
                throw ImportValidationError.archiveExpansionRatioExceeded
            }
        }

        return validated
    }

    public static func isMacOSMetadataPath(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        return components.contains("__MACOSX")
            || components.contains(".DS_Store")
            || components.contains { $0.hasPrefix("._") }
    }

    private func validateSymbolicLink(
        _ destination: String,
        at path: CanonicalPath,
        originalPath: String
    ) throws {
        let parent = (path.string as NSString).deletingLastPathComponent
        let combined = parent.isEmpty ? destination : parent + "/" + destination
        do {
            _ = try CanonicalPath(combined, maximumDepth: limits.maximumPathDepth)
        } catch {
            throw ImportValidationError.escapingSymbolicLink(originalPath)
        }
    }
}
