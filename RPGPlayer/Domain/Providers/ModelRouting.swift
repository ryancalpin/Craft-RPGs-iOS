import Foundation

public struct TextModelSelection: Codable, Equatable, Hashable, Sendable {
    public let providerID: ProviderID
    public let modelID: String

    public init(providerID: ProviderID, modelID: String) {
        self.providerID = providerID
        self.modelID = modelID
    }
}

public struct ModelRoutingSettings: Codable, Equatable, Sendable {
    public var primary: TextModelSelection
    public var fallback: TextModelSelection?
    public var automaticFallbackEnabled: Bool

    public init(
        primary: TextModelSelection,
        fallback: TextModelSelection? = nil,
        automaticFallbackEnabled: Bool = true
    ) {
        self.primary = primary
        self.fallback = fallback
        self.automaticFallbackEnabled = automaticFallbackEnabled
    }

    public static let `default` = ModelRoutingSettings(
        primary: TextModelSelection(
            providerID: .openAI,
            modelID: CuratedProviderModelCatalog.models(for: .openAI)[0].id
        ),
        fallback: TextModelSelection(
            providerID: .anthropic,
            modelID: CuratedProviderModelCatalog.models(for: .anthropic)[0].id
        )
    )
}

public enum ModelRoutingError: Error, Equatable, Sendable {
    case incompatibleModel(providerID: ProviderID, modelID: String)
    case unavailableProvider(ProviderID)
    case missingFallback
}

public enum ModelRouteValidator {
    public static func validateGMModel(_ model: ProviderModel) throws {
        guard model.supportsTools, model.supportsStructuredOutput else {
            throw ModelRoutingError.incompatibleModel(
                providerID: model.providerID,
                modelID: model.id
            )
        }
    }

    public static func model(
        for selection: TextModelSelection,
        in catalog: [ProviderModel]
    ) throws -> ProviderModel {
        guard let model = catalog.first(where: {
            $0.providerID == selection.providerID && $0.id == selection.modelID
        }) else {
            throw ModelRoutingError.incompatibleModel(
                providerID: selection.providerID,
                modelID: selection.modelID
            )
        }
        try validateGMModel(model)
        return model
    }
}

public enum ModelRoutingStoreError: Error, Equatable, Sendable {
    case corruptSettings
}

public protocol ModelRoutingSettingsStore: Sendable {
    func load() async throws -> ModelRoutingSettings
    func save(_ settings: ModelRoutingSettings) async throws
}

public struct UserDefaultsModelRoutingStore: ModelRoutingSettingsStore,
    Sendable
{
    public static let key = "rpgplayer.model-routing.v1"

    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    public func load() async throws -> ModelRoutingSettings {
        guard let data = defaults.data(forKey: Self.key) else {
            return .default
        }
        do {
            return try JSONDecoder().decode(ModelRoutingSettings.self, from: data)
        } catch {
            throw ModelRoutingStoreError.corruptSettings
        }
    }

    public func save(_ settings: ModelRoutingSettings) async throws {
        defaults.set(try JSONEncoder().encode(settings), forKey: Self.key)
    }

    private var defaults: UserDefaults {
        if let suiteName, let suite = UserDefaults(suiteName: suiteName) {
            return suite
        }
        return .standard
    }
}
