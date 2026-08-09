# Native Player Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Build a runnable native iOS player shell that reproduces the recording-verified transcript, Visual Novel, drawer, player-turn, and generation states using deterministic fixture data.

**Architecture:** A pure PlayerSessionState reducer owns navigation and presentation state while focused SwiftUI views render that state. Phase 1 uses a fixture repository and simulated generation stream behind protocols so import, real model providers, voice, and durable jobs can replace adapters without rewriting the UI.

**Tech Stack:** Swift 6, SwiftUI, XCTest/XCUITest, ActivityKit, WidgetKit, Xcode 26, XcodeGen

## Global Constraints

- iOS 18.0 minimum deployment target.
- Swift 6 strict concurrency.
- Bundle identifier com.calpinlabs.rpgplayer and app group group.com.calpinlabs.rpgplayer.
- The supplied iPhone recording is the geometry and behavior source of truth.
- Do not bundle captured Craft artwork, logos, copy, credentials, or cookies.
- Do not add third-party runtime dependencies in Phase 1.
- Use fixture-owned gradients so the shell is distributable.
- Every primary control needs an accessibility label and a 44-point hit target.
- Only one drawer may be open.
- Visual Novel and transcript modes render the same GMMessage.
- Run xcodebuild on macOS; the current Linux workspace cannot execute Xcode or Simulator tests.

---

## File Structure

~~~text
project.yml
Config/App-Info.plist
Config/RPGPlayer.entitlements
Config/TurnActivityExtension-Info.plist
RPGPlayer/App/RPGPlayerApp.swift
RPGPlayer/App/AppMetadata.swift
Shared/GenerationPhase.swift
RPGPlayer/Domain/PlayerModels.swift
RPGPlayer/Domain/PlayerSessionState.swift
RPGPlayer/Domain/PlayerFixtures.swift
RPGPlayer/DesignSystem/PlayerTheme.swift
RPGPlayer/Features/Player/PlayerShellView.swift
RPGPlayer/Features/Player/GameHeaderView.swift
RPGPlayer/Features/Drawers/ProjectDrawerView.swift
RPGPlayer/Features/Drawers/OverviewDrawerView.swift
RPGPlayer/Features/VisualNovel/VisualNovelView.swift
RPGPlayer/Features/Transcript/TranscriptView.swift
RPGPlayer/Features/Turn/YourMoveDock.swift
RPGPlayer/Features/Turn/YourMoveSheet.swift
RPGPlayer/Features/Generation/GenerationView.swift
RPGPlayer/Services/TurnStreaming.swift
Shared/TurnActivityAttributes.swift
TurnActivityExtension/TurnActivityWidget.swift
RPGPlayerTests/PlayerSessionStateTests.swift
RPGPlayerTests/PlayerFixtureTests.swift
RPGPlayerTests/TurnSimulationTests.swift
RPGPlayerUITests/PlayerShellUITests.swift
~~~

### Task 1: Scaffold the App and Test Targets

**Files:**
- Create: project.yml
- Create: Config/App-Info.plist
- Create: Config/RPGPlayer.entitlements
- Create: RPGPlayer/App/RPGPlayerApp.swift
- Create: RPGPlayer/App/AppMetadata.swift
- Test: RPGPlayerTests/AppMetadataTests.swift
- Test: RPGPlayerUITests/LaunchTests.swift

**Interfaces:**
- Produces: AppMetadata.displayName, app target RPGPlayer, unit-test target, and UI-test target.

- [ ] **Step 1: Write the failing metadata test**

~~~swift
import XCTest
@testable import RPGPlayer

final class AppMetadataTests: XCTestCase {
    func testDisplayNameUsesWorkingProductName() {
        XCTAssertEqual(AppMetadata.displayName, "RPGPlayer")
    }
}
~~~

~~~swift
import XCTest

final class LaunchTests: XCTestCase {
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertEqual(app.state, .runningForeground)
    }
}
~~~

- [ ] **Step 2: Add project.yml and generate the Xcode project**

