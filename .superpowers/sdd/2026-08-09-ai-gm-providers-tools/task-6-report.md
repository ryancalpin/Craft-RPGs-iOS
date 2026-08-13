# Task 6 report: bounded deterministic turn context

## RED evidence

`RPGPlayerTests/TurnContextAssemblerTests.swift` was added before the
assembler implementation. It covers priority/order, budget truncation,
secret/local-URL/private-context/draft exclusions, approved-checkpoint-only
summary use, conservative budget math, randomized record order, and stable
context hashing.

The RED test command was attempted, but this worker host has no `xcodebuild`,
`xcodegen`, `swift`, or `swiftc`. Therefore the test could not execute and no
runtime failure is claimed.

## Implementation and GREEN evidence

- Added `ContextBudget.swift` with deterministic UTF-8-byte/3 token estimates,
  fixed framing overhead, complete model-output reservation, configurable tool
  reservation, and a safety margin.
- Added `TurnContextAssembler.swift` with a `Sendable` `TurnContextSource`,
  fixed priority selection, per-section bounds, recent transcript bounds,
  whole-item omission, omission reasons, and no canonical-history mutation.
- Added `ContextSection.swift` and moved the existing public
  `ContextHash`, `ContextSection`, `ContextSection.Item`, and `TurnContext`
  definitions there. `AIProvider.swift` now has no duplicate definitions and
  the public API is preserved.
- Stable SHA-256 hashes use sorted JSON encoding of selected sections, the
  final budget, and sorted omission metadata.
- `git diff --check` passed.
- A whitespace scan of every new/changed source and test file passed.
- The production context-source scan found no test secrets, provider-key
  literals, private-context markers, or local private paths.

The GREEN Xcode/unit-test result is deferred because the required Apple
toolchain is unavailable. The implementation must still be run through
`xcodegen generate` and the focused/full `xcodebuild` test lanes on a macOS
host before claiming runtime green.

## Public API decisions

`TurnContextSource` is the documented immutable `Sendable` input. It carries a
`NormalizedProject`, `CampaignProjection`, caller-provided safety/system
contract, stable referenced-record IDs, and an optional unapproved
`HandoffDraft` only so its exclusion can be reported. The draft is never
serialized or used as context. `TurnContextInput` is a compatibility typealias.

`TurnContextAssembly` returns the existing `TurnContext` plus `ContextBudget`
and `ContextAssemblyMetadata`. Metadata exposes omitted sections, omitted item
IDs/names, omission reasons, and whether budget/size truncation occurred.

## Deterministic ordering and hash details

The exact section priority is:

1. safety/system contract
2. player character
3. current scene
4. pending decision
5. recent transcript
6. referenced records
7. unresolved threads
8. broader world records

Dictionary-backed records, patches, inventory deltas, referenced IDs, record
fields, and omission metadata are sorted by stable IDs/names or canonical keys.
Imported records are merged with projection patches deterministically, with
persisted patches taking precedence. Recent actions and GM messages retain
their persisted projection event order; the recent suffix is selected in that
order, and canonical narration, dialogue, and beat block order is retained
inside each message. No dictionary iteration order participates in output.

The estimate is based on the sorted JSON encoding of each item, including its
`id`, `name`, `text`, and JSON framing, plus 8 provider-message item-framing
tokens and 4 section-framing tokens. This intentionally conservative heuristic
avoids provider-tokenizer drift. Input budget subtracts output, tool, and safety
reserves in clamped stages, with the tool reserve applied only to tool-capable
models.

The SHA-256 input is sorted canonical JSON containing selected sections, the
final budget including actual estimated usage, and sorted omission metadata.
Identical source/model/configuration therefore produces identical sections,
budget metadata, and hash, independent of randomized record dictionary/array
input order.

## Privacy scan

- Provider credentials and extension payloads are not context sources.
- Sensitive record fields and known provider-token-shaped values are omitted.
- `file://` values are omitted; imported assets and their local paths are never
  loaded into context.
- `additionalContext` on historical projected player actions is never copied;
  non-empty values are reported as private optional context exclusions.
- Only `approvedHandoffCheckpoint` fields may provide handoff summaries.
- Unapproved handoff drafts and payload keys containing `draft` are omitted and
  reported; canonical history is not rewritten or summarized.

## Deferred local checks

The following checks are intentionally deferred, not passed:

- `xcodegen generate` — `xcodegen` is absent on this host.
- Focused and full `xcodebuild` unit tests — `xcodebuild` is absent on this
  host, so no Swift compilation, XCTest/Swift Testing execution, simulator
  run, or iOS runtime check was possible.
- Any local macOS Simulator, device, archive, or UI verification.

## Fix round 1 evidence

Addressed all five reported findings:

- Recent player actions and GM messages retain projection event order through
  recent-suffix truncation. Canonical narration, dialogue, and beat block order
  remains unchanged inside each selected GM message. Regression coverage uses
  opaque UUIDs to prove selection follows event order rather than UUID sorting.
