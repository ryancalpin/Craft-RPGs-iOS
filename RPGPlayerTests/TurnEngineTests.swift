import Foundation
import Testing
@testable import RPGPlayer

@Suite(.serialized)
struct TurnEngineTests {
    @Test
    func happyPathPresentsStreamAndAppendsOneAtomicBatch() async throws {
        let request = try Fixture.request()
        let envelope = Fixture.envelope(requestID: request.requestID)
        let presentedEnvelope = VersionedTurnEnvelope(envelope: envelope)
        let provider = ScriptedProvider(events: [
            .textDelta("The rain needles the glass."),
            .toolCallStarted(callID: "search-1", toolName: "searchRecords"),
            .toolCallCompleted(
                callID: "search-1",
                toolName: "searchRecords",
                arguments: try ProviderToolArguments(
                    values: ["query": .string("bell")]
                )
            ),
            .finished(.completed(envelope))
        ])
        let store = RecordingCampaignStore()
        let engine = TurnEngine(
            provider: provider,
            store: store,
            validationContext: Fixture.validationContext(
                campaignID: request.campaignID
            )
        )

        let execution = await engine.run(request)

        #expect(execution.result == .committed)
        #expect(execution.presentation.contains(.status(.queued)))
        #expect(execution.presentation.contains(.status(.readingWorld)))
        #expect(execution.presentation.contains(.status(.planning)))
        #expect(execution.presentation.contains(.status(.writingScene)))
        #expect(execution.presentation.contains(.status(.voicing)))
        #expect(execution.presentation.contains(.prose("The rain needles the glass.")))
        #expect(execution.presentation.contains(.toolStarted(callID: "search-1", toolName: "searchRecords")))
        #expect(execution.presentation.contains(.toolResult(callID: "search-1", toolName: "searchRecords", sanitizedStatus: "Records searched.")))
        #expect(execution.presentation.contains(.completed(presentedEnvelope)))
        #expect(await store.appendCount == 1)
        let batch = try #require(await store.batches.first)
        #expect(batch.count == 2)
        #expect(batch.allSatisfy { $0.requestID == request.requestID })
        #expect(batch[0].sequence == 0)
        #expect(batch[1].sequence == 0)
        #expect(batch.contains { if case .playerActionSubmitted = $0.payload { return true }; return false })
        #expect(batch.contains { if case .gmMessageCommitted = $0.payload { return true }; return false })
    }

    @Test
    func toolBoundaryContinuesWithChangedContextAndFinalCompletion() async throws {
        let request = try Fixture.request()
        let provider = ScriptedProvider(turns: [
            [
                .toolCallStarted(callID: "search-1", toolName: "searchRecords"),
                .toolCallCompleted(
                    callID: "search-1",
                    toolName: "searchRecords",
                    arguments: try ProviderToolArguments(
                        values: ["query": .string("bell")]
                    )
                ),
                .finished(.requiresToolResults)
            ],
            [.finished(.completed(Fixture.envelope(requestID: request.requestID)))]
        ])
        let store = RecordingCampaignStore()
        let engine = TurnEngine(
            provider: provider,
            store: store,
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        )

        let execution = await engine.run(request)

        #expect(execution.result == .committed)
        #expect(await provider.streamCallCount == 2)
        let first = try #require(await provider.request(at: 0))
        let continuation = try #require(await provider.request(at: 1))
        #expect(continuation.requestID == first.requestID)
        #expect(continuation.campaignID == first.campaignID)
        #expect(continuation.expectedSequence == first.expectedSequence)
        #expect(continuation.action == first.action)
        #expect(continuation.context != first.context)
        #expect(continuation.context.sections.contains { $0.kind == .toolResults })
        #expect(continuation.context.sections.last?.items.first?.text.contains("Records searched.") == true)

        let expectedSections = continuation.context.sections
        let expectedInputTokens = expectedSections.reduce(0) { total, section in
            total + ContextBudget.sectionOverheadTokens
                + section.items.reduce(0) {
                    $0 + ContextBudget.estimateTokens(for: $1)
                }
        }
        let firstAssembly = try #require(first.contextAssembly)
        let expectedBudget = firstAssembly.budget.recording(
            estimatedInputTokens: expectedInputTokens
        )
        let expectedMetadata = firstAssembly.metadata
        let expectedHash = TurnContextAssembler.canonicalHash(
            sections: expectedSections,
            budget: expectedBudget,
            metadata: expectedMetadata
        )
        #expect(continuation.context.contextHash == expectedHash)
        #expect(continuation.contextAssembly?.budget == expectedBudget)
        #expect(continuation.contextAssembly?.metadata == expectedMetadata)
    }

    @Test
    func toolBoundaryRejectsAnIncompleteCurrentStream() async throws {
        let request = try Fixture.request()
        let provider = ScriptedProvider(events: [
            .toolCallStarted(callID: "search-1", toolName: "searchRecords"),
            .finished(.requiresToolResults)
        ])
        let store = RecordingCampaignStore()
        let engine = TurnEngine(
            provider: provider,
            store: store,
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        )

        let execution = await engine.run(request)

        #expect(execution.result == .failed(.invalidTool(.malformedArguments)))
        #expect(await provider.streamCallCount == 1)
        #expect(await store.appendCount == 0)
    }

    @Test
    func finalCompletionCannotCommitWithAnIncompleteToolCall() async throws {
        let request = try Fixture.request()
        let provider = ScriptedProvider(events: [
            .toolCallStarted(callID: "search-1", toolName: "searchRecords"),
            .finished(.completed(Fixture.envelope(requestID: request.requestID)))
        ])
        let store = RecordingCampaignStore()
        let engine = TurnEngine(
            provider: provider,
            store: store,
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        )

        let execution = await engine.run(request)

        #expect(execution.result == .failed(.invalidTool(.malformedArguments)))
        #expect(await store.appendCount == 0)
    }