~~~yaml
name: RPGPlayer
options:
  bundleIdPrefix: com.calpinlabs
  deploymentTarget:
    iOS: "18.0"
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
targets:
  RPGPlayer:
    type: application
    platform: iOS
    sources: [RPGPlayer]
    info:
      path: Config/App-Info.plist
    entitlements:
      path: Config/RPGPlayer.entitlements
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.calpinlabs.rpgplayer
  RPGPlayerTests:
    type: bundle.unit-test
    platform: iOS
    sources: [RPGPlayerTests]
    dependencies:
      - target: RPGPlayer
  RPGPlayerUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [RPGPlayerUITests]
    dependencies:
      - target: RPGPlayer
schemes:
  RPGPlayer:
    build:
      targets:
        RPGPlayer: all
    test:
      targets:
        - RPGPlayerTests
        - RPGPlayerUITests
~~~

Run:

~~~bash
xcodegen generate
xcodebuild test -project RPGPlayer.xcodeproj -scheme RPGPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max,OS=latest' \
  -only-testing:RPGPlayerTests/AppMetadataTests
~~~

Expected: compilation fails because AppMetadata is missing.

- [ ] **Step 3: Implement the app entry point**

~~~swift
enum AppMetadata {
    static let displayName = "RPGPlayer"
}

import SwiftUI

@main
struct RPGPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            Text(AppMetadata.displayName)
                .preferredColorScheme(.dark)
        }
    }
}
~~~

Config/App-Info.plist must include CFBundleDisplayName, UILaunchScreen, NSSupportsLiveActivities=true, and remote-notification background mode. The entitlements file must include group.com.calpinlabs.rpgplayer and development APNs.

- [ ] **Step 4: Run the metadata test and generic simulator build**

Expected: test passes and the app target compiles.

- [ ] **Step 5: Commit**

~~~bash
git add project.yml Config RPGPlayer/App RPGPlayerTests/AppMetadataTests.swift
git commit -m "build: scaffold native RPG player"
~~~

---

### Task 2: Implement the Deterministic Player State Machine

**Files:**
- Create: Shared/GenerationPhase.swift
- Create: RPGPlayer/Domain/PlayerModels.swift
- Create: RPGPlayer/Domain/PlayerSessionState.swift
- Modify: project.yml
- Test: RPGPlayerTests/PlayerSessionStateTests.swift

**Interfaces:**
- Produces: PlayerSessionState, PlayerAction, PlayerMode, PlayerDrawer, GenerationPhase, GMMessage, VisualNovelBeat, and PlayerChoice.

- [ ] **Step 1: Write reducer tests**

~~~swift
import XCTest
@testable import RPGPlayer

final class PlayerSessionStateTests: XCTestCase {
    func testOpeningRightDrawerReplacesLeftDrawer() {
        var state = makeState()
        state.reduce(.openDrawer(.project))
        state.reduce(.openDrawer(.overview))
        XCTAssertEqual(state.drawer, .overview)
    }

    func testBeatNavigationClampsToMessageBounds() {
        var state = makeState()
        state.reduce(.setMode(.visualNovel))
        state.reduce(.previousBeat)
        XCTAssertEqual(state.beatIndex, 0)
        for _ in 0..<20 { state.reduce(.nextBeat) }
        XCTAssertEqual(state.beatIndex, state.latestMessage.beats.count - 1)
    }

    func testCompletedGenerationInstallsMessageOnce() {
        var state = makeState()
        let message = makeMessage(id: UUID())
        state.reduce(.generationStarted(requestID: "request-1"))
        state.reduce(.generationCompleted(requestID: "request-1", message: message))
        state.reduce(.generationCompleted(requestID: "request-1", message: message))
        XCTAssertEqual(state.messages.filter { $0.id == message.id }.count, 1)
        XCTAssertEqual(state.mode, .visualNovel)
    }

    private func makeState() -> PlayerSessionState {
        PlayerSessionState(
            campaignTitle: "Test Campaign",
            mode: .transcript,
            drawer: .none,
            beatIndex: 0,
            messages: [makeMessage(id: UUID())],
            choices: [],
            isTurnSheetPresented: false,
            generation: nil,
            activeRequestID: nil,
            completedRequestIDs: []
        )
    }

