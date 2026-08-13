# Handoff: Continue RPGPlayer Phase 3 in the Cloud

## Task

Hand back the completed cloud continuation from the Phase 3 Task 3 application-code baseline `4b5140e`. Phase 3 Tasks 4–9 are implemented and review-complete on `codex/phase3-cloud-continuation` through `c55a81d584734e570c4bf02dcb2af4c26fdacef5`. Stop here for a local pull-back before Phase 3 Task 10 integration and all real-provider or real-app acceptance testing.

## Concept and context

RPGPlayer is a standalone native iOS player for user-exported AI-RPG projects. Its compact mobile gameplay hierarchy is a faithful native reconstruction of a private August 9, 2026 iPhone recording, not a redesign. The app owns its imported data, append-only campaign history, deterministic projection, provider credentials, and player UI; it does not authenticate with Craft or call undocumented Craft services.

The implementation has progressed beyond the fixture shell and import system. Phase 3 now has provider-neutral turn contracts, private Keychain-backed provider settings, and bounded SSE/JSONL transport. The next objective is to add real provider adapters without weakening the established security, streaming, determinism, or visual contracts.

All remaining delegated work must follow `docs/superpowers/plans/2026-08-12-gpt-luna-project-orchestration.md`: GPT Luna is mandatory for every worker role, while the root agent coordinates and gates the work. Because the model catalog changed during the local session, the fresh cloud session must resolve and smoke-test the exact GPT Luna selector before spawning any project worker; no fallback model is authorized.

## Goal and acceptance criteria

- Complete the remaining Phase 3 tasks in dependency order, beginning with Task 4 (OpenAI and OpenRouter adapters).
- Keep deterministic source, fixtures, adapter contract tests, and domain work cloud-executable and committed in small green increments.
- Preserve the recording-faithful Phase 1 UI and the event-sourced Phase 2 campaign model.
- Pull the cloud branch back to the local Mac before real credentials or user-visible runtime acceptance are required. Task 10 source work may proceed in cloud only if it can preserve the existing presentation behind dependency injection, but its final integration and visual acceptance must be local.
- [x] Tasks 4–9 are cloud-complete in reviewable commit ranges; final whole-phase review status is READY at `c55a81d`.
- [x] The cloud branch contains the completed Task 4–9 implementation and review-fix history.
- [ ] Task 10 integration and local unit/build/UI/visual acceptance.
- [ ] Local work resumes no later than Phase 3 Task 10 integration, then runs real BYOK, Xcode/Simulator UI, canonical visual, and available physical-device checks.
- [ ] Phase 3 is not marked complete until a real user-owned provider key completes Your Move → generation → validated tools/roll → transcript or Visual Novel, with the visual gate rechecked.

## Current status

The cloud continuation is complete through Phase 3 Task 9. The verified application-code tip on branch `codex/phase3-cloud-continuation` is clean commit `c55a81d584734e570c4bf02dcb2af4c26fdacef5` (`fix: reconcile stale roll resolutions`); this documentation handoff is the only commit after that code tip. Task 9 initial commit is `71b7b2aa383e4632057f6f513464e2e8009ddccb`, and Task 8 ends at `8fd081c290431d55061d85c01ce1111009fe58fe`. Final whole-phase review status is **READY**. This is a cloud code handoff only: Task 10 has not been claimed, and the Phase 3 completion gate remains open. The local root's intentionally untracked `.worktrees/` directory is not project content.

### Completed

- **Verified — Phase 1:** native player shell Tasks 1–8, commits `97f8243` through `4413e20`.
- **Verified — Phase 1 visual gate:** all nine canonical Simulator states were accepted at 440×956 points / 1320×2868 pixels. The portable evidence record is `docs/qa/native-player-shell-checklist.md`.
- **Verified — Phase 2:** import/event-store Tasks 1–9 plus real folder/archive acceptance, commits `a9bf17b` through `ad16d16`.
- **Verified — Phase 2 behavior:** bounded staging, CDF v2 normalization, explicit handoff mapping, atomic SwiftData event persistence, deterministic replay/checkpoints, import review/commit, recovery export/restore/deletion, library navigation, and exact relaunch state.
- **Verified — Phase 3 Task 1:** provider-neutral requests, models, normalized stream events/errors, safe proposed-event envelope, and size bounds in `b326ebc`.
- **Verified — Phase 3 Task 2:** Keychain credential storage/settings and diagnostics redaction in `f91dd24`. Production credential validation intentionally reports unavailable until live adapters are injected.
- **Verified — Phase 3 Task 3:** bounded streaming HTTP, incremental SSE/JSONL decoders, deterministic transport seams, exact-task cancellation, and demand-driven provider-stream enforcement in `4b5140e`.
- **Cloud-complete — Phase 3 Tasks 4–9:** implementation and review-fix ranges are preserved exactly below. These are source/fixture/static-review completions; they do not include local Apple-runtime acceptance.

