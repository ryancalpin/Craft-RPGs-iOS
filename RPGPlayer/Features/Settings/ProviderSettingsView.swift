import Observation
import SwiftUI

enum ProviderCredentialValidationState: Equatable, Sendable {
    case idle
    case unavailable
    case validating
    case rejected
    case saved
    case failed
}

struct ProviderCredentialSettingsState: Identifiable, Equatable, Sendable {
    var id: String { providerID.rawValue }

    let providerID: ProviderID
    var draft: String
    var isConfigured: Bool
    var statusText: String
    var validationAvailability: ProviderCredentialValidationAvailability
    var validationState: ProviderCredentialValidationState
    var validationText: String
}

@MainActor
@Observable
final class ProviderSettingsModel {
    private(set) var states: [ProviderCredentialSettingsState]

    private let store: any ProviderCredentialSettingsStore
    private let validator: any ProviderCredentialValidator
    @ObservationIgnored
    private var validationTasks: [String: Task<Void, Never>] = [:]

    init(
        store: any ProviderCredentialSettingsStore,
        validator: any ProviderCredentialValidator
    ) {
        self.store = store
        self.validator = validator
        states = ProviderID.allCases.map { providerID in
            let reference = Self.primaryReference(for: providerID)
            let availability = validator.availability(for: reference)
            return ProviderCredentialSettingsState(
                providerID: providerID,
                draft: "",
                isConfigured: false,
                statusText: "Checking this device…",
                validationAvailability: availability,
                validationState: availability == .available
                    ? .idle
                    : .unavailable,
                validationText: availability == .available
                    ? "Ready to validate"
                    : "Provider validation is not connected yet."
            )
        }
    }

    func state(
        for providerID: ProviderID
    ) -> ProviderCredentialSettingsState {
        guard let state = states.first(where: {
            $0.providerID.rawValue == providerID.rawValue
        }) else {
            preconditionFailure("Missing closed provider settings state")
        }
        return state
    }

    func load() async {
        for providerID in ProviderID.allCases {
            let reference = Self.primaryReference(for: providerID)
            do {
                let isConfigured = try await store.exists(for: reference)
                updateState(for: providerID) { state in
                    state.isConfigured = isConfigured
                    state.statusText = isConfigured
                        ? "Saved on this device"
                        : "Not saved"
                }
            } catch {
                updateState(for: providerID) { state in
                    state.statusText = "Credential status unavailable."
                }
            }
        }
    }

    func setDraft(_ draft: String, for providerID: ProviderID) {
        updateState(for: providerID) { state in
            state.draft = draft
            if state.validationState == .rejected
                || state.validationState == .failed
                || state.validationState == .saved {
                state.validationState = state.validationAvailability == .available
                    ? .idle
                    : .unavailable
                state.validationText = state.validationAvailability == .available
                    ? "Ready to validate"
                    : "Provider validation is not connected yet."
            }
        }
    }

    func clearDraft(for providerID: ProviderID) {
        updateState(for: providerID) { state in
            state.draft = ""
        }
    }

    func clearDrafts() {
        for index in states.indices {
            states[index].draft = ""
        }
    }