    private func makeMessage(id: UUID) -> GMMessage {
        GMMessage(
            id: id,
            prose: ["Test narration"],
            dialogue: [],
            actionCount: 0,
            finalQuestion: "What do you do?",
            beats: [
                VisualNovelBeat(id: UUID(), kind: .narration, title: nil, subtitle: nil, speaker: "Narrator", mood: nil, text: "First"),
                VisualNovelBeat(id: UUID(), kind: .dialogue, title: nil, subtitle: nil, speaker: "Guide", mood: "Calm", text: "Second")
            ]
        )
    }
}
~~~

- [ ] **Step 2: Run the tests**

Expected: compilation fails because the domain types are missing.

- [ ] **Step 3: Add the domain types**

Add Shared to the RPGPlayer target source list in project.yml before regenerating the project: sources: [RPGPlayer, Shared].

~~~swift
import Foundation

enum PlayerMode: Equatable, Sendable { case transcript, visualNovel }
enum PlayerDrawer: Equatable, Sendable { case none, project, overview }

// Shared/GenerationPhase.swift
import Foundation

enum GenerationPhase: String, Codable, Hashable, Sendable {
    case queued, readingWorld, planning, updatingWorld, writingScene, voicing, ready, needsAttention

    var displayText: String {
        switch self {
        case .queued: "Getting ready…"
        case .readingWorld: "Consulting the lore…"
        case .planning: "Connecting the dots…"
        case .updatingWorld: "Updating the world…"
        case .writingScene: "Weaving the story…"
        case .voicing: "Giving everyone a voice…"
        case .ready: "Ready"
        case .needsAttention: "Needs attention"
        }
    }
}

// RPGPlayer/Domain/PlayerModels.swift
import Foundation

struct DialogueBlock: Identifiable, Equatable, Sendable {
    let id: UUID
    let speaker: String
    let mood: String?
    let text: String
}

struct VisualNovelBeat: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable { case title, narration, dialogue }
    let id: UUID
    let kind: Kind
    let title: String?
    let subtitle: String?
    let speaker: String?
    let mood: String?
    let text: String
}

struct GMMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let prose: [String]
    let dialogue: [DialogueBlock]
    let actionCount: Int
    let finalQuestion: String
    let beats: [VisualNovelBeat]
}

struct PlayerChoice: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let detail: String
}
~~~

- [ ] **Step 4: Add the reducer**

~~~swift
import Foundation

struct PlayerSessionState: Equatable, Sendable {
    var campaignTitle: String
    var mode: PlayerMode
    var drawer: PlayerDrawer
    var beatIndex: Int
    var messages: [GMMessage]
    var choices: [PlayerChoice]
    var isTurnSheetPresented: Bool
    var generation: GenerationPhase?
    var activeRequestID: String?
    var completedRequestIDs: Set<String>

    var latestMessage: GMMessage { messages[messages.count - 1] }

    mutating func reduce(_ action: PlayerAction) {
        switch action {
        case .openDrawer(let value): drawer = value
        case .closeDrawer: drawer = .none
        case .setMode(let value):
            mode = value
            beatIndex = min(beatIndex, max(0, latestMessage.beats.count - 1))
        case .previousBeat: beatIndex = max(0, beatIndex - 1)
        case .nextBeat: beatIndex = min(max(0, latestMessage.beats.count - 1), beatIndex + 1)
        case .presentTurnSheet: isTurnSheetPresented = true
        case .dismissTurnSheet: isTurnSheetPresented = false
        case .generationStarted(let requestID):
            activeRequestID = requestID
            generation = .queued
            isTurnSheetPresented = false
        case .generationPhaseChanged(let phase): generation = phase
        case .generationCompleted(let requestID, let message):
            guard activeRequestID == requestID,
                  completedRequestIDs.insert(requestID).inserted else { return }
            if !messages.contains(where: { $0.id == message.id }) { messages.append(message) }
            generation = nil
            activeRequestID = nil
            beatIndex = 0
            mode = .visualNovel
        case .generationFailed: generation = .needsAttention
        }
    }
}

enum PlayerAction: Equatable, Sendable {
    case openDrawer(PlayerDrawer)
    case closeDrawer
    case setMode(PlayerMode)
    case previousBeat
    case nextBeat
    case presentTurnSheet
    case dismissTurnSheet
    case generationStarted(requestID: String)
    case generationPhaseChanged(GenerationPhase)
    case generationCompleted(requestID: String, message: GMMessage)
    case generationFailed
}
~~~

