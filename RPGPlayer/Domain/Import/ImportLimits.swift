import Foundation

public struct ImportLimits: Equatable, Sendable {
    public let maximumTotalExpandedBytes: Int64
    public let maximumEntryCount: Int
    public let maximumFileBytes: Int64
    public let maximumPathDepth: Int
    public let maximumArchiveExpansionRatio: Int

    public init(
        maximumTotalExpandedBytes: Int64,
        maximumEntryCount: Int,
        maximumFileBytes: Int64,
        maximumPathDepth: Int,
        maximumArchiveExpansionRatio: Int
    ) {
        self.maximumTotalExpandedBytes = maximumTotalExpandedBytes
        self.maximumEntryCount = maximumEntryCount
        self.maximumFileBytes = maximumFileBytes
        self.maximumPathDepth = maximumPathDepth
        self.maximumArchiveExpansionRatio = maximumArchiveExpansionRatio
    }

    public static let standard = ImportLimits(
        maximumTotalExpandedBytes: 1_000_000_000,
        maximumEntryCount: 10_000,
        maximumFileBytes: 100_000_000,
        maximumPathDepth: 30,
        maximumArchiveExpansionRatio: 20
    )
}
