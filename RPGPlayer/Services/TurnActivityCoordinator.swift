@preconcurrency import ActivityKit
import Foundation

/// Owns the app-side lifecycle of a campaign turn Live Activity.
///
/// The activity intentionally carries only a phase and sanitized status. The
/// current product runs provider calls with user-owned credentials on-device,
/// so there is no push token or backend continuation path to hand to APNs.
@MainActor
final class TurnActivityCoordinator {
    private struct ActiveTurn {
        let activity: Activity<TurnActivityAttributes>
        let campaignID: UUID
        let campaignTitle: String
        let turnID: String
        let startedAt: Date
    }

    private var activeTurn: ActiveTurn?

    func start(
        campaignID: UUID,
        campaignTitle: String,
        turnID: String
    ) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }

        await endCurrentActivity(
            status: "Replaced by a newer turn",
            phase: .needsAttention
        )

        let startedAt = Date()
        let attributes = TurnActivityAttributes(
            campaignID: campaignID,
            campaignTitle: campaignTitle,
            turnID: turnID
        )
        let state = TurnActivityAttributes.ContentState(
            phase: .queued,
            status: "Preparing the next turn",
            startedAt: startedAt,
            canCancel: true
        )

        do {
            let activity = try Activity<TurnActivityAttributes>.request(
                attributes: attributes,
                content: ActivityContent(
                    state: state,
                    staleDate: Date().addingTimeInterval(15 * 60)
                ),
                pushType: nil
            )
            activeTurn = ActiveTurn(
                activity: activity,
                campaignID: campaignID,
                campaignTitle: campaignTitle,
                turnID: turnID,
                startedAt: startedAt
            )
        } catch {
            // Live Activities are supplemental UI. A failure must not prevent
            // the durable turn from running in the player.
        }
    }

    func update(
        phase: GenerationPhase,
        status: String
    ) async {
        guard let activeTurn else { return }
        let state = TurnActivityAttributes.ContentState(
            phase: phase,
            status: Self.sanitizedStatus(status),
            startedAt: activeTurn.startedAt,
            canCancel: true
        )
        await activeTurn.activity.update(
            ActivityContent(
                state: state,
                staleDate: Date().addingTimeInterval(15 * 60)
            )
        )
    }

    func finish(
        phase: GenerationPhase = .ready,
        status: String = "Turn complete"
    ) async {
        await endCurrentActivity(status: status, phase: phase)
    }

    func cancel() async {
        await endCurrentActivity(
            status: "Turn cancelled",
            phase: .needsAttention
        )
    }

    private func endCurrentActivity(
        status: String,
        phase: GenerationPhase
    ) async {
        guard let activeTurn else { return }
        self.activeTurn = nil
        let state = TurnActivityAttributes.ContentState(
            phase: phase,
            status: Self.sanitizedStatus(status),
            startedAt: activeTurn.startedAt,
            canCancel: false
        )
        await activeTurn.activity.end(
            ActivityContent(
                state: state,
                staleDate: nil
            ),
            dismissalPolicy: .default
        )
    }

    private static func sanitizedStatus(_ status: String) -> String {
        let collapsed = status
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard collapsed.isEmpty == false else { return "Working" }
        return String(collapsed.prefix(96))
    }
}
