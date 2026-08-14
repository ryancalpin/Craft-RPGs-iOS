import Foundation

public struct ImageModelSelection: Codable, Equatable, Hashable, Sendable {
    public let providerID: ProviderID
    public let modelID: String

    public init(providerID: ProviderID, modelID: String) {
        self.providerID = providerID
        self.modelID = modelID
    }
}

public struct ImageRoutingSettings: Codable, Equatable, Sendable {
    public var primary: ImageModelSelection
    public var fallback: ImageModelSelection?
    public var automaticFallbackEnabled: Bool

    public init(
        primary: ImageModelSelection,
        fallback: ImageModelSelection? = nil,
        automaticFallbackEnabled: Bool = true
    ) {
        self.primary = primary
        self.fallback = fallback
        self.automaticFallbackEnabled = automaticFallbackEnabled
    }

    public static let `default` = ImageRoutingSettings(
        primary: ImageModelSelection(
            providerID: .openAI,
            modelID: "gpt-image-1"
        )
    )
}

public protocol ImageRoutingSettingsStore: Sendable {
    func load() async throws -> ImageRoutingSettings
    func save(_ settings: ImageRoutingSettings) async throws
}

public struct UserDefaultsImageRoutingStore: ImageRoutingSettingsStore,
    Sendable
{
    public static let key = "rpgplayer.image-routing.v1"

    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    public func load() async throws -> ImageRoutingSettings {
        guard let data = defaults.data(forKey: Self.key) else {
            return .default
        }
        do {
            return try JSONDecoder().decode(ImageRoutingSettings.self, from: data)
        } catch {
            throw ModelRoutingStoreError.corruptSettings
        }
    }

    public func save(_ settings: ImageRoutingSettings) async throws {
        defaults.set(try JSONEncoder().encode(settings), forKey: Self.key)
    }

    private var defaults: UserDefaults {
        if let suiteName, let suite = UserDefaults(suiteName: suiteName) {
            return suite
        }
        return .standard
    }
}

public protocol ImageProviderCatalogProviding: Sendable {
    func models(for providerID: ProviderID) async -> [ImageGenerationModel]
}

public struct ImageProviderCatalogService: ImageProviderCatalogProviding,
    Sendable
{
    private let providers: [ProviderID: any ImageProvider]

    public init(providers: [ProviderID: any ImageProvider]) {
        self.providers = providers
    }

    public func models(for providerID: ProviderID) async -> [ImageGenerationModel] {
        guard let provider = providers[providerID] else { return [] }
        return (try? await provider.models()) ?? []
    }
}

public actor ImageRoutingProvider: ImageProvider {
    public nonisolated let id: ProviderID

    private var settings: ImageRoutingSettings
    private let providers: [ProviderID: any ImageProvider]

    public init(
        settings: ImageRoutingSettings,
        providers: [ProviderID: any ImageProvider]
    ) {
        self.settings = settings
        self.providers = providers
        id = settings.primary.providerID
    }

    public func update(settings: ImageRoutingSettings) {
        self.settings = settings
    }

    public func models() async throws -> [ImageGenerationModel] {
        var result: [ImageGenerationModel] = []
        for providerID in providers.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            result.append(contentsOf: (try? await providers[providerID]?.models()) ?? [])
        }
        return result
    }

    public func generateImage(
        _ request: ImageGenerationRequest
    ) async throws -> ImageGenerationResult {
        let routes = routeCandidates()
        guard let primary = providers[routes[0].providerID] else {
            throw ModelRoutingError.unavailableProvider(routes[0].providerID)
        }

        do {
            return try await primary.generateImage(
                request.with(modelID: routes[0].modelID)
            )
        } catch {
            guard routes.count > 1,
                  error.isFallbackEligible,
                  let fallback = providers[routes[1].providerID] else {
                throw error
            }
            return try await fallback.generateImage(
                request.with(modelID: routes[1].modelID)
            )
        }
    }

    private func routeCandidates() -> [ImageModelSelection] {
        var routes = [settings.primary]
        if settings.automaticFallbackEnabled,
           let fallback = settings.fallback,
           fallback != settings.primary {
            routes.append(fallback)
        }
        return routes
    }
}

private extension ImageGenerationRequest {
    func with(modelID: String) -> ImageGenerationRequest {
        try! ImageGenerationRequest(
            prompt: prompt,
            modelID: modelID,
            size: size,
            quality: quality,
            count: count
        )
    }
}

private extension Error {
    var isFallbackEligible: Bool {
        guard let error = self as? ProviderError else { return false }
        return error.isFallbackEligible
    }
}
