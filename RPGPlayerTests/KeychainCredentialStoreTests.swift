import CryptoKit
import Foundation
import Security
import SwiftData
import Testing
@testable import RPGPlayer

struct KeychainCredentialStoreTests {
    @Test
    func referenceTrimsAccountLabelAndRejectsBlankLabels() throws {
        let reference = try ProviderCredentialReference(
            providerID: .openAI,
            accountLabel: "  work account  "
        )

        #expect(reference.providerID.rawValue == "openAI")
        #expect(reference.accountLabel == "work account")
        #expect(
            throws: ProviderCredentialError.invalidReference
        ) {
            try ProviderCredentialReference(
                providerID: .openAI,
                accountLabel: "  \n  "
            )
        }
    }

    @Test
    func queryShapesUseExactGenericPasswordIdentityAndDeviceOnlyWrites() throws {
        let testStoreIdentifier = "unit-query"
        let reference = try ProviderCredentialReference(
            providerID: .anthropic,
            accountLabel: "primary"
        )
        let secretData = Data("unit-secret".utf8)

        let identity = KeychainCredentialQueryBuilder.identityQuery(
            reference: reference,
            testStoreIdentifier: testStoreIdentifier
        )
        let add = KeychainCredentialQueryBuilder.addQuery(
            reference: reference,
            testStoreIdentifier: testStoreIdentifier,
            credentialData: secretData
        )
        let exists = KeychainCredentialQueryBuilder.existenceQuery(
            reference: reference,
            testStoreIdentifier: testStoreIdentifier
        )
        let read = KeychainCredentialQueryBuilder.readQuery(
            reference: reference,
            testStoreIdentifier: testStoreIdentifier
        )
        let replacement = KeychainCredentialQueryBuilder.replacementAttributes(
            credentialData: secretData
        )

        #expect(
            identity[kSecClass as String] as? String
                == kSecClassGenericPassword as String
        )
        #expect(
            identity[kSecAttrService as String] as? String
                == "com.calpinlabs.rpgplayer.provider-credential.v1.anthropic.unit-query"
        )
        #expect(identity[kSecAttrAccount as String] as? String == "primary")
        #expect(identity[kSecAttrAccessGroup as String] == nil)
        #expect(identity[kSecAttrSynchronizable as String] == nil)

        #expect(add[kSecValueData as String] as? Data == secretData)
        #expect(
            add[kSecAttrAccessible as String] as? String
                == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
        #expect(add[kSecAttrSynchronizable as String] == nil)

        #expect(
            exists[kSecMatchLimit as String] as? String
                == kSecMatchLimitOne as String
        )
        #expect(exists[kSecReturnData as String] == nil)
        #expect(exists[kSecReturnAttributes as String] == nil)

        #expect(read[kSecReturnData as String] as? Bool == true)
        #expect(
            read[kSecMatchLimit as String] as? String
                == kSecMatchLimitOne as String
        )

        #expect(replacement[kSecValueData as String] as? Data == secretData)
        #expect(
            replacement[kSecAttrAccessible as String] as? String
                == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
        #expect(replacement[kSecAttrSynchronizable as String] == nil)
    }

    @Test
    func blankCredentialIsRejectedWithoutCreatingAnItem() async throws {
        let fixture = try KeychainStoreFixture(providerID: .openRouter)
        defer { fixture.removeAllItems() }

        await #expect(throws: ProviderCredentialError.emptyCredential) {
            try await fixture.store.save(" \n ", for: fixture.reference)
        }
        #expect(
            try await fixture.store.exists(for: fixture.reference) == false
        )
    }

    @Test
    func duplicateSaveNeverOverwritesTheExistingDeviceOnlySecret() async throws {
        let fixture = try KeychainStoreFixture(providerID: .openAI)
        defer { fixture.removeAllItems() }

        try await fixture.store.save(
            "unit-original-secret",
            for: fixture.reference
        )
        await #expect(throws: ProviderCredentialError.alreadyExists) {
            try await fixture.store.save(
                "unit-replacement-secret",
                for: fixture.reference
            )
        }

        let storedData = try await fixture.store.credentialData(
            for: fixture.reference
        )
        #expect(storedData == Data("unit-original-secret".utf8))

        let attributes = try fixture.storedAttributes()
        #expect(
            attributes[kSecAttrAccessible as String] as? String
                == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
    }

    @Test
    func replaceUpdatesAnExactItemAndNeverUpsertsAMissingItem() async throws {
        let fixture = try KeychainStoreFixture(providerID: .gemini)
        defer { fixture.removeAllItems() }

        await #expect(throws: ProviderCredentialError.notFound) {
            try await fixture.store.replace(
                "unit-missing-secret",
                for: fixture.reference
            )
        }
        #expect(
            try await fixture.store.exists(for: fixture.reference) == false
        )

        try await fixture.store.save("unit-old-secret", for: fixture.reference)
        try await fixture.store.replace(
            "unit-new-secret",
            for: fixture.reference
        )

        #expect(
            try await fixture.store.credentialData(for: fixture.reference)
                == Data("unit-new-secret".utf8)
        )
    }

    @Test
    func deleteIsExactAndIdempotent() async throws {
        let fixture = try KeychainStoreFixture(providerID: .openAI)
        defer { fixture.removeAllItems() }
        let otherReference = try ProviderCredentialReference(
            providerID: .openAI,
            accountLabel: "secondary"
        )

        try await fixture.store.save("unit-primary", for: fixture.reference)
        try await fixture.store.save("unit-secondary", for: otherReference)

        try await fixture.store.delete(fixture.reference)
        try await fixture.store.delete(fixture.reference)

        #expect(
            try await fixture.store.exists(for: fixture.reference) == false
        )
        #expect(try await fixture.store.exists(for: otherReference))
        #expect(
            try await fixture.store.credentialData(for: otherReference)
                == Data("unit-secondary".utf8)
        )
    }

    @Test
    func settingsExistenceAndAdapterOnlyReadRemainSeparateCapabilities() async throws {
        let fixture = try KeychainStoreFixture(providerID: .anthropic)
        defer { fixture.removeAllItems() }
        let settingsStore: any ProviderCredentialSettingsStore = fixture.store
        let reader: any ProviderCredentialReader = fixture.store

        #expect(try await settingsStore.exists(for: fixture.reference) == false)
        try await settingsStore.save("unit-adapter-secret", for: fixture.reference)
        #expect(try await settingsStore.exists(for: fixture.reference))
        #expect(
            try await reader.credentialData(for: fixture.reference)
                == Data("unit-adapter-secret".utf8)
        )
    }

    @Test
    func sentinelExistsOnlyInScopedKeychainNotDefaultsOrSwiftData() async throws {
        let fixture = try KeychainStoreFixture(providerID: .openRouter)
        defer { fixture.removeAllItems() }
        let sentinel = "runtime-sentinel-\(UUID().uuidString)"
        let sentinelData = Data(sentinel.utf8)

        try await fixture.store.save(sentinel, for: fixture.reference)
        let readData = try await fixture.store.credentialData(
            for: fixture.reference
        )
        #expect(
            SHA256.hash(data: readData)
                == SHA256.hash(data: sentinelData)
        )

        let defaults = UserDefaults.standard
        let defaultsFixtureKey = "credential-audit-\(UUID().uuidString)"
        defer { defaults.removeObject(forKey: defaultsFixtureKey) }
        defaults.set(
            ["seed": ["message": "unrelated preference"]],
            forKey: defaultsFixtureKey
        )
        let persistentDomain: [String: Any]
        if let bundleIdentifier = Bundle.main.bundleIdentifier,
           let domain = defaults.persistentDomain(forName: bundleIdentifier) {
            persistentDomain = domain
        } else {
            persistentDomain = defaults.dictionaryRepresentation()
        }
        #expect(persistentDomain[defaultsFixtureKey] != nil)
        #expect(
            recursivelyContainsCredential(
                data: sentinelData,
                string: sentinel,
                in: persistentDomain
            ) == false
        )

        let container = try seededCredentialAuditContainer()
        let context = ModelContext(container)
        let eventRecords = try context.fetch(
            FetchDescriptor<CampaignEventRecord>()
        )
        let assetRecords = try context.fetch(
            FetchDescriptor<ImportedAssetRecord>()
        )
        let checkpointRecords = try context.fetch(
            FetchDescriptor<ProjectionCheckpointRecord>()
        )
        #expect(eventRecords.isEmpty == false)
        #expect(assetRecords.isEmpty == false)
        #expect(checkpointRecords.isEmpty == false)

        let textFields = eventRecords.map(\.payloadType)
            + assetRecords.flatMap {
                [$0.assetID, $0.sha256, $0.appRelativeURL]
            }
        let dataFields = eventRecords.map(\.payloadData)
            + checkpointRecords.map(\.projectionData)
        #expect(textFields.contains { $0.contains(sentinel) } == false)
        #expect(
            dataFields.contains { data in
                dataContains(data, needle: sentinelData)
            } == false
        )
    }
}

