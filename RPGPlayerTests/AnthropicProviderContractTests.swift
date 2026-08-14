import Foundation
import Testing
@testable import RPGPlayer

@Suite(.serialized)
struct AnthropicProviderContractTests {
    @Test(.timeLimit(.minutes(1)))
    func messagesFixtureNormalizesStructuredTextAndUsage() async throws {
        let provider = try await makeProvider(fixture: "successful-text.sse")
        let events = try await collect(
            provider.adapter.streamTurn(try makeRequest())
        )

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
    func messagesRequestUsesStrictRecursiveStructuredOutputSchema() async throws {
        let provider = try await makeProvider(fixture: "successful-text.sse")
        _ = try await collect(provider.adapter.streamTurn(try makeRequest()))

        let snapshot = try #require(await provider.registration.diagnosticSnapshot())
        let body = try #require(snapshot.bodyData)
        let root = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let outputConfig = try #require(root["output_config"] as? [String: Any])
        let format = try #require(outputConfig["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let schema = try #require(format["schema"] as? [String: Any])
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
        #expect(data["type"] as? String == "string")
        #expect(data["description"] as? String == "A bounded JSON-encoded object for the discriminated event data.")
        #expect(unionParameterCount(in: schema) == 2)
        #expect(unionParameterCount(in: schema) <= 16)
        #expect(optionalParameterCount(in: schema) == 9)
        #expect(optionalParameterCount(in: schema) <= 24)
        #expect(objectSchemasAreStrict(in: schema))
    }

    @Test
    func messagesNormalizerReconstructsEveryProposalVariantAndRejectsMissingData() throws {
        let rollID = "33333333-3333-4333-8333-333333333333"
        let variants: [[String: Any]] = [
            ["type": "recordPatch", "data": "{\"recordID\":\"record-1\",\"fields\":\"{\\\"custom\\\":\\\"kept\\\",\\\"nested\\\":{\\\"count\\\":7}}\"}"],
            ["type": "rollRequest", "data": "{\"rollID\":\"\(rollID)\",\"expression\":\"1d20+4\",\"prompt\":\"Test the bell\"}"],
            ["type": "sceneChange", "data": "{\"sceneRecordID\":\"scene-1\",\"title\":\"Bell Tower\",\"summary\":\"Rain falls.\"}"],
            ["type": "clockUpdate", "data": "{\"clockRecordID\":\"clock-1\",\"current\":2,\"maximum\":6}"],
            ["type": "voiceSuggestion", "data": "{\"characterRecordID\":\"guide\",\"styleDescription\":\"Warm and cautious\"}"],
            ["type": "assetAttachment", "data": "{\"assetID\":\"asset-1\",\"targetRecordID\":\"scene-1\",\"fieldID\":\"portrait\"}"]
        ]
        let root: [String: Any] = [
            "schemaVersion": 1,
            "envelope": [
                "requestID": "11111111-1111-4111-8111-111111111111",
                "narration": [],
                "beats": [],
                "proposedEvents": variants,
                "pendingDecision": NSNull(),
                "voiceSegments": [],
                "usage": NSNull()
            ]
        ]
        let wireData = try JSONSerialization.data(withJSONObject: root)
        let normalized = try ProviderAdapterSupport.normalizedAnthropicEnvelopeData(from: wireData)
        let decoded = try VersionedTurnEnvelope.decode(from: normalized)
        let decodedRollID = try #require(UUID(uuidString: rollID))

        #expect(decoded.envelope.proposedEvents.count == 6)
        #expect(decoded.envelope.proposedEvents[0] == .recordPatch(recordID: "record-1", fields: ["custom": .string("kept"), "nested": .object(["count": .integer(7)])]))
        #expect(decoded.envelope.proposedEvents[1] == .rollRequest(rollID: decodedRollID, expression: "1d20+4", prompt: "Test the bell"))
        #expect(decoded.envelope.proposedEvents[2] == .sceneChange(sceneRecordID: "scene-1", title: "Bell Tower", summary: "Rain falls."))
        #expect(decoded.envelope.proposedEvents[3] == .clockUpdate(clockRecordID: "clock-1", current: 2, maximum: 6))
        #expect(decoded.envelope.proposedEvents[4] == .voiceSuggestion(characterRecordID: "guide", styleDescription: "Warm and cautious"))
        #expect(decoded.envelope.proposedEvents[5] == .assetAttachment(assetID: "asset-1", targetRecordID: "scene-1", fieldID: "portrait"))

        let missingData: [String: Any] = [
            "schemaVersion": 1,
            "envelope": [
                "requestID": "11111111-1111-4111-8111-111111111111",
                "narration": [], "beats": [],
                "proposedEvents": [["type": "rollRequest", "data": "{\"expression\":\"1d20\"}"]],
                "pendingDecision": NSNull(), "voiceSegments": [], "usage": NSNull()
            ]
        ]
        let missingDataWire = try JSONSerialization.data(withJSONObject: missingData)
        let normalizedMissingData = try ProviderAdapterSupport.normalizedAnthropicEnvelopeData(from: missingDataWire)
        #expect(throws: DecodingError.self) {
            try VersionedTurnEnvelope.decode(from: normalizedMissingData)
        }
    }

