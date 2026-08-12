# Handoff: Continue RPGPlayer Phase 3 in the Cloud

## Task

Continue the RPGPlayer implementation from the current `origin/main`; the last application-code baseline before this documentation handoff is `4b5140e`. Execute `docs/superpowers/plans/2026-08-09-ai-gm-providers-tools.md` task by task with TDD. Start with Phase 3 Task 4, implement and verify cloud-safe work through reviewable commits, and stop for a local pull-back before real-provider and real-app acceptance testing.

## Concept and context

RPGPlayer is a standalone native iOS player for user-exported AI-RPG projects. Its compact mobile gameplay hierarchy is a faithful native reconstruction of a private August 9, 2026 iPhone recording, not a redesign. The app owns its imported data, append-only campaign history, deterministic projection, provider credentials, and player UI; it does not authenticate with Craft or call undocumented Craft services.

The implementation has progressed beyond the fixture shell and import system. Phase 3 now has provider-neutral turn contracts, private Keychain-backed provider settings, and bounded SSE/JSONL transport. The next objective is to add real provider adapters without weakening the established security, streaming, determinism, or visual contracts.

All remaining delegated work must follow `docs/superpowers/plans/2026-08-12-gpt-luna-project-orchestration.md`: GPT Luna is mandatory for every worker role, while the root agent coordinates and gates the work. Because the model catalog changed during the local session, the fresh cloud session must resolve and smoke-test the exact GPT Luna selector before spawning any project worker; no fallback model is authorized.

## Goal and acceptance criteria

- Complete the remaining Phase 3 tasks in dependency order, beginning with Task 4 (OpenAI and OpenRouter adapters).
- Keep deterministic source, fixtures, adapter contract tests, and domain work cloud-executable and committed in small green increments.
- Preserve the recording-faithful Phase 1 UI and the event-sourced Phase 2 campaign model.
- Pull the cloud branch back to the local Mac before real credentials or user-visible runtime acceptance are required. Task 10 source work may proceed in cloud only if it can preserve the existing presentation behind dependency injection, but its final integration and visual acceptance must be local.
- [ ] Task 4 passes sanitized recorded transport contract tests for OpenAI and OpenRouter.
- [ ] Task 5 gives Anthropic and Gemini the same normalized contract coverage.
- [ ] Tasks 6–9 complete bounded context, native tool validation, atomic turn execution, and dice interruption.
- [ ] The cloud branch is pushed with a clean, reviewable commit for every completed task.
- [ ] Local work resumes no later than Phase 3 Task 10 integration, then runs real BYOK, Xcode/Simulator UI, canonical visual, and available physical-device checks.
- [ ] Phase 3 is not marked complete until a real user-owned provider key completes Your Move → generation → validated tools/roll → transcript or Visual Novel, with the visual gate rechecked.

## Current status

The last application-code commit is `4b5140ee486b2df9c10783947c3ca37e556d72c7`; a later documentation-only commit contains this handoff and the reconciled plans. Phase 1 and Phase 2 product gates are complete. Phase 3 Tasks 1–3 are complete; Task 4 has not started. A cloud agent must fetch and branch from the current `origin/main` tip rather than hard-resetting to the application-code baseline. The local root's intentionally untracked `.worktrees/` directory is not project content.

### Completed

- **Verified — Phase 1:** native player shell Tasks 1–8, commits `97f8243` through `4413e20`.
- **Verified — Phase 1 visual gate:** all nine canonical Simulator states were accepted at 440×956 points / 1320×2868 pixels. The portable evidence record is `docs/qa/native-player-shell-checklist.md`.
- **Verified — Phase 2:** import/event-store Tasks 1–9 plus real folder/archive acceptance, commits `a9bf17b` through `ad16d16`.
- **Verified — Phase 2 behavior:** bounded staging, CDF v2 normalization, explicit handoff mapping, atomic SwiftData event persistence, deterministic replay/checkpoints, import review/commit, recovery export/restore/deletion, library navigation, and exact relaunch state.
- **Verified — Phase 3 Task 1:** provider-neutral requests, models, normalized stream events/errors, safe proposed-event envelope, and size bounds in `b326ebc`.
- **Verified — Phase 3 Task 2:** Keychain credential storage/settings and diagnostics redaction in `f91dd24`. Production credential validation intentionally reports unavailable until live adapters are injected.
- **Verified — Phase 3 Task 3:** bounded streaming HTTP, incremental SSE/JSONL decoders, deterministic transport seams, exact-task cancellation, and demand-driven provider-stream enforcement in `4b5140e`.

