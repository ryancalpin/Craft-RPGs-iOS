import Observation
import SwiftUI
import UniformTypeIdentifiers

struct CampaignLibraryItem: Identifiable, Equatable, Sendable {
    let summary: CampaignSummary
    let currentSceneTitle: String?

    var id: UUID { summary.campaignID }
}

private enum CampaignLibrarySheet: Identifiable {
    case newCampaign
    case campaignImport

    var id: String {
        switch self {
        case .newCampaign: "new-campaign"
        case .campaignImport: "campaign-import"
        }
    }
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
    @State private var presentedSheet: CampaignLibrarySheet?
    @State private var createdCampaignID: UUID?
    @State private var isRecoveryImporterPresented = false
    @State private var isRestoring = false
    @State private var recoveryErrorMessage: String?

    let model: CampaignLibraryModel
    let campaignCreator: CampaignCreator
    let importCoordinator: ImportCoordinator
    let recoveryBundleReader: RecoveryBundleReader
    let openProviderSettings: @MainActor () -> Void
    let openCampaign: @MainActor (UUID) -> Void

    var body: some View {
        List {
            Section {
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
                        "Your worlds are waiting",
                        systemImage: "sparkles",
                        description: Text(
                            "Start a new campaign, import a CDF v2 project, or restore a recovery bundle."
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
                            HStack(spacing: 14) {
                                CampaignGlyph()

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(campaign.summary.title)
                                        .font(.system(.headline, design: .rounded).weight(.bold))
                                        .foregroundStyle(PlayerTheme.primaryText)
                                        .accessibilityIdentifier(
                                            "campaignRowTitle-\(campaign.id.uuidString.lowercased())"
                                        )
                                    if let scene = campaign.currentSceneTitle,
                                       scene.isEmpty == false {
                                        Label(scene, systemImage: "location.north.line")
                                            .font(.caption)
                                            .foregroundStyle(PlayerTheme.secondaryText)
                                    }
                                }

                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(PlayerTheme.tertiaryText)
                            }
                            .padding(.vertical, 8)
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

            Section {
                Button {
                    presentedSheet = .newCampaign
                } label: {
                    LibraryActionLabel(
                        title: "New campaign",
                        detail: "Start a story from a name and premise",
                        systemName: "plus.circle.fill",
                        tint: PlayerTheme.accentCool
                    )
                }
                .accessibilityIdentifier("newCampaignButton")

                Button {
                    presentedSheet = .campaignImport
                } label: {
                    LibraryActionLabel(
                        title: "Import a campaign",
                        detail: "Bring in a CDF v2 world or project",
                        systemName: "arrow.down.circle.fill",
                        tint: PlayerTheme.accent
                    )
                }
                .accessibilityIdentifier("importCampaignButton")

                Button {
                    isRecoveryImporterPresented = true
                } label: {
                    LibraryActionLabel(
                        title: "Restore a recovery bundle",
                        detail: "Continue from a saved campaign archive",
                        systemName: "arrow.counterclockwise.circle.fill",
                        tint: PlayerTheme.accentCool
                    )
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
        .navigationTitle("Campaign library")
        .navigationBarTitleDisplayMode(.large)
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
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .newCampaign:
                NewCampaignSheet(
                    creator: campaignCreator,
                    onCreated: { createdCampaignID = $0 }
                )
                .presentationSizing(.form)
            case .campaignImport:
                ImportFlowSheet(coordinator: importCoordinator)
                    .presentationSizing(.form)
            }
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
        .onChange(of: createdCampaignID) { _, campaignID in
            guard let campaignID else { return }
            createdCampaignID = nil
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

private struct CampaignGlyph: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(PlayerTheme.accentGradient)
            Image(systemName: "lamp.desk.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(PlayerTheme.canvas)
        }
        .frame(width: 52, height: 52)
        .shadow(color: PlayerTheme.accent.opacity(0.18), radius: 10, y: 5)
        .accessibilityHidden(true)
    }
}

private struct LibraryActionLabel: View {
    let title: String
    let detail: String
    let systemName: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemName)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background {
                    Circle().fill(tint.opacity(0.14))
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(PlayerTheme.primaryText)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(PlayerTheme.tertiaryText)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(PlayerTheme.tertiaryText)
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
struct CampaignPlayerHost: View {
    @State private var model: PlayerSessionModel
    @State private var turnStreaming: CampaignTurnStreaming?
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
        _turnStreaming = State(initialValue: nil)
    }

    var body: some View {
        Group {
            if let state = model.state {
                PlayerShellView(
                    model: model,
                    campaignDataContext: graph.campaignDataContext(
                        campaignID: campaignID,
                        title: state.campaignTitle,
                        project: model.project
                    ),
                    turnStreaming: turnStreaming,
                    turnActivityCoordinator: graph.turnActivityCoordinator,
                    turnBackgroundExecutionController: graph.turnBackgroundExecutionController,
                    narrationPlaybackCoordinator: graph.narrationPlaybackCoordinator,
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
                turnStreaming = graph.makeCampaignTurnStreaming(model: model)
            } catch {
                errorMessage = "Its imported project or event history could not be read."
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
