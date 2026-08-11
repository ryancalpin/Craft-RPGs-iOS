import SwiftUI

struct PlayerShellView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var fixtureState: PlayerSessionState
    @State private var measuredHeaderHeight = PlayerTheme.controlHeight
    @State private var headerFocusRequest: GameHeaderFocus?
    @State private var projectSearchText = ""
    @State private var packageSheetPresented = false
    @State private var overviewDrawerState: OverviewDrawerState
    @State private var drawerPresentationSettled = true
    @State private var stableContainerSafeAreaBottom: CGFloat = 0
    @GestureState private var drawerDragOffset: CGFloat = 0
    @State private var projectSearchFocused = false
    @State private var pendingSubmission: PlayerSubmission?
    @State private var generationSteps: [String] = []
    @State private var generationTask: Task<Void, Never>?
    @State private var yourMoveFocusRequest = false
    private let sessionModel: PlayerSessionModel?
    private let turnStreaming: (any TurnStreaming)?
    private let exposesTurnContextForTesting: Bool
    private let forcedDynamicTypeSize: DynamicTypeSize?
    private let forcesReduceMotionForTesting: Bool
    private let forcesReduceTransparencyForTesting: Bool
    private let exposesAccessibilityEnvironmentForTesting: Bool
    private let campaignDataContext: CampaignDataContext?
    private let exitCampaign: @MainActor () -> Void
    private let campaignDeleted: @MainActor () -> Void

    private var state: PlayerSessionState {
        sessionModel?.state ?? fixtureState
    }

    init(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        campaignDataContext: CampaignDataContext? = nil,
        campaignDeleted: @escaping @MainActor () -> Void = {}
    ) {
        sessionModel = nil
        turnStreaming = SimulatedTurnStreaming(delay: .milliseconds(1_000))
        self.campaignDataContext = campaignDataContext
        exitCampaign = {}
        self.campaignDeleted = campaignDeleted
        var initialState = PlayerSessionState.fixture
        var initialGenerationSteps: [String] = []
        switch Self.fixtureName(in: arguments) {
        case "visual-novel":
            initialState.mode = .visualNovel
        case "generation":
            initialState.generation = .voicing
            initialState.activeRequestID = "visual-fixture"
            initialGenerationSteps = [
                "Loaded the latest campaign state.",
                "Prepared the next scene outline.",
                "Applied the player action to the world state.",
                "Drafted the next story beat.",
                "Prepared dialogue and narration."
            ]
        default:
            break
        }
        exposesTurnContextForTesting = arguments.contains(
            "-turn-sheet-geometry-test"
        )
        forcedDynamicTypeSize = arguments.contains(
            "-dynamic-type-accessibility-test"
        ) ? .accessibility5 : nil
        forcesReduceMotionForTesting = arguments.contains(
            "-reduce-motion-test"
        )
        forcesReduceTransparencyForTesting = arguments.contains(
            "-reduce-transparency-test"
        )
        exposesAccessibilityEnvironmentForTesting = arguments.contains(
            "-accessibility-environment-test"
        )
        _fixtureState = State(initialValue: initialState)
        _generationSteps = State(initialValue: initialGenerationSteps)
        _overviewDrawerState = State(initialValue: OverviewDrawerState())
    }

    init(
        model: PlayerSessionModel,
        campaignDataContext: CampaignDataContext,
        exitCampaign: @escaping @MainActor () -> Void,
        campaignDeleted: @escaping @MainActor () -> Void
    ) {
        guard let initialState = model.state else {
            preconditionFailure("A live player session must be loaded before display")
        }
        sessionModel = model
        turnStreaming = nil
        self.campaignDataContext = campaignDataContext
        self.exitCampaign = exitCampaign
        self.campaignDeleted = campaignDeleted
        exposesTurnContextForTesting = false
        forcedDynamicTypeSize = nil
        forcesReduceMotionForTesting = false
        forcesReduceTransparencyForTesting = false
        exposesAccessibilityEnvironmentForTesting = false
        _fixtureState = State(initialValue: initialState)
        _generationSteps = State(initialValue: [])
        _overviewDrawerState = State(
            initialValue: OverviewDrawerState(live: true)
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let safeAreaTop = PlayerLayoutMetrics.safeAreaInset(proxy.safeAreaInsets.top)
            let safeAreaBottom = PlayerLayoutMetrics.safeAreaInset(proxy.safeAreaInsets.bottom)
            let effectiveTypeSize = forcedDynamicTypeSize ?? dynamicTypeSize
            let presentationSafeAreaTop = PlayerAccessibilityPolicy.presentationSafeAreaTop(
                baseSafeAreaTop: safeAreaTop,
                measuredHeaderHeight: measuredHeaderHeight,
                isAccessibilitySize: effectiveTypeSize.isAccessibilitySize
            )

            ZStack {
                if exposesAccessibilityEnvironmentForTesting {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Accessibility environment")
                        .accessibilityValue(
                            "Reduce Motion, Reduce Transparency"
                        )
                        .accessibilityIdentifier("accessibilityEnvironment")
                        .accessibilityRespondsToUserInteraction(false)
                        .allowsHitTesting(false)
                }

                SceneCanvasView()
                    .accessibilityHidden(
                        state.drawer != .none || state.isTurnSheetPresented
                    )
                    .accessibilitySortPriority(1)

                TopLegibilityGradient()

                presentationContent(
                    availableHeight: proxy.size.height
                        + safeAreaTop
                        + safeAreaBottom,
                    safeAreaTop: presentationSafeAreaTop,
                    safeAreaBottom: safeAreaBottom
                )
                .accessibilityHidden(
                    state.drawer != .none
                        || (state.isTurnSheetPresented
                            && !exposesTurnContextForTesting)
                )
                .accessibilitySortPriority(2)

                VStack(spacing: 0) {
                    GameHeaderView(
                        title: state.campaignTitle,
                        focusRequest: $headerFocusRequest,
                        openProject: { send(.openDrawer(.project)) },
                        openOverview: { send(.openDrawer(.overview)) }
                    )
                    .onGeometryChange(for: CGFloat.self) { headerProxy in
                        headerProxy.size.height
                    } action: { newHeight in
                        guard newHeight.isFinite,
                              abs(measuredHeaderHeight - newHeight) > 0.5 else {
                            return
                        }
                        measuredHeaderHeight = max(
                            PlayerTheme.controlHeight,
                            newHeight
                        )
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, safeAreaTop)
                .accessibilityHidden(
                    state.drawer != .none || state.isTurnSheetPresented
                )
                .accessibilitySortPriority(3)

                if state.isTurnSheetPresented, state.mode == .transcript {
                    turnSheetOverlay(
                        availableWidth: proxy.size.width,
                        availableHeight: proxy.size.height
                            + safeAreaTop
                            + safeAreaBottom,
                        obscuredBottom: safeAreaBottom,
                        safeAreaBottom: max(
                            stableContainerSafeAreaBottom,
                            PlayerLayoutMetrics.containerSafeAreaBottom(
                                from: safeAreaBottom
                            )
                        )
                    )
                    .transition(turnSheetTransition)
                }

                if state.drawer != .none {
                    DrawerDismissLayer(close: closeDrawer)
                }

                if state.drawer == .project {
                    HStack(spacing: 0) {
                        ProjectDrawerView(
                            searchText: $projectSearchText,
                            searchFocused: $projectSearchFocused,
                            presentationSettled: drawerPresentationSettled,
                            safeAreaTop: safeAreaTop,
                            safeAreaBottom: max(
                                stableContainerSafeAreaBottom,
                                safeAreaBottom
                            ),
                            close: closeDrawer,
                            openPackages: presentPackages,
                            project: sessionModel?.project,
                            exitCampaign: sessionModel == nil
                                ? closeDrawer
                                : exitCampaign
                        )
                            .frame(
                                width: PlayerLayoutMetrics.projectDrawerWidth(
                                    for: proxy.size.width
                                )
                            )
                            .offset(x: min(0, drawerDragOffset))
                            .transition(drawerTransition(edge: .leading))
                        Spacer(minLength: 0)
                    }
                    .simultaneousGesture(projectDismissGesture)
                }

                if state.drawer == .overview {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        OverviewDrawerView(
                            state: $overviewDrawerState,
                            presentationSettled: drawerPresentationSettled,
                            safeAreaTop: safeAreaTop,
                            safeAreaBottom: safeAreaBottom,
                            close: closeDrawer,
                            campaignDataContext: campaignDataContext,
                            campaignDeleted: campaignDeleted,
                            liveContext: liveCampaignOverview
                        )
                            .frame(
                                width: PlayerLayoutMetrics.overviewDrawerWidth(
                                    for: proxy.size.width
                                )
                            )
                            .offset(x: max(0, drawerDragOffset))
                            .transition(drawerTransition(edge: .trailing))
                    }
                    .simultaneousGesture(overviewDismissGesture)
                }

            }
            .ignoresSafeArea(.container, edges: .all)
            .simultaneousGesture(edgeOpeningGesture(screenWidth: proxy.size.width))
            .animation(drawerAnimation, value: state.drawer)
            .onAppear {
                stableContainerSafeAreaBottom = max(
                    stableContainerSafeAreaBottom,
                    PlayerLayoutMetrics.containerSafeAreaBottom(
                        from: safeAreaBottom
                    )
                )
            }
            .onChange(of: proxy.safeAreaInsets.bottom) { _, newValue in
                stableContainerSafeAreaBottom = max(
                    stableContainerSafeAreaBottom,
                    PlayerLayoutMetrics.containerSafeAreaBottom(from: newValue)
                )
            }
            .onDisappear {
                generationTask?.cancel()
                generationTask = nil
            }
        }
        .ignoresSafeArea(
            .keyboard,
            edges: state.drawer == .project ? .bottom : []
        )
        .preferredColorScheme(.dark)
        .environment(
            \.dynamicTypeSize,
            forcedDynamicTypeSize ?? dynamicTypeSize
        )
        .environment(
            \.playerReduceMotionOverride,
            forcesReduceMotionForTesting
        )
        .environment(
            \.playerReduceTransparencyOverride,
            forcesReduceTransparencyForTesting
        )
        .sheet(isPresented: $packageSheetPresented, onDismiss: {
            headerFocusRequest = .project
        }) {
            PackageSheetView()
                .presentationDetents([.fraction(0.83)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
                .presentationBackground(
                    Color(red: 0.025, green: 0.028, blue: 0.035)
                )
        }
    }

    private var drawerAnimation: Animation {
        if effectiveReduceMotion {
            return .easeOut(duration: 0.16)
        }
        return .spring(response: 0.30, dampingFraction: 0.85)
    }

    private var effectiveReduceMotion: Bool {
        PlayerAccessibilityPolicy.reducesMotion(
            systemEnabled: reduceMotion,
            forcedForTesting: forcesReduceMotionForTesting
        )
    }

    private var liveCampaignOverview: LiveCampaignOverview? {
        guard let sessionModel,
              let project = sessionModel.project,
              let projection = sessionModel.projection else {
            return nil
        }
        return LiveCampaignOverview(
            campaignTitle: state.campaignTitle,
            currentSceneTitle: projection.currentScene?.title,
            recordCount: project.records.count,
            submittedActionCount: projection.submittedActions.count,
            pendingDecision: projection.pendingDecision
        )
    }

    @ViewBuilder
    private func presentationContent(
        availableHeight: CGFloat,
        safeAreaTop: CGFloat,
        safeAreaBottom: CGFloat
    ) -> some View {
        if let generation = state.generation {
            GenerationView(
                phase: generation,
                steps: generationSteps,
                safeAreaTop: safeAreaTop,
                safeAreaBottom: safeAreaBottom,
                canStop: state.activeRequestID != nil,
                stop: stopGeneration
            )
        } else {
            switch state.mode {
            case .transcript:
                TranscriptView(
                    messages: state.messages,
                    choiceCount: state.choices.count + 1,
                    usesFixtureCopy: sessionModel == nil,
                    safeAreaTop: safeAreaTop,
                    safeAreaBottom: safeAreaBottom,
                    moveSheetReservation: moveSheetReservation(
                        availableHeight: availableHeight,
                        obscuredBottom: safeAreaBottom
                    ),
                    dockFocusRequest: $yourMoveFocusRequest,
                    openMove: { send(.presentTurnSheet) }
                )
            case .visualNovel:
                VisualNovelView(
                    message: state.latestMessage,
                    beatIndex: state.beatIndex,
                    safeAreaTop: safeAreaTop,
                    safeAreaBottom: safeAreaBottom,
                    previous: { send(.previousBeat) },
                    next: { send(.nextBeat) },
                    close: { send(.setMode(.transcript)) },
                    finish: { send(.finishVisualNovel) }
                )
            }
        }
    }

    private func turnSheetOverlay(
        availableWidth: CGFloat,
        availableHeight: CGFloat,
        obscuredBottom: CGFloat,
        safeAreaBottom: CGFloat
    ) -> some View {
        let sheetHeight = PlayerLayoutMetrics.turnSheetHeight(
            for: availableHeight,
            obscuredBottom: obscuredBottom
        )
        let bottomClearance = PlayerLayoutMetrics.turnSheetBottomClearance(
            obscuredBottom: obscuredBottom
        )

        return ZStack {
            Color.clear
                .contentShape(Rectangle())
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                YourMoveSheet(
                    choices: state.choices,
                    prompt: state.latestMessage.finalQuestion,
                    safeAreaBottom: PlayerLayoutMetrics.turnSheetFooterInset(
                        containerSafeAreaBottom: safeAreaBottom,
                        obscuredBottom: obscuredBottom
                    ),
                    cancel: dismissTurnSheet,
                    submit: submitMove
                )
                .frame(
                    width: PlayerLayoutMetrics.turnSheetWidth(
                        for: availableWidth
                    ),
                    height: sheetHeight
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: PlayerLayoutMetrics.turnSheetCornerRadius,
                        style: .continuous
                    )
                )
                .background {
                    if exposesTurnContextForTesting {
                        Color.clear
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Your Move surface")
                            .accessibilityIdentifier("yourMoveSurface")
                            .accessibilityRespondsToUserInteraction(false)
                            .allowsHitTesting(false)
                    }
                }
                .shadow(color: Color.black.opacity(0.18), radius: 18, y: -6)

                Color.clear
                    .frame(height: bottomClearance)
                    .accessibilityHidden(true)
            }
        }
    }

    private func moveSheetReservation(
        availableHeight: CGFloat,
        obscuredBottom: CGFloat
    ) -> CGFloat? {
        guard state.isTurnSheetPresented else { return nil }
        return PlayerLayoutMetrics.turnSheetHeight(
            for: availableHeight,
            obscuredBottom: obscuredBottom
        ) + PlayerLayoutMetrics.turnSheetBottomClearance(
            obscuredBottom: obscuredBottom
        ) + PlayerLayoutMetrics.turnSheetContextGap(
            obscuredBottom: obscuredBottom
        )
    }

    private static func fixtureName(in arguments: [String]) -> String? {
        guard let fixtureFlag = arguments.firstIndex(of: "-fixture") else {
            return nil
        }
        let valueIndex = arguments.index(after: fixtureFlag)
        guard arguments.indices.contains(valueIndex) else { return nil }
        return arguments[valueIndex]
    }

    private func submitMove(_ submission: PlayerSubmission) {
        guard let turnStreaming else {
            send(.dismissTurnSheet)
            return
        }
        generationTask?.cancel()
        let requestID = UUID().uuidString
        pendingSubmission = submission
        generationSteps = []
        send(.generationStarted(requestID: requestID))
        generationTask = Task { @MainActor in
            do {
                for try await event in turnStreaming.events(for: submission) {
                    guard !Task.isCancelled,
                          state.activeRequestID == requestID else {
                        return
                    }

                    switch event {
                    case .phase(let phase):
                        send(.generationPhaseChanged(phase))
                    case .step(let step):
                        generationSteps.append(step)
                    case .completed(let message):
                        send(
                            .generationCompleted(
                                requestID: requestID,
                                message: message
                            )
                        )
                        pendingSubmission = nil
                        generationSteps = []
                        generationTask = nil
                        return
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                guard state.activeRequestID == requestID else { return }
                pendingSubmission = nil
                generationTask = nil
                send(.generationFailed)
            }
        }
    }

    private func stopGeneration() {
        guard state.activeRequestID != nil else { return }
        generationTask?.cancel()
        generationTask = nil
        pendingSubmission = nil
        send(.generationFailed)
    }

    private func drawerTransition(edge: Edge) -> AnyTransition {
        effectiveReduceMotion ? .opacity : .move(edge: edge)
    }

    private var turnSheetTransition: AnyTransition {
        effectiveReduceMotion ? .opacity : .move(edge: .bottom)
    }

    private func send(_ action: PlayerAction) {
        if let sessionModel {
            Task { @MainActor in
                try? await sessionModel.send(action)
            }
            return
        }

        let tracksDrawerPresentation: Bool
        switch action {
        case .openDrawer, .closeDrawer:
            tracksDrawerPresentation = true
            drawerPresentationSettled = false
        default:
            tracksDrawerPresentation = false
        }

        if tracksDrawerPresentation {
            withAnimation(
                drawerAnimation,
                completionCriteria: .logicallyComplete
            ) {
                fixtureState.reduce(action)
            } completion: {
                drawerPresentationSettled = true
            }
            return
        }

        switch action {
        case .presentTurnSheet, .dismissTurnSheet, .finishVisualNovel:
            withAnimation(drawerAnimation) {
                fixtureState.reduce(action)
            }
        case .setMode:
            withAnimation(.easeOut(duration: effectiveReduceMotion ? 0.12 : 0.20)) {
                fixtureState.reduce(action)
            }
        case .previousBeat, .nextBeat:
            if PlayerAccessibilityPolicy.animatesSpatialChanges(
                reducesMotion: effectiveReduceMotion
            ) {
                withAnimation(.easeOut(duration: 0.20)) {
                    fixtureState.reduce(action)
                }
            } else {
                fixtureState.reduce(action)
            }
        default:
            fixtureState.reduce(action)
        }
    }

    private func dismissTurnSheet() {
        send(.dismissTurnSheet)
        yourMoveFocusRequest = true
    }

    private func closeDrawer() {
        let closingDrawer = state.drawer
        if closingDrawer == .project {
            projectSearchFocused = false
        }
        send(.closeDrawer)
        switch closingDrawer {
        case .project:
            headerFocusRequest = .project
        case .overview:
            headerFocusRequest = .overview
        case .none:
            break
        }
    }

    private func presentPackages() {
        send(.closeDrawer)
        packageSheetPresented = true
    }

    private var projectDismissGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($drawerDragOffset) { value, offset, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                offset = min(0, value.translation.width)
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.predictedEndTranslation.width < -80 {
                    closeDrawer()
                }
            }
    }

    private var overviewDismissGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($drawerDragOffset) { value, offset, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                offset = max(0, value.translation.width)
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.predictedEndTranslation.width > 80 {
                    closeDrawer()
                }
            }
    }

    private func edgeOpeningGesture(screenWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onEnded { value in
                guard state.drawer == .none,
                      !state.isTurnSheetPresented else { return }
                if value.startLocation.x <= 24,
                   value.predictedEndTranslation.width > 80 {
                    send(.openDrawer(.project))
                } else if value.startLocation.x >= screenWidth - 24,
                          value.predictedEndTranslation.width < -80 {
                    send(.openDrawer(.overview))
                }
            }
    }
}

