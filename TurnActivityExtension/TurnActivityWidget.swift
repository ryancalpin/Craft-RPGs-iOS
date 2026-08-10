import ActivityKit
import SwiftUI
import WidgetKit

@main
struct TurnActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        TurnActivityWidget()
    }
}

struct TurnActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TurnActivityAttributes.self) { context in
            TurnActivityLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.88))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(context.attributes.deepLinkURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "book.pages.fill")
                        .foregroundStyle(.indigo)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startedAt, style: .timer)
                        .font(.caption.monospacedDigit())
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.campaignTitle)
                        .font(.headline)
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.state.phase.displayText)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)

                            Text(context.state.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        if context.state.canCancel {
                            Text("Open to stop")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "book.pages.fill")
            } compactTrailing: {
                Text(context.state.startedAt, style: .timer)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "book.closed.fill")
            }
            .widgetURL(context.attributes.deepLinkURL)
            .keylineTint(.indigo)
        }
    }
}

private struct TurnActivityLockScreenView: View {
    let context: ActivityViewContext<TurnActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(context.attributes.campaignTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 10) {
                Image(systemName: "book.pages.fill")
                    .foregroundStyle(.indigo)

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.phase.displayText)
                        .font(.headline)
                        .lineLimit(1)

                    Text(context.state.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(context.state.startedAt, style: .timer)
                    .font(.caption.monospacedDigit())
            }

            if context.state.canCancel {
                Text("Open RPGPlayer to stop")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

private let previewAttributes = TurnActivityAttributes(
    campaignID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
    campaignTitle: "The Ascendant Road",
    turnID: "preview-turn"
)

private let previewContentState = TurnActivityAttributes.ContentState(
    phase: .writingScene,
    status: "Drafting the next story beat",
    startedAt: .now.addingTimeInterval(-42),
    canCancel: true
)

#Preview("Lock Screen", as: .content, using: previewAttributes) {
    TurnActivityWidget()
} contentStates: {
    previewContentState
}

#Preview("Dynamic Island Compact", as: .dynamicIsland(.compact), using: previewAttributes) {
    TurnActivityWidget()
} contentStates: {
    previewContentState
}

#Preview("Dynamic Island Minimal", as: .dynamicIsland(.minimal), using: previewAttributes) {
    TurnActivityWidget()
} contentStates: {
    previewContentState
}

#Preview("Dynamic Island Expanded", as: .dynamicIsland(.expanded), using: previewAttributes) {
    TurnActivityWidget()
} contentStates: {
    previewContentState
}
