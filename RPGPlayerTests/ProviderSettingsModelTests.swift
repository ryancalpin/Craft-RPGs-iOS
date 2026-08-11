import Foundation
import Security
import Testing
@testable import RPGPlayer

@MainActor
struct ProviderSettingsModelTests {
    @Test
    func validationCompletesBeforeTheFirstCredentialIsSaved() async throws {
        let fixture = try SettingsKeychainFixture(providerID: .openAI)
        defer { fixture.removeAllItems() }
        let observation = ValidationObservation()
        let validator = TestProviderCredentialValidator { _, reference in
            await observation.record(
                credentialExisted: try await fixture.store.exists(
                    for: reference
                )
            )
        }
        let model = ProviderSettingsModel(
            store: fixture.store,
            validator: validator
        )
        await model.load()
        model.setDraft("unit-valid-key", for: .openAI)

        await model.validateAndPersist(for: .openAI)

        #expect(await observation.existenceSnapshots == [false])
        #expect(try await fixture.store.exists(for: fixture.reference))
        #expect(model.state(for: .openAI).isConfigured)
    }

    @Test
    func rejectedInitialValidationStoresNothing() async throws {
        let fixture = try SettingsKeychainFixture(providerID: .openRouter)
        defer { fixture.removeAllItems() }
        let model = ProviderSettingsModel(
            store: fixture.store,
            validator: TestProviderCredentialValidator.rejecting
        )
        await model.load()
        model.setDraft("unit-rejected-key", for: .openRouter)

        await model.validateAndPersist(for: .openRouter)

        #expect(
            try await fixture.store.exists(for: fixture.reference) == false
        )
        let state = model.state(for: .openRouter)
        #expect(state.isConfigured == false)
        #expect(state.validationState == .rejected)
        #expect(state.draft == "unit-rejected-key")
    }

    @Test
    func rejectedReplacementPreservesTheExistingKnownGoodSecret() async throws {
        let fixture = try SettingsKeychainFixture(providerID: .anthropic)
        defer { fixture.removeAllItems() }
        try await fixture.store.save("unit-known-good", for: fixture.reference)
        let model = ProviderSettingsModel(
            store: fixture.store,
            validator: TestProviderCredentialValidator.rejecting
        )
        await model.load()
        model.setDraft("unit-rejected-replacement", for: .anthropic)

        await model.validateAndPersist(for: .anthropic)

        #expect(
            try await fixture.store.credentialData(for: fixture.reference)
                == Data("unit-known-good".utf8)
        )
        let state = model.state(for: .anthropic)
        #expect(state.isConfigured)
        #expect(state.validationState == .rejected)
    }

    @Test
    func unavailableValidationCannotSave() async throws {
        let fixture = try SettingsKeychainFixture(providerID: .gemini)
        defer { fixture.removeAllItems() }
        let model = ProviderSettingsModel(
            store: fixture.store,
            validator: UnavailableProviderCredentialValidator()
        )
        await model.load()
        model.setDraft("unit-never-stored", for: .gemini)

        await model.validateAndPersist(for: .gemini)

        #expect(
            try await fixture.store.exists(for: fixture.reference) == false
        )
        let state = model.state(for: .gemini)
        #expect(state.validationAvailability == .unavailable)
        #expect(state.validationState == .unavailable)
    }

    @Test
    func successfulSaveClearsTheActiveDraftAndReportsDeviceStorage() async throws {
        let fixture = try SettingsKeychainFixture(providerID: .openAI)
        defer { fixture.removeAllItems() }
        let model = ProviderSettingsModel(
            store: fixture.store,
            validator: TestProviderCredentialValidator.accepting
        )
        await model.load()
        model.setDraft("unit-clear-after-save", for: .openAI)

        await model.validateAndPersist(for: .openAI)

        let state = model.state(for: .openAI)
        #expect(state.draft.isEmpty)
        #expect(state.isConfigured)
        #expect(state.statusText == "Saved on this device")
        #expect(state.validationState == .saved)
    }

    @Test
    func successfulReplacementClearsTheDraftAndReplacesTheExactSecret() async throws {
        let fixture = try SettingsKeychainFixture(providerID: .openRouter)
        defer { fixture.removeAllItems() }
        try await fixture.store.save("unit-old-key", for: fixture.reference)
        let model = ProviderSettingsModel(
            store: fixture.store,
            validator: TestProviderCredentialValidator.accepting
        )
        await model.load()
        model.setDraft("unit-new-key", for: .openRouter)

        await model.validateAndPersist(for: .openRouter)

        #expect(
            try await fixture.store.credentialData(for: fixture.reference)
                == Data("unit-new-key".utf8)
        )
        let state = model.state(for: .openRouter)
        #expect(state.draft.isEmpty)
        #expect(state.isConfigured)
    }

    @Test
    func deletingSavedCredentialClearsDraftAndConfiguredState() async throws {
        let fixture = try SettingsKeychainFixture(providerID: .gemini)
        defer { fixture.removeAllItems() }
        try await fixture.store.save("unit-delete-key", for: fixture.reference)
        let model = ProviderSettingsModel(
            store: fixture.store,
            validator: TestProviderCredentialValidator.accepting
        )
        await model.load()
        model.setDraft("unit-unsaved-draft", for: .gemini)

        await model.delete(for: .gemini)

        #expect(
            try await fixture.store.exists(for: fixture.reference) == false
        )
        let state = model.state(for: .gemini)
        #expect(state.isConfigured == false)
        #expect(state.draft.isEmpty)
        #expect(state.statusText == "Not saved")
    }

    @Test
    func clearingDraftsNeverDeletesSavedCredentials() async throws {
        let fixture = try SettingsKeychainFixture(providerID: .anthropic)
        defer { fixture.removeAllItems() }
        try await fixture.store.save("unit-persisted-key", for: fixture.reference)
        let model = ProviderSettingsModel(
            store: fixture.store,
            validator: TestProviderCredentialValidator.accepting
        )
        await model.load()
        model.setDraft("unit-ephemeral-draft", for: .anthropic)

        model.clearDrafts()

        #expect(model.state(for: .anthropic).draft.isEmpty)
        #expect(try await fixture.store.exists(for: fixture.reference))
    }

    @Test
    func disappearingDuringSuspendedValidationCancelsBeforeSaveAndClearsDraft() async throws {
        let fixture = try SettingsKeychainFixture(providerID: .openAI)
        defer { fixture.removeAllItems() }
        let gate = SuspendedValidationGate()
        let model = ProviderSettingsModel(
            store: fixture.store,
            validator: SuspendedProviderCredentialValidator(gate: gate)
        )
        await model.load()
        model.setDraft("unit-cancelled-key", for: .openAI)

        let validationTask = model.startValidation(for: .openAI)
        await gate.waitUntilValidationStarts()
        model.cancelValidationsAndClearDrafts()
        await gate.resumeValidation()
        await validationTask.value

        #expect(
            try await fixture.store.exists(for: fixture.reference) == false
        )
        #expect(model.state(for: .openAI).draft.isEmpty)
    }
}

