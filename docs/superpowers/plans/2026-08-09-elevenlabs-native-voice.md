# ElevenLabs Native Voice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add user-owned ElevenLabs voices for narrator, GM, and characters, with discovery, assignment, streaming playback, pronunciation dictionaries, caching, interruption, and Visual Novel Auto behavior.

**Architecture:** Voice configuration is campaign-scoped metadata while credentials remain device-scoped Keychain items. A provider-neutral `SpeechService` generates `VoiceAudioStream` values. A main-actor playback coordinator owns AVAudioSession and queued segments. Cache keys include every synthesis-affecting input. Apple speech is the fallback adapter.

**Tech Stack:** Swift 6, AVFoundation/AVSpeechSynthesizer, URLSession WebSocket and bytes APIs, CryptoKit, Keychain, XCTest, XCUITest

## Global Constraints

- Execute after Phase 3 contracts are stable.
- Never embed, log, or persist the ElevenLabs key outside Keychain.
- Manual assignments always win over suggestions.
- Auto advances only after successful playback or an explicit skip.
- A pending roll, player choice, error, phone call, or route interruption halts Auto.
- The visual player remains recording-faithful; voice adds behavior to existing speaker/audio controls.

## Task 1: Define Speech, Voice, and Assignment Contracts

**Files:**

- Create: `RPGPlayer/Domain/Voice/VoiceDescriptor.swift`
- Create: `RPGPlayer/Domain/Voice/VoiceAssignment.swift`
- Create: `RPGPlayer/Domain/Voice/VoiceSegment.swift`
- Create: `RPGPlayer/Domain/Voice/VoiceAudioStream.swift`
- Create: `RPGPlayer/Domain/Voice/SpeechService.swift`
- Create: `RPGPlayer/Domain/Voice/VoicePlaybackEvent.swift`
- Test: `RPGPlayer/RPGPlayerTests/VoiceContractTests.swift`

- [ ] Model narrator, GM, character, and unassigned speaker targets.
- [ ] Separate manual assignment, accepted suggestion, and transient suggestion sources.
- [ ] Include provider voice ID, display name, language, preview URL metadata, and capability flags.
- [ ] Define playback events for preparing, buffering, playing, paused, completed, interrupted, skipped, and failed.
- [ ] Encode assignment events without credentials or expiring preview URLs.
- [ ] Run tests and commit `feat: define native voice contracts`.

## Task 2: Add ElevenLabs Credential and Voice Discovery

**Files:**

- Create: `RPGPlayer/Infrastructure/Networking/ElevenLabs/ElevenLabsClient.swift`
- Create: `RPGPlayer/Infrastructure/Networking/ElevenLabs/ElevenLabsWireModels.swift`
- Create: `RPGPlayer/Features/Voice/ElevenLabsSettingsView.swift`
- Test: `RPGPlayer/RPGPlayerTests/ElevenLabsClientTests.swift`
- Test: `RPGPlayer/RPGPlayerUITests/ElevenLabsSettingsTests.swift`

- [ ] Reuse the Keychain credential boundary from Phase 3 under a separate service identifier.
- [ ] Validate the key with the smallest authenticated endpoint and map unauthorized/quota/connectivity errors.
- [ ] Fetch and paginate the user's available voices through bounded JSON responses.
- [ ] Cache non-sensitive voice metadata for 24 hours and offer explicit refresh.
- [ ] Add search, language/category filters, preview, and selected state in a native sheet.
- [ ] Verify the sentinel key is absent from logs, store, UserDefaults, screenshots, and exported recovery bundles.
- [ ] Run tests and commit `feat: add elevenlabs key and voice discovery`.

## Task 3: Build Campaign Voice Assignment

**Files:**

- Create: `RPGPlayer/Features/Voice/VoiceAssignmentView.swift`
- Create: `RPGPlayer/Features/Voice/VoicePickerSheet.swift`
- Create: `RPGPlayer/Domain/Voice/VoiceSuggestionEngine.swift`
- Test: `RPGPlayer/RPGPlayerTests/VoiceSuggestionTests.swift`
- Test: `RPGPlayer/RPGPlayerUITests/VoiceAssignmentTests.swift`

- [ ] List narrator, GM, player, and discovered NPCs with current assignment and preview control.
- [ ] Suggest based only on user-visible character traits, declared age band, language, and desired tone; do not infer protected traits.
- [ ] Require user confirmation to accept a suggestion.
- [ ] Append `voiceAssignmentChanged` on manual/accepted assignment and preserve it through replay/export.
- [ ] Verify a later suggestion never replaces a manual mapping.
- [ ] Run tests and commit `feat: add per-campaign voice assignment`.

## Task 4: Implement Streaming ElevenLabs Synthesis

**Files:**

- Create: `RPGPlayer/Infrastructure/Networking/ElevenLabs/ElevenLabsSpeechService.swift`
- Create: `RPGPlayer/Infrastructure/Networking/ElevenLabs/ElevenLabsWebSocketSession.swift`
- Create: `RPGPlayer/Infrastructure/Audio/AudioChunkDecoder.swift`
- Test: `RPGPlayer/RPGPlayerTests/ElevenLabsSpeechServiceTests.swift`
- Fixtures: `RPGPlayer/Fixtures/Voice/ElevenLabs/`

- [ ] Use input streaming for incremental GM text and HTTP streaming for complete short beats when measured latency is lower.
- [ ] Send text in sentence-aware chunks; never split grapheme clusters or SSML/pronunciation tokens.
- [ ] Initialize pronunciation dictionaries and synthesis settings before text.
- [ ] Bound inbound messages and decoded audio buffers; apply backpressure when playback falls behind.
- [ ] Cancel network work immediately on Stop, speaker change, campaign exit, or superseding turn.
- [ ] Normalize transport errors into retryable synthesis failures without failing the completed story turn.
- [ ] Run tests and commit `feat: stream elevenlabs synthesis safely`.

