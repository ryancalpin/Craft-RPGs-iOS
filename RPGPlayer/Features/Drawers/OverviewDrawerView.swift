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

        var systemImage: String {
            switch self {
            case .overview: "list.bullet.rectangle"
            case .assistant: "sparkles"
            }
        }
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.playerReduceTransparencyOverride) private var reduceTransparencyOverride

    @Binding var state: OverviewDrawerState
    let presentationSettled: Bool
    let safeAreaTop: CGFloat
    let safeAreaBottom: CGFloat
    let close: () -> Void
    var campaignDataContext: CampaignDataContext? = nil
    var campaignDeleted: @MainActor () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            OverviewDrawerHeader(
                selectedSection: $state.selectedSection,
                presentationSettled: presentationSettled,
                close: close,
                campaignDataContext: campaignDataContext,
                campaignDeleted: campaignDeleted
            )

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
            DrawerMaterialBackground(
                isOpaque: PlayerAccessibilityPolicy.reducesTransparency(
                    systemEnabled: reduceTransparency,
                    forcedForTesting: reduceTransparencyOverride
                )
            )
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
    var assistantActionsExpanded = true
    var assistantMessages = AssistantFixtureMessage.initialMessages
    var assistantScrollPosition: Int?
}

private struct OverviewDrawerHeader: View {
    @State private var fixtureSettingsPresented = false
    @State private var campaignDataPresented = false

    @Binding var selectedSection: OverviewDrawerView.Section
    let presentationSettled: Bool
    let close: () -> Void
    let campaignDataContext: CampaignDataContext?
    let campaignDeleted: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 0) {
            OverviewSectionTabs(
                selection: $selectedSection,
                presentationSettled: presentationSettled
            )

            DrawerHeaderButton(
                systemName: "gearshape",
                label: "Campaign settings",
                identifier: "overviewDrawerSettings",
                action: openSettings
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
        .alert("Campaign settings", isPresented: $fixtureSettingsPresented) {
            Button("Done", role: .cancel) {}
        } message: {
            Text("Settings are unavailable in this local fixture.")
        }
        .sheet(isPresented: $campaignDataPresented) {
            if let campaignDataContext {
                NavigationStack {
                    CampaignDataView(
                        context: campaignDataContext,
                        campaignDeleted: campaignDeleted
                    )
                }
            }
        }
    }

    private func openSettings() {
        if campaignDataContext == nil {
            fixtureSettingsPresented = true
        } else {
            campaignDataPresented = true
        }
    }
}

private struct OverviewSectionTabs: View {
    @AccessibilityFocusState private var focusedSection: OverviewDrawerView.Section?

