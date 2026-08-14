import SwiftUI
import UIKit

@MainActor
@Observable
final class CampaignImageGenerationModel {
    struct Target: Identifiable, Hashable, Sendable {
        let recordID: String
        let fieldID: String
        let title: String

        var id: String { recordID + ":" + fieldID }
    }

    private(set) var models: [ImageGenerationModel] = []
    private(set) var isLoadingModels = false
    private(set) var isGenerating = false
    private(set) var errorText: String?
    private(set) var generatedFileURL: URL?
    private(set) var generatedAssetID: String?

    var prompt = ""
    var selectedTarget: Target?

    let targets: [Target]

    private let campaignID: UUID
    private let project: NormalizedProject
    private let projectionLoader: ProjectionLoader
    private let campaignStore: any CampaignStore
    private let routingStore: any ImageRoutingSettingsStore
    private let imageProvider: ImageRoutingProvider
    private let assetStore: any CampaignImageAssetStoring

    init(
        campaignID: UUID,
        project: NormalizedProject,
        projectionLoader: ProjectionLoader,
        campaignStore: any CampaignStore,
        routingStore: any ImageRoutingSettingsStore,
        imageProvider: ImageRoutingProvider,
        assetStore: any CampaignImageAssetStoring
    ) {
        self.campaignID = campaignID
        self.project = project
        self.projectionLoader = projectionLoader
        self.campaignStore = campaignStore
        self.routingStore = routingStore
        self.imageProvider = imageProvider
        self.assetStore = assetStore

        let builtTargets = project.records.flatMap { record in
            let fields = record.fields.isEmpty
                ? [NormalizedField(id: "asset", value: .null, extensionPayload: [:])]
                : record.fields
            return fields.map {
                Target(
                    recordID: record.id,
                    fieldID: $0.id,
                    title: "\(record.id) · \($0.id)"
                )
            }
        }
        targets = builtTargets
        selectedTarget = builtTargets.first
    }

    func load() async {
        isLoadingModels = true
        defer { isLoadingModels = false }
        do {
            let settings = try await routingStore.load()
            await imageProvider.update(settings: settings)
            models = try await imageProvider.models()
            if models.isEmpty {
                errorText = "No configured image models are available."
            } else {
                errorText = nil
            }
        } catch {
            models = []
            errorText = "Image models could not be loaded. Add an OpenAI key in Provider Settings."
        }
    }

    func generate() async {
        guard isGenerating == false else { return }
        guard let target = selectedTarget else {
            errorText = "Choose a campaign record and field to attach the image."
            return
        }
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPrompt.isEmpty == false else {
            errorText = "Describe the image you want to create."
            return
        }

        isGenerating = true
        defer { isGenerating = false }
        do {
            let settings = try await routingStore.load()
            await imageProvider.update(settings: settings)
            let request = try ImageGenerationRequest(
                prompt: trimmedPrompt,
                modelID: nil,
                count: 1
            )
            let result = try await imageProvider.generateImage(request)
            guard let generated = result.images.first else {
                throw ImageGenerationViewError.noImageReturned
            }
            let data = try await Self.data(for: generated)
            let stored = try await assetStore.store(
                data: data,
                for: campaignID,
                targetRecordID: target.recordID,
                fieldID: target.fieldID,
                format: Self.format(for: generated.url)
            )
            let projection = try await projectionLoader.load(
                campaignID: campaignID
            ).projection
            let existingAssets = try await campaignStore.importedAssets(
                for: campaignID
            )
            let event = CampaignEvent(
                id: UUID(),
                campaignID: campaignID,
                sequence: 0,
                requestID: UUID(),
                timestamp: Date(),
                schemaVersion: 1,
                payload: stored.eventPayload
            )
            _ = try await campaignStore.append(
                batch: [event],
                assets: existingAssets.contains(where: {
                    $0.assetID == stored.asset.assetID
                }) ? [] : [stored.asset],
                expectedSequence: projection.appliedThroughSequence
            )
            generatedFileURL = stored.fileURL
            generatedAssetID = stored.asset.assetID
            errorText = nil
        } catch is CancellationError {
            return
        } catch {
            errorText = "The image could not be generated or attached."
        }
    }

