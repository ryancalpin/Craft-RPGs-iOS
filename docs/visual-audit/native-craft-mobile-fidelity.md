# Native Craft Mobile Fidelity Audit

**Audit date:** August 9, 2026  
**Source:** User-supplied 57-second iPhone recording, 1320×2868 pixels  
**Scope:** Plan-level visual and interaction verification before implementation  
**Status:** The implementation plan covers every observed primary state. Runtime fidelity remains unverified until the Phase 1 SwiftUI app can be captured at the same viewport.

## Audit Method

Ten frames were extracted from the recording in this audit run and inspected individually. The recording is authoritative; generated mockups and written assumptions are subordinate. Each state below maps to a concrete implementation task and measurable capture gate.

![Recording evidence contact sheet](evidence/contact-sheet.png)

## Source Measurements and Invariants

- The scene image is a single full-bleed canvas beneath the status bar, header, story surface, character cutout, drawers, and bottom controls.
- The header is visually transparent with a top readability gradient: menu at leading edge, campaign title optically centered, overview button at trailing edge.
- There are no persistent side rails in compact width.
- The left drawer occupies about 72% of the content width and leaves a meaningful scene strip.
- The right drawer occupies about 88–90% and leaves a narrow leading scene strip.
- Drawers overlay the canvas; they do not push the player into a desktop split view.
- Visual Novel controls sit immediately above the dialogue/title card, not in the header or a permanent bottom toolbar.
- Transcript content uses one continuous translucent story surface with inset dialogue cards.
- `Your Move` is pinned above the home indicator and expands upward without replacing the scene/header.
- Generation keeps the scene and cutout visible and reuses the bottom dialogue area for status.

## Step-by-Step Fidelity Matrix

### 1. Closed Player Canvas and Generation

**Health:** Plan-aligned; runtime capture pending.

![Generation reference](evidence/vn-generation.png)

Observed:

- Full-bleed scene and lower character cutout remain present.
- Minimal three-item header stays visible.
- Circular close control floats above the bottom card.
- Bottom card has a large circular avatar, one natural-language status line, and a trailing disclosure.
- No spinner-dominated loading page, tab bar, or separate navigation bar appears.

Implementation mapping:

- Phase 1 Tasks 3, 4, and 7.
- Phase 3 Task 10 replaces simulation without changing geometry.
- Phase 5 mirrors the same status vocabulary to ActivityKit.

Acceptance:

- At 430×932 points, scene reaches all four display edges.
- Header title remains centered independently of unequal side-button widths.
- Generation card stays above the home indicator and does not jump as status copy changes.
- Disclosure reveals sanitized work steps within the same visual system.

### 2. Right Drawer — Overview

**Health:** Plan-aligned; runtime capture pending.

![Overview reference](evidence/right-overview.png)

Observed:

- Narrow scene sliver remains on the leading edge.
- A compact segmented Overview/Assistant control anchors the top.
- Overview is a vertically scrolling stack of collapsible modules.
- Music, map, pinned file, and character sheet modules use dense dark surfaces.
- Map and pinned-file artwork are content, not decorative chrome.

Implementation mapping:

- Phase 1 Task 4 owns the overlay, width, tabs, modules, and gesture dismissal.
- Phase 2 supplies imported map/file/character data.

Acceptance:

- Drawer width is 88–90% in compact width.
- Canvas remains visually stationary behind the drawer.
- Only one drawer can be open.
- Module headers, artwork crops, and disclosure state match the source density.

### 3. Right Drawer — Assistant

**Health:** Plan-aligned; assistant data policy requires implementation validation.

![Assistant reference](evidence/right-assistant.png)

Observed:

- It is the second tab of the same right drawer, not a new screen.
- It has its own conversation history, context chip, utility row, token/context indicator, and composer.
- Assistant tool results appear as readable cards and an `Actions` disclosure.
- The underlying game remains visible only as a narrow leading strip.

Implementation mapping:

