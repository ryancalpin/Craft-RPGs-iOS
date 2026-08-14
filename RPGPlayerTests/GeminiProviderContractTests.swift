import Foundation
import Testing
@testable import RPGPlayer

@Suite(.serialized)
struct GeminiProviderContractTests {
    @Test(.timeLimit(.minutes(1)))
    func generateContentFixtureNormalizesStructuredTextAndUsage() async throws {
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
        let expectedRequestID = try uuid("11111111-1111-4111-8111-111111111111")
        #expect(envelope.requestID == expectedRequestID)
    }

    @Test
    func generateContentRequestUsesStrictRecursiveStructuredOutputSchema() async throws {
        let provider = try await makeProvider(fixture: "successful-text.sse")
        _ = try await collect(provider.adapter.streamTurn(try makeRequest()))

        let snapshot = try #require(await provider.registration.diagnosticSnapshot())
        let body = try #require(snapshot.bodyData)
        let root = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let generationConfig = try #require(root["generationConfig"] as? [String: Any])
        #expect(generationConfig["responseMimeType"] as? String == "application/json")
        let schema = try #require(generationConfig["responseJsonSchema"] as? [String: Any])
        #expect(schema["type"] as? String == "object")
        #expect(schema["additionalProperties"] as? Bool == false)
        let schemaProperties = try #require(schema["properties"] as? [String: Any])
        let envelope = try #require(schemaProperties["envelope"] as? [String: Any])
        #expect(envelope["additionalProperties"] as? Bool == false)
        let envelopeProperties = try #require(envelope["properties"] as? [String: Any])
        let proposedEvents = try #require(envelopeProperties["proposedEvents"] as? [String: Any])
        let eventItems = try #require(proposedEvents["items"] as? [String: Any])
        let eventProperties = try #require(eventItems["properties"] as? [String: Any])
        let data = try #require(eventProperties["data"] as? [String: Any])
        #expect(data["additionalProperties"] as? Bool == false)
        let dataProperties = try #require(data["properties"] as? [String: Any])
        let fields = try #require(dataProperties["fields"] as? [String: Any])
        #expect(fields["type"] as? [String] == ["string", "null"])
    }

    @Test
    func generateContentFixturePreservesArbitraryRecordPatchFields() async throws {
        let provider = try await makeProvider(fixture: "successful-patch.sse")
        let events = try await collect(provider.adapter.streamTurn(try makeRequest()))
        guard case .finished(.completed(let envelope)) = events.last,
              case .recordPatch(let recordID, let fields) = envelope.proposedEvents.first else {
            Issue.record("Expected a completed record-patch envelope")
            return
        }
        #expect(recordID == "record-1")
        #expect(fields["customField"] == .string("preserved"))
        #expect(fields["nested"] == .object(["amount": .integer(7)]))
    }

    @Test
    func generateContentModelDiscoveryExposesAnUnknownModel() async throws {
        let provider = try await makeProvider(fixture: "models.json", path: "models")
        let models = try await provider.adapter.models()
        #expect(models.map(\.id) == ["vendor/new-model"])
        #expect(models[0].providerID == .gemini)
    }

    @Test
    func generateContentModelDiscoveryFallsBackWhenProviderIsUnavailable() async throws {
        let provider = try await makeProvider(
            fixture: "models.json",
            response: .http(statusCode: 503),
            path: "models"
        )
        let models = try await provider.adapter.models()
        #expect(models.isEmpty == false)
        #expect(models.allSatisfy { $0.providerID == .gemini })
        #expect(models.map(\.id).contains("gemini-3.6-flash"))
    }