- [ ] **Step 5: Run tests and commit**

Expected: reducer tests pass.

~~~bash
git add RPGPlayer/Domain RPGPlayerTests/PlayerSessionStateTests.swift
git commit -m "feat: add deterministic player state machine"
~~~

---

### Task 3: Add Recording-Shaped Fixtures and Design Tokens

**Files:**
- Create: RPGPlayer/Domain/PlayerFixtures.swift
- Create: RPGPlayer/DesignSystem/PlayerTheme.swift
- Test: RPGPlayerTests/PlayerFixtureTests.swift

**Interfaces:**
- Produces: PlayerSessionState.fixture, GMMessage.fixture(id:), and PlayerTheme.

- [ ] **Step 1: Write fixture integrity tests**

~~~swift
final class PlayerFixtureTests: XCTestCase {
    func testFixtureSupportsBothPresentations() {
        let fixture = PlayerSessionState.fixture
        XCTAssertFalse(fixture.latestMessage.prose.isEmpty)
        XCTAssertGreaterThanOrEqual(fixture.latestMessage.beats.count, 3)
        XCTAssertFalse(fixture.choices.isEmpty)
    }

    func testEveryFixtureIdentifierIsUnique() {
        let fixture = PlayerSessionState.fixture
        let ids = fixture.latestMessage.beats.map(\.id) + fixture.choices.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }
}
~~~

- [ ] **Step 2: Run and verify failure**

Expected: fixture members are missing.

- [ ] **Step 3: Add deterministic app-owned fixture copy**

Use three beats: title, narrator, and character dialogue. Use two prose paragraphs, one inset dialogue, a collapsed action count, a final question, and three player choices. Use fixed UUIDs for every fixture item so UI tests remain deterministic. Use original campaign copy such as “The Ascendant Road” and do not copy story text from the recording.

- [ ] **Step 4: Add design tokens**

~~~swift
import SwiftUI

enum PlayerTheme {
    static let canvas = Color(red: 0.025, green: 0.04, blue: 0.065)
    static let panel = Color(red: 0.045, green: 0.075, blue: 0.12).opacity(0.92)
    static let panelStroke = Color.white.opacity(0.12)
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.62)
    static let accent = Color(red: 0.88, green: 0.66, blue: 0.19)
    static let pageInset: CGFloat = 16
    static let controlHeight: CGFloat = 52
    static let panelRadius: CGFloat = 22
}
~~~

- [ ] **Step 5: Run tests and commit**

~~~bash
git add RPGPlayer/Domain/PlayerFixtures.swift RPGPlayer/DesignSystem RPGPlayerTests/PlayerFixtureTests.swift
git commit -m "feat: add recording-shaped player fixtures"
~~~

---

### Task 4: Build the Scene Shell, Header, and Drawers

**Files:**
- Create: RPGPlayer/Features/Player/GameHeaderView.swift
- Create: RPGPlayer/Features/Player/PlayerShellView.swift
- Create: RPGPlayer/Features/Drawers/ProjectDrawerView.swift
- Create: RPGPlayer/Features/Drawers/OverviewDrawerView.swift
- Modify: RPGPlayer/App/RPGPlayerApp.swift
- Test: RPGPlayerUITests/PlayerShellUITests.swift

**Interfaces:**
- Produces accessibility identifiers projectDrawerButton, overviewDrawerButton, projectDrawer, overviewDrawer, closeProjectDrawer, and sceneCanvas.

- [ ] **Step 1: Write the drawer UI test**

~~~swift
func testDrawersOpenAsOverlaysAndRemainExclusive() {
    let app = XCUIApplication()
    app.launchArguments = ["-fixture", "player-shell"]
    app.launch()

    app.buttons["projectDrawerButton"].tap()
    XCTAssertTrue(app.otherElements["projectDrawer"].waitForExistence(timeout: 2))
    app.buttons["closeProjectDrawer"].tap()
    app.buttons["overviewDrawerButton"].tap()
    XCTAssertTrue(app.otherElements["overviewDrawer"].waitForExistence(timeout: 2))
    XCTAssertFalse(app.otherElements["projectDrawer"].exists)
}
~~~

- [ ] **Step 2: Run and verify failure**

Expected: identifiers are missing.

- [ ] **Step 3: Implement the persistent header**

