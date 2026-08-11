import Foundation
import Testing
@testable import RPGPlayer

struct ProviderContractTests {
    @Test(arguments: [
        String(repeating: "a", count: 63),
        String(repeating: "A", count: 64),
        String(repeating: "g", count: 64)
    ])
    func contextHashRejectsValuesOutsideLowercaseSHA256Shape(
        _ rawValue: String
    ) {
        #expect(throws: ContextHash.ValidationError.invalidFormat) {
            try ContextHash(rawValue: rawValue)
        }
    }

    @Test
    func richTurnRequestRoundTripsWithSubmittedActionDistinctFromSessionAction() throws {
        let requestID = try #require(
            UUID(uuidString: "11111111-1111-4111-8111-111111111111")
        )
        let campaignID = try #require(
            UUID(uuidString: "22222222-2222-4222-8222-222222222222")
        )
        let request = TurnRequest(
            requestID: requestID,
            campaignID: campaignID,
            expectedSequence: 42,
            action: PlayerAction(
                text: "I light the lantern.",
                additionalContext: "Keep the villagers out of danger."
            ),
            context: TurnContext(
                contextHash: try ContextHash(
                    rawValue: String(repeating: "a", count: 64)
                ),
                sections: [
                    ContextSection(
                        kind: .systemContract,
                        items: [
                            ContextSection.Item(
                                id: "system-contract-v1",
                                name: "GM contract",
                                text: "Run a grounded mystery."
                            )
                        ]
                    ),
                    ContextSection(
                        kind: .currentScene,
                        items: [
                            ContextSection.Item(
                                id: "scene-bell-tower",
                                name: "Bell Tower",
                                text: "The bell tower is dark."
                            ),
                            ContextSection.Item(
                                text: "Rain masks footsteps."
                            )
                        ]
                    )
                ]
            )
        )
        let sessionAction: PlayerSessionAction = .setMode(.visualNovel)

        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(TurnRequest.self, from: encoded)

        #expect(decoded == request)
        #expect(decoded.action.text == "I light the lantern.")
        #expect(
            decoded.action.additionalContext
                == "Keep the villagers out of danger."
        )
        #expect(sessionAction == .setMode(.visualNovel))
    }

    @Test
    func versionOneGoldenEnvelopeDecodesAndRoundTripsExactly() throws {
        let fixtureData = try Data(contentsOf: turnEnvelopeFixtureURL)

        let decoded = try VersionedTurnEnvelope.decode(from: fixtureData)
        let reencoded = try decoded.encoded()
        let expected = try expectedVersionedEnvelope()

        #expect(decoded == expected)
        #expect(try normalizedJSON(reencoded) == normalizedJSON(fixtureData))
    }

    @Test
    func versionOneEnvelopeIgnoresAdditiveUnknownObjectFields() throws {
        let fixtureData = try Data(contentsOf: turnEnvelopeFixtureURL)
        var root = try #require(
            try JSONSerialization.jsonObject(with: fixtureData)
                as? [String: Any]
        )
        root["futureTopLevel"] = "preserved by its owner"
        var envelope = try #require(root["envelope"] as? [String: Any])
        envelope["futureEnvelopeField"] = ["enabled": true]
        var storyBlocks = try #require(
            envelope["narration"] as? [[String: Any]]
        )
        storyBlocks[0]["futureStoryField"] = 7
        envelope["narration"] = storyBlocks
        var proposals = try #require(
            envelope["proposedEvents"] as? [[String: Any]]
        )
        var proposalData = try #require(
            proposals[0]["data"] as? [String: Any]
        )
        proposalData["futureProposalField"] = "ignored"
        proposals[0]["data"] = proposalData
        envelope["proposedEvents"] = proposals
        root["envelope"] = envelope
        let additiveData = try JSONSerialization.data(withJSONObject: root)

        let decoded = try VersionedTurnEnvelope.decode(from: additiveData)
        let expected = try expectedVersionedEnvelope()

        #expect(decoded == expected)
    }

    @Test
    func versionedEnvelopeRejectsUnsupportedSchemaVersion() throws {
        let fixtureData = try Data(contentsOf: turnEnvelopeFixtureURL)
        var root = try #require(
            try JSONSerialization.jsonObject(with: fixtureData)
                as? [String: Any]
        )
        root["schemaVersion"] = 2
        let unsupportedData = try JSONSerialization.data(withJSONObject: root)

        #expect(
            throws: VersionedTurnEnvelope.CodingError
                .unsupportedSchemaVersion(2)
        ) {
            try VersionedTurnEnvelope.decode(from: unsupportedData)
        }
    }

    @Test(arguments: [
        "teleport",
        "campaignImported",
        "playerActionSubmitted",
        "gmStatusChanged",
        "gmMessageCommitted",
        "turnCancelled",
        "turnFailed"
    ])
    func versionedEnvelopeRejectsUnknownAndControlProposalKinds(
        _ proposalKind: String
    ) throws {
        let fixtureData = try Data(contentsOf: turnEnvelopeFixtureURL)
        var root = try #require(
            try JSONSerialization.jsonObject(with: fixtureData)
                as? [String: Any]
        )
        var envelope = try #require(root["envelope"] as? [String: Any])
        var proposals = try #require(
            envelope["proposedEvents"] as? [[String: Any]]
        )
        proposals[0]["type"] = proposalKind
        envelope["proposedEvents"] = proposals
        root["envelope"] = envelope
        let invalidData = try JSONSerialization.data(withJSONObject: root)

        #expect(throws: DecodingError.self) {
            try VersionedTurnEnvelope.decode(from: invalidData)
        }
    }

    @Test
    func versionedEnvelopeRejectsOversizedInputBeforeJSONParsing() {
        let oversizedData = Data(
            repeating: 0x20,
            count: VersionedTurnEnvelope.maximumEncodedBytes + 1
        )

        #expect(
            throws: VersionedTurnEnvelope.CodingError.payloadTooLarge(
                maximumBytes: 8_000_000,
                actualBytes: 8_000_001
            )
        ) {
            try VersionedTurnEnvelope.decode(from: oversizedData)
        }
    }

    @Test
    func versionedEnvelopeRefusesToEncodeMoreThanEightMillionBytes() throws {
        let oversized = VersionedTurnEnvelope(
            envelope: TurnEnvelope(
                requestID: try uuid(
                    "11111111-1111-4111-8111-111111111111"
                ),
                narration: [
                    StoryBlock(
                        id: try uuid(
                            "10000000-0000-4000-8000-000000000001"
                        ),
                        kind: .narration,
                        text: String(repeating: "x", count: 8_000_000)
                    )
                ],
                beats: [],
                proposedEvents: [],
                pendingDecision: nil,
                voiceSegments: [],
                usage: nil
            )
        )

        do {
            _ = try oversized.encoded()
            Issue.record("Expected the oversized envelope to be rejected")
        } catch VersionedTurnEnvelope.CodingError.payloadTooLarge(
            let maximumBytes,
            let actualBytes
        ) {
            #expect(maximumBytes == 8_000_000)
            #expect(actualBytes > maximumBytes)
        } catch {
            Issue.record("Wrong error thrown: \(error)")
        }
    }

    @Test
    func completedToolArgumentsUseBoundedCanonicalJSON() throws {
        let accepted = try ProviderToolArguments(
            values: [
                "payload": .string(
                    String(repeating: "x", count: 999_986)
                )
            ]
        )
        let acceptedLiteralData = try JSONSerialization.data(
            withJSONObject: [
                "payload": String(repeating: "x", count: 999_986)
            ],
            options: [.sortedKeys]
        )

        #expect(acceptedLiteralData.count == 1_000_000)
        #expect(
            accepted.values["payload"]
                == .string(String(repeating: "x", count: 999_986))
        )

        do {
            _ = try ProviderToolArguments(
                values: [
                    "payload": .string(
                        String(repeating: "x", count: 999_987)
                    )
                ]
            )
            Issue.record("Expected oversized tool arguments to be rejected")
        } catch ProviderToolArguments.ValidationError.payloadTooLarge(
            let maximumBytes,
            let actualBytes
        ) {
            #expect(maximumBytes == 1_000_000)
            #expect(actualBytes > maximumBytes)
        } catch {
            Issue.record("Wrong error thrown: \(error)")
        }
    }

    @Test
    func providerModelRoundTripsWithTheClosedProviderIdentity() throws {
        let model = try ProviderModel(
            providerID: .openAI,
            id: "gpt-5.1",
            displayName: "GPT-5.1",
            contextWindowTokens: 400_000,
            maximumOutputTokens: 128_000,
            supportsTools: true,
            supportsStructuredOutput: true
        )

        let encoded = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(
            ProviderModel.self,
            from: encoded
        )

        #expect(decoded == model)
        #expect(
            ProviderID.allCases
                == [.openAI, .openRouter, .anthropic, .gemini]
        )
    }

    @Test(arguments: ProviderModelInvalidFixture.allCases)
    func providerModelInitializationAndDecodingRejectInvalidIdentityOrWindows(
        _ fixture: ProviderModelInvalidFixture
    ) throws {
        do {
            _ = try ProviderModel(
                providerID: .openAI,
                id: fixture.id,
                displayName: "Test Model",
                contextWindowTokens: fixture.contextWindowTokens,
                maximumOutputTokens: fixture.maximumOutputTokens,
                supportsTools: true,
                supportsStructuredOutput: true
            )
            Issue.record("Expected model initialization to fail")
        } catch let error as ProviderModel.ValidationError {
            #expect(error == fixture.expectedError)
        } catch {
            Issue.record("Wrong initialization error: \(error)")
        }

        let encoded = try JSONSerialization.data(
            withJSONObject: [
                "providerID": "openAI",
                "id": fixture.id,
                "displayName": "Test Model",
                "contextWindowTokens": fixture.contextWindowTokens,
                "maximumOutputTokens": fixture.maximumOutputTokens,
                "supportsTools": true,
                "supportsStructuredOutput": true
            ],
            options: [.sortedKeys]
        )
        do {
            _ = try JSONDecoder().decode(ProviderModel.self, from: encoded)
            Issue.record("Expected model decoding to fail")
        } catch let error as ProviderModel.ValidationError {
            #expect(error == fixture.expectedError)
        } catch {
            Issue.record("Wrong decoding error: \(error)")
        }
    }

    @Test(arguments: ProviderErrorRetryFixture.all)
    func providerErrorsExposeOnlyTheFrozenRetryPolicy(
        _ fixture: ProviderErrorRetryFixture
    ) throws {
        #expect(
            fixture.error.isRetryableWithoutUserCorrection
                == fixture.expectedRetryable
        )
        let description = try #require(fixture.error.errorDescription)
        #expect(description.isEmpty == false)
    }

    @Test
    func streamContractStopsAtTheFirstCompletedTerminal() async throws {
        let envelope = try expectedVersionedEnvelope().envelope
        let usage = ProviderUsage(
            inputTokens: 80,
            outputTokens: 20,
            cachedInputTokens: 10
        )
        let source = AsyncThrowingStream<ProviderStreamEvent, Error> {
            continuation in
            continuation.yield(.textDelta("Rain needles the windows."))
            continuation.yield(.warning(.contentFiltered))
            continuation.yield(.usage(usage))
            continuation.yield(.finished(.completed(envelope)))
            continuation.yield(.textDelta("must be ignored"))
            continuation.yield(.finished(.maximumOutputTokens))
            continuation.finish()
        }

        let events = try await collect(
            ProviderStreamContract.enforcing(source, onCancel: {})
        )

        #expect(events == [
            .textDelta("Rain needles the windows."),
            .warning(.contentFiltered),
            .usage(usage),
            .finished(.completed(envelope))
        ])
    }

    @Test
    func streamContractPreservesInterleavedToolsUntilToolSubturnTerminal()
        async throws {
        let searchArguments = try ProviderToolArguments(
            values: ["query": .string("bell rope")]
        )
        let rollArguments = try ProviderToolArguments(
            values: ["expression": .string("1d20+4")]
        )
        let source = AsyncThrowingStream<ProviderStreamEvent, Error> {
            continuation in
            continuation.yield(
                .toolCallStarted(callID: "call-search", toolName: "searchRecords")
            )
            continuation.yield(
                .toolCallStarted(callID: "call-roll", toolName: "requestRoll")
            )
            continuation.yield(
                .toolCallArgumentFragment(
                    callID: "call-search",
                    fragment: "{\"query\":"
                )
            )
            continuation.yield(
                .toolCallArgumentFragment(
                    callID: "call-roll",
                    fragment: "{\"expression\":\"1d20+4\"}"
                )
            )
            continuation.yield(
                .toolCallArgumentFragment(
                    callID: "call-search",
                    fragment: "\"bell rope\"}"
                )
            )
            continuation.yield(
                .toolCallCompleted(
                    callID: "call-roll",
                    toolName: "requestRoll",
                    arguments: rollArguments
                )
            )
            continuation.yield(
                .toolCallCompleted(
                    callID: "call-search",
                    toolName: "searchRecords",
                    arguments: searchArguments
                )
            )
            continuation.yield(.finished(.requiresToolResults))
            continuation.finish()
        }

        let events = try await collect(
            ProviderStreamContract.enforcing(source, onCancel: {})
        )

        #expect(events.last == .finished(.requiresToolResults))
        #expect(events.count == 8)
        #expect(
            events[2]
                == .toolCallArgumentFragment(
                    callID: "call-search",
                    fragment: "{\"query\":"
                )
        )
        #expect(
            events[5]
                == .toolCallCompleted(
                    callID: "call-roll",
                    toolName: "requestRoll",
                    arguments: rollArguments
                )
        )
    }

    @Test
    func streamContractMapsEOFBeforeTerminalToMalformedResponse() async {
        let source = AsyncThrowingStream<ProviderStreamEvent, Error> {
            continuation in
            continuation.yield(.textDelta("An incomplete answer"))
            continuation.finish()
        }

        do {
            _ = try await collect(
                ProviderStreamContract.enforcing(source, onCancel: {})
            )
            Issue.record("Expected EOF without a terminal event to fail")
        } catch let error as ProviderError {
            #expect(error == .malformedResponse)
        } catch {
            Issue.record("Wrong stream error: \(error)")
        }
    }

    @Test
    func downstreamCancellationInvokesAsyncCancellationExactlyOnce() async {
        let sourcePair = AsyncThrowingStream<ProviderStreamEvent, Error>
            .makeStream()
        let ready = AsyncProbe()
        let cancelled = AsyncProbe()
        let sourceTerminated = AsyncProbe()
        sourcePair.continuation.onTermination = { _ in
            Task {
                await sourceTerminated.record()
            }
        }
        let consumer = Task {
            var iterator = ProviderStreamContract.enforcing(
                sourcePair.stream,
                onCancel: {
                    await cancelled.record()
                }
            ).makeAsyncIterator()
            _ = try await iterator.next()
            await ready.record()
            return try await iterator.next()
        }
        sourcePair.continuation.yield(.textDelta("ready"))
        await ready.wait()

        consumer.cancel()
        let result = await consumer.result
        await cancelled.wait()
        await sourceTerminated.wait()
        let lateYield = sourcePair.continuation.yield(
            .textDelta("must not be relayed")
        )

        let cancellationCount = await cancelled.count
        let sourceTerminationCount = await sourceTerminated.count
        #expect(cancellationCount == 1)
        #expect(sourceTerminationCount == 1)
        switch result {
        case .success(let event):
            // AsyncThrowingStream reports downstream Task cancellation as EOF.
            #expect(event == nil)
        case .failure(let error as ProviderError):
            #expect(error == .cancelled)
        case .failure(let error):
            Issue.record("Wrong downstream cancellation error: \(error)")
        }
        switch lateYield {
        case .terminated:
            break
        case .enqueued, .dropped:
            Issue.record("Source accepted an event after cancellation")
        @unknown default:
            Issue.record("Unknown yield result after cancellation")
        }
    }

    @Test
    func actorProviderSupportsAsyncFactoryAndIdempotentExplicitCancellation()
        async throws {
        let fake = ContractFakeProvider()
        let provider: any AIProvider = fake
        let request = try makeTurnRequest()

        let models = try await provider.models()
        let stream = try await provider.streamTurn(request)
        await provider.cancel(requestID: request.requestID)
        await provider.cancel(requestID: request.requestID)

        #expect(provider.id == .openAI)
        #expect(models.map(\.id) == ["test-model"])
        do {
            _ = try await collect(stream)
            Issue.record("Expected explicit cancellation to terminate the stream")
        } catch let error as ProviderError {
            #expect(error == .cancelled)
        } catch {
            Issue.record("Wrong cancellation error: \(error)")
        }
        let cancellationCount = await fake.cancellationCount(
            for: request.requestID
        )
        #expect(cancellationCount == 1)
    }

    private var turnEnvelopeFixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("RPGPlayer/Fixtures/Providers/v1")
            .appendingPathComponent("turn-envelope.json")
    }

    private func collect(
        _ stream: AsyncThrowingStream<ProviderStreamEvent, Error>
    ) async throws -> [ProviderStreamEvent] {
        var events: [ProviderStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    private func makeTurnRequest() throws -> TurnRequest {
        TurnRequest(
            requestID: try uuid(
                "11111111-1111-4111-8111-111111111111"
            ),
            campaignID: try uuid(
                "22222222-2222-4222-8222-222222222222"
            ),
            expectedSequence: 42,
            action: PlayerAction(text: "I light the lantern."),
            context: TurnContext(
                contextHash: try ContextHash(
                    rawValue: String(repeating: "a", count: 64)
                ),
                sections: []
            )
        )
    }

    private func normalizedJSON(_ data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data)
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
    }

    private func expectedVersionedEnvelope() throws -> VersionedTurnEnvelope {
        VersionedTurnEnvelope(
            envelope: TurnEnvelope(
                requestID: try uuid(
                    "11111111-1111-4111-8111-111111111111"
                ),
                narration: [
                    StoryBlock(
                        id: try uuid(
                            "10000000-0000-4000-8000-000000000001"
                        ),
                        kind: .narration,
                        text: "Rain needles the dark windows."
                    ),
                    StoryBlock(
                        id: try uuid(
                            "10000000-0000-4000-8000-000000000002"
                        ),
                        kind: .dialogue,
                        speakerRecordID: "record-guide",
                        speakerName: "Mara Vale",
                        mood: "Hushed",
                        text: "The bell did not ring by itself."
                    )
                ],
                beats: [
                    VisualNovelBeat(
                        id: try uuid(
                            "20000000-0000-4000-8000-000000000001"
                        ),
                        kind: .title,
                        title: "THE SILENT BELL",
                        subtitle: "Greyhaven, after midnight",
                        speaker: nil,
                        mood: nil,
                        text: "The Silent Bell"
                    ),
                    VisualNovelBeat(
                        id: try uuid(
                            "20000000-0000-4000-8000-000000000002"
                        ),
                        kind: .dialogue,
                        title: nil,
                        subtitle: nil,
                        speaker: "Mara Vale",
                        mood: "Hushed",
                        text: "The bell did not ring by itself."
                    )
                ],
                proposedEvents: [
                    .recordPatch(
                        recordID: "record-bell-tower",
                        fields: [
                            "searched": .bool(true),
                            "threatLevel": .integer(2)
                        ]
                    ),
                    .rollRequest(
                        rollID: try uuid(
                            "30000000-0000-4000-8000-000000000001"
                        ),
                        expression: "1d20+4",
                        prompt: "Search the bell tower before the watch arrives."
                    ),
                    .sceneChange(
                        sceneRecordID: "record-bell-tower",
                        title: "The Silent Bell",
                        summary: "Rain and old bronze conceal a fresh crime."
                    ),
                    .clockUpdate(
                        clockRecordID: "clock-watch-arrives",
                        current: 2,
                        maximum: 6
                    ),
                    .voiceSuggestion(
                        characterRecordID: "record-guide",
                        styleDescription: "Low, deliberate, and guarded"
                    ),
                    .assetAttachment(
                        assetID: "asset-bell-sketch",
                        targetRecordID: "record-bell-tower",
                        fieldID: "illustration"
                    )
                ],
                pendingDecision: PlayerDecision(
                    id: try uuid(
                        "40000000-0000-4000-8000-000000000001"
                    ),
                    prompt: "Where do you search first?",
                    options: [
                        PlayerDecision.Option(
                            title: "Climb to the bell",
                            detail: "Inspect the bronze and its rope."
                        ),
                        PlayerDecision.Option(
                            title: "Search the vestry",
                            detail: "Look for whoever entered below."
                        )
                    ]
                ),
                voiceSegments: [
                    VoiceSegment(
                        id: try uuid(
                            "50000000-0000-4000-8000-000000000001"
                        ),
                        sourceStoryBlockID: try uuid(
                            "10000000-0000-4000-8000-000000000002"
                        ),
                        speakerRecordID: "record-guide",
                        speakerName: "Mara Vale",
                        text: "The bell did not ring by itself."
                    )
                ],
                usage: ProviderUsage(
                    inputTokens: 1_200,
                    outputTokens: 340,
                    cachedInputTokens: 250
                )
            )
        )
    }

    private func uuid(_ value: String) throws -> UUID {
        try #require(UUID(uuidString: value))
    }
}