    @Test
    func continuationRejectsAStaleOrForgedInputAssemblyHash() async throws {
        let request = try Fixture.request()
        let assembly = try #require(request.contextAssembly)
        let forgedAssembly = TurnContextAssembly(
            context: TurnContext(
                contextHash: try ContextHash(rawValue: String(repeating: "0", count: 64)),
                sections: assembly.context.sections
            ),
            budget: assembly.budget,
            metadata: assembly.metadata
        )
        let forgedRequest = TurnRequest(
            requestID: request.requestID,
            campaignID: request.campaignID,
            expectedSequence: request.expectedSequence,
            action: request.action,
            assembly: forgedAssembly
        )
        let provider = ScriptedProvider(turns: [[
            .toolCallStarted(callID: "search-1", toolName: "searchRecords"),
            .toolCallCompleted(
                callID: "search-1",
                toolName: "searchRecords",
                arguments: try ProviderToolArguments(values: ["query": .string("bell")])
            ),
            .finished(.requiresToolResults)
        ], [
            .finished(.completed(Fixture.envelope(requestID: request.requestID)))
        ]])
        let store = RecordingCampaignStore()
        let engine = TurnEngine(
            provider: provider,
            store: store,
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        )

        let execution = await engine.run(forgedRequest)

        #expect(execution.result == .failed(.missingContextAssembly))
        #expect(await provider.streamCallCount == 1)
        #expect(await store.appendCount == 0)
    }

    @Test
    func concurrentRequestReservationPreventsDuplicateProviderRuns() async throws {
        let request = try Fixture.request()
        let provider = ScriptedProvider(events: [
            .finished(.completed(Fixture.envelope(requestID: request.requestID)))
        ])
        let store = LookupBarrierCampaignStore()
        let engine = TurnEngine(
            provider: provider,
            store: store,
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        )

        let firstTask = Task { await engine.run(request) }
        await store.waitUntilFirstLookupStarted()
        let second = await engine.run(request)
        #expect(second.result == .failed(.alreadyRunning))

        await store.releaseFirstLookup()
        let first = await firstTask.value
        #expect(first.result == .committed)
        #expect(await provider.streamCallCount == 1)
    }

    @Test
    func cancellationDuringDurableLookupIsPersistedBeforeProviderSetup() async throws {
        let request = try Fixture.request()
        let provider = ScriptedProvider(events: [
            .finished(.completed(Fixture.envelope(requestID: request.requestID)))
        ])
        let store = LookupBarrierCampaignStore()
        let engine = TurnEngine(
            provider: provider,
            store: store,
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        )

        let task = Task { await engine.run(request) }
        await store.waitUntilFirstLookupStarted()
        let cancellation = await engine.cancel(requestID: request.requestID)
        #expect(cancellation.result == .failed(.cancelled))

        await store.releaseFirstLookup()
        let execution = await task.value
        #expect(execution.result == .cancelled)
        #expect(await provider.streamCallCount == 0)
        #expect(await store.appendCount == 1)
    }

    @Test
    func cancellationBeforeRunIsRetainedUntilRunPersistsTheTerminalOutcome() async throws {
        let request = try Fixture.request(expectedSequence: 0)
        let provider = ScriptedProvider(events: [
            .finished(.completed(Fixture.envelope(requestID: request.requestID)))
        ])
        let store = DurableCampaignStore()
        let engine = TurnEngine(
            provider: provider,
            store: store,
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        )

        let cancellation = await engine.cancel(requestID: request.requestID)
        let execution = await engine.run(request)

        #expect(cancellation.result == .failed(.cancelled))
        #expect(execution.result == .cancelled)
        #expect(await provider.streamCallCount == 0)
        #expect(await store.appendCount == 1)
    }

    @Test
    func cancellationReconcilesARealTerminalBeforeReportingCancellation() async throws {
        let request = try Fixture.request(expectedSequence: 0)
        let store = DurableCampaignStore()
        let firstProvider = ScriptedProvider(events: [
            .finished(.completed(Fixture.envelope(requestID: request.requestID)))
        ])
        let firstEngine = TurnEngine(
            provider: firstProvider,
            store: store,
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        )
        #expect((await firstEngine.run(request)).result == .committed)

        let retryProvider = ScriptedProvider(events: [])
        let retryEngine = TurnEngine(
            provider: retryProvider,
            store: store,
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        )
        let cancellation = await retryEngine.cancel(requestID: request.requestID)

        #expect(cancellation.result == .failed(.canonicalFinalAlreadyExists))
        #expect(await retryProvider.streamCallCount == 0)
        #expect(await store.appendCount == 1)
    }

    @Test
    func toolContinuationRejectsResultsThatExceedTheInputBudget() async throws {
        let request = try Fixture.constrainedRequest()
        let provider = ScriptedProvider(turns: [[
            .toolCallStarted(callID: "search-1", toolName: "searchRecords"),
            .toolCallCompleted(
                callID: "search-1",
                toolName: "searchRecords",
                arguments: try ProviderToolArguments(
                    values: ["query": .string("bell")]
                )
            ),
            .finished(.requiresToolResults)
        ], [
            .finished(.completed(Fixture.envelope(requestID: request.requestID)))
        ]])
        let store = RecordingCampaignStore()
        let engine = TurnEngine(
            provider: provider,
            store: store,
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        )

        let execution = await engine.run(request)

        if case .failed(.contextBudgetExceeded(let estimated, let budget)) = execution.result {
            #expect(estimated > budget)
        } else {
            Issue.record("Expected the continuation to fail before provider dispatch.")
        }
        #expect(await provider.streamCallCount == 1)
        #expect(await store.appendCount == 0)
    }

    @Test
    func invalidToolDoesNotAppendPartialState() async throws {
        let request = try Fixture.request()
        let provider = ScriptedProvider(events: [
            .toolCallStarted(callID: "bad-1", toolName: "runShell"),
            .toolCallCompleted(
                callID: "bad-1",
                toolName: "runShell",
                arguments: try ProviderToolArguments(values: [:])
            )
        ])
        let store = RecordingCampaignStore()
        let engine = TurnEngine(
            provider: provider,
            store: store,
            validationContext: Fixture.validationContext(
                campaignID: request.campaignID
            )
        )

        let execution = await engine.run(request)

        #expect(execution.result == .failed(.invalidTool(.unknownTool)))
        #expect(await store.appendCount == 0)
        #expect(execution.presentation.contains(.failure(.invalidTool(.unknownTool))))
    }

