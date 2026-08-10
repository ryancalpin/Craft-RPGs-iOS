import SwiftUI

struct GenerationView: View {
    let phase: GenerationPhase
    let steps: [String]
    let safeAreaTop: CGFloat
    let safeAreaBottom: CGFloat
    let canStop: Bool
    let stop: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsSteps = false

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 5) {
                Spacer(minLength: safeAreaTop + 68)

                CharacterSilhouettePlaceholder()
                    .frame(width: min(proxy.size.width * 0.50, 220))
                    .frame(height: min(proxy.size.height * 0.24, 220))
                    .padding(.bottom, -45)
                    .accessibilityHidden(true)

                stopRow

                GenerationCard(
                    phase: phase,
                    steps: steps,
                    showsSteps: $showsSteps,
                    reduceMotion: reduceMotion
                )
                .padding(.horizontal, PlayerTheme.pageInset)
            }
            .padding(.bottom, max(16, safeAreaBottom - 2))
            .frame(maxWidth: 720, maxHeight: .infinity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("generationView")
    }

    private var stopRow: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            Button(action: stop) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(PlayerTheme.primaryText)
                    .frame(width: 40, height: 40)
                    .background {
                        Circle()
                            .fill(Color.black.opacity(0.52))
                            .overlay {
                                Circle()
                                    .stroke(PlayerTheme.panelStroke, lineWidth: 1)
                            }
                    }
                    .frame(width: 52, height: 52)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canStop)
            .accessibilityLabel("Stop generation")
            .accessibilityIdentifier("stopGeneration")
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }
}

private struct GenerationCard: View {
    let phase: GenerationPhase
    let steps: [String]
    @Binding var showsSteps: Bool
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showsSteps {
                stepList
                    .transition(.opacity)
            }

            statusRow
                .frame(minHeight: 104)
        }
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(
                cornerRadius: PlayerTheme.panelRadius,
                style: .continuous
            )
            .fill(PlayerTheme.panel)
            .overlay {
                RoundedRectangle(
                    cornerRadius: PlayerTheme.panelRadius,
                    style: .continuous
                )
                .stroke(PlayerTheme.panelStroke, lineWidth: 1)
            }
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: PlayerTheme.panelRadius,
                style: .continuous
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("generationCard")
    }

    private var statusRow: some View {
        HStack(spacing: 15) {
            GenerationAvatarPlaceholder()

            Text(phase.displayText)
                .font(.headline)
                .foregroundStyle(PlayerTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.opacity)
                .animation(
                    .easeOut(duration: reduceMotion ? 0.12 : 0.20),
                    value: phase
                )
                .accessibilityIdentifier("generationStatus")

            Button {
                withAnimation(
                    reduceMotion
                        ? .easeOut(duration: 0.12)
                        : .spring(response: 0.26, dampingFraction: 0.88)
                ) {
                    showsSteps.toggle()
                }
            } label: {
                Image(systemName: showsSteps ? "chevron.up" : "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PlayerTheme.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showsSteps ? "Hide generation steps" : "Show generation steps")
            .accessibilityIdentifier("generationStepsDisclosure")
        }
        .padding(.leading, 18)
        .padding(.trailing, 4)
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(PlayerTheme.accent)
                        .accessibilityHidden(true)

                    Text(step)
                        .font(.subheadline)
                        .foregroundStyle(PlayerTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("generationStep-\(index)")
                }
            }

            if steps.isEmpty {
                Text("Preparing the first update…")
                    .font(.subheadline)
                    .foregroundStyle(PlayerTheme.secondaryText)
                    .accessibilityIdentifier("generationStepPending")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }
}

private struct GenerationAvatarPlaceholder: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            PlayerTheme.accent.opacity(0.72),
                            Color.indigo.opacity(0.58)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: "sparkles")
                .font(.title3.weight(.semibold))
                .foregroundStyle(PlayerTheme.primaryText)
        }
        .frame(width: 60, height: 60)
        .overlay {
            Circle()
                .stroke(PlayerTheme.panelStroke, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

#Preview("Generation") {
    ZStack {
        PlayerTheme.canvas
        GenerationView(
            phase: .writingScene,
            steps: [
                "Loaded the latest campaign state.",
                "Prepared the next scene outline."
            ],
            safeAreaTop: 59,
            safeAreaBottom: 34,
            canStop: true,
            stop: {}
        )
    }
    .preferredColorScheme(.dark)
}