~~~swift
struct GameHeaderView: View {
    let title: String
    let openProject: () -> Void
    let openOverview: () -> Void

    var body: some View {
        HStack {
            Button(action: openProject) { Image(systemName: "line.3.horizontal") }
                .accessibilityIdentifier("projectDrawerButton")
            Spacer()
            Text(title).font(.headline).lineLimit(1)
            Spacer()
            Button(action: openOverview) { Image(systemName: "sidebar.right") }
                .accessibilityIdentifier("overviewDrawerButton")
        }
        .frame(minHeight: 44)
        .foregroundStyle(PlayerTheme.primaryText)
        .padding(.horizontal, PlayerTheme.pageInset)
    }
}
~~~

- [ ] **Step 4: Implement the shell and recording proportions**

Use a full-bleed app-owned gradient scene, a top legibility gradient, and a ZStack. The left drawer width is proxy.size.width * 0.72. The right drawer width is proxy.size.width * 0.90 and is trailing-aligned. Both use move transitions; Reduce Motion switches to opacity. Only state.drawer determines presentation, so mutual exclusion is structural.

ProjectDrawerView contains Exit Game, Files/Search tabs, a fixture file tree, Settings, Trash, and a local profile. OverviewDrawerView contains Overview/Assistant tabs and collapsible Music, Scene Map, Pinned File, and Character Sheet modules. Neither view includes a persistent rail.

Replace the temporary Text(AppMetadata.displayName) root in RPGPlayerApp with PlayerShellView at the end of this step.

- [ ] **Step 5: Run UI tests and commit**

~~~bash
git add RPGPlayer/App RPGPlayer/Features RPGPlayerUITests
git commit -m "feat: add native scene shell and overlay drawers"
~~~

---

### Task 5: Implement Visual Novel Presentation

**Files:**
- Create: RPGPlayer/Features/VisualNovel/VisualNovelView.swift
- Modify: RPGPlayer/Features/Player/PlayerShellView.swift
- Test: RPGPlayerUITests/PlayerShellUITests.swift

**Interfaces:**
- Produces visualNovelCard, previousBeat, nextBeat, closeVisualNovel, and narrationControl identifiers.

- [ ] **Step 1: Write the beat progression UI test**

~~~swift
func testVisualNovelAdvancesAndClosesIntoTranscript() {
    let app = XCUIApplication()
    app.launchArguments = ["-fixture", "visual-novel"]
    app.launch()
    XCTAssertTrue(app.otherElements["visualNovelCard"].exists)
    app.buttons["nextBeat"].tap()
    XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 1))
    app.buttons["closeVisualNovel"].tap()
    XCTAssertTrue(app.otherElements["transcriptSurface"].waitForExistence(timeout: 1))
}
~~~

- [ ] **Step 2: Run and verify failure**

- [ ] **Step 3: Implement the view**

VisualNovelView consumes one GMMessage and current beat index. It fills remaining scene space, uses an app-owned character silhouette placeholder for non-title beats, positions Previous/count/Narration/Close directly above one bottom card, and shows Continue. The last beat uses “End of scene — your move” and switches to transcript plus the player-turn sheet. Closing preserves beatIndex.

The dialogue card uses PlayerTheme.panel, a 22-point radius, avatar, speaker, mood pill, Dynamic Type story text, and no model selector or extra status strip.

- [ ] **Step 4: Route PlayerMode from PlayerShellView**

Use a switch over state.mode. Header remains visible in both modes.

- [ ] **Step 5: Run UI and reducer tests, then commit**

~~~bash
git add RPGPlayer/Features/VisualNovel RPGPlayer/Features/Player RPGPlayerUITests
git commit -m "feat: reproduce mobile visual novel flow"
~~~

---

### Task 6: Implement Transcript and Your Move Sheet

**Files:**
- Create: RPGPlayer/Features/Transcript/TranscriptView.swift
- Create: RPGPlayer/Features/Turn/YourMoveDock.swift
- Create: RPGPlayer/Features/Turn/YourMoveSheet.swift
- Modify: RPGPlayer/Features/Player/PlayerShellView.swift
- Test: RPGPlayerUITests/PlayerShellUITests.swift

**Interfaces:**
- Produces PlayerSubmission(action:additionalContext:).

