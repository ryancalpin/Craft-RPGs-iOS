import Foundation

/// Provider model metadata used when a provider catalog cannot be fetched.
///
/// These entries are deliberately a fallback only. A successful provider
/// discovery response remains authoritative and can replace them in Settings.
public enum CuratedProviderModelCatalog {
    public static func models(for providerID: ProviderID) -> [ProviderModel] {
        switch providerID {
        case .openAI:
            return openAI
        case .openRouter:
            return openRouter
        case .anthropic:
            return anthropic
        case .gemini:
            return gemini
        }
    }

    private static let openAI: [ProviderModel] = [
        try! ProviderModel(
            providerID: .openAI,
            id: "gpt-5.1",
            displayName: "GPT-5.1",
            contextWindowTokens: 400_000,
            maximumOutputTokens: 128_000,
            supportsTools: true,
            supportsStructuredOutput: true
        ),
        try! ProviderModel(
            providerID: .openAI,
            id: "gpt-4.1",
            displayName: "GPT-4.1",
            contextWindowTokens: 1_047_576,
            maximumOutputTokens: 32_768,
            supportsTools: true,
            supportsStructuredOutput: true
        )
    ]

    private static let openRouter: [ProviderModel] = [
        try! ProviderModel(
            providerID: .openRouter,
            id: "openai/gpt-5.1",
            displayName: "OpenAI GPT-5.1 via OpenRouter",
            contextWindowTokens: 400_000,
            maximumOutputTokens: 128_000,
            supportsTools: true,
            supportsStructuredOutput: true
        ),
        try! ProviderModel(
            providerID: .openRouter,
            id: "openai/gpt-4.1-mini",
            displayName: "OpenAI GPT-4.1 mini via OpenRouter",
            contextWindowTokens: 1_047_576,
            maximumOutputTokens: 32_768,
            supportsTools: true,
            supportsStructuredOutput: true
        )
    ]

    private static let anthropic: [ProviderModel] = [
        try! ProviderModel(
            providerID: .anthropic,
            id: "claude-opus-5",
            displayName: "Claude Opus 5",
            contextWindowTokens: 1_000_000,
            maximumOutputTokens: 128_000,
            supportsTools: true,
            supportsStructuredOutput: true
        ),
        try! ProviderModel(
            providerID: .anthropic,
            id: "claude-sonnet-5",
            displayName: "Claude Sonnet 5",
            contextWindowTokens: 1_000_000,
            maximumOutputTokens: 128_000,
            supportsTools: true,
            supportsStructuredOutput: true
        )
    ]

    private static let gemini: [ProviderModel] = [
        try! ProviderModel(
            providerID: .gemini,
            id: "gemini-3.6-flash",
            displayName: "Gemini 3.6 Flash",
            contextWindowTokens: 1_048_576,
            maximumOutputTokens: 65_536,
            supportsTools: true,
            supportsStructuredOutput: true
        ),
        try! ProviderModel(
            providerID: .gemini,
            id: "gemini-3.5-flash-lite",
            displayName: "Gemini 3.5 Flash-Lite",
            contextWindowTokens: 1_048_576,
            maximumOutputTokens: 65_536,
            supportsTools: true,
            supportsStructuredOutput: true
        )
    ]
}
