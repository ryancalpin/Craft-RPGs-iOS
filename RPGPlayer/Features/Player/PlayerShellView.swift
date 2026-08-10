import SwiftUI

struct PlayerShellView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var state = PlayerSessionState.fixture
    @State private var headerFocusRequest: GameHeaderFocus?
    @State private var projectSearchText = ""
    @State private var packageSheetPresented = false
    @State private var overviewDrawerState = OverviewDrawerState()
    @State private var drawerPresentationSettled = true
    @State private var stableContainerSafeAreaBottom: CGFloat = 0
    @GestureState private var drawerDragOffset: CGFloat = 0
    @State private var projectSearchFocused = false

    var body: some View {
        GeometryReader { proxy in
            let safeAreaTop = PlayerLayoutMetrics.safeAreaInset(proxy.safeAreaInsets.top)
            let safeAreaBottom = PlayerLayoutMetrics.safeAreaInset(proxy.safeAreaInsets.bottom)

            ZStack {
                SceneCanvasView()
                    .accessibilityHidden(state.drawer != .none)

                TopLegibilityGradient()

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
                .accessibilityHidden(state.drawer != .none)

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
                    safeAreaBottom
                )
            }
            .onChange(of: proxy.safeAreaInsets.bottom) { _, newValue in
                stableContainerSafeAreaBottom = max(
                    stableContainerSafeAreaBottom,
                    PlayerLayoutMetrics.safeAreaInset(newValue)
                )
            }
        }
        .ignoresSafeArea(
            .keyboard,
            edges: state.drawer == .project ? .bottom : []
        )
        .preferredColorScheme(.dark)
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

    private func drawerTransition(edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge)
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
                guard state.drawer == .none else { return }
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
    static func projectDrawerWidth(for availableWidth: CGFloat) -> CGFloat {
        min(validatedWidth(availableWidth) * 0.72, 420)
    }

    static func overviewDrawerWidth(for availableWidth: CGFloat) -> CGFloat {
        min(validatedWidth(availableWidth) * 0.90, 620)
    }

    static func safeAreaInset(_ inset: CGFloat) -> CGFloat {
        validatedWidth(inset)
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
