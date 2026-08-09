# RPGPlayer Native iOS Implementation Specification

**Status:** Visual direction approved from the August 9, 2026 iPhone recording

**Working title:** RPGPlayer. This is an internal name; no Craft trademark, logo, or copied product artwork ships with the app.

**Execution plans:** `docs/superpowers/plans/2026-08-09-rpgplayer-complete-implementation.md` and its six linked phase plans.

**Visual contract:** `docs/visual-audit/native-craft-mobile-fidelity.md` with recording-derived evidence in `docs/visual-audit/evidence/`.

## 1. Product Goal

Build a standalone, native SwiftUI player for imported AI-RPG projects. The app preserves the interaction model demonstrated by Craft's mobile player while running its own local campaign state, model connections, narration, and durable turn jobs.

The first release is personal/TestFlight software. It imports user-exported content and does not authenticate with Craft, call undocumented Craft gameplay endpoints, scrape Craft pages, or synchronize play back to Craft.

## 2. Source of Truth

The supplied 57-second iPhone recording is the source of truth for mobile geometry and behavior. Generated mockups communicate intent but do not override the recording.

The verified mobile hierarchy is:

1. Full-bleed scene artwork remains the canvas in every gameplay state.
2. The persistent header contains a left menu button, centered campaign title, and right overview button.
3. The left project browser and right overview/assistant panel are slide-over drawers, not persistent rails.
4. Visual Novel mode displays one beat at a time over the scene.
5. Transcript mode displays the complete turn in a continuous translucent surface over the scene.
6. Player input begins from the pinned `Your Move` dock and expands into a choice/custom-input sheet.
7. GM generation temporarily occupies the Visual Novel dialogue area with a rotating status and expandable work-step list.

## 3. Platform and Technical Baseline

- Swift 6 with strict concurrency.
- SwiftUI lifecycle.
- iOS 18.0 minimum deployment target.
- iOS 26 enhancements are conditionally adopted for `BGContinuedProcessingTask`.
- ActivityKit Live Activity and Dynamic Island support on compatible devices.
- SwiftData for local records and a pure Swift reducer for deterministic campaign-state projection.
- `URLSession` for HTTPS and WebSocket transport.
- AVFoundation for streamed narration playback and audio-session management.
- Keychain Services for device-held provider credentials.
- No embedded browser in the primary player experience.
- No runtime-downloaded executable code.

## 4. Primary Gameplay States

### 4.1 Transcript Mode

Transcript mode is the default reading and player-input surface.

- The scene image fills the screen beneath the safe areas.
- A dark top gradient protects header legibility without creating a separate navigation bar.
- The transcript scrolls vertically over the scene using one continuous translucent material.
- Narrator prose remains full width.
- Character speech uses compact inset dialogue blocks with avatar, name, mood, and text.
- GM tool mutations appear under a collapsed `Actions` disclosure row.
- The latest GM question ends immediately above the player-input dock.
- A pinned `Your Move` dock remains above the home indicator while the GM is waiting.
- Tapping the dock opens the player-turn sheet.

### 4.2 Player-Turn Sheet

The sheet retains context by covering only the lower portion of the scene.

- Suggested choices use single-select rows with title and optional explanatory text.
- `Type something…` is always available as a custom choice.
- Selecting custom input replaces the choices with a multiline native editor.
- `Add additional context (optional)…` is separate from the in-character action.
- `Confirm` is disabled until a suggested choice or non-empty custom action exists.
- Dice, microphone dictation, and cancellation are native controls within the sheet, not permanent buttons in the transcript.
- Submission is idempotent and immediately produces a player message in the event log.

### 4.3 Visual Novel Mode

Visual Novel mode is a presentation of the same completed GM turn, not a second source of story data.

- Beat 1 may be a title card with scene title and subtitle.
- Later beats show a character cutout over the background when an appropriate asset exists.
- One bottom dialogue card shows speaker avatar, speaker name, mood, and beat text.
- Previous, beat count, narration, and close controls sit directly above the dialogue card.
- `Continue` advances one beat; the final beat returns to transcript/player-turn state.
- Closing Visual Novel mode preserves the current beat index.
- Auto narration advances only after playback completes and never skips a pending roll or player decision.

### 4.4 GM Generation Mode