    @discardableResult
    func startValidation(
        for providerID: ProviderID
    ) -> Task<Void, Never> {
        let key = providerID.rawValue
        validationTasks[key]?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.validateAndPersist(for: providerID)
        }
        validationTasks[key] = task
        return task
    }

    func cancelValidationsAndClearDrafts() {
        for task in validationTasks.values {
            task.cancel()
        }
        validationTasks.removeAll()
        clearDrafts()
    }

    func validateAndPersist(for providerID: ProviderID) async {
        let current = state(for: providerID)
        guard current.validationAvailability == .available else {
            updateState(for: providerID) { state in
                state.validationState = .unavailable
                state.validationText =
                    "Provider validation is not connected yet."
            }
            return
        }
        guard current.validationState != .validating else { return }

        let candidate = current.draft
        let reference = Self.primaryReference(for: providerID)
        updateState(for: providerID) { state in
            state.validationState = .validating
            state.validationText = "Validating API key…"
        }

        do {
            try Task.checkCancellation()
            try await validator.validate(candidate, for: reference)
            try Task.checkCancellation()
            if current.isConfigured {
                try await store.replace(candidate, for: reference)
            } else {
                try await store.save(candidate, for: reference)
            }
            updateState(for: providerID) { state in
                state.draft = ""
                state.isConfigured = true
                state.statusText = "Saved on this device"
                state.validationState = .saved
                state.validationText = "Validated and saved"
            }
        } catch is CancellationError {
            updateState(for: providerID) { state in
                state.validationState = state.validationAvailability == .available
                    ? .idle
                    : .unavailable
                state.validationText = state.validationAvailability == .available
                    ? "Ready to validate"
                    : "Provider validation is not connected yet."
            }
        } catch ProviderCredentialError.validationUnavailable {
            updateState(for: providerID) { state in
                state.validationState = .unavailable
                state.validationText =
                    "Provider validation is not connected yet."
            }
        } catch ProviderCredentialError.validationRejected {
            updateState(for: providerID) { state in
                state.validationState = .rejected
                state.validationText = "The API key was rejected."
            }
        } catch ProviderCredentialError.emptyCredential {
            updateState(for: providerID) { state in
                state.validationState = .failed
                state.validationText = "Enter an API key to validate."
            }
        } catch {
            updateState(for: providerID) { state in
                state.validationState = .failed
                state.validationText = "The API key could not be saved."
            }
        }
    }

    func delete(for providerID: ProviderID) async {
        let reference = Self.primaryReference(for: providerID)
        do {
            try await store.delete(reference)
            updateState(for: providerID) { state in
                state.draft = ""
                state.isConfigured = false
                state.statusText = "Not saved"
                state.validationState = state.validationAvailability == .available
                    ? .idle
                    : .unavailable
                state.validationText = state.validationAvailability == .available
                    ? "Ready to validate"
                    : "Provider validation is not connected yet."
            }
        } catch {
            updateState(for: providerID) { state in
                state.validationState = .failed
                state.validationText = "The saved API key could not be removed."
            }
        }
    }

    private func updateState(
        for providerID: ProviderID,
        _ update: (inout ProviderCredentialSettingsState) -> Void
    ) {
        guard let index = states.firstIndex(where: {
            $0.providerID.rawValue == providerID.rawValue
        }) else {
            preconditionFailure("Missing closed provider settings state")
        }
        update(&states[index])
    }

    private static func primaryReference(
        for providerID: ProviderID
    ) -> ProviderCredentialReference {
        do {
            return try ProviderCredentialReference(providerID: providerID)
        } catch {
            preconditionFailure("The primary account reference must be valid")
        }
    }
}

@MainActor
struct ProviderSettingsView: View {
    @State private var model: ProviderSettingsModel
    @State private var pendingDeletion: ProviderID?

    init(
        store: any ProviderCredentialSettingsStore,
        validator: any ProviderCredentialValidator,
        modelRoutingStore: (any ModelRoutingSettingsStore)? = nil,
        providerModelCatalog: (any ProviderModelCatalogProviding)? = nil,
        imageRoutingStore: (any ImageRoutingSettingsStore)? = nil,
        imageProviderCatalog: (any ImageProviderCatalogProviding)? = nil,
        voiceSettings: VoiceSettingsDependencies? = nil
    ) {
        _model = State(
            initialValue: ProviderSettingsModel(
                store: store,
                validator: validator
            )
        )
        self.modelRoutingStore = modelRoutingStore
        self.providerModelCatalog = providerModelCatalog
        self.imageRoutingStore = imageRoutingStore
        self.imageProviderCatalog = imageProviderCatalog
        self.voiceSettings = voiceSettings
    }

    private let modelRoutingStore: (any ModelRoutingSettingsStore)?
    private let providerModelCatalog: (any ProviderModelCatalogProviding)?
    private let imageRoutingStore: (any ImageRoutingSettingsStore)?
    private let imageProviderCatalog: (any ImageProviderCatalogProviding)?
    private let voiceSettings: VoiceSettingsDependencies?