    @Test
    func malformedEnvelopeRequestMismatchAndDuplicateCompletionDoNotAppend() async throws {
        let request = try Fixture.request()
        let malformed = TurnEnvelope(
            requestID: request.requestID,
            narration: [Fixture.storyBlock],
            beats: [VisualNovelBeat(id: Fixture.beat.id, kind: .narration, title: nil, subtitle: nil, speaker: nil, mood: nil, text: "different text")],
            proposedEvents: [],
            pendingDecision: nil,
            voiceSegments: [],
            usage: nil
        )
        let provider = ScriptedProvider(events: [
            .finished(.completed(malformed))
        ])
        let store = RecordingCampaignStore()
        let engine = TurnEngine(
            provider: provider,
            store: store,
            validationContext: Fixture.validationContext(
                campaignID: request.campaignID
            )
        )

        let malformedResult = await engine.run(request)
        #expect(malformedResult.result == .failed(.invalidEnvelope(.transcriptBeatMismatch)))
        #expect(await store.appendCount == 0)

        let duplicateProvider = ScriptedProvider(events: [
            .finished(.completed(Fixture.envelope(requestID: request.requestID))),
            .finished(.completed(Fixture.envelope(requestID: request.requestID)))
        ])
        let duplicateStore = RecordingCampaignStore()
        let duplicateEngine = TurnEngine(
            provider: duplicateProvider,
            store: duplicateStore,
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        )
        let duplicate = await duplicateEngine.run(request)
        #expect(duplicate.result == .failed(.duplicateCompletion))
        #expect(await duplicateStore.appendCount == 0)

        let mismatchRequest = try Fixture.request()
        let mismatchProvider = ScriptedProvider(events: [
            .finished(.completed(
                Fixture.envelope(requestID: UUID())
            ))
        ])
        let mismatchStore = RecordingCampaignStore()
        let mismatchEngine = TurnEngine(
            provider: mismatchProvider,
            store: mismatchStore,
            validationContext: Fixture.validationContext(
                campaignID: mismatchRequest.campaignID
            )
        )
        let mismatch = await mismatchEngine.run(mismatchRequest)
        #expect(mismatch.result == .failed(.requestIDMismatch))
        #expect(await mismatchStore.appendCount == 0)
    }

