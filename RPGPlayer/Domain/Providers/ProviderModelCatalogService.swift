import Foundation

public protocol ProviderModelCatalogProviding: Sendable {
    func models(for providerID: ProviderID) async -> [ProviderModel]
}

public struct ProviderModelCatalogService: ProviderModelCatalogProviding,
    Sendable
{
    private let providers: [ProviderID: any AIProvider]

    public init(providers: [ProviderID: any AIProvider]) {
        self.providers = providers
    }

    public func models(for providerID: ProviderID) async -> [ProviderModel] {
        guard let provider = providers[providerID] else {
            return CuratedProviderModelCatalog.models(for: providerID)
        }

        do {
            let discovered = try await provider.models()
            return discovered.isEmpty
                ? CuratedProviderModelCatalog.models(for: providerID)
                : discovered
        } catch {
            return CuratedProviderModelCatalog.models(for: providerID)
        }
    }
}
