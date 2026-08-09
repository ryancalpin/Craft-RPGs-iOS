# TestFlight Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the integrated app into a reliable, accessible, privacy-accurate TestFlight build with reproducible release configuration, migration/recovery guarantees, and measured performance.

**Architecture:** Release hardening adds no new gameplay architecture. It verifies the existing boundaries under production build settings, centralizes environment configuration, instruments only redacted operational metrics, and makes every failure recoverable through the local event log or durable-job cursor.

**Tech Stack:** Xcode 26, XCTest/XCUITest, Swift Testing where already adopted, MetricKit, OSLog with privacy annotations, Accessibility Inspector, Instruments, ActivityKit, App Store Connect/TestFlight

## Global Constraints

- Execute after Phases 1–5.
- No release fixture, development endpoint, test key, debug menu, or supplied Craft campaign content may enter the archive.
- Do not claim universal background execution; describe durable mode and device-only mode accurately.
- The app is 18+ because imported/AI-generated content may be mature.
- Accessibility findings require device/Inspector validation; screenshots alone are insufficient.
- All privacy answers must match runtime behavior and backend retention.

## Task 1: Centralize Release Configuration

**Files:**

- Create: `RPGPlayer/Config/Debug.xcconfig`
- Create: `RPGPlayer/Config/Release.xcconfig`
- Create: `RPGPlayer/Config/TestFlight.xcconfig`
- Create: `RPGPlayer/App/AppEnvironment.swift`
- Create: `RPGPlayer/Scripts/verify-release.sh`
- Test: `RPGPlayer/RPGPlayerTests/AppEnvironmentTests.swift`

- [ ] Define typed environments for local, development, TestFlight, and production service URLs.
- [ ] Fail release build if localhost, development Cloudflare hostname, test encryption key, fixture launch flag, or debug entitlement is present.
- [ ] Keep all secrets out of xcconfig and repository; document Keychain/wrangler/App Store Connect setup.
- [ ] Generate version/build values through CI inputs and ensure migration schema versions are explicit.
- [ ] Make `verify-release.sh` scan archive strings, entitlements, embedded fixtures, privacy manifest, and signing identities.
- [ ] Commit `build: centralize testflight release configuration`.

## Task 2: Complete Data Migrations and Corruption Recovery

**Files:**

- Create: `RPGPlayer/Infrastructure/Persistence/CampaignMigrationPlan.swift`
- Create: `RPGPlayer/Features/Recovery/StoreRecoveryView.swift`
- Test: `RPGPlayer/RPGPlayerTests/MigrationTests.swift`
- Fixtures: `RPGPlayer/Fixtures/Stores/v1/`

- [ ] Open and migrate every committed store schema fixture to the current version.
- [ ] Verify event payload backward decoding before schema migration.
- [ ] Detect corrupted checkpoints and rebuild them from events.
- [ ] If the event log itself is unreadable, preserve a diagnostic copy, offer recovery-bundle restore, and never silently reset.
- [ ] Test disk-full during append/import/cache, interrupted migration, and backup exclusion attributes.
- [ ] Commit `feat: add migration and corruption recovery`.

## Task 3: Run Full Accessibility Remediation

**Files:**

- Modify: all primary feature views identified by the audit
- Create: `RPGPlayer/RPGPlayerUITests/AccessibilityFlowTests.swift`
- Create: `RPGPlayer/docs/accessibility-test-matrix.md`

- [ ] Validate header, both drawers, VN title/dialogue, transcript, Your Move, roll, generation, voice, import, settings, and Live Activity.
- [ ] Use accessibility labels/values for speaker, mood, beat count, Auto, drawer state, generation phase, roll expression/result, and selected choice.
- [ ] Trap VoiceOver focus in open drawers and restore it to the invoking header button on dismissal.
- [ ] Test Dynamic Type through AX5; allow scrolling/growth instead of clipping or shrinking essential text.
- [ ] Test Reduce Motion, Reduce Transparency, Bold Text, Button Shapes, Differentiate Without Color, Voice Control, and Switch Control.
- [ ] Verify all interactive targets are at least 44×44 points.
- [ ] Measure contrast over dark, bright, and high-detail user art; tune adaptive scrims/materials without changing hierarchy.
- [ ] Commit `fix: complete player accessibility remediation`.

## Task 4: Measure and Fix Performance

**Files:**

- Create: `RPGPlayer/RPGPlayerTests/PerformanceTests.swift`
- Create: `RPGPlayer/docs/performance-budgets.md`
- Modify: transcript, scene image, audio cache, and projection loader implementations as measured

- [ ] Measure warm first meaningful player render against the 500 ms target.
- [ ] Measure drawer animation at 60 fps on the oldest supported physical device.
- [ ] Load a 10,000-block synthetic transcript and verify initial rendering uses the newest 30 plus lazy history pages.
- [ ] Downsample scene/cutout images off the main actor to display dimensions.
- [ ] Keep stable identities and narrow observation so streaming status does not redraw the full transcript.
- [ ] Measure peak memory under 250 MB for one scene background, two cutouts, long transcript, and streaming audio.
- [ ] Capture Instruments Time Profiler, Allocations, Leaks, and hangs baselines.
- [ ] Commit `perf: meet native player budgets`.

## Task 5: Harden Network and Failure Recovery

**Files:**

- Create: `RPGPlayer/RPGPlayerUITests/NetworkChaosTests.swift`
- Create: `RPGPlayer/docs/failure-recovery-matrix.md`

