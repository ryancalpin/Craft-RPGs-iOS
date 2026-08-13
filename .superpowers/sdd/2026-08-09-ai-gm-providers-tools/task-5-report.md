# Task 5 report — Anthropic and Gemini adapters

## Scope

Implemented Task 5 on branch `codex/phase3-cloud-continuation`. Anthropic Messages SSE and Gemini `streamGenerateContent?alt=sse` are normalized into the existing provider-neutral `AIProvider`/`ProviderStreamEvent` contract. Wire DTOs remain in their respective adapter folders.

## RED evidence

- Added `AnthropicProviderContractTests.swift` and `GeminiProviderContractTests.swift` before adding the adapter implementations.
- Added sanitized fixtures for successful structured text, record patches, interleaved/allowlisted tools, unknown tools, refusal/safety, rate limit, malformed event, disconnect, usage, model discovery, and credential redaction.
- The required RED test execution was attempted but this host has no Swift or Xcode toolchain:
  - `swift --version` → `/bin/bash: swift: command not found`
  - `xcodebuild -version` → `/bin/bash: xcodebuild: command not found`
- Therefore no compiled RED failure can be claimed; exact compiler/test execution is deferred to a Swift/Xcode host.

## GREEN implementation

- `AnthropicProvider` handles named SSE lifecycle events, text deltas, `tool_use` content blocks, `input_json_delta`, usage, `end_turn`, `tool_use`, `max_tokens`, `stop_sequence`, and refusal/safety errors.
- `GeminiProvider` handles SSE JSON chunks, text parts, `functionCall` parts, `STOP`, `MAX_TOKENS`, safety/block reasons, malformed function calls, and usage metadata.
- Both adapters use `ProviderCredentialReader` only, inject credentials into provider-specific headers, use the bounded pull-based `StreamingHTTPClient`, and enforce `ProviderStreamContract` cancellation/terminal behavior.
- Unknown tool names are checked before any normalized tool-start event.
- Incremental text/tool-argument data is bounded at 1 MB; final `VersionedTurnEnvelope` decoding retains the 8 MB bound.
- Provider-specific record-patch field encoding is normalized through the shared helper without changing the upstream contract.
- Model discovery maps provider-native model records and falls back to adapter defaults for non-credential/non-cancellation failures.

## Cross-provider equivalence

`GeminiProviderContractTests.equivalentStructuredTextFixtureMatchesOtherAdapters` asserts identical normalized event sequences for equivalent successful structured-text/usage fixtures from Gemini, Anthropic, OpenAI, and OpenRouter. The assertion is present but could not execute without Swift/Xcode; fixture JSON parsing and `git diff --check` completed successfully on this host.

## Files changed

- `RPGPlayer/Infrastructure/Networking/Anthropic/AnthropicProvider.swift`
- `RPGPlayer/Infrastructure/Networking/Anthropic/AnthropicWireModels.swift`
- `RPGPlayer/Infrastructure/Networking/Gemini/GeminiProvider.swift`
- `RPGPlayer/Infrastructure/Networking/Gemini/GeminiWireModels.swift`
- `RPGPlayer/Infrastructure/Networking/ProviderAdapterSupport.swift`
- `RPGPlayerTests/AnthropicProviderContractTests.swift`
- `RPGPlayerTests/GeminiProviderContractTests.swift`
- `RPGPlayer/Fixtures/Providers/Anthropic/`
- `RPGPlayer/Fixtures/Providers/Gemini/`

## Privacy/security scan

- No real provider credentials are present in fixtures, production source, logs, diagnostics, SwiftData, or this report.
- Test-only synthetic sentinels exist solely to prove header/body redaction and are not stored in provider fixtures.
- Anthropic credentials use `x-api-key`; Gemini credentials use `x-goog-api-key`; both names are covered by `NetworkDiagnosticRedactor`.
- No logging or diagnostic output was added. No persistence or campaign-state mutation was added; safety errors surface as `ProviderError.safetyRefusal`.

## Host checks and deferred checks

Completed:

- Non-malformed Anthropic/Gemini fixture JSON parsing with Node.js.
- `git diff --check`.
- Static scans for credential-looking literals and logging calls in the new production adapter/helper files.

Deferred because Swift/Xcode are unavailable:

- Swift compilation and type checking.
- `RPGPlayerTests` contract test execution.
- iOS Simulator/device validation, real provider calls, and TestFlight acceptance.