struct NetworkDiagnosticRedactorTests {
    @Test(arguments: SensitiveHeaderFixture.all)
    func sensitiveHeaderValuesAreEntirelyRedactedCaseInsensitively(
        _ fixture: SensitiveHeaderFixture
    ) {
        let redactor = NetworkDiagnosticRedactor()

        let redacted = redactor.redactedHeaders([
            fixture.name: fixture.value,
            "Content-Type": "application/json"
        ])

        #expect(redacted[fixture.name] == "<redacted>")
        #expect(redacted["Content-Type"] == "application/json")
    }

    @Test
    func exactRuntimeKnownSecretIsRedactedWhereverItOccurs() {
        let sentinel = "runtime-redaction-\(UUID().uuidString)"
        let diagnostic = "before \(sentinel) middle \(sentinel) after"

        let redacted = NetworkDiagnosticRedactor().redact(
            diagnostic,
            knownSecrets: [sentinel]
        )

        #expect(redacted.contains(sentinel) == false)
        #expect(redacted == "before <redacted> middle <redacted> after")
    }

    @Test(arguments: ProviderTokenFixture.all)
    func commonProviderTokenShapesAreFullyRedacted(
        _ fixture: ProviderTokenFixture
    ) {
        let diagnostic = "request credential=\(fixture.token) failed"

        let redacted = NetworkDiagnosticRedactor().redact(diagnostic)

        #expect(redacted.contains(fixture.token) == false)
        #expect(redacted == "request credential=<redacted> failed")
    }