- [ ] **Step 1: Write the validation UI test**

~~~swift
func testYourMoveSheetRequiresAnAction() {
    let app = XCUIApplication()
    app.launchArguments = ["-fixture", "player-shell"]
    app.launch()
    app.buttons["yourMoveDock"].tap()
    XCTAssertFalse(app.buttons["confirmMove"].isEnabled)
    app.buttons["Stay in the shadow"].tap()
    XCTAssertTrue(app.buttons["confirmMove"].isEnabled)
}
~~~

- [ ] **Step 2: Run and verify failure**

- [ ] **Step 3: Implement the dock**

~~~swift
struct YourMoveDock: View {
    let choiceCount: Int
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                Image(systemName: "checklist")
                VStack(alignment: .leading) {
                    Text("Your Move").font(.headline)
                    Text("The GM is waiting — tap to view \(choiceCount) choices")
                        .font(.caption)
                        .foregroundStyle(PlayerTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.up")
            }
            .padding(16)
            .frame(minHeight: 72)
            .background(PlayerTheme.panel, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("yourMoveDock")
    }
}
~~~

- [ ] **Step 4: Implement transcript and sheet behavior**

TranscriptView renders every prose paragraph in one continuous material surface, character dialogue as inset blocks, one collapsed Actions row, and the final question. YourMoveDock is pinned with safeAreaInset.

YourMoveSheet uses single-select suggestion rows, Type something, a multiline TextEditor, Add additional context, and Confirm. Confirm stays disabled until a suggestion or trimmed custom action exists.

~~~swift
struct PlayerSubmission: Equatable, Sendable {
    let action: String
    let additionalContext: String
}
~~~

Submission immediately dismisses the sheet and dispatches generationStarted with a fresh UUID request ID.

- [ ] **Step 5: Run tests and commit**

~~~bash
git add RPGPlayer/Features/Transcript RPGPlayer/Features/Turn RPGPlayer/Features/Player RPGPlayerUITests
git commit -m "feat: add transcript and player turn sheet"
~~~

---

### Task 7: Add Simulated Generation and Live Activity Contract

**Files:**
- Create: RPGPlayer/Services/TurnStreaming.swift
- Create: RPGPlayer/Features/Generation/GenerationView.swift
- Create: Shared/TurnActivityAttributes.swift
- Create: TurnActivityExtension/TurnActivityWidget.swift
- Create: Config/TurnActivityExtension-Info.plist
- Modify: project.yml
- Test: RPGPlayerTests/TurnSimulationTests.swift
- Modify: RPGPlayer/Features/Player/PlayerShellView.swift

**Interfaces:**
- Produces TurnStreaming.events(for:) as AsyncThrowingStream<TurnStreamEvent, Error>.

- [ ] **Step 1: Write the ordered stream test**

~~~swift
func testSimulationEndsWithExactlyOneMessage() async throws {
    let service = SimulatedTurnStreaming(delay: .zero)
    var phases: [GenerationPhase] = []
    var messages: [GMMessage] = []

    for try await event in service.events(
        for: PlayerSubmission(action: "Wait", additionalContext: "")
    ) {
        if case .phase(let phase) = event { phases.append(phase) }
        if case .completed(let message) = event { messages.append(message) }
    }

    XCTAssertEqual(phases, [.readingWorld, .planning, .updatingWorld, .writingScene, .voicing])
    XCTAssertEqual(messages.count, 1)
}
~~~

- [ ] **Step 2: Run and verify missing service types**

- [ ] **Step 3: Implement the service seam**

~~~swift
enum TurnStreamEvent: Equatable, Sendable {
    case phase(GenerationPhase)
    case step(String)
    case completed(GMMessage)
}

protocol TurnStreaming: Sendable {
    func events(for submission: PlayerSubmission)
        -> AsyncThrowingStream<TurnStreamEvent, Error>
}
~~~

SimulatedTurnStreaming emits the five phases in the asserted order, one sanitized step per phase, then one fixture GMMessage and finish. A zero duration skips sleeps; UI fixtures use 700 milliseconds.

- [ ] **Step 4: Implement generation presentation**

GenerationView reuses the Visual Novel bottom-card geometry. It shows phase.displayText and a disclosure list of sanitized steps. It never shows hidden model reasoning. Stop cancels the active Task and dispatches generationFailed only when cancellation is user initiated.

- [ ] **Step 5: Add ActivityKit contract and widget**

~~~swift
import ActivityKit
import Foundation

struct TurnActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let phase: GenerationPhase
        let status: String
        let startedAt: Date
        let canCancel: Bool
    }

    let campaignID: UUID
    let campaignTitle: String
    let turnID: String
}
~~~