- The scene and available character cutout remain visible.
- The bottom dialogue card changes to the GM identity, current human-readable status, and a disclosure control.
- Status copy rotates through concise phrases such as `Connecting the dots…`, `Consulting the lore…`, `Updating the world…`, and `Giving everyone a voice…`.
- Expanding the disclosure shows sanitized tool steps, never hidden model reasoning.
- Send becomes Stop while the app is foregrounded.
- The model picker and conflicting controls remain disabled for the active turn.
- Completion atomically installs the final event batch and transitions into Visual Novel mode when enabled.

## 5. Drawer Behavior

### 5.1 Left Project Drawer

- Opens from the header menu button or an intentional edge swipe.
- Covers approximately 72% of compact-width screens and leaves a scene sliver visible.
- Contains Exit Game, Files, Search, project taxonomy, Settings, Trash, and local profile.
- The file tree supports folders, counts, disclosure, type icons, and native search.
- Tapping the scene sliver or swiping left dismisses the drawer.

### 5.2 Right Overview Drawer

- Opens from the header overview button or an intentional trailing-edge swipe.
- Covers approximately 90% of compact-width screens and leaves a narrow scene sliver visible.
- Contains `Overview` and `Assistant` tabs.
- Overview uses collapsible modules for music, scene map, pinned file, and character sheet.
- Assistant has its own transcript and composer and cannot mutate the live story unless an explicit action is confirmed.
- Tapping the scene sliver or swiping right dismisses the drawer.

### 5.3 Drawer Rules

- Only one drawer may be open.
- The gameplay canvas scales by at most 2%; it does not shrink into a desktop split view.
- VoiceOver focus is trapped inside the open drawer.
- Reduce Motion replaces the spring slide with a short opacity transition.

## 6. Campaign Data and Import

### 6.1 Supported Inputs

- User-selected Craft Data Format v2 export.
- Folder-based projects selected through the document picker.
- Archive-based projects after validation and extraction into a staging directory.
- Optional Markdown or plain-text campaign handoff containing previous story history.
- User-selected images, maps, audio, and pronunciation dictionaries.

### 6.2 Import Pipeline

1. Copy the security-scoped source into an app-owned staging directory.
2. Reject path traversal, symlinks escaping the stage, unsupported executable content, oversized entries, and duplicate canonical paths.
3. Parse metadata and file-type definitions before content records.
4. Build a deterministic asset manifest using SHA-256 hashes.
5. Validate references and preserve unknown fields in an extension payload.
6. Present `What I understood` with project title, world summary, player character, system, current scene, unresolved references, and warnings.
7. Commit the staged import atomically only after user confirmation.

CDF contains project/world content rather than complete live-game history. The app must never label a CDF import as a full save restoration. Imported transcript/handoff content is summarized into an explicit checkpoint that the user approves.

## 7. Local Campaign State

The local source of truth is an append-only event log.

Core event families:

- `campaignImported`
- `playerActionSubmitted`
- `gmStatusChanged`
- `gmMessageCommitted`
- `recordPatched`
- `rollRequested`
- `rollResolved`
- `sceneChanged`
- `voiceAssignmentChanged`
- `turnCancelled`
- `turnFailed`

Each event carries a campaign ID, monotonically increasing sequence, request ID, timestamp, schema version, and typed payload. A pure reducer projects the current session, transcript, scene, character records, and pending decisions. Replaying the same event batch produces the same state. Duplicate request IDs and event IDs are ignored.

## 8. AI GM

### 8.1 Providers

The provider abstraction supports OpenAI, Anthropic, Gemini, and OpenRouter without exposing provider-specific types to the player UI.

Each provider adapter must implement:

- model discovery or a curated fallback list;
- streaming text deltas;
- structured tool calls;
- cancellation;
- token and cost metadata when available;
- normalized retryable and terminal errors.

### 8.2 Native Tools

The GM may request only validated app-owned tools:

- read project record;
- search project records;
- patch record fields;
- request dice roll;
- update scene;
- update campaign clock;
- assign or suggest voice;
- attach a generated or imported asset.

Every mutation is validated against the imported schema and converted into events. Invalid tool calls become visible recoverable errors and do not partially mutate state.

### 8.3 Turn Contract

The GM response is a typed envelope containing narration blocks, dialogue blocks, visual-novel beats, proposed state events, pending player decisions, and voice segments. The client validates the complete envelope before committing it.

## 9. Voice and ElevenLabs

