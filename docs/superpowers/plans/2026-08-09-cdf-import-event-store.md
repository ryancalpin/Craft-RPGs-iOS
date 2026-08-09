# CDF Import and Event Store Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace fixture-only campaigns with safely imported CDF v2 projects and a deterministic, append-only local campaign store that survives relaunch and supports recovery.

**Architecture:** A staged importer copies user-selected sources into an app-owned quarantine, validates paths and limits, parses content into normalized domain records, and presents an explicit review before atomic commit. SwiftData persists event rows and import manifests; a pure reducer projects player state. Imported source data is immutable, while gameplay changes are events layered above it.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, UniformTypeIdentifiers, CryptoKit, ZIPFoundation locked through Package.resolved, XCTest, XCUITest

## Global Constraints

- Execute after Phase 1.
- Treat CDF as project/world content, not a complete live save.
- Never edit the user-selected source in place.
- Reject traversal, escaping symlinks, duplicate canonical paths, zip bombs, and executable entries before parsing.
- Preserve unknown JSON fields for forward-compatible re-export.
- Import commits are atomic and cancellable before commit.
- The event reducer performs no I/O and is deterministic across process launches.

## Task 1: Define Import and Campaign Domain Contracts

**Files:**

- Create: `RPGPlayer/Domain/Import/ImportSource.swift`
- Create: `RPGPlayer/Domain/Import/ImportLimits.swift`
- Create: `RPGPlayer/Domain/Import/ImportReport.swift`
- Create: `RPGPlayer/Domain/Campaign/CampaignEvent.swift`
- Create: `RPGPlayer/Domain/Campaign/CampaignProjection.swift`
- Test: `RPGPlayer/RPGPlayerTests/DomainContractTests.swift`

- [ ] Write decoding tests for all supported event payloads and one future unknown-field import record.
- [ ] Implement `ImportSource` as folder, archive, and handoff-document cases using security-scoped URLs only at the infrastructure boundary.
- [ ] Set limits to 1 GB total expanded bytes, 10,000 entries, 100 MB per file, 30 levels of path depth, and 20:1 maximum archive expansion ratio.
- [ ] Implement the campaign event envelope exactly as frozen in the master plan.
- [ ] Add stable `schemaVersion = 1` encoding fixtures under `Fixtures/Events/v1/`.
- [ ] Run `xcodebuild test` and commit `feat: define import and campaign event contracts`.

## Task 2: Build Safe Staging and Archive Validation

**Files:**

- Create: `RPGPlayer/Infrastructure/Files/ImportStager.swift`
- Create: `RPGPlayer/Infrastructure/Files/ArchiveInspector.swift`
- Create: `RPGPlayer/Infrastructure/Files/CanonicalPath.swift`
- Create: `RPGPlayer/Infrastructure/Files/FileHashing.swift`
- Test: `RPGPlayer/RPGPlayerTests/ImportStagerTests.swift`
- Fixtures: `RPGPlayer/Fixtures/Imports/Malicious/`

- [ ] Write failing tests for `../escape`, absolute paths, NUL bytes, case-folded duplicates, escaping symlinks, oversized files, too many entries, and expansion-ratio violation.
- [ ] Implement lexical normalization followed by resolved-path containment under a unique `Application Support/ImportStaging/{uuid}` directory.
- [ ] Stream file copies and SHA-256 hashing; never buffer whole assets.
- [ ] Reject file modes with executable bits and ignore macOS metadata entries.
- [ ] Ensure cancellation removes only the validated staging UUID, never the staging parent.
- [ ] Add a test that cancellation leaves the source unchanged.
- [ ] Run tests and commit `feat: add bounded safe import staging`.

## Task 3: Parse CDF v2 into Normalized Records

**Files:**

- Create: `RPGPlayer/Domain/Import/CDFDecoder.swift`
- Create: `RPGPlayer/Domain/Import/CDFDocument.swift`
- Create: `RPGPlayer/Domain/Import/NormalizedProject.swift`
- Create: `RPGPlayer/Domain/Import/ReferenceValidator.swift`
- Test: `RPGPlayer/RPGPlayerTests/CDFDecoderTests.swift`
- Fixtures: `RPGPlayer/Fixtures/Imports/CDFv2/`