    var body: some View {
        Form {
            if let modelRoutingStore,
               let providerModelCatalog,
               let imageRoutingStore,
               let imageProviderCatalog {
                Section("Capabilities") {
                    NavigationLink {
                        AIModelSettingsView(
                            store: modelRoutingStore,
                            catalog: providerModelCatalog
                        )
                    } label: {
                        Label("AI Models", systemImage: "cpu")
                    }
                    .accessibilityIdentifier("aiModelsSettingsLink")

                    NavigationLink {
                        ImageGenerationSettingsView(
                            store: imageRoutingStore,
                            catalog: imageProviderCatalog
                        )
                    } label: {
                        Label("Images", systemImage: "photo.on.rectangle")
                    }
                    .accessibilityIdentifier("imageSettingsLink")

                    if let voiceSettings {
                        NavigationLink {
                            VoiceSettingsView(dependencies: voiceSettings)
                        } label: {
                            Label("Voice", systemImage: "waveform")
                        }
                        .accessibilityIdentifier("voiceSettingsLink")
                    }
                }
                .listRowBackground(PlayerTheme.opaquePanel)
            }

            Section {
                Text(
                    "Keys are stored in this device’s Keychain and are never included in campaign recovery bundles."
                )
                .font(.footnote)
                .foregroundStyle(PlayerTheme.secondaryText)
            } header: {
                Text("Provider Keys")
            }
            .listRowBackground(PlayerTheme.opaquePanel)

            ForEach(model.states) { state in
                providerSection(state)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(PlayerTheme.canvas)
        .foregroundStyle(PlayerTheme.primaryText)
        .tint(PlayerTheme.accent)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("providerSettingsView")
        .task {
            await model.load()
        }
        .onDisappear {
            model.cancelValidationsAndClearDrafts()
        }
        .alert(
            deletionTitle,
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { isPresented in
                    if isPresented == false {
                        pendingDeletion = nil
                    }
                }
            )
        ) {
            Button("Remove API Key", role: .destructive) {
                guard let providerID = pendingDeletion else { return }
                pendingDeletion = nil
                Task {
                    await model.delete(for: providerID)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the API key saved on this device.")
        }
    }

    @ViewBuilder
    private func providerSection(
        _ state: ProviderCredentialSettingsState
    ) -> some View {
        Section(state.providerID.settingsDisplayName) {
            APIKeyField(
                providerID: state.providerID,
                text: Binding(
                    get: { model.state(for: state.providerID).draft },
                    set: { model.setDraft($0, for: state.providerID) }
                ),
                isDisabled: state.validationState == .validating
            )

            Text(state.statusText)
                .font(.footnote)
                .foregroundStyle(PlayerTheme.secondaryText)
                .accessibilityIdentifier(
                    "providerCredentialStatus-\(state.providerID.rawValue)"
                )

            Text(state.validationText)
                .font(.footnote)
                .foregroundStyle(PlayerTheme.secondaryText)
                .accessibilityIdentifier(
                    "providerValidationState-\(state.providerID.rawValue)"
                )

            if state.validationState == .validating {
                ProgressView("Validating API key…")
                    .tint(PlayerTheme.accent)
                    .accessibilityLabel(
                        "Validating \(state.providerID.settingsDisplayName) API key"
                    )
            }

            Button("Clear entered API key") {
                model.clearDraft(for: state.providerID)
            }
            .disabled(
                state.draft.isEmpty
                    || state.validationState == .validating
            )
            .accessibilityIdentifier(
                "clearAPIKey-\(state.providerID.rawValue)"
            )
            .accessibilityLabel(
                "Clear \(state.providerID.settingsDisplayName) API key"
            )

            Button(
                state.isConfigured
                    ? "Validate and Replace"
                    : "Validate and Save"
            ) {
                model.startValidation(for: state.providerID)
            }
            .disabled(
                state.validationAvailability == .unavailable
                    || state.validationState == .validating
                    || state.draft.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
            )
            .accessibilityIdentifier(
                "validateProviderCredential-\(state.providerID.rawValue)"
            )
            .accessibilityLabel(
                state.isConfigured
                    ? "Validate and Replace \(state.providerID.settingsDisplayName) API key"
                    : "Validate and Save \(state.providerID.settingsDisplayName) API key"
            )

            Button("Remove saved API key", role: .destructive) {
                pendingDeletion = state.providerID
            }
            .disabled(
                state.isConfigured == false
                    || state.validationState == .validating
            )
            .foregroundStyle(.red)
            .accessibilityIdentifier(
                "deleteProviderCredential-\(state.providerID.rawValue)"
            )
            .accessibilityLabel(
                "Remove saved \(state.providerID.settingsDisplayName) API key"
            )
        }
        .listRowBackground(PlayerTheme.opaquePanel)
    }

    private var deletionTitle: String {
        let displayName = pendingDeletion?.settingsDisplayName ?? "Provider"
        return "Remove \(displayName) API key?"
    }
}
