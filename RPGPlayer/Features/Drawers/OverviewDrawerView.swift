import SwiftUI

struct OverviewDrawerView: View {
    enum Section: CaseIterable, Identifiable {
        case overview
        case assistant

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .overview: "Overview"
            case .assistant: "Assistant"
            }
        }

        var accessibilityIdentifier: String {
            switch self {
            case .overview: "overviewTab"
            case .assistant: "assistantTab"
            }
        }
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @Binding var state: OverviewDrawerState
    let presentationSettled: Bool
    let safeAreaTop: CGFloat
    let safeAreaBottom: CGFloat
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OverviewDrawerHeader(selectedSection: $state.selectedSection, close: close)

            Divider().overlay(PlayerTheme.panelStroke)

            switch state.selectedSection {
            case .overview:
                CampaignOverviewContent(state: $state)
            case .assistant:
                CampaignAssistantContent(
                    message: $state.assistantDraft,
                    messages: $state.assistantMessages,
                    actionsExpanded: $state.assistantActionsExpanded,
                    scrollPosition: $state.assistantScrollPosition
                )
            }
        }
        .padding(.top, safeAreaTop)
        .padding(.bottom, safeAreaBottom)
        .foregroundStyle(PlayerTheme.primaryText)
        .background {
            DrawerMaterialBackground(isOpaque: reduceTransparency)
                .scaleEffect(x: -1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
        .accessibilityIdentifier("overviewDrawer")
        .accessibilityValue(presentationSettled ? "Settled" : "Transitioning")
    }
}

struct OverviewDrawerState {
    var selectedSection: OverviewDrawerView.Section = .overview
    var musicExpanded = true
    var mapExpanded = true
    var fileExpanded = true
    var characterExpanded = true
    var musicPlaying = false
    var assistantDraft = ""
    var assistantActionsExpanded = false
    var assistantMessages = AssistantFixtureMessage.initialMessages
    var assistantScrollPosition: Int?
}

private struct OverviewDrawerHeader: View {
    @State private var settingsPresented = false

    @Binding var selectedSection: OverviewDrawerView.Section
    let close: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Picker("Campaign panel", selection: $selectedSection) {
                ForEach(OverviewDrawerView.Section.allCases) { section in
                    Text(section.title)
                        .accessibilityIdentifier(section.accessibilityIdentifier)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)

            DrawerHeaderButton(
                systemName: "gearshape",
                label: "Campaign settings",
                identifier: "overviewDrawerSettings",
                action: { settingsPresented = true }
            )

            DrawerHeaderButton(
                systemName: "sidebar.right",
                label: "Close campaign panel",
                identifier: "closeOverviewDrawer",
                action: close
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .alert("Campaign settings", isPresented: $settingsPresented) {
            Button("Done", role: .cancel) {}
        } message: {
            Text("Settings are unavailable in this local fixture.")
        }
    }
}

private struct DrawerHeaderButton: View {
    let systemName: String
    let label: LocalizedStringKey
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.07), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

private struct CampaignOverviewContent: View {
    @Binding var state: OverviewDrawerState

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                OverviewModule(title: "Music Player", systemImage: "music.note", isExpanded: $state.musicExpanded) {
                    HStack(spacing: 12) {
                        Button {
                            state.musicPlaying.toggle()
                        } label: {
                            Image(systemName: state.musicPlaying ? "pause.fill" : "play.fill")
                                .frame(width: 44, height: 44)
                                .background(Color.white.opacity(0.10), in: Circle())
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(state.musicPlaying ? "Pause ambient music" : "Play ambient music")
                        .accessibilityIdentifier("overviewMusicPlay")
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Rain on the High Road").font(.subheadline.weight(.semibold))
                            Text("Ambient • 03:42").font(.caption).foregroundStyle(PlayerTheme.secondaryText)
                        }
                        Spacer()
                    }
                }

                OverviewModule(title: "Scene Map", systemImage: "map", isExpanded: $state.mapExpanded) {
                    FixtureMapPreview()
                }

                OverviewModule(title: "GM Pinned File", systemImage: "pin.fill", isExpanded: $state.fileExpanded) {
                    PinnedFilePreview()
                }

                OverviewModule(title: "Character Sheet", systemImage: "person.text.rectangle", isExpanded: $state.characterExpanded) {
                    VStack(spacing: 8) {
                        CharacterStat(label: "Resolve", value: "3")
                        CharacterStat(label: "Instinct", value: "2")
                        CharacterStat(label: "Wounds", value: "0 / 4")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.visible)
    }
}

private struct FixtureMapPreview: View {
    @State private var zoom: CGFloat = 1
    @State private var expanded = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.teal.opacity(0.72), .blue.opacity(0.50), .black.opacity(0.54)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "map.fill")
                .font(.largeTitle.weight(.light))
                .foregroundStyle(Color.white.opacity(0.70))
                .scaleEffect(zoom)

