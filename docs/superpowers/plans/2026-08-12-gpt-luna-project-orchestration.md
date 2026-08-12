# GPT Luna Remaining-Project Orchestration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` to execute this plan. GPT Luna must be the model for every spawned worker. The root agent is a controller and gatekeeper, not an implementer.

**Goal:** Complete RPGPlayer from Phase 3 Task 4 through the Phase 6 release gate using fresh GPT Luna subagents for implementation, review, fixes, verification, research, and documentation while preserving strict TDD, phase gates, and the cloud-to-local acceptance boundary.

**Architecture:** A root controller owns dependency ordering, isolated phase branches/worktrees, the durable SDD ledger, worker briefs, review packages, integration, and owner approvals. Every unit of delegated work goes to an explicitly verified GPT Luna worker. One fresh implementer writes each task, a separate fresh reviewer gates it, and phase-level Luna reviewers gate integration before a phase can merge.

**Tech Stack:** Codex subagents, GPT Luna, Superpowers SDD workspaces, Git worktrees, Swift 6, SwiftUI, SwiftData, XCTest/XCUITest, AVFoundation, ActivityKit, Cloudflare Workers, TypeScript, Vitest, XcodeGen

## Global Constraints

- The private August 9, 2026 iPhone recording and `docs/visual-audit/native-craft-mobile-fidelity.md` remain the visual authority. This is not a redesign.
- Execute every implementation task with a meaningful RED → smallest GREEN → refactor cycle, focused verification, independent review, and a task commit.
- Do not silently skip, merge, reorder, or mark complete any task or phase gate.
- Do not advance a dependent task while its prerequisite is failed, mid-review, or blocked.
- The root controller does not implement production code or fixes. It may create briefs, ledgers, review packages, documentation links, and integration commits.
- Every spawned worker role—implementer, reviewer, fixer, researcher, security reviewer, verifier, documentation writer, and merge-conflict resolver—must use GPT Luna.
- Workers may not spawn nested agents. The root controller owns every dispatch, model check, worktree, and ledger entry.
- Do not substitute another model when GPT Luna is unavailable. Stop as `BLOCKED` and ask the user.
- Do not invent a GPT Luna selector. Resolve and smoke-test the exact currently exposed selector after restarting Codex.
- Keep cloud work deterministic and credential-free. Real keys, real provider connectivity, private captures, and user content never enter prompts, fixtures, commits, logs, or reports.
- Preserve Keychain-only credentials, bounded streaming, atomic event commits, deterministic replay, and frozen schema compatibility.
- Do not hyperfixate on unsupported or rare scenarios. Cover normal flows, the plans' explicit failure cases, security/data-loss boundaries, and failures demonstrated by evidence.
- Before each future-phase brief is dispatched, resolve its listed paths against the current repository and amend stale create/modify instructions; do not create a second type or file when an established cross-phase contract already exists.
- Keep one local Simulator booted during active testing and minimize boot/shutdown cycles. Never carry a local Simulator UDID into a cloud script.
- External deployment, production Cloudflare changes, APNs credentials, App Store Connect/TestFlight upload, real-key use, and release submission require explicit owner authorization at action time.
- Never commit `.superpowers/`, `build/`, `.worktrees/`, generated `RPGPlayer.xcodeproj`, private recordings/captures, credentials, or unsanitized provider payloads.

## 1. GPT Luna Selector Preflight

This preflight is mandatory in the fresh cloud session before any project worker is dispatched.

- [ ] Restart Codex so the current model catalog is authoritative.
- [ ] Inspect the model identifiers exposed by the active subagent tool.
- [ ] Resolve the exact identifier that the product exposes as GPT Luna; do not infer it from marketing copy or guess a string.
- [ ] Record the exact selector and supported reasoning tiers in `.superpowers/sdd/2026-08-12-gpt-luna-project-orchestration/progress.md`.
- [ ] Dispatch one harmless read-only worker using GPT Luna with a non-inheriting context fork.
- [ ] Confirm the returned dispatch metadata identifies GPT Luna.
- [ ] Record `GPT_LUNA_PREFLIGHT: PASS`, selector, timestamp, and smoke-worker ID in the ledger.
- [ ] If GPT Luna is absent, ambiguous, or cannot be confirmed, record `GPT_LUNA_PREFLIGHT: BLOCKED`, stop all delegation, and ask the user. Never inherit the root model or substitute Sol, Terra, or another model.

