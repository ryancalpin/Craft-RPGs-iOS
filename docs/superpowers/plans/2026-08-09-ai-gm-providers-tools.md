# AI GM Providers and Native Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn an imported local campaign into a complete playable solo AI-GM experience using user-owned provider keys, streaming generation, validated native tools, rolls, cancellation, and deterministic event commits.

**Architecture:** The player submits a provider-neutral `TurnRequest` to a `TurnEngine`. A context assembler reads a bounded campaign projection, a provider adapter streams normalized deltas/tool calls, and a tool executor validates proposed effects without directly mutating storage. A final envelope validator converts the complete response into one atomic campaign-event batch.

**Tech Stack:** Swift 6, Foundation, URLSession, AsyncSequence, CryptoKit, Security/Keychain, XCTest, SwiftUI

**Implementation status (August 12, 2026): IN PROGRESS.** Tasks 1–3 are committed on `main` as `b326ebc`, `f91dd24`, and `4b5140e`. Task 4 (OpenAI and OpenRouter adapters) is the immediate continuation. Tasks 4–11 and every real BYOK/physical-device completion claim remain open. See `docs/handoffs/2026-08-12-cloud-continuation.md`.

## Global Constraints

- Execute after Phase 2.
- Provider-specific wire types stay inside adapter modules.
- API keys are `AfterFirstUnlockThisDeviceOnly` Keychain items and never enter SwiftData, logs, fixtures, or crash metadata.
- Model text is untrusted input. It cannot write files, call arbitrary URLs, execute code, or mutate state outside validated tools.
- Partial streamed output is presentation state only; canonical campaign state changes in one final atomic batch.
- Cancellation and retries reuse the original request ID.
- Sanitized progress describes observable work only, never hidden chain-of-thought.

## Task 1: Define Provider-Neutral Turn Contracts

**Files:**

- Create: `RPGPlayer/Domain/Providers/AIProvider.swift`
- Create: `RPGPlayer/Domain/Providers/ProviderModel.swift`
- Create: `RPGPlayer/Domain/Providers/ProviderStreamEvent.swift`
- Create: `RPGPlayer/Domain/Providers/ProviderError.swift`
- Create: `RPGPlayer/Domain/Providers/TurnEnvelope.swift`
- Test: `RPGPlayerTests/ProviderContractTests.swift`

- [x] Define `AIProvider` with model listing, `streamTurn(_:) -> AsyncThrowingStream<ProviderStreamEvent, Error>`, and cancellation by request ID.
- [x] Normalize events to text delta, tool-call started/arguments/completed, usage, warning, and finish reason.
- [x] Normalize errors to invalid credential, quota, rate limited with retry date, context exceeded, safety refusal, malformed response, connectivity, cancelled, and service failure.
- [x] Decode and encode a versioned `TurnEnvelope` fixture shared with the future backend.
- [x] Test that UI-facing modules import no provider wire models.
- [x] Run tests and commit `b326ebc` (`feat: define provider-neutral turn contracts`).

## Task 2: Build Credential Storage and Provider Settings

**Files:**

- Create: `RPGPlayer/Infrastructure/Keychain/KeychainCredentialStore.swift`
- Create: `RPGPlayer/Domain/Providers/ProviderCredentialStore.swift`
- Create: `RPGPlayer/Features/Settings/ProviderSettingsView.swift`
- Create: `RPGPlayer/Features/Settings/APIKeyField.swift`
- Test: `RPGPlayerTests/KeychainCredentialStoreTests.swift`
- Test: `RPGPlayerUITests/ProviderSettingsTests.swift`