    private static func data(
        for image: ImageGenerationAsset
    ) async throws -> Data {
        if let data = image.data, data.isEmpty == false {
            return data
        }
        guard let url = image.url,
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false else {
            throw ImageGenerationViewError.invalidImageURL
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              data.isEmpty == false else {
            throw ImageGenerationViewError.invalidImageResponse
        }
        return data
    }

    private static func format(for url: URL?) -> GeneratedImageFormat {
        switch url?.pathExtension.lowercased() {
        case "jpg", "jpeg": .jpeg
        case "webp": .webp
        case "gif": .gif
        case "heic": .heic
        case "heif": .heif
        case "avif": .avif
        default: .png
        }
    }
}

private enum ImageGenerationViewError: Error {
    case noImageReturned
    case invalidImageURL
    case invalidImageResponse
}

@MainActor
struct ImageGenerationView: View {
    @State private var model: CampaignImageGenerationModel

    init(
        campaignID: UUID,
        project: NormalizedProject,
        projectionLoader: ProjectionLoader,
        campaignStore: any CampaignStore,
        routingStore: any ImageRoutingSettingsStore,
        imageProvider: ImageRoutingProvider,
        assetStore: any CampaignImageAssetStoring
    ) {
        _model = State(
            initialValue: CampaignImageGenerationModel(
                campaignID: campaignID,
                project: project,
                projectionLoader: projectionLoader,
                campaignStore: campaignStore,
                routingStore: routingStore,
                imageProvider: imageProvider,
                assetStore: assetStore
            )
        )
    }

    var body: some View {
        Form {
            Section {
                TextField(
                    "Describe the image",
                    text: $model.prompt,
                    axis: .vertical
                )
                .lineLimit(3...8)
                .accessibilityIdentifier("imageGenerationPrompt")

                if model.isLoadingModels {
                    ProgressView("Loading image models…")
                } else if model.models.isEmpty {
                    Text("No image models are available.")
                        .foregroundStyle(PlayerTheme.secondaryText)
                } else {
                    Picker("Model", selection: Binding(
                        get: { model.models.first?.id ?? "" },
                        set: { _ in }
                    )) {
                        ForEach(model.models) { option in
                            Text(option.displayName).tag(option.id)
                        }
                    }
                    .disabled(true)
                    .accessibilityIdentifier("imageGenerationModelPicker")
                }
            } header: {
                Text("Create an image")
            } footer: {
                Text("The selected image is saved inside this campaign and attached as a durable campaign event.")
            }
            .listRowBackground(PlayerTheme.opaquePanel)

            Section("Attach to campaign") {
                if model.targets.isEmpty {
                    Text("This project has no attachable record fields.")
                        .foregroundStyle(PlayerTheme.secondaryText)
                } else {
                    Picker(
                        "Record and field",
                        selection: Binding(
                            get: { model.selectedTarget ?? model.targets[0] },
                            set: { model.selectedTarget = $0 }
                        )
                    ) {
                        ForEach(model.targets) { target in
                            Text(target.title).tag(target)
                        }
                    }
                    .accessibilityIdentifier("imageAttachmentTargetPicker")
                }

                Button {
                    Task { await model.generate() }
                } label: {
                    Label(
                        model.isGenerating ? "Generating…" : "Generate and attach",
                        systemImage: "sparkles"
                    )
                }
                .disabled(
                    model.isGenerating
                        || model.targets.isEmpty
                        || model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .accessibilityIdentifier("generateAndAttachImageButton")
            }
            .listRowBackground(PlayerTheme.opaquePanel)

            if let generatedFileURL = model.generatedFileURL,
               let image = UIImage(contentsOfFile: generatedFileURL.path) {
                Section("Latest generated asset") {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Generated campaign image")
                    if let generatedAssetID = model.generatedAssetID {
                        Text(generatedAssetID)
                            .font(.caption.monospaced())
                            .foregroundStyle(PlayerTheme.secondaryText)
                    }
                }
                .listRowBackground(PlayerTheme.opaquePanel)
            }

            if let errorText = model.errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(PlayerTheme.secondaryText)
                    .accessibilityIdentifier("imageGenerationError")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(PlayerTheme.canvas)
        .foregroundStyle(PlayerTheme.primaryText)
        .tint(PlayerTheme.accent)
        .navigationTitle("Generate image")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("imageGenerationView")
        .task { await model.load() }
    }
}
