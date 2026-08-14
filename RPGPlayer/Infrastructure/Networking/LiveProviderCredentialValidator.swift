import Foundation

struct LiveProviderCredentialValidator: ProviderCredentialValidator,
    Sendable
{
    func availability(
        for reference: ProviderCredentialReference
    ) -> ProviderCredentialValidationAvailability {
        .available
    }

    func validate(
        _ candidate: String,
        for reference: ProviderCredentialReference
    ) async throws {
        guard candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false else {
            throw ProviderCredentialError.emptyCredential
        }

        let reader = CandidateProviderCredentialReader(candidate: candidate)
        let provider: any AIProvider
        switch reference.providerID {
        case .openAI:
            provider = OpenAIProvider(
                credentialReader: reader,
                credentialReference: reference
            )
        case .openRouter:
            provider = OpenRouterProvider(
                credentialReader: reader,
                credentialReference: reference
            )
        case .anthropic:
            provider = AnthropicProvider(
                credentialReader: reader,
                credentialReference: reference
            )
        case .gemini:
            provider = GeminiProvider(
                credentialReader: reader,
                credentialReference: reference
            )
        }

        do {
            _ = try await provider.models()
        } catch ProviderError.invalidCredential {
            throw ProviderCredentialError.validationRejected
        } catch ProviderError.cancelled {
            throw CancellationError()
        } catch {
            throw ProviderCredentialError.operationFailed
        }
    }
}

private struct CandidateProviderCredentialReader: ProviderCredentialReader,
    Sendable
{
    let candidate: String

    func credentialData(
        for reference: ProviderCredentialReference
    ) async throws -> Data {
        Data(candidate.utf8)
    }
}