enum PlayerLayoutMetrics {
    static let turnSheetHeightRatio: CGFloat = 1_242.0 / 2_868.0
    static let turnSheetHorizontalInset: CGFloat = 12
    static let turnSheetMaxWidth: CGFloat = 700
    static let turnSheetRestingBottomClearance: CGFloat = 13
    static let turnSheetCornerRadius: CGFloat = 24
    static let turnSheetRestingContextGap: CGFloat = 45
    static let turnSheetContentSpacing: CGFloat = 8
    static let turnChoiceSpacing: CGFloat = 8
    static let turnChoiceMinimumHeight: CGFloat = 72
    static let turnChoiceIndicatorDiameter: CGFloat = 18
    static let turnConfirmChromeSize = CGSize(width: 94, height: 34)
    static let turnConfirmHitHeight: CGFloat = 44
    static let turnConfirmFooterPadding: CGFloat = 7

    static func projectDrawerWidth(for availableWidth: CGFloat) -> CGFloat {
        min(validatedWidth(availableWidth) * 0.72, 420)
    }

    static func overviewDrawerWidth(for availableWidth: CGFloat) -> CGFloat {
        min(validatedWidth(availableWidth) * 0.90, 620)
    }

    static func safeAreaInset(_ inset: CGFloat) -> CGFloat {
        validatedWidth(inset)
    }