    @Test
    func finalRollMustMatchTheCompletedRequestRollLineage() async throws {
        let request = try Fixture.request()
        let callID = "roll-1"
        let expected = TurnEngine.deterministicRollID(
            requestID: request.requestID,
            callID: callID
        )
        let wrong = UUID(uuidString: "99999999-9999-4999-8999-999999999999")!
        let provider = ScriptedProvider(events: [
            .toolCallStarted(callID: callID, toolName: "requestRoll"),
            .toolCallCompleted(
                callID: callID,
                toolName: "requestRoll",
                arguments: try ProviderToolArguments(
                    values: [
                        "expression": .string("1d20+4"),
                        "prompt": .string("Test the bell")
                    ]
                )
            ),
            .finished(.completed(
                Fixture.envelope(
                    requestID: request.requestID,
                    proposedEvents: [
                        .rollRequest(
                            rollID: wrong,
                            expression: "1d20+4",
                            prompt: "Test the bell"
                        )
                    ]
                )
            ))
        ])
        let engine = TurnEngine(
            provider: provider,
            store: RecordingCampaignStore(),
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        )

        let execution = await engine.run(request)

        #expect(
            execution.result
                == .failed(
                    .invalidEnvelope(
                        .rollLineageMismatch(
                            index: 0,
                            expected: expected,
                            actual: wrong
                        )
                    )
                )
        )
    }

    @Test
    func finalRollMustMatchTheCompleteRequestRollTuple() async throws {
        let request = try Fixture.request()
        let callID = "roll-1"
        let expected = TurnEngine.deterministicRollID(
            requestID: request.requestID,
            callID: callID
        )
        let provider = ScriptedProvider(events: [
            .toolCallStarted(callID: callID, toolName: "requestRoll"),
            .toolCallCompleted(
                callID: callID,
                toolName: "requestRoll",
                arguments: try ProviderToolArguments(
                    values: [
                        "expression": .string("1d20+4"),
                        "prompt": .string("Test the bell")
                    ]
                )
            ),
            .finished(.completed(
                Fixture.envelope(
                    requestID: request.requestID,
                    proposedEvents: [
                        .rollRequest(
                            rollID: expected,
                            expression: "1d20+6",
                            prompt: "Test the bell"
                        )
                    ]
                )
            ))
        ])
        let engine = TurnEngine(
            provider: provider,
            store: RecordingCampaignStore(),
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        )

        let execution = await engine.run(request)

        #expect(
            execution.result
                == .failed(
                    .invalidEnvelope(
                        .rollLineageMismatch(
                            index: 0,
                            expected: expected,
                            actual: expected
                        )
                    )
                )
        )
    }

    @Test
    func campaignMismatchUsesOwnershipError() async throws {
        let request = try Fixture.request()
        let mismatchedRequest = TurnRequest(
            requestID: request.requestID,
            campaignID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            expectedSequence: request.expectedSequence,
            action: request.action,
            context: request.context
        )
        let execution = await TurnEngine(
            provider: ScriptedProvider(events: []),
            store: RecordingCampaignStore(),
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        ).run(mismatchedRequest)

        #expect(execution.result == .failed(.campaignOwnershipMismatch))
        #expect(execution.errorMessage == "The turn request belonged to a different campaign.")
    }

    @Test
    func disconnectBeforeFinalIsRetryableWithSameRequestID() async throws {
        let request = try Fixture.request()
        let provider = ScriptedProvider(events: [.textDelta("partial")], error: ProviderError.connectivity)
        let store = RecordingCampaignStore()
        let engine = TurnEngine(
            provider: provider,
            store: store,
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        )

        let first = await engine.run(request)
        #expect(first.result == .failed(.provider(.connectivity)))
        #expect(await store.appendCount == 0)

        await provider.replace(events: [.finished(.completed(Fixture.envelope(requestID: request.requestID)))])
        let retry = await engine.run(request)
        #expect(retry.result == .committed)
        #expect(await store.appendCount == 1)
    }

    @Test
    func cleanEOFBeforeFinalRemainsDistinctFromMalformedProviderResponse() async throws {
        let request = try Fixture.request()
        let provider = ScriptedProvider(events: [.textDelta("partial")])
        let engine = TurnEngine(
            provider: provider,
            store: RecordingCampaignStore(),
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        )

        let execution = await engine.run(request)

        #expect(execution.result == .failed(.streamEndedBeforeFinal))
    }

    @Test
    func malformedProviderResponseIsNotReportedAsCleanEOF() async throws {
        let request = try Fixture.request()
        let provider = ScriptedProvider(
            events: [.textDelta("partial")],
            error: .malformedResponse
        )
        let engine = TurnEngine(
            provider: provider,
            store: RecordingCampaignStore(),
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        )

        let execution = await engine.run(request)

        #expect(execution.result == .failed(.provider(.malformedResponse)))
        #expect(
            execution.errorMessage
                == ProviderError.malformedResponse.errorDescription
        )
    }

    @Test
    func cancellationPersistsOnlyTruthfulCancellationBatch() async throws {
        let request = try Fixture.request()
        let provider = ScriptedProvider(events: [.textDelta("partial")], holdsOpen: true)
        let store = RecordingCampaignStore()
        let engine = TurnEngine(
            provider: provider,
            store: store,
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        )
        let task = Task { await engine.run(request) }
        await provider.waitUntilStarted()
        await engine.cancel(requestID: request.requestID)

        let execution = await task.value
        #expect(execution.result == .cancelled)
        #expect(await store.appendCount == 1)
        let batch = try #require(await store.batches.first)
        #expect(batch.count == 2)
        #expect(batch.contains { if case .turnCancelled = $0.payload { return true }; return false })
        #expect(batch.contains { if case .gmMessageCommitted = $0.payload { return true }; return false } == false)
    }

    @Test
    func cancellationDuringStreamSetupCancelsReturnedStreamBeforeConsumption() async throws {
        let request = try Fixture.request()
        let presentedEnvelope = VersionedTurnEnvelope(
            envelope: Fixture.envelope(requestID: request.requestID)
        )
        let provider = ScriptedProvider(
            events: [.finished(.completed(Fixture.envelope(requestID: request.requestID)))],
            holdsOpen: true,
            holdsBeforeReturn: true
        )
        let store = RecordingCampaignStore()
        let engine = TurnEngine(
            provider: provider,
            store: store,
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        )

        let task = Task { await engine.run(request) }
        await provider.waitUntilStreamReturnBlocked()

        let cancellation = await engine.cancel(requestID: request.requestID)
        #expect(cancellation.result == .failed(.cancelled))

        await provider.releaseStreamReturn()
        await provider.waitUntilStreamReturned()
        await provider.finishReturnedStream()

        let execution = await task.value
        #expect(execution.result == .cancelled)
        #expect(execution.presentation.contains(.completed(presentedEnvelope)) == false)
        #expect(await provider.cancellationCount(for: request.requestID) == 2)
        #expect(await store.appendCount == 1)
        let batch = try #require(await store.batches.first)
        #expect(batch.contains { if case .turnCancelled = $0.payload { return true }; return false })
        #expect(batch.contains { if case .gmMessageCommitted = $0.payload { return true }; return false } == false)
    }

    @Test
    func sequenceConflictReloadsAndSurfacesStableMessageWithoutRetryingAppend() async throws {
        let request = try Fixture.request()
        let provider = ScriptedProvider(events: [
            .finished(.completed(Fixture.envelope(requestID: request.requestID)))
        ])
        let store = RecordingCampaignStore(appendError: .expectedSequenceConflict(expected: 4, actual: 5))
        let engine = TurnEngine(
            provider: provider,
            store: store,
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        )

        let execution = await engine.run(request)

        #expect(execution.result == .failed(.sequenceConflict))
        #expect(execution.errorMessage == "Campaign changed; review before retrying")
        #expect(await store.appendCount == 1)
        #expect(await store.reloadCount == 2)
    }

    @Test
    func sequenceConflictReloadFailureIsNotReportedAsAConflict() async throws {
        let request = try Fixture.request()
        let provider = ScriptedProvider(events: [
            .finished(.completed(Fixture.envelope(requestID: request.requestID)))
        ])
        let store = RecordingCampaignStore(
            appendError: .expectedSequenceConflict(expected: 4, actual: 5),
            reloadFailure: .invalidStoredPayload(eventID: UUID())
        )
        let engine = TurnEngine(
            provider: provider,
            store: store,
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        )

        let execution = await engine.run(request)

        #expect(execution.result == .failed(.persistenceFailure))
        #expect(await store.appendCount == 1)
        #expect(await store.reloadCount == 2)
    }

    @Test
    func sequenceConflictReloadRejectsNoncontiguousStoredPages() async throws {
        let request = try Fixture.request()
        let corruptEvent = CampaignEvent(
            id: UUID(),
            campaignID: request.campaignID,
            sequence: 2,
            requestID: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_726_100_000),
            schemaVersion: 1,
            payload: .sceneChanged(
                SceneChangedPayload(sceneID: "corrupt", title: "Corrupt")
            )
        )
        let provider = ScriptedProvider(events: [
            .finished(.completed(Fixture.envelope(requestID: request.requestID)))
        ])
        let store = RecordingCampaignStore(
            appendError: .expectedSequenceConflict(expected: 4, actual: 5),
            conflictReloadEvents: [corruptEvent]
        )
        let engine = TurnEngine(
            provider: provider,
            store: store,
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        )

        let execution = await engine.run(request)

        #expect(execution.result == .failed(.persistenceFailure))
        #expect(await store.appendCount == 1)
        #expect(await store.reloadCount == 2)
    }

    @Test
    func sequenceConflictReloadRejectsReducerDiagnostics() async throws {
        let request = try Fixture.request()
        let corruptEvent = CampaignEvent(
            id: UUID(),
            campaignID: request.campaignID,
            sequence: 1,
            requestID: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_726_100_000),
            schemaVersion: 99,
            payload: .sceneChanged(
                SceneChangedPayload(sceneID: "unsupported", title: "Unsupported")
            )
        )
        let provider = ScriptedProvider(events: [
            .finished(.completed(Fixture.envelope(requestID: request.requestID)))
        ])
        let store = RecordingCampaignStore(
            appendError: .expectedSequenceConflict(expected: 4, actual: 5),
            conflictReloadEvents: [corruptEvent]
        )
        let engine = TurnEngine(
            provider: provider,
            store: store,
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        )

        let execution = await engine.run(request)

        #expect(execution.result == .failed(.persistenceFailure))
        #expect(await store.appendCount == 1)
        #expect(await store.reloadCount == 2)
    }

    @Test
    func duplicateRunAfterCanonicalCommitIsIdempotentAtEngineBoundary() async throws {
        let request = try Fixture.request()
        let provider = ScriptedProvider(events: [
            .finished(.completed(Fixture.envelope(requestID: request.requestID)))
        ])
        let store = RecordingCampaignStore()
        let engine = TurnEngine(
            provider: provider,
            store: store,
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        )

        _ = await engine.run(request)
        let duplicate = await engine.run(request)

        #expect(duplicate.result == .failed(.canonicalFinalAlreadyExists))
        #expect(await provider.streamCallCount == 1)
        #expect(await store.appendCount == 1)
    }

    @Test
    func recreatedEngineReturnsDurableCanonicalResultWithoutReappending() async throws {
        let request = try Fixture.request(expectedSequence: 0)
        let store = DurableCampaignStore()
        let firstProvider = ScriptedProvider(events: [
            .finished(.completed(Fixture.envelope(requestID: request.requestID)))
        ])
        let firstEngine = TurnEngine(
            provider: firstProvider,
            store: store,
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        )
        #expect((await firstEngine.run(request)).result == .committed)

        let retryProvider = ScriptedProvider(events: [
            .finished(.completed(Fixture.envelope(requestID: request.requestID)))
        ])
        let recreatedEngine = TurnEngine(
            provider: retryProvider,
            store: store,
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        )
        let retry = await recreatedEngine.run(request)

        #expect(retry.result == .committed)
        #expect(await retryProvider.streamCallCount == 0)
        #expect(await store.appendCount == 1)
        #expect(retry.appendedEvents.contains { if case .gmMessageCommitted = $0.payload { return true }; return false })
    }

    @Test
    func cancellationDuringAppendLeavesCanonicalCommitTruthful() async throws {
        let request = try Fixture.request()
        let store = BarrierCampaignStore()
        let provider = ScriptedProvider(events: [
            .finished(.completed(Fixture.envelope(requestID: request.requestID)))
        ])
        let engine = TurnEngine(
            provider: provider,
            store: store,
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        )
        let task = Task { await engine.run(request) }
        await store.waitUntilAppendStarted()

        let inFlightCancel = await engine.cancel(requestID: request.requestID)
        #expect(inFlightCancel.result == .failed(.alreadyRunning))
        await store.releaseAppend()

        let execution = await task.value
        #expect(execution.result == .committed)
        let subsequentCancel = await engine.cancel(requestID: request.requestID)
        #expect(subsequentCancel.result == .failed(.canonicalFinalAlreadyExists))
        #expect(await store.appendCount == 1)
    }

    @Test
    func presentationObserverReceivesCompletionBeforeDurableAppendFinishes() async throws {
        let request = try Fixture.request()
        let provider = ScriptedProvider(events: [
            .textDelta("The bell answers."),
            .finished(.completed(Fixture.envelope(requestID: request.requestID)))
        ])
        let store = BarrierCampaignStore()
        let engine = TurnEngine(
            provider: provider,
            store: store,
            validationContext: Fixture.validationContext(campaignID: request.campaignID)
        )
        let (presentationStream, presentationContinuation) =
            AsyncStream<TurnPresentationEvent>.makeStream()

        let task = Task {
            await engine.run(request) { event in
                presentationContinuation.yield(event)
                if case .completed = event {
                    presentationContinuation.finish()
                }
            }
        }

        var observed: [TurnPresentationEvent] = []
        for await event in presentationStream {
            observed.append(event)
        }

        #expect(observed.contains(.prose("The bell answers.")))
        #expect(observed.contains(.completed(
            VersionedTurnEnvelope(envelope: Fixture.envelope(requestID: request.requestID))
        )))
        await store.waitUntilAppendStarted()
        #expect(await store.appendCount == 0)

        await store.releaseAppend()
        let execution = await task.value
        #expect(execution.result == .committed)
        #expect(observed == execution.presentation)
        #expect(await store.appendCount == 1)
    }

    @Test
    func builderPersistsEveryAdvertisedMutationBeforeTerminalMessage() throws {
        let request = try Fixture.request()
        let rollID = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000777"))
        let envelope = Fixture.envelope(
            requestID: request.requestID,
            proposedEvents: [
                .clockUpdate(clockRecordID: "clock-journey", current: 2, maximum: 6),
                .assetAttachment(assetID: "asset-map", targetRecordID: "scene-quay", fieldID: "mapAsset"),
                .rollRequest(rollID: rollID, expression: "1d20+2", prompt: "Cross the quay")
            ]
        )

        let batch = try TurnEventBuilder(idGenerator: Fixture.idGenerator()).build(
            request: request,
            envelope: VersionedTurnEnvelope(envelope: envelope)
        )

        #expect(batch.dropFirst().dropLast().map { $0.payload.kind } == [
            .clockUpdated, .assetAttached, .rollRequested
        ])
        guard case .clockUpdated(let clock) = batch[1].payload,
              case .assetAttached(let asset) = batch[2].payload,
              let last = batch.last,
              case .gmMessageCommitted = last.payload else {
            Issue.record("Expected canonical mutation events before the terminal message")
            return
        }
        #expect(clock.current == 2)
        #expect(clock.maximum == 6)
        #expect(asset.assetID == "asset-map")
    }

    @Test
    func voiceSuggestionBuildsItsOwnCanonicalEvent() throws {
        let request = try Fixture.request()
        let envelope = Fixture.envelope(
            requestID: request.requestID,
            proposedEvents: [
                .voiceSuggestion(
                    characterRecordID: "character-guide",
                    styleDescription: "Warm and cautious"
                )
            ]
        )
        let batch = try TurnEventBuilder(
            idGenerator: Fixture.idGenerator()
        ).build(
            request: request,
            envelope: VersionedTurnEnvelope(envelope: envelope)
        )

        #expect(batch.contains { event in
            if case .voiceSuggestionProposed(let payload) = event.payload {
                return payload.characterID == "character-guide"
                    && payload.styleDescription == "Warm and cautious"
            }
            return false
        })
        #expect(batch.contains { if case .voiceAssignmentChanged = $0.payload { return true }; return false } == false)
    }
}

