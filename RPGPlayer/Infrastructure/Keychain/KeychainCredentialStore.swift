import Foundation
import Security

public actor KeychainCredentialStore:
    ProviderCredentialSettingsStore,
    ProviderCredentialReader
{
    private let testStoreIdentifier: String?

    public init() {
        testStoreIdentifier = nil
    }

    init(testStoreIdentifier: String) throws {
        self.testStoreIdentifier = try KeychainCredentialQueryBuilder
            .validatedTestStoreIdentifier(testStoreIdentifier)
    }

    public func exists(
        for reference: ProviderCredentialReference
    ) async throws -> Bool {
        let query = KeychainCredentialQueryBuilder.existenceQuery(
            reference: reference,
            testStoreIdentifier: testStoreIdentifier
        )
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            return false
        default:
            throw Self.error(for: status)
        }
    }

    public func save(
        _ candidate: String,
        for reference: ProviderCredentialReference
    ) async throws {
        let credentialData = try Self.validatedCredentialData(candidate)
        let query = KeychainCredentialQueryBuilder.addQuery(
            reference: reference,
            testStoreIdentifier: testStoreIdentifier,
            credentialData: credentialData
        )
        let status = SecItemAdd(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            throw ProviderCredentialError.alreadyExists
        default:
            throw Self.error(for: status)
        }
    }

    public func replace(
        _ candidate: String,
        for reference: ProviderCredentialReference
    ) async throws {
        let credentialData = try Self.validatedCredentialData(candidate)
        let query = KeychainCredentialQueryBuilder.identityQuery(
            reference: reference,
            testStoreIdentifier: testStoreIdentifier
        )
        let attributes = KeychainCredentialQueryBuilder
            .replacementAttributes(credentialData: credentialData)
        let status = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            throw ProviderCredentialError.notFound
        default:
            throw Self.error(for: status)
        }
    }

    public func delete(
        _ reference: ProviderCredentialReference
    ) async throws {
        let query = KeychainCredentialQueryBuilder.identityQuery(
            reference: reference,
            testStoreIdentifier: testStoreIdentifier
        )
        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw Self.error(for: status)
        }
    }

    public func credentialData(
        for reference: ProviderCredentialReference
    ) async throws -> Data {
        let query = KeychainCredentialQueryBuilder.readQuery(
            reference: reference,
            testStoreIdentifier: testStoreIdentifier
        )
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let credentialData = result as? Data else {
                throw ProviderCredentialError.corruptCredential
            }
            return credentialData
        case errSecItemNotFound:
            throw ProviderCredentialError.notFound
        default:
            throw Self.error(for: status)
        }
    }

    private static func validatedCredentialData(
        _ candidate: String
    ) throws -> Data {
        guard candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false else {
            throw ProviderCredentialError.emptyCredential
        }
        return Data(candidate.utf8)
    }

    private static func error(for status: OSStatus) -> ProviderCredentialError {
        switch status {
        case errSecInteractionNotAllowed:
            .lockedUntilFirstUnlock
        case errSecNotAvailable:
            .storageUnavailable
        case errSecDecode:
            .corruptCredential
        default:
            .operationFailed
        }
    }
}

enum KeychainCredentialQueryBuilder {
    static let productionServiceNamespace =
        "com.calpinlabs.rpgplayer.provider-credential.v1"

    static func validatedTestStoreIdentifier(
        _ identifier: String
    ) throws -> String {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-_")
        )
        guard identifier.isEmpty == false,
              identifier.count <= 64,
              identifier.unicodeScalars.allSatisfy(allowed.contains)
        else {
            throw ProviderCredentialError.invalidReference
        }
        return identifier
    }

    static func identityQuery(
        reference: ProviderCredentialReference,
        testStoreIdentifier: String? = nil
    ) -> [String: Any] {
        let productionService =
            "\(productionServiceNamespace).\(reference.providerID.rawValue)"
        let service = if let testStoreIdentifier {
            "\(productionService).\(testStoreIdentifier)"
        } else {
            productionService
        }
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference.accountLabel
        ]
    }

    static func addQuery(
        reference: ProviderCredentialReference,
        testStoreIdentifier: String? = nil,
        credentialData: Data
    ) -> [String: Any] {
        var query = identityQuery(
            reference: reference,
            testStoreIdentifier: testStoreIdentifier
        )
        query[kSecValueData as String] = credentialData
        query[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return query
    }

    static func existenceQuery(
        reference: ProviderCredentialReference,
        testStoreIdentifier: String? = nil
    ) -> [String: Any] {
        var query = identityQuery(
            reference: reference,
            testStoreIdentifier: testStoreIdentifier
        )
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    static func readQuery(
        reference: ProviderCredentialReference,
        testStoreIdentifier: String? = nil
    ) -> [String: Any] {
        var query = existenceQuery(
            reference: reference,
            testStoreIdentifier: testStoreIdentifier
        )
        query[kSecReturnData as String] = true
        return query
    }

    static func replacementAttributes(
        credentialData: Data
    ) -> [String: Any] {
        [
            kSecValueData as String: credentialData,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
    }
}
