# Durable Turns and Live Activity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Guarantee that explicitly opted-in AI turns continue after iOS suspension or termination, while the Dynamic Island and Lock Screen show sanitized progress and the local campaign commits exactly one validated result.

**Architecture:** The iOS app anonymously registers an installation with App Attest, encrypts a bounded immutable turn package with a per-job content key, and submits it to a Worker. One Durable Object per job persists ordered progress and coordinates clients. One Cloudflare Workflow per job performs provider/tool/voice stages with durable retries. R2 stores encrypted input/output artifacts with short TTL. APNs ActivityKit push updates mirror sanitized job events. The iOS event store remains canonical and reconciles final results by request ID and sequence.

**Tech Stack:** Swift 6, ActivityKit, WidgetKit, BackgroundTasks, DeviceCheck/App Attest, CryptoKit/Security, URLSession; Cloudflare Workers, Durable Objects SQLite, Workflows, R2, TypeScript, Zod, Web Crypto, Vitest

**Implementation status (August 12, 2026): NOT STARTED.** Execute only after Phase 3 passes; server voice additionally depends on Phase 4. Worker execution is governed by `docs/superpowers/plans/2026-08-12-gpt-luna-project-orchestration.md`. `Backend/`, `Shared/`, tests, configuration, and the activity extension are repository-root paths.

## Global Constraints

- Execute after Phase 3; integrate server voice only after Phase 4.
- Durable mode is opt-in and explains job-scoped server processing before enabling it.
- Device-only mode remains available and is labeled best effort in background.
- Never use background audio, repeated notifications, or a Live Activity to pretend the app process is always running.
- One Durable Object coordinates one job; never use a global job object.
- Persist every job transition before broadcasting it.
- Server logs contain IDs, phase, latency, and error category only; never prompts, imported text, keys, audio, or provider bodies.
- Job payload maximum is 8 MB JSON plus separately uploaded hashed assets.
- Encrypted input/output is deleted after client acknowledgement, with a hard 24-hour recovery TTL.
- At execution time, retrieve current Cloudflare Workers, Durable Objects, Workflows, and Apple ActivityKit/App Attest APIs before copying platform signatures.

## Task 1: Freeze the Cross-Platform Job Protocol

**Files:**

- Create: `Shared/Jobs/job-protocol.schema.json`
- Create: `RPGPlayer/Domain/Jobs/JobProtocol.swift`
- Create: `Backend/src/protocol.ts`
- Create: `Backend/test/protocol.test.ts`
- Test: `RPGPlayerTests/JobProtocolTests.swift`
- Fixtures: `RPGPlayer/Fixtures/Jobs/v1/`

- [ ] Define schemas for installation challenge/registration, job submission, wrapped credential envelope, job receipt, ordered job event, event page, cancellation, acknowledgement, and final encrypted result.
- [ ] Use UUID strings, signed 64-bit sequence values encoded as JSON numbers within safe range, RFC 3339 timestamps, and `protocolVersion: 1`.
- [ ] Limit phases to queued, readingWorld, planning, updatingWorld, writingScene, voicing, ready, needsAttention, cancelled, and failed.
- [ ] Limit sanitized detail to 160 Unicode scalars and prohibit imported/story content in that field.
- [ ] Generate Swift and TypeScript fixtures from one canonical JSON set and round-trip them in both test suites.
- [ ] Add a compatibility test that ignores additive unknown fields but rejects unknown terminal states.
- [ ] Commit `feat: freeze durable job protocol v1`.

## Task 2: Scaffold the Cloudflare Service

**Files:**

- Create: `Backend/package.json`
- Create: `Backend/tsconfig.json`
- Create: `Backend/wrangler.jsonc`
- Create: `Backend/src/index.ts`
- Create: `Backend/vitest.config.ts`
- Create: `Backend/test/env.d.ts`
- Create: `Backend/.gitignore`