- Phase 1 Task 4 builds fixture behavior.
- Phase 3 tool validation governs any assistant action.
- The product specification requires explicit confirmation before assistant mutations affect the live campaign.

Acceptance:

- Switching tabs does not close or resize the drawer.
- Assistant scroll/composer state is independent from the main transcript.
- No assistant action silently mutates campaign events.

### 4. Left Drawer — Project Files

**Health:** Plan-aligned; runtime capture pending.

![Files reference](evidence/left-files.png)

Observed:

- Drawer starts at the leading edge and leaves a wider trailing scene strip than the right drawer leaves on the left.
- `Exit Game` is at top, followed by three content tabs and a compact action row.
- The file tree is dense, uses disclosure controls, type-colored icons, counts, and a scrollbar.
- Settings, Trash, and profile are pinned to the lower section.

Implementation mapping:

- Phase 1 Task 4 builds overlay, tabs, file hierarchy fixture, and pinned lower controls.
- Phase 2 Task 7 replaces fixtures with normalized imported records.

Acceptance:

- Drawer width is 71–73% in compact width.
- Lower controls remain reachable while the file tree scrolls independently.
- Tapping the scene strip, swiping left, or activating the header control dismisses it.
- Dismissal restores accessibility focus to the menu button.

### 5. Left Drawer — Search and Keyboard

**Health:** Plan-aligned; keyboard avoidance must be verified on device.

![Search reference](evidence/left-search.png)

Observed:

- Search is a tab inside the existing drawer.
- The search field is directly beneath the tab strip.
- An empty-state sentence is centered in the remaining drawer area.
- Native iOS keyboard and input accessory appear without converting the drawer into a full-screen route.

Implementation mapping:

- Phase 1 Task 4 builds the fixture search state.
- Phase 2 Task 7 connects normalized records and debounced async search.

Acceptance:

- Focus does not resize the scene strip away.
- Search restarts after a 250 ms debounce and treats cancellation as normal.
- Input accessory, keyboard dismissal, and drawer dismissal do not lose the query unexpectedly.

### 6. Visual Novel — Title Beat

**Health:** Plan-aligned; runtime typography/crop pending.

![Title beat reference](evidence/vn-title.png)

Observed:

- The title beat removes the character cutout.
- Beat count, speaker control, and close remain in a compact row above the card.
- The card uses highly tracked uppercase title and an italic subtitle.
- Continue overlaps/attaches visually to the bottom edge of the card.

Implementation mapping:

- Phase 1 Task 5.
- Phase 4 Task 8 adds voice without moving the control row.

Acceptance:

- Title card occupies the lower visual band and leaves most art unobscured.
- Subtitle wraps without colliding with Continue.
- Continue advances exactly one beat and the beat count updates.

### 7. Visual Novel — Dialogue Beat

**Health:** Plan-aligned; runtime typography/cutout pending.

![Dialogue beat reference](evidence/vn-dialogue.png)

Observed:

- Character cutout sits between background and bottom card.
- Previous appears at leading; count, speaker, and close cluster at trailing.
- Dialogue card contains avatar, speaker, mood pill, large readable copy, and attached Continue.
- The card grows for content but preserves bottom anchoring.

Implementation mapping:

- Phase 1 Task 5.
- Phase 4 Tasks 6 and 8.

Acceptance:

- Cutout uses aspect-fit/controlled crop and is never stretched.
- Text scrolls within bounded dialogue treatment only when required by accessibility sizes.
- Closing preserves current beat; previous never underflows.

### 8. Visual Novel — Narration and Auto

**Health:** Plan-aligned; source frame contains recording-motion artifacts, so stable adjacent frames govern typography.

![Auto control reference](evidence/vn-auto.png)

Observed:

- Activating narration expands the speaker control inline to reveal `Auto` and a toggle.
- The expanded control overlays the scene directly above the card.
- Header, beat count, previous, close, and Continue remain in place.

Implementation mapping:

- Phase 4 Task 8.

Acceptance:

