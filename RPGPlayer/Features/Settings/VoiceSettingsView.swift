import Observation
import SwiftUI

struct VoiceSettingsDependencies: Sendable {
    let credentialSettingsStore: any VoiceCredentialSettingsStore
    let credentialReader: any VoiceCredentialReader
    let credentialValidator: any VoiceCredentialValidator
    let routingStore: any VoiceRoutingSettingsStore
    let catalog: any VoiceCatalogProviding
}

@MainActor
@Observable
final class VoiceSettingsModel {
    private(set) var routing: VoiceRoutingSettings
    private(set) var automaticallyPlayNarration = false
    private(set) var draft = ""
    private(set) var isConfigured = false
    private(set) var statusText = "Checking this device…"
    private(set) var validationAvailability: ProviderCredentialValidationAvailability
    private(set) var validationState: ProviderCredentialValidationState
    private(set) var validationText: String
    private(set) var voices: [VoiceDescriptor] = []
    private(set) var isLoadingVoices = false
    private(set) var errorText: String?

    private let dependencies: VoiceSettingsDependencies
    private let reference: VoiceCredentialReference

    init(dependencies: VoiceSettingsDependencies) {
        self.dependencies = dependencies
        reference = try! VoiceCredentialReference(providerID: .elevenLabs)
        routing = .default
        let availability = dependencies.credentialValidator.availability(
            for: reference
        )
        validationAvailability = availability
        validationState = availability == .available ? .idle : .unavailable
        validationText = availability == .available
            ? "Ready to validate"
            : "Voice validation is not connected yet."
    }

    func load() async {
        do {
            routing = try await dependencies.routingStore.load()
        } catch {
            routing = .default
            errorText = "Saved voice choices could not be read; defaults are active."
        }
        automaticallyPlayNarration =
            SpeechPlaybackPreferences.automaticallyPlayNarration

        do {
            isConfigured = try await dependencies.credentialSettingsStore
                .exists(for: reference)
            statusText = isConfigured ? "Saved on this device" : "Not saved"
        } catch {
            statusText = "Credential status unavailable."
        }
    }

    func setProvider(_ provider: VoiceProviderID) {
        routing.provider = provider
        if provider == .elevenLabs, routing.fallback == nil {
            routing.fallback = .appleSpeech
        }
        if provider == .appleSpeech {
            routing.fallback = nil
        }
        persistRouting()
    }

    func setFallbackEnabled(_ enabled: Bool) {
        routing.automaticFallbackEnabled = enabled
        persistRouting()
    }

    func setModelID(_ modelID: String) {
        routing.modelID = modelID
        persistRouting()
    }

    func setAutomaticallyPlayNarration(_ enabled: Bool) {
        automaticallyPlayNarration = enabled
        SpeechPlaybackPreferences.setAutomaticallyPlayNarration(enabled)
    }

    func setDraft(_ value: String) {
        draft = value
        if validationState == .rejected
            || validationState == .failed
            || validationState == .saved {
            validationState = validationAvailability == .available
                ? .idle
                : .unavailable
            validationText = validationAvailability == .available
                ? "Ready to validate"
                : "Voice validation is not connected yet."
        }
    }

    func clearDraft() {
        draft = ""
    }

    func validateAndPersist() async {
        guard validationAvailability == .available else {
            validationState = .unavailable
            validationText = "Voice validation is not connected yet."
            return
        }
        let candidate = draft
        guard candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false else {
            validationState = .failed
            validationText = "Enter an ElevenLabs API key to validate."
            return
        }

        validationState = .validating
        validationText = "Validating ElevenLabs API key…"
        do {
            try await dependencies.credentialValidator.validate(
                candidate,
                for: reference
            )
            if isConfigured {
                try await dependencies.credentialSettingsStore.replace(
                    candidate,
                    for: reference
                )
            } else {
                try await dependencies.credentialSettingsStore.save(
                    candidate,
                    for: reference
                )
            }
            draft = ""
            isConfigured = true
            statusText = "Saved on this device"
            validationState = .saved
            validationText = "Validated and saved"
            errorText = nil
        } catch is CancellationError {
            validationState = .idle
            validationText = "Ready to validate"
        } catch ProviderCredentialError.validationRejected {
            validationState = .rejected
            validationText = "The ElevenLabs API key was rejected."
        } catch {
            validationState = .failed
            validationText = "The ElevenLabs API key could not be saved."
        }
    }

    func deleteCredential() async {
        do {
            try await dependencies.credentialSettingsStore.delete(reference)
            draft = ""
            isConfigured = false
            statusText = "Not saved"
            validationState = validationAvailability == .available
                ? .idle
                : .unavailable
            validationText = validationAvailability == .available
                ? "Ready to validate"
                : "Voice validation is not connected yet."
            voices = []
        } catch {
            validationState = .failed
            validationText = "The saved ElevenLabs API key could not be removed."
        }
    }

    func refreshVoices() async {
        guard isConfigured else {
            errorText = "Validate an ElevenLabs key before browsing voices."
            return
        }
        isLoadingVoices = true
        errorText = nil
        defer { isLoadingVoices = false }
        do {
            voices = try await dependencies.catalog.voices()
        } catch {
            errorText = "ElevenLabs voices could not be loaded."
        }
    }

