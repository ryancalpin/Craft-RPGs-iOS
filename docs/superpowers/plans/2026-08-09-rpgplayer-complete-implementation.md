# RPGPlayer Complete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a standalone, recording-faithful native iOS player for imported Craft RPG project data, with local event-sourced campaigns, provider-neutral AI turns, custom ElevenLabs voices, durable background generation, Dynamic Island progress, and TestFlight-ready privacy and reliability.

**Architecture:** The product is split into six independently runnable phases. The iOS app owns presentation, imported content, the append-only campaign event log, state projection, playback, and device credentials. Provider and voice adapters work directly on-device first. An explicitly opted-in Cloudflare service adds durable turn execution without becoming the campaign source of truth; the client reconciles ordered server events into the same reducer used for device-only turns.

**Tech Stack:** Swift 6, SwiftUI, Observation, SwiftData, XCTest/XCUITest, ActivityKit, WidgetKit, AVFoundation, Security/Keychain, URLSession, UniformTypeIdentifiers, Cloudflare Workers, Durable Objects with SQLite storage, Workflows, R2, TypeScript, Zod, Vitest

## Current Implementation Status

**Last reconciled:** August 12, 2026
**Code baseline:** `main` through `4b5140e` (`feat: add bounded streaming HTTP transport`)
**Continuation:** `docs/handoffs/2026-08-12-cloud-continuation.md`
**Worker orchestration:** `docs/superpowers/plans/2026-08-12-gpt-luna-project-orchestration.md`

| Phase | Status | Evidence and next action |
|---|---|---|
| 1 — Native player shell | **Complete** | Canonical Simulator visual-fidelity gate accepted; implementation commits `97f8243` through `4413e20`. Physical-device and real-VoiceOver checks remain release evidence, not Phase 1 gate blockers. |
| 2 — Import and event store | **Complete** | Tasks 1–9 plus real folder/archive acceptance are committed through `ad16d16`; deterministic import, replay, relaunch, recovery, and Phase 1 visual regression gates passed. |
| 3 — AI GM providers and tools | **In progress** | Tasks 1–3 are committed as `b326ebc`, `f91dd24`, and `4b5140e`. Start Task 4: OpenAI and OpenRouter adapters. Tasks 4–11 and the real BYOK completion gate remain. |
| 4 — ElevenLabs/native voice | **Not started** | Begin only after Phase 3 contracts and completion gate are accepted. |
| 5 — Durable turns/Live Activity | **Not started** | May begin after Phase 3; server TTS additionally depends on Phase 4. |
| 6 — TestFlight hardening | **Not started** | Requires Phases 1–5. |

The task checklists in the phase plans remain the executable TDD scripts. A checked item means implemented and verified in its recorded scope; it does not substitute for physical-device, real-provider, or TestFlight acceptance.

## Global Constraints

- The supplied August 9, 2026 iPhone recording is the visual and interaction source of truth.
- This is a faithful native reconstruction, not a redesign.
- Do not ship Craft marks, logos, copied proprietary art, or the supplied campaign content.
- Do not authenticate with Craft, call undocumented Craft endpoints, scrape pages, extract cookies, or sync back to Craft.
- Imports are user-selected CDF v2/project files plus optional transcript handoff, not a promise of complete Craft save restoration.
- Every phase must launch and demonstrate value without unfinished later phases.
- All state-changing operations are idempotent and covered by failure/relaunch tests.
- Direct device credentials remain in Keychain. Durable mode requires an explicit consent screen for job-scoped server processing.
- Device-only mode is labeled `Device-only · best effort in background`; only durable mode may promise continuation after suspension or termination.
- No hidden model reasoning is shown. Generation details contain only sanitized, user-meaningful tool steps.
- Use native SwiftUI controls and platform accessibility behavior while matching Craft's recorded hierarchy, proportions, and transitions.
- Minimum target is iOS 18. iOS 26 background continuation is a conditional enhancement, never the correctness layer.

## Delivery Map

| Phase | Executable plan | Demonstrable outcome | Exit dependency | Current state |
|---|---|---|---|---|
| 1 | `2026-08-09-native-player-shell.md` | Recording-faithful shell with deterministic fixtures | None | Complete |
| 2 | `2026-08-09-cdf-import-event-store.md` | Import a project and persist/replay a local campaign | Phase 1 | Complete |
| 3 | `2026-08-09-ai-gm-providers-tools.md` | Play complete on-device AI turns with validated tools | Phase 2 | Tasks 1–3 complete; Task 4 next |
| 4 | `2026-08-09-elevenlabs-native-voice.md` | Assign custom voices and narrate/auto-advance beats | Phase 3 | Not started |
| 5 | `2026-08-09-durable-turns-live-activity.md` | Continue opted-in turns durably with Dynamic Island status | Phase 3; Phase 4 for server TTS | Not started |
| 6 | `2026-08-09-testflight-hardening.md` | Accessible, recoverable, performant TestFlight build | Phases 1–5 | Not started |

