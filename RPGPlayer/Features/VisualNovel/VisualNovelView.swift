import SwiftUI

struct VisualNovelView: View {
    let message: GMMessage
    let beatIndex: Int
    let safeAreaTop: CGFloat
    let safeAreaBottom: CGFloat
    let previous: () -> Void
    let next: () -> Void
    let close: () -> Void
    let finish: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var resolvedBeatIndex: Int {
        min(max(0, beatIndex), max(0, message.beats.count - 1))
    }

    private var currentBeat: VisualNovelBeat? {
        guard message.beats.indices.contains(resolvedBeatIndex) else { return nil }
        return message.beats[resolvedBeatIndex]
    }

    private var isLastBeat: Bool {
        resolvedBeatIndex == message.beats.count - 1
    }

    var body: some View {
        GeometryReader { proxy in
            if let currentBeat {
                VStack(spacing: 8) {
                    Spacer(minLength: safeAreaTop + 68)

                    if currentBeat.kind != .title {
                        CharacterSilhouettePlaceholder()
                            .frame(width: min(proxy.size.width * 0.50, 220))
                            .frame(height: min(proxy.size.height * 0.24, 220))
                            .padding(.bottom, -45)
                            .accessibilityHidden(true)
                    }

                    VisualNovelControlRow(
                        currentBeat: resolvedBeatIndex,
                        beatCount: message.beats.count,
                        previous: previous,
                        close: close
                    )

                    VisualNovelCard(
                        beat: currentBeat,
                        isLastBeat: isLastBeat,
                        usesScrollableStory: dynamicTypeSize.isAccessibilitySize,
                        continueAction: isLastBeat ? finish : next
                    )
                }
                .padding(.horizontal, PlayerTheme.pageInset)
                .padding(.bottom, max(safeAreaBottom, 8) + 12)
                .frame(maxWidth: 720, maxHeight: .infinity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct VisualNovelControlRow: View {
    let currentBeat: Int
    let beatCount: Int
    let previous: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if currentBeat > 0 {
                CircleIconButton(
                    systemName: "chevron.left",
                    label: "Previous beat",
                    identifier: "previousBeat",
                    action: previous
                )
            }

            Spacer(minLength: 8)

            Text("\(currentBeat + 1) / \(beatCount)")
                .font(.body.monospacedDigit())
                .foregroundStyle(PlayerTheme.secondaryText)

            CircleIconButton(
                systemName: "speaker.wave.2.fill",
                label: "Narration",
                identifier: "narrationControl",
                action: {}
            )

            CircleIconButton(
                systemName: "xmark",
                label: "Close visual novel",
                identifier: "closeVisualNovel",
                action: close
            )
        }
        .frame(minHeight: 52)
    }
}

private struct VisualNovelCard: View {
    let beat: VisualNovelBeat
    let isLastBeat: Bool
    let usesScrollableStory: Bool
    let continueAction: () -> Void

    var body: some View {
        Group {
            if beat.kind == .title {
                titleContent
            } else {
                dialogueContent
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 46)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: PlayerTheme.panelRadius, style: .continuous)
                .fill(PlayerTheme.panel)
                .overlay {
                    RoundedRectangle(cornerRadius: PlayerTheme.panelRadius, style: .continuous)
                        .stroke(PlayerTheme.panelStroke, lineWidth: 1)
                }
        }
        .overlay(alignment: .bottom) {
            continueButton
                .offset(y: 10)
        }
        .padding(.bottom, 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("visualNovelCard")
    }

    private var titleContent: some View {
        VStack(spacing: 12) {
            Text((beat.title ?? beat.text).uppercased())
                .font(.title2.weight(.medium))
                .tracking(4)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(PlayerTheme.primaryText)
                .frame(maxWidth: 280)

            if let subtitle = beat.subtitle {
                Text(subtitle)
                    .font(.title3.italic())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(PlayerTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 112)
    }

    private var dialogueContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                AvatarPlaceholder(name: beat.speaker ?? "Narrator")

                VStack(alignment: .leading, spacing: 6) {
                    Text(beat.speaker ?? "Narrator")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(PlayerTheme.primaryText)

                    if let mood = beat.mood {
                        Text(mood)
                            .font(.subheadline)
                            .foregroundStyle(PlayerTheme.secondaryText)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 32)
                            .background {
                                Capsule()
                                    .fill(Color.black.opacity(0.26))
                                    .overlay {
                                        Capsule()
                                            .stroke(PlayerTheme.panelStroke, lineWidth: 1)
                                    }
                            }
                    }
                }
            }

            Group {
                if usesScrollableStory {
                    ScrollView {
                        storyText
                    }
                    .frame(maxHeight: 230)
                } else {
                    storyText
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var storyText: some View {
        Text(beat.text)
            .font(.body)
            .foregroundStyle(PlayerTheme.primaryText)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var continueButton: some View {
        Button(action: continueAction) {
            HStack(spacing: 12) {
                Text(isLastBeat ? "End of scene — your move" : "Continue")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
            }
            .foregroundStyle(PlayerTheme.primaryText)
            .padding(.horizontal, 24)
            .frame(minWidth: 160, minHeight: 46)
            .background {
                Capsule()
                    .fill(Color(red: 0.035, green: 0.04, blue: 0.055))
                    .overlay {
                        Capsule()
                            .stroke(PlayerTheme.panelStroke, lineWidth: 1)
                    }
            }
            .frame(minHeight: PlayerTheme.controlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("nextBeat")
    }
}

private struct CircleIconButton: View {
    let systemName: String
    let label: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
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
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

private struct AvatarPlaceholder: View {
    let name: String

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [PlayerTheme.accent.opacity(0.72), Color.indigo.opacity(0.58)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(String(name.prefix(1)).uppercased())
                .font(.headline.weight(.bold))
                .foregroundStyle(PlayerTheme.primaryText)
        }
        .frame(width: 52, height: 52)
        .overlay {
            Circle()
                .stroke(PlayerTheme.panelStroke, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

struct CharacterSilhouettePlaceholder: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack(alignment: .top) {
                CharacterCloakShape()
                    .fill(
                        LinearGradient(
                            colors: [Color.black.opacity(0.18), Color.black.opacity(0.90)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: width * 0.94, height: height * 0.72)
                    .padding(.top, height * 0.28)

                Circle()
                    .fill(Color.black.opacity(0.78))
                    .frame(width: width * 0.42, height: width * 0.42)
                    .padding(.top, height * 0.04)

                Capsule()
                    .fill(Color.black.opacity(0.72))
                    .frame(width: width * 0.20, height: height * 0.24)
                    .padding(.top, height * 0.26)

                CharacterCloakShape()
                    .stroke(PlayerTheme.accent.opacity(0.12), lineWidth: 2)
                    .frame(width: width * 0.94, height: height * 0.72)
                    .padding(.top, height * 0.28)
            }
            .frame(width: width, height: height)
        }
        .accessibilityIdentifier("characterSilhouette")
    }
}

private struct CharacterCloakShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.height * 0.38),
            control1: CGPoint(x: rect.width * 0.76, y: rect.height * 0.04),
            control2: CGPoint(x: rect.width * 0.96, y: rect.height * 0.18)
        )
        path.addLine(to: CGPoint(x: rect.width * 0.91, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.width * 0.09, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.38))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.width * 0.04, y: rect.height * 0.18),
            control2: CGPoint(x: rect.width * 0.24, y: rect.height * 0.04)
        )
        path.closeSubpath()
        return path
    }
}

#Preview("Visual Novel Title") {
    ZStack {
        PlayerTheme.canvas
        VisualNovelView(
            message: PlayerSessionState.fixture.latestMessage,
            beatIndex: 0,
            safeAreaTop: 59,
            safeAreaBottom: 34,
            previous: {},
            next: {},
            close: {},
            finish: {}
        )
    }
    .preferredColorScheme(.dark)
}