    private func persistRouting() {
        let settings = routing
        Task {
            do {
                try await dependencies.routingStore.save(settings)
            } catch {
                errorText = "Voice choices could not be saved."
            }
        }
    }
}

@MainActor
struct VoiceSettingsView: View {
    @State private var model: VoiceSettingsModel
    @State private var isDeleteConfirmationPresented = false

    init(dependencies: VoiceSettingsDependencies) {
        _model = State(
            initialValue: VoiceSettingsModel(dependencies: dependencies)
        )
    }

    var body: some View {
        Form {
            Section {
                Picker(
                    "Voice provider",
                    selection: Binding(
                        get: { model.routing.provider },
                        set: { model.setProvider($0) }
                    )
                ) {
                    Text("Apple Speech").tag(VoiceProviderID.appleSpeech)
                    Text("ElevenLabs").tag(VoiceProviderID.elevenLabs)
                }
                .accessibilityIdentifier("voiceProviderPicker")

                if model.routing.provider == .elevenLabs {
                    Picker(
                        "ElevenLabs model",
                        selection: Binding(
                            get: { model.routing.modelID },
                            set: { model.setModelID($0) }
                        )
                    ) {
                        ForEach(VoiceModelCatalog.elevenLabs, id: \.id) { option in
                            Text(option.displayName).tag(option.id)
                        }
                    }
                    .accessibilityIdentifier("elevenLabsSpeechModelPicker")

                    Toggle(
                        "Use Apple Speech if ElevenLabs fails",
                        isOn: Binding(
                            get: { model.routing.automaticFallbackEnabled },
                            set: { model.setFallbackEnabled($0) }
                        )
                    )
                    .accessibilityIdentifier("appleSpeechFallbackToggle")
                }

                Toggle(
                    "Automatically play new narration",
                    isOn: Binding(
                        get: { model.automaticallyPlayNarration },
                        set: { model.setAutomaticallyPlayNarration($0) }
                    )
                )
                .accessibilityIdentifier("automaticNarrationPlaybackToggle")
            } header: {
                Text("Speech provider")
            } footer: {
                Text(
                    "Apple Speech is the offline provider option. ElevenLabs uses your own key and remains optional; voice assignments are campaign-scoped."
                )
            }
            .listRowBackground(PlayerTheme.opaquePanel)

            Section("ElevenLabs key") {
                SecureField("ElevenLabs API key", text: Binding(
                    get: { model.draft },
                    set: { model.setDraft($0) }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .privacySensitive()
                .disabled(model.validationState == .validating)
                .accessibilityIdentifier("voiceAPIKeyField-elevenLabs")

                Text(model.statusText)
                    .font(.footnote)
                    .foregroundStyle(PlayerTheme.secondaryText)
                    .accessibilityIdentifier("voiceCredentialStatus-elevenLabs")

                Text(model.validationText)
                    .font(.footnote)
                    .foregroundStyle(PlayerTheme.secondaryText)
                    .accessibilityIdentifier("voiceValidationState-elevenLabs")

                Button("Clear entered API key") {
                    model.clearDraft()
                }
                .disabled(
                    model.draft.isEmpty
                        || model.validationState == .validating
                )

                Button(
                    model.isConfigured
                        ? "Validate and Replace"
                        : "Validate and Save"
                ) {
                    Task { await model.validateAndPersist() }
                }
                .disabled(
                    model.validationAvailability == .unavailable
                        || model.validationState == .validating
                        || model.draft.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                )
                .accessibilityIdentifier("validateVoiceCredential-elevenLabs")

                Button("Remove saved API key", role: .destructive) {
                    isDeleteConfirmationPresented = true
                }
                .disabled(
                    model.isConfigured
                        == false
                        || model.validationState == .validating
                )
            }
            .listRowBackground(PlayerTheme.opaquePanel)

            Section {
                Button("Refresh ElevenLabs voices") {
                    Task { await model.refreshVoices() }
                }
                .disabled(model.isConfigured == false || model.isLoadingVoices)
                .accessibilityIdentifier("refreshElevenLabsVoicesButton")

                if model.isLoadingVoices {
                    ProgressView("Loading voices…")
                } else if model.voices.isEmpty {
                    Text("No voices loaded yet.")
                        .foregroundStyle(PlayerTheme.secondaryText)
                } else {
                    ForEach(model.voices) { voice in
                        LabeledContent(
                            voice.displayName,
                            value: voice.language ?? "Language not specified"
                        )
                    }
                }
            } header: {
                Text("Available voices")
            } footer: {
                Text(
                    "Voice browsing is read-only here. Campaign voice assignments are saved as campaign events so recovery exports can preserve them without including credentials."
                )
            }
            .listRowBackground(PlayerTheme.opaquePanel)

            if let errorText = model.errorText {
                Section {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(PlayerTheme.secondaryText)
                        .accessibilityIdentifier("voiceSettingsError")
                }
                .listRowBackground(PlayerTheme.opaquePanel)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(PlayerTheme.canvas)
        .foregroundStyle(PlayerTheme.primaryText)
        .tint(PlayerTheme.accent)
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("voiceSettingsView")
        .task {
            await model.load()
        }
        .alert(
            "Remove ElevenLabs API key?",
            isPresented: $isDeleteConfirmationPresented
        ) {
            Button("Remove API Key", role: .destructive) {
                Task { await model.deleteCredential() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the ElevenLabs key saved on this device.")
        }
    }
}