- [x] Store one credential per provider/account label using generic-password Keychain items.
- [x] Apply `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; do not synchronize.
- [x] Implement save, existence, replace, and delete without exposing a read-back value to UI; retain the validator seam and an explicit unavailable production state until Tasks 4–5 provide live adapters.
- [x] Redact authorization headers and known key prefixes in network diagnostics.
- [x] Use secure text entry with paste, clear, and validation state; never echo the full key after save.
- [x] Add a test asserting UserDefaults and the SwiftData store never contain the sentinel test key.
- [x] Run tests and commit `f91dd24` (`feat: add private provider credential settings`).

## Task 3: Implement Shared Streaming HTTP Infrastructure

**Files:**

- Create: `RPGPlayer/Infrastructure/Networking/StreamingHTTPClient.swift`
- Create: `RPGPlayer/Infrastructure/Networking/ServerSentEventDecoder.swift`
- Create: `RPGPlayer/Infrastructure/Networking/JSONLineDecoder.swift`
- Create: `RPGPlayer/Infrastructure/Networking/RedactingURLProtocol.swift`
- Test: `RPGPlayerTests/StreamingHTTPClientTests.swift`

- [x] Write tests for fragmented UTF-8, multi-line SSE data, comments, JSON lines, mid-stream HTTP failure, cancellation, and bounded frame size.
- [x] Use `URLSession.bytes(for:)`; never accumulate an unbounded response.
- [x] Cap a single event frame at 1 MB and the normalized final envelope at 8 MB.
- [x] Make cancellation close the exact URLSession task and finish the stream with cancellation semantics.
- [x] Inject a URL protocol/session so every adapter has deterministic recorded transport tests.
- [x] Run tests and commit `4b5140e` (`feat: add bounded streaming HTTP transport`).

## Task 4: Implement OpenAI and OpenRouter Adapters

**Files:**

- Create: `RPGPlayer/Infrastructure/Networking/OpenAI/OpenAIProvider.swift`
- Create: `RPGPlayer/Infrastructure/Networking/OpenAI/OpenAIWireModels.swift`
- Create: `RPGPlayer/Infrastructure/Networking/OpenRouter/OpenRouterProvider.swift`
- Test: `RPGPlayerTests/OpenAIProviderContractTests.swift`
- Test: `RPGPlayerTests/OpenRouterProviderContractTests.swift`
- Fixtures: `RPGPlayer/Fixtures/Providers/OpenAI/`
- Fixtures: `RPGPlayer/Fixtures/Providers/OpenRouter/`

- [ ] Record sanitized successful text, interleaved tool calls, refusal, rate-limit, malformed event, and disconnect fixtures.
- [ ] Map each fixture to the shared normalized event sequence.
- [ ] Use structured response/tool schemas; reject unknown tool names before execution.
- [ ] Provide curated fallback model lists when discovery is unavailable.
- [ ] Test that no header or body diagnostic contains the sentinel credential.
- [ ] Run contract tests and commit `feat: add openai and openrouter adapters`.

## Task 5: Implement Anthropic and Gemini Adapters

**Files:**

- Create: `RPGPlayer/Infrastructure/Networking/Anthropic/AnthropicProvider.swift`
- Create: `RPGPlayer/Infrastructure/Networking/Anthropic/AnthropicWireModels.swift`
- Create: `RPGPlayer/Infrastructure/Networking/Gemini/GeminiProvider.swift`
- Create: `RPGPlayer/Infrastructure/Networking/Gemini/GeminiWireModels.swift`
- Test: `RPGPlayerTests/AnthropicProviderContractTests.swift`
- Test: `RPGPlayerTests/GeminiProviderContractTests.swift`
- Fixtures: `RPGPlayer/Fixtures/Providers/Anthropic/`
- Fixtures: `RPGPlayer/Fixtures/Providers/Gemini/`

- [ ] Cover the same shared adapter contract matrix as Task 4.
- [ ] Normalize provider-specific tool-use and finish semantics without leaking them upstream.
- [ ] Convert provider safety blocks into a user-readable refusal that leaves the campaign unchanged.
- [ ] Verify all four adapters yield identical normalized sequences for semantically equivalent fixtures.
- [ ] Run contract tests and commit `feat: add anthropic and gemini adapters`.

## Task 6: Assemble Bounded Campaign Context

**Files:**

- Create: `RPGPlayer/Domain/Providers/TurnContextAssembler.swift`
- Create: `RPGPlayer/Domain/Providers/ContextBudget.swift`
- Create: `RPGPlayer/Domain/Providers/ContextSection.swift`
- Test: `RPGPlayerTests/TurnContextAssemblerTests.swift`

- [ ] Define deterministic priority: safety/system contract, player character, current scene, pending decision, recent transcript, referenced records, unresolved threads, broader world records.
- [ ] Exclude secrets, local file URLs, discarded drafts, and private optional context after its turn.
- [ ] Use provider model limits to compute a conservative input budget and reserve output/tool tokens.
- [ ] Summarize only through an explicit stored checkpoint; never silently mutate canonical history to fit.
- [ ] Add a stable-context hash for retry and durable upload.
- [ ] Test deterministic ordering under randomized source-record order.
- [ ] Run tests and commit `feat: assemble bounded deterministic turn context`.

## Task 7: Define and Validate Native GM Tools

**Files:**

- Create: `RPGPlayer/Domain/Tools/GMTool.swift`
- Create: `RPGPlayer/Domain/Tools/GMToolRegistry.swift`
- Create: `RPGPlayer/Domain/Tools/ToolProposal.swift`
- Create: `RPGPlayer/Domain/Tools/ToolValidator.swift`
- Test: `RPGPlayerTests/GMToolValidatorTests.swift`

- [ ] Register only read record, search records, patch fields, request roll, update scene, update clock, suggest voice, and attach imported/generated asset.
- [ ] Validate record IDs, field schemas, enum values, relationship targets, patch sizes, asset hashes, and campaign ownership.
- [ ] Return proposed events and sanitized status text; never call the campaign store from a tool.
- [ ] Reject arbitrary URLs, paths, shell commands, executable payloads, unknown tools, and cross-campaign IDs.
- [ ] Add property-based/fuzz inputs for malformed tool JSON with a 1 MB argument cap.
- [ ] Run tests and commit `feat: validate app-owned gm tools`.

## Task 8: Implement Turn Engine and Atomic Commit

**Files:**

- Create: `RPGPlayer/Domain/Providers/TurnEngine.swift`
- Create: `RPGPlayer/Domain/Providers/TurnEnvelopeValidator.swift`
- Create: `RPGPlayer/Domain/Providers/TurnEventBuilder.swift`
- Test: `RPGPlayerTests/TurnEngineTests.swift`

- [ ] Write a failing happy-path test covering status, streamed prose, tool proposal, tool result, final envelope, and one atomic append.
- [ ] Write failure tests for invalid tool, malformed final envelope, cancellation, disconnect before final, sequence conflict, duplicate completion, and retry.
- [ ] Emit transient `TurnPresentationEvent` values for UI; persist only submitted action, explicit status milestones if desired, and the validated final batch.
- [ ] Validate that Visual Novel beats reconstruct the same text/order as transcript blocks.
- [ ] Append the final batch with the original expected sequence and request ID.
- [ ] On conflict, reload projection and surface `Campaign changed; review before retrying` rather than silently overwriting.
- [ ] Run tests and commit `feat: execute and atomically commit ai turns`.

## Task 9: Add Dice Roll Interruption

**Files:**

- Create: `RPGPlayer/Domain/Campaign/DiceExpression.swift`
- Create: `RPGPlayer/Domain/Campaign/DiceRoller.swift`
- Create: `RPGPlayer/Features/Player/DiceRollCard.swift`
- Create: `RPGPlayer/Features/Player/DiceRollSheet.swift`
- Test: `RPGPlayerTests/DiceRollerTests.swift`
- Test: `RPGPlayerUITests/DiceInterruptionTests.swift`

- [ ] Parse bounded forms such as `1d20+5` with maximum 100 dice and 1,000 sides.
- [ ] Use `SystemRandomNumberGenerator` in production and an injected deterministic generator in tests.
- [ ] Pause the turn at `rollRequested`; do not let Visual Novel Auto pass it.
- [ ] Commit one `rollResolved` event and resume using the same request lineage.
- [ ] Match Craft's interaction hierarchy: roll card within the story flow, result legible, no permanent dice toolbar.
- [ ] Run tests and commit `feat: add deterministic roll interruption flow`.

## Task 10: Wire Real Generation into the Recording-Faithful UI

**Files:**

- Modify: `RPGPlayer/Features/Player/PlayerSessionModel.swift`
- Modify: `RPGPlayer/Features/Generation/GenerationView.swift` (`GenerationCard` is currently private here)
- Modify: `RPGPlayer/Features/Turn/YourMoveSheet.swift`
- Create: `RPGPlayer/Features/Generation/GenerationDetailView.swift`
- Test: `RPGPlayerUITests/RealTurnPresentationTests.swift`

- [ ] Replace the simulated generator through dependency injection; keep the same presentation states and geometry.
- [ ] Rotate only through recorded-style human statuses: connecting, consulting lore, updating world, writing scene, giving everyone a voice.
- [ ] Show sanitized completed/active tool steps behind the disclosure.
- [ ] Change Confirm to submission progress and then collapse to the generation card.
- [ ] Expose Stop only while cancellation can succeed; a stopped turn retains the submitted player event plus `turnCancelled`.
- [ ] On validated completion, enter Visual Novel title/first beat when enabled; otherwise remain in transcript at the new content.
- [ ] Run all visual-state captures and commit `feat: connect native player to ai turn engine`.

## Task 11: Add Failure, Retry, and Offline UX

**Files:**

- Create: `RPGPlayer/Features/Recovery/TurnFailureCard.swift`
- Create: `RPGPlayer/Features/Recovery/RetryTurnSheet.swift`
- Test: `RPGPlayerUITests/TurnRecoveryTests.swift`

- [ ] Present plain-language causes and whether campaign state changed.
- [ ] Allow retry with the same request ID only when no canonical final batch exists.
- [ ] Allow edit-and-resubmit with a new request ID and an explicit superseding event.
- [ ] Keep player action drafts through network errors and app relaunch.
- [ ] Test offline-before-submit, offline-mid-stream, provider quota, invalid key, safety refusal, cancellation, and relaunch.
- [ ] Run tests and commit `feat: add truthful turn recovery states`.

## Phase 3 Completion Gate

- [ ] All four adapters pass one shared contract suite.
- [ ] Credentials exist only in Keychain and redaction tests pass.
- [ ] Tool inputs cannot escape the app-owned schema/campaign boundary.
- [ ] Partial streams never partially mutate canonical state.
- [ ] Dice interruption, cancellation, retry, and relaunch are idempotent.
- [ ] A real BYOK turn completes from Your Move to transcript/Visual Novel.
- [ ] All nine visual states still match the recording.