No real-provider, Simulator, device, or TestFlight acceptance is claimed.

## Review fix round 3 report

### Findings addressed

- Anthropic now sends native `output_config.format` structured output with `type: "json_schema"`; Gemini now sends `generationConfig.responseMimeType: "application/json"` together with `responseJsonSchema`. Both schemas recursively describe the version 1 envelope, use `additionalProperties: false`, and keep `recordPatch.data.fields` as the established nullable scalar JSON string representation for arbitrary fields. Existing shared normalization and 1 MB tool / 8 MB envelope bounds remain unchanged.
- Added deterministic request-payload assertions that inspect the actual captured wire body, including the structured-output envelope, strict object closure, and scalar `fields` representation.
- Gemini complete function-call packets are normalized into the same starts, argument fragments, and completion ordering as the Anthropic, OpenAI, and OpenRouter interleaved fixtures. The four-adapter test now compares the complete normalized tool-event arrays, not only text fixtures. Unknown tools still reject before any normalized tool event.
- Added cloud-adapter coverage for discovery fallback on a non-credential service outage, preservation of invalid-credential errors, cancellation during discovery, and natural stream stop cleanup on successful and terminal-failure paths.

### RED evidence

The focused fix-round command was attempted after adding the new tests and before the production changes:

```text
xcodebuild test -scheme RPGPlayer -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:RPGPlayerTests/AnthropicProviderContractTests -only-testing:RPGPlayerTests/GeminiProviderContractTests
/bin/bash: line 1: xcodebuild: command not found
exit=127
```

Swift/Xcode are unavailable on this host, so a compiled runtime RED could not be observed. The Swift tests remain the deterministic proof to execute on the required host.

### Host-executable verification

Passed:

```text
git diff --check
exit=0

jq -e . RPGPlayer/Fixtures/Providers/Anthropic/models.json RPGPlayer/Fixtures/Providers/Gemini/models.json RPGPlayer/Fixtures/Providers/OpenAI/models.json RPGPlayer/Fixtures/Providers/OpenRouter/models.json
exit=0

non-malformed fixture JSON/SSE payload validation with Node.js
PASS

interleaved fixture semantic equivalence across Anthropic, Gemini, OpenAI, and OpenRouter with Node.js
PASS

provider bounds-presence scan, production logging scan, and non-fixture credential scan
PASS
```

### Wire-format references

- Anthropic Structured Outputs: https://platform.claude.com/docs/en/build-with-claude/structured-outputs
- Gemini Generate Content API: https://ai.google.dev/api/generate-content

### Deferred checks

These exact commands remain deferred because the host has no Swift/Xcode toolchain:

```text
swift --version
/bin/bash: line 1: swift: command not found
exit=127

xcodebuild -version
/bin/bash: line 1: xcodebuild: command not found
exit=127

xcodegen version
/bin/bash: line 1: xcodegen: command not found
exit=127

xcodebuild test -scheme RPGPlayer -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:RPGPlayerTests/AnthropicProviderContractTests -only-testing:RPGPlayerTests/GeminiProviderContractTests
/bin/bash: line 1: xcodebuild: command not found
exit=127

xcodebuild test -scheme RPGPlayer -destination 'platform=iOS Simulator,name=iPhone 16'
/bin/bash: line 1: xcodebuild: command not found
exit=127
```

No real provider calls, credentials, Simulator/device runs, or TestFlight acceptance were attempted or claimed. Safety/refusal mapping remains `ProviderError.safetyRefusal`, with no canonical mutation or credential logging.

## Review fix round 2 report

### Findings addressed

- Anthropic now uses a deliberate strict structured-output profile: `recordID`, scalar JSON-string `fields`, `pendingDecision`, and `usage` remain the only nullable unions. The remaining nil-capable leaf fields are strict optional properties. The captured payload assertion requires exactly 4 union parameters and 23 optional parameters, both below Anthropic's documented limits of 16 and 24, and recursively checks `additionalProperties: false` for every object schema.
- Anthropic still preserves `recordPatch.data.fields` as the bounded scalar JSON string representation and still validates completed text through local `VersionedTurnEnvelope.decode`, retaining the 8 MB envelope bound.
- Gemini now emits completed tool events in the recorded function-call packet order; it no longer sorts opaque call IDs. Added `nonlexical-tools.sse` fixtures for all four adapters with `call-zeta` streamed before lexically earlier `call-alpha`, plus a direct Gemini regression and four-adapter equivalence assertion.
- Unknown-tool rejection, 1 MB tool/frame bounds, cancellation/cleanup, credential privacy, and safety-refusal behavior were not weakened or changed.