### In progress

- None. Phase 3 Task 3 was completed, reviewed, merged, and pushed before this handoff.

### Blocked, open, or unknown

- **Open:** Phase 3 Tasks 4–11 and its completion gate.
- **Open:** no real user-supplied provider key has been validated or used for a turn.
- **Open:** production provider validation is wired to `UnavailableProviderCredentialValidator` until Tasks 4–5 supply live adapters.
- **Open:** physical-device, real VoiceOver, broad device-matrix, and full real-app acceptance. Simulator visual acceptance does not prove these.
- **Unknown:** the cloud host's Xcode/Simulator availability. Do not infer UI or device acceptance from source/unit work on a host that cannot run those environments.
- **Local-only historical evidence:** ignored `build/`, `.xcresult`, private recording frames, and `.worktrees/` artifacts do not travel with a fresh clone and must not be prerequisites for cloud work.

## Work log

- Built and visually accepted the native fixture shell before beginning later phases — Phase 1 gate PASS — commits `97f8243`…`4413e20`.
- Implemented and completed the staged CDF import, local event store, recovery, library, and relaunch flow — Phase 2 gate PASS — commits `a9bf17b`…`ad16d16`.
- Froze provider-neutral request/envelope contracts and a closed metadata-free proposal enum — Task 1 PASS — `b326ebc`.
- Added device-only Keychain credential settings, sentinel non-persistence coverage, and an explicit unavailable live-validation state — Task 2 PASS — `f91dd24`.
- Added `URLSession.bytes(for:)` streaming, 1 MB frame bounds, 8 MB final-envelope bounds, incremental SSE/JSONL parsing, safe errors, cancellation, and a demand-driven `ProviderStreamContract` — Task 3 PASS — `4b5140e`.
- Ran the merged-main unit suite, app build, and focused Visual Novel regression before the push — all passed in their stated scope.
- Fast-forwarded and pushed `main` to GitHub — remote verification matched `4b5140e` before the documentation reconciliation.

## Decisions and constraints

- The private screen recording and `docs/visual-audit/native-craft-mobile-fidelity.md` remain the visual authority. Do not redesign the player.
- Use task-by-task TDD: establish a meaningful RED, implement the smallest GREEN, run the relevant lane, review, then commit.
- Do not begin a later task before the current task is verified. Do not begin Phase 4 or Phase 5 before Phase 3's contract/completion requirements permit it.
- Provider wire DTOs stay inside their adapter folders. Player/domain UI switches only on shared provider-neutral types.
- Model output is untrusted. It cannot write files, execute code, call arbitrary URLs, or mutate campaign state outside validated native tools.
- Partial streams are presentation-only. Canonical state changes only after full-envelope validation in the final atomic event batch.
- Keep provider credentials only in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Never put secrets in fixtures, logs, source, UserDefaults, SwiftData, crash metadata, commits, or handoff text.
- Frame bounds are frozen at 1,000,000 encoded bytes for SSE/JSONL frames and tool arguments; the versioned final envelope is capped at 8,000,000 bytes.
- Provider streaming is a normal single-consumer TurnEngine flow. Do not spend time on unsupported concurrent-iterator edge cases unless normal use exposes a defect.
- Preserve the store's current meaning: a `CampaignEvent.requestID` identifies one accepted atomic append run, and the reducer recognizes a contiguous request run. Before Task 8/9, explicitly reconcile this with longer-lived turn/roll lineage rather than silently reusing a request ID across later non-contiguous batches.
- Preserve ordered story semantics. `TurnEnvelope.narration` uses ordered `StoryBlock` values, while the current persisted `GMMessageCommittedPayload` still separates narration and dialogue. Task 8 must define a backward-compatible mapping that cannot reorder interleaved story blocks after relaunch.
- Preserve unknown/additive import data and frozen event/envelope schema compatibility. Any schema change requires compatibility and migration tests.
- Keep the Simulator running during local testing and minimize boots/shutdowns. Do not carry local Simulator UUIDs into cloud scripts.
- Do not commit `build/`, `.worktrees/`, private captures/recordings, generated `RPGPlayer.xcodeproj`, or credentials.

## What was tried

