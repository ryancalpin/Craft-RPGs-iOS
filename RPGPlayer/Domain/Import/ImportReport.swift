import Foundation

public struct ImportIssue: Codable, Equatable, Sendable {
    public let code: String
    public let message: String
    public let relativePath: String?

    public init(code: String, message: String, relativePath: String? = nil) {
        self.code = code
        self.message = message
        self.relativePath = relativePath
    }
}

public struct ImportReport: Codable, Equatable, Sendable {
    public let projectTitle: String?
    public let recordCount: Int
    public let assetCount: Int
    public let warnings: [ImportIssue]
    public let fatalErrors: [ImportIssue]

    public init(
        projectTitle: String?,
        recordCount: Int,
        assetCount: Int,
        warnings: [ImportIssue],
        fatalErrors: [ImportIssue]
    ) {
        self.projectTitle = projectTitle
        self.recordCount = recordCount
        self.assetCount = assetCount
        self.warnings = warnings
        self.fatalErrors = fatalErrors
    }

    public var canCommit: Bool {
        fatalErrors.isEmpty
    }
}
