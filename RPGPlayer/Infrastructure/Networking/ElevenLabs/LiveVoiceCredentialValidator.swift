import Foundation

struct LiveVoiceCredentialValidator: VoiceCredentialValidator, Sendable {
    func availability(
        for reference: VoiceCredentialReference
    ) -> ProviderCredentialValidationAvailability {
        .available
    }

    func validate(
        _ candidate: String,
        for reference: VoiceCredentialReference
    ) async throws {
        guard candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false else {
            throw ProviderCredentialError.emptyCredential
        }

        do {
            try await ElevenLabsClient(
                credentialReader: CandidateVoiceCredentialReader(
                    candidate: candidate
                ),
                credentialReference: reference
            ).validate()
        } catch ProviderError.invalidCredential {
            throw ProviderCredentialError.validationRejected
        } catch ProviderError.cancelled {
            throw CancellationError()
        } catch {
            throw ProviderCredentialError.operationFailed
        }
    }
}

private struct CandidateVoiceCredentialReader: VoiceCredentialReader,
    Sendable
{
    let candidate: String

    func credentialData(
        for reference: VoiceCredentialReference
    ) async throws -> Data {
        Data(candidate.utf8)
    }
}