            Text("High pass map")
                .font(.caption.weight(.semibold))
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            VStack {
                HStack {
                    Spacer()
                    MapControlButton(
                        systemName: expanded
                            ? "arrow.down.right.and.arrow.up.left"
                            : "arrow.up.left.and.arrow.down.right",
                        label: expanded ? "Restore map" : "Expand map",
                        identifier: "overviewMapExpand"
                    ) {
                        expanded.toggle()
                        zoom = expanded ? 1.08 : 1
                    }
                }

                Spacer()

                HStack(spacing: 0) {
                    Spacer()
                    MapControlButton(
                        systemName: "minus",
                        label: "Zoom map out",
                        identifier: "overviewMapZoomOut"
                    ) {
                        zoom = max(0.85, zoom - 0.08)
                    }
                    MapControlButton(
                        systemName: "plus",
                        label: "Zoom map in",
                        identifier: "overviewMapZoomIn"
                    ) {
                        zoom = min(1.25, zoom + 0.08)
                    }
                }
            }
            .padding(6)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("High pass map")
        .accessibilityIdentifier("overviewMapArtwork")
    }
}

private struct MapControlButton: View {
    let systemName: String
    let label: LocalizedStringKey
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption.weight(.semibold))
                .frame(width: 34, height: 34)
                .background(Color.black.opacity(0.62), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

private struct OverviewModule<Content: View>: View {
    let title: String
    let systemImage: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    init(
        title: String,
        systemImage: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 8) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 10) {
                    Label(title.uppercased(), systemImage: systemImage)
                        .font(.caption.weight(.semibold))
                        .tracking(1.5)
                    Spacer()
                    Image(systemName: "chevron.up")
                        .rotationEffect(isExpanded ? .zero : .degrees(180))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                content
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    }
            }
        }
    }
}

private struct FixtureArtwork: View {
    let colors: [Color]
    let systemImage: String
    let label: LocalizedStringKey
    let accessibilityIdentifier: String

    var body: some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: systemImage)
                .font(.largeTitle.weight(.light))
                .foregroundStyle(Color.white.opacity(0.70))
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct PinnedFilePreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FixtureArtwork(
                colors: [.brown.opacity(0.74), .orange.opacity(0.48), .black.opacity(0.58)],
                systemImage: "doc.richtext.fill",
                label: "The Lantern Road",
                accessibilityIdentifier: "overviewPinnedFileArtwork"
            )
            Text("The Lantern Road")
                .font(.headline)
            Text("Quest reference")
                .font(.caption)
                .foregroundStyle(PlayerTheme.secondaryText)
            Text("A local campaign brief with the current objective, known risks, and the clues already discovered.")
                .font(.subheadline)
                .foregroundStyle(PlayerTheme.secondaryText)
                .lineLimit(3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("overviewPinnedFilePreview")
    }
}

private struct CharacterStat: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(PlayerTheme.secondaryText)
        }
    }
}

private struct CampaignAssistantContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var message: String
    @Binding var messages: [AssistantFixtureMessage]
    @Binding var actionsExpanded: Bool
    @Binding var scrollPosition: Int?

    var body: some View {
        ScrollViewReader { scrollProxy in
            VStack(spacing: 0) {
                AssistantContextBar {
                    scrollToLatest(using: scrollProxy)
                }

                Divider().overlay(PlayerTheme.panelStroke)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            AssistantConversationMessage(message: message)
                                .id(message.id)
                        }

                        AssistantToolResultCard()

                        DisclosureGroup("Actions", isExpanded: $actionsExpanded) {
                            Text("No action changes the live campaign until you explicitly confirm it.")
                                .font(.caption)
                                .foregroundStyle(PlayerTheme.secondaryText)
                                .padding(.top, 8)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(12)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("assistantActionsDisclosure")
                    }
                    .padding(16)
                }
                .onAppear {
                    guard let scrollPosition else { return }
                    scrollProxy.scrollTo(scrollPosition, anchor: .center)
                }
                .onChange(of: messages.count) { _, _ in
                    scrollToLatest(using: scrollProxy)
                }

                Divider().overlay(PlayerTheme.panelStroke)

                AssistantTokenBar()

                Divider().overlay(PlayerTheme.panelStroke)

                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Ask about the campaign", text: $message, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 46)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 15))
                        .accessibilityIdentifier("assistantComposer")
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.bold))
                            .frame(width: 44, height: 44)
                            .background(
                                canSend ? PlayerTheme.accent : Color.white.opacity(0.08),
                                in: Circle()
                            )
                            .foregroundStyle(
                                canSend ? Color.black.opacity(0.76) : PlayerTheme.secondaryText
                            )
                    }
                    .disabled(!canSend)
                    .accessibilityLabel("Send to campaign assistant")
                    .accessibilityIdentifier("sendAssistantMessage")
                }
                .padding(12)
            }
        }
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        guard let newestMessage = messages.last else { return }
        scrollPosition = newestMessage.id
        if reduceMotion {
            proxy.scrollTo(newestMessage.id, anchor: .center)
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(newestMessage.id, anchor: .center)
            }
        }
    }

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendMessage() {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        let nextID = (messages.map(\.id).max() ?? 0) + 1
        messages.append(
            AssistantFixtureMessage(id: nextID, role: .user, text: trimmedMessage)
        )
        messages.append(
            AssistantFixtureMessage(
                id: nextID + 1,
                role: .assistant,
                text: "I prepared a local summary and placed any proposed changes under Actions for confirmation."
            )
        )
        message = ""
    }
}