private actor ScriptedProvider: AIProvider {
    nonisolated let id: ProviderID = .openAI
    private var scriptedEvents: [ProviderStreamEvent]
    private var scriptedTurns: [[ProviderStreamEvent]]
    private var scriptedError: ProviderError?
    private let holdsOpen: Bool
    private let holdsBeforeReturn: Bool
    private var continuation: AsyncThrowingStream<ProviderStreamEvent, Error>.Continuation?
    private var streamReturnContinuation: CheckedContinuation<Void, Never>?
    private(set) var streamCallCount = 0
    private(set) var requests: [TurnRequest] = []
    private var started = false
    private var streamReturnBlocked = false
    private var streamReturned = false
    private var cancelCallCount = 0

    init(
        events: [ProviderStreamEvent],
        error: ProviderError? = nil,
        holdsOpen: Bool = false,
        holdsBeforeReturn: Bool = false
    ) {
        scriptedEvents = events
        scriptedTurns = [events]
        scriptedError = error
        self.holdsOpen = holdsOpen
        self.holdsBeforeReturn = holdsBeforeReturn
    }

    init(turns: [[ProviderStreamEvent]]) {
        scriptedEvents = turns.first ?? []
        scriptedTurns = turns
        scriptedError = nil
        holdsOpen = false
        holdsBeforeReturn = false
    }

    func models() async throws -> [ProviderModel] { [] }

    func streamTurn(_ request: TurnRequest) async throws -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        streamCallCount += 1
        requests.append(request)
        if holdsBeforeReturn {
            await withCheckedContinuation { continuation in
                streamReturnBlocked = true
                streamReturnContinuation = continuation
            }
        }
        let events = scriptedTurns.isEmpty ? scriptedEvents : scriptedTurns.removeFirst()
        started = true
        let pair = AsyncThrowingStream<ProviderStreamEvent, Error>.makeStream()
        continuation = pair.continuation
        for event in events { pair.continuation.yield(event) }
        if let scriptedError { pair.continuation.finish(throwing: scriptedError) }
        else if holdsOpen == false { pair.continuation.finish() }
        streamReturned = true
        return pair.stream
    }

    func cancel(requestID: UUID) async {
        cancelCallCount += 1
        continuation?.finish(throwing: ProviderError.cancelled)
        continuation = nil
    }

    func replace(events: [ProviderStreamEvent]) {
        scriptedEvents = events
        scriptedTurns = [events]
        scriptedError = nil
    }

    func request(at index: Int) -> TurnRequest? {
        guard requests.indices.contains(index) else { return nil }
        return requests[index]
    }

    func waitUntilStarted() async {
        while started == false { await Task.yield() }
    }

    func waitUntilStreamReturnBlocked() async {
        while streamReturnBlocked == false { await Task.yield() }
    }

    func releaseStreamReturn() {
        streamReturnContinuation?.resume()
        streamReturnContinuation = nil
    }

    func waitUntilStreamReturned() async {
        while streamReturned == false { await Task.yield() }
    }

    func finishReturnedStream() {
        continuation?.finish()
        continuation = nil
    }

    func cancellationCount(for _: UUID) -> Int {
        cancelCallCount
    }
}