    @Test
    func unrelatedDiagnosticCopyRemainsReadable() {
        let diagnostic =
            "The provider returned HTTP 429; retry after 14 seconds."

        #expect(
            NetworkDiagnosticRedactor().redact(diagnostic) == diagnostic
        )
    }
}

private struct KeychainStoreFixture {
    let store: KeychainCredentialStore
    let reference: ProviderCredentialReference
    let serviceName: String

    init(providerID: ProviderID) throws {
        let identifier = "unit-\(UUID().uuidString)"
        serviceName =
            "com.calpinlabs.rpgplayer.provider-credential.v1.\(providerID.rawValue).\(identifier)"
        store = try KeychainCredentialStore(testStoreIdentifier: identifier)
        reference = try ProviderCredentialReference(providerID: providerID)
    }

    func removeAllItems() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        SecItemDelete(query as CFDictionary)
    }

    func storedAttributes() throws -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: reference.accountLabel,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true
        ]
        query[kSecReturnData as String] = false
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            query as CFDictionary,
            &result
        )
        guard status == errSecSuccess,
              let attributes = result as? [String: Any]
        else {
            throw KeychainCredentialTestError.unavailableAttributes
        }
        return attributes
    }
}

private func seededCredentialAuditContainer() throws -> ModelContainer {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: CampaignEventRecord.self,
        ImportedAssetRecord.self,
        ProjectionCheckpointRecord.self,
        configurations: configuration
    )
    let context = ModelContext(container)
    let campaignID = UUID()
    let event = CampaignEvent(
        id: UUID(),
        campaignID: campaignID,
        sequence: 1,
        requestID: UUID(),
        timestamp: Date(timeIntervalSince1970: 1_726_000_000),
        schemaVersion: 1,
        payload: .campaignImported(
            CampaignImportedPayload(
                projectID: "credential-audit-project",
                campaignTitle: "Credential Audit Campaign",
                manifestHash: "sha256:unrelated"
            )
        )
    )
    context.insert(
        CampaignEventRecord(
            event: event,
            payloadData: try JSONEncoder().encode(event.payload)
        )
    )
    context.insert(
        ImportedAssetRecord(
            asset: ImportedAsset(
                assetID: "credential-audit-asset",
                sha256: "7f83b1657ff1fc53b92dc18148a1d65dfa13514b",
                appRelativeURL: URL(string: "ImportedAssets/audit.txt")!
            ),
            campaignID: campaignID
        )
    )
    let projection = CampaignProjection(
        campaignID: campaignID,
        campaignTitle: "Credential Audit Campaign"
    )
    let checkpoint = ProjectionCheckpoint(
        sourceSequence: 0,
        reducerSchemaVersion: CampaignReducer.reducerSchemaVersion,
        projection: projection
    )
    context.insert(
        ProjectionCheckpointRecord(
            checkpoint: checkpoint,
            projectionData: try JSONEncoder().encode(projection)
        )
    )
    try context.save()
    return container
}