    @Test
    func generateContentModelDiscoveryPreservesInvalidCredentialError() async throws {
        let provider = try await makeProvider(
            fixture: "models.json",
            response: .http(statusCode: 401),
            path: "models"
        )
        do {
            _ = try await provider.adapter.models()
            Issue.record("Expected invalid credentials to remain an error")
        } catch let error as ProviderError {
            #expect(error == .invalidCredential)
        } catch {
            Issue.record("Wrong normalized error: \(error)")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func generateContentModelDiscoveryCancellationNormalizesToCancelled() async throws {
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
    func generateContentFixtureNormalizesAllowlistedFunctionCalls() async throws {
        let provider = try await makeProvider(fixture: "interleaved-tools.sse")
        let events = try await collect(provider.adapter.streamTurn(try makeRequest()))
        #expect(events == [
            .toolCallStarted(callID: "call-search", toolName: "searchRecords"),
            .toolCallStarted(callID: "call-roll", toolName: "requestRoll"),
            .toolCallArgumentFragment(callID: "call-search", fragment: "{\"query\":\"bell rope\"}"),
            .toolCallArgumentFragment(callID: "call-roll", fragment: "{\"expression\":\"1d20+4\"}"),
            .toolCallCompleted(callID: "call-search", toolName: "searchRecords", arguments: try ProviderToolArguments(values: ["query": .string("bell rope")])),
            .toolCallCompleted(callID: "call-roll", toolName: "requestRoll", arguments: try ProviderToolArguments(values: ["expression": .string("1d20+4")])),
            .finished(.requiresToolResults)
        ])
    }

    @Test
    func generateContentFixtureUsesFunctionPacketOrderForNonLexicalCallIDs() async throws {
        let provider = try await makeProvider(fixture: "nonlexical-tools.sse")
        let events = try await collect(provider.adapter.streamTurn(try makeRequest()))
        #expect(events == [
            .toolCallStarted(callID: "call-zeta", toolName: "searchRecords"),
            .toolCallStarted(callID: "call-alpha", toolName: "requestRoll"),
            .toolCallArgumentFragment(callID: "call-zeta", fragment: "{\"query\":\"bell rope\"}"),
            .toolCallArgumentFragment(callID: "call-alpha", fragment: "{\"expression\":\"1d20+4\"}"),
            .toolCallCompleted(callID: "call-zeta", toolName: "searchRecords", arguments: try ProviderToolArguments(values: ["query": .string("bell rope")])),
            .toolCallCompleted(callID: "call-alpha", toolName: "requestRoll", arguments: try ProviderToolArguments(values: ["expression": .string("1d20+4")])),
            .finished(.requiresToolResults)
        ])
    }

    @Test
    func omittedFunctionCallIDsAreNamespacedAcrossContinuationDrivers() async throws {
        let provider = try await makeProvider(fixture: "omitted-id-tools.sse")
        let first = try await collect(provider.adapter.streamTurn(try makeRequest()))
        let continuationRequest = TurnRequest(
            requestID: try uuid("11111111-1111-4111-8111-111111111111"),
            campaignID: try uuid("22222222-2222-4222-8222-222222222222"),
            expectedSequence: 42,
            action: PlayerAction(text: "I light the lantern."),
            context: TurnContext(
                contextHash: try ContextHash(rawValue: String(repeating: "b", count: 64)),
                sections: []
            )
        )
        let second = try await collect(provider.adapter.streamTurn(continuationRequest))

        let firstIDs = first.compactMap { event -> String? in
            if case .toolCallStarted(let callID, _) = event { return callID }
            return nil
        }
        let secondIDs = second.compactMap { event -> String? in
            if case .toolCallStarted(let callID, _) = event { return callID }
            return nil
        }
        let firstCompletedIDs = first.compactMap { event -> String? in
            if case .toolCallCompleted(let callID, _, _) = event { return callID }
            return nil
        }
        let secondCompletedIDs = second.compactMap { event -> String? in
            if case .toolCallCompleted(let callID, _, _) = event { return callID }
            return nil
        }
        #expect(firstIDs.count == 2)
        #expect(secondIDs.count == 2)
        #expect(Set(firstIDs).isDisjoint(with: secondIDs))
        #expect(firstCompletedIDs == firstIDs)
        #expect(secondCompletedIDs == secondIDs)
        #expect(firstIDs.allSatisfy { $0.contains("11111111-1111-4111-8111-111111111111") })
        #expect(secondIDs.allSatisfy { $0.contains(String(repeating: "b", count: 64)) })
    }

    @Test
    func equivalentInterleavedToolFixtureMatchesAllFourAdapters() async throws {
        let gemini = try await makeProvider(fixture: "nonlexical-tools.sse")
        let anthropic = try await makeAnthropicProvider(fixture: "nonlexical-tools.sse")
        let openAI = try await makeOpenAIProvider(fixture: "nonlexical-tools.sse")
        let openRouter = try await makeOpenRouterProvider(fixture: "nonlexical-tools.sse")
        let request = try makeRequest()

        let geminiEvents = try await collect(gemini.adapter.streamTurn(request))
        let anthropicEvents = try await collect(anthropic.streamTurn(request))
        let openAIEvents = try await collect(openAI.streamTurn(request))
        let openRouterEvents = try await collect(openRouter.streamTurn(request))

        #expect(geminiEvents == anthropicEvents)
        #expect(geminiEvents == openAIEvents)
        #expect(geminiEvents == openRouterEvents)
    }

    @Test
    func generateContentFixtureRejectsUnknownToolBeforeEmittingToolEvents() async throws {
        let provider = try await makeProvider(fixture: "unknown-tool.sse")
        var iterator = (try await provider.adapter.streamTurn(try makeRequest())).makeAsyncIterator()
        do {
            _ = try await iterator.next()
            Issue.record("Expected the unknown tool to fail before an event")
        } catch let error as ProviderError {
            #expect(error == .malformedResponse)
        } catch {
            Issue.record("Wrong normalized error: \(error)")
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["refusal.sse", "malformed-event.sse", "disconnect.sse"])
    func generateContentFixturesNormalizeTerminalFailures(fixture: String) async throws {
        let provider = try await makeProvider(fixture: fixture)
        let expected: ProviderError = fixture == "refusal.sse" ? .safetyRefusal : .malformedResponse
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
    func generateContentRateLimitNormalizesAndRedactsCredential() async throws {
        let sentinel = "AIza-fixture-sentinel-123456"
        let provider = try await makeProvider(fixture: "rate-limit.sse", sentinel: sentinel, response: .http(statusCode: 429))
        do {
            _ = try await collect(provider.adapter.streamTurn(try makeRequest()))
            Issue.record("Expected a rate-limit error")
        } catch let error as ProviderError {
            #expect(error == .rateLimited(retryAfter: nil))
        } catch {
            Issue.record("Wrong normalized error: \(error)")
        }
        let snapshot = try #require(await provider.registration.diagnosticSnapshot())
        #expect(snapshot.headers["x-goog-api-key"] == "<redacted>")
        #expect(snapshot.headers.values.contains { $0.contains(sentinel) } == false)
        #expect(NetworkDiagnosticRedactor().redact("body=\(sentinel)", knownSecrets: [sentinel]).contains(sentinel) == false)
    }

    @Test
    func generateContentCredentialLoadingCancellationNormalizesToCancelled() async {
        let gate = CredentialLoadGate()
        let provider = GeminiProvider(credentialReader: BlockingCredentialReader(gate: gate))
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

    @Test
    func equivalentStructuredTextFixtureMatchesOtherAdapters() async throws {
        let gemini = try await makeProvider(fixture: "successful-text.sse")
        let anthropic = try await makeAnthropicProvider(fixture: "successful-text.sse")
        let openAI = try await makeOpenAIProvider(fixture: "successful-text.sse")
        let openRouter = try await makeOpenRouterProvider(fixture: "successful-text.sse")
        let request = try makeRequest()
        let expected = try await collect(gemini.adapter.streamTurn(request))
        let anthropicEvents = try await collect(anthropic.streamTurn(request))
        let openAIEvents = try await collect(openAI.streamTurn(request))
        let openRouterEvents = try await collect(openRouter.streamTurn(request))
        #expect(expected == anthropicEvents)
        #expect(expected == openAIEvents)
        #expect(expected == openRouterEvents)
    }

    private func makeProvider(fixture: String, sentinel: String = "AIza-fixture-safe-123456", response: RedactingURLProtocol.Response = .http(statusCode: 200), path: String = "models/gemini-3.6-flash:streamGenerateContent", steps: [RedactingURLProtocol.Step]? = nil) async throws -> (adapter: GeminiProvider, registration: RedactingURLProtocol.Registration) {
        let url = try #require(URL(string: "https://fixture.invalid/v1beta/\(path)"))
        let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("RPGPlayer/Fixtures/Providers/Gemini").appendingPathComponent(fixture)
        let fixtureData = try Data(contentsOf: fixtureURL)
        let registration = await RedactingURLProtocol.register(scenario: RedactingURLProtocol.Scenario(response: response, steps: steps ?? [.chunk(fixtureData)]), for: URLRequest(url: url))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedactingURLProtocol.self]
        return (GeminiProvider(credentialReader: FixtureCredentialReader(value: sentinel), baseRequest: registration.request, httpClient: StreamingHTTPClient(session: URLSession(configuration: configuration))), registration)
    }

    private func makeAnthropicProvider(fixture: String) async throws -> AnthropicProvider {
        let url = try #require(URL(string: "https://fixture.invalid/v1/messages"))
        let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("RPGPlayer/Fixtures/Providers/Anthropic").appendingPathComponent(fixture)
        let fixtureData = try Data(contentsOf: fixtureURL)
        let registration = await RedactingURLProtocol.register(scenario: RedactingURLProtocol.Scenario(response: .http(statusCode: 200), steps: [.chunk(fixtureData)]), for: URLRequest(url: url))
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [RedactingURLProtocol.self]
        return AnthropicProvider(credentialReader: FixtureCredentialReader(value: "sk-ant-equivalence"), baseRequest: registration.request, httpClient: StreamingHTTPClient(session: URLSession(configuration: configuration)))
    }

    private func makeOpenAIProvider(fixture: String) async throws -> OpenAIProvider {
        let url = try #require(URL(string: "https://fixture.invalid/v1/responses"))
        let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("RPGPlayer/Fixtures/Providers/OpenAI").appendingPathComponent(fixture)
        let fixtureData = try Data(contentsOf: fixtureURL)
        let registration = await RedactingURLProtocol.register(scenario: RedactingURLProtocol.Scenario(response: .http(statusCode: 200), steps: [.chunk(fixtureData)]), for: URLRequest(url: url))
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [RedactingURLProtocol.self]
        return OpenAIProvider(credentialReader: FixtureCredentialReader(value: "sk-openai-equivalence"), baseRequest: registration.request, httpClient: StreamingHTTPClient(session: URLSession(configuration: configuration)))
    }

    private func makeOpenRouterProvider(fixture: String) async throws -> OpenRouterProvider {
        let url = try #require(URL(string: "https://fixture.invalid/api/v1/chat/completions"))
        let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("RPGPlayer/Fixtures/Providers/OpenRouter").appendingPathComponent(fixture)
        let fixtureData = try Data(contentsOf: fixtureURL)
        let registration = await RedactingURLProtocol.register(scenario: RedactingURLProtocol.Scenario(response: .http(statusCode: 200), steps: [.chunk(fixtureData)]), for: URLRequest(url: url))
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [RedactingURLProtocol.self]
        return OpenRouterProvider(credentialReader: FixtureCredentialReader(value: "sk-router-equivalence"), baseRequest: registration.request, httpClient: StreamingHTTPClient(session: URLSession(configuration: configuration)))
    }

    private func collect(_ stream: AsyncThrowingStream<ProviderStreamEvent, Error>) async throws -> [ProviderStreamEvent] { var events: [ProviderStreamEvent] = []; for try await event in stream { events.append(event) }; return events }
    private func makeRequest() throws -> TurnRequest { TurnRequest(requestID: try uuid("11111111-1111-4111-8111-111111111111"), campaignID: try uuid("22222222-2222-4222-8222-222222222222"), expectedSequence: 42, action: PlayerAction(text: "I light the lantern."), context: TurnContext(contextHash: try ContextHash(rawValue: String(repeating: "a", count: 64)), sections: [])) }
    private func uuid(_ value: String) throws -> UUID { try #require(UUID(uuidString: value)) }
}

private struct FixtureCredentialReader: ProviderCredentialReader, Sendable {
    let value: String
    func credentialData(for reference: ProviderCredentialReference) async throws -> Data { Data(value.utf8) }
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
        await withCheckedContinuation { continuation in waiters.append(continuation) }
    }
}

private struct BlockingCredentialReader: ProviderCredentialReader, Sendable {
    let gate: CredentialLoadGate

    func credentialData(for reference: ProviderCredentialReference) async throws -> Data {
        await gate.markStarted()
        try await Task.sleep(for: .seconds(60))
        return Data("unused-fixture-credential".utf8)
    }
}
