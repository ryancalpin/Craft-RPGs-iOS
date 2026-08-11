import Foundation

/// A user-selected import location. Infrastructure owns security-scope access;
/// this domain value never starts, stops, or persists that access.
public enum ImportSource: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case folder
        case archive
        case handoffDocument
    }

    case folder(URL)
    case archive(URL)
    case handoffDocument(URL)

    public var kind: Kind {
        switch self {
        case .folder: .folder
        case .archive: .archive
        case .handoffDocument: .handoffDocument
        }
    }

    public var url: URL {
        switch self {
        case .folder(let url), .archive(let url), .handoffDocument(let url):
            url
        }
    }
}