- **Direct, bounded URLSession streaming** — kept. `StreamingHTTPClient` wraps `URLSession.bytes(for:)`, validates the response, and exposes pull-based decoded frames.
- **Continuation-backed eager provider relay** — replaced. A RED test proved the old wrapper prefetched a second event; `AsyncThrowingStream(unfolding:)` now applies downstream demand without an added unbounded buffer.
- **Custom URLProtocol for held incremental bytes on iOS 26.5** — not used as the sole midstream proof. That runtime may withhold custom-protocol bytes until completion. Completed URLProtocol fixtures verify real request/response/status/redaction paths; an internal pull-byte seam deterministically verifies midstream failure, cancellation, and backpressure.
- **Forcing a custom cancellation error through downstream AsyncThrowingStream task cancellation** — not required. Explicit provider cancellation proves `ProviderError.cancelled`; downstream cancellation proves exact-once cancellation and no later events, while the standard stream may surface EOF or cancellation.
- **Repeated simulator recovery/reboot matrices** — intentionally avoided. The owner asked to keep the Simulator running and not hyperfixate on rare scenarios.

## Relevant files and artifacts

- `docs/superpowers/plans/2026-08-09-rpgplayer-complete-implementation.md` — master status, dependencies, gates, and phase order.
- `docs/superpowers/plans/2026-08-12-gpt-luna-project-orchestration.md` — mandatory worker topology, selector preflight, task/review loop, concurrency, branching, and cloud/local gates for the rest of the project.
- `docs/superpowers/plans/2026-08-09-ai-gm-providers-tools.md` — active Phase 3 TDD plan; start at Task 4.
- `docs/product/rpgplayer-implementation-spec.md` — product and architecture contract.
- `docs/visual-audit/native-craft-mobile-fidelity.md` — recording-derived hierarchy and geometry authority.
- `docs/qa/native-player-shell-checklist.md` — portable Phase 1 acceptance record and honest remaining device/accessibility evidence.
- `RPGPlayer/Domain/Providers/AIProvider.swift` — `AIProvider`, `TurnRequest`, `TurnContext`, `PlayerAction`, and context hash/sections.
- `RPGPlayer/Domain/Providers/ProviderModel.swift` — closed provider IDs and validated model capabilities.
- `RPGPlayer/Domain/Providers/ProviderStreamEvent.swift` — normalized events, 1 MB tool arguments, and pull-based stream enforcement.
- `RPGPlayer/Domain/Providers/ProviderError.swift` — normalized safe provider errors and retry policy.
- `RPGPlayer/Domain/Providers/TurnEnvelope.swift` — ordered story blocks, closed proposals, versioned 8 MB final envelope.
- `RPGPlayer/Infrastructure/Networking/StreamingHTTPClient.swift` — bounded SSE/JSONL transport and cancellation.
- `RPGPlayer/Infrastructure/Networking/ServerSentEventDecoder.swift` — incremental SSE framing.
- `RPGPlayer/Infrastructure/Networking/JSONLineDecoder.swift` — incremental JSONL framing.
- `RPGPlayer/Infrastructure/Networking/NetworkDiagnosticRedactor.swift` — header/token redaction shared by adapters.
- `RPGPlayer/Infrastructure/Keychain/KeychainCredentialStore.swift` — device-only credential persistence and internal read seam.
- `RPGPlayer/App/AppDependencyGraph.swift` — production credential validator is deliberately unavailable until adapters are injected.
- `RPGPlayer/Domain/Campaign/CampaignStore.swift` and `RPGPlayer/Infrastructure/Persistence/SwiftDataCampaignStore.swift` — atomic append and current request-run semantics.
- `RPGPlayer/Domain/Campaign/CampaignReducer.swift` — deterministic replay and contiguous request-run handling.
- `RPGPlayerTests/ProviderContractTests.swift` and `RPGPlayerTests/StreamingHTTPClientTests.swift` — shared contract and transport regression suites.
- `project.yml` — XcodeGen source/package authority; provider fixtures are excluded from the shipping app target.

## Validation and evidence

- **Verified, merged-main unit lane:** 172 logical tests / 232 device invocations, 0 failures, on the local iOS 26.5 iPhone 16 Pro Max Simulator.
- **Verified, merged-main app build:** `RPGPlayer.app` built successfully for iOS Simulator.
- **Verified, merged-main UI regression:** `testVisualNovelAdvancesAndClosesIntoTranscript` passed 1/1.
- **Reported, visual review:** fresh post-Task-3 Visual Novel title/dialogue captures matched the accepted canonical layout/content, except the status-bar clock.
- **Reported, scoped reviews:** two independent Task 3 reviewers returned READY with no normal-flow P0–P2 findings.
- **Evidence boundary:** local result bundles and captures were ignored build artifacts, not portable repository content. Reproduce required evidence on the environment where acceptance is claimed.

