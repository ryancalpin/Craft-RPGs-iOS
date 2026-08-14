import Foundation

/// Applies the user's primary/fallback text route to provider-neutral turn
/// requests. Fallback is allowed only before the primary provider has emitted
/// any stream content, so a partially rendered story is never silently
/// duplicated by a second provider.
public actor ModelRoutingProvider: AIProvider {
    public nonisolated let id: ProviderID

    private var settings: ModelRoutingSettings
    private let providers: [ProviderID: any AIProvider]
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    public init(
        settings: ModelRoutingSettings,
        providers: [ProviderID: any AIProvider]
    ) {
        self.settings = settings
        self.providers = providers
        id = settings.primary.providerID
    }

    public func update(settings: ModelRoutingSettings) {
        self.settings = settings
    }

    public func models() async throws -> [ProviderModel] {
        var result: [ProviderModel] = []
        for providerID in ProviderID.allCases {
            if let provider = providers[providerID],
               let models = try? await provider.models() {
                result.append(contentsOf: models)
            } else {
                result.append(contentsOf: CuratedProviderModelCatalog.models(
                    for: providerID
                ))
            }
        }
        return result
    }

    public func streamTurn(
        _ request: TurnRequest
    ) async throws -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        let routes = routeCandidates()
        guard let primary = providers[routes[0].providerID] else {
            throw ModelRoutingError.unavailableProvider(routes[0].providerID)
        }
        let fallback = routes.dropFirst().first.flatMap {
            providers[$0.providerID]
        }

        let source = AsyncThrowingStream<ProviderStreamEvent, Error> {
            continuation in
            let task = Task {
                await Self.forward(
                    request: request,
                    primary: primary,
                    primaryRoute: routes[0],
                    fallback: fallback,
                    fallbackRoute: routes.dropFirst().first,
                    continuation: continuation
                )
            }
            activeTasks[request.requestID] = task
        }
        return source
    }

    public func cancel(requestID: UUID) async {
        activeTasks.removeValue(forKey: requestID)?.cancel()
        for provider in providers.values {
            await provider.cancel(requestID: requestID)
        }
    }

    private func routeCandidates() -> [TextModelSelection] {
        var routes = [settings.primary]
        if settings.automaticFallbackEnabled,
           let fallback = settings.fallback,
           fallback != settings.primary {
            routes.append(fallback)
        }
        return routes
    }

    private static func forward(
        request: TurnRequest,
        primary: any AIProvider,
        primaryRoute: TextModelSelection,
        fallback: (any AIProvider)?,
        fallbackRoute: TextModelSelection?,
        continuation: AsyncThrowingStream<ProviderStreamEvent, Error>.Continuation
    ) async {
        var emitted = false
        do {
            let stream = try await primary.streamTurn(
                request.with(modelID: primaryRoute.modelID)
            )
            do {
                for try await event in stream {
                    emitted = true
                    continuation.yield(event)
                }
                continuation.finish()
            } catch {
                if emitted == false,
                   let fallback,
                   let fallbackRoute,
                   error.isFallbackEligible {
                    await forwardFallback(
                        request: request,
                        provider: fallback,
                        route: fallbackRoute,
                        continuation: continuation
                    )
                } else {
                    continuation.finish(throwing: error)
                }
            }
        } catch {
            if let fallback,
               let fallbackRoute,
               error.isFallbackEligible {
                await forwardFallback(
                    request: request,
                    provider: fallback,
                    route: fallbackRoute,
                    continuation: continuation
                )
            } else {
                continuation.finish(throwing: error)
            }
        }
    }

    private static func forwardFallback(
        request: TurnRequest,
        provider: any AIProvider,
        route: TextModelSelection,
        continuation: AsyncThrowingStream<ProviderStreamEvent, Error>.Continuation
    ) async {
        do {
            let stream = try await provider.streamTurn(
                request.with(modelID: route.modelID)
            )
            for try await event in stream {
                continuation.yield(event)
            }
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }
}

private extension TurnRequest {
    func with(modelID: String) -> TurnRequest {
        TurnRequest(
            requestID: requestID,
            campaignID: campaignID,
            expectedSequence: expectedSequence,
            action: action,
            context: context,
            contextAssembly: contextAssembly,
            modelID: modelID
        )
    }
}

private extension Error {
    var isFallbackEligible: Bool {
        guard let error = self as? ProviderError else { return false }
        return error.isFallbackEligible
    }
}
