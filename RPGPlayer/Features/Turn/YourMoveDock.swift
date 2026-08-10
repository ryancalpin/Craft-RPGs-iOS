import SwiftUI

struct YourMoveDock: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let choiceCount: Int
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            dockLabel
            .foregroundStyle(PlayerTheme.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .fill(PlayerTheme.panel.opacity(0.58))
                    }
                    .overlay {
                        Capsule()
                            .stroke(PlayerTheme.panelStroke, lineWidth: 1)
                    }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Your Move")
        .accessibilityValue("The GM is waiting. \(choiceCount) choices")
        .accessibilityHint("Opens the player action sheet")
        .accessibilityIdentifier("yourMoveDock")
    }

    @ViewBuilder
    private var dockLabel: some View {
        if dynamicTypeSize.isAccessibilitySize {
            HStack(spacing: 12) {
                Text("Your Move")
                    .font(.headline)
                    .fixedSize(horizontal: true, vertical: true)

                Spacer(minLength: 8)

                Image(systemName: "chevron.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PlayerTheme.secondaryText)
                    .accessibilityHidden(true)
            }
        } else {
            HStack(spacing: 14) {
                Image(systemName: "checklist")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .overlay {
                                Circle()
                                    .stroke(PlayerTheme.panelStroke, lineWidth: 1)
                            }
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Your Move")
                        .font(.headline)
                    Text("The GM is waiting — tap to view \(choiceCount) choices")
                        .font(.caption)
                        .foregroundStyle(PlayerTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PlayerTheme.secondaryText)
            }
        }
    }
}

#Preview {
    ZStack {
        PlayerTheme.canvas
        YourMoveDock(choiceCount: 3, open: {})
            .padding()
    }
    .preferredColorScheme(.dark)
}
