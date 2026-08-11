import SwiftUI

struct YourMoveSheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.playerReduceMotionOverride) private var reduceMotionOverride

    let choices: [PlayerChoice]
    let prompt: String
    let safeAreaBottom: CGFloat
    let cancel: () -> Void
    let submit: (PlayerSubmission) -> Void

    @State private var selectedChoiceID: UUID?
    @State private var customSelected = false
    @State private var customAction = ""
    @State private var additionalContext = ""
    @FocusState private var focusedField: MoveField?
    @AccessibilityFocusState private var closeControlFocused: Bool

    private enum MoveField: Hashable {
        case customAction
        case additionalContext
    }

    private var trimmedCustomAction: String {
        customAction.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedAction: String? {
        if customSelected {
            return trimmedCustomAction.isEmpty ? nil : trimmedCustomAction
        }
        return choices.first(where: { $0.id == selectedChoiceID })?.title
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(
                        alignment: .leading,
                        spacing: PlayerLayoutMetrics.turnSheetContentSpacing
                    ) {
                        sheetHeader
                        Text(prompt)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(PlayerTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(spacing: PlayerLayoutMetrics.turnChoiceSpacing) {
                            ForEach(choices) { choice in
                                MoveChoiceRow(
                                    choice: choice,
                                    selected: selectedChoiceID == choice.id,
                                    select: { select(choice) }
                                )
                            }
                        }

                        customChoice
                            .id(MoveField.customAction)

                        additionalContextEditor
                            .id(MoveField.additionalContext)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 14)
                    .padding(.bottom, 18)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: focusedField) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(
                        PlayerAccessibilityPolicy.reducesMotion(
                            systemEnabled: reduceMotion,
                            forcedForTesting: reduceMotionOverride
                        )
                            ? nil
                            : .easeOut(duration: 0.18)
                    ) {
                        scrollProxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }

            Divider()
                .overlay(PlayerTheme.panelStroke)

            HStack {
                Spacer()
                Button(action: confirm) {
                    HStack(spacing: 6) {
                        Text("Confirm")
                        Image(systemName: "return")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.82))
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(
                        minWidth: PlayerLayoutMetrics.turnConfirmChromeSize.width,
                        minHeight: PlayerLayoutMetrics.turnConfirmChromeSize.height
                    )
                    .background {
                        Capsule()
                            .fill(Color.white.opacity(resolvedAction == nil ? 0.46 : 0.92))
                    }
                    .frame(
                        minWidth: PlayerLayoutMetrics.turnConfirmChromeSize.width,
                        minHeight: PlayerLayoutMetrics.turnConfirmHitHeight
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(resolvedAction == nil)
                .accessibilityIdentifier("confirmMove")
            }
            .padding(.horizontal, 12)
            .padding(.top, PlayerLayoutMetrics.turnConfirmFooterPadding)
            .padding(
                .bottom,
                max(safeAreaBottom, PlayerLayoutMetrics.turnConfirmFooterPadding)
            )
            .background(PlayerTheme.canvas.opacity(0.90))
        }
        .background {
            PlayerSemanticSurface(
                shape: Rectangle(),
                style: .material(panelOverlayOpacity: 0.62),
                drawsStroke: false
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, cancel)
        .accessibilityIdentifier("yourMoveSheet")
        .onAppear {
            closeControlFocused = true
        }
    }

    private var sheetHeader: some View {
        HStack(alignment: .center) {
            Text("YOUR MOVE")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PlayerTheme.primaryText)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: cancel) {
                Image(systemName: "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PlayerTheme.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Your Move")
            .accessibilityIdentifier("closeYourMoveSheet")
            .accessibilityFocused($closeControlFocused)
        }
    }

    private var customChoice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                selectedChoiceID = nil
                customSelected = true
                focusedField = .customAction
            } label: {
                HStack(spacing: 12) {
                    ChoiceIndicator(selected: customSelected)
                    Text("Type something…")
                        .font(.headline)
                        .foregroundStyle(
                            customSelected
                                ? PlayerTheme.primaryText
                                : PlayerTheme.secondaryText
                        )
                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Type something…")
            .accessibilityValue(customSelected ? "Selected" : "Not selected")
            .accessibilityIdentifier("customMoveChoice")
            .accessibilityAddTraits(customSelected ? .isSelected : [])

            if customSelected {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your action")
                        .font(.caption)
                        .foregroundStyle(PlayerTheme.secondaryText)
                    TextEditor(text: $customAction)
                        .focused($focusedField, equals: .customAction)
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(PlayerTheme.primaryText)
                        .padding(10)
                        .frame(minHeight: 96)
                        .background {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.black.opacity(0.18))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(PlayerTheme.panelStroke, lineWidth: 1)
                                }
                        }
                        .accessibilityLabel("Custom action")
                        .accessibilityIdentifier("customActionEditor")
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(PlayerTheme.panelStroke, lineWidth: 1)
                }
        }
    }

    private var additionalContextEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add additional context (optional)")
                .font(.headline)
                .foregroundStyle(PlayerTheme.secondaryText)
            TextEditor(text: $additionalContext)
                .focused($focusedField, equals: .additionalContext)
                .scrollContentBackground(.hidden)
                .foregroundStyle(PlayerTheme.primaryText)
                .padding(10)
                .frame(minHeight: 96)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.18))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(PlayerTheme.panelStroke, lineWidth: 1)
                        }
                }
                .accessibilityLabel("Additional context")
                .accessibilityIdentifier("additionalContextEditor")
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(PlayerTheme.panelStroke, lineWidth: 1)
                }
        }
    }

    private func select(_ choice: PlayerChoice) {
        selectedChoiceID = choice.id
        customSelected = false
        focusedField = nil
    }

    private func confirm() {
        guard let resolvedAction else { return }
        submit(
            PlayerSubmission(
                action: resolvedAction,
                additionalContext: additionalContext
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
    }
}

private struct MoveChoiceRow: View {
    let choice: PlayerChoice
    let selected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 10) {
                ChoiceIndicator(selected: selected)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(choice.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PlayerTheme.primaryText)
                    Text(choice.detail)
                        .font(.footnote)
                        .foregroundStyle(PlayerTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(
                maxWidth: .infinity,
                minHeight: PlayerLayoutMetrics.turnChoiceMinimumHeight,
                alignment: .leading
            )
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selected ? PlayerTheme.accent.opacity(0.12) : Color.black.opacity(0.10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                selected ? PlayerTheme.accent.opacity(0.72) : PlayerTheme.panelStroke,
                                lineWidth: 1
                            )
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.title)
        .accessibilityValue(
            "\(choice.detail) \(selected ? "Selected" : "Not selected")"
        )
        .accessibilityHint("Selects this action")
        .accessibilityIdentifier(choice.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ChoiceIndicator: View {
    let selected: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    selected ? PlayerTheme.accent : PlayerTheme.secondaryText,
                    lineWidth: 1.5
                )
            if selected {
                Circle()
                    .fill(PlayerTheme.accent)
                    .padding(5)
            }
        }
        .frame(
            width: PlayerLayoutMetrics.turnChoiceIndicatorDiameter,
            height: PlayerLayoutMetrics.turnChoiceIndicatorDiameter
        )
        .accessibilityHidden(true)
    }
}

#Preview {
    YourMoveSheet(
        choices: PlayerSessionState.fixture.choices,
        prompt: PlayerSessionState.fixture.latestMessage.finalQuestion,
        safeAreaBottom: 34,
        cancel: {},
        submit: { _ in }
    )
    .preferredColorScheme(.dark)
}
