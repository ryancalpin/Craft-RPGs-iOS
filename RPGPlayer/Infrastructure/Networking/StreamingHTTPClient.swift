import Foundation
import Synchronization

struct StreamingHTTPClient: Sendable {
    private let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    static func live() -> StreamingHTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        return StreamingHTTPClient(
            session: URLSession(configuration: configuration)
        )
    }

    func serverSentEvents(
        for request: URLRequest
    ) async throws -> StreamingHTTPSequence<ServerSentEventDecoder> {
        try await sequence(
            for: request,
            decoder: ServerSentEventDecoder()
        )
    }

    func jsonLines(
        for request: URLRequest
    ) async throws -> StreamingHTTPSequence<JSONLineDecoder> {
        try await sequence(for: request, decoder: JSONLineDecoder())
    }

    func boundedData(
        for request: URLRequest,
        maximumBytes: Int = 1_000_000
    ) async throws -> Data {
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            guard error.code != .cancelled, Task.isCancelled == false else {
                throw CancellationError()
            }
            throw StreamingHTTPError.transport(error.code)
        } catch {
            guard Task.isCancelled == false else {
                throw CancellationError()
            }
            throw StreamingHTTPError.transport(.unknown)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            bytes.task.cancel()
            throw StreamingHTTPError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            bytes.task.cancel()
            throw StreamingHTTPError.httpStatus(httpResponse.statusCode)
        }

        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                guard data.count <= maximumBytes else {
                    bytes.task.cancel()
                    throw StreamingHTTPError.frameTooLarge(
                        maximumBytes: maximumBytes,
                        actualBytes: data.count
                    )
                }
            }
        } catch is CancellationError {
            bytes.task.cancel()
            throw CancellationError()
        } catch let error as StreamingHTTPError {
            bytes.task.cancel()
            throw error
        } catch let error as URLError {
            bytes.task.cancel()
            guard error.code != .cancelled, Task.isCancelled == false else {
                throw CancellationError()
            }
            throw StreamingHTTPError.transport(error.code)
        } catch {
            bytes.task.cancel()
            guard Task.isCancelled == false else {
                throw CancellationError()
            }
            throw StreamingHTTPError.transport(.unknown)
        }
        return data
    }

    private func sequence<Decoder: IncrementalFrameDecoder>(
        for request: URLRequest,
        decoder: Decoder
    ) async throws -> StreamingHTTPSequence<Decoder> {
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            guard error.code != .cancelled, Task.isCancelled == false else {
                throw CancellationError()
            }
            throw StreamingHTTPError.transport(error.code)
        } catch {
            guard Task.isCancelled == false else {
                throw CancellationError()
            }
            throw StreamingHTTPError.transport(.unknown)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            bytes.task.cancel()
            throw StreamingHTTPError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            bytes.task.cancel()
            throw StreamingHTTPError.httpStatus(httpResponse.statusCode)
        }

        return StreamingHTTPSequence(bytes: bytes, decoder: decoder)
    }
}

struct StreamingHTTPSequence<Decoder: IncrementalFrameDecoder>:
    AsyncSequence,
    Sendable {
    typealias Element = Decoder.Frame

    private let decoder: Decoder
    private let nextByte: @Sendable () async throws -> UInt8?
    private let cancellation: CancellationHandle

    init(bytes: URLSession.AsyncBytes, decoder: Decoder) {
        let source = URLSessionByteSource(
            iterator: bytes.makeAsyncIterator()
        )
        let task = bytes.task
        self.init(
            decoder: decoder,
            nextByte: { try await source.next() },
            cancel: { task.cancel() }
        )
    }

    init(
        decoder: Decoder,
        nextByte: @escaping @Sendable () async throws -> UInt8?,
        cancel: @escaping @Sendable () -> Void
    ) {
        self.decoder = decoder
        self.nextByte = nextByte
        cancellation = CancellationHandle(cancel)
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            state: IteratorState(
                nextByte: nextByte,
                decoder: decoder
            ),
            cancellation: cancellation
        )
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        private let state: IteratorState
        private let cancellation: CancellationHandle

        fileprivate init(
            state: IteratorState,
            cancellation: CancellationHandle
        ) {
            self.state = state
            self.cancellation = cancellation
        }

        mutating func next() async throws -> Decoder.Frame? {
            let cancellation = cancellation
            do {
                return try await withTaskCancellationHandler {
                    try Task.checkCancellation()
                    let frame = try await state.next()
                    try Task.checkCancellation()
                    return frame
                } onCancel: {
                    cancellation.cancel()
                }
            } catch is CancellationError {
                cancellation.cancel()
                await state.discard()
                throw CancellationError()
            } catch let error as URLError {
                cancellation.cancel()
                await state.discard()
                guard error.code != .cancelled,
                      Task.isCancelled == false else {
                    throw CancellationError()
                }
                throw StreamingHTTPError.transport(error.code)
            } catch let error as StreamingHTTPError {
                cancellation.cancel()
                await state.discard()
                throw error
            } catch {
                cancellation.cancel()
                await state.discard()
                guard Task.isCancelled == false else {
                    throw CancellationError()
                }
                throw StreamingHTTPError.transport(.unknown)
            }
        }

        mutating func cancel() async {
            cancellation.cancel()
            await state.discard()
        }
    }

    fileprivate actor IteratorState {
        private let nextByte: @Sendable () async throws -> UInt8?
        private var decoder: Decoder?
        private var reachedEOF = false

        init(
            nextByte: @escaping @Sendable () async throws -> UInt8?,
            decoder: Decoder
        ) {
            self.nextByte = nextByte
            self.decoder = decoder
        }

        func next() async throws -> Decoder.Frame? {
            guard reachedEOF == false, var decoder else { return nil }

            while let byte = try await nextByte() {
                if let frame = try decoder.consume(byte) {
                    self.decoder = decoder
                    return frame
                }
            }

            reachedEOF = true
            self.decoder = nil
            return try decoder.finishAtEOF()
        }

        func discard() {
            reachedEOF = true
            decoder = nil
        }
    }
}

private actor URLSessionByteSource {
    private var iterator: URLSession.AsyncBytes.Iterator

    init(iterator: URLSession.AsyncBytes.Iterator) {
        self.iterator = iterator
    }

    func next() async throws -> UInt8? {
        var iterator = iterator
        let byte = try await iterator.next()
        self.iterator = iterator
        return byte
    }
}

private final class CancellationHandle: @unchecked Sendable {
    private struct State {
        var didCancel = false
        let operation: @Sendable () -> Void
    }

    private let state: Mutex<State>

    init(_ operation: @escaping @Sendable () -> Void) {
        state = Mutex(State(operation: operation))
    }

    func cancel() {
        let operation = state.withLock { state -> (@Sendable () -> Void)? in
            guard state.didCancel == false else { return nil }
            state.didCancel = true
            return state.operation
        }
        operation?()
    }
}
