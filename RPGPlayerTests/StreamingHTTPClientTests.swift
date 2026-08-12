import Foundation
import Synchronization
import Testing
@testable import RPGPlayer

@Suite(.serialized)
struct StreamingHTTPClientTests {
    @Test
    func sseDecoderPreservesFragmentedUTF8CommentsAndMultilineData() throws {
        var decoder = ServerSentEventDecoder()
        let wire = Data(
            (
                ": keepalive\r\n"
                    + "event: chapter\r\n"
                    + "data: Rain falls 🌧️\r\n"
                    + "ignored: future-value\r\n"
                    + "data: Bells answer.\r\n"
                    + "\r\n"
            ).utf8
        )
        var events: [ServerSentEvent] = []

        for byte in wire {
            events.append(
                contentsOf: try decoder.append(Data([byte]))
            )
        }

        #expect(events == [
            ServerSentEvent(
                event: "chapter",
                data: Data("Rain falls 🌧️\nBells answer.".utf8)
            )
        ])
        #expect(try decoder.finish() == nil)
    }

    @Test
    func jsonLineDecoderPreservesFragmentedUTF8BlankLinesAndFinalLine()
        throws {
        var decoder = JSONLineDecoder()
        let expected = [
            Data(#"{"text":"Café 🌧️"}"#.utf8),
            Data(#"{"count":2}"#.utf8),
            Data(#"{"final":true}"#.utf8)
        ]
        let wire = Data(
            (
                #"{"text":"Café 🌧️"}"#
                    + "\r\n\r\n"
                    + #"{"count":2}"#
                    + "\n"
                    + #"{"final":true}"#
            ).utf8
        )
        var lines: [Data] = []

        for byte in wire {
            lines.append(
                contentsOf: try decoder.append(Data([byte]))
            )
        }
        if let finalLine = try decoder.finish() {
            lines.append(finalLine)
        }

        #expect(lines == expected)
    }

    @Test
    func sseDecoderAcceptsOneMegabyteBlockAndRejectsNextByte() throws {
        var exactDecoder = ServerSentEventDecoder()
        var exactBlock = Data(":x\n".utf8)
        exactBlock.append(Data("data: ".utf8))
        exactBlock.append(Data(repeating: 0x61, count: 999_990))
        exactBlock.append(contentsOf: [0x0A, 0x0A])

        let events = try exactDecoder.append(exactBlock)
        let event = try #require(events.first)

        #expect(events.count == 1)
        #expect(event.data.count == 999_990)

        var oversizedDecoder = ServerSentEventDecoder()
        var oversizedBlock = Data(":x\n".utf8)
        oversizedBlock.append(Data("data: ".utf8))
        oversizedBlock.append(Data(repeating: 0x61, count: 999_991))
        oversizedBlock.append(0x61)

        do {
            _ = try oversizedDecoder.append(oversizedBlock)
            Issue.record("Expected the oversized SSE block to be rejected")
        } catch let error as StreamingHTTPError {
            #expect(
                error == .frameTooLarge(
                    maximumBytes: 1_000_000,
                    actualBytes: 1_000_001
                )
            )
        } catch {
            Issue.record("Wrong SSE bound error: \(error)")
        }
    }

    @Test
    func jsonLineDecoderAcceptsOneMegabyteLineAndRejectsNextByte() throws {
        var exactDecoder = JSONLineDecoder()
        let exactLine = Data(repeating: 0x61, count: 1_000_000)

        #expect(try exactDecoder.append(exactLine).isEmpty)
        #expect(try exactDecoder.finish()?.count == 1_000_000)

        var oversizedDecoder = JSONLineDecoder()
        do {
            _ = try oversizedDecoder.append(
                Data(repeating: 0x61, count: 1_000_001)
            )
            Issue.record("Expected the oversized JSON line to be rejected")
        } catch let error as StreamingHTTPError {
            #expect(
                error == .frameTooLarge(
                    maximumBytes: 1_000_000,
                    actualBytes: 1_000_001
                )
            )
        } catch {
            Issue.record("Wrong JSONL bound error: \(error)")
        }
    }

    @Test
    func decodersRejectMalformedUTF8AndSSERejectsTruncatedBlock() throws {
        var sse = ServerSentEventDecoder()
        do {
            _ = try sse.append(
                Data([0x64, 0x61, 0x74, 0x61, 0x3A, 0x20, 0xC3, 0x28, 0x0A])
            )
            Issue.record("Expected malformed SSE UTF-8 to be rejected")
        } catch let error as StreamingHTTPError {
            #expect(error == .malformedUTF8)
        } catch {
            Issue.record("Wrong malformed SSE error: \(error)")
        }

        var jsonLines = JSONLineDecoder()
        do {
            _ = try jsonLines.append(Data([0xC3, 0x28, 0x0A]))
            Issue.record("Expected malformed JSONL UTF-8 to be rejected")
        } catch let error as StreamingHTTPError {
            #expect(error == .malformedUTF8)
        } catch {
            Issue.record("Wrong malformed JSONL error: \(error)")
        }

        var truncatedSSE = ServerSentEventDecoder()
        _ = try truncatedSSE.append(Data("event: chapter\ndata: unfinished\n".utf8))
        do {
            _ = try truncatedSSE.finish()
            Issue.record("Expected the unfinished SSE block to be rejected")
        } catch let error as StreamingHTTPError {
            #expect(error == .truncatedFrame)
        } catch {
            Issue.record("Wrong truncated SSE error: \(error)")
        }
    }

    @Test
    func injectedClientStreamsSSEFromRawURLSessionBytes() async throws {
        let url = try #require(URL(string: "https://fixture.invalid/sse"))
        let registration = await RedactingURLProtocol.register(
            scenario: RedactingURLProtocol.Scenario(
                response: .http(statusCode: 200),
                steps: [
                    .chunk(Data("data: first".utf8)),
                    .chunk(Data("\n\ndata: second\n\n".utf8))
                ]
            ),
            for: URLRequest(url: url)
        )
        let session = makeFixtureSession()
        defer { session.invalidateAndCancel() }
        let client = StreamingHTTPClient(session: session)

        var iterator = try await client
            .serverSentEvents(for: registration.request)
            .makeAsyncIterator()

        #expect(
            try await iterator.next()
                == ServerSentEvent(
                    event: nil,
                    data: Data("first".utf8)
                )
        )
        #expect(
            try await iterator.next()
                == ServerSentEvent(
                    event: nil,
                    data: Data("second".utf8)
                )
        )
        #expect(try await iterator.next() == nil)
    }

    @Test
    func injectedClientStreamsJSONLinesFromRawURLSessionBytes()
        async throws {
        let url = try #require(URL(string: "https://fixture.invalid/jsonl"))
        let registration = await RedactingURLProtocol.register(
            scenario: RedactingURLProtocol.Scenario(
                response: .http(statusCode: 200),
                steps: [
                    .chunk(Data(#"{"first":true}"#.utf8)),
                    .chunk(Data("\n".utf8)),
                    .chunk(Data(#"{"second":"part"#.utf8)),
                    .chunk(Data(#"ial"}"#.utf8))
                ]
            ),
            for: URLRequest(url: url)
        )
        let session = makeFixtureSession()
        defer { session.invalidateAndCancel() }
        let client = StreamingHTTPClient(session: session)

        var iterator = try await client
            .jsonLines(for: registration.request)
            .makeAsyncIterator()

        #expect(try await iterator.next() == Data(#"{"first":true}"#.utf8))
        #expect(
            try await iterator.next()
                == Data(#"{"second":"partial"}"#.utf8)
        )
        #expect(try await iterator.next() == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func injectedClientRejectsNonHTTPResponseAndCancelsItsTask() async throws {
        let url = try #require(URL(string: "https://fixture.invalid/non-http"))
        let registration = await RedactingURLProtocol.register(
            scenario: RedactingURLProtocol.Scenario(
                response: .nonHTTP,
                steps: []
            ),
            for: URLRequest(url: url)
        )
        let session = makeFixtureSession()
        defer { session.invalidateAndCancel() }
        let client = StreamingHTTPClient(session: session)

        do {
            _ = try await client.serverSentEvents(for: registration.request)
            Issue.record("Expected a non-HTTP response to be rejected")
        } catch let error as StreamingHTTPError {
            #expect(error == .invalidResponse)
        } catch {
            Issue.record("Wrong non-HTTP response error: \(error)")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func injectedClientRejectsNonSuccessStatusWithoutReadingBody()
        async throws {
        let url = try #require(URL(string: "https://fixture.invalid/status"))
        let registration = await RedactingURLProtocol.register(
            scenario: RedactingURLProtocol.Scenario(
                response: .http(statusCode: 429),
                steps: []
            ),
            for: URLRequest(url: url)
        )
        let session = makeFixtureSession()
        defer { session.invalidateAndCancel() }
        let client = StreamingHTTPClient(session: session)

        do {
            _ = try await client.jsonLines(for: registration.request)
            Issue.record("Expected a non-success response to be rejected")
        } catch let error as StreamingHTTPError {
            #expect(error == .httpStatus(429))
        } catch {
            Issue.record("Wrong HTTP status error: \(error)")
        }
    }

    @Test
    func midstreamFailurePreservesCompletedFrameAndDiscardsPartialFrame()
        async throws {
        let source = ScriptedPullByteSource(
            bytes: Data("data: complete\n\ndata: partial".utf8),
            ending: .failure(.networkConnectionLost)
        )
        let cancellation = SynchronousCancellationProbe()
        var iterator = StreamingHTTPSequence(
            decoder: ServerSentEventDecoder(),
            nextByte: { try await source.next() },
            cancel: { cancellation.cancel() }
        ).makeAsyncIterator()

        #expect(
            try await iterator.next()
                == ServerSentEvent(
                    event: nil,
                    data: Data("complete".utf8)
                )
        )
        do {
            _ = try await iterator.next()
            Issue.record("Expected the scripted transport failure")
        } catch let error as StreamingHTTPError {
            #expect(error == .transport(.networkConnectionLost))
        } catch {
            Issue.record("Wrong midstream transport error: \(error)")
        }
        #expect(cancellation.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func downstreamCancellationCancelsExactTaskOnceWithNativeError()
        async throws {
        let source = ScriptedPullByteSource(
            bytes: Data("data: ready\n\n".utf8),
            ending: .hold
        )
        let cancellation = SynchronousCancellationProbe()
        let sequence = StreamingHTTPSequence(
            decoder: ServerSentEventDecoder(),
            nextByte: { try await source.next() },
            cancel: { cancellation.cancel() }
        )
        let firstFrameObserved = AsyncProbe()
        let consumer = Task {
            var iterator = sequence.makeAsyncIterator()
            #expect(
                try await iterator.next()
                    == ServerSentEvent(
                        event: nil,
                        data: Data("ready".utf8)
                    )
            )
            await firstFrameObserved.record()
            return try await iterator.next()
        }

        await firstFrameObserved.wait()
        await source.waitUntilHeld()
        consumer.cancel()

        switch await consumer.result {
        case .success(let event):
            Issue.record("Cancellation unexpectedly emitted \(String(describing: event))")
        case .failure(is CancellationError):
            break
        case .failure(let error):
            Issue.record("Wrong downstream cancellation error: \(error)")
        }
        #expect(cancellation.count == 1)
    }

    @Test
    func fixtureCapturesOnlyRedactedRequestDiagnostics() async throws {
        let sentinel = "sk-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var components = try #require(
            URLComponents(string: "https://fixture.invalid/diagnostics")
        )
        components.queryItems = [
            URLQueryItem(name: "token", value: sentinel),
            URLQueryItem(name: "model", value: "public-model")
        ]
        let url = try #require(components.url)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(sentinel)", forHTTPHeaderField: "Authorization")
        request.setValue("safe-client", forHTTPHeaderField: "X-Client")
        request.httpBody = Data(sentinel.utf8)
        let registration = await RedactingURLProtocol.register(
            scenario: RedactingURLProtocol.Scenario(
                response: .http(statusCode: 200),
                steps: []
            ),
            for: request
        )
        let session = makeFixtureSession()
        defer { session.invalidateAndCancel() }

        #expect(RedactingURLProtocol.canInit(with: request) == false)
        #expect(RedactingURLProtocol.canInit(with: registration.request))
        var iterator = try await StreamingHTTPClient(session: session)
            .jsonLines(for: registration.request)
            .makeAsyncIterator()
        #expect(try await iterator.next() == nil)
        await registration.waitUntilStarted()
        let snapshot = try #require(
            await registration.diagnosticSnapshot()
        )

        #expect(snapshot.method == "POST")
        #expect(snapshot.scheme == "https")
        #expect(snapshot.host == "fixture.invalid")
        #expect(snapshot.path == "/diagnostics")
        #expect(snapshot.queryItemNames == ["model", "token"])
        #expect(snapshot.bodyByteCount == sentinel.utf8.count)
        #expect(snapshot.headers["Authorization"] == "<redacted>")
        #expect(snapshot.headers["X-Client"] == "safe-client")
        #expect(
            snapshot.headers.values.contains {
                $0.contains(sentinel)
            } == false
        )
        #expect(snapshot.path.contains(sentinel) == false)
        #expect(snapshot.queryItemNames.contains(sentinel) == false)
    }

    private func makeFixtureSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedactingURLProtocol.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration)
    }
}

private actor ScriptedPullByteSource {
    enum Ending: Sendable {
        case end
        case failure(URLError.Code)
        case hold
    }

    private let bytes: [UInt8]
    private let ending: Ending
    private var index = 0
    private var isHeld = false
    private var heldWaiters: [CheckedContinuation<Void, Never>] = []
    private var pullContinuation: CheckedContinuation<UInt8?, Error>?

    init(bytes: Data, ending: Ending) {
        self.bytes = Array(bytes)
        self.ending = ending
    }

    func next() async throws -> UInt8? {
        if index < bytes.count {
            defer { index += 1 }
            return bytes[index]
        }

        switch ending {
        case .end:
            return nil
        case .failure(let code):
            throw URLError(code)
        case .hold:
            isHeld = true
            let waiters = heldWaiters
            heldWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        pullContinuation = continuation
                    }
                }
            } onCancel: {
                Task { await self.cancelHeldPull() }
            }
        }
    }

    func waitUntilHeld() async {
        guard isHeld == false else { return }
        await withCheckedContinuation { continuation in
            heldWaiters.append(continuation)
        }
    }

    private func cancelHeldPull() {
        pullContinuation?.resume(throwing: CancellationError())
        pullContinuation = nil
    }
}

private final class SynchronousCancellationProbe: @unchecked Sendable {
    private let storage = Mutex(0)

    var count: Int {
        storage.withLock { $0 }
    }

    func cancel() {
        storage.withLock { $0 += 1 }
    }
}
