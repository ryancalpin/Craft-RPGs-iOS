import Observation
import SwiftUI

struct TextModelOption: Identifiable, Hashable {
    let selection: TextModelSelection
    let displayName: String
    let supportsTools: Bool
    let supportsStructuredOutput: Bool

    var id: TextModelSelection { selection }
}

@MainActor
@Observable
final class ModelRoutingSettingsModel {
    private(set) var settings: ModelRoutingSettings
    private(set) var catalogs: [ProviderID: [ProviderModel]] = [:]
    private(set) var isLoading = false
    private(set) var errorText: String?

    private let store: any ModelRoutingSettingsStore
    private let catalog: any ProviderModelCatalogProviding

    init(
        store: any ModelRoutingSettingsStore,
        catalog: any ProviderModelCatalogProviding
    ) {
        self.store = store
        self.catalog = catalog
        settings = .default
    }

    var options: [TextModelOption] {
        var all = catalogs.values
            .flatMap { $0 }
            .filter { $0.supportsTools && $0.supportsStructuredOutput }
            .map {
                TextModelOption(
                    selection: TextModelSelection(
                        providerID: $0.providerID,
                        modelID: $0.id
                    ),
                    displayName: $0.displayName,
                    supportsTools: $0.supportsTools,
                    supportsStructuredOutput: $0.supportsStructuredOutput
                )
            }
        let selected = [settings.primary, settings.fallback].compactMap { $0 }
        for selection in selected where all.contains(where: { $0.id == selection }) == false {
            all.append(
                TextModelOption(
                    selection: selection,
                    displayName: selection.modelID,
                    supportsTools: true,
                    supportsStructuredOutput: true
                )
            )
        }
        return all.sorted {
            if $0.selection.providerID.rawValue == $1.selection.providerID.rawValue {
                return $0.displayName.localizedStandardCompare($1.displayName)
                    == .orderedAscending
            }
            return $0.selection.providerID.rawValue < $1.selection.providerID.rawValue
        }
    }

    func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            settings = try await store.load()
        } catch {
            settings = .default
            errorText = "Saved model choices could not be read; defaults are active."
        }
        await refreshCatalogs()
    }

    func refreshCatalogs() async {
        isLoading = true
        defer { isLoading = false }
        for providerID in ProviderID.allCases {
            catalogs[providerID] = await catalog.models(for: providerID)
        }
    }

    func setPrimary(_ selection: TextModelSelection) {
        settings.primary = selection
    }

    func setFallback(_ selection: TextModelSelection?) {
        settings.fallback = selection == settings.primary ? nil : selection
    }

    func setAutomaticFallbackEnabled(_ enabled: Bool) {
        settings.automaticFallbackEnabled = enabled
    }

    func save() async {
        do {
            try await store.save(settings)
            errorText = nil
        } catch {
            errorText = "Model choices could not be saved."
        }
    }
}

@MainActor
struct AIModelSettingsView: View {
    @State private var model: ModelRoutingSettingsModel

    init(
        store: any ModelRoutingSettingsStore,
        catalog: any ProviderModelCatalogProviding
    ) {
        _model = State(
            initialValue: ModelRoutingSettingsModel(
                store: store,
                catalog: catalog
            )
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Primary model", selection: primaryBinding) {
                    ForEach(model.options) { option in
                        Text(optionLabel(option))
                            .tag(option.selection)
                    }
                }
                .accessibilityIdentifier("primaryTextModelPicker")

                Picker("Fallback model", selection: fallbackBinding) {
                    Text("None").tag(FallbackChoice.none)
                    ForEach(model.options) { option in
                        Text(optionLabel(option))
                            .tag(FallbackChoice.route(option.selection))
                    }
                }
                .accessibilityIdentifier("fallbackTextModelPicker")

                Toggle(
                    "Automatically use fallback",
                    isOn: Binding(
                        get: { model.settings.automaticFallbackEnabled },
                        set: {
                            model.setAutomaticFallbackEnabled($0)
                            persist()
                        }
                    )
                )
                .accessibilityIdentifier("automaticTextFallbackToggle")
            } header: {
                Text("Turn generation")
            } footer: {
                Text(
                    "Fallback is used for connectivity, rate limits, service failures, or exhausted quota before any story content is emitted. Invalid keys, safety refusals, malformed responses, and cancellations stay visible."
                )
            }
            .listRowBackground(PlayerTheme.opaquePanel)

            Section("Available catalogs") {
                if model.isLoading && model.options.isEmpty {
                    ProgressView("Loading model catalogs…")
                }
                ForEach(ProviderID.allCases, id: \.self) { providerID in
                    LabeledContent(
                        providerID.settingsDisplayName,
                        value: "\(model.catalogs[providerID]?.count ?? 0) models"
                    )
                }
                Button("Refresh model catalogs") {
                    Task {
                        await model.refreshCatalogs()
                        await model.save()
                    }
                }
                .disabled(model.isLoading)
                .accessibilityIdentifier("refreshModelCatalogsButton")
            }
            .listRowBackground(PlayerTheme.opaquePanel)

            if let errorText = model.errorText {
                Section {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(PlayerTheme.secondaryText)
                        .accessibilityIdentifier("modelSettingsError")
                }
                .listRowBackground(PlayerTheme.opaquePanel)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(PlayerTheme.canvas)
        .foregroundStyle(PlayerTheme.primaryText)
        .tint(PlayerTheme.accent)
        .navigationTitle("AI Models")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("aiModelSettingsView")
        .task {
            await model.load()
        }
    }

    private enum FallbackChoice: Hashable {
        case none
        case route(TextModelSelection)
    }

    private var primaryBinding: Binding<TextModelSelection> {
        Binding(
            get: { model.settings.primary },
            set: {
                model.setPrimary($0)
                persist()
            }
        )
    }

    private var fallbackBinding: Binding<FallbackChoice> {
        Binding(
            get: {
                guard let fallback = model.settings.fallback else { return .none }
                return .route(fallback)
            },
            set: {
                switch $0 {
                case .none:
                    model.setFallback(nil)
                case .route(let selection):
                    model.setFallback(selection)
                }
                persist()
            }
        )
    }

    private func optionLabel(_ option: TextModelOption) -> String {
        "\(option.selection.providerID.settingsDisplayName) · \(option.displayName)"
    }

    private func persist() {
        Task { await model.save() }
    }
}