    static func turnSheetHeight(
        for availableHeight: CGFloat,
        obscuredBottom: CGFloat = 0
    ) -> CGFloat {
        let fullHeight = validatedWidth(availableHeight)
        let canonicalHeight = fullHeight * turnSheetHeightRatio
        let bottomInset = validatedWidth(obscuredBottom)
        guard bottomInset > 100 else { return canonicalHeight }
        let visibleHeight = max(0, fullHeight - bottomInset)
        return min(canonicalHeight, max(0, visibleHeight - 120))
    }

    static func turnSheetWidth(for availableWidth: CGFloat) -> CGFloat {
        min(
            max(0, validatedWidth(availableWidth) - 2 * turnSheetHorizontalInset),
            turnSheetMaxWidth
        )
    }

    static func turnSheetBottomClearance(obscuredBottom: CGFloat) -> CGFloat {
        validatedWidth(obscuredBottom) > 100
            ? 0
            : turnSheetRestingBottomClearance
    }

    static func turnSheetContextGap(obscuredBottom: CGFloat) -> CGFloat {
        validatedWidth(obscuredBottom) > 100
            ? 0
            : turnSheetRestingContextGap
    }

    static func turnSheetFooterInset(
        containerSafeAreaBottom _: CGFloat,
        obscuredBottom: CGFloat
    ) -> CGFloat {
        _ = validatedWidth(obscuredBottom)
        return turnConfirmFooterPadding
    }