## Cross-Phase Interface Freeze

The following types are compatibility boundaries. Changes require migration tests and updates to every dependent phase:

~~~swift
// Implemented and compatibility-tested in Phase 2.
public struct CampaignEvent: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let campaignID: UUID
    public let sequence: Int64
    public let requestID: UUID
    public let timestamp: Date
    public let schemaVersion: Int
    public let payload: CampaignEventPayload
}

// Implemented and compatibility-tested in Phase 3 Task 1.
public struct TurnRequest: Codable, Sendable, Equatable {
    public let requestID: UUID
    public let campaignID: UUID
    public let expectedSequence: Int64
    public let action: PlayerAction
    public let context: TurnContext
}

// Implemented and compatibility-tested in Phase 3 Task 1.
public struct TurnEnvelope: Codable, Sendable, Equatable {
    public let requestID: UUID
    public let narration: [StoryBlock]
    public let beats: [VisualNovelBeat]
    public let proposedEvents: [ProposedCampaignEvent]
    public let pendingDecision: PlayerDecision?
    public let voiceSegments: [VoiceSegment]
    public let usage: ProviderUsage?
}

public struct VersionedTurnEnvelope: Codable, Sendable, Equatable {
    public static let maximumEncodedBytes = 8_000_000
    public let schemaVersion: Int // currently 1
    public let envelope: TurnEnvelope
}

// Planned Phase 5 boundary; not implemented yet.
public struct JobEvent: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let jobID: UUID
    public let sequence: Int64
    public let phase: GenerationPhase
    public let sanitizedDetail: String?
    public let terminal: JobTerminalState?
}
~~~

Rules:

- `CampaignEvent.sequence` is monotonic per campaign and allocated by the local event store.
- `JobEvent.sequence` is monotonic per durable job and allocated by the job Durable Object.
- A durable final envelope is converted into local events only after full schema and expected-sequence validation.
- The reducer is pure; file, network, keychain, audio, and notification effects live behind protocols.
- UI never switches on provider-specific response types.

## Repository Layout

~~~
.
├── project.yml
├── RPGPlayer/
│   ├── App/
│   ├── Features/
│   │   ├── Drawers/
│   │   ├── Generation/
│   │   ├── Import/
│   │   ├── Player/
│   │   ├── Settings/
│   │   ├── Transcript/
│   │   ├── Turn/
│   │   └── VisualNovel/
│   ├── Domain/
│   │   ├── Campaign/
│   │   ├── Import/
│   │   └── Providers/
│   ├── Infrastructure/
│   │   ├── Persistence/
│   │   ├── Files/
│   │   ├── Networking/
│   │   └── Keychain/
│   └── Services/
├── Shared/
├── TurnActivityExtension/
├── RPGPlayerTests/
├── RPGPlayerUITests/
├── docs/
└── Backend/                 # Planned Phase 5; absent until created.
    ├── src/
    ├── test/
    ├── migrations/
    ├── package.json
    └── wrangler.jsonc
~~~

## Milestone Sequence

### Milestone A — Visual Contract

- [x] Execute Phase 1 through its canonical Simulator completion gate.
- [x] Capture all nine canonical UI states at the recording's 440×956-point (1320×2868-pixel) viewport.
- [x] Compare captures beside the recording-derived visual authority.
- [x] Resolve every Phase 1 visual blocker in `docs/visual-audit/native-craft-mobile-fidelity.md`.
- [x] Freeze the accepted geometry in `PlayerLayoutMetrics` after the comparison pass.

Physical-device, real-VoiceOver, broader device-matrix, and the known accessibility-size XCTest snapshot timeout remain later acceptance evidence and are tracked in `docs/qa/native-player-shell-checklist.md`.

### Milestone B — Local Playable Product

- [x] Execute Phase 2 and prove sanitized folder and archive CDF fixtures through the real staged import/commit pipeline.
- [ ] Exercise the production Files document picker with a user-selected export during the local real-app pass; fixture-driven UI automation does not establish Files-app interaction.
- [x] Kill and relaunch the app; confirm exact projection value equality and the same visible beat/state.
- [x] Complete Phase 3 Tasks 1–3: provider-neutral contracts, private credential settings, and bounded streaming transport.
- [ ] Execute Phase 3 with one real user-supplied provider key.
- [ ] Complete player action → streaming GM → validated tool → roll → final turn.
- [ ] Verify the same fixture still runs with a recorded provider transport and no network.

