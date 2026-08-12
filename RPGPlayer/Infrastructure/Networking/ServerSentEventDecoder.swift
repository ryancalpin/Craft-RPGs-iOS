import Foundation

enum StreamingHTTPError: Error, Equatable, Sendable {
    case invalidResponse
    case httpStatus(Int)
    case transport(URLError.Code)
    case malformedUTF8
    case truncatedFrame
    case frameTooLarge(maximumBytes: Int, actualBytes: Int)
}

struct ServerSentEvent: Equatable, Sendable {
    let event: String?
    let data: Data
}

protocol IncrementalFrameDecoder: Sendable {
    associatedtype Frame: Sendable

    mutating func consume(_ byte: UInt8) throws -> Frame?
    mutating func finish() throws -> Frame?
}

struct ServerSentEventDecoder: IncrementalFrameDecoder {
    private static let maximumFrameBytes = 1_000_000

    private var lineBytes = Data()
    private var completedBlockBytes = 0
    private var eventName: String?
    private var dataLines: [Data] = []

    mutating func consume(_ byte: UInt8) throws -> ServerSentEvent? {
        guard byte == 0x0A else {
            let actualBytes = completedBlockBytes + lineBytes.count + 1
            if actualBytes > Self.maximumFrameBytes,
               !(lineBytes.isEmpty && byte == 0x0D) {
                throw StreamingHTTPError.frameTooLarge(
                    maximumBytes: Self.maximumFrameBytes,
                    actualBytes: actualBytes
                )
            }
            lineBytes.append(byte)
            return nil
        }

        let rawLineByteCount = lineBytes.count
        var completeLine = lineBytes
        lineBytes = Data()
        if completeLine.last == 0x0D {
            completeLine.removeLast()
        }

        guard completeLine.isEmpty == false else {
            completedBlockBytes = 0
            return dispatchEventIfPresent()
        }

        let actualBytes = completedBlockBytes + rawLineByteCount + 1
        guard actualBytes <= Self.maximumFrameBytes else {
            throw StreamingHTTPError.frameTooLarge(
                maximumBytes: Self.maximumFrameBytes,
                actualBytes: actualBytes
            )
        }
        completedBlockBytes = actualBytes
        return try consumeCompleteLine(completeLine)
    }

    mutating func finish() throws -> ServerSentEvent? {
        if lineBytes.isEmpty == false {
            let finalLine = lineBytes
            lineBytes = Data()
            _ = try consumeCompleteLine(finalLine)
        }
        guard eventName == nil, dataLines.isEmpty else {
            throw StreamingHTTPError.truncatedFrame
        }
        return nil
    }

    mutating func append(_ chunk: Data) throws -> [ServerSentEvent] {
        var events: [ServerSentEvent] = []
        for byte in chunk {
            if let event = try consume(byte) {
                events.append(event)
            }
        }
        return events
    }

    private mutating func consumeCompleteLine(
        _ line: Data
    ) throws -> ServerSentEvent? {
        guard let decodedLine = String(data: line, encoding: .utf8) else {
            throw StreamingHTTPError.malformedUTF8
        }
        guard decodedLine.hasPrefix(":") == false else { return nil }

        let field: Substring
        var value: Substring
        if let colon = decodedLine.firstIndex(of: ":") {
            field = decodedLine[..<colon]
            value = decodedLine[decodedLine.index(after: colon)...]
        } else {
            field = decodedLine[...]
            value = ""
        }
        if value.first == " " {
            value.removeFirst()
        }

        switch field {
        case "event":
            eventName = String(value)
        case "data":
            dataLines.append(Data(value.utf8))
        default:
            break
        }
        return nil
    }

    private mutating func dispatchEventIfPresent() -> ServerSentEvent? {
        defer {
            eventName = nil
            dataLines.removeAll(keepingCapacity: true)
        }
        guard dataLines.isEmpty == false else { return nil }
        return ServerSentEvent(
            event: eventName,
            data: joinedDataLines()
        )
    }

    private func joinedDataLines() -> Data {
        var joined = Data()
        for (index, line) in dataLines.enumerated() {
            if index > 0 {
                joined.append(0x0A)
            }
            joined.append(line)
        }
        return joined
    }
}