- Budget accounting now estimates the sorted JSON encoding of each
  `ContextSection.Item`, including `id`, `name`, `text`, JSON framing, and the
  existing provider-message item overhead. A large metadata regression proves
  the item is omitted when its metadata exceeds the remaining budget.
- Item IDs/names, record names, project titles, record types, field IDs, and
  omission metadata pass the same secret/local-file privacy filter as text.
  Unsafe metadata is omitted or replaced with `[redacted]` and never reaches
  serialized provider context.
- Draft detection now covers record fields, nested draft-bearing JSON values,
  field extension payloads, and projection patch fields. Omitted draft fields
  are reported with `discardedDraftExcluded`; canonical records and patches are
  not mutated.
- Context budget subtraction clamps public reserve inputs and subtracts in
  non-underflowing stages. Extreme `Int.max`/`Int.min` reserve coverage was
  added; selection accounting also avoids overflowing additions.

Host checks:

- `git diff --check` — passed.
- Changed-file trailing-whitespace scan — passed.
- `xcodegen generate` — deferred: `/bin/bash: line 1: xcodegen: command not found`.
- Focused test command
  `xcodebuild -scheme RPGPlayer -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:RPGPlayerTests/TurnContextAssemblerTests`
  — deferred: `/bin/bash: line 1: xcodebuild: command not found`.
- Full test command
  `xcodebuild -scheme RPGPlayer -destination 'platform=iOS Simulator,name=iPhone 16' test`
  — deferred: `/bin/bash: line 1: xcodebuild: command not found`.

No Swift compilation, XCTest/Swift Testing execution, simulator run, or iOS
runtime verification was possible on this host.

## Fix round 3 evidence

- Omission metadata normalizes each complete identifier/value before applying
  secret, draft, private, credential, and local-file checks. Punctuated forms
  such as `API Key`, `api-key`, and `x-api-key` therefore use `[redacted]`.
- Candidate IDs and names in both budget and per-section item-limit omissions
  pass the same omission sanitizer as other omission paths.
- Record item IDs and names use the safe metadata filter. Only approved
  `identity`, `name`, `title`, and `label` fields can supply a record name;
  records without an approved safe name leave `Item.name` nil rather than
  falling back to an ID.
- Regression coverage exercises punctuated omission metadata, unsafe record
  IDs/names, no-safe-name records, and budget/item-limit omission metadata.
- Focused and full Swift/Xcode verification remain deferred on this host;
  `xcodebuild` is unavailable, so no compiled-test result is claimed.

## Fix round 4 evidence

- Recursive JSON privacy checks now inspect object keys as well as values for
  provider-token-shaped secrets and local file URLs. The key checks recurse
  through arrays and nested objects, while the existing sensitive field-key
  and discarded-draft filtering remains in place.
- Added record-field and projection-patch regressions covering nested local
  file URL keys and token-shaped keys with benign values. The tests assert the
  unsafe keys and benign nested values are omitted from serialized context,
  while safe sibling fields remain and the expected omission reasons are
  recorded.
- The pre-fix focused `xcodebuild` attempt could not execute because
  `xcodebuild` is unavailable on this host. Static inspection of the old
  traversal confirms it checked object values (and only sensitive key names),
  so these new key-shaped fixtures would have reached `jsonText`; no runtime
  RED result is claimed.
- `git diff --check`, changed-file whitespace scanning, and production-source
  privacy/static scans passed. The test-only scan reports only the intentional
  sentinel fixtures and their negative assertions.
- Focused and full Swift/Xcode verification remain deferred on this host;
  no Swift compilation, XCTest/Swift Testing execution, simulator run, or
  iOS runtime result is claimed.

## Fix round 5 evidence

- Approved checkpoint unresolved-thread IDs are now `approved-thread-<index>`
  after the existing deterministic lexical sort; approved-inventory IDs are
  now `approved-inventory-<index>` after the existing sorted dictionary
  entries are enumerated. Neither ID contains checkpoint text or an inventory
  name, and the obsolete `stableSlug` helper was removed.
- Added a regression covering token-shaped and local-file-shaped thread and
  inventory checkpoint content. It checks serialized context, the context
  hash, serialized omission metadata, and the complete serialized assembly for
  the raw token/path markers, and requires all four unsafe checkpoint
  omissions to use the fixed index-only IDs. The previous slug/raw-name
  implementation fails this proof because the slug preserves the token body
  and the omission IDs are not the required index-only IDs.
- `git diff --check` passed. Static scans confirm no `stableSlug` references
  remain and no approved-thread/approved-inventory ID interpolates thread or
  inventory content.
- The focused regression and full Swift/Xcode lanes remain deferred because
  `xcodebuild`, `xcodegen`, `swift`, and `swiftc` are unavailable on this
  host. No Swift compilation or test execution is claimed.
