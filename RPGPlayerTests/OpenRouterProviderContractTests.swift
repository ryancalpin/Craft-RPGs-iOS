import Foundation
import Testing
@testable import RPGPlayer

@Suite(.serialized)
struct OpenRouterProviderContractTests {
    @Test(.timeLimit(.seconds(5)))
    func chatCompletionFixtureNormalizesStructuredTextAndUsage() async throws {
        let provider = try await makeProvider(fixture: "successful-text.sse")
        let events = try await collect(provider.adapter.streamTurn(try makeRequest()))

        await provider.registration.waitUntilStopped()
        #expect(await provider.registration.stopCount() == 1)

        #expect(events.count == 4)
        #expect(events[0] == .textDelta("{\"schemaVersion\":1,"))
        #expect(events[1] == .textDelta("\"envelope\":{\"requestID\":\"11111111-1111-4111-8111-111111111111\",\"narration\":[],\"beats\":[],\"proposedEvents\":[],\"pendingDecision\":null,\"voiceSegments\":[],\"usage\":null}}"))
        #expect(events[2] == .usage(ProviderUsage(inputTokens: 12, outputTokens: 9, cachedInputTokens: 2)))
        guard case .finished(.completed(let envelope)) = events[3] else {
            Issue.record("Expected a completed normalized envelope")
            return
        }
        #expect(envelope.requestID == try uuid("11111111-1111-4111-8111-111111111111"))
    }

    @Test
    func chatCompletionFixturePreservesArbitraryRecordPatchFields() async throws {
        let provider = try await makeProvider(fixture: "successful-patch.sse")
        let events = try await collect(provider.adapter.streamTurn(try makeRequest()))

        guard case .finished(.completed(let envelope)) = events.last,
              let event = envelope.proposedEvents.first else {
            Issue.record("Expected a completed record-patch envelope")
            return
        }
        guard case .recordPatch(let recordID, let fields) = event else {
            Issue.record("Expected a normalized record-patch event")
            return
        }
        #expect(recordID == "record-1")
        #expect(fields["customField"] == .string("preserved"))
        #expect(fields["nested"] == .object(["amount": .integer(7)]))
    }

    @Test
    func chatCompletionModelDiscoveryExposesAPreviouslyUnknownModel() async throws {
        let provider = try await makeProvider(
            fixture: "models.json",
            path: "models"
        )

        let models = try await provider.adapter.models()

        #expect(models.map(\.id) == ["vendor/new-model"])
        #expect(models[0].providerID == .openRouter)
    }

    @Test
    func chatCompletionCredentialLoadingCancellationNormalizesToCancelled() async {
        let gate = CredentialLoadGate()
        let provider = OpenRouterProvider(
            credentialReader: BlockingCredentialReader(gate: gate)
        )
        let task = Task { () -> ProviderError? in
            do {
                _ = try await provider.streamTurn(try! makeRequest())
                return nil
            } catch let error as ProviderError {
                return error
            } catch {
                return nil
            }
        }

        await gate.waitUntilStarted()
        task.cancel()

        #expect(await task.value == .cancelled)
    }

    @Test(.timeLimit(.seconds(5)))
    func chatCompletionModelDiscoveryCancellationNormalizesToCancelled() async throws {
        let provider = try await makeProvider(
            fixture: "models.json",
            path: "models",
            steps: [.holdOpen]
        )
        let task = Task { () -> ProviderError? in
            do {
                _ = try await provider.adapter.models()
                return nil
            } catch let error as ProviderError {
                return error
            } catch {
                return nil
            }
        }

        await provider.registration.waitUntilHeldOpen()
        task.cancel()

        #expect(await task.value == .cancelled)
        await provider.registration.waitUntilStopped()
    }

