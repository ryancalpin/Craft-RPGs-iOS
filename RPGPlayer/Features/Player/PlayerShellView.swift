import SwiftUI

struct PlayerShellView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var state: PlayerSessionState
    @State private var headerFocusRequest: GameHeaderFocus?
    @State private var projectSearchText = ""
    @State private var packageSheetPresented = false
    @State private var overviewDrawerState = OverviewDrawerState()
    @State private var drawerPresentationSettled = true
    @State private var stableContainerSafeAreaBottom: CGFloat = 0
    @GestureState private var drawerDragOffset: CGFloat = 0
    @State private var projectSearchFocused = false
    @State private var pendingSubmission: PlayerSubmission?
    @State private var generationSteps: [String] = []
    @State private var generationTask: Task<Void, Never>?
    private let turnStreaming: any TurnStreaming
    private let exposesTurnContextForTesting: Bool
    private let forcedDynamicTypeSize: DynamicTypeSize?

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        turnStreaming = SimulatedTurnStreaming(delay: .milliseconds(700))
        var initialState = PlayerSessionState.fixture
        if Self.fixtureName(in: arguments) == "visual-novel" {
            initialState.mode = .visualNovel
        }
        exposesTurnContextForTesting = arguments.contains(
            "-turn-sheet-geometry-test"
        )
        forcedDynamicTypeSize = arguments.contains(
            "-dynamic-type-accessibility-test"
        ) ? .accessibility5 : nil
        _state = State(initialValue: initialState)
    }

    var body: some View {
        GeometryReader { proxy in
            let safeAreaTop = PlayerLayoutMetrics.safeAreaInset(proxy.safeAreaInsets.top)
            let safeAreaBottom = PlayerLayoutMetrics.safeAreaInset(proxy.safeAreaInsets.bottom)

            ZStack {
                SceneCanvasView()
                    .accessibilityHidden(
                        state.drawer != .none || state.isTurnSheetPresented
                    )

                TopLegibilityGradient()

                presentationContent(
                    availableHeight: proxy.size.height
                        + safeAreaTop
                        + safeAreaBottom,
                    safeAreaTop: safeAreaTop,
                    safeAreaBottom: safeAreaBottom
                )
                .accessibilityHidden(
                    state.drawer != .none
                        || (state.isTurnSheetPresented
                            && !exposesTurnContextForTesting)
                )

                VStack(spacing: 0) {
                    GameHeaderView(
                        title: state.campaignTitle,
                        focusRequest: $headerFocusRequest,
                        openProject: { send(.openDrawer(.project)) },
                        openOverview: { send(.openDrawer(.overview)) }
                    )
                    Spacer(minLength: 0)
                }
                .padding(.top, safeAreaTop)
                .accessibilityHidden(
                    state.drawer != .none || state.isTurnSheetPresented
                )

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
                            openPackages: presentPackages
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
                            close: closeDrawer
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
        if reduceMotion {
            return .easeOut(duration: 0.16)
        }
        return .spring(response: 0.30, dampingFraction: 0.85)
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
                    choiceCount: state.choices.count,
                    safeAreaTop: safeAreaTop,
                    safeAreaBottom: safeAreaBottom,
                    moveSheetReservation: moveSheetReservation(
                        availableHeight: availableHeight,
                        obscuredBottom: safeAreaBottom
                    ),
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
                    cancel: { send(.dismissTurnSheet) },
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
        reduceMotion ? .opacity : .move(edge: edge)
    }

    private var turnSheetTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom)
    }

    private func send(_ action: PlayerAction) {
        let tracksDrawerPresentation: Bool
        switch action {
        case .openDrawer, .closeDrawer:
            tracksDrawerPresentation = true
            drawerPresentationSettled = false
        default:
            tracksDrawerPresentation = false
        }

        withAnimation(
            drawerAnimation,
            completionCriteria: .logicallyComplete
        ) {
            state.reduce(action)
        } completion: {
            if tracksDrawerPresentation {
                drawerPresentationSettled = true
            }
        }
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