private struct AssistantContextBar: View {
    private enum Utility {
        case records
        case history
        case latest
    }

    @State private var selectedUtility: Utility?
    let jumpToLatest: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(contextLabel)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(minHeight: 30)
                .background(PlayerTheme.accent.opacity(0.18), in: Capsule())

            Spacer(minLength: 4)

            AssistantUtilityButton(
                systemName: "rectangle.and.text.magnifyingglass",
                label: "Campaign records",
                identifier: "assistantRecordsUtility",
                selected: selectedUtility == .records
            ) {
                selectedUtility = selectedUtility == .records ? nil : .records
            }
            AssistantUtilityButton(
                systemName: "clock",
                label: "Assistant history",
                identifier: "assistantHistoryUtility",
                selected: selectedUtility == .history
            ) {
                selectedUtility = selectedUtility == .history ? nil : .history
            }
            AssistantUtilityButton(
                systemName: "chevron.forward.2",
                label: "Jump to latest",
                identifier: "assistantLatestUtility",
                selected: selectedUtility == .latest
            ) {
                selectedUtility = selectedUtility == .latest ? nil : .latest
                jumpToLatest()
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .foregroundStyle(PlayerTheme.secondaryText)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("assistantContextBar")
    }

    private var contextLabel: LocalizedStringKey {
        switch selectedUtility {
        case .records: "3 local records"
        case .history: "3 assistant turns"
        case .latest: "Latest response"
        case nil: "Current: Ascendant Road"
        }
    }
}

private struct AssistantUtilityButton: View {
    let systemName: String
    let label: LocalizedStringKey
    let identifier: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 32, height: 32)
                .background(selected ? Color.white.opacity(0.10) : .clear, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct AssistantToolResultCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Local record summary", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PlayerTheme.primaryText)
            Text("Prepared from three fixture records")
                .font(.caption)
                .foregroundStyle(PlayerTheme.secondaryText)
            Label("Current objective and two open clues", systemImage: "doc.text")
            Label("One proposed follow-up action", systemImage: "wand.and.stars")
        }
        .font(.footnote)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("assistantToolResult")
    }
}

private struct AssistantTokenBar: View {
    var body: some View {
        HStack {
            Label("3.8K context", systemImage: "gauge.with.dots.needle.67percent")
            Spacer()
            Image(systemName: "paperclip")
            Image(systemName: "doc.text.magnifyingglass")
        }
        .font(.caption)
        .foregroundStyle(PlayerTheme.secondaryText)
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("assistantTokenBar")
    }
}

struct AssistantFixtureMessage: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
    }

    let id: Int
    let role: Role
    let text: String

    static let initialMessages = [
        AssistantFixtureMessage(
            id: 1,
            role: .assistant,
            text: "I can summarize local campaign records and prepare actions for your confirmation."
        ),
        AssistantFixtureMessage(
            id: 2,
            role: .user,
            text: "Prepare a local summary of the road ahead."
        ),
        AssistantFixtureMessage(
            id: 3,
            role: .assistant,
            text: "I found three fixture records with a current objective, two unresolved clues, and one proposed follow-up."
        )
    ]
}

private struct AssistantConversationMessage: View {
    let message: AssistantFixtureMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if message.role == .assistant {
                Text("Campaign Assistant").font(.footnote.weight(.semibold))
            }
            Text(message.text)
                .font(.footnote)
                .foregroundStyle(PlayerTheme.secondaryText)
                .accessibilityIdentifier(
                    message.role == .user ? "assistantUserMessage" : "assistantMessage"
                )
        }
        .padding(12)
        .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

#Preview("Overview Drawer") {
    OverviewDrawerView(
        state: .constant(OverviewDrawerState()),
        presentationSettled: true,
        safeAreaTop: 0,
        safeAreaBottom: 0,
        close: {}
    )
        .frame(width: 390)
        .preferredColorScheme(.dark)
}
