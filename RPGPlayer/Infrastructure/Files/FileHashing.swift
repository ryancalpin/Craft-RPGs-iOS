import CryptoKit
import Foundation

public struct StreamedFileDigest: Equatable, Sendable {
    public let sha256: String
    public let byteCount: Int64
}

public enum FileHashing {
    public static let chunkSize = 64 * 1_024

    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()

        while let data = try handle.read(upToCount: chunkSize), data.isEmpty == false {
            hasher.update(data: data)
        }

        return hexadecimal(hasher.finalize())
    }

    public static func copyAndHash(
        from source: URL,
        to destination: URL,
        maximumBytes: Int64,
        maximumAggregateBytesRemaining: Int64 = .max,
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

        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: destination)
        defer {
            try? input.close()
            try? output.close()
        }
        var hasher = SHA256()
        var copiedBytes: Int64 = 0

        while let data = try input.read(upToCount: chunkSize), data.isEmpty == false {
            try Task.checkCancellation()
            let (nextByteCount, overflow) = copiedBytes.addingReportingOverflow(
                Int64(data.count)
            )
            guard overflow == false, nextByteCount <= maximumBytes else {
                throw ImportValidationError.fileTooLarge(
                    source.lastPathComponent
                )
            }
            guard nextByteCount <= maximumAggregateBytesRemaining else {
                throw ImportValidationError.totalExpandedSizeExceeded
            }
            try output.write(contentsOf: data)
            hasher.update(data: data)
            copiedBytes = nextByteCount
            progress(Int64(data.count))
        }
        try Task.checkCancellation()
        return StreamedFileDigest(
            sha256: hexadecimal(hasher.finalize()),
            byteCount: copiedBytes
        )
    }

    public static func hexadecimal<D: Sequence>(_ digest: D) -> String
    where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