private actor RecordingCampaignStore: CampaignStore {
    private(set) var batches: [[CampaignEvent]] = []
    private(set) var appendCount = 0
    private(set) var reloadCount = 0
    private let appendError: CampaignStoreError?
    private let reloadFailure: CampaignStoreError?
    private let conflictReloadEvents: [CampaignEvent]

    init(
        appendError: CampaignStoreError? = nil,
        reloadFailure: CampaignStoreError? = nil,
        conflictReloadEvents: [CampaignEvent] = []
    ) {
        self.appendError = appendError
        self.reloadFailure = reloadFailure
        self.conflictReloadEvents = conflictReloadEvents
    }

    func campaigns() async throws -> [CampaignSummary] { [] }

    func append(batch: [CampaignEvent], assets: [ImportedAsset], expectedSequence: Int64) async throws -> [CampaignEvent] {
        appendCount += 1
        batches.append(batch)
        if let appendError { throw appendError }
        return batch.enumerated().map { index, event in
            CampaignEvent(id: event.id, campaignID: event.campaignID, sequence: expectedSequence + Int64(index) + 1, requestID: event.requestID, timestamp: event.timestamp, schemaVersion: event.schemaVersion, payload: event.payload)
        }
    }

    func events(for campaignID: UUID, after sequence: Int64, limit: Int) async throws -> [CampaignEvent] {
        if reloadCount == 2 {
            if let reloadFailure { throw reloadFailure }
            if conflictReloadEvents.isEmpty == false {
                return conflictReloadEvents
            }
        }
        return []
    }
    func latestSequence(for campaignID: UUID) async throws -> Int64 {
        reloadCount += 1
        guard reloadCount == 2 else { return 0 }
        if reloadFailure != nil { return 1 }
        return conflictReloadEvents.map(\.sequence).max() ?? 0
    }
    func importedAssets(for campaignID: UUID) async throws -> [ImportedAsset] { [] }
    func saveProjectionCheckpoint(_ checkpoint: ProjectionCheckpoint) async throws {}
    func latestProjectionCheckpoint(for campaignID: UUID, reducerSchemaVersion: Int) async throws -> ProjectionCheckpoint? { nil }
    func restoreCampaign(events: [CampaignEvent], assets: [ImportedAsset]) async throws {}
    func deleteCampaign(_ campaignID: UUID) async throws {}
}

