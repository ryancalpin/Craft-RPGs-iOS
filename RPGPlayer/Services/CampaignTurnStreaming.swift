import Foundation

/// Bridges the durable TurnEngine into the presentation stream used by the
/// recording-faithful player. The engine remains the source of truth; this
/// adapter only translates sanitized progress and the committed envelope into
/// UI events.
actor CampaignTurnStreaming: TurnStreaming {
    private let campaignID: UUID
    private let project: NormalizedProject
    private let projectionLoader: ProjectionLoader
    private let campaignStore: any CampaignStore
    private let routingStore: any ModelRoutingSettingsStore
    private let modelCatalog: any ProviderModelCatalogProviding
    private let providers: [ProviderID: any AIProvider]

    private var producer: Task<Void, Never>?
    private var engine: TurnEngine?
    private var requestID: UUID?

    init(
        campaignID: UUID,
        project: NormalizedProject,
        projectionLoader: ProjectionLoader,
        campaignStore: any CampaignStore,
        routingStore: any ModelRoutingSettingsStore,
        modelCatalog: any ProviderModelCatalogProviding,
        providers: [ProviderID: any AIProvider]
    ) {
        self.campaignID = campaignID
        self.project = project
        self.projectionLoader = projectionLoader
        self.campaignStore = campaignStore
        self.routingStore = routingStore
        self.modelCatalog = modelCatalog
        self.providers = providers
    }

    func events(
        for submission: PlayerSubmission
    ) -> AsyncThrowingStream<TurnStreamEvent, Error> {
        producer?.cancel()
        let (stream, continuation) = AsyncThrowingStream.makeStream(
            of: TurnStreamEvent.self,
            throwing: Error.self
        )
        let task = Task { [weak self] in
            guard let self else { return }
            await self.run(submission: submission, continuation: continuation)
        }
        producer = task
        continuation.onTermination = { @Sendable _ in
            task.cancel()
            Task { await self.cancel() }
        }
        return stream
    }

    func cancel() async {
        producer?.cancel()
        if let engine, let requestID {
            _ = await engine.cancel(requestID: requestID)
        }
        producer = nil
        engine = nil
        requestID = nil
    }

    private func run(
        submission: PlayerSubmission,
        continuation: AsyncThrowingStream<TurnStreamEvent, Error>.Continuation
    ) async {
        do {
            try Task.checkCancellation()
            let loaded = try await projectionLoader.load(campaignID: campaignID)
            let settings = try await routingStore.load()
            let discovered = await modelCatalog.models(
                for: settings.primary.providerID
            )
            let model = try selectedModel(
                for: settings.primary,
                discovered: discovered
            )
            let source = TurnContextSource(
                project: project,
                projection: loaded.projection,
                safetySystemContract: Self.safetySystemContract
            )
            let assembly = TurnContextAssembler().assemble(
                source: source,
                model: model
            )
            let request = TurnRequest(
                requestID: UUID(),
                campaignID: campaignID,
                expectedSequence: loaded.projection.appliedThroughSequence,
                action: PlayerAction(
                    text: submission.action,
                    additionalContext: submission.additionalContext.isEmpty
                        ? nil
                        : submission.additionalContext
                ),
                assembly: assembly,
                modelID: settings.primary.modelID
            )
            requestID = request.requestID
            let storedAssets = try await campaignStore.importedAssets(
                for: campaignID
            )
            let declaredAssetIDs = Set(project.assets.map(\.id))
            let importedAssets = storedAssets.filter {
                declaredAssetIDs.contains($0.assetID)
            }
            let generatedAssetReferences = storedAssets
                .filter { declaredAssetIDs.contains($0.assetID) == false }
                .map {
                    GMToolAssetReference(
                        assetID: $0.assetID,
                        sha256: $0.sha256,
                        campaignID: campaignID,
                        origin: "generated",
                        path: $0.appRelativeURL.relativeString
                    )
                }
            let validationContext = GMToolValidationContext(
                campaignID: campaignID,
                project: project,
                projection: loaded.projection,
                importedAssets: importedAssets,
                assetReferences: generatedAssetReferences
            )
            let routedProvider = ModelRoutingProvider(
                settings: settings,
                providers: providers
            )
            let turnEngine = TurnEngine(
                provider: routedProvider,
                store: campaignStore,
                validationContext: validationContext
            )
            engine = turnEngine

            let execution = await turnEngine.run(request) { event in
                // The final envelope is announced by the engine before its
                // atomic append begins. Hold that UI event until the engine
                // returns a committed result so the player never refreshes
                // against a half-committed turn.
                if case .completed = event {
                    return
                }
                Self.publish(
                    event,
                    to: continuation,
                    actionCount: loaded.projection.submittedActions.count + 1
                )
            }
            try Task.checkCancellation()
            guard case .committed = execution.result else {
                throw execution.error ?? CampaignTurnStreamingError.turnFailed
            }
            if let completed = execution.presentation.last(where: {
                if case .completed = $0 { return true }
                return false
            }) {
                Self.publish(
                    completed,
                    to: continuation,
                    actionCount: loaded.projection.submittedActions.count + 1
                )
            }
            continuation.finish()
        } catch is CancellationError {
            continuation.finish(throwing: CancellationError())
        } catch {
            continuation.finish(throwing: error)
        }
        producer = nil
        engine = nil
        requestID = nil
    }

    private func selectedModel(
        for selection: TextModelSelection,
        discovered: [ProviderModel]
    ) throws -> ProviderModel {
        if let selected = discovered.first(where: {
            $0.providerID == selection.providerID && $0.id == selection.modelID
        }) {
            try ModelRouteValidator.validateGMModel(selected)
            return selected
        }
        if let curated = CuratedProviderModelCatalog.models(
            for: selection.providerID
        ).first(where: { $0.id == selection.modelID }) {
            try ModelRouteValidator.validateGMModel(curated)
            return curated
        }
        throw ModelRoutingError.incompatibleModel(
            providerID: selection.providerID,
            modelID: selection.modelID
        )
    }

    private static func message(
        from envelope: TurnEnvelope,
        actionCount: Int
    ) -> GMMessage {
        let prose = envelope.narration
            .filter { $0.kind == .narration }
            .map(\.text)
        let dialogue = envelope.narration
            .filter { $0.kind == .dialogue }
            .map {
                DialogueBlock(
                    id: $0.id,
                    speaker: $0.speakerName ?? "Unknown",
                    mood: $0.mood,
                    text: $0.text
                )
            }
        let transcript = envelope.narration.map {
            TranscriptBlock(
                id: $0.id,
                kind: $0.kind == .dialogue ? .dialogue : .narration,
                speaker: $0.speakerName,
                mood: $0.mood,
                text: $0.text
            )
        }
        return GMMessage(
            id: envelope.requestID,
            prose: prose,
            dialogue: dialogue,
            actionCount: actionCount,
            finalQuestion: envelope.pendingDecision?.prompt
                ?? "What do you do?",
            beats: envelope.beats,
            transcript: transcript
        )
    }

    private static func publish(
        _ event: TurnPresentationEvent,
        to continuation: AsyncThrowingStream<TurnStreamEvent, Error>.Continuation,
        actionCount: Int
    ) {
        switch event {
        case .status(let phase):
            continuation.yield(
                .phase(
                    GenerationPhase(rawValue: phase.rawValue)
                        ?? .needsAttention
                )
            )
        case .prose:
            continuation.yield(.step("Drafted the next story beat."))
        case .toolStarted(_, let toolName):
            continuation.yield(.step("Prepared \(toolName)."))
        case .toolResult(_, _, let detail):
            continuation.yield(.step(detail))
        case .completed(let envelope):
            continuation.yield(
                .completed(
                    Self.message(
                        from: envelope.envelope,
                        actionCount: actionCount
                    )
                )
            )
        case .failure:
            break
        }
    }

    private static let safetySystemContract = """
    You are the RPGPlayer game master. Return only the versioned RPGPlayer turn envelope. Stay within the imported campaign, use only the declared native tools, keep narration bounded, and never reveal credentials, local paths, hidden reasoning, or arbitrary URLs.
    """
}

enum CampaignTurnStreamingError: Error, Equatable, Sendable {
    case turnFailed
}

private extension TurnEngineExecution {
    var error: Error? {
        guard case .failed(let error) = result else { return nil }
        return error
    }
}
