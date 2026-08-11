import SwiftUI

@MainActor
struct APIKeyField: View {
    let providerID: ProviderID
    @Binding var text: String
    let isDisabled: Bool

    var body: some View {
        SecureField(providerID.apiKeyLabel, text: $text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)
            .privacySensitive()
            .disabled(isDisabled)
            .accessibilityIdentifier(
                "apiKeyField-\(providerID.rawValue)"
            )
    }
}

extension ProviderID {
    var settingsDisplayName: String {
        switch self {
        case .openAI:
            "OpenAI"
        case .openRouter:
            "OpenRouter"
        case .anthropic:
            "Anthropic"
        case .gemini:
            "Gemini"
        }
    }

    var apiKeyLabel: String {
        "\(settingsDisplayName) API key"
    }
}