private actor LookupBarrierCampaignStore: CampaignStore {
    private var storedEvents: [CampaignEvent] = []
    private(set) var appendCount = 0
    private var firstLookupStarted = false
    private var firstLookupContinuation: CheckedContinuation<Void, Never>?

    func campaigns() async throws -> [CampaignSummary] { [] }

    func append(
        batch: [CampaignEvent],
        assets: [ImportedAsset],
        expectedSequence: Int64
    ) async throws -> [CampaignEvent] {
        appendCount += 1
        let appended = batch.enumerated().map { index, event in
            CampaignEvent(
                id: event.id,
                campaignID: event.campaignID,
                sequence: expectedSequence + Int64(index) + 1,
                requestID: event.requestID,
                timestamp: event.timestamp,
                schemaVersion: event.schemaVersion,
                payload: event.payload
            )
        }
        storedEvents.append(contentsOf: appended)
        return appended
    }

    func events(
        for campaignID: UUID,
        after sequence: Int64,
        limit: Int
    ) async throws -> [CampaignEvent] {
        storedEvents
            .filter { $0.campaignID == campaignID && $0.sequence > sequence }
            .prefix(limit)
            .map { $0 }
    }

    func latestSequence(for campaignID: UUID) async throws -> Int64 {
        if firstLookupStarted == false {
            firstLookupStarted = true
            await withCheckedContinuation { continuation in
                firstLookupContinuation = continuation
            }
        }
        return storedEvents
            .filter { $0.campaignID == campaignID }
            .map(\.sequence)
            .max() ?? 0
    }

    func waitUntilFirstLookupStarted() async {
        while firstLookupStarted == false { await Task.yield() }
    }

    func releaseFirstLookup() {
        firstLookupContinuation?.resume()
        firstLookupContinuation = nil
    }

    func importedAssets(for campaignID: UUID) async throws -> [ImportedAsset] { [] }
    func saveProjectionCheckpoint(_ checkpoint: ProjectionCheckpoint) async throws {}
    func latestProjectionCheckpoint(
        for campaignID: UUID,
        reducerSchemaVersion: Int
    ) async throws -> ProjectionCheckpoint? { nil }
    func restoreCampaign(events: [CampaignEvent], assets: [ImportedAsset]) async throws {}
    func deleteCampaign(_ campaignID: UUID) async throws { storedEvents.removeAll() }
}

private actor DurableCampaignStore: CampaignStore {
    private var storedEvents: [CampaignEvent] = []
    private(set) var appendCount = 0

    func campaigns() async throws -> [CampaignSummary] {
        guard let campaignID = storedEvents.first?.campaignID else { return [] }
        return [
            CampaignSummary(
                campaignID: campaignID,
                title: "Fixture",
                projectID: "fixture",
                importedAt: Date(timeIntervalSince1970: 1_726_100_000)
            )
        ]
    }

    func append(batch: [CampaignEvent], assets: [ImportedAsset], expectedSequence: Int64) async throws -> [CampaignEvent] {
        guard let first = batch.first else { return [] }
        if storedEvents.contains(where: { $0.requestID == first.requestID }) {
            throw CampaignStoreError.duplicateRequestID(first.requestID)
        }
        let latest = storedEvents.map(\.sequence).max() ?? 0
        guard latest == expectedSequence else {
            throw CampaignStoreError.expectedSequenceConflict(expected: expectedSequence, actual: latest)
        }
        appendCount += 1
        let appended = batch.enumerated().map { index, event in
            CampaignEvent(
                id: event.id,
                campaignID: event.campaignID,
                sequence: latest + Int64(index) + 1,
                requestID: event.requestID,
                timestamp: event.timestamp,
                schemaVersion: event.schemaVersion,
                payload: event.payload
            )
        }
        storedEvents.append(contentsOf: appended)
        return appended
    }

    func events(for campaignID: UUID, after sequence: Int64, limit: Int) async throws -> [CampaignEvent] {
        storedEvents
            .filter { $0.campaignID == campaignID && $0.sequence > sequence }
            .sorted { $0.sequence < $1.sequence }
            .prefix(limit)
            .map { $0 }
    }

    func latestSequence(for campaignID: UUID) async throws -> Int64 {
        storedEvents.filter { $0.campaignID == campaignID }.map(\.sequence).max() ?? 0
    }

    func importedAssets(for campaignID: UUID) async throws -> [ImportedAsset] { [] }
    func saveProjectionCheckpoint(_ checkpoint: ProjectionCheckpoint) async throws {}
    func latestProjectionCheckpoint(for campaignID: UUID, reducerSchemaVersion: Int) async throws -> ProjectionCheckpoint? { nil }
    func restoreCampaign(events: [CampaignEvent], assets: [ImportedAsset]) async throws {}
    func deleteCampaign(_ campaignID: UUID) async throws { storedEvents.removeAll() }
}

