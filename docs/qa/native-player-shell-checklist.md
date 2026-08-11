# Native Player Shell — Phase 1 QA Checklist

**Last evidence review:** August 10, 2026
**Visual authority:** the private 57-second iPhone recording, then `docs/visual-audit/native-craft-mobile-fidelity.md`
**Current gate status:** **PASS — the canonical Phase 1 visual-fidelity gate is accepted.**

This document deliberately separates source, automated Simulator, visual-comparison, archive, physical-device, and real-VoiceOver evidence. Passing XCTest does not establish visual fidelity, and Simulator evidence does not satisfy a physical-device or real-VoiceOver requirement.

## Status and Evidence Rules

- **Source-verified:** inspected in the current worktree, whose committed baseline is `e5a8542` plus in-progress Task 8 changes; no runtime claim.
- **Simulator-verified:** backed by a named `.xcresult` from the current Task 8 implementation lineage.
- **Visual-verified:** requires a fresh, same-viewport side-by-side comparison between the current app capture and the corresponding recording frame.
- **Device/VoiceOver:** must be performed on physical hardware or with real VoiceOver; XCTest accessibility queries do not count.
- `[x]` means the named evidence exists and passed only the stated scope.
- `[ ]` means pending, failed, blocked, historical, stale, or not yet evidenced. Do not infer green status from implementation alone.

Current caveats:

- All nine canonical states were captured at the recording's exact 1320×2868 resolution, combined with the available authority evidence, and accepted on August 10, 2026. Final artifacts are retained under `build/VisualQA/Task8CanonicalMax`.
- The current Max full-suite bundle executed 46 tests: 45 passed and one accessibility-size keyboard test ended in an XCTest snapshot timeout. One focused retry reproduced the same event-loop/query timeout, with no bad-geometry assertion or crash. Per the owner's direction, this edge lane is documented rather than expanded further.
- The Assistant fixture was the only production change after that aggregate build; its complete interaction test was rerun and passed in `build/TestResults/task8-assistant-max-density2-final.xcresult`.
- The unsigned generic-iOS archive succeeded at `build/RPGPlayer-Phase1.xcarchive`; its app and extension plists parse, both binaries are arm64, and no captured recording, private path, Craft Docs brand string, or source image asset is bundled.
- Physical-device and real-VoiceOver checks remain explicitly unverified. They are follow-up evidence, not claims made by this Simulator visual gate.
- No manual shutdown or reboot was issued. XcodeBuildMCP returned the Max to `Shutdown` after its final request; it was booted once at handoff, and both the Pro and Pro Max are now left running.

## Evidence Inventory

Earlier task increments used temporary result bundles that are no longer retained. They are not cited as current acceptance evidence; only the durable `build/TestResults` artifacts below count.

Accepted current Task 8 Simulator evidence:

- [x] **iPhone 16 Pro Max / canonical core:** 4/4 passed — generation, Overview, Visual Novel/transcript, and Your Move — `build/TestResults/task8-canonical-core-max.xcresult`.
- [x] **iPhone 16 Pro Max / drawer and campaign loop:** 4/4 passed — overlays, gesture dismissal, Packages, and the exact loop — `build/TestResults/task8-core-drawers-loop-max.xcresult`.
- [x] **iPhone 16 Pro Max / project Files and Search keyboard:** 1/1 passed — `build/TestResults/task8-project-max-final.xcresult`.
- [x] **iPhone 16 Pro Max / final Assistant density and behavior:** 1/1 passed — `build/TestResults/task8-assistant-max-density2-final.xcresult`.
- [x] **iPhone 16 Pro / focused Assistant behavior:** 1/1 passed — `build/TestResults/task8-green-assistant-pro-final.xcresult`.
- [x] **iPhone 16 Pro / focused Project behavior:** 1/1 passed — `build/TestResults/task8-green-project-pro-final.xcresult`.
- [x] **iPhone 16 Pro / focused Transcript behavior:** 1/1 passed — `build/TestResults/task8-green-transcript-pro.xcresult`.
- [x] **Full Max aggregate:** 45/46 passed; the only failure was a repeated XCTest snapshot timeout in the accessibility-size keyboard lane — `build/TestResults/task8-full-max-45-of-46.xcresult` and `build/TestResults/task8-ax-turn-max-timeout-repeat.xcresult`.
- [x] **Unsigned archive proof:** `build/RPGPlayer-Phase1.xcarchive` was produced and inspected with signing disabled.