- [ ] Pin package versions through `package-lock.json` and use Node 22 in `.nvmrc`.
- [ ] Set `compatibility_date` to the implementation date, enable `nodejs_compat`, observability, one `TURN_JOB` Durable Object binding, one `TURN_WORKFLOW` Workflow binding, and `JOB_ARTIFACTS` R2 binding.
- [ ] Configure `TurnJob` as a new SQLite class migration.
- [ ] Generate `worker-configuration.d.ts` with `wrangler types`; do not hand-write `Env`.
- [ ] Add scripts `check` for TypeScript/lint/no-floating-promises, `test` for Vitest runtime tests, and `dev` for Wrangler.
- [ ] Store APNs signing key, App Attest verification material, and envelope private key only with Wrangler secrets.
- [ ] Run `npm run check && npm test` and commit `build: scaffold durable turn worker`.

## Task 3: Implement Anonymous Installation Registration

**Files:**

- Create: `Backend/src/auth/installation.ts`
- Create: `Backend/src/auth/app-attest.ts`
- Create: `RPGPlayer/Infrastructure/Networking/InstallationRegistrar.swift`
- Create: `RPGPlayer/Infrastructure/Keychain/InstallationCredentialStore.swift`
- Test: `Backend/test/installation.test.ts`
- Test: `RPGPlayerTests/InstallationRegistrarTests.swift`

- [ ] Issue a one-time 32-byte challenge with a five-minute expiry.
- [ ] Generate and attest an App Attest key on supported devices; use a clearly marked development-device fallback only in debug/TestFlight environments that cannot attest.
- [ ] Verify bundle ID, team ID, challenge hash, counter monotonicity, and assertion signature server-side.
- [ ] Issue a random installation token, store only its SHA-256 digest server-side, and compare fixed-size digests in constant time.
- [ ] Store the token in device-only Keychain and rotate it after 90 days or suspected compromise.
- [ ] Do not collect email, Craft identity, advertising ID, contacts, or device name.
- [ ] Test replayed challenges, cloned assertions, counter rollback, expired token, and wrong bundle.
- [ ] Commit `feat: register anonymous attested installations`.

## Task 4: Implement Job Envelope Encryption and Consent

**Files:**

- Create: `RPGPlayer/Domain/Jobs/JobEnvelopeEncryptor.swift`
- Create: `RPGPlayer/Features/Settings/DurableModeConsentView.swift`
- Create: `Backend/src/crypto/job-envelope.ts`
- Test: `RPGPlayerTests/JobEnvelopeEncryptorTests.swift`
- Test: `Backend/test/job-envelope.test.ts`

- [ ] Display exactly what leaves the phone: bounded turn context, selected provider key, optional ElevenLabs key, model/voice settings, and requested assets.
- [ ] Offer `Enable durable turns` and `Keep device-only`; persist the choice without preselecting consent.
- [ ] Generate a random AES-256-GCM content key and nonce per job.
- [ ] Encrypt the bounded package locally, wrap the content key with the service's pinned RSA-OAEP-256 public key, and include authenticated protocol/job metadata.
- [ ] Decrypt only inside the Workflow step needing the credential; never persist plaintext or place it in exceptions/logs.
- [ ] Zero mutable key buffers where supported and release plaintext before step completion.
- [ ] Add Swift-created → Worker-decrypted and Worker-created → Swift-decrypted fixture tests in a non-production test-key environment.
- [ ] Commit `feat: add explicit durable consent and encrypted job envelopes`.

## Task 5: Implement Per-Job Durable Object Storage

**Files:**

- Create: `Backend/src/jobs/turn-job.ts`
- Create: `Backend/src/jobs/job-store.ts`
- Test: `Backend/test/turn-job.test.ts`