    @Test
    func chatCompletionFixturePreservesInterleavedAllowlistedToolCalls() async throws {
        let provider = try await makeProvider(fixture: "interleaved-tools.sse")
        let events = try await collect(provider.adapter.streamTurn(try makeRequest()))

        #expect(events == [
            .toolCallStarted(callID: "call-search", toolName: "searchRecords"),
            .toolCallStarted(callID: "call-roll", toolName: "requestRoll"),
            .toolCallArgumentFragment(callID: "call-search", fragment: "{\"query\":"),
            .toolCallArgumentFragment(callID: "call-roll", fragment: "{\"expression\":\"1d20+4\"}"),
            .toolCallArgumentFragment(callID: "call-search", fragment: "\"bell rope\"}"),
            .toolCallCompleted(
                callID: "call-roll",
                toolName: "requestRoll",
                arguments: try ProviderToolArguments(values: ["expression": .string("1d20+4")])
            ),
            .toolCallCompleted(
                callID: "call-search",
                toolName: "searchRecords",
                arguments: try ProviderToolArguments(values: ["query": .string("bell rope")])
            ),
            .finished(.requiresToolResults)
        ])
    }

    @Test
    func chatCompletionFixtureRejectsUnknownToolBeforeEmittingToolEvents() async throws {
        let provider = try await makeProvider(fixture: "unknown-tool.sse")
        let stream = try await provider.adapter.streamTurn(try makeRequest())
        var iterator = stream.makeAsyncIterator()

        do {
            let event = try await iterator.next()
            Issue.record("Unexpected event before unknown-tool failure: \(String(describing: event))")
        } catch let error as ProviderError {
            #expect(error == .malformedResponse)
        } catch {
            Issue.record("Wrong normalized error: \(error)")
        }
    }

    @Test(.timeLimit(.seconds(5)), arguments: ["refusal.sse", "malformed-event.sse", "disconnect.sse"])
    func chatCompletionFixturesNormalizeTerminalFailures(
        fixture: String
    ) async throws {
        let provider = try await makeProvider(fixture: fixture)
        let expected: ProviderError = fixture == "refusal.sse"
            ? .safetyRefusal
            : .malformedResponse

        do {
            _ = try await collect(provider.adapter.streamTurn(try makeRequest()))
            Issue.record("Expected fixture \(fixture) to fail")
        } catch let error as ProviderError {
            #expect(error == expected)
        } catch {
            Issue.record("Wrong normalized error: \(error)")
        }
        await provider.registration.waitUntilStopped()
        #expect(await provider.registration.stopCount() == 1)
    }

    @Test
    func chatCompletionRateLimitNormalizesWithoutLeakingCredential() async throws {
        let sentinel = "sk-or-fixture-sentinel-123456"
        let provider = try await makeProvider(
            fixture: "rate-limit.sse",
            sentinel: sentinel,
            response: .http(statusCode: 429)
        )

        do {
            _ = try await collect(provider.adapter.streamTurn(try makeRequest()))
            Issue.record("Expected a rate-limit error")
        } catch let error as ProviderError {
            guard case .rateLimited(retryAfter: nil) = error else {
                Issue.record("Expected a normalized rate-limit error")
                return
            }
        }
        let snapshot = try #require(await provider.registration.diagnosticSnapshot())
        #expect(snapshot.headers["Authorization"] == "<redacted>")
        #expect(snapshot.headers.values.contains { $0.contains(sentinel) } == false)
        #expect(snapshot.bodyByteCount ?? 0 > 0)
        let bodyDiagnostic = NetworkDiagnosticRedactor().redact(
            "body=\(sentinel)",
            knownSecrets: [sentinel]
        )
        #expect(bodyDiagnostic.contains(sentinel) == false)
    }

    private func makeProvider(
        fixture: String,
        sentinel: String = "sk-fixture-openrouter-safe-123456",
        response: RedactingURLProtocol.Response = .http(statusCode: 200),
        path: String = "chat/completions",
        steps: [RedactingURLProtocol.Step]? = nil
    ) async throws -> FixtureOpenRouterProvider {
        let url = try #require(URL(string: "https://fixture.invalid/api/v1/\(path)"))
        let request = URLRequest(url: url)
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("RPGPlayer/Fixtures/Providers/OpenRouter")
            .appendingPathComponent(fixture)
        let bytes = try Data(contentsOf: fixtureURL)
        let registration = await RedactingURLProtocol.register(
            scenario: RedactingURLProtocol.Scenario(
                response: response,
                steps: steps ?? [.chunk(bytes)]
            ),
            for: request
        )
        return FixtureOpenRouterProvider(
            adapter: OpenRouterProvider(
                credentialReader: FixtureCredentialReader(value: sentinel),
                baseRequest: registration.request,
                httpClient: StreamingHTTPClient(session: makeFixtureSession())
            ),
            registration: registration
        )
    }

    private func collect(
        _ stream: AsyncThrowingStream<ProviderStreamEvent, Error>
    ) async throws -> [ProviderStreamEvent] {
        var events: [ProviderStreamEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    private func makeRequest() throws -> TurnRequest {
        TurnRequest(
            requestID: try uuid("11111111-1111-4111-8111-111111111111"),
            campaignID: try uuid("22222222-2222-4222-8222-222222222222"),
            expectedSequence: 42,
            action: PlayerAction(text: "I light the lantern."),
            context: TurnContext(
                contextHash: try ContextHash(rawValue: String(repeating: "a", count: 64)),
                sections: []
            )
        )
    }

    private func uuid(_ value: String) throws -> UUID {
        try #require(UUID(uuidString: value))
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

private struct FixtureCredentialReader: ProviderCredentialReader, Sendable {
    let value: String

    func credentialData(
        for reference: ProviderCredentialReference
    ) async throws -> Data {
        Data(value.utf8)
    }
}

private struct FixtureOpenRouterProvider: Sendable {
    let adapter: OpenRouterProvider
    let registration: RedactingURLProtocol.Registration
}

private actor CredentialLoadGate {
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func markStarted() {
        started = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }

    func waitUntilStarted() async {
        guard started == false else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private struct BlockingCredentialReader: ProviderCredentialReader, Sendable {
    let gate: CredentialLoadGate

    func credentialData(
        for reference: ProviderCredentialReference
    ) async throws -> Data {
        await gate.markStarted()
        try await Task.sleep(for: .seconds(60))
        return Data("unused-fixture-credential".utf8)
    }
}