- [ ] Add sanitized fixtures for a minimal project, a full project, unknown fields, broken references, duplicate IDs, missing assets, and unsupported record types.
- [ ] Decode metadata and file-type definitions before content records.
- [ ] Normalize project, folders, records, fields, relationships, assets, maps, characters, and schema descriptors into `Sendable` value types.
- [ ] Store unrecognized JSON keys in `[String: JSONValue] extensionPayload`.
- [ ] Convert broken references into review warnings unless they make the root project unreadable.
- [ ] Generate a deterministic manifest sorted by canonical relative path and record ID.
- [ ] Snapshot the normalized result for the full fixture.
- [ ] Run tests and commit `feat: decode and normalize cdf v2 projects`.

## Task 4: Parse Optional Transcript Handoffs

**Files:**

- Create: `RPGPlayer/Domain/Import/HandoffParser.swift`
- Create: `RPGPlayer/Domain/Import/HandoffCheckpoint.swift`
- Create: `RPGPlayer/Features/Import/HandoffMappingView.swift`
- Test: `RPGPlayer/RPGPlayerTests/HandoffParserTests.swift`

- [ ] Write tests for Markdown headings, speaker-prefixed dialogue, plain text, empty input, and ambiguous character names.
- [ ] Parse only structural signals; never silently claim exact recovery.
- [ ] Produce editable fields for summary, current scene, player character, unresolved threads, inventory deltas, and last known player choice.
- [ ] Require explicit user approval before the handoff becomes a `campaignImported` checkpoint payload.
- [ ] Preserve the original handoff file hash and user edits, not the full raw text in analytics or logs.
- [ ] Run tests and commit `feat: add explicit transcript handoff mapping`.

## Task 5: Implement the Append-Only SwiftData Store

**Files:**

- Create: `RPGPlayer/Infrastructure/Persistence/CampaignEventRecord.swift`
- Create: `RPGPlayer/Infrastructure/Persistence/ImportedAssetRecord.swift`
- Create: `RPGPlayer/Infrastructure/Persistence/SwiftDataCampaignStore.swift`
- Create: `RPGPlayer/Domain/Campaign/CampaignStore.swift`
- Test: `RPGPlayer/RPGPlayerTests/CampaignStoreTests.swift`

- [ ] Write tests for atomic batch append, monotonic sequence allocation, duplicate event ID, duplicate request ID, expected-sequence conflict, and rollback on invalid payload.
- [ ] Persist payloads as versioned encoded data with indexed scalar envelope fields.
- [ ] Enforce unique campaign/sequence, campaign/event-ID, and campaign/request-ID constraints in the store logic.
- [ ] Save imported asset hashes and app-owned relative URLs, never security-scoped source bookmarks as permanent dependencies.
- [ ] Add `events(after:limit:)`, `latestSequence`, `append(batch:expectedSequence:)`, and `deleteCampaign`.
- [ ] Prove with an in-memory container test that a failed batch writes zero rows.
- [ ] Run tests and commit `feat: persist append-only campaign events`.

## Task 6: Implement Pure Replay and Checkpoints

**Files:**

- Create: `RPGPlayer/Domain/Campaign/CampaignReducer.swift`
- Create: `RPGPlayer/Domain/Campaign/ProjectionCheckpoint.swift`
- Create: `RPGPlayer/Infrastructure/Persistence/ProjectionLoader.swift`
- Test: `RPGPlayer/RPGPlayerTests/CampaignReducerTests.swift`
- Test: `RPGPlayer/RPGPlayerTests/ProjectionLoaderTests.swift`

- [ ] Write a table-driven reducer test for every event family in the product specification.
- [ ] Add associativity coverage: reducing A+B equals reducing A then B.
- [ ] Add idempotency coverage: duplicate IDs and request IDs do not mutate the projection twice.
- [ ] Add corrupted/out-of-order event detection with a recoverable diagnostics result.
- [ ] Store projection checkpoints every 200 events with source sequence and reducer schema version.
- [ ] On launch, load the newest compatible checkpoint and replay the tail; fall back to full replay if the checkpoint is invalid.
- [ ] Compare a full replay and checkpoint replay for exact equality.
- [ ] Run tests and commit `feat: replay deterministic campaign projections`.