private actor BarrierCampaignStore: CampaignStore {
    private var appendStarted = false
    private var released = false
    private(set) var appendCount = 0

    func campaigns() async throws -> [CampaignSummary] { [] }

    func append(batch: [CampaignEvent], assets: [ImportedAsset], expectedSequence: Int64) async throws -> [CampaignEvent] {
        appendStarted = true
        while released == false { await Task.yield() }
        appendCount += 1
        return batch.enumerated().map { index, event in
            CampaignEvent(id: event.id, campaignID: event.campaignID, sequence: expectedSequence + Int64(index) + 1, requestID: event.requestID, timestamp: event.timestamp, schemaVersion: event.schemaVersion, payload: event.payload)
        }
    }

    func waitUntilAppendStarted() async {
        while appendStarted == false { await Task.yield() }
    }

    func releaseAppend() { released = true }
    func events(for campaignID: UUID, after sequence: Int64, limit: Int) async throws -> [CampaignEvent] { [] }
    func latestSequence(for campaignID: UUID) async throws -> Int64 { 0 }
    func importedAssets(for campaignID: UUID) async throws -> [ImportedAsset] { [] }
    func saveProjectionCheckpoint(_ checkpoint: ProjectionCheckpoint) async throws {}
    func latestProjectionCheckpoint(for campaignID: UUID, reducerSchemaVersion: Int) async throws -> ProjectionCheckpoint? { nil }
    func restoreCampaign(events: [CampaignEvent], assets: [ImportedAsset]) async throws {}
    func deleteCampaign(_ campaignID: UUID) async throws {}
}

private enum Fixture {
    static let campaignID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    static let requestID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    static let storyBlock = StoryBlock(id: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!, kind: .narration, text: "The rain needles the glass.")
    static let beat = VisualNovelBeat(id: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!, kind: .narration, title: nil, subtitle: nil, speaker: nil, mood: nil, text: "The rain needles the glass.")

    static func request(expectedSequence: Int64 = 7) throws -> TurnRequest {
        try TurnRequest(
            requestID: requestID,
            campaignID: campaignID,
            expectedSequence: expectedSequence,
            action: PlayerAction(text: "Search the bell tower."),
            assembly: assembly()
        )
    }

    static func constrainedRequest() throws -> TurnRequest {
        let model = try ProviderModel(
            providerID: .openAI,
            id: "constrained-fixture-model",
            displayName: "Constrained Fixture Model",
            contextWindowTokens: 56,
            maximumOutputTokens: 4,
            supportsTools: true,
            supportsStructuredOutput: true
        )
        let baseBudget = ContextBudget(
            model: model,
            toolTokenReserve: 0,
            safetyMarginTokens: 0
        )
        let sections = [
            ContextSection(
                kind: .systemContract,
                items: [
                    ContextSection.Item(
                        id: "system-contract",
                        text: "Return a bounded turn envelope."
                    )
                ]
            )
        ]
        let budget = baseBudget.recording(
            estimatedInputTokens: ContextBudget.estimateTokens(for: sections)
        )
        let metadata = ContextAssemblyMetadata(
            omittedSections: [],
            omittedItems: [],
            wasTruncated: false
        )
        let hash = TurnContextAssembler.canonicalHash(
            sections: sections,
            budget: budget,
            metadata: metadata
        )
        return TurnRequest(
            requestID: requestID,
            campaignID: campaignID,
            expectedSequence: 7,
            action: PlayerAction(text: "Search the bell tower."),
            assembly: TurnContextAssembly(
                context: TurnContext(contextHash: hash, sections: sections),
                budget: budget,
                metadata: metadata
            )
        )
    }

    static func assembly() throws -> TurnContextAssembly {
        let model = try ProviderModel(
            providerID: .openAI,
            id: "fixture-model",
            displayName: "Fixture Model",
            contextWindowTokens: 20_000,
            maximumOutputTokens: 1_000,
            supportsTools: true,
            supportsStructuredOutput: true
        )
        let baseBudget = ContextBudget(model: model)
        let metadata = ContextAssemblyMetadata(
            omittedSections: [.worldRecords],
            omittedItems: [
                ContextOmission(
                    kind: .worldRecords,
                    itemID: "omitted-record",
                    reason: .budgetExceeded
                )
            ],
            wasTruncated: true
        )
        let sections = [
            ContextSection(
                kind: .systemContract,
                items: [
                    ContextSection.Item(
                        id: "system-contract",
                        name: "GM contract",
                        text: "Return a bounded turn envelope."
                    )
                ]
            )
        ]
        let estimatedInputTokens = sections.reduce(0) { total, section in
            total + ContextBudget.sectionOverheadTokens
                + section.items.reduce(0) {
                    $0 + ContextBudget.estimateTokens(for: $1)
                }
        }
        let budget = baseBudget.recording(
            estimatedInputTokens: estimatedInputTokens
        )
        let hash = TurnContextAssembler.canonicalHash(
            sections: sections,
            budget: budget,
            metadata: metadata
        )
        return TurnContextAssembly(
            context: TurnContext(contextHash: hash, sections: sections),
            budget: budget,
            metadata: metadata
        )
    }

    static func envelope(
        requestID: UUID,
        proposedEvents: [ProposedCampaignEvent] = []
    ) -> TurnEnvelope {
        TurnEnvelope(requestID: requestID, narration: [storyBlock], beats: [beat], proposedEvents: proposedEvents, pendingDecision: nil, voiceSegments: [], usage: nil)
    }

    static func validationContext(campaignID: UUID) -> GMToolValidationContext {
        GMToolValidationContext(campaignID: campaignID, project: NormalizedProject(cdfVersion: 2, importScope: .projectWorldContent, id: "project", title: "Test", summary: nil, system: nil, rootFolderID: "root", currentSceneRecordID: nil, playerCharacterRecordID: nil, projectExtensionPayload: [:], schemas: [], content: NormalizedContent(folders: [], records: [], relationships: [], assets: [], maps: [], characters: [], extensionPayload: [:]), manifest: NormalizedManifest(files: [], recordIDs: []), extensionPayload: [:]), projection: CampaignProjection(campaignID: campaignID))
    }

    static func idGenerator() -> TurnEventBuilder.IDGenerator {
        { UUID() }
    }
}