- The user can enter an ElevenLabs API key and validate it without storing it in logs or analytics.
- Device-only mode stores the key in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- The app fetches the user's available voices and supports narrator, GM, and per-character assignments.
- Automatic suggestions never overwrite a manual voice assignment.
- Streaming TTS uses ElevenLabs' WebSocket input-streaming endpoint when text arrives incrementally.
- Completed text may use HTTP streaming when that reduces complexity without increasing perceived latency.
- Pronunciation dictionaries are attached at connection initialization.
- Audio is cached by SHA-256 of normalized text, voice, model, settings, and dictionary version.
- Apple speech synthesis is the offline/error fallback.
- Auto mode advances Visual Novel beats after playback and respects silent mode preferences configured inside the app.

## 10. Durable Background Turns and Dynamic Island

The app never treats iOS background execution as a correctness guarantee. `BGContinuedProcessingTask` is an optimization on supported systems; the durable turn job is authoritative.

### 10.1 Durable Job Flow

1. The app writes `playerActionSubmitted` locally with a unique request ID.
2. The app uploads an immutable turn package and receives a durable job ID.
3. The service persists ordered job events and runs model tools, validation, and optional voice generation.
4. The service sends phase updates through ActivityKit push notifications.
5. Foreground clients stream the same ordered events over HTTPS or WebSocket.
6. Reconnecting clients resume from the last acknowledged event sequence.
7. The final validated batch is committed once, even after retries or relaunch.

### 10.2 Live Activity States

- Queued
- Reading the world
- Planning
- Updating the world
- Writing the scene
- Giving everyone a voice
- Ready
- Needs attention

The compact Dynamic Island shows the campaign glyph and phase indicator. The expanded presentation shows campaign title, current status, elapsed time, and Stop when cancellation remains possible. Tapping deep-links to the active turn.

### 10.3 Credential Boundary

Guaranteed continuation with user-owned model or ElevenLabs credentials requires explicit opt-in to job-scoped server processing. Credentials are encrypted in transit and in a short-lived job envelope, decrypted only by the assigned worker, excluded from logs, and destroyed when the job reaches a terminal state or its TTL expires.

If the user declines server processing, the app labels the mode `Device-only · best effort in background`; it cannot promise uninterrupted generation after suspension or termination.

## 11. Security and Privacy

- No Craft credentials or cookies are collected.
- API keys never appear in SwiftData, UserDefaults, crash reports, or analytics.
- Imported projects remain inside the app container unless explicitly exported.
- Logs redact authorization headers, prompts marked private, imported file contents, and character/world text.
- Network requests use TLS and fail closed on invalid certificates.
- Job payloads are deleted after configurable retention, defaulting to immediate deletion after successful client acknowledgement and a 24-hour maximum for failed recovery.
- Local campaign deletion removes events, imported assets, cached narration, and key references after confirmation.

## 12. Accessibility and Motion

- Dynamic Type through accessibility sizes.
- VoiceOver labels for speaker, mood, beat count, drawer state, generation phase, and dice results.
- Minimum 44-by-44 point targets.
- Contrast remains readable over arbitrary imported scene art using adaptive gradients and material opacity.
- Reduce Transparency switches materials to opaque semantic surfaces.
- Reduce Motion disables parallax, spring drawers, and character-cutout transitions.
- Narration controls include rate and auto-advance settings.

## 13. Performance Budgets

- Player shell first meaningful render under 500 ms on an iPhone 16 Pro Max with a warm local store.
- Drawer open animation maintains 60 fps.
- Transcript initially renders only the most recent 30 blocks and virtualizes older content.
- Scene images are decoded to display size and never synchronously decoded on the main actor.
- Peak foreground memory target under 250 MB for a typical scene with one background, two cutouts, transcript, and streaming audio.
- No network or file parsing on the main actor.

## 14. Test Strategy

- Pure reducer unit tests for every event and idempotency rule.
- Import fixtures covering valid CDF v2, unknown fields, broken references, traversal, duplicate paths, and oversized assets.
- Provider contract tests using recorded sanitized responses.
- UI tests for transcript, both drawers, player-turn sheet, Visual Novel progression, generation overlay, interruption, and relaunch.
- Accessibility audit for every primary state.
- Live Activity rendering tests for compact, minimal, and expanded presentations.
- Background recovery test: submit, terminate app, finish job remotely, relaunch, and verify exactly one committed GM turn.

## 15. Delivery Phases

1. Native player shell with fixture data and recording-faithful transitions.
2. Event store and CDF/handoff import.
3. Direct device provider adapters and validated GM tools.
4. ElevenLabs voice assignment, streaming, and playback.
5. Durable turn service, APNs, Live Activity, and reconnection.
6. TestFlight hardening, privacy disclosures, accessibility, performance, and failure recovery.

Each phase must remain runnable and demonstrable without relying on incomplete later phases.