Recommended cloud checks, adjusted to the host's installed toolchain:

~~~bash
xcodegen generate
xcodebuild -project RPGPlayer.xcodeproj \
  -scheme RPGPlayer \
  -destination '<available iOS Simulator>' \
  -parallel-testing-enabled NO \
  -only-testing:RPGPlayerTests \
  test
~~~

If Xcode/Simulator is unavailable in the cloud, run every available deterministic source/unit/static check, record that runtime testing is deferred, and do not fabricate a green Xcode result.

## Remaining work

1. **Phase 3 Task 4 — immediate:** implement OpenAI and OpenRouter adapters with adapter-local wire DTOs and sanitized fixtures for text, interleaved tools, refusal, rate limit, malformed event, and disconnect. Map both to identical shared normalized events where semantics match; reject unknown tools before execution; supply curated fallback models; assert that sentinel credentials never appear in headers/body diagnostics.
2. **Task 5:** add Anthropic and Gemini with the same contract matrix, including provider-specific tool/finish/safety mappings and cross-provider normalized equivalence.
3. **Task 6:** assemble deterministic bounded campaign context, excluding secrets/private transient context and hashing the stable result.
4. **Task 7:** define the closed native GM tool registry and validate every proposed mutation against schema, campaign ownership, path/URL, size, and relationship boundaries.
5. **Task 8:** implement the TurnEngine and final-envelope validator/builder. Resolve ordered story persistence and request-run versus durable turn/roll lineage before committing the first happy path. Keep all partial output transient and append the validated terminal result atomically.
6. **Task 9:** implement bounded dice expressions and deterministic tests, then pause/resume the same logical turn without violating store/reducer idempotency.
7. **Pull back locally no later than Task 10 integration.** Fetch the cloud branch, inspect its commit sequence, regenerate the Xcode project, run full units and an app build, then execute focused UI and canonical visual regression on the existing local Simulator.
8. **Task 10 local acceptance:** inject or verify the real TurnEngine in the recording-faithful presentation without geometry changes; run all nine visual captures against the recording authority.
9. **Task 11 locally:** add truthful offline/failure/retry/relaunch UX, retaining drafts and preserving canonical-state truth.
10. **Phase 3 completion locally:** validate a real user-owned provider key and complete one full turn including a native tool and roll. Repeat the recorded-transport no-network path and re-run visual/accessibility evidence that the touched UI requires.
11. After Phase 3 passes, execute Phase 4 voice, Phase 5 durable continuation, and Phase 6 TestFlight hardening according to their plans. Real ElevenLabs, audio interruption, APNs, Dynamic Island, background/termination, Instruments, archive/signing, and clean-device acceptance remain local/device work.

## Risks and handoff notes

- Provider APIs and model catalogs are temporally unstable. At implementation time, verify current official provider documentation for request/stream schema, authentication, tool calls, error codes, and model discovery; keep wire changes adapter-local.
- Never commit real provider responses unless they are sanitized and reviewed for keys, prompts, imported story text, account IDs, headers, URLs/query values, or private metadata.
- The master plans contain future-facing types; current source is authoritative for already-frozen code contracts. Change them only with migration/compatibility tests.
- Phase 1's canonical Simulator gate passed, but physical-device and real-VoiceOver evidence remain open. Do not rewrite that distinction.
- The private recording and ignored canonical images are not in Git. A cloud agent can preserve geometry and run existing regression tests, but final side-by-side visual judgment belongs on the local machine with the authority available.
- The known accessibility-size custom-editor XCTest query timeout is documented as harness evidence. Do not chase it unless normal runtime behavior or a product assertion fails.
- When the cloud branch is ready to return, do not merge blindly over new local changes. Fetch, inspect the range, fast-forward or review-merge cleanly, regenerate with XcodeGen, then start local acceptance.

## Next agent instruction

Fetch the current `origin/main`, create a `codex/` Phase 3 continuation branch, read the master plan and active Phase 3 plan in full, and begin Task 4 with a clean adapter-contract RED. Preserve all provider-neutral contracts, streaming/size/cancellation bounds, credential privacy, event-store determinism, and Phase 1 geometry. Commit and push each green task. Stop and hand the branch back no later than Phase 3 Task 10 integration—or earlier if real credentials/runtime behavior are needed—and clearly label every local-only acceptance item as deferred rather than passed.