## Task 5: Implement Audio Cache and Pronunciation Dictionaries

**Files:**

- Create: `RPGPlayer/Infrastructure/Audio/VoiceAudioCache.swift`
- Create: `RPGPlayer/Domain/Voice/PronunciationDictionary.swift`
- Create: `RPGPlayer/Features/Voice/PronunciationEditorView.swift`
- Test: `RPGPlayer/RPGPlayerTests/VoiceAudioCacheTests.swift`
- Test: `RPGPlayer/RPGPlayerTests/PronunciationDictionaryTests.swift`

- [ ] Hash normalized text, voice ID, model, output format, settings, and dictionary version for cache identity.
- [ ] Store audio under a validated campaign/cache UUID path with size and last-access metadata.
- [ ] Implement a 500 MB default LRU limit, per-campaign clear, and automatic invalidation when synthesis inputs change.
- [ ] Validate pronunciation entries, cap dictionary size, and preview changed words before save.
- [ ] Never include the API key or raw provider response in cache metadata.
- [ ] Test corruption fallback and concurrent reads/writes.
- [ ] Run tests and commit `feat: cache narration and edit pronunciations`.

## Task 6: Build Playback and Audio-Session Coordination

**Files:**

- Create: `RPGPlayer/Infrastructure/Audio/VoicePlaybackCoordinator.swift`
- Create: `RPGPlayer/Infrastructure/Audio/AudioSessionCoordinator.swift`
- Test: `RPGPlayer/RPGPlayerTests/VoicePlaybackCoordinatorTests.swift`

- [ ] Queue segments by story order and speaker; expose only actor-isolated state to SwiftUI.
- [ ] Configure spoken-audio playback with user-controlled silent-mode behavior and external route support.
- [ ] Handle interruption begin/end, route changes, headphones disconnect, Control Center pause, and media-services reset.
- [ ] Resume only when system policy and user intent permit; never auto-resume after explicit user pause.
- [ ] Keep at most a measured bounded number of decoded buffers in memory.
- [ ] Run tests and commit `feat: coordinate narration playback and interruptions`.

## Task 7: Add Apple Speech Fallback

**Files:**

- Create: `RPGPlayer/Infrastructure/Audio/AppleSpeechService.swift`
- Create: `RPGPlayer/Domain/Voice/SpeechServiceRouter.swift`
- Test: `RPGPlayer/RPGPlayerTests/SpeechServiceRouterTests.swift`

- [ ] Use Apple speech when no ElevenLabs key/assignment exists, the user selects offline voice, or ElevenLabs fails and fallback is enabled.
- [ ] Preserve speaker ordering and playback event semantics across adapters.
- [ ] Surface a subtle non-blocking fallback label in settings/history, not in the main dialogue card.
- [ ] Test offline, quota, invalid key, and mid-segment fallback policy.
- [ ] Run tests and commit `feat: add apple speech narration fallback`.

## Task 8: Connect Voice to Visual Novel Auto and Transcript

**Files:**

- Modify: `RPGPlayer/Features/Player/VisualNovelView.swift`
- Modify: `RPGPlayer/Features/Player/TranscriptView.swift`
- Modify: `RPGPlayer/Features/Player/PlayerSessionModel.swift`
- Create: `RPGPlayer/Features/Voice/InlineNarrationControl.swift`
- Test: `RPGPlayer/RPGPlayerUITests/VisualNovelAutoVoiceTests.swift`

- [ ] Keep the recorded control row: previous, beat count, speaker control, inline Auto toggle, close.
- [ ] Start the current beat's assigned voice from the speaker control.
- [ ] In Auto, advance only after the current segment emits completed.
- [ ] Halt Auto at final beat, roll request, player decision, error, app interruption, or manual previous/close.
- [ ] Transcript speaker controls replay only their own block and do not alter beat position.
- [ ] Verify VoiceOver announces speaker, playback state, and Auto state without duplicating dialogue text.
- [ ] Capture VN title, VN dialogue, and VN Auto states and compare to evidence.
- [ ] Run tests and commit `feat: connect native voices to player presentation`.

## Task 9: Validate Background Audio Boundaries

**Files:**

- Modify: `RPGPlayer/App/RPGPlayer.entitlements`
- Create: `RPGPlayer/RPGPlayerTests/BackgroundAudioPolicyTests.swift`
- Test: `RPGPlayer/RPGPlayerUITests/AudioInterruptionUITests.swift`

- [ ] Enable the audio background mode only for user-initiated narration playback.
- [ ] Do not use silent audio to keep generation alive.
- [ ] Stop or pause according to user settings when narration finishes or the app loses playback intent.
- [ ] Verify screen lock, app switch, phone interruption, AirPods route change, and Control Center commands on a real device.
- [ ] Document that durable text generation is Phase 5, separate from background audio.
- [ ] Commit `test: validate background narration behavior`.

## Phase 4 Completion Gate

- [ ] A user can validate a custom ElevenLabs key and browse their voices.
- [ ] Narrator, GM, and NPC manual assignments persist through replay/export.
- [ ] Streaming audio begins before a long beat finishes generating.
- [ ] Cache, fallback, cancellation, and interruption behavior is deterministic.
- [ ] Visual Novel Auto never skips a roll, choice, error, or unfinished segment.
- [ ] Voice additions do not change the recording-faithful visual hierarchy.
- [ ] The credential leakage test suite passes.