- Expansion does not reflow the dialogue card or move the campaign header.
- Auto advances only after playback completion.
- Roll, player decision, error, interruption, previous, or close stops Auto.

### 9. Transcript and Collapsed Your Move

**Health:** Plan-aligned; long-content performance pending.

![Transcript reference](evidence/transcript.png)

Observed:

- Story is one continuous translucent surface over the scene.
- Narrator prose is full width; character dialogue uses inset bordered cards with avatar initials, speaker, and mood.
- `Actions` appears as a low-emphasis collapsed disclosure inside the story.
- `Your Move` is a separate pinned dock with a subtitle explaining that the GM is waiting.

Implementation mapping:

- Phase 1 Task 6.
- Phase 2 Task 9 supplies event-replayed story.
- Phase 3 Tasks 7–10 supply real actions and turns.

Acceptance:

- The transcript is not redesigned into message bubbles.
- Latest GM question ends above the dock.
- Scrolling transcript does not move the dock.
- Older content virtualizes without changing visible typography or spacing.

### 10. Expanded Your Move

**Health:** Plan-aligned; keyboard/custom-input variants pending.

![Your Move reference](evidence/your-move.png)

Observed:

- The bottom dock expands into a tall translucent choice surface while transcript/header remain visible.
- Suggestions are dense radio rows with optional explanatory text.
- `Type something…` is a peer choice.
- Additional context is a separate editor.
- Confirm is pinned in a bottom action band.

Implementation mapping:

- Phase 1 Task 6.
- Phase 3 Task 10 submits through the real turn engine.

Acceptance:

- Sheet expands upward from the dock and preserves scene context.
- Exactly one suggested/custom choice can be active.
- Confirm remains disabled until a valid action exists.
- Custom action and additional context remain semantically separate.
- Keyboard avoidance keeps Confirm reachable and does not dismiss the sheet.

## Plan-to-Visual Coverage

| Visual invariant | Owner | Later integration that must not move it |
|---|---|---|
| Full-bleed layered scene canvas | Phase 1 Tasks 3–4 | Import assets, AI, voice |
| Minimal centered header | Phase 1 Task 4 | All phases |
| 72% left overlay drawer | Phase 1 Task 4 | Imported files/search |
| 88–90% right overlay drawer | Phase 1 Task 4 | Overview/assistant data |
| VN title/dialogue geometry | Phase 1 Task 5 | ElevenLabs Auto |
| Continuous transcript surface | Phase 1 Task 6 | Event store/AI turns |
| Pinned/expanded Your Move | Phase 1 Task 6 | Provider submission |
| Bottom generation card | Phase 1 Task 7 | Real/durable generation |
| Dynamic Island progress | Phase 1 Task 7 contract | Phase 5 service/APNs |

## Intentional Native Differences

These differences preserve behavior without copying Craft assets:

- SF Symbols or the closest system icon replace proprietary icon artwork.
- User-imported/generated scene and character art replace the supplied campaign art.
- SwiftUI materials, native keyboard, native text editor, accessibility focus, and platform haptics replace browser implementations.
- The internal app name and icon do not use Craft branding.
- Reduce Transparency may use opaque surfaces; Reduce Motion may replace drawer springs with a short fade/slide.

No other visual redesign is authorized by this audit.

## Accessibility Risks Requiring Runtime Evidence

These are open verification items, not screenshot-proven failures:

- Contrast of white/secondary text over arbitrary bright imported art.
- Dialogue card growth at accessibility text sizes.
- VoiceOver focus containment and restoration for both drawers.
- Keyboard reachability of Confirm and drawer search.
- Small-looking icon controls whose hit regions must still be 44×44 points.
- Reduced-transparency appearance and state differentiation without color.

## Audit Conclusion

The end-to-end plan matches the recorded Craft mobile hierarchy and includes explicit visual regression gates. The implementation must not proceed past Phase 1 acceptance until the nine canonical app captures are compared side-by-side with this evidence and every visible mismatch in crop, geometry, typography, material, and control placement is resolved.