- [ ] Exercise offline, high latency, packet loss, DNS failure, TLS failure, provider 429/5xx, APNs delay, WebSocket drop, and duplicate server events.
- [ ] Verify drafts, job cursors, partial audio, and canonical event batches behave according to the recovery matrix.
- [ ] Confirm retries are bounded with jitter and respect provider retry hints.
- [ ] Verify foreground refresh reconciles server truth after stale Live Activity state.
- [ ] Verify local play remains available when the durable service is unavailable.
- [ ] Commit `test: harden network and recovery paths`.

## Task 6: Perform Security and Privacy Verification

**Files:**

- Create: `RPGPlayer/PrivacyInfo.xcprivacy`
- Create: `RPGPlayer/docs/privacy-data-map.md`
- Create: `RPGPlayer/docs/security-checklist.md`
- Test: `RPGPlayer/RPGPlayerTests/SecretLeakageTests.swift`
- Test: `RPGPlayer/Backend/test/privacy-boundary.test.ts`

- [ ] Map every collected, local-only, transmitted, retained, and deleted data category.
- [ ] Declare required-reason APIs and third-party SDK manifests.
- [ ] Confirm Craft credentials/cookies are never collected and imported content is user-selected.
- [ ] Scan app container, logs, crash captures, exports, backend logs, R2 metadata, and UI snapshots for sentinel secrets.
- [ ] Validate certificate handling, App Attest replay protection, job ownership, rate limits, archive traversal defenses, and deletion.
- [ ] Document model-provider and ElevenLabs direct/durable processing choices in plain language.
- [ ] Commit `security: verify release privacy boundaries`.

## Task 7: Complete Visual Fidelity Regression

**Files:**

- Create: `RPGPlayer/RPGPlayerUITests/CanonicalVisualStateTests.swift`
- Create: `RPGPlayer/docs/visual-regression-matrix.md`
- Modify: only views/tokens with measured mismatches

- [ ] Capture the nine canonical states at 430×932 points with deterministic fixture art/content.
- [ ] Place each app capture beside the matching recording frame in a comparison image.
- [ ] Check full-bleed crop, header vertical position, centered title, drawer widths, scene slivers, top gradients, material opacity, corner radii, text scale/weight, control placement, transcript density, and sheet height.
- [ ] Verify left drawer is about 72% width and right drawer about 90%; neither becomes a desktop split view.
- [ ] Verify VN controls remain immediately above the bottom card and Your Move stays pinned above the home indicator.
- [ ] Resolve every visual audit blocker and document any intentional native/accessibility difference.
- [ ] Run the same states in light accessibility settings, Reduce Transparency, and maximum text size without changing the normal-state target.
- [ ] Commit `fix: lock recording-faithful visual regression`.

## Task 8: Validate Live Activity and Background Behavior on Device

**Files:**

- Create: `RPGPlayer/docs/device-background-test-matrix.md`
- Create: `RPGPlayer/RPGPlayerUITests/LiveActivityLaunchTests.swift`

- [ ] Test Dynamic Island compact/minimal/expanded and Lock Screen states on a compatible iPhone.
- [ ] Submit a durable job, background, lock, switch apps, apply memory pressure, terminate, reboot, and return.
- [ ] Verify remote status continues, deep link restores the correct campaign/job, and final commit occurs once.
- [ ] Verify Stop semantics before/after the provider can cancel.
- [ ] Verify device-only mode expires gracefully without corrupting state and shows truthful recovery copy.
- [ ] Test iOS 18 fallback and iOS 26 continued-processing enhancement separately.
- [ ] Commit `test: validate real-device background continuity`.

## Task 9: Prepare TestFlight Product Material

**Files:**

- Create: `RPGPlayer/docs/testflight-release-notes.md`
- Create: `RPGPlayer/docs/app-review-notes.md`
- Create: `RPGPlayer/docs/support-and-privacy-copy.md`

- [ ] Explain that the app imports user-owned RPG project files and does not connect to Craft accounts.
- [ ] Explain BYOK providers, optional ElevenLabs, optional durable processing, retention, and deletion.
- [ ] Set 18+ age positioning and describe possible mature AI output.
- [ ] Provide review steps using bundled non-Craft demo content and a development-safe provider stub if reviewer networking is unavailable.
- [ ] Avoid Craft marks in the name, subtitle, icon, screenshots, and metadata.
- [ ] Prepare tester notes for import, Your Move, Visual Novel, voice, background, Dynamic Island, recovery, and feedback.
- [ ] Commit `docs: prepare transparent testflight materials`.

## Task 10: Archive and Release Candidate Gate

**Files:**

- Create: `RPGPlayer/Scripts/archive-testflight.sh`
- Create: `RPGPlayer/docs/release-checklist.md`

- [ ] Run all iOS and backend checks from clean dependency installs.
- [ ] Run `verify-release.sh` before archive and fail on any forbidden artifact.
- [ ] Archive with the TestFlight configuration, distribution signing, production APNs, and production durable service URL.
- [ ] Validate the exported archive, dSYM upload, privacy manifest, entitlements, app group, associated scheme, and Activity extension.
- [ ] Install the archived build on a clean device and execute the full product acceptance journey from the master plan.
- [ ] Record build number, commit SHA, backend deployment version, schema versions, and test evidence in the release checklist.
- [ ] Commit `release: prepare rpgplayer testflight candidate`.

## Phase 6 Completion Gate

- [ ] Clean install, upgrade, migration, corruption recovery, export, and restore pass.
- [ ] Accessibility matrix passes with real tools/devices.
- [ ] Performance budgets pass on the oldest supported device.
- [ ] Visual comparison has no unresolved blockers.
- [ ] Durable and device-only background behavior matches product copy.
- [ ] Privacy manifests, data map, retention, and TestFlight disclosures agree.
- [ ] Release archive contains no secret, fixture, Craft mark, or development endpoint.
- [ ] The full acceptance journey passes twice from a clean TestFlight install.