## Source-Verified Foundations

- [x] Full-bleed scene composition and stationary overlay layers are present in `PlayerShellView`.
- [x] Compact drawer metrics are encoded as 72% left and 90% right, with regular-width caps, in `PlayerLayoutMetrics`.
- [x] Drawer exclusivity and presentation state are reducer-owned rather than view-local.
- [x] Visual Novel, transcript, Your Move, generation, and fixture streaming exist in focused feature/service files.
- [x] Generation work-step copy is sanitized by `SimulatedTurnStreaming` before presentation.
- [x] Reduce Motion and Reduce Transparency environment branches exist in the primary shell and affected feature views.
- [x] Modal accessibility traits, escape actions, explicit labels/identifiers, and focus-restoration hooks exist for the drawers and turn sheet.
- [x] Production target sources contain no captured Craft image asset or `Craft` product/trademark string.
- [x] Produced archive scan found no captured recording, private path, source image asset, Craft Docs brand string, or embedded user identifier.

## Nine Canonical Fidelity Captures

Every row below uses the final iPhone 16 Pro Max capture at 1320×2868. The available recording-derived comparisons were judged together with the full nine-state grid; app-owned fixture copy/artwork and native keyboard differences remain intentional.

| Canonical state | Required visual result | Current evidence | Gate |
|---|---|---|---|
| Generation over closed player canvas | Full-bleed scene and cutout remain visible; centered header; close above bottom status card; disclosure stays in the same visual system | `build/VisualQA/Task8CanonicalMax/01-generation-collapsed.png` | [x] |
| Right drawer — Overview | 88–90% width; narrow leading scene sliver; stationary canvas; dense modules and artwork | `build/VisualQA/Task8CanonicalMax/02-overview-drawer.png`; final comparison retained | [x] |
| Right drawer — Assistant | Same drawer geometry; independent history/context/tools/composer; no resize on tab switch | `build/VisualQA/Task8CanonicalMax/03-assistant-drawer-final.png`; `assistant-authority-current-final.png` | [x] |
| Left drawer — Files | 71–73% width; trailing scene strip; dense file tree; lower controls remain pinned | `build/VisualQA/Task8CanonicalMax/04-project-files.png`; `files-authority-current-final.png` | [x] |
| Left drawer — Search + keyboard | Existing drawer remains 71–73%; field below tabs; native keyboard/accessory; scene strip remains visible | `build/VisualQA/Task8CanonicalMax/05-project-search-keyboard.png` | [x] |
| Visual Novel — Title beat | No character cutout; compact controls above highly tracked title card; attached Continue | `build/VisualQA/Task8CanonicalMax/06-visual-novel-title.png` | [x] |
| Visual Novel — Dialogue beat | Controlled character cutout; previous/count/speaker/close row; bottom-anchored dialogue card | `build/VisualQA/Task8CanonicalMax/07-visual-novel-dialogue.png` | [x] |
| Transcript + collapsed Your Move | One continuous story surface, inset dialogue cards, dock pinned independently above home indicator | `build/VisualQA/Task8CanonicalMax/08-transcript-collapsed-move.png`; `transcript-authority-current.png` | [x] |
| Expanded Your Move | Sheet expands upward without replacing scene/header; dense choices; separate custom/context fields; pinned Confirm | `build/VisualQA/Task8CanonicalMax/09-your-move-expanded.png` | [x] |

The Phase 4 narration/Auto expansion is intentionally outside this Phase 1 capture gate. Phase 1 must not fake or prematurely claim that later behavior.

## Simulator Functional Checklist

### Shell and drawers