enum ProviderModelInvalidFixture: CaseIterable, Sendable {
    case blankID
    case nonpositiveContextWindow
    case nonpositiveMaximumOutput
    case outputExceedsContextWindow

    var id: String {
        self == .blankID ? "   " : "model-id"
    }

    var contextWindowTokens: Int {
        switch self {
        case .nonpositiveContextWindow: 0
        case .outputExceedsContextWindow: 4_000
        default: 8_000
        }
    }

    var maximumOutputTokens: Int {
        switch self {
        case .nonpositiveMaximumOutput: 0
        case .outputExceedsContextWindow: 4_001
        default: 2_000
        }
    }

    var expectedError: ProviderModel.ValidationError {
        switch self {
        case .blankID: .blankModelID
        case .nonpositiveContextWindow: .nonpositiveContextWindow
        case .nonpositiveMaximumOutput: .nonpositiveMaximumOutputTokens
        case .outputExceedsContextWindow: .maximumOutputExceedsContextWindow
        }
    }
}

struct ProviderErrorRetryFixture: Sendable {
    let error: ProviderError
    let expectedRetryable: Bool

    static let all: [ProviderErrorRetryFixture] = [
        ProviderErrorRetryFixture(
            error: .invalidCredential,
            expectedRetryable: false
        ),
        ProviderErrorRetryFixture(
            error: .quotaExceeded,
            expectedRetryable: false
        ),
        ProviderErrorRetryFixture(
            error: .rateLimited(retryAfter: nil),
            expectedRetryable: true
        ),
        ProviderErrorRetryFixture(
            error: .contextExceeded,
            expectedRetryable: false
        ),
        ProviderErrorRetryFixture(
            error: .safetyRefusal,
            expectedRetryable: false
        ),
        ProviderErrorRetryFixture(
            error: .malformedResponse,
            expectedRetryable: false
        ),
        ProviderErrorRetryFixture(
            error: .connectivity,
            expectedRetryable: true
        ),
        ProviderErrorRetryFixture(
            error: .cancelled,
            expectedRetryable: false
        ),
        ProviderErrorRetryFixture(
            error: .serviceFailure(statusCode: nil),
            expectedRetryable: true
        )
    ]
}

