import Observation
import SwiftUI

struct ImageModelOption: Identifiable, Hashable {
    let selection: ImageModelSelection
    let displayName: String

    var id: ImageModelSelection { selection }
}

@MainActor
@Observable
final class ImageRoutingSettingsModel {
    private(set) var settings: ImageRoutingSettings
    private(set) var catalogs: [ProviderID: [ImageGenerationModel]] = [:]
    private(set) var isLoading = false
    private(set) var errorText: String?

    private let store: any ImageRoutingSettingsStore
    private let catalog: any ImageProviderCatalogProviding

    init(
        store: any ImageRoutingSettingsStore,
        catalog: any ImageProviderCatalogProviding
    ) {
        self.store = store
        self.catalog = catalog
        settings = .default
    }

    var options: [ImageModelOption] {
        var all = catalogs.values
            .flatMap { $0 }
            .map {
                ImageModelOption(
                    selection: ImageModelSelection(
                        providerID: $0.providerID,
                        modelID: $0.id
                    ),
                    displayName: $0.displayName
                )
            }
        let selected = [settings.primary, settings.fallback].compactMap { $0 }
        for selection in selected where all.contains(where: { $0.id == selection }) == false {
            all.append(
                ImageModelOption(
                    selection: selection,
                    displayName: selection.modelID
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
            errorText = "Saved image choices could not be read; defaults are active."
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

    func setPrimary(_ selection: ImageModelSelection) {
        settings.primary = selection
    }

    func setFallback(_ selection: ImageModelSelection?) {
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
            errorText = "Image choices could not be saved."
        }
    }
}

@MainActor
struct ImageGenerationSettingsView: View {
    @State private var model: ImageRoutingSettingsModel

    init(
        store: any ImageRoutingSettingsStore,
        catalog: any ImageProviderCatalogProviding
    ) {
        _model = State(
            initialValue: ImageRoutingSettingsModel(
                store: store,
                catalog: catalog
            )
        )
    }

    var body: some View {
        Form {
            Section {
                if model.options.isEmpty {
                    ContentUnavailableView(
                        "No Image Provider",
                        systemImage: "photo.badge.exclamationmark",
                        description: Text(
                            "Add a supported image-provider key under Provider Keys, then refresh this catalog."
                        )
                    )
                } else {
                    Picker("Primary image model", selection: primaryBinding) {
                        ForEach(model.options) { option in
                            Text(optionLabel(option)).tag(option.selection)
                        }
                    }
                    .accessibilityIdentifier("primaryImageModelPicker")

                    Picker("Fallback image model", selection: fallbackBinding) {
                        Text("None").tag(FallbackChoice.none)
                        ForEach(model.options) { option in
                            Text(optionLabel(option))
                                .tag(FallbackChoice.route(option.selection))
                        }
                    }
                    .accessibilityIdentifier("fallbackImageModelPicker")

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
                    .accessibilityIdentifier("automaticImageFallbackToggle")
                }
            } header: {
                Text("Image generation")
            } footer: {
                Text(
                    "Image generation is a separate capability from GM text generation. Generated images remain provider-owned until the campaign attaches an app-owned asset record."
                )
            }
            .listRowBackground(PlayerTheme.opaquePanel)

            Section("Catalog") {
                Button("Refresh image catalogs") {
                    Task {
                        await model.refreshCatalogs()
                        await model.save()
                    }
                }
                .disabled(model.isLoading)
                .accessibilityIdentifier("refreshImageCatalogsButton")

                if model.isLoading {
                    ProgressView("Refreshing image catalogs…")
                }
            }
            .listRowBackground(PlayerTheme.opaquePanel)

            if let errorText = model.errorText {
                Section {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(PlayerTheme.secondaryText)
                        .accessibilityIdentifier("imageSettingsError")
                }
                .listRowBackground(PlayerTheme.opaquePanel)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(PlayerTheme.canvas)
        .foregroundStyle(PlayerTheme.primaryText)
        .tint(PlayerTheme.accent)
        .navigationTitle("Images")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("imageGenerationSettingsView")
        .task {
            await model.load()
        }
    }

    private enum FallbackChoice: Hashable {
        case none
        case route(ImageModelSelection)
    }

    private var primaryBinding: Binding<ImageModelSelection> {
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

    private func optionLabel(_ option: ImageModelOption) -> String {
        "\(option.selection.providerID.settingsDisplayName) · \(option.displayName)"
    }

    private func persist() {
        Task { await model.save() }
    }
}
