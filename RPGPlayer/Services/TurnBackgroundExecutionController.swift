import UIKit

/// Keeps a user-started local turn alive for iOS's finite background window.
/// This is intentionally not presented as an APNs-backed continuation.
@MainActor
final class TurnBackgroundExecutionController {
    private var taskIdentifier = UIBackgroundTaskIdentifier.invalid

    func begin() {
        end()
        taskIdentifier = UIApplication.shared.beginBackgroundTask(
            withName: "RPGPlayer turn"
        ) { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard taskIdentifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskIdentifier)
        taskIdentifier = .invalid
    }
}