actor AsyncProbe {
    private(set) var count = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func record() {
        count += 1
        let pendingWaiters = waiters
        waiters.removeAll()
        for waiter in pendingWaiters {
            waiter.resume()
        }
    }

    func wait() async {
        guard count == 0 else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

actor ContractFakeProvider: AIProvider {
    nonisolated let id: ProviderID = .openAI

    private var continuations: [
        UUID: AsyncThrowingStream<ProviderStreamEvent, Error>.Continuation
    ] = [:]
    private var cancellationCounts: [UUID: Int] = [:]

    func models() async throws -> [ProviderModel] {
        [
            try ProviderModel(
                providerID: id,
                id: "test-model",
                displayName: "Test Model",
                contextWindowTokens: 8_000,
                maximumOutputTokens: 2_000,
                supportsTools: true,
                supportsStructuredOutput: true
            )
        ]
    }

    func streamTurn(
        _ request: TurnRequest
    ) async throws -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        let pair = AsyncThrowingStream<ProviderStreamEvent, Error>.makeStream()
        continuations[request.requestID] = pair.continuation
        return ProviderStreamContract.enforcing(
            pair.stream,
            onCancel: { [weak self] in
                await self?.cancel(requestID: request.requestID)
            }
        )
    }

    func cancel(requestID: UUID) async {
        guard cancellationCounts[requestID] == nil,
              let continuation = continuations.removeValue(
                  forKey: requestID
              ) else {
            return
        }
        cancellationCounts[requestID] = 1
        continuation.finish(throwing: ProviderError.cancelled)
    }

    func cancellationCount(for requestID: UUID) -> Int {
        cancellationCounts[requestID, default: 0]
    }
}
