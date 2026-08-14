import CryptoKit
import Foundation

public enum TurnEngineError: Error, Equatable, Sendable {
    case campaignOwnershipMismatch
    case requestIDMismatch
    case missingContextAssembly
    case contextBudgetExceeded(estimatedInputTokens: Int, inputTokenBudget: Int)
    case invalidTool(ToolValidationError)
    case invalidEnvelope(TurnEnvelopeValidationError)
    case toolSubturnLimitExceeded
    case cancelled
    case streamEndedBeforeFinal
    case duplicateCompletion
    case canonicalFinalAlreadyExists
    case canonicalFailure(
        category: TurnFailureCategory,
        message: String,
        isRetryable: Bool
    )
    case alreadyRunning
    case sequenceConflict
    case provider(ProviderError)
    case persistenceFailure

    public var userMessage: String {
        switch self {
        case .campaignOwnershipMismatch:
            "The turn request belonged to a different campaign."
        case .requestIDMismatch:
            "The turn response did not belong to this request."
        case .missingContextAssembly:
            "The turn context cannot continue because its canonical assembly is missing."
        case .contextBudgetExceeded:
            "The turn context exceeded the model input budget."
        case .invalidTool:
            "The GM proposed an invalid world action."
        case .invalidEnvelope:
            "The GM returned an invalid turn response."
        case .toolSubturnLimitExceeded:
            "The GM requested too many tool steps for this turn."
        case .cancelled:
            "Turn cancelled."
        case .streamEndedBeforeFinal:
            "The turn ended before the GM finished."
        case .duplicateCompletion:
            "The GM sent more than one completion for this turn."
        case .canonicalFinalAlreadyExists:
            "This turn has already been completed."
        case .canonicalFailure(_, let message, _):
            message
        case .alreadyRunning:
            "This turn is already running."
        case .sequenceConflict:
            "Campaign changed; review before retrying"
        case .provider(let error):
            error.errorDescription ?? "The provider could not complete the turn."
        case .persistenceFailure:
            "The campaign could not save this turn."
        }
    }
}

public enum TurnPresentationEvent: Sendable, Equatable {
    case status(CampaignGenerationPhase)
    case prose(String)
    case toolStarted(callID: String, toolName: String)
    case toolResult(
        callID: String,
        toolName: String,
        sanitizedStatus: String
    )
    case completed(VersionedTurnEnvelope)
    case failure(TurnEngineError)

    public static func == (
        lhs: TurnPresentationEvent,
        rhs: TurnPresentationEvent
    ) -> Bool {
        switch (lhs, rhs) {
        case (.status(let left), .status(let right)):
            return left.rawValue == right.rawValue
        case (.prose(let left), .prose(let right)):
            return left == right
        case (
            .toolStarted(let leftID, let leftName),
            .toolStarted(let rightID, let rightName)
        ):
            return leftID == rightID && leftName == rightName
        case (
            .toolResult(let leftID, let leftName, let leftStatus),
            .toolResult(let rightID, let rightName, let rightStatus)
        ):
            return leftID == rightID
                && leftName == rightName
                && leftStatus == rightStatus
        case (.completed(let left), .completed(let right)):
            return left == right
        case (.failure(let left), .failure(let right)):
            return left == right
        default:
            return false
        }
    }
}

public typealias TurnPresentationObserver =
    @Sendable (TurnPresentationEvent) -> Void

public enum TurnEngineResult: Equatable, Sendable {
    case committed
    case cancelled
    case failed(TurnEngineError)
}

public struct TurnEngineExecution: Equatable, Sendable {
    public let result: TurnEngineResult
    public let presentation: [TurnPresentationEvent]
    public let appendedEvents: [CampaignEvent]

    public init(
        result: TurnEngineResult,
        presentation: [TurnPresentationEvent],
        appendedEvents: [CampaignEvent] = []
    ) {
        self.result = result
        self.presentation = presentation
        self.appendedEvents = appendedEvents
    }

    public var errorMessage: String? {
        guard case .failed(let error) = result else { return nil }
        return error.userMessage
    }
}

