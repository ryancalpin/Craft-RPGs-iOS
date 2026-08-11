import Observation
import SwiftUI
import UniformTypeIdentifiers

struct CampaignLibraryItem: Identifiable, Equatable, Sendable {
    let summary: CampaignSummary
    let currentSceneTitle: String?

    var id: UUID { summary.campaignID }
}

@MainActor
@Observable
final class CampaignLibraryModel {
    private(set) var campaigns: [CampaignLibraryItem] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let store: any CampaignStore
    private let projectionLoader: ProjectionLoader

    init(store: any CampaignStore, projectionLoader: ProjectionLoader) {
        self.store = store
        self.projectionLoader = projectionLoader
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let summaries = try await store.campaigns()
            var items: [CampaignLibraryItem] = []
            for summary in summaries {
                let projection = try await projectionLoader.load(
                    campaignID: summary.campaignID
                ).projection
                items.append(
                    CampaignLibraryItem(
                        summary: summary,
                        currentSceneTitle: projection.currentScene?.title
                    )
                )
            }
            campaigns = items
            errorMessage = nil
        } catch {
            errorMessage = "Campaigns could not be loaded."
        }
    }

    func contains(_ campaignID: UUID) -> Bool {
        campaigns.contains { $0.id == campaignID }
    }
}

@MainActor
struct CampaignLibraryView: View {
    @State private var presentedSheet: ImportSheetDestination?
    @State private var isRecoveryImporterPresented = false
    @State private var isRestoring = false
    @State private var recoveryErrorMessage: String?

    let model: CampaignLibraryModel
    let importCoordinator: ImportCoordinator
    let recoveryBundleReader: RecoveryBundleReader
    let openProviderSettings: @MainActor () -> Void
    let openCampaign: @MainActor (UUID) -> Void

    var body: some View {
        List {
            Section("Campaigns") {
                if model.isLoading, model.campaigns.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(PlayerTheme.accent)
                            .accessibilityIdentifier("campaignLibraryLoading")
                        Spacer()
                    }
                    .listRowBackground(PlayerTheme.opaquePanel)
                } else if model.campaigns.isEmpty {
                    ContentUnavailableView(
                        "No Campaigns",
                        systemImage: "books.vertical",
                        description: Text(
                            "Import a CDF v2 project or restore a recovery bundle to begin."
                        )
                    )
                    .foregroundStyle(PlayerTheme.secondaryText)
                    .accessibilityIdentifier("campaignLibraryEmptyState")
                    .listRowBackground(PlayerTheme.opaquePanel)
                } else {
                    ForEach(model.campaigns) { campaign in
                        Button {
                            openCampaign(campaign.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(campaign.summary.title)
                                    .font(.headline)
                                    .foregroundStyle(PlayerTheme.primaryText)
                                    .accessibilityIdentifier(
                                        "campaignRowTitle-\(campaign.id.uuidString.lowercased())"
                                    )
                                if let scene = campaign.currentSceneTitle,
                                   scene.isEmpty == false {
                                    Text(scene)
                                        .font(.subheadline)
                                        .foregroundStyle(PlayerTheme.secondaryText)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            "campaignRow-\(campaign.id.uuidString.lowercased())"
                        )
                        .listRowBackground(PlayerTheme.opaquePanel)
                    }
                }
            }

            Section("Add Campaign") {
                Button {
                    presentedSheet = .campaignImport
                } label: {
                    Label("Import campaign", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("importCampaignButton")

                Button {
                    isRecoveryImporterPresented = true
                } label: {
                    Label("Restore recovery bundle", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(isRestoring)
                .accessibilityIdentifier("restoreCampaignButton")

                if isRestoring {
                    ProgressView("Restoring campaign…")
                        .tint(PlayerTheme.accent)
                        .accessibilityIdentifier("recoveryRestoreProgressView")
                }
            }
            .listRowBackground(PlayerTheme.opaquePanel)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PlayerTheme.canvas)
        .foregroundStyle(PlayerTheme.primaryText)
        .tint(PlayerTheme.accent)
        .navigationTitle("Campaigns")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: openProviderSettings) {
                    Label("Provider Settings", systemImage: "key")
                }
                .accessibilityIdentifier("providerSettingsButton")
            }
        }
        .accessibilityIdentifier("campaignLibraryList")
        .accessibilityElement(children: .contain)
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Campaign library")
                .accessibilityIdentifier("campaignLibraryView")
                .allowsHitTesting(false)
        }
        .sheet(item: $presentedSheet) { _ in
            ImportFlowSheet(coordinator: importCoordinator)
                .presentationSizing(.form)
        }
        .fileImporter(
            isPresented: $isRecoveryImporterPresented,
            allowedContentTypes: [.zip],
            allowsMultipleSelection: false,
            onCompletion: restore
        )
        .onChange(of: importCoordinator.committedCampaignID) { _, campaignID in
            guard let campaignID else { return }
            presentedSheet = nil
            Task { @MainActor in
                await model.refresh()
                openCampaign(campaignID)
            }
        }
        .alert(
            "Recovery Error",
            isPresented: Binding(
                get: { recoveryErrorMessage != nil },
                set: { presented in
                    if presented == false { recoveryErrorMessage = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recoveryErrorMessage ?? "The recovery bundle could not be restored.")
        }
        .overlay {
            if let errorMessage = model.errorMessage {
                ContentUnavailableView(
                    "Campaign Library Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
                .accessibilityIdentifier("campaignLibraryError")
            }
        }
    }

    private func restore(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure = result {
                recoveryErrorMessage = "The recovery bundle could not be opened."
            }
            return
        }
        isRestoring = true
        Task { @MainActor in
            defer { isRestoring = false }
            do {
                let campaignID = try await recoveryBundleReader.restore(
                    from: url
                )
                await model.refresh()
                openCampaign(campaignID)
            } catch {
                recoveryErrorMessage = "The recovery bundle could not be restored."
            }
        }
    }
}

@MainActor
struct CampaignPlayerHost: View {
    @State private var model: PlayerSessionModel
    @State private var errorMessage: String?

    private let graph: AppDependencyGraph
    private let campaignID: UUID
    private let exitCampaign: @MainActor () -> Void
    private let campaignDeleted: @MainActor () -> Void

    init(
        graph: AppDependencyGraph,
        campaignID: UUID,
        exitCampaign: @escaping @MainActor () -> Void,
        campaignDeleted: @escaping @MainActor () -> Void
    ) {
        self.graph = graph
        self.campaignID = campaignID
        self.exitCampaign = exitCampaign
        self.campaignDeleted = campaignDeleted
        _model = State(
            initialValue: graph.makePlayerSessionModel(campaignID: campaignID)
        )
    }

    var body: some View {
        Group {
            if let state = model.state {
                PlayerShellView(
                    model: model,
                    campaignDataContext: graph.campaignDataContext(
                        campaignID: campaignID,
                        title: state.campaignTitle
                    ),
                    exitCampaign: exitCampaign,
                    campaignDeleted: campaignDeleted
                )
            } else if let errorMessage {
                ContentUnavailableView(
                    "Campaign Could Not Open",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
                .foregroundStyle(PlayerTheme.primaryText)
                .background(PlayerTheme.canvas)
            } else {
                ProgressView("Opening campaign…")
                    .tint(PlayerTheme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PlayerTheme.canvas)
            }
        }
        .task {
            guard model.state == nil, errorMessage == nil else { return }
            do {
                try await model.load()
            } catch {
                errorMessage = "Its imported project or event history could not be read."
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