    static func containerSafeAreaBottom(from inset: CGFloat) -> CGFloat {
        let value = validatedWidth(inset)
        return value <= 100 ? value : 0
    }

    private static func validatedWidth(_ availableWidth: CGFloat) -> CGFloat {
        guard availableWidth.isFinite else { return 0 }
        return max(0, availableWidth)
    }
}

private struct SceneCanvasView: View {
    var body: some View {
        ZStack {
            PlayerTheme.canvas

            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.10, blue: 0.17),
                    Color(red: 0.10, green: 0.12, blue: 0.20),
                    Color(red: 0.02, green: 0.035, blue: 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [PlayerTheme.accent.opacity(0.24), .clear],
                center: UnitPoint(x: 0.72, y: 0.30),
                startRadius: 10,
                endRadius: 280
            )

            Image(systemName: "mountain.2.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.black.opacity(0.34))
                .frame(maxWidth: .infinity)
                .offset(y: 176)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Campaign scene")
        .accessibilityIdentifier("sceneCanvas")
    }
}

private struct TopLegibilityGradient: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.black.opacity(0.78), Color.black.opacity(0.28), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 150)
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct DrawerDismissLayer: View {
    let close: () -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(perform: close)
            .accessibilityHidden(true)
    }
}

#Preview("Player Shell") {
    PlayerShellView()
}