/// Orchestrates one provider stream and one atomic campaign append.
public actor TurnEngine {
    private enum RunState: Sendable, Equatable {
        case active
        case committing
        case canonicalFinal
        case cancelled
    }

    private struct StreamState: Sendable {
        var startedTools: [String: String] = [:]
        var completedTools = Set<String>()
        var validatedToolResults = Set<String>()
        var startedToolsBySubturn: [Int: Set<String>] = [:]
        var argumentBytes: [String: Int] = [:]
        var proseBytes = 0
        var finalEnvelope: TurnEnvelope?
        var requiresToolResults = false
        var toolResultItems: [ContextSection.Item] = []
        var expectedRolls: [TurnRollLineage] = []
    }

    private let provider: any AIProvider
    private let store: any CampaignStore
    private var validationContext: GMToolValidationContext
    private var validator: TurnEnvelopeValidator
    private let builder: TurnEventBuilder
    private var states: [UUID: RunState] = [:]
    private var requests: [UUID: TurnRequest] = [:]
    private var cancellationRequests = Set<UUID>()
    private var externallyCommittedRequestIDs = Set<UUID>()

    public init(
        provider: any AIProvider,
        store: any CampaignStore,
        validationContext: GMToolValidationContext,
        eventIDGenerator: @escaping TurnEventBuilder.IDGenerator = { UUID() }
    ) {
        self.provider = provider
        self.store = store
        self.validationContext = validationContext
        validator = TurnEnvelopeValidator(context: validationContext)
        builder = TurnEventBuilder(idGenerator: eventIDGenerator)
    }

    /// `run`, `execute`, and `finish` intentionally share one idempotent
    /// boundary so callers cannot create a second canonical completion.
    public func run(_ request: TurnRequest) async -> TurnEngineExecution {
        await perform(request, observer: nil)
    }

    /// Delivers sanitized presentation events as the provider stream advances.
    /// The observer is called before the engine proceeds to the next step,
    /// including before the durable append for a completed envelope.
    public func run(
        _ request: TurnRequest,
        onPresentation observer: @escaping TurnPresentationObserver
    ) async -> TurnEngineExecution {
        await perform(request, observer: observer)
    }

    public func execute(_ request: TurnRequest) async -> TurnEngineExecution {
        await perform(request, observer: nil)
    }

    public func execute(
        _ request: TurnRequest,
        onPresentation observer: @escaping TurnPresentationObserver
    ) async -> TurnEngineExecution {
        await perform(request, observer: observer)
    }

    public func finish(_ request: TurnRequest) async -> TurnEngineExecution {
        await perform(request, observer: nil)
    }

    public func finish(
        _ request: TurnRequest,
        onPresentation observer: @escaping TurnPresentationObserver
    ) async -> TurnEngineExecution {
        await perform(request, observer: observer)
    }

    @discardableResult
    public func cancel(requestID: UUID) async -> TurnEngineExecution {
        let request = requests[requestID]
        switch states[requestID] {
        case .canonicalFinal, .cancelled:
            return await reconcileCancellation(
                requestID: requestID,
                request: request,
                fallback: failure(
                    .canonicalFinalAlreadyExists,
                    presentation: [.failure(.canonicalFinalAlreadyExists)]
                )
            )
        case .committing:
            return await reconcileCancellation(
                requestID: requestID,
                request: request,
                fallback: failure(
                    .alreadyRunning,
                    presentation: [.failure(.alreadyRunning)]
                )
            )
        case .active:
            cancellationRequests.insert(requestID)
            await provider.cancel(requestID: requestID)
            return await reconcileCancellation(
                requestID: requestID,
                request: request,
                fallback: TurnEngineExecution(
                    result: .failed(.cancelled),
                    presentation: [.failure(.cancelled)]
                )
            )
        case nil:
            // Cancellation is an intent, not a best-effort notification. Keep
            // it until a later run consumes it or durable reconciliation finds
            // the request's terminal event.
            cancellationRequests.insert(requestID)
            return await reconcileCancellation(
                requestID: requestID,
                request: request,
                fallback: failure(.cancelled, presentation: [.failure(.cancelled)])
            )
        }
    }

    private func perform(
        _ request: TurnRequest,
        observer: TurnPresentationObserver?
    ) async -> TurnEngineExecution {
        guard request.campaignID == validationContext.campaignID else {
            return failure(
                .campaignOwnershipMismatch,
                presentation: [.failure(.campaignOwnershipMismatch)],
                observer: observer
            )
        }
        if states[request.requestID] == .canonicalFinal {
            return failure(
                .canonicalFinalAlreadyExists,
                presentation: [.failure(.canonicalFinalAlreadyExists)],
                observer: observer
            )
        }
        if externallyCommittedRequestIDs.contains(request.requestID) {
            return failure(
                .canonicalFinalAlreadyExists,
                presentation: [.failure(.canonicalFinalAlreadyExists)],
                observer: observer
            )
        }
        if states[request.requestID] == .active {
            return failure(
                .alreadyRunning,
                presentation: [.failure(.alreadyRunning)],
                observer: observer
            )
        }
        if states[request.requestID] == .committing {
            return failure(
                .alreadyRunning,
                presentation: [.failure(.alreadyRunning)],
                observer: observer
            )
        }
        if states[request.requestID] == .cancelled {
            return failure(
                .canonicalFinalAlreadyExists,
                presentation: [.failure(.canonicalFinalAlreadyExists)],
                observer: observer
            )
        }

        // Reserve the request synchronously before the first suspension. This
        // makes the actor's request identity gate effective for concurrent
        // callers and lets cancellation race with durable reconciliation.
        states[request.requestID] = .active
        requests[request.requestID] = request

        do {
            if let existing = try await existingTerminalExecution(for: request) {
                return adopt(existing, for: request.requestID)
            }
            if cancellationRequests.contains(request.requestID) {
                return await persistCancellation(
                    request,
                    presentation: [],
                    observer: observer
                )
            }
            try Task.checkCancellation()
        } catch is CancellationError {
            return await persistCancellation(
                request,
                presentation: [],
                observer: observer
            )
        } catch {
            if cancellationRequests.contains(request.requestID) {
                return await persistCancellation(
                    request,
                    presentation: [],
                    observer: observer
                )
            }
            states.removeValue(forKey: request.requestID)
            return failure(
                .persistenceFailure,
                presentation: [.failure(.persistenceFailure)],
                observer: observer
            )
        }

        var presentation: [TurnPresentationEvent] = []
        for phase in [
            CampaignGenerationPhase.queued,
            .readingWorld,
            .planning,
            .writingScene,
            .voicing
        ] {
            recordPresentation(
                .status(phase),
                in: &presentation,
                observer: observer
            )
        }
        var streamState = StreamState()

        do {
            var currentRequest = request
            var stream = try await provider.streamTurn(currentRequest)
            try Task.checkCancellation()
            if let cancellation = await persistCancellationIfRequestedAfterStreamSetup(
                request,
                presentation: presentation,
                observer: observer
            ) {
                return cancellation
            }
            var toolSubturnCount = 0
            var subturnIndex = 0
            while true {
                for try await event in stream {
                    try Task.checkCancellation()
                    try process(
                        event,
                        request: request,
                        subturnIndex: subturnIndex,
                        state: &streamState,
                        presentation: &presentation,
                        observer: observer
                    )
                }
                guard streamState.finalEnvelope == nil,
                      streamState.requiresToolResults else {
                    break
                }
                toolSubturnCount += 1
                guard toolSubturnCount <= 16 else {
                    throw TurnEngineError.toolSubturnLimitExceeded
                }
                streamState.requiresToolResults = false
                subturnIndex = toolSubturnCount
                // The provider contract exposes a tool boundary as a terminal
                // stream event. Providers that support a follow-up subturn
                // receive the same request lineage; tool results remain
                // presentation-only and never enter canonical history.
                currentRequest = try continuationRequest(
                    from: currentRequest,
                    state: streamState
                )
                stream = try await provider.streamTurn(currentRequest)
                try Task.checkCancellation()
                if let cancellation = await persistCancellationIfRequestedAfterStreamSetup(
                    request,
                    presentation: presentation,
                    observer: observer
                ) {
                    return cancellation
                }
            }
            guard let finalEnvelope = streamState.finalEnvelope else {
                throw TurnEngineError.streamEndedBeforeFinal
            }

            let validatedEnvelope: VersionedTurnEnvelope
            do {
                let versionedEnvelope = VersionedTurnEnvelope(
                    envelope: finalEnvelope
                )
                validatedEnvelope = try validator.validate(
                    versionedEnvelope,
                    for: request,
                    expectedRolls: streamState.expectedRolls
                )
            } catch let error as TurnEnvelopeValidationError {
                throw TurnEngineError.invalidEnvelope(error)
            } catch {
                throw TurnEngineError.invalidEnvelope(.unsafeText)
            }
            recordPresentation(
                .completed(validatedEnvelope),
                in: &presentation,
                observer: observer
            )

            let batch: [CampaignEvent]
            do {
                batch = try builder.build(
                    request: request,
                    envelope: validatedEnvelope
                )
            } catch let error as TurnEventBuilderError {
                switch error {
                case .requestIDMismatch:
                    throw TurnEngineError.requestIDMismatch
                case .duplicateEventID:
                    throw TurnEngineError.persistenceFailure
                }
            }

            do {
                guard cancellationRequests.contains(request.requestID) == false else {
                    return await persistCancellation(
                        request,
                        presentation: presentation,
                        observer: observer
                    )
                }
                states[request.requestID] = .committing
                let appended = try await store.append(
                    batch: batch,
                    assets: [],
                    expectedSequence: request.expectedSequence
                )
                states[request.requestID] = .canonicalFinal
                cancellationRequests.remove(request.requestID)
                return TurnEngineExecution(
                    result: .committed,
                    presentation: presentation,
                    appendedEvents: appended
                )
            } catch let error as CampaignStoreError {
                if case .duplicateRequestID = error {
                    do {
                        if let existing = try await existingTerminalExecution(for: request) {
                            return adopt(existing, for: request.requestID)
                        }
                    } catch {
                        states.removeValue(forKey: request.requestID)
                        throw TurnEngineError.persistenceFailure
                    }
                    states.removeValue(forKey: request.requestID)
                    throw TurnEngineError.persistenceFailure
                }
                if case .expectedSequenceConflict = error {
                    do {
                        let loaded = try await reloadCampaign(
                            campaignID: request.campaignID
                        )
                        retain(loaded.projection)
                    } catch {
                        states.removeValue(forKey: request.requestID)
                        throw TurnEngineError.persistenceFailure
                    }
                    states.removeValue(forKey: request.requestID)
                    throw TurnEngineError.sequenceConflict
                }
                throw TurnEngineError.persistenceFailure
            } catch {
                throw TurnEngineError.persistenceFailure
            }
        } catch let error as TurnEngineError {
            if error == .cancelled || cancellationRequests.contains(request.requestID) {
                return await persistCancellation(
                    request,
                    presentation: presentation,
                    observer: observer
                )
            }
            states.removeValue(forKey: request.requestID)
            recordPresentation(
                .failure(error),
                in: &presentation,
                observer: observer
            )
            return TurnEngineExecution(result: .failed(error), presentation: presentation)
        } catch is CancellationError {
            return await persistCancellation(
                request,
                presentation: presentation,
                observer: observer
            )
        } catch let error as ProviderError {
            if error == .cancelled || cancellationRequests.contains(request.requestID) {
                return await persistCancellation(
                    request,
                    presentation: presentation,
                    observer: observer
                )
            }
            states.removeValue(forKey: request.requestID)
            let engineError = TurnEngineError.provider(error)
            recordPresentation(
                .failure(engineError),
                in: &presentation,
                observer: observer
            )
            return TurnEngineExecution(result: .failed(engineError), presentation: presentation)
        } catch {
            states.removeValue(forKey: request.requestID)
            // A provider-facing stream error is not a clean EOF. Keep the
            // clean-EOF error reserved for normal stream exhaustion below.
            let engineError = TurnEngineError.provider(.malformedResponse)
            recordPresentation(
                .failure(engineError),
                in: &presentation,
                observer: observer
            )
            return TurnEngineExecution(result: .failed(engineError), presentation: presentation)
        }
    }

    private func process(
        _ event: ProviderStreamEvent,
        request: TurnRequest,
        subturnIndex: Int,
        state: inout StreamState,
        presentation: inout [TurnPresentationEvent],
        observer: TurnPresentationObserver?
    ) throws {
        guard presentation.count < 4_096 else {
            throw TurnEngineError.invalidEnvelope(.tooManyItems)
        }
        switch event {
        case .textDelta(let text):
            guard TurnEnvelopeValidator.isSafeText(text),
                  text.utf8.count <= TurnEnvelopeValidator.maximumTextBytes else {
                throw TurnEngineError.invalidEnvelope(.unsafeText)
            }
            state.proseBytes += text.utf8.count
            guard state.proseBytes <= 2_000_000 else {
                throw TurnEngineError.invalidEnvelope(.textTooLarge)
            }
            recordPresentation(
                .prose(text),
                in: &presentation,
                observer: observer
            )

        case .toolCallStarted(let callID, let toolName):
            guard isSafeIdentifier(callID), callID.isEmpty == false,
                  isSafeIdentifier(toolName), toolName.isEmpty == false else {
                throw TurnEngineError.invalidTool(.unsafeArgument)
            }
            guard state.startedTools.count < TurnEnvelopeValidator.maximumItems else {
                throw TurnEngineError.invalidTool(.invalidBounds)
            }
            let trackingCallID = lineageCallID(callID, subturnIndex: subturnIndex)
            guard state.startedTools[trackingCallID] == nil else {
                throw TurnEngineError.invalidTool(.malformedArguments)
            }
            state.startedTools[trackingCallID] = toolName
            state.startedToolsBySubturn[subturnIndex, default: []].insert(
                trackingCallID
            )
            recordPresentation(
                .toolStarted(
                    callID: callID,
                    toolName: sanitizedToolName(toolName)
                ),
                in: &presentation,
                observer: observer
            )

        case .toolCallArgumentFragment(let callID, let fragment):
            let trackingCallID = lineageCallID(callID, subturnIndex: subturnIndex)
            guard state.startedTools[trackingCallID] != nil,
                  TurnEnvelopeValidator.isSafeText(fragment) else {
                throw TurnEngineError.invalidTool(.malformedArguments)
            }
            state.argumentBytes[trackingCallID, default: 0] += fragment.utf8.count
            guard state.argumentBytes[trackingCallID, default: 0]
                    <= ProviderToolArguments.maximumEncodedBytes else {
                throw TurnEngineError.invalidTool(
                    .argumentsTooLarge(
                        maximumBytes: ProviderToolArguments.maximumEncodedBytes,
                        actualBytes: state.argumentBytes[trackingCallID, default: 0]
                    )
                )
            }

        case .toolCallCompleted(let callID, let toolName, let arguments):
            let trackingCallID = lineageCallID(callID, subturnIndex: subturnIndex)
            guard state.startedTools[trackingCallID] == toolName,
                  state.completedTools.insert(trackingCallID).inserted else {
                throw TurnEngineError.invalidTool(.malformedArguments)
            }
            let rollID = Self.deterministicRollID(
                requestID: request.requestID,
                callID: trackingCallID
            )
            let proposal: ToolProposal
            do {
                proposal = try ToolValidator().validate(
                    toolName: toolName,
                    arguments: arguments,
                    context: validationContext,
                    rollID: rollID
                )
            } catch let error as ToolValidationError {
                throw TurnEngineError.invalidTool(error)
            } catch {
                throw TurnEngineError.invalidTool(.malformedArguments)
            }
            recordPresentation(
                .toolResult(
                    callID: callID,
                    toolName: sanitizedToolName(toolName),
                    sanitizedStatus: sanitizedStatus(proposal.status)
                ),
                in: &presentation,
                observer: observer
            )
            state.toolResultItems.append(
                continuationItem(
                    callID: trackingCallID,
                    toolName: toolName,
                    proposal: proposal
                )
            )
            if toolName == GMTool.requestRoll.rawValue {
                guard case .proposedEvent(
                    .rollRequest(_, let expression, let prompt)
                ) = proposal.result else {
                    throw TurnEngineError.invalidTool(.malformedArguments)
                }
                state.expectedRolls.append(
                    TurnRollLineage(
                        rollID: rollID,
                        expression: expression,
                        prompt: prompt
                    )
                )
            }
            state.validatedToolResults.insert(trackingCallID)

        case .usage, .warning:
            break

        case .finished(.completed(let envelope)):
            guard state.finalEnvelope == nil else {
                throw TurnEngineError.duplicateCompletion
            }
            guard allStartedToolsHaveValidatedResults(state) else {
                throw TurnEngineError.invalidTool(.malformedArguments)
            }
            guard envelope.requestID == request.requestID else {
                throw TurnEngineError.requestIDMismatch
            }
            state.finalEnvelope = envelope

        case .finished(.requiresToolResults):
            // A provider may report an intermediate tool boundary. The engine
            // only commits after it observes and validates a completed envelope.
            guard let currentCalls = state.startedToolsBySubturn[subturnIndex],
                  currentCalls.isEmpty == false,
                  currentCalls.allSatisfy({
                      state.validatedToolResults.contains($0)
                  }) else {
                throw TurnEngineError.invalidTool(.malformedArguments)
            }
            state.requiresToolResults = true

        case .finished(.maximumOutputTokens):
            break
        }
    }

    private func persistCancellation(
        _ request: TurnRequest,
        presentation: [TurnPresentationEvent],
        observer: TurnPresentationObserver? = nil
    ) async -> TurnEngineExecution {
        guard states[request.requestID] != .canonicalFinal,
              states[request.requestID] != .committing else {
            return failure(
                .canonicalFinalAlreadyExists,
                presentation: presentation,
                observer: observer
            )
        }
        do {
            let batch = try builder.buildCancellation(
                request: request,
                reason: "The turn was cancelled before completion."
            )
            states[request.requestID] = .committing
            let appended = try await store.append(
                batch: batch,
                assets: [],
                expectedSequence: request.expectedSequence
            )
            states[request.requestID] = .cancelled
            cancellationRequests.remove(request.requestID)
            var resultPresentation = presentation
            recordPresentation(
                .failure(.cancelled),
                in: &resultPresentation,
                observer: observer
            )
            return TurnEngineExecution(
                result: .cancelled,
                presentation: resultPresentation,
                appendedEvents: appended
            )
        } catch let error as CampaignStoreError {
            if case .duplicateRequestID = error {
                do {
                    if let existing = try await existingTerminalExecution(for: request) {
                        return adopt(existing, for: request.requestID)
                    }
                } catch {
                    states.removeValue(forKey: request.requestID)
                    var resultPresentation = presentation
                    recordPresentation(
                        .failure(.persistenceFailure),
                        in: &resultPresentation,
                        observer: observer
                    )
                    return TurnEngineExecution(
                        result: .failed(.persistenceFailure),
                        presentation: resultPresentation
                    )
                }
                states.removeValue(forKey: request.requestID)
                var resultPresentation = presentation
                recordPresentation(
                    .failure(.persistenceFailure),
                    in: &resultPresentation,
                    observer: observer
                )
                return TurnEngineExecution(
                    result: .failed(.persistenceFailure),
                    presentation: resultPresentation
                )
            }
            if case .expectedSequenceConflict = error {
                do {
                    let loaded = try await reloadCampaign(
                        campaignID: request.campaignID
                    )
                    retain(loaded.projection)
                } catch {
                    states.removeValue(forKey: request.requestID)
                    var resultPresentation = presentation
                    recordPresentation(
                        .failure(.persistenceFailure),
                        in: &resultPresentation,
                        observer: observer
                    )
                    return TurnEngineExecution(
                        result: .failed(.persistenceFailure),
                        presentation: resultPresentation
                    )
                }
                states.removeValue(forKey: request.requestID)
                var resultPresentation = presentation
                recordPresentation(
                    .failure(.sequenceConflict),
                    in: &resultPresentation,
                    observer: observer
                )
                return TurnEngineExecution(
                    result: .failed(.sequenceConflict),
                    presentation: resultPresentation
                )
            }
            states.removeValue(forKey: request.requestID)
            var resultPresentation = presentation
            recordPresentation(
                .failure(.persistenceFailure),
                in: &resultPresentation,
                observer: observer
            )
            return TurnEngineExecution(
                result: .failed(.persistenceFailure),
                presentation: resultPresentation
            )
        } catch {
            states.removeValue(forKey: request.requestID)
            var resultPresentation = presentation
            recordPresentation(
                .failure(.persistenceFailure),
                in: &resultPresentation,
                observer: observer
            )
            return TurnEngineExecution(
                result: .failed(.persistenceFailure),
                presentation: resultPresentation
            )
        }
    }

    private func persistCancellationIfRequestedAfterStreamSetup(
        _ request: TurnRequest,
        presentation: [TurnPresentationEvent],
        observer: TurnPresentationObserver? = nil
    ) async -> TurnEngineExecution? {
        guard cancellationRequests.contains(request.requestID) else {
            return nil
        }
        await provider.cancel(requestID: request.requestID)
        return await persistCancellation(
            request,
            presentation: presentation,
            observer: observer
        )
    }

    private func continuationRequest(
        from request: TurnRequest,
        state: StreamState
    ) throws -> TurnRequest {
        guard let assembly = request.contextAssembly,
              assembly.context == request.context,
              TurnContextAssembler.canonicalHash(
                  sections: assembly.context.sections,
                  budget: assembly.budget,
                  metadata: assembly.metadata
              ) == assembly.context.contextHash else {
            throw TurnEngineError.missingContextAssembly
        }
        let baseSections = request.context.sections.filter {
            $0.kind != .toolResults
        }
        let sections = baseSections + [
            ContextSection(kind: .toolResults, items: state.toolResultItems)
        ]
        let estimatedInputTokens = ContextBudget.estimateTokens(for: sections)
        guard estimatedInputTokens <= assembly.budget.inputTokenBudget else {
            throw TurnEngineError.contextBudgetExceeded(
                estimatedInputTokens: estimatedInputTokens,
                inputTokenBudget: assembly.budget.inputTokenBudget
            )
        }
        let budget = assembly.budget.recording(
            estimatedInputTokens: estimatedInputTokens
        )
        let hash = TurnContextAssembler.canonicalHash(
            sections: sections,
            budget: budget,
            metadata: assembly.metadata
        )
        let continuationAssembly = TurnContextAssembly(
            context: TurnContext(contextHash: hash, sections: sections),
            budget: budget,
            metadata: assembly.metadata
        )
        return TurnRequest(
            requestID: request.requestID,
            campaignID: request.campaignID,
            expectedSequence: request.expectedSequence,
            action: request.action,
            assembly: continuationAssembly,
            modelID: request.modelID
        )
    }

    private func allStartedToolsHaveValidatedResults(
        _ state: StreamState
    ) -> Bool {
        state.startedTools.keys.allSatisfy {
            state.validatedToolResults.contains($0)
        }
    }

    private func continuationItem(
        callID: String,
        toolName: String,
        proposal: ToolProposal
    ) -> ContextSection.Item {
        let resultText: String
        switch proposal.result {
        case .recordRead(let result):
            resultText = deterministicJSON(result) ?? "recordRead"
        case .recordsFound(let results):
            resultText = deterministicJSON(results) ?? "recordsFound"
        case .proposedEvent(let event):
            resultText = deterministicJSON(event) ?? "proposalAccepted"
        }
        let fullText = "status=\(proposal.status)\nresult=\(resultText)"
        let text: String
        if fullText.utf8.count <= 32_000,
           TurnEnvelopeValidator.isSafeText(fullText) {
            text = fullText
        } else {
            text = "status=\(proposal.status)\nresult=bounded"
        }
        return ContextSection.Item(
            id: "tool-result-\(callID)",
            name: sanitizedToolName(toolName),
            text: text
        )
    }

    private func deterministicJSON<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), data.count <= 30_000 else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func lineageCallID(_ callID: String, subturnIndex: Int) -> String {
        subturnIndex == 0 ? callID : "subturn-\(subturnIndex)-\(callID)"
    }

    private func existingTerminalExecution(
        for request: TurnRequest
    ) async throws -> TurnEngineExecution? {
        let loaded = try await reloadCampaign(campaignID: request.campaignID)
        retain(loaded.projection)
        return terminalExecution(
            requestID: request.requestID,
            events: loaded.events
        )
    }

    private func existingTerminalExecution(
        requestID: UUID
    ) async throws -> TurnEngineExecution? {
        for campaign in try await store.campaigns() {
            let loaded = try await reloadCampaign(campaignID: campaign.campaignID)
            retain(loaded.projection)
            if let terminal = terminalExecution(
                requestID: requestID,
                events: loaded.events
            ) {
                return terminal
            }
        }
        return nil
    }

    private func terminalExecution(
        requestID: UUID,
        events: [CampaignEvent]
    ) -> TurnEngineExecution? {
        let requestEvents = events.filter { $0.requestID == requestID }
        guard let terminal = requestEvents.last(where: { event in
            switch event.payload {
            case .gmMessageCommitted, .turnCancelled, .turnFailed:
                true
            default:
                false
            }
        }) else {
            return nil
        }
        switch terminal.payload {
        case .gmMessageCommitted:
            return TurnEngineExecution(
                result: .committed,
                presentation: [],
                appendedEvents: requestEvents
            )
        case .turnCancelled:
            return TurnEngineExecution(
                result: .cancelled,
                presentation: [],
                appendedEvents: requestEvents
            )
        case .turnFailed(let payload):
            return TurnEngineExecution(
                result: .failed(
                    .canonicalFailure(
                        category: payload.category,
                        message: payload.message,
                        isRetryable: payload.isRetryable
                    )
                ),
                presentation: [],
                appendedEvents: requestEvents
            )
        default:
            return nil
        }
    }

    private func reconcileCancellation(
        requestID: UUID,
        request: TurnRequest?,
        fallback: TurnEngineExecution
    ) async -> TurnEngineExecution {
        do {
            let existing = if let request {
                try await existingTerminalExecution(for: request)
            } else {
                try await existingTerminalExecution(requestID: requestID)
            }
            guard let existing else {
                return fallback
            }

            // A cancellation request must not mask a terminal event that was
            // already durable. Keep the public cancellation contract's
            // canonical-terminal error while adopting the durable state.
            _ = adopt(existing, for: requestID)
            return failure(
                .canonicalFinalAlreadyExists,
                presentation: [.failure(.canonicalFinalAlreadyExists)]
            )
        } catch {
            // Do not report cancellation when the store could not tell us
            // whether a terminal event already exists.
            return failure(
                .persistenceFailure,
                presentation: [.failure(.persistenceFailure)]
            )
        }
    }

    private struct ReloadedCampaign: Sendable {
        let events: [CampaignEvent]
        let projection: CampaignProjection
    }

    private func reloadCampaign(campaignID: UUID) async throws -> ReloadedCampaign {
        let pageSize = 256
        var events: [CampaignEvent] = []
        var eventIDs = Set<UUID>()
        let latestSequence = try await store.latestSequence(for: campaignID)
        guard latestSequence >= 0 else {
            throw CampaignStoreError.persistenceFailure
        }
        var cursor: Int64 = 0
        while cursor < latestSequence {
            let page = try await store.events(
                for: campaignID,
                after: cursor,
                limit: pageSize
            )
            guard page.isEmpty == false else { break }
            var expectedSequence = cursor
            for event in page {
                guard event.campaignID == campaignID else {
                    throw CampaignStoreError.mixedCampaignBatch
                }
                guard expectedSequence < Int64.max else {
                    throw CampaignStoreError.persistenceFailure
                }
                expectedSequence += 1
                guard event.sequence == expectedSequence else {
                    throw CampaignStoreError.invalidRestoreSequence(
                        expected: expectedSequence,
                        actual: event.sequence
                    )
                }
                guard event.sequence <= latestSequence else {
                    throw CampaignStoreError.persistenceFailure
                }
                guard eventIDs.insert(event.id).inserted else {
                    throw CampaignStoreError.duplicateEventID(event.id)
                }
            }
            guard let last = page.last else {
                throw CampaignStoreError.persistenceFailure
            }
            events.append(contentsOf: page)
            cursor = last.sequence
        }
        guard cursor == latestSequence else {
            throw CampaignStoreError.persistenceFailure
        }

        var projection = CampaignProjection(campaignID: campaignID)
        do {
            if let checkpoint = try await store.latestProjectionCheckpoint(
                for: campaignID,
                reducerSchemaVersion: CampaignReducer.reducerSchemaVersion
            ), checkpoint.isValid(
                for: campaignID,
                latestSequence: latestSequence,
                reducerSchemaVersion: CampaignReducer.reducerSchemaVersion
            ) {
                projection = checkpoint.projection
            }
        } catch CampaignStoreError.invalidProjectionCheckpoint(_) {
            // Rebuild from canonical events when a store cannot decode its
            // newest checkpoint. The checkpoint is never trusted partially.
        }
        let replayEvents = projection.appliedThroughSequence == 0
            ? events
            : events.filter { $0.sequence > projection.appliedThroughSequence }
        let reduction = CampaignReducer().reduce(
            projection,
            events: replayEvents
        )
        guard reduction.diagnostics.isEmpty else {
            throw CampaignStoreError.persistenceFailure
        }
        projection = reduction.projection
        guard projection.appliedThroughSequence == latestSequence else {
            throw CampaignStoreError.persistenceFailure
        }
        return ReloadedCampaign(events: events, projection: projection)
    }

    private func retain(_ projection: CampaignProjection) {
        validationContext = GMToolValidationContext(
            campaignID: validationContext.campaignID,
            project: validationContext.project,
            projection: projection,
            importedAssets: validationContext.importedAssets,
            assetReferences: validationContext.assetReferences
        )
        validator = TurnEnvelopeValidator(context: validationContext)
    }

    private func failure(
        _ error: TurnEngineError,
        presentation: [TurnPresentationEvent],
        observer: TurnPresentationObserver? = nil
    ) -> TurnEngineExecution {
        var resultPresentation = presentation
        let terminal = TurnPresentationEvent.failure(error)
        if resultPresentation.last != terminal {
            recordPresentation(
                terminal,
                in: &resultPresentation,
                observer: observer
            )
        } else {
            observer?(terminal)
        }
        return TurnEngineExecution(
            result: .failed(error),
            presentation: resultPresentation
        )
    }

    private func recordPresentation(
        _ event: TurnPresentationEvent,
        in presentation: inout [TurnPresentationEvent],
        observer: TurnPresentationObserver?
    ) {
        presentation.append(event)
        observer?(event)
    }

    private func adopt(
        _ execution: TurnEngineExecution,
        for requestID: UUID
    ) -> TurnEngineExecution {
        switch execution.result {
        case .committed:
            states[requestID] = .canonicalFinal
        case .cancelled:
            states[requestID] = .cancelled
        case .failed:
            states.removeValue(forKey: requestID)
        }
        cancellationRequests.remove(requestID)
        return execution
    }

    private func isSafeIdentifier(_ value: String) -> Bool {
        value.utf8.count <= 128
            && TurnEnvelopeValidator.isSafeText(value)
    }

    private func sanitizedToolName(_ value: String) -> String {
        guard isSafeIdentifier(value) else { return "unknown tool" }
        return value
    }

    private func sanitizedStatus(_ value: String) -> String {
        guard TurnEnvelopeValidator.isSafeText(value),
              value.utf8.count <= 256 else {
            return "Tool completed."
        }
        return value
    }

    static func deterministicRollID(requestID: UUID, callID: String) -> UUID {
        let digest = Array(
            SHA256.hash(data: Data("\(requestID.uuidString):\(callID)".utf8))
        )
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5],
            (digest[6] & 0x0f) | 0x40,
            digest[7],
            (digest[8] & 0x3f) | 0x80,
            digest[9], digest[10], digest[11], digest[12], digest[13],
            digest[14], digest[15]
        ))
    }
}
