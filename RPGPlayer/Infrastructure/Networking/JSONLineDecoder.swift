import Foundation

struct JSONLineDecoder: IncrementalFrameDecoder {
    private static let maximumFrameBytes = 1_000_000

    private var lineBytes = Data()

    mutating func consume(_ byte: UInt8) throws -> Data? {
        guard byte == 0x0A else {
            let actualBytes = lineBytes.count + 1
            guard actualBytes <= Self.maximumFrameBytes else {
                throw StreamingHTTPError.frameTooLarge(
                    maximumBytes: Self.maximumFrameBytes,
                    actualBytes: actualBytes
                )
            }
            lineBytes.append(byte)
            return nil
        }

        var completeLine = lineBytes
        lineBytes = Data()
        if completeLine.last == 0x0D {
            completeLine.removeLast()
        }
        return try validatedLine(completeLine)
    }

    mutating func finish() throws -> Data? {
        let finalLine = lineBytes
        lineBytes = Data()
        return try validatedLine(finalLine)
    }

    mutating func append(_ chunk: Data) throws -> [Data] {
        var lines: [Data] = []
        for byte in chunk {
            if let line = try consume(byte) {
                lines.append(line)
            }
        }
        return lines
    }

    private func validatedLine(_ line: Data) throws -> Data? {
        guard line.isEmpty == false else { return nil }
        guard String(data: line, encoding: .utf8) != nil else {
            throw StreamingHTTPError.malformedUTF8
        }
        return line
    }
}