- [x] Fresh canonical captures verify that the header remains optically centered despite unequal side controls.
- [x] Left and right drawers overlay rather than push the scene in the accepted Max non-keyboard campaign.
- [x] Only one drawer can be open at a time, and both explicit drawer close controls are exercised.
- [x] `testDrawerSceneStripsAndSwipesDismissWithoutMovingTheCanvas` covers scene-strip dismissal and both drawer swipe directions.
- [x] Project search query survives keyboard dismissal and drawer close/reopen in the accepted Max keyboard lane.
- [x] Project-search field and actual keyboard-dismiss button expose at least 44×44-point hit regions in the accepted Max keyboard lane.
- [ ] Re-run drawer focus containment/restoration with real VoiceOver; `isModal` and XCTest hittability are source/automation evidence only.

### Visual Novel

- [x] Continue advances one beat, count updates, previous does not underflow, close preserves the current beat, and the final beat enters the player turn in accepted unit/UI tests.
- [x] Current title/dialogue fixtures exercise the intended text, speaker, mood, count, card, and Continue states in the accepted Max non-keyboard campaign.
- [x] Fresh title/dialogue comparisons verify the intended absence/presence and hierarchy of the character cutout.
- [x] At accessibility size, automation verifies that the story viewport remains below the header and separate from a reachable 44-point Continue control.

### Transcript and Your Move

- [x] Transcript stays a single surface and the Your Move dock remains independently pinned in the accepted Max non-keyboard campaign.
- [x] Suggestions, custom action, and additional context remain separate inputs; Confirm requires a valid action.
- [x] The accepted Max keyboard lanes keep project search, Assistant composer, custom action, and Confirm reachable above the keyboard.
- [ ] The final Max accessibility-size keyboard lane hit a repeated XCTest snapshot timeout before it could query the custom editor; no new product-layout claim is made from that run.
- [x] Accessibility-size automation keeps the latest GM question above the measured dock and retains it through repeated transcript scrolling.

### Generation and completion

- [x] Ordered simulated phases, one sanitized step per phase, and exactly one completion have accepted unit/UI evidence.
- [x] Current automation verifies the generation card, status, stop control, and collapsed/expanded disclosure geometry.
- [x] The fresh generation capture preserves the full scene/cutout/header hierarchy and recording-shaped bottom band.
- [x] The current fixture campaign appends exactly one completed GM message and returns to a two-message transcript — `build/TestResults/task8-core-drawers-loop-max.xcresult`.
- [x] Reducer tests reject duplicate and late completion, while the stop-flow UI test keeps the app out of Visual Novel after user cancellation.

### Accessibility and reduced effects

- [x] Accessibility-size automation exercises multiline header growth and effective 44×44-point header controls.
- [x] Accessibility-size automation keeps both drawer tab rows and package-sheet controls horizontally contained and reachable.
- [x] Accessibility-size source/UI evidence leaves story text uncapped and keeps Visual Novel story/Continue regions operable.
- [x] Accessibility-size evidence keeps transcript and Your Move choices reachable; the repeated final keyboard snapshot timeout is recorded separately above.
- [x] Deterministic Reduce Motion and Reduce Transparency overrides keep drawers, Visual Novel, transcript, and Your Move operable in the accepted Max non-keyboard campaign.
- [ ] Bright-art contrast: test white and secondary text over an intentionally bright scene fixture; existing dark artwork is insufficient evidence.
- [x] Final `.xcresult` inspection found no invalid-frame or layout-cycle warning; the locked physical-device notification noise and repeated AX-size snapshot timeout are recorded as harness evidence.
- [ ] Repeat the accessibility traversal with real VoiceOver; automation does not establish spoken order, focus trapping, or focus restoration.

## Simulator Device Matrix

Keep booted Simulators running throughout active testing. Reuse the current devices, minimize boot/shutdown cycles, and only boot an additional device when the matrix requires it; if an iPad is booted, leave it running through the remaining testing.