private func recursivelyContainsCredential(
    data needleData: Data,
    string needleString: String,
    in value: Any
) -> Bool {
    if let string = value as? String {
        return string.contains(needleString)
    }
    if let data = value as? Data {
        return dataContains(data, needle: needleData)
    }
    if let dictionary = value as? [String: Any] {
        return dictionary.contains { key, nested in
            key.contains(needleString)
                || recursivelyContainsCredential(
                    data: needleData,
                    string: needleString,
                    in: nested
                )
        }
    }
    if let array = value as? [Any] {
        return array.contains {
            recursivelyContainsCredential(
                data: needleData,
                string: needleString,
                in: $0
            )
        }
    }
    return false
}

private func dataContains(_ data: Data, needle: Data) -> Bool {
    guard needle.isEmpty == false, data.count >= needle.count else {
        return false
    }
    return data.range(of: needle) != nil
}

private enum KeychainCredentialTestError: Error {
    case unavailableAttributes
}

struct SensitiveHeaderFixture: Sendable, CustomTestStringConvertible {
    static let all = [
        SensitiveHeaderFixture(
            name: "Authorization",
            value: "Bearer unit-authorization"
        ),
        SensitiveHeaderFixture(
            name: "proxy-authorization",
            value: "Basic unit-proxy"
        ),
        SensitiveHeaderFixture(
            name: "X-API-Key",
            value: "unit-api-key"
        ),
        SensitiveHeaderFixture(
            name: "x-goog-api-key",
            value: "unit-google-key"
        )
    ]

    let name: String
    let value: String

    var testDescription: String { name }
}

struct ProviderTokenFixture: Sendable, CustomTestStringConvertible {
    static let all = [
        ProviderTokenFixture(
            provider: "OpenAI",
            token: "sk-proj-abcdefghijklmnopqrstuvwxyz012345"
        ),
        ProviderTokenFixture(
            provider: "OpenRouter",
            token: "sk-or-v1-abcdefghijklmnopqrstuvwxyz012345"
        ),
        ProviderTokenFixture(
            provider: "Anthropic",
            token: "sk-ant-api03-abcdefghijklmnopqrstuvwxyz012345"
        ),
        ProviderTokenFixture(
            provider: "Gemini",
            token: "AIzaSyABCDEFGHIJKLMNOPQRSTUVWXYZ012345"
        )
    ]

    let provider: String
    let token: String

    var testDescription: String { provider }
}