- [ ] Route with `env.TURN_JOB.getByName(jobID)`.
- [ ] Initialize SQLite schema in constructor `blockConcurrencyWhile` only: metadata, events, client acknowledgements, activity tokens, and schema migrations.
- [ ] Implement typed RPC methods for initialize, appendEvent, eventsAfter, setResultReference, requestCancellation, acknowledge, activityTokens, and expire.
- [ ] Allocate event sequence and insert event atomically before in-memory WebSocket broadcast.
- [ ] Enforce installation ownership, job request-ID uniqueness, and legal phase transitions.
- [ ] Use a hibernatable WebSocket for foreground progress and HTTP polling as fallback.
- [ ] Schedule the one alarm for expiry/retry cleanup and make it idempotent.
- [ ] Test concurrent append ordering, duplicate completion, reconnect after sequence, cancellation races, eviction, and alarm cleanup.
- [ ] Commit `feat: coordinate each turn in a durable object`.

## Task 6: Implement Submission, Status, Cancel, and Acknowledge Routes

**Files:**

- Create: `Backend/src/routes/jobs.ts`
- Create: `Backend/src/http/validation.ts`
- Create: `RPGPlayer/Infrastructure/Networking/DurableTurnClient.swift`
- Test: `Backend/test/jobs-route.test.ts`
- Test: `RPGPlayerTests/DurableTurnClientTests.swift`

- [ ] Provide `POST /v1/jobs`, `GET /v1/jobs/{id}/events?after=`, `GET /v1/jobs/{id}/stream`, `POST /v1/jobs/{id}/cancel`, and `POST /v1/jobs/{id}/ack`.
- [ ] Authenticate every route with the installation token plus an App Attest assertion for mutating requests.
- [ ] Validate content type, bounded length, protocol version, ownership, request ID, and expected campaign sequence.
- [ ] Write encrypted input to R2 under a server-generated job UUID key; pass only the object key to the Workflow.
- [ ] Return 202 with job ID and first event after durable initialization and Workflow creation.
- [ ] Stream event pages without returning R2 payloads through public routes.
- [ ] Test oversized body, malformed JSON, unauthorized cross-installation access, replay, and cancellation.
- [ ] Commit `feat: expose authenticated durable job api`.

## Task 7: Implement the Durable Turn Workflow

**Files:**

- Create: `Backend/src/workflows/turn-workflow.ts`
- Create: `Backend/src/providers/`
- Create: `Backend/src/tools/`
- Create: `Backend/src/validation/turn-envelope.ts`
- Test: `Backend/test/turn-workflow.test.ts`

- [ ] Use durable steps for decrypt/read, provider generation, validated tools, final validation, optional voice generation, encrypted result write, ready notification, and cleanup scheduling.
- [ ] Before and after every external call, read cancellation/terminal state from the job object.
- [ ] Reuse the same JSON tool schemas and golden protocol fixtures as the Swift implementation.
- [ ] Make provider idempotency explicit; where a provider cannot resume, retry from the last committed workflow step and deduplicate final output by request ID.
- [ ] Append sanitized phases only after durable step entry/exit.
- [ ] Encrypt the final envelope and optional audio references with the job content key before R2 write.
- [ ] On terminal failure, store category/retryability without provider body or story text.
- [ ] Test provider timeout, workflow retry, duplicate delivery, tool rejection, cancellation at every stage, and result validation failure.
- [ ] Commit `feat: execute retriable durable turn workflows`.

## Task 8: Send ActivityKit Push Updates

**Files:**

- Modify: `Shared/TurnActivityAttributes.swift`
- Modify: `TurnActivityExtension/TurnActivityWidget.swift`
- Create: `Backend/src/apns/activity-push.ts`
- Create: `RPGPlayer/Domain/Jobs/LiveActivityCoordinator.swift`
- Test: `Backend/test/activity-push.test.ts`
- Test: `RPGPlayerTests/LiveActivityCoordinatorTests.swift`

- [ ] Start the Live Activity after job acceptance and upload its push token to the owning job.
- [ ] Render compact campaign glyph plus phase indicator; expanded view shows campaign title, status, elapsed time, and Stop only while cancellable.
- [ ] Send ActivityKit start/update/end payloads using current APNs schema, monotonic timestamps, and `stale-date`.
- [ ] Never include imported text, player action, character names beyond user-selected campaign title, provider, key, or tool arguments.
- [ ] Rate-limit/coalesce status pushes and always send terminal Ready/Needs Attention.
- [ ] Deep-link `rpgplayer://campaign/{campaignID}/job/{jobID}` through the centralized router.
- [ ] Test compact, minimal, expanded, stale, cancelled, failed, and ready snapshots.
- [ ] Commit `feat: mirror durable turn progress in live activities`.