    @Test
    func messagesFixturePreservesArbitraryRecordPatchFields() async throws {
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
    func messagesModelDiscoveryExposesAnUnknownModel() async throws {
        let provider = try await makeProvider(fixture: "models.json", path: "models")
        let models = try await provider.adapter.models()
        #expect(models.map(\.id) == ["vendor/new-model"])
        #expect(models[0].providerID == .anthropic)
    }

    @Test
    func messagesModelDiscoveryFallsBackWhenProviderIsUnavailable() async throws {
        let provider = try await makeProvider(
            fixture: "models.json",
            response: .http(statusCode: 503),
            path: "models"
        )
        let models = try await provider.adapter.models()
        #expect(models.isEmpty == false)
        #expect(models.allSatisfy { $0.providerID == .anthropic })
        #expect(models.map(\.id).contains("claude-opus-5"))
    }

    @Test
    func messagesModelDiscoveryPreservesInvalidCredentialError() async throws {
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
    func messagesModelDiscoveryCancellationNormalizesToCancelled() async throws {
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
    func messagesFixturePreservesInterleavedAllowlistedToolCalls() async throws {
        let provider = try await makeProvider(fixture: "interleaved-tools.sse")
        let events = try await collect(provider.adapter.streamTurn(try makeRequest()))
        #expect(events == [
            .toolCallStarted(callID: "call-search", toolName: "searchRecords"),
            .toolCallStarted(callID: "call-roll", toolName: "requestRoll"),
            .toolCallArgumentFragment(callID: "call-search", fragment: "{\"query\":"),
            .toolCallArgumentFragment(callID: "call-roll", fragment: "{\"expression\":\"1d20+4\"}"),
            .toolCallArgumentFragment(callID: "call-search", fragment: "\"bell rope\"}"),
            .toolCallCompleted(callID: "call-roll", toolName: "requestRoll", arguments: try ProviderToolArguments(values: ["expression": .string("1d20+4")])),
            .toolCallCompleted(callID: "call-search", toolName: "searchRecords", arguments: try ProviderToolArguments(values: ["query": .string("bell rope")])),
            .finished(.requiresToolResults)
        ])
    }

    @Test
    func messagesFixtureRejectsUnknownToolBeforeEmittingToolEvents() async throws {
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
        await provider.registration.waitUntilStopped()
        #expect(await provider.registration.stopCount() == 1)
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["refusal.sse", "malformed-event.sse", "disconnect.sse"])
    func messagesFixturesNormalizeTerminalFailures(fixture: String) async throws {
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
    func messagesRateLimitNormalizesAndRedactsCredential() async throws {
        let sentinel = "sk-ant-fixture-sentinel-123456"
        let provider = try await makeProvider(
            fixture: "rate-limit.sse",
            sentinel: sentinel,
            response: .http(statusCode: 429)
        )
        do {
            _ = try await collect(provider.adapter.streamTurn(try makeRequest()))
            Issue.record("Expected a rate-limit error")
        } catch let error as ProviderError {
            #expect(error == .rateLimited(retryAfter: nil))
        } catch {
            Issue.record("Wrong normalized error: \(error)")
        }
        let snapshot = try #require(await provider.registration.diagnosticSnapshot())
        #expect(snapshot.headers["x-api-key"] == "<redacted>")
        #expect(snapshot.headers.values.contains { $0.contains(sentinel) } == false)
        #expect(NetworkDiagnosticRedactor().redact("body=\(sentinel)", knownSecrets: [sentinel]).contains(sentinel) == false)
    }

    @Test
    func messagesCredentialLoadingCancellationNormalizesToCancelled() async {
        let gate = CredentialLoadGate()
        let provider = AnthropicProvider(credentialReader: BlockingCredentialReader(gate: gate))
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

    private func makeProvider(
        fixture: String,
        sentinel: String = "sk-ant-fixture-safe-123456",
        response: RedactingURLProtocol.Response = .http(statusCode: 200),
        path: String = "messages",
        steps: [RedactingURLProtocol.Step]? = nil
    ) async throws -> (adapter: AnthropicProvider, registration: RedactingURLProtocol.Registration) {
        let url = try #require(URL(string: "https://fixture.invalid/v1/\(path)"))
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("RPGPlayer/Fixtures/Providers/Anthropic")
            .appendingPathComponent(fixture)
        let fixtureData = try Data(contentsOf: fixtureURL)
        let registration = await RedactingURLProtocol.register(
            scenario: RedactingURLProtocol.Scenario(response: response, steps: steps ?? [.chunk(fixtureData)]),
            for: URLRequest(url: url)
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedactingURLProtocol.self]
        return (
            AnthropicProvider(
                credentialReader: FixtureCredentialReader(value: sentinel),
                baseRequest: registration.request,
                httpClient: StreamingHTTPClient(session: URLSession(configuration: configuration))
            ),
            registration
        )
    }

    private func unionParameterCount(in value: Any) -> Int {
        if let object = value as? [String: Any] {
            let ownCount = (object["type"] as? [Any])?.contains { $0 as? String == "null" } == true ? 1 : 0
            return ownCount + object.values.reduce(0) { $0 + unionParameterCount(in: $1) }
        }
        if let array = value as? [Any] {
            return array.reduce(0) { $0 + unionParameterCount(in: $1) }
        }
        return 0
    }

    private func optionalParameterCount(in value: Any) -> Int {
        if let object = value as? [String: Any] {
            let properties = object["properties"] as? [String: Any] ?? [:]
            let required = Set(object["required"] as? [String] ?? [])
            let ownCount = properties.keys.filter { required.contains($0) == false }.count
            return ownCount + object.values.reduce(0) { $0 + optionalParameterCount(in: $1) }
        }
        if let array = value as? [Any] {
            return array.reduce(0) { $0 + optionalParameterCount(in: $1) }
        }
        return 0
    }

    private func objectSchemasAreStrict(in value: Any) -> Bool {
        if let object = value as? [String: Any] {
            let isObject = object["type"] as? String == "object"
                || (object["type"] as? [Any])?.contains { $0 as? String == "object" } == true
            if isObject && object["additionalProperties"] as? Bool != false {
                return false
            }
            return object.values.allSatisfy { objectSchemasAreStrict(in: $0) }
        }
        if let array = value as? [Any] {
            return array.allSatisfy { objectSchemasAreStrict(in: $0) }
        }
        return true
    }

    private func collect(_ stream: AsyncThrowingStream<ProviderStreamEvent, Error>) async throws -> [ProviderStreamEvent] {
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
            context: TurnContext(contextHash: try ContextHash(rawValue: String(repeating: "a", count: 64)), sections: [])
        )
    }

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