After the preflight, every spawn must set the verified GPT Luna selector explicitly. Reasoning tiers may vary within the verified Luna family:

- Mechanical one- or two-file implementation: lowest verified Luna tier that can reliably execute the complete brief.
- Multi-file integration, Swift concurrency, persistence, networking, audio, or backend work: standard/high Luna tier.
- Architecture, security/privacy, cryptography, exact-once reconciliation, phase review, and release review: highest verified Luna tier.
- Fix rounds 4–5: a fresh worker at least one verified Luna tier above the original implementer.

## 2. Controller and Worker Roles

### Root controller

The root agent performs orchestration only:

- Read the current `origin/main`, master plan, active phase plan, and tracked handoff.
- Create or verify one isolated branch/worktree per phase.
- Initialize and maintain the ignored SDD ledger for each phase plan.
- Record task base SHA, extract the exact task brief, and dispatch Luna workers.
- Answer `NEEDS_CONTEXT` questions using source and plan evidence.
- Freeze the branch during review, generate review packages, and adjudicate findings.
- Run or delegate final regression/verification commands and read their complete results.
- Push accepted task commits and integrate only after the correct gate passes.
- Obtain owner approval for deployments, real credentials, TestFlight, or other external mutations.

The root controller must not write production implementation or fix code. If the root notices a defect, it records a precise finding and dispatches a Luna fixer.

### Fresh GPT Luna implementer

Use one new worker per task. It receives only the extracted task brief, binding constraints, worktree/branch, prerequisite interfaces/decisions, and report path. It must:

1. Read the task brief first.
2. Establish a meaningful failing test for the expected reason.
3. Implement the smallest production change that makes the test pass.
4. Run focused tests and the applicable build/static checks.
5. Self-review the complete task diff.
6. Commit with the task plan's commit message unless current repository conventions require a precise equivalent.
7. Write a full report to its SDD report path.
8. Return only one of `DONE`, `DONE_WITH_CONCERNS`, `NEEDS_CONTEXT`, or `BLOCKED`, plus commit SHA and one-line verification summary.

An implementer is never reused for a different task.

### Fresh GPT Luna task reviewer

A different Luna worker performs a read-only review of the task brief, report, base-to-head diff, tests, and relevant contracts. It must return:

- `Spec compliant: YES|NO`
- `Quality approved: YES|NO`
- Severity-ranked findings with exact paths/lines and normal-flow impact
- Evidence gaps and deferred environment checks
- `READY` only when no load-bearing finding remains

Reviewers never edit, commit, run destructive commands, or touch Simulator lifecycle.

### GPT Luna fix workers

- Fix rounds 1–3 resume the task's original implementer.
- Fix rounds 4–5 use a new higher-tier Luna implementer.
- Every fix starts from a finding-specific RED or existing failing proof, makes the smallest change, adds a separate commit, updates the report, and receives a fresh scoped Luna re-review.
- After five failed rounds, the root controller adjudicates each remaining item. Park only a clearly non-load-bearing issue with a written rationale. Mark a load-bearing issue `BLOCKED` and stop dependent tasks.

### GPT Luna specialist and phase workers

- Add a separate Luna security/privacy review when a task changes credentials, authentication, cryptography, native tool boundaries, exact-once persistence, server data handling, privacy manifests, or release boundaries.
- At each cloud/local handback, dispatch a fresh Luna verifier/handoff writer to update the tracked handoff with exact branch/SHA, commits, tests, deferred checks, and risks.
- At each phase end, dispatch a fresh Luna whole-phase reviewer. Phase 5 and Phase 6 require both a general phase reviewer and a separate security/privacy reviewer.

## 3. Durable Ledger and Context Hygiene

Each phase plan owns an ignored workspace created with the SDD helper:

~~~bash
scripts/sdd-workspace docs/superpowers/plans/<phase-plan>.md
~~~

If the helper is installed with Superpowers rather than in the repository, use the skill's resolved absolute script path. The ledger's first line must identify its phase plan exactly:

~~~markdown
# SDD ledger — plan: docs/superpowers/plans/<phase-plan>.md
~~~

For every task, record:

- Base and accepted head SHA
- GPT Luna selector/tier and worker IDs
- Brief, report, and review-package paths
- RED command and expected failure
- GREEN/regression/build commands and exact result counts
- Review verdict and all findings
- Fix-round commits and re-review verdicts
- Parked findings with controller ruling
- Local/device evidence explicitly deferred
- Push status and remote branch SHA

Use fresh non-inheriting worker contexts. Do not paste the full conversation or growing project history into prompts. A task brief is the source of requirements; the ledger and Git history are the recovery map after compaction.

## 4. Per-Task Execution Gate

For every remaining task:

- [ ] Root confirms all prerequisites and the preceding task review are accepted.
- [ ] Root records `BASE=$(git rev-parse HEAD)` and extracts the task brief.
- [ ] Fresh Luna implementer creates the intended RED and records its evidence.
- [ ] The same implementer reaches GREEN, self-reviews, commits, and writes its report.
- [ ] Root freezes the branch and creates a base-to-head review package.
- [ ] Fresh Luna reviewer returns spec and quality verdicts.
- [ ] A security/privacy Luna reviewer runs when the specialist trigger applies.
- [ ] Every load-bearing finding completes the bounded fix/re-review loop.
- [ ] Applicable regression lane and build pass on the accepted head.
- [ ] Root records task completion in the ledger and pushes the feature branch.
- [ ] Only then may the next task start.

One task reviewer is sufficient by default. Minor speculative improvements do not trigger churn; record them for the phase reviewer unless they violate the plan, a normal flow, security/privacy, data integrity, accessibility, or accepted visual behavior.

## 5. Branch, Worktree, Commit, and Push Protocol

Use these phase branches/worktrees:

| Phase | Branch | Worktree |
|---|---|---|
| Phase 3 | `codex/phase3-cloud-continuation` | `.worktrees/phase3-cloud-continuation` |
| Phase 4 | `codex/phase4-voice` | `.worktrees/phase4-voice` |
| Phase 5 | `codex/phase5-durable` | `.worktrees/phase5-durable` |
| Phase 6 | `codex/phase6-testflight` | `.worktrees/phase6-testflight` |

- Create each branch from the then-current accepted `origin/main`.
- Exactly one writer may operate in a worktree at a time.
- Freeze that branch while a reviewer reads it.
- Implementers commit; reviewers never commit.
- Fixes are additional commits. Do not amend already reviewed or pushed commits.
- Push after each accepted task so cloud progress is durable.
- Never push a failing or mid-review range.
- Never force-push.
- Do not merge a phase into `main` until its full completion gate passes in the correct environment.
- When parallel Phase 4/5 history must converge, merge updated `origin/main` into the surviving feature branch, run complete integration checks, and review the merge. Do not rebase already-pushed history.

Maximum concurrency is three active Luna workers plus the root controller:

- Within a phase: one writer, or one reviewer while the branch is frozen.
- Across proven-independent phase worktrees: at most two writers; the third Luna slot may review the other branch.
- Never send two writers to the same branch or overlapping files.
- Phase 3 is fully sequential.
- Phase 6 is fully sequential after Phases 4 and 5.

## 6. Remaining-Project Worker Sequence

### Phase 3 — AI GM providers and tools

**Active plan:** `docs/superpowers/plans/2026-08-09-ai-gm-providers-tools.md`
**Branch:** `codex/phase3-cloud-continuation`
**Execution:** sequential

Cloud Luna workers execute:

1. Task 4 — Implement OpenAI and OpenRouter Adapters
2. Task 5 — Implement Anthropic and Gemini Adapters
3. Task 6 — Assemble Bounded Campaign Context
4. Task 7 — Define and Validate Native GM Tools
5. Task 8 — Implement Turn Engine and Atomic Commit
6. Task 9 — Add Dice Roll Interruption

Mandatory Task 8 preflight decisions, with migration tests if source contracts change:

