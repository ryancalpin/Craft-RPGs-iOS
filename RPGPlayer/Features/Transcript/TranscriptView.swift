import SwiftUI

struct TranscriptView: View {
    let messages: [GMMessage]
    let choiceCount: Int
    let usesFixtureCopy: Bool
    let safeAreaTop: CGFloat
    let safeAreaBottom: CGFloat
    let moveSheetReservation: CGFloat?
    @Binding var dockFocusRequest: Bool
    let openMove: () -> Void
    let pendingRoll: RollRequestedPayload?
    let resolvedRoll: RollResolvedPayload?
    let resolveRoll: @MainActor (RollRequestedPayload) async throws -> RollResolvedPayload
    let dismissRoll: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 700
            let leadingInset = compact ? min(62, proxy.size.width * 0.14) : 24
            let trailingInset = compact ? 16.0 : 24.0
            let bottomInset = max(safeAreaBottom, 8)
            let minimumSurfaceHeight = max(
                0,
                proxy.size.height
                    - safeAreaTop
                    - bottomInset
                    - 182
            )

            ScrollView {
                VStack(spacing: 0) {
                    LazyVStack(spacing: 18) {
                        ForEach(messages) { message in
                            TranscriptMessageView(
                                message: message,
                                usesFixtureCopy: usesFixtureCopy,
                                pendingRoll: message.id == messages.last?.id
                                    ? pendingRoll
                                    : nil,
                                resolvedRoll: message.id == messages.last?.id
                                    ? resolvedRoll
                                    : nil,
                                resolveRoll: resolveRoll,
                                dismissRoll: dismissRoll
                            )
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: 700, alignment: .leading)
                    .frame(minHeight: minimumSurfaceHeight, alignment: .bottom)
                    .background {
                        transcriptBackground
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("transcriptSurface")
                    .accessibilityValue(
                        messages.count == 1
                            ? "1 GM message"
                            : "\(messages.count) GM messages"
                    )
                    .padding(.leading, leadingInset)
                    .padding(.trailing, trailingInset)
                    .padding(.bottom, 14)
                    .frame(
                        maxWidth: .infinity,
                        alignment: compact ? .trailing : .center
                    )

                    if let moveSheetReservation {
                        Color.clear
                            .frame(height: moveSheetReservation)
                            .accessibilityHidden(true)
                    }
                }
            }
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("transcriptScrollViewport")
            .safeAreaInset(
                edge: .bottom,
                spacing: moveSheetReservation == nil ? 14 : 0
            ) {
                if moveSheetReservation == nil {
                    YourMoveDock(
                        choiceCount: choiceCount,
                        focusRequest: $dockFocusRequest,
                        open: openMove
                    )
                        .padding(.horizontal, 12)
                        .padding(.bottom, bottomInset)
                }
            }
            .padding(.top, safeAreaTop + 68)
        }
    }

    @ViewBuilder
    private var transcriptBackground: some View {
        PlayerSemanticSurface(
            shape: RoundedRectangle(cornerRadius: 24, style: .continuous),
            style: .material(panelOverlayOpacity: 0.50)
        )
    }
}

private struct TranscriptMessageView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.playerReduceMotionOverride) private var reduceMotionOverride
    let message: GMMessage
    let usesFixtureCopy: Bool
    let pendingRoll: RollRequestedPayload?
    let resolvedRoll: RollResolvedPayload?
    let resolveRoll: @MainActor (RollRequestedPayload) async throws -> RollResolvedPayload
    let dismissRoll: () -> Void
    @State private var actionsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(message.transcript) { block in
                switch block.kind {
                case .narration:
                    Text(block.text)
                        .font(.body)
                        .foregroundStyle(PlayerTheme.primaryText)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .dialogue:
                    TranscriptDialogueBlock(
                        block: DialogueBlock(
                            id: block.id,
                            speaker: block.speaker ?? "Narrator",
                            mood: block.mood,
                            text: block.text
                        )
                    )
                }
            }

            if let rollRequest = pendingRoll {
                DiceRollCard(
                    request: rollRequest,
                    resolved: resolvedRoll,
                    resolve: { try await resolveRoll(rollRequest) },
                    onDismiss: dismissRoll
                )
            }

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(
                        reduceMotion || reduceMotionOverride
                            ? nil
                            : .easeOut(duration: 0.18)
                    ) {
                        actionsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("Actions")
                        Image(systemName: actionsExpanded ? "chevron.down" : "chevron.right")
                    }
                    .font(.body)
                    .foregroundStyle(PlayerTheme.secondaryText)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(actionsExpanded ? "Expanded" : "Collapsed")
                .accessibilityIdentifier("transcriptActionsDisclosure")

                if actionsExpanded {
                    Text(
                        usesFixtureCopy
                            ? "\(message.actionCount) fixture actions recorded for this turn."
                            : "\(message.actionCount) actions recorded for this turn."
                    )
                        .font(.subheadline)
                        .foregroundStyle(PlayerTheme.secondaryText)
                        .padding(.bottom, 16)
                        .transition(.opacity)
                }

                Text(message.finalQuestion)
                    .font(.title3)
                    .foregroundStyle(PlayerTheme.primaryText)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("latestGMQuestion")
            }
        }
    }
}

private struct TranscriptDialogueBlock: View {
    let block: DialogueBlock

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.24))
                Text(String(block.speaker.prefix(1)).uppercased())
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(PlayerTheme.secondaryText)
            }
            .frame(width: 44, height: 44)
            .overlay {
                Circle()
                    .stroke(PlayerTheme.panelStroke, lineWidth: 1)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(block.speaker)
                        .font(.headline)
                    if let mood = block.mood {
                        Text(mood.lowercased())
                            .font(.subheadline.italic())
                            .foregroundStyle(PlayerTheme.secondaryText)
                    }
                }
                Text(block.text)
                    .font(.body)
                    .foregroundStyle(PlayerTheme.primaryText)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(PlayerTheme.panelStroke, lineWidth: 1)
                }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ZStack {
        PlayerTheme.canvas
        TranscriptView(
            messages: PlayerSessionState.fixture.messages,
            choiceCount: PlayerSessionState.fixture.choices.count,
            usesFixtureCopy: true,
            safeAreaTop: 59,
            safeAreaBottom: 34,
            moveSheetReservation: nil,
            dockFocusRequest: .constant(false),
            openMove: {},
            pendingRoll: nil,
            resolvedRoll: nil,
            resolveRoll: { _ in
                throw CancellationError()
            },
            dismissRoll: {}
        )
    }
    .preferredColorScheme(.dark)
}
