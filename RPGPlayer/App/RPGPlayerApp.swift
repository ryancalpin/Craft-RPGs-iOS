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
        case player
    }

    @State private var destination: Destination
    private let arguments: [String]

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.arguments = arguments
        if arguments.contains("-fixture") {
            _destination = State(initialValue: .player)
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
            ImportLibraryHostView(coordinator: coordinator) {
                destination = .player
            }
        case .player:
            PlayerShellView(arguments: arguments)
        }
    }
}