private struct TestProviderCredentialValidator:
    ProviderCredentialValidator,
    Sendable
{
    let validation: @Sendable (
        String,
        ProviderCredentialReference
    ) async throws -> Void

    init(
        validation: @escaping @Sendable (
            String,
            ProviderCredentialReference
        ) async throws -> Void
    ) {
        self.validation = validation
    }

    static let accepting = TestProviderCredentialValidator { _, _ in }
    static let rejecting = TestProviderCredentialValidator { _, _ in
        throw ProviderCredentialError.validationRejected
    }

    func availability(
        for reference: ProviderCredentialReference
    ) -> ProviderCredentialValidationAvailability {
        .available
    }

    func validate(
        _ candidate: String,
        for reference: ProviderCredentialReference
    ) async throws {
        try await validation(candidate, reference)
    }
}

private actor ValidationObservation {
    private(set) var existenceSnapshots: [Bool] = []

    func record(credentialExisted: Bool) {
        existenceSnapshots.append(credentialExisted)
    }
}

private struct SuspendedProviderCredentialValidator:
    ProviderCredentialValidator,
    Sendable
{
    let gate: SuspendedValidationGate

    func availability(
        for reference: ProviderCredentialReference
    ) -> ProviderCredentialValidationAvailability {
        .available
    }

    func validate(
        _ candidate: String,
        for reference: ProviderCredentialReference
    ) async throws {
        await gate.suspendValidation()
    }
}

private actor SuspendedValidationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var didStart = false

    func suspendValidation() async {
        didStart = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilValidationStarts() async {
        while didStart == false {
            await Task.yield()
        }
    }

    func resumeValidation() {
        continuation?.resume()
        continuation = nil
    }
}

private struct SettingsKeychainFixture {
    let store: KeychainCredentialStore
    let reference: ProviderCredentialReference
    let serviceName: String

    init(providerID: ProviderID) throws {
        let identifier = "settings-\(UUID().uuidString)"
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
}