## Task 7: Build the Native Import Review Flow

**Files:**

- Create: `RPGPlayer/Features/Import/ImportCoordinator.swift`
- Create: `RPGPlayer/Features/Import/ImportPickerView.swift`
- Create: `RPGPlayer/Features/Import/ImportProgressView.swift`
- Create: `RPGPlayer/Features/Import/ImportReviewView.swift`
- Create: `RPGPlayer/Features/Import/ImportWarningsView.swift`
- Test: `RPGPlayer/RPGPlayerUITests/ImportFlowTests.swift`

- [ ] Route import as an enum-driven sheet from the campaign library, not from the active player canvas.
- [ ] Use `.fileImporter` with folder, zip, JSON, Markdown, and plain-text content types.
- [ ] Display progress for copy, inspect, parse, validate, and prepare-review phases.
- [ ] Present `What I understood` with title, world summary, player character, system, scene, record counts, missing references, and handoff uncertainty.
- [ ] Disable commit for fatal errors and explain the exact file/path without leaking file content.
- [ ] On confirm, atomically move normalized assets to `Application Support/Campaigns/{campaign-id}` and append the initial event.
- [ ] Add UI tests for cancel, warning review, fatal error, and successful launch into the Phase 1 player shell.
- [ ] Run tests and commit `feat: add native import review and commit flow`.

## Task 8: Add Export, Delete, and Recovery Bundles

**Files:**

- Create: `RPGPlayer/Domain/Campaign/RecoveryBundle.swift`
- Create: `RPGPlayer/Infrastructure/Files/RecoveryBundleWriter.swift`
- Create: `RPGPlayer/Features/Settings/CampaignDataView.swift`
- Test: `RPGPlayer/RPGPlayerTests/RecoveryBundleTests.swift`
- Test: `RPGPlayer/RPGPlayerUITests/CampaignDeletionTests.swift`

- [ ] Define a versioned app-owned recovery archive containing manifest, normalized import, event log, manual voice mappings without keys, and user-owned assets.
- [ ] Write a round-trip test from import → events → export → clean container → restore.
- [ ] Verify hashes before restore and reject partial/tampered archives.
- [ ] Make campaign deletion remove events, assets, audio cache entries, and campaign-scoped key references after native confirmation.
- [ ] Ensure delete cannot target a directory outside the validated campaign UUID path.
- [ ] Run tests and commit `feat: add campaign recovery export and deletion`.

## Task 9: Replace Fixtures in the Player Shell

**Files:**

- Modify: `RPGPlayer/App/AppDependencyGraph.swift`
- Modify: `RPGPlayer/Features/Player/PlayerSessionModel.swift`
- Create: `RPGPlayer/Features/Player/CampaignLibraryView.swift`
- Test: `RPGPlayer/RPGPlayerUITests/PersistenceRelaunchTests.swift`

- [ ] Inject `CampaignStore` and `ProjectionLoader` at the app root; keep fixtures only in previews and UI-test launch arguments.
- [ ] Show imported campaigns in a native library before entering the full-screen player.
- [ ] Preserve one `NavigationStack`; present drawers as player overlays, not navigation destinations.
- [ ] Add a UI test that imports, opens, changes beat index, terminates, relaunches, and restores identical player state.
- [ ] Confirm Phase 1 screenshot tests remain unchanged for the equivalent fixture state.
- [ ] Run the complete iOS test suite and commit `feat: drive player from imported event-sourced campaigns`.

## Phase 2 Completion Gate

- [ ] Valid CDF v2 folder and archive fixtures import through the real staged pipeline.
- [ ] Every malicious fixture is rejected before app-owned campaign commit.
- [ ] The review accurately distinguishes project import from save restoration.
- [ ] Event replay is deterministic, idempotent, and checkpoint-compatible.
- [ ] Export/restore round-trips a campaign exactly.
- [ ] Relaunch returns to the same recording-faithful player state.
- [ ] Phase 1 visual acceptance captures have no regressions.