    @Binding var selection: OverviewDrawerView.Section
    let presentationSettled: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(OverviewDrawerView.Section.allCases) { section in
                Button {
                    selection = section
                } label: {
                    ViewThatFits(in: .horizontal) {
                        Text(section.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)

                        Image(systemName: section.systemImage)
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(
                        selection == section
                            ? PlayerTheme.primaryText
                            : PlayerTheme.secondaryText
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background {
                        if selection == section {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.white.opacity(0.10))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityLabel(section.title)
                .accessibilityIdentifier(section.accessibilityIdentifier)
                .accessibilityAddTraits(
                    selection == section ? .isSelected : []
                )
                .accessibilityFocused($focusedSection, equals: section)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(2)
        .background(
            Color.black.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Campaign panel")
        .onChange(of: presentationSettled, initial: true) { _, settled in
            if settled {
                focusedSection = selection
            }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                .lineLimit(
                    PlayerAccessibilityPolicy.lineLimit(
                        compactLimit: 3,
                        isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
                    )
                )
                .fixedSize(horizontal: false, vertical: true)
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
    @Environment(\.playerReduceMotionOverride) private var reduceMotionOverride

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
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { message in
                            AssistantConversationMessage(message: message)
                                .id(message.id)
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            Button {
                                actionsExpanded.toggle()
                            } label: {
                                HStack(spacing: 8) {
                                    Text("Actions")
                                    Spacer()
                                    Image(systemName: "chevron.forward")
                                        .rotationEffect(
                                            actionsExpanded ? .degrees(90) : .zero
                                        )
                                }
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Actions")
                            .accessibilityValue(
                                actionsExpanded ? "Expanded" : "Collapsed"
                            )
                            .accessibilityIdentifier("assistantActionsDisclosure")

                            if actionsExpanded {
                                VStack(alignment: .leading, spacing: 8) {
                                    AssistantToolResultCard()
                                    Text("No action changes the live campaign until you explicitly confirm it.")
                                        .font(.caption)
                                        .foregroundStyle(PlayerTheme.secondaryText)
                                }
                                .padding(.top, 8)
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(12)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onAppear {
                    guard let scrollPosition else { return }
                    scrollProxy.scrollTo(scrollPosition, anchor: .bottom)
                }
                .onChange(of: messages.count) { _, _ in
                    scrollToLatest(using: scrollProxy)
                }

                Divider().overlay(PlayerTheme.panelStroke)

                AssistantComposerSurface(
                    message: $message,
                    canSend: canSend,
                    send: sendMessage
                )
            }
        }
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        guard let newestMessage = messages.last else { return }
        scrollPosition = newestMessage.id
        if PlayerAccessibilityPolicy.reducesMotion(
            systemEnabled: reduceMotion,
            forcedForTesting: reduceMotionOverride
        ) {
            proxy.scrollTo(newestMessage.id, anchor: .bottom)
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(newestMessage.id, anchor: .bottom)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum Utility {
        case addContext
        case history
        case latest
    }

    @State private var showsContextChip = true
    @State private var selectedUtility: Utility?
    let jumpToLatest: () -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    if showsContextChip {
                        AssistantContextChip {
                            showsContextChip = false
                        }
                    }
                    HStack(spacing: 6) {
                        Spacer(minLength: 0)
                        utilityButtons
                    }
                }
            } else {
                HStack(spacing: 6) {
                    if showsContextChip {
                        AssistantContextChip {
                            showsContextChip = false
                        }
                    }
                    Spacer(minLength: 4)
                    utilityButtons
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .foregroundStyle(PlayerTheme.secondaryText)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("assistantContextBar")
    }

    @ViewBuilder
    private var utilityButtons: some View {
            AssistantUtilityButton(
                systemName: "plus",
                label: "Add context",
                identifier: "assistantAddContextUtility",
                selected: selectedUtility == .addContext
            ) {
                showsContextChip = true
                selectedUtility = selectedUtility == .addContext ? nil : .addContext
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
}

private struct AssistantContextChip: View {
    let close: () -> Void

    var body: some View {
        Button(action: close) {
            HStack(spacing: 6) {
                Text("Visual Assets Needed")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(PlayerTheme.accent.opacity(0.18), in: Capsule())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Visual Assets Needed")
        .accessibilityHint("Remove from assistant context")
        .accessibilityIdentifier("assistantContextChip")
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
            Text("Prepared from three local fixture records • Review only")
                .font(.caption)
                .foregroundStyle(PlayerTheme.secondaryText)
            Label("Current objective: reach the high pass before nightfall", systemImage: "doc.text")
            Label("Open clues: the distant rider and broken watchtower", systemImage: "person.2")
            Label("Visual assets: pass map, rider silhouette, and lantern study", systemImage: "photo.on.rectangle")
            Label("Proposed follow-up: confirm a scene brief before any campaign change", systemImage: "wand.and.stars")
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

private struct AssistantComposerSurface: View {
    @Binding var message: String
    let canSend: Bool
    let send: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            AssistantTokenBar()

            Divider().overlay(PlayerTheme.panelStroke)

            TextField("Let’s Craft…", text: $message, axis: .vertical)
                .lineLimit(1...3)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 39, alignment: .topLeading)
                .accessibilityIdentifier("assistantComposer")

            AssistantComposerFooter(canSend: canSend, send: send)
        }
        .frame(minHeight: 128, idealHeight: 136, maxHeight: 155)
        .background(Color.black.opacity(0.16))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(PlayerTheme.panelStroke)
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
        .background {
            Color.clear
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Assistant composer surface")
                .accessibilityIdentifier("assistantComposerSurface")
                .accessibilityRespondsToUserInteraction(false)
                .allowsHitTesting(false)
        }
    }
}

private struct AssistantTokenBar: View {
    var body: some View {
        HStack(spacing: 4) {
            Label("3.8K context", systemImage: "gauge.with.dots.needle.67percent")
                .font(.caption)
                .foregroundStyle(PlayerTheme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 4)
            AssistantComposerControl(
                systemName: "doc",
                label: "Attach document",
                identifier: "assistantDocumentControl"
            )
            AssistantComposerControl(
                systemName: "text.badge.plus",
                label: "Add context",
                identifier: "assistantContextControl"
            )
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("assistantTokenBar")
    }
}

private struct AssistantComposerFooter: View {
    let canSend: Bool
    let send: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            AssistantComposerControl(
                systemName: "plus",
                label: "Add to prompt",
                identifier: "assistantComposerAdd"
            )

            Button(action: {}) {
                HStack(spacing: 5) {
                    Text("GPT-5.6 Luna")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(Color.white.opacity(0.07), in: Capsule())
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("GPT-5.6 Luna")
            .accessibilityIdentifier("assistantModelPicker")

            Spacer(minLength: 0)

            Button(action: send) {
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
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send to campaign assistant")
            .accessibilityIdentifier("sendAssistantMessage")
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
    }
}

private struct AssistantComposerControl: View {
    let systemName: String
    let label: LocalizedStringKey
    let identifier: String

    var body: some View {
        Button(action: {}) {
            Image(systemName: systemName)
                .font(.caption.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
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
            text: "I can summarize the local campaign record, trace the open clues, and prepare a visual brief for the next scene. Every proposed action stays local until you confirm it."
        ),
        AssistantFixtureMessage(
            id: 2,
            role: .user,
            text: "Prepare a local summary of the road ahead, including the watchtower, the rider, and the visual assets the next scene may need."
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
                .accessibilityLabel(
                    message.role == .user
                        ? "You, \(message.text)"
                        : "Campaign Assistant, \(message.text)"
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