- [x] Largest iPhone functional coverage: the accepted iPhone 16 Pro Max bundles cover all non-keyboard tests plus project search, Assistant, and custom-move keyboard lanes.
- [x] Largest iPhone visual coverage: all nine canonical states passed fresh same-viewport review at 1320×2868.
- [x] iPhone 16 Pro targeted keyboard coverage: Project and Assistant passed without rebooting the Simulator.
- [ ] iPhone 16 Pro adaptive/non-keyboard coverage and all nine applicable canonical visual states.
- [ ] Smallest installed iPhone: all applicable canonical states; no clipping, overlap, or unreachable controls.
- [ ] iPad Pro 13-inch: non-keyboard adaptive layouts and capped drawer widths.
- [ ] iPad Pro 13-inch keyboard lanes: search and custom action. Retry with in-place pasteboard-service recovery if needed; do not count a deadlocked run as an app failure or a pass.
- [ ] Score every final capture against the project’s 42-item visual-review rubric and retain the screenshots.

## Physical-Device Checklist

These remain open until performed on actual hardware.

- [ ] iPhone 16 Pro Max portrait: header matches the recording proportions.
- [ ] iPhone 16 Pro portrait: no horizontal clipping.
- [ ] Left drawer covers 72% ± 2% and leaves a scene sliver.
- [ ] Right drawer covers 90% ± 2% and leaves a scene sliver.
- [ ] Visual Novel title and dialogue retain the scene artwork and controlled character crop.
- [ ] Transcript is one continuous material surface.
- [ ] Your Move remains above the home indicator.
- [ ] Choice sheet supports suggestion, custom text, context, cancellation, and keyboard avoidance.
- [ ] Generation phases and sanitized steps are visible without layout jumps.
- [ ] Reduce Motion and Reduce Transparency remain usable.
- [ ] Bright imported artwork preserves readable text contrast.
- [ ] No captured Craft asset or trademark appears in the installed bundle.

## Real VoiceOver Checklist

Perform with VoiceOver enabled; XCTest element order is not a substitute.

- [ ] Closed player traversal follows header → active story/generation surface → bottom action surface.
- [ ] Opening either drawer traps focus inside the modal drawer.
- [ ] Drawer tabs, disclosures, state values, dense file rows, and close actions are announced in visual order.
- [ ] Closing the left drawer restores focus to the project/menu button.
- [ ] Closing the right drawer restores focus to the overview button.
- [ ] Visual Novel announces beat position, speaker/mood, story, and Continue in a coherent order.
- [ ] Transcript reads chronologically without treating decorative art as content.
- [ ] Expanded Your Move announces selection state, keeps custom action distinct from additional context, and reaches Confirm.
- [ ] Generation announces phase/status changes without reading decorative progress elements repeatedly.
- [ ] Every small-looking icon control has a discoverable label and an effective 44×44-point target.

## Phase 1 Completion Gate

The accepted automated fixture campaign establishes the following functional loop on Simulator:

- [x] Launch in transcript mode over a full-bleed scene.
- [x] Open and dismiss both recording-proportioned drawers with their explicit close controls.
- [x] Expand Your Move, select a valid action, and confirm.
- [x] Observe ordered generation phases and sanitized steps.
- [x] Receive exactly one completed GM message.
- [x] Advance that message through all Visual Novel beats.
- [x] Return to transcript mode with exactly two GM messages and no duplicate completion.
- [ ] Explicitly assert preservation of the expected transcript scroll and Visual Novel beat position after the full loop; the current campaign does not prove both.
- [x] All nine canonical side-by-side comparisons pass.
- [x] The full Max aggregate passed 45/46 tests; the sole accessibility-size keyboard case repeated the same XCTest event-loop/snapshot timeout in one focused retry. No crash or bad-layout assertion was reported.
- [x] The only post-aggregate production change affected Assistant fixture density; its complete behavior test was rerun and passed on Max.
- [x] Unsigned generic-device archive succeeds and its bundle inspection passes.
- [ ] Required physical-device and real-VoiceOver checks above are recorded.

**Gate decision:** the Phase 1 canonical visual-fidelity gate passes. Physical-device, real-VoiceOver, broad device-matrix, and the repeated AX-size snapshot timeout remain documented follow-ups; no later phase was started in this task.
