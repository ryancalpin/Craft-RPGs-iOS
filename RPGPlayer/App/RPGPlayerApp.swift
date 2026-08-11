import Observation
import SwiftUI

@main
struct RPGPlayerApp: App {
    @State private var rootModel: RPGPlayerRootModel

    init() {
        _rootModel = State(
            initialValue: RPGPlayerRootModel(
                arguments: ProcessInfo.processInfo.arguments
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            RPGPlayerRootView(model: rootModel)
        }
    }
}

@MainActor
@Observable
final class RPGPlayerRootModel {
    let arguments: [String]
    let graph: AppDependencyGraph?

    init(arguments: [String]) {
        self.arguments = arguments
        if arguments.contains("-fixture") {
            graph = nil
        } else {
            graph = AppDependencyGraph(arguments: arguments)
        }
    }
}

@MainActor
struct RPGPlayerRootView: View {
    let model: RPGPlayerRootModel

    @ViewBuilder
    var body: some View {
        if model.arguments.contains("-fixture") {
            PlayerShellView(arguments: model.arguments)
        } else if let graph = model.graph {
            CampaignAppRoot(graph: graph)
        }
    }
}

@MainActor
private struct CampaignAppRoot: View {
    private enum Route: Hashable {
        case player(UUID)
    }

    @State private var path: [Route] = []
    @State private var didStart = false
    @State private var libraryModel: CampaignLibraryModel

    private let graph: AppDependencyGraph

    init(graph: AppDependencyGraph) {
        self.graph = graph
        _libraryModel = State(
            initialValue: CampaignLibraryModel(
                store: graph.store,
                projectionLoader: graph.projectionLoader
            )
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            CampaignLibraryView(
                model: libraryModel,
                importCoordinator: graph.importCoordinator,
                recoveryBundleReader: graph.recoveryBundleReader,
                openCampaign: openCampaign
            )
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .player(let campaignID):
                    CampaignPlayerHost(
                        graph: graph,
                        campaignID: campaignID,
                        exitCampaign: { exitCampaign(campaignID) },
                        campaignDeleted: { campaignDeleted(campaignID) }
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            guard didStart == false else { return }
            didStart = true
            await libraryModel.refresh()
            guard graph.startsAtLibrary == false else { return }
            do {
                guard let campaignID = try await graph.presentationStore
                    .activeCampaignID() else {
                    return
                }
                if libraryModel.contains(campaignID) {
                    path = [.player(campaignID)]
                } else {
                    try await graph.presentationStore.setActiveCampaign(nil)
                }
            } catch {
                path = []
            }
        }
    }

    private func openCampaign(_ campaignID: UUID) {
        Task { @MainActor in
            do {
                try await graph.presentationStore.setActiveCampaign(campaignID)
                path = [.player(campaignID)]
            } catch {
                path = []
            }
        }
    }

    private func exitCampaign(_ campaignID: UUID) {
        Task { @MainActor in
            try? await graph.presentationStore.setActiveCampaign(nil)
            path = []
        }
    }

    private func campaignDeleted(_ campaignID: UUID) {
        Task { @MainActor in
            try? await graph.presentationStore.clearCampaign(campaignID)
            await libraryModel.refresh()
            path = []
        }
    }
}
