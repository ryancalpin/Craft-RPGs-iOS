import Foundation

public struct VoiceCredentialReference: Equatable, Sendable {
    public static let primaryAccountLabel = "primary"

    public let providerID: VoiceProviderID
    public let accountLabel: String

    public init(
        providerID: VoiceProviderID,
        accountLabel: String = VoiceCredentialReference.primaryAccountLabel
    ) throws {
        let normalizedLabel = accountLabel.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard normalizedLabel.isEmpty == false else {
            throw ProviderCredentialError.invalidReference
        }
        self.providerID = providerID
        self.accountLabel = normalizedLabel
    }
}

public protocol VoiceCredentialSettingsStore: Sendable {
    func exists(for reference: VoiceCredentialReference) async throws -> Bool
    func save(
        _ candidate: String,
        for reference: VoiceCredentialReference
    ) async throws
    func replace(
        _ candidate: String,
        for reference: VoiceCredentialReference
    ) async throws
    func delete(_ reference: VoiceCredentialReference) async throws
}

public protocol VoiceCredentialReader: Sendable {
    func credentialData(
        for reference: VoiceCredentialReference
    ) async throws -> Data
}

public protocol VoiceCredentialValidator: Sendable {
    func availability(
        for reference: VoiceCredentialReference
    ) -> ProviderCredentialValidationAvailability
    func validate(
        _ candidate: String,
        for reference: VoiceCredentialReference
    ) async throws
}

public struct UnavailableVoiceCredentialValidator: VoiceCredentialValidator,
    Sendable
{
    public init() {}

    public func availability(
        for reference: VoiceCredentialReference
    ) -> ProviderCredentialValidationAvailability {
        .unavailable
    }

    public func validate(
        _ candidate: String,
        for reference: VoiceCredentialReference
    ) async throws {
        throw ProviderCredentialError.validationUnavailable
    }
}

public protocol VoiceCatalogProviding: Sendable {
    func voices() async throws -> [VoiceDescriptor]
}