### Host-executable verification

Passed:

```text
git diff --check
exit=0

jq -e . RPGPlayer/Fixtures/Providers/Anthropic/models.json RPGPlayer/Fixtures/Providers/Gemini/models.json RPGPlayer/Fixtures/Providers/OpenAI/models.json RPGPlayer/Fixtures/Providers/OpenRouter/models.json
exit=0

non-malformed provider SSE fixture data-line validation with Node.js
PASS

nonlexical four-adapter fixture packet/completion-order validation with Node.js
PASS: zeta then alpha across all four adapters; lexical order is alpha then zeta
```

### Deferred commands

Swift/Xcode are unavailable on this host. These exact commands were attempted and must be run on the Swift/Xcode host:

```text
swift --version
/bin/bash: line 1: swift: command not found
exit=127

xcodebuild -version
/bin/bash: line 1: xcodebuild: command not found
exit=127

xcodegen version
/bin/bash: line 1: xcodegen: command not found
exit=127

xcodebuild test -scheme RPGPlayer -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:RPGPlayerTests/AnthropicProviderContractTests -only-testing:RPGPlayerTests/GeminiProviderContractTests
/bin/bash: line 1: xcodebuild: command not found
exit=127

xcodebuild test -scheme RPGPlayer -destination 'platform=iOS Simulator,name=iPhone 16'
/bin/bash: line 1: xcodebuild: command not found
exit=127
```

No compiled Swift tests, real provider calls, Simulator/device runs, or TestFlight acceptance are claimed.

## Review fix round 3 continuation report

### Remaining Important finding addressed

- Anthropic proposal `data` is now an adapter-local bounded JSON-string scalar. The strict provider schema no longer exposes a superset object with optional event-specific fields, so a `rollRequest` cannot be provider-valid with missing `rollID`, `expression`, or `prompt` merely because those properties are omitted from a shared object schema.
- `ProviderAdapterSupport.normalizedAnthropicEnvelopeData` bounds and parses every proposal-data string, reconstructs each data object, decodes the established scalar `recordPatch.fields` representation back into its arbitrary JSON object, and then passes the reconstructed envelope to the unchanged `VersionedTurnEnvelope`/`ProposedCampaignEvent` decoder. Missing required variant fields remain a decoding failure; nothing is silently dropped.
- Added a test that normalizes and decodes all six `ProposedCampaignEvent` variants and verifies nested arbitrary record-patch fields. The same test feeds a roll request missing required data and asserts shared-decoder rejection.
- Existing Gemini ordering and the prior protections remain unchanged: unknown tools are rejected before tool events, tool/frame bounds remain 1 MB, final envelopes remain 8 MB, cancellation/cleanup and safety refusal behavior remain intact, credentials remain redacted, and the four-adapter equivalence tests were not weakened.

### Host-executable verification

Passed:

```text
git diff --check
exit=0

jq -e . RPGPlayer/Fixtures/Providers/Anthropic/models.json RPGPlayer/Fixtures/Providers/Gemini/models.json RPGPlayer/Fixtures/Providers/OpenAI/models.json RPGPlayer/Fixtures/Providers/OpenRouter/models.json
exit=0

non-malformed provider SSE fixture parsing plus Anthropic string-backed recordPatch normalization with Node.js
PASS: all non-malformed provider SSE fixtures parse; Anthropic string-backed recordPatch fields preserved
```

Deferred because Swift/Xcode are unavailable on this host:

```text
swift --version
/bin/bash: line 1: swift: command not found
exit=127

xcodebuild -version
/bin/bash: line 1: xcodebuild: command not found
exit=127

xcodegen version
/bin/bash: line 1: xcodegen: command not found
exit=127

xcodebuild test -scheme RPGPlayer -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:RPGPlayerTests/AnthropicProviderContractTests -only-testing:RPGPlayerTests/GeminiProviderContractTests
/bin/bash: line 1: xcodebuild: command not found
exit=127

xcodebuild test -scheme RPGPlayer -destination 'platform=iOS Simulator,name=iPhone 16'
/bin/bash: line 1: xcodebuild: command not found
exit=127
```

Concern: compiled Swift contract tests and iOS runtime validation remain deferred to a Swift/Xcode host; no real provider calls, Simulator/device runs, or TestFlight acceptance are claimed.