### Milestone C — Native Voice

- [ ] Execute Phase 4.
- [ ] Validate an ElevenLabs key, fetch user voices, and assign narrator plus one character.
- [ ] Stream narration, interrupt it, resume it, and verify auto-advance waits for completion.
- [ ] Disable network and verify Apple TTS fallback plus cached ElevenLabs audio.

### Milestone D — Durable Continuation

- [ ] Execute Phase 5 in a separate Cloudflare development environment.
- [ ] Submit a turn, background the app, terminate it, complete the job remotely, and relaunch.
- [ ] Reconcile exactly one final GM event batch.
- [ ] Verify the Live Activity reaches `Ready` without exposing imported text or credentials.
- [ ] Verify job credentials and payloads are deleted at terminal acknowledgement or TTL.

### Milestone E — TestFlight Candidate

- [ ] Execute Phase 6.
- [ ] Pass unit, integration, UI, accessibility, performance, privacy, migration, and recovery gates.
- [ ] Produce App Store Connect privacy answers and an 18+ TestFlight description.
- [ ] Archive a release build with no development endpoints, fixture content, or secret files.

## Product Acceptance Journey

The release candidate must pass this uninterrupted scenario:

1. Install on a clean iPhone and choose `Import Project`.
2. Select a CDF v2 export and optional transcript handoff.
3. Review `What I understood`, resolve the player character and current scene, and commit.
4. Open the full-bleed player canvas.
5. Open and dismiss both overlay drawers by buttons, scene-sliver tap, and edge gesture.
6. Open `Your Move`, choose or type an action, add optional context, and confirm.
7. See generation progress in the recording-faithful bottom card.
8. Background the app and follow the same job in the Dynamic Island.
9. Return to a completed Visual Novel title beat and continue through dialogue beats.
10. Hear assigned ElevenLabs voices and verify Auto advances only after audio completion.
11. Close Visual Novel mode and read the same turn in transcript form.
12. Roll a requested check, see the result committed once, and continue.
13. Relaunch and confirm the exact scene, transcript, beat index, voice assignment, and pending decision.
14. Export a local recovery bundle and successfully restore it into a clean test container.

## Program-Level Test Commands

Run after every phase:

~~~bash
xcodegen generate
# Reuse one already-booted Simulator and keep it running.
xcrun simctl list devices booted
xcodebuild test -project RPGPlayer.xcodeproj -scheme RPGPlayer -destination 'platform=iOS Simulator,id=<BOOTED_UDID>' -parallel-testing-enabled NO
~~~

Run when the planned Phase 5 backend exists:

~~~bash
cd Backend
npm ci
npm run check
npm test
~~~

Run the planned Phase 6 release validation after `Scripts/verify-release.sh` exists:

~~~bash
./Scripts/verify-release.sh
~~~

## Change-Control Rules

- A visual change requires updating the matching snapshot/reference test and the visual audit matrix.
- An event schema change requires a decoder compatibility test and store migration.
- A provider contract change requires all adapter contract tests.
- A server job event change requires Swift and TypeScript fixture round-trip tests.
- A background claim change requires a real-device suspension/termination test.
- A credential-boundary change requires an updated consent screen and privacy threat review.

## Definition of Complete

- [ ] All six phase completion gates pass.
- [ ] The visual-fidelity audit has no unresolved blockers.
- [ ] Every primary state works with VoiceOver, Dynamic Type, Reduce Motion, and Reduce Transparency.
- [ ] Device-only and durable mode promises are accurate in UI copy.
- [ ] No Craft authentication, private endpoint, brand asset, or copyrighted fixture ships.
- [ ] A clean TestFlight install can import, play, narrate, background, recover, and export a campaign.
- [ ] The release archive is reproducible from the committed repository and documented secret setup.

## Implementation Handoff

Continue from `docs/handoffs/2026-08-12-cloud-continuation.md` and execute workers through `docs/superpowers/plans/2026-08-12-gpt-luna-project-orchestration.md`. Phase 1 and Phase 2 are complete; Phase 3 Task 4 is the immediate next task. Preserve task order and TDD. GPT Luna is mandatory for every spawned worker after its exact current selector is verified in a fresh session; do not substitute another model. Cloud work may implement deterministic contracts, adapters, fixtures, and unit-tested domain logic, but it must not claim real-provider, physical-device, visual, audio, background, or TestFlight acceptance. Pull the branch back to the local Mac no later than Phase 3 Task 10 integration and the real BYOK/UI completion pass. Phase 4 voice work may run in parallel with Phase 5 only after Phase 3 contracts are frozen.