TurnActivityWidget renders Lock Screen, compact, minimal, and expanded Dynamic Island states. It performs no networking. Use a deep link to the active turn.

Add the TurnActivityExtension app-extension target to project.yml, include TurnActivityExtension and Shared as its sources, set PRODUCT_BUNDLE_IDENTIFIER to com.calpinlabs.rpgplayer.turn-activity, set APPLICATION_EXTENSION_API_ONLY to YES, and add it as an RPGPlayer target dependency. Regenerate the project before building.

- [ ] **Step 6: Run tests and commit**

~~~bash
git add RPGPlayer/Services RPGPlayer/Features/Generation Shared TurnActivityExtension RPGPlayerTests
git commit -m "feat: add generation flow and live activity contract"
~~~

---

### Task 8: Accessibility, Motion, and Fidelity QA

**Files:**
- Modify: all primary feature views
- Modify: RPGPlayerUITests/PlayerShellUITests.swift
- Create: docs/qa/native-player-shell-checklist.md

**Interfaces:**
- Produces a verified Phase 1 shell and device checklist.

- [ ] **Step 1: Add large-text and Reduce Motion UI launches**

Launch once with accessibility XXXL and once with Reduce Motion. Assert the header, drawers, Visual Novel controls, transcript, and Your Move remain hittable.

- [ ] **Step 2: Run before adjustments**

Expected: at least one compact row clips at accessibility XXXL.

- [ ] **Step 3: Apply adaptive rules**

Use ViewThatFits for compact rows, fixedSize for story blocks, minimum 44-point content shapes, opaque semantic surfaces under Reduce Transparency, and opacity transitions under Reduce Motion. Never cap story text below accessibility3.

- [ ] **Step 4: Execute this physical-device checklist**

~~~markdown
- [ ] iPhone 16 Pro Max portrait: header matches recording proportions
- [ ] iPhone 16 Pro portrait: no horizontal clipping
- [ ] Left drawer covers 72% ± 2% and leaves a scene sliver
- [ ] Right drawer covers 90% ± 2% and leaves a scene sliver
- [ ] Visual Novel title, narration, and dialogue retain scene artwork
- [ ] Transcript is one continuous material surface
- [ ] Your Move remains above the home indicator
- [ ] Choice sheet supports suggestion, custom text, context, and cancellation
- [ ] Generation phases and sanitized steps are visible
- [ ] Reduce Motion and Reduce Transparency remain usable
- [ ] VoiceOver traversal follows visual order
- [ ] No captured Craft asset or trademark appears in the bundle
~~~

- [ ] **Step 5: Run the full suite and unsigned archive**

~~~bash
xcodebuild test -project RPGPlayer.xcodeproj -scheme RPGPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max,OS=latest'
xcodebuild archive -project RPGPlayer.xcodeproj -scheme RPGPlayer \
  -destination 'generic/platform=iOS' \
  -archivePath build/RPGPlayer-Phase1.xcarchive CODE_SIGNING_ALLOWED=NO
~~~

Expected: tests pass and the archive is produced.

- [ ] **Step 6: Commit**

~~~bash
git add RPGPlayer TurnActivityExtension Shared RPGPlayerTests RPGPlayerUITests docs/qa
git commit -m "test: harden native player shell"
~~~

---

## Phase 1 Completion Gate

Phase 1 is complete only when a fixture campaign demonstrates this loop:

1. Launch into transcript mode over a scene.
2. Open and dismiss each recording-proportioned drawer.
3. Expand Your Move, select or type an action, and confirm.
4. Observe ordered generation phases and sanitized steps.
5. Receive exactly one completed GM message.
6. Advance that message through Visual Novel beats.
7. Return to transcript mode without duplicate data or lost position.

Real CDF import, provider credentials, ElevenLabs streaming, APNs, and durable execution begin after this gate passes.