| Task | Inclusive commit range | Status |
| --- | --- | --- |
| 4 — OpenAI/OpenRouter adapters | `9dde19edc0e3ee4648114f8ead2b31a29aaefd3e^..a8ea53e8fec747b44ea7db5988d58f4362965cfa` | Cloud-complete; review fixes closed |
| 5 — Anthropic/Gemini adapters | `61033a0cbd1005f1ebab63dbf2721cecc61c6372^..c069af30c8c45fb2e29a812b12d415c65fee4518` | Cloud-complete; review fixes closed |
| 6 — bounded deterministic context | `3107151c5ae87b2d8e3b586a90fd31b48bfb63e7^..9bfa55258f48678d03446e60a1f30310034e9e00` | Cloud-complete; review fixes closed |
| 7 — native GM tool validation | `4d2b82030269298ba6c7d94b18b76557a557caa7^..2c620f5fec1938edf86dc502b7a4d22d9ce87393` | Cloud-complete; review fixes closed |
| 8 — TurnEngine and atomic commit | `77f93aa7ee7337ef744f9ada148699d59c81c74a^..8fd081c290431d55061d85c01ce1111009fe58fe` | Cloud-complete through reviewed fix |
| 9 — dice-roll interruption | `71b7b2aa383e4632057f6f513464e2e8009ddccb^..c55a81d584734e570c4bf02dcb2af4c26fdacef5` | Cloud-complete; final review READY |

The final reviewed Task 9 fix is `c55a81d`; no commit after it is part of the application-code continuation.

### In progress

- None in the cloud branch. Work stops after Task 9 for local pull-back before Task 10 integration.

### Blocked, open, or unknown

- **Open:** local pull-back, conflict review, Xcode project regeneration, and Task 10 integration.
- **Open:** no real user-supplied provider key has been validated or used for a full turn.
- **Open:** full-turn provider/runtime acceptance, including a native tool and dice roll, and the Phase 3 completion gate.
- **Open:** visual fidelity, accessibility/VoiceOver, relaunch/SwiftData runtime, physical-device, and broad device-matrix acceptance.
- **Cloud limitation:** this host has no Swift, Xcode, or XcodeGen. Swift compilation, XCTest/Swift Testing, Simulator/UI/runtime, real provider/BYOK, visual, and device acceptance could not run and are not claimed.
- **Local-only historical evidence:** ignored `build/`, `.xcresult`, private recording frames, and `.worktrees/` artifacts do not travel with a fresh clone and must not be prerequisites for cloud work.

## Work log

- Verified the completed cloud continuation on `codex/phase3-cloud-continuation` at `c55a81d584734e570c4bf02dcb2af4c26fdacef5`; Tasks 4–9 are complete in the ranges recorded above and the final whole-phase review status is READY.
- Passed cloud-safe verification: `git diff --check`, `git show --check` for every commit in `4b5140e^..HEAD`, `jq -e .` validation for all 24 tracked JSON fixtures, and static scans for credential-looking literals, production logging, and generated artifacts.
- Confirmed the cloud limitation: Swift/Xcode/XcodeGen/Simulator/XCTest/UI/runtime/provider/BYOK/visual/device acceptance could not run on this host; no Task 10 or Phase 3 gate is claimed.
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
- **Cloud continuation static checks:** `git diff --check` passed; `git show --check` passed for every commit in `4b5140e^..HEAD`; `jq -e .` parsed all 24 tracked JSON files; and narrow static scans found no credential-looking literals, production logging calls, or generated Xcode/build/capture artifacts in the continuation diff.
- **Cloud runtime boundary:** Swift, Xcode, and XcodeGen are unavailable here, so Swift compilation, XCTest/Swift Testing, Simulator/UI/runtime, provider/BYOK, visual, and physical-device acceptance could not run. These checks remain local and are not implied by the static passes.

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

