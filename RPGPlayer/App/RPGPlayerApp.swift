import SwiftUI

@main
struct RPGPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            RPGPlayerRootView()
        }
    }
}

@MainActor
private struct RPGPlayerRootView: View {
    private enum Destination {
        case library(ImportCoordinator)
        case player(CampaignDataContext?, ImportCoordinator?)
    }

    @State private var destination: Destination
    private let arguments: [String]

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.arguments = arguments
        if arguments.contains("-fixture") {
            _destination = State(initialValue: .player(nil, nil))
        } else {
            _destination = State(
                initialValue: .library(
                    ImportCoordinator.live(arguments: arguments)
                )
            )
        }
    }

    var body: some View {
        switch destination {
        case .library(let coordinator):
            ImportLibraryHostView(coordinator: coordinator) { campaignID in
                destination = .player(
                    coordinator.campaignDataContext(for: campaignID),
                    coordinator
                )
            }
        case .player(let campaignDataContext, let coordinator):
            PlayerShellView(
                arguments: arguments,
                campaignDataContext: campaignDataContext
            ) {
                if let coordinator {
                    destination = .library(coordinator)
                }
            }
        }
    }
}