- Reconcile `CampaignEvent.requestID` as one accepted atomic append run with the longer-lived turn/roll lineage needed by Tasks 8–9. Do not silently reuse a request ID in non-contiguous store/reducer runs.
- Preserve interleaved `StoryBlock` order when mapping `TurnEnvelope` into persisted `GMMessageCommittedPayload`; current separated narration/dialogue arrays must not reorder story after relaunch.

After Task 9, a fresh Luna verifier/handoff worker updates the tracked cloud handoff and the root pushes the exact reviewed SHA. Hand back to the local Mac before Task 10 integration, or earlier if real credentials/runtime behavior become necessary.

Local Luna workers then execute:

7. Task 10 — Wire Real Generation into the Recording-Faithful UI
8. Task 11 — Add Failure, Retry, and Offline UX
9. Phase 3 completion gate and whole-phase reviews

Local Phase 3 acceptance must include the full unit/build/regression lanes, real BYOK validation, one real tool-and-roll turn, recorded-transport offline equivalence, and the nine-state visual comparison. No Phase 4 or Phase 5 task starts before Phase 3 passes locally and lands on `main`.

### Phase 4 — ElevenLabs native voice

**Active plan:** `docs/superpowers/plans/2026-08-09-elevenlabs-native-voice.md`
**Branch:** `codex/phase4-voice`
**Execution:** sequential within the phase

Fresh Luna implementer/reviewer pairs execute Tasks 1–9 in plan order:

1. Define Speech, Voice, and Assignment Contracts
2. Add ElevenLabs Credential and Voice Discovery
3. Build Campaign Voice Assignment
4. Implement Streaming ElevenLabs Synthesis
5. Implement Audio Cache and Pronunciation Dictionaries
6. Build Playback and Audio-Session Coordination
7. Add Apple Speech Fallback
8. Connect Voice to Visual Novel Auto and Transcript
9. Validate Background Audio Boundaries

Tasks 1 and deterministic portions of later tasks may run without real credentials, but live ElevenLabs discovery, streaming, preview, audio-session/interruption, background audio, hardware routes, and final Visual Novel Auto acceptance are local/device gates.

### Phase 5 — Durable turns and Live Activity

**Active plan:** `docs/superpowers/plans/2026-08-09-durable-turns-live-activity.md`
**Branch:** `codex/phase5-durable`
**Execution:** sequential within the phase; limited overlap with Phase 4 after Phase 3 passes

Fresh Luna implementer/reviewer pairs execute Tasks 1–11 in plan order:

1. Freeze the Cross-Platform Job Protocol
2. Scaffold the Cloudflare Service
3. Implement Anonymous Installation Registration
4. Implement Job Envelope Encryption and Consent
5. Implement Per-Job Durable Object Storage
6. Implement Submission, Status, Cancel, and Acknowledge Routes
7. Implement the Durable Turn Workflow
8. Send ActivityKit Push Updates
9. Reconcile Durable Results Exactly Once
10. Add iOS Background Enhancements Without Correctness Dependency
11. Enforce Retention, Observability, and Abuse Limits

After Phase 3 passes, Phase 4 and Phase 5 Tasks 1–6 may occupy separate worktrees concurrently because their write sets are largely independent. Pause Phase 5 before Task 7 wherever optional server voice integration depends on Phase 4 contracts. After Phase 4 passes and lands, merge updated `origin/main` into the Phase 5 branch, run complete Swift/TypeScript integration tests, and obtain a Luna merge review before continuing.

Cloud Luna workers may implement deterministic backend/protocol/crypto/storage/route tests. Real Cloudflare deployment, App Attest, APNs, ActivityKit push, Dynamic Island, suspension/termination, and cleanup/TTL acceptance require the configured local/device/development environment and explicit owner authorization.

Phase 5 workers must evolve the existing `Shared/TurnActivityAttributes.swift` and `TurnActivityExtension/TurnActivityWidget.swift`, not create parallel ActivityKit contracts. New voice/job/store fixtures must be excluded from the shipping app target in `project.yml` unless they are explicitly release-safe resources.

### Phase 6 — TestFlight hardening

**Active plan:** `docs/superpowers/plans/2026-08-09-testflight-hardening.md`
**Branch:** `codex/phase6-testflight`
**Execution:** sequential after Phase 4 and Phase 5 gates pass