## Task 9: Reconcile Durable Results Exactly Once

**Files:**

- Create: `RPGPlayer/Domain/Jobs/JobReconciler.swift`
- Create: `RPGPlayer/Infrastructure/Persistence/PendingJobRecord.swift`
- Modify: `RPGPlayer/Features/Player/PlayerSessionModel.swift`
- Test: `RPGPlayerTests/JobReconcilerTests.swift`
- Test: `RPGPlayerUITests/DurableRelaunchTests.swift`

- [ ] Persist job ID, request ID, campaign ID, expected local sequence, last job sequence, and encryption material reference before leaving the foreground.
- [ ] Resume via WebSocket when active and event-page polling after reconnect/relaunch.
- [ ] Validate/decrypt the final envelope, compare request/context hash, and run the same Phase 3 envelope validator.
- [ ] Append one final local event batch using expected sequence and request ID.
- [ ] If local state diverged, show a recovery review and never auto-merge mutations.
- [ ] Acknowledge only after the local transaction commits; then delete job key material and request remote deletion.
- [ ] Test submit → background → process termination → remote finish → relaunch → exactly one commit.
- [ ] Commit `feat: reconcile durable turn results exactly once`.

## Task 10: Add iOS Background Enhancements Without Correctness Dependency

**Files:**

- Create: `RPGPlayer/Domain/Jobs/BackgroundContinuationCoordinator.swift`
- Modify: `RPGPlayer/App/RPGPlayerApp.swift`
- Modify: `Config/App-Info.plist`
- Test: `RPGPlayerTests/BackgroundContinuationTests.swift`

- [ ] On iOS 26, register and submit `BGContinuedProcessingTask` only for user-started active turns.
- [ ] On earlier iOS, use short background task time only to finish submission/persist handoff.
- [ ] Expiration handlers cancel local streaming, persist cursor, and leave the durable job running.
- [ ] Foreground restoration always queries server state instead of trusting cached UI status.
- [ ] Confirm device-only mode never claims guaranteed continuation.
- [ ] Real-device test foreground, lock, home, memory pressure, force quit, reboot, offline, and return.
- [ ] Commit `feat: add truthful ios background continuation`.

## Task 11: Enforce Retention, Observability, and Abuse Limits

**Files:**

- Create: `Backend/src/jobs/cleanup.ts`
- Create: `Backend/src/observability/log.ts`
- Test: `Backend/test/retention.test.ts`
- Test: `Backend/test/redaction.test.ts`

- [ ] Default successful artifacts to deletion after acknowledgement; expire all unrecovered artifacts at 24 hours.
- [ ] Cap concurrent jobs per installation at two and reject duplicate active request IDs.
- [ ] Cap provider/tool loops, output size, audio size, workflow duration, and retries.
- [ ] Use structured redacted logs with request ID, job ID, phase, duration, byte counts, and category only.
- [ ] Enable sampled traces without request/response bodies.
- [ ] Add canary tests containing sentinel secrets and story phrases; assert they never appear in captured logs or error responses.
- [ ] Commit `feat: enforce durable job retention and redaction`.

## Phase 5 Completion Gate

- [ ] Opt-in consent accurately describes transient server handling.
- [ ] Device-only mode remains fully usable and truthfully labeled.
- [ ] One job maps to one Durable Object and one Workflow.
- [ ] Input, credentials, and final output are encrypted at rest; plaintext is never logged.
- [ ] A terminated app later commits exactly one completed turn.
- [ ] Dynamic Island and Lock Screen progress survive app suspension.
- [ ] Cancellation, sequence conflict, retry, expiry, and offline reconnection pass.
- [ ] Acknowledged data is deleted and 24-hour cleanup is verified.