1. **Pull back locally before Task 10 integration.** Fetch `codex/phase3-cloud-continuation`, inspect `4b5140e..c55a81d` and the task ranges above, regenerate the Xcode project with XcodeGen, then run the full unit, build, UI, and canonical visual lanes on the local Mac/Simulator.
2. **Task 10 local integration:** inject or verify the real TurnEngine in the recording-faithful presentation without geometry changes; do not mark this task complete from the cloud branch.
3. **Task 11 locally:** add truthful offline/failure/retry/relaunch UX, retaining drafts and preserving canonical-state truth.
4. **Phase 3 completion locally:** validate a real user-owned provider key and complete one full turn including a native tool and roll. Repeat the recorded-transport no-network path and re-run visual/accessibility evidence required by the touched UI.
5. After Phase 3 passes, execute Phase 4 voice, Phase 5 durable continuation, and Phase 6 TestFlight hardening according to their plans. Real ElevenLabs, audio interruption, APNs, Dynamic Island, background/termination, Instruments, archive/signing, and clean-device acceptance remain local/device work.

## Risks and handoff notes

- Remaining acceptance risks are the real provider key/full turn with a native tool and roll, visual fidelity, accessibility, relaunch/SwiftData runtime behavior, and local conflict/runtime acceptance after pull-back.
- Provider APIs and model catalogs are temporally unstable. At implementation time, verify current official provider documentation for request/stream schema, authentication, tool calls, error codes, and model discovery; keep wire changes adapter-local.
- Never commit real provider responses unless they are sanitized and reviewed for keys, prompts, imported story text, account IDs, headers, URLs/query values, or private metadata.
- The master plans contain future-facing types; current source is authoritative for already-frozen code contracts. Change them only with migration/compatibility tests.
- Phase 1's canonical Simulator gate passed, but physical-device and real-VoiceOver evidence remain open. Do not rewrite that distinction.
- The private recording and ignored canonical images are not in Git. A cloud agent can preserve geometry and run existing regression tests, but final side-by-side visual judgment belongs on the local machine with the authority available.
- The known accessibility-size custom-editor XCTest query timeout is documented as harness evidence. Do not chase it unless normal runtime behavior or a product assertion fails.
- When the cloud branch is ready to return, do not merge blindly over new local changes. Fetch, inspect the range, fast-forward or review-merge cleanly, regenerate with XcodeGen, then start local acceptance. The cloud branch is ready to return at reviewed `c55a81d`; this does not mean Task 10 or the Phase 3 gate is complete.

## Next agent instruction

Pull back the reviewed `codex/phase3-cloud-continuation` branch at `c55a81d` before Phase 3 Task 10 integration. First run the local sequence below, adapting the destination to the existing booted Simulator:

~~~bash
git fetch origin codex/phase3-cloud-continuation
git log --oneline --decorate 4b5140e..FETCH_HEAD
git diff --stat 4b5140e..FETCH_HEAD
xcodegen generate
xcodebuild test -project RPGPlayer.xcodeproj -scheme RPGPlayer -destination '<available iOS Simulator>' -parallel-testing-enabled NO -only-testing:RPGPlayerTests
xcodebuild build -project RPGPlayer.xcodeproj -scheme RPGPlayer -destination '<available iOS Simulator>'
xcodebuild test -project RPGPlayer.xcodeproj -scheme RPGPlayer -destination '<available iOS Simulator>' -parallel-testing-enabled NO -only-testing:RPGPlayerUITests
# Run the local canonical visual lane against the recording authority.
~~~

Then review local conflicts/runtime failures, integrate Task 10, and run the real-provider/BYOK, native-tool-and-roll, visual, accessibility, relaunch/SwiftData, and device checks. Do not claim Task 10 or the Phase 3 gate complete until those local checks pass; keep every unavailable or deferred acceptance item explicitly labeled.
