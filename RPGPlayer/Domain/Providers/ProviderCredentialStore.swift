import Foundation

public enum ProviderCredentialError: Error, Equatable, Sendable {
    case invalidReference
    case emptyCredential
    case alreadyExists
    case notFound
    case lockedUntilFirstUnlock
    case storageUnavailable
    case corruptCredential
    case operationFailed
    case validationUnavailable
    case validationRejected
}

public struct ProviderCredentialReference: Equatable, Sendable {
    public static let primaryAccountLabel = "primary"

    public let providerID: ProviderID
    public let accountLabel: String

    public init(
        providerID: ProviderID,
        accountLabel: String = ProviderCredentialReference.primaryAccountLabel
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

public protocol ProviderCredentialSettingsStore: Sendable {
    func exists(for reference: ProviderCredentialReference) async throws -> Bool
    func save(
        _ candidate: String,
        for reference: ProviderCredentialReference
    ) async throws
    func replace(
        _ candidate: String,
        for reference: ProviderCredentialReference
    ) async throws
    func delete(_ reference: ProviderCredentialReference) async throws
}

public protocol ProviderCredentialReader: Sendable {
    func credentialData(
        for reference: ProviderCredentialReference
    ) async throws -> Data
}

public enum ProviderCredentialValidationAvailability: Equatable, Sendable {
    case available
    case unavailable
}

public protocol ProviderCredentialValidator: Sendable {
    func availability(
        for reference: ProviderCredentialReference
    ) -> ProviderCredentialValidationAvailability
    func validate(
        _ candidate: String,
        for reference: ProviderCredentialReference
    ) async throws
}

public struct UnavailableProviderCredentialValidator:
    ProviderCredentialValidator,
    Sendable
{
    public init() {}

    public func availability(
        for reference: ProviderCredentialReference
    ) -> ProviderCredentialValidationAvailability {
        .unavailable
    }

    public func validate(
        _ candidate: String,
        for reference: ProviderCredentialReference
    ) async throws {
        throw ProviderCredentialError.validationUnavailable
    }
}

enum ProviderSettingsUITestValidationOutcome: Sendable {
    case accepting
    case rejecting
}

struct ProviderSettingsUITestValidator:
    ProviderCredentialValidator,
    Sendable
{
    let outcome: ProviderSettingsUITestValidationOutcome

    func availability(
        for reference: ProviderCredentialReference
    ) -> ProviderCredentialValidationAvailability {
        .available
    }

    func validate(
        _ candidate: String,
        for reference: ProviderCredentialReference
    ) async throws {
        if outcome == .rejecting {
            throw ProviderCredentialError.validationRejected
        }
    }
}
