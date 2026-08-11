import Foundation

public enum ImportValidationError: Error, Equatable, Sendable {
    case absolutePath(String)
    case nullByte(String)
    case pathTraversal(String)
    case pathDepthExceeded(String)
    case emptyPath
    case duplicateCanonicalPath(String)
    case escapingSymbolicLink(String)
    case fileTooLarge(String)
    case tooManyEntries
    case totalExpandedSizeExceeded
    case archiveExpansionRatioExceeded
    case executableEntry(String)
    case unsupportedSymbolicLink(String)
    case invalidArchive
    case unsupportedSource
    case stagingDirectoryAlreadyExists(UUID)
}

public struct CanonicalPath: Equatable, Hashable, Sendable {
    public let string: String
    public let caseFoldedKey: String

    public init(_ rawPath: String, maximumDepth: Int) throws {
        guard rawPath.contains("\0") == false else {
            throw ImportValidationError.nullByte(rawPath)
        }
        guard (rawPath as NSString).isAbsolutePath == false else {
            throw ImportValidationError.absolutePath(rawPath)
        }

        var components: [String] = []
        for component in rawPath.split(separator: "/", omittingEmptySubsequences: false) {
            switch component {
            case "", ".":
                continue
            case "..":
                throw ImportValidationError.pathTraversal(rawPath)
            default:
                components.append(String(component))
            }
        }
        guard components.isEmpty == false else {
            throw ImportValidationError.emptyPath
        }
        guard components.count <= maximumDepth else {
            throw ImportValidationError.pathDepthExceeded(rawPath)
        }

        string = components.joined(separator: "/")
            .precomposedStringWithCanonicalMapping
        caseFoldedKey = string.lowercased(
            with: Locale(identifier: "en_US_POSIX")
        )
    }

    public func url(under root: URL) throws -> URL {
        let candidate = root.appendingPathComponent(string).standardizedFileURL
        guard Self.contains(candidate, under: root) else {
            throw ImportValidationError.pathTraversal(string)
        }
        return candidate
    }

    public static func contains(_ candidate: URL, under root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        return candidatePath == rootPath
            || candidatePath.hasPrefix(rootPath + "/")
    }

    public static func resolvesInside(_ candidate: URL, root: URL) -> Bool {
        contains(
            candidate.resolvingSymlinksInPath(),
            under: root.resolvingSymlinksInPath()
        )
    }
}