Fresh Luna implementer/reviewer pairs execute Tasks 1–10 in plan order:

1. Centralize Release Configuration
2. Complete Data Migrations and Corruption Recovery
3. Run Full Accessibility Remediation
4. Measure and Fix Performance
5. Harden Network and Failure Recovery
6. Perform Security and Privacy Verification
7. Complete Visual Fidelity Regression
8. Validate Live Activity and Background Behavior on Device
9. Prepare TestFlight Product Material
10. Archive and Release Candidate Gate

Phase 6 is local-first. Accessibility Inspector/VoiceOver, Instruments, signing, archive inspection, clean-device installation, App Store Connect/TestFlight, privacy answers, and the full acceptance journey cannot be inferred from cloud tests. The root must obtain owner approval immediately before any upload or release action.

## 7. Cloud-to-Local Handback Gate

Before handing a branch from cloud to local, dispatch a fresh Luna verifier/handoff worker. It must commit an update to `docs/handoffs/2026-08-12-cloud-continuation.md` containing:

- Feature branch and exact remote head SHA
- Completed task commits and review verdicts
- RED/GREEN/regression commands and exact results
- Changed contracts and migration implications
- Secret/privacy scan result
- Deferred Xcode, Simulator, credential, visual, device, audio, APNs, background, or release evidence
- Known risks and first local command

The local root then:

1. Fetches without overwriting local changes.
2. Inspects the exact `origin/main..origin/<feature>` commit range.
3. Scans for credentials, private fixtures, generated artifacts, and unexpected binaries.
4. Regenerates with XcodeGen.
5. Reuses the already-running Simulator; no reboot/erase unless genuinely unavailable.
6. Runs full units, app build, focused UI, and relevant visual regression.
7. Performs the real-provider/device acceptance required by the current gate.
8. Dispatches a Luna local integration reviewer.
9. Merges and pushes `main` only after every load-bearing gate passes.

## 8. Phase Completion and Final Release Gates

At each phase end:

- [ ] Every task has an accepted commit and clean task review.
- [ ] The phase ledger contains no unresolved load-bearing finding.
- [ ] The full phase test/build matrix passes in the required environment.
- [ ] A fresh Luna whole-phase reviewer returns READY.
- [ ] Specialist Luna security/privacy review passes where required.
- [ ] The tracked implementation status and handoff are updated.
- [ ] The root integrates and pushes only after the completion gate passes.

At project end, Phase 6 requires two clean full acceptance journeys from a clean TestFlight install, a reproducible release archive, matching privacy/retention claims, and explicit owner approval for submission. A Luna worker may prepare and verify the release, but it may not independently authorize the upload or submission.

## 9. Recovery, Blocking, and Stop Conditions

The controller stops rather than improvising when:

- GPT Luna cannot be positively selected and smoke-verified.
- A plan conflict changes product behavior or a frozen contract without an unambiguous migration path.
- A task reaches five failed fix rounds with a load-bearing finding.
- Required real credentials, private visual authority, hardware, signing, APNs, Cloudflare account state, or owner consent is unavailable.
- A test failure suggests security, data loss, duplicate canonical commits, or release leakage.
- The current branch/worktree contains overlapping unknown user changes.

Normal simulator/runtime flakiness is diagnosed with evidence but not used to justify speculative product rewrites. When the necessary environment is unavailable, record the exact deferred check and continue only with work that does not depend on it.

## 10. First Dispatch in the Fresh Cloud Session

After the GPT Luna selector preflight passes:

1. Fetch current `origin/main` and confirm `docs/handoffs/2026-08-12-cloud-continuation.md` plus this plan are present.
2. Create `codex/phase3-cloud-continuation` in `.worktrees/phase3-cloud-continuation`.
3. Initialize the Phase 3 SDD ledger and copy the Luna preflight record into it.
4. Extract Phase 3 Task 4 from `docs/superpowers/plans/2026-08-09-ai-gm-providers-tools.md` into a task brief.
5. Dispatch a fresh GPT Luna implementer with a non-inheriting fork to establish the OpenAI/OpenRouter adapter-contract RED.
6. Continue without asking the user between tasks unless a defined stop condition occurs.
