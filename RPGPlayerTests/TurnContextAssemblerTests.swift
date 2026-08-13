import Foundation
import Testing
@testable import RPGPlayer

struct TurnContextAssemblerTests {
    @Test
    func assemblesSectionsInPriorityOrderAndSortsRecordsIndependentlyOfSourceOrder() throws {
        let project = makeProject(
            records: [
                record(id: "record-zebra", name: "Zebra"),
                record(id: "record-hero", name: "Mara Venn"),
                record(id: "record-scene", name: "The Quay"),
                record(id: "record-ash", name: "Ash"),
                record(id: "record-brine", name: "Brine")
            ]
        )
        let projection = CampaignProjection(
            campaignID: try uuid("22222222-2222-4222-8222-222222222222"),
            pendingDecision: "What do you do?",
            records: ["record-zebra": ["present": .bool(true)]],
            currentScene: SceneChangedPayload(
                sceneID: "record-scene",
                title: "The Quay",
                summary: "Rain gathers on the stones."
            ),
            submittedActions: [
                ProjectedPlayerAction(
                    requestID: try uuid("11111111-1111-4111-8111-111111111111"),
                    action: "Follow the lantern."
                )
            ],
            gmMessages: [
                GMMessageCommittedPayload(
                    messageID: try uuid("33333333-3333-4333-8333-333333333333"),
                    narration: ["The bell answers."],
                    dialogue: [],
                    beats: [],
                    finalQuestion: "What do you do?"
                )
            ]
        )
        let source = TurnContextSource(
            project: project,
            projection: projection,
            safetySystemContract: "Keep the game safe and grounded.",
            referencedRecordIDs: ["record-zebra"]
        )
        let model = try model(context: 20_000, output: 1_000)

        let assembly = TurnContextAssembler().assemble(
            source: source,
            model: model
        )

        #expect(
            assembly.context.sections.map(\.kind)
                == [
                    .systemContract,
                    .playerCharacter,
                    .currentScene,
                    .pendingDecision,
                    .recentTranscript,
                    .referencedRecords,
                    .worldRecords
                ]
        )
        let world = try #require(
            assembly.context.sections.first { $0.kind == .worldRecords }
        )
        #expect(
            world.items.compactMap { item in
                item.id?.hasPrefix("record-") == true ? item.id : nil
            } == ["record-ash", "record-brine"]
        )
        #expect(
            assembly.context.contextHash.rawValue.count == 64
        )
    }

    @Test
    func omitsLowerPriorityContentWhenConservativeInputBudgetIsExhausted() throws {
        let project = makeProject(
            records: [
                record(
                    id: "record-world",
                    name: "World",
                    description: String(repeating: "world ", count: 200)
                )
            ]
        )
        let source = TurnContextSource(
            project: project,
            projection: CampaignProjection(
                campaignID: try uuid("22222222-2222-4222-8222-222222222222"),
                pendingDecision: "Choose."
            ),
            safetySystemContract: "Safety contract."
        )
        let model = try model(context: 180, output: 100)

        let assembly = TurnContextAssembler(
            toolTokenReserve: 20,
            safetyMarginTokens: 10
        ).assemble(source: source, model: model)

        #expect(assembly.budget.inputTokenBudget == 50)
        #expect(assembly.metadata.wasTruncated)
        #expect(assembly.metadata.omittedSections.contains(.worldRecords))
        #expect(
            assembly.metadata.omittedItems.contains {
                $0.kind == .worldRecords && $0.reason == .budgetExceeded
            }
        )
        #expect(
            assembly.context.sections.flatMap(\.items).allSatisfy {
                $0.text.contains("world ") == false
            }
        )
    }

    @Test
    func excludesSecretsLocalFileURLsPrivateOptionalContextAndUnapprovedDrafts() throws {
        let unsafeRecord = NormalizedRecord(
            id: "record-unsafe",
            fileTypeID: "lore",
            folderID: nil,
            fields: [
                NormalizedField(
                    id: "description",
                    value: .string("A safe clue."),
                    extensionPayload: [:]
                ),
                NormalizedField(
                    id: "apiKey",
                    value: .string("sk-test-secret-value"),
                    extensionPayload: [:]
                ),
                NormalizedField(
                    id: "asset",
                    value: .string("file:///Users/private/secret.txt"),
                    extensionPayload: [:]
                )
            ],
            extensionPayload: [
                "discardedDraft": .string("never include this")
            ]
        )
        let discardedDraft = HandoffDraft(
            originalHandoffSHA256: String(repeating: "a", count: 64),
            summary: "Unapproved draft summary"
        )
        let checkpoint = try HandoffDraft(
            originalHandoffSHA256: String(repeating: "c", count: 64),
            summary: "Approved checkpoint summary"
        ).approvedCheckpoint(
            confirmingUserApproval: true
        )
        let project = makeProject(records: [unsafeRecord])
        let projection = CampaignProjection(
            campaignID: try uuid("22222222-2222-4222-8222-222222222222"),
            approvedHandoffCheckpoint: checkpoint,
            submittedActions: [
                ProjectedPlayerAction(
                    requestID: try uuid("11111111-1111-4111-8111-111111111111"),
                    action: "Inspect the clue.",
                    additionalContext: "PRIVATE_CONTEXT_MARKER"
                )
            ]
        )
        let source = TurnContextSource(
            project: project,
            projection: projection,
            safetySystemContract: "Safety contract.",
            discardedHandoffDraft: discardedDraft
        )

        let assembly = TurnContextAssembler().assemble(
            source: source,
            model: try model(context: 20_000, output: 1_000)
        )
        let encoded = try JSONEncoder().encode(assembly.context.sections)
        let text = String(decoding: encoded, as: UTF8.self)

        #expect(text.contains("sk-test-secret-value") == false)
        #expect(text.contains("file:///Users/private/secret.txt") == false)
        #expect(text.contains("PRIVATE_CONTEXT_MARKER") == false)
        #expect(text.contains("Unapproved draft summary") == false)
        #expect(text.contains("A safe clue."))
        #expect(
            assembly.metadata.omittedItems.contains {
                $0.reason == .secretExcluded
            }
        )
        #expect(
            assembly.metadata.omittedItems.contains {
                $0.reason == .localFileURLExcluded
            }
        )
        #expect(
            assembly.metadata.omittedItems.contains {
                $0.reason == .privateOptionalContextExcluded
            }
        )
        #expect(
            assembly.metadata.omittedItems.contains {
                $0.reason == .discardedDraftExcluded
            }
        )
    }

    @Test
    func usesOnlyApprovedCheckpointAsAHandOffSummarySource() throws {
        let draft = HandoffDraft(
            originalHandoffSHA256: String(repeating: "b", count: 64),
            summary: "Approved checkpoint summary",
            currentScene: "Checkpoint scene",
            playerCharacter: "Checkpoint hero",
            unresolvedThreads: ["Find the missing bell"]
        )
        let checkpoint = try draft.approvedCheckpoint(
            confirmingUserApproval: true
        )
        let projection = CampaignProjection(
            campaignID: try uuid("22222222-2222-4222-8222-222222222222"),
            approvedHandoffCheckpoint: checkpoint
        )
        let source = TurnContextSource(
            project: makeProject(records: []),
            projection: projection,
            safetySystemContract: "Safety contract."
        )

        let assembly = TurnContextAssembler().assemble(
            source: source,
            model: try model(context: 20_000, output: 1_000)
        )
        let text = String(
            decoding: try JSONEncoder().encode(assembly.context.sections),
            as: UTF8.self
        )

        #expect(text.contains("Approved checkpoint summary"))
        #expect(text.contains("Checkpoint scene"))
        #expect(text.contains("Checkpoint hero"))
        #expect(text.contains("Find the missing bell"))
    }

    @Test
    func doesNotEmbedUnsafeApprovedCheckpointContentInCandidateIDsOrMetadata()
        throws
    {
        let token = "AIzaabcdefghijklmnop123456"
        let tokenBody = "abcdefghijklmnop123456"
        let threadLocalPath = "checkpoint-thread.txt"
        let threadLocalURL = "file:///Users/private/\(threadLocalPath)"
        let inventoryLocalPath = "checkpoint-inventory.txt"
        let inventoryLocalURL = "file:///Users/private/\(inventoryLocalPath)"
        let inventoryToken = "AIzainventoryabcdefghijklmnop123456"
        let inventoryTokenBody = "inventoryabcdefghijklmnop123456"
        let draft = HandoffDraft(
            originalHandoffSHA256: String(repeating: "d", count: 64),
            summary: "Approved checkpoint summary",
            unresolvedThreads: [
                token,
                threadLocalURL
            ],
            inventoryDeltas: [
                inventoryToken: 1,
                inventoryLocalURL: 2
            ]
        )
        let checkpoint = try draft.approvedCheckpoint(
            confirmingUserApproval: true
        )
        let assembly = TurnContextAssembler().assemble(
            source: TurnContextSource(
                project: makeProject(records: [], projectExtensionPayload: [:]),
                projection: CampaignProjection(
                    campaignID: try uuid("22222222-2222-4222-8222-222222222222"),
                    approvedHandoffCheckpoint: checkpoint
                ),
                safetySystemContract: "Safety contract."
            ),
            model: try model(context: 20_000, output: 1_000)
        )
        let serializedContext = String(
            decoding: try JSONEncoder().encode(assembly.context),
            as: UTF8.self
        )
        let serializedHash = assembly.context.contextHash.rawValue
        let serializedMetadata = String(
            decoding: try JSONEncoder().encode(assembly.metadata),
            as: UTF8.self
        )
        let serializedAssembly = String(
            decoding: try JSONEncoder().encode(assembly),
            as: UTF8.self
        )
        let forbiddenSubstrings = [
            token,
            tokenBody,
            threadLocalURL,
            threadLocalPath,
            inventoryToken,
            inventoryTokenBody,
            inventoryLocalURL,
            inventoryLocalPath
        ]

        for substring in forbiddenSubstrings {
            #expect(serializedContext.contains(substring) == false)
            #expect(serializedHash.contains(substring) == false)
            #expect(serializedMetadata.contains(substring) == false)
            #expect(serializedAssembly.contains(substring) == false)
        }

        let unsafeCheckpointOmissions = assembly.metadata.omittedItems.filter {
            $0.kind == .unresolvedThreads
                && ($0.reason == .secretExcluded
                    || $0.reason == .localFileURLExcluded)
        }
        #expect(unsafeCheckpointOmissions.count == 4)
        #expect(
            Set(unsafeCheckpointOmissions.compactMap(\.itemID)) == Set([
                "approved-thread-0",
                "approved-thread-1",
                "approved-inventory-0",
                "approved-inventory-1"
            ])
        )
    }

    @Test
    func computesBudgetAndHashWithStableCanonicalMetadata() throws {
        let first = TurnContextSource(
            project: makeProject(
                records: [
                    record(id: "record-b", name: "B"),
                    record(id: "record-a", name: "A")
                ]
            ),
            projection: CampaignProjection(
                campaignID: try uuid("22222222-2222-4222-8222-222222222222")
            ),
            safetySystemContract: "Safety contract."
        )
        let second = TurnContextSource(
            project: makeProject(
                records: [
                    record(id: "record-a", name: "A"),
                    record(id: "record-b", name: "B")
                ]
            ),
            projection: first.projection,
            safetySystemContract: first.safetySystemContract
        )
        let model = try model(context: 1_000, output: 200)

        let firstAssembly = TurnContextAssembler(
            toolTokenReserve: 100,
            safetyMarginTokens: 25
        ).assemble(source: first, model: model)
        let secondAssembly = TurnContextAssembler(
            toolTokenReserve: 100,
            safetyMarginTokens: 25
        ).assemble(source: second, model: model)

        #expect(firstAssembly.budget.inputTokenBudget == 675)
        #expect(ContextBudget.estimateTokens(for: "abc") == 1)
        #expect(ContextBudget.estimateTokens(for: "abcd") == 2)
        #expect(firstAssembly.context == secondAssembly.context)
        #expect(
            firstAssembly.context.contextHash
                == secondAssembly.context.contextHash
        )
    }

    @Test
    func recencySelectionPreservesProjectionOrderWithOpaqueUUIDs() throws {
        let oldAction = ProjectedPlayerAction(
            requestID: try uuid("ffffffff-ffff-4fff-8fff-ffffffffffff"),
            action: "Old action"
        )
        let middleAction = ProjectedPlayerAction(
            requestID: try uuid("eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"),
            action: "Middle action"
        )
        let newestAction = ProjectedPlayerAction(
            requestID: try uuid("00000000-0000-4000-8000-000000000000"),
            action: "Newest action"
        )
        let oldMessage = GMMessageCommittedPayload(
            messageID: try uuid("ffffffff-ffff-4fff-8fff-ffffffffffff"),
            narration: ["Old message"],
            dialogue: [],
            beats: [],
            finalQuestion: ""
        )
        let middleMessage = GMMessageCommittedPayload(
            messageID: try uuid("eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"),
            narration: ["Middle message"],
            dialogue: [],
            beats: [],
            finalQuestion: ""
        )
        let newestMessage = GMMessageCommittedPayload(
            messageID: try uuid("00000000-0000-4000-8000-000000000000"),
            narration: ["Newest message"],
            dialogue: [
                CampaignDialogueBlock(
                    id: try uuid("ffffffff-ffff-4fff-8fff-ffffffffffff"),
                    speaker: "Old speaker",
                    text: "Old dialogue"
                ),
                CampaignDialogueBlock(
                    id: try uuid("00000000-0000-4000-8000-000000000000"),
                    speaker: "New speaker",
                    text: "Newest dialogue"
                )
            ],
            beats: [
                CampaignStoryBeat(
                    id: try uuid("ffffffff-ffff-4fff-8fff-ffffffffffff"),
                    kind: .narration,
                    text: "Old beat"
                ),
                CampaignStoryBeat(
                    id: try uuid("00000000-0000-4000-8000-000000000000"),
                    kind: .narration,
                    text: "Newest beat"
                )
            ],
            finalQuestion: ""
        )
        let source = TurnContextSource(
            project: makeProject(records: []),
            projection: CampaignProjection(
                campaignID: try uuid("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"),
                submittedActions: [oldAction, middleAction, newestAction],
                gmMessages: [oldMessage, middleMessage, newestMessage]
            ),
            safetySystemContract: "Safety contract."
        )

        let assembly = TurnContextAssembler(recentTranscriptItemLimit: 2)
            .assemble(
                source: source,
                model: try model(context: 20_000, output: 1_000)
            )
        let transcript = try #require(
            assembly.context.sections.first { $0.kind == .recentTranscript }
        )

        #expect(transcript.items.map(\.text) == [
            "Middle action",
            "Newest action",
            "Middle message",
            "Newest message\nOld speaker: Old dialogue\nNew speaker: Newest dialogue\nOld beat\nNewest beat"
        ])
        #expect(transcript.items.contains { $0.text == "Old action" } == false)
        #expect(transcript.items.contains { $0.text == "Old message" } == false)
    }

    @Test
    func budgetCountsSerializedItemMetadataAndCanOmitLargeNamedItems() throws {
        let item = ContextSection.Item(
            id: String(repeating: "i", count: 300),
            name: String(repeating: "n", count: 300),
            text: "x"
        )
        #expect(
            ContextBudget.estimateTokens(for: item)
                > ContextBudget.estimateTokens(for: item.text)
                    + ContextBudget.itemOverheadTokens
        )

        let project = makeProject(
            records: [],
            title: String(repeating: "campaign-name-", count: 80),
            summary: "A short campaign summary."
        )
        let assembly = TurnContextAssembler(
            toolTokenReserve: 0,
            safetyMarginTokens: 0
        ).assemble(
            source: TurnContextSource(
                project: project,
                projection: CampaignProjection(
                    campaignID: try uuid("22222222-2222-4222-8222-222222222222")
                ),
                safetySystemContract: "Safety contract."
            ),
            model: try model(context: 180, output: 100, supportsTools: false)
        )
        let encoded = String(
            decoding: try JSONEncoder().encode(assembly.context.sections),
            as: UTF8.self
        )

        #expect(encoded.contains("campaign-name-") == false)
        #expect(assembly.metadata.omittedItems.contains {
            $0.kind == .worldRecords && $0.reason == .budgetExceeded
        })
        #expect(assembly.budget.estimatedInputTokens <= assembly.budget.inputTokenBudget)
    }

    @Test
    func filtersUnsafeRecordNamesAndProjectTitlesFromItemMetadata() throws {
        let unsafeRecord = record(
            id: "record-safe-id",
            name: "sk-record-secret-value"
        )
        let project = makeProject(
            records: [unsafeRecord],
            title: "file:///Users/private/campaign-title.txt"
        )
        let assembly = TurnContextAssembler().assemble(
            source: TurnContextSource(
                project: project,
                projection: CampaignProjection(
                    campaignID: try uuid("22222222-2222-4222-8222-222222222222")
                ),
                safetySystemContract: "Safety contract."
            ),
            model: try model(context: 20_000, output: 1_000)
        )
        let encoded = String(
            decoding: try JSONEncoder().encode(assembly.context.sections),
            as: UTF8.self
        )

        #expect(encoded.contains("sk-record-secret-value") == false)
        #expect(encoded.contains("file:///Users/private/campaign-title.txt") == false)
        #expect(assembly.context.sections.flatMap(\.items).allSatisfy { item in
            item.name?.contains("sk-record-secret-value") != true
                && item.name?.contains("file://") != true
        })
    }

    @Test
    func usesOnlyApprovedRecordNameKeys() throws {
        let recordWithLabel = NormalizedRecord(
            id: "record-label",
            fileTypeID: "lore",
            folderID: nil,
            fields: [
                NormalizedField(
                    id: "description",
                    value: .string("Description is not an identity."),
                    extensionPayload: [:]
                ),
                NormalizedField(
                    id: "label",
                    value: .string("Approved label"),
                    extensionPayload: [:]
                )
            ],
            extensionPayload: [:]
        )
        let assembly = TurnContextAssembler().assemble(
            source: TurnContextSource(
                project: makeProject(records: [recordWithLabel]),
                projection: CampaignProjection(
                    campaignID: try uuid("22222222-2222-4222-8222-222222222222")
                ),
                safetySystemContract: "Safety contract."
            ),
            model: try model(context: 20_000, output: 1_000)
        )
        let item = try #require(
            assembly.context.sections
                .first(where: { $0.kind == .worldRecords })?.items.first(where: {
                    $0.id == "record-label"
                })
        )

        #expect(item.name == "Approved label")
    }

    @Test
    func doesNotUseSecretOrDraftOnlyFieldsAsRecordNamesOrOmissionMetadata() throws {
        let recordWithNoSafeName = NormalizedRecord(
            id: "draft-record",
            fileTypeID: "lore",
            folderID: nil,
            fields: [
                NormalizedField(
                    id: "description",
                    value: .string("Visible record description."),
                    extensionPayload: [:]
                ),
                NormalizedField(
                    id: "apiKey",
                    value: .string("sk-record-secret"),
                    extensionPayload: [:]
                ),
                NormalizedField(
                    id: "password",
                    value: .string("record-password"),
                    extensionPayload: [:]
                ),
                NormalizedField(
                    id: "draftName",
                    value: .string("Draft-only name"),
                    extensionPayload: [:]
                ),
                NormalizedField(
                    id: "privateNote",
                    value: .string("Private-only note"),
                    extensionPayload: [:]
                ),
                NormalizedField(
                    id: "API Key",
                    value: .string("punctuated-secret-1"),
                    extensionPayload: [:]
                ),
                NormalizedField(
                    id: "api-key",
                    value: .string("punctuated-secret-2"),
                    extensionPayload: [:]
                ),
                NormalizedField(
                    id: "x-api-key",
                    value: .string("punctuated-secret-3"),
                    extensionPayload: [:]
                )
            ],
            extensionPayload: [:]
        )
        let assembly = TurnContextAssembler().assemble(
            source: TurnContextSource(
                project: makeProject(records: [recordWithNoSafeName]),
                projection: CampaignProjection(
                    campaignID: try uuid("22222222-2222-4222-8222-222222222222"),
                    records: [
                        "draft-record": [
                            "privatePatch": .string("Private patch"),
                            "secretPatch": .string("Secret patch")
                        ]
                    ]
                ),
                safetySystemContract: "Safety contract."
            ),
            model: try model(context: 20_000, output: 1_000)
        )
        let encoded = String(
            decoding: try JSONEncoder().encode(assembly),
            as: UTF8.self
        )
        let item = try #require(
            assembly.context.sections
                .first(where: { $0.kind == .worldRecords })?.items.first(where: {
                    $0.text.contains("Visible record description.")
                })
        )

        #expect(item.id == nil)
        #expect(item.name == nil)
        #expect(encoded.contains("sk-record-secret") == false)
        #expect(encoded.contains("record-password") == false)
        #expect(encoded.contains("Draft-only name") == false)
        #expect(encoded.contains("Private-only note") == false)
        #expect(encoded.contains("apiKey") == false)
        #expect(encoded.contains("password") == false)
        #expect(encoded.contains("draftName") == false)
        #expect(encoded.contains("privateNote") == false)
        #expect(encoded.contains("punctuated-secret-1") == false)
        #expect(encoded.contains("punctuated-secret-2") == false)
        #expect(encoded.contains("punctuated-secret-3") == false)
        #expect(encoded.contains("API Key") == false)
        #expect(encoded.contains("api-key") == false)
        #expect(encoded.contains("x-api-key") == false)
        #expect(encoded.contains("Private patch") == false)
        #expect(encoded.contains("Secret patch") == false)
        #expect(encoded.contains("privatePatch") == false)
        #expect(encoded.contains("secretPatch") == false)
    }

    @Test
    func normalizesWholePunctuatedValuesBeforeSanitizingOmissionMetadata() throws {
        let project = makeProject(
            records: [],
            projectExtensionPayload: [
                "API Key": .object(["draftValue": .string("secret-1")]),
                "api-key": .object(["draftValue": .string("secret-2")]),
                "x-api-key": .object(["draftValue": .string("secret-3")])
            ]
        )
        let assembly = TurnContextAssembler().assemble(
            source: TurnContextSource(
                project: project,
                projection: CampaignProjection(
                    campaignID: try uuid("22222222-2222-4222-8222-222222222222")
                ),
                safetySystemContract: "Safety contract."
            ),
            model: try model(context: 20_000, output: 1_000)
        )
        let punctuatedKeys = Set(["API Key", "api-key", "x-api-key"])
        let punctuatedOmissions = assembly.metadata.omittedItems.filter {
            punctuatedKeys.contains($0.itemName ?? "")
                || ($0.itemID ?? "").contains("API Key")
                || ($0.itemID ?? "").contains("api-key")
                || ($0.itemID ?? "").contains("x-api-key")
        }

        #expect(punctuatedOmissions.isEmpty)
        #expect(
            assembly.metadata.omittedItems.filter {
                $0.reason == .discardedDraftExcluded
                    && $0.itemID == "[redacted]"
                    && $0.itemName == "[redacted]"
            }.count == 3
        )
    }

    @Test
    func sanitizesUnsafeMetadataInBudgetAndItemLimitOmissions() throws {
        let project = makeProject(
            records: [
                record(
                    id: "draft-record-a",
                    name: "API Key",
                    description: "A small unsafe metadata candidate."
                ),
                record(
                    id: "draft-record-b",
                    name: "api-key",
                    description: String(repeating: "Z large unsafe text ", count: 200)
                )
            ]
        )
        let source = TurnContextSource(
            project: project,
            projection: CampaignProjection(
                campaignID: try uuid("22222222-2222-4222-8222-222222222222")
            ),
            safetySystemContract: "Safety contract."
        )

        let itemLimitAssembly = TurnContextAssembler(
            maximumItemsPerSection: 1
        ).assemble(
            source: source,
            model: try model(context: 20_000, output: 1_000)
        )
        let itemLimitOmission = try #require(
            itemLimitAssembly.metadata.omittedItems.first {
                $0.kind == .worldRecords
                    && $0.reason == .itemLimitExceeded
                    && $0.itemID == nil
                    && $0.itemName == nil
            }
        )
        #expect(itemLimitOmission.itemID == nil)
        #expect(itemLimitOmission.itemName == nil)
        #expect(
            itemLimitAssembly.metadata.omittedItems.contains {
                $0.itemID == "draft-record-a"
                    || $0.itemID == "draft-record-b"
                    || $0.itemName == "API Key"
                    || $0.itemName == "api-key"
            } == false
        )

        let budgetAssembly = TurnContextAssembler(
            toolTokenReserve: 0,
            safetyMarginTokens: 0
        ).assemble(
            source: source,
            model: try model(context: 180, output: 100, supportsTools: false)
        )
        let budgetOmission = try #require(
            budgetAssembly.metadata.omittedItems.first {
                $0.kind == .worldRecords
                    && $0.reason == .budgetExceeded
                    && $0.itemID == nil
                    && $0.itemName == nil
            }
        )
        #expect(budgetOmission.itemID == nil)
        #expect(budgetOmission.itemName == nil)
        #expect(
            budgetAssembly.metadata.omittedItems.contains {
                $0.itemID == "draft-record-a"
                    || $0.itemID == "draft-record-b"
                    || $0.itemName == "API Key"
                    || $0.itemName == "api-key"
            } == false
        )
    }

    @Test
    func filtersDraftFieldsAndPatchValuesAcrossRecordSources() throws {
        let draftRecord = NormalizedRecord(
            id: "record-drafts",
            fileTypeID: "lore",
            folderID: nil,
            fields: [
                NormalizedField(
                    id: "name",
                    value: .string("Draft Test Record"),
                    extensionPayload: [:]
                ),
                NormalizedField(
                    id: "draftSummary",
                    value: .string("never emit record draft"),
                    extensionPayload: [:]
                ),
                NormalizedField(
                    id: "notes",
                    value: .object(["draft": .string("never emit nested draft")]),
                    extensionPayload: [:]
                )
            ],
            extensionPayload: [:]
        )
        let projection = CampaignProjection(
            campaignID: try uuid("22222222-2222-4222-8222-222222222222"),
            records: [
                "record-drafts": [
                    "draftDecision": .string("never emit patch draft"),
                    "visibleFact": .string("emit this fact")
                ]
            ]
        )
        let assembly = TurnContextAssembler().assemble(
            source: TurnContextSource(
                project: makeProject(records: [draftRecord]),
                projection: projection,
                safetySystemContract: "Safety contract."
            ),
            model: try model(context: 20_000, output: 1_000)
        )
        let encoded = String(
            decoding: try JSONEncoder().encode(assembly.context.sections),
            as: UTF8.self
        )

        #expect(encoded.contains("never emit record draft") == false)
        #expect(encoded.contains("never emit nested draft") == false)
        #expect(encoded.contains("never emit patch draft") == false)
        #expect(encoded.contains("emit this fact"))
        #expect(assembly.metadata.omittedItems.contains {
            $0.itemID == "[redacted]"
                && $0.itemName == "[redacted]"
                && $0.reason == .discardedDraftExcluded
        })
        #expect(assembly.metadata.omittedItems.contains {
            $0.itemID == "[redacted]"
                && $0.itemName == "[redacted]"
                && $0.reason == .discardedDraftExcluded
        })
    }

    @Test
    func omitsNestedUnsafeObjectKeysFromRecordJSONValues() throws {
        let record = NormalizedRecord(
            id: "record-nested-keys",
            fileTypeID: "lore",
            folderID: nil,
            fields: [
                NormalizedField(
                    id: "name",
                    value: .string("Nested key record"),
                    extensionPayload: [:]
                ),
                NormalizedField(
                    id: "description",
                    value: .string("Visible record description."),
                    extensionPayload: [:]
                ),
                NormalizedField(
                    id: "nestedLocalPayload",
                    value: .array([
                        .object([
                            "nested": .object([
                                "file:///Users/private/record.txt": .string(
                                    "benign local-key value"
                                )
                            ])
                        ])
                    ]),
                    extensionPayload: [:]
                ),
                NormalizedField(
                    id: "nestedTokenPayload",
                    value: .array([
                        .object([
                            "nestedAgain": .array([
                                .object([
                                    "sk-abcdefgh123456": .string(
                                        "benign token-key value"
                                    )
                                ])
                            ])
                        ])
                    ]),
                    extensionPayload: [:]
                )
            ],
            extensionPayload: [:]
        )
        let assembly = TurnContextAssembler().assemble(
            source: TurnContextSource(
                project: makeProject(records: [record]),
                projection: CampaignProjection(
                    campaignID: try uuid("22222222-2222-4222-8222-222222222222")
                ),
                safetySystemContract: "Safety contract."
            ),
            model: try model(context: 20_000, output: 1_000)
        )
        let encoded = String(
            decoding: try JSONEncoder().encode(assembly.context.sections),
            as: UTF8.self
        )

        #expect(encoded.contains("file:///Users/private/record.txt") == false)
        #expect(encoded.contains("sk-abcdefgh123456") == false)
        #expect(encoded.contains("benign local-key value") == false)
        #expect(encoded.contains("benign token-key value") == false)
        #expect(encoded.contains("Visible record description."))
        #expect(assembly.metadata.omittedItems.contains {
            $0.itemID == "record-nested-keys.nestedLocalPayload"
                && $0.reason == .localFileURLExcluded
        })
        #expect(assembly.metadata.omittedItems.contains {
            $0.itemID == "record-nested-keys.nestedTokenPayload"
                && $0.reason == .secretExcluded
        })
    }

    @Test
    func omitsNestedUnsafeObjectKeysFromProjectionJSONValues() throws {
        let assembly = TurnContextAssembler().assemble(
            source: TurnContextSource(
                project: makeProject(records: []),
                projection: CampaignProjection(
                    campaignID: try uuid("22222222-2222-4222-8222-222222222222"),
                    records: [
                        "record-projection-nested-keys": [
                            "nestedTokenPatch": .array([
                                .object([
                                    "wrapper": .object([
                                        "sk-zyxwvuts987654": .string(
                                            "benign projection-token value"
                                        )
                                    ])
                                ])
                            ]),
                            "nestedLocalPatch": .array([
                                .object([
                                    "wrapperAgain": .array([
                                        .object([
                                            "file:///Users/private/projection.txt": .string(
                                                "benign projection-file value"
                                            )
                                        ])
                                    ])
                                ])
                            ]),
                            "visiblePatch": .string("Visible projection patch")
                        ]
                    ]
                ),
                safetySystemContract: "Safety contract."
            ),
            model: try model(context: 20_000, output: 1_000)
        )
        let encoded = String(
            decoding: try JSONEncoder().encode(assembly.context.sections),
            as: UTF8.self
        )

        #expect(encoded.contains("sk-zyxwvuts987654") == false)
        #expect(encoded.contains("file:///Users/private/projection.txt") == false)
        #expect(encoded.contains("benign projection-token value") == false)
        #expect(encoded.contains("benign projection-file value") == false)
        #expect(encoded.contains("Visible projection patch"))
        #expect(assembly.metadata.omittedItems.contains {
            $0.itemID == "record-projection-nested-keys.nestedTokenPatch"
                && $0.reason == .secretExcluded
        })
        #expect(assembly.metadata.omittedItems.contains {
            $0.itemID == "record-projection-nested-keys.nestedLocalPatch"
                && $0.reason == .localFileURLExcluded
        })
    }

    @Test
    func clampsExtremePublicBudgetReservesWithoutArithmeticOverflow() throws {
        let model = try model(context: 100, output: 40)
        let hugeReserves = ContextBudget(
            model: model,
            toolTokenReserve: Int.max,
            safetyMarginTokens: Int.max
        )
        let negativeReserves = ContextBudget(
            model: model,
            toolTokenReserve: Int.min,
            safetyMarginTokens: Int.min
        )

        #expect(hugeReserves.inputTokenBudget == 0)
        #expect(negativeReserves.reservedToolTokens == 0)
        #expect(negativeReserves.safetyMarginTokens == 0)
        #expect(negativeReserves.inputTokenBudget == 60)
    }

    private func model(
        context: Int,
        output: Int,
        supportsTools: Bool = true
    ) throws -> ProviderModel {
        try ProviderModel(
            providerID: .openAI,
            id: "test-model",
            displayName: "Test Model",
            contextWindowTokens: context,
            maximumOutputTokens: output,
            supportsTools: supportsTools,
            supportsStructuredOutput: true
        )
    }

    private func makeProject(
        records: [NormalizedRecord],
        title: String = "Test Campaign",
        summary: String? = "A test campaign.",
        projectExtensionPayload: [String: JSONValue] = [
            "apiKey": .string("sk-project-secret")
        ]
    ) -> NormalizedProject {
        NormalizedProject(
            cdfVersion: 2,
            importScope: .projectWorldContent,
            id: "project-test",
            title: title,
            summary: summary,
            system: "D20 Fantasy",
            rootFolderID: "folder-root",
            currentSceneRecordID: "record-scene",
            playerCharacterRecordID: "record-hero",
            projectExtensionPayload: projectExtensionPayload,
            schemas: [],
            content: NormalizedContent(
                folders: [],
                records: records,
                relationships: [],
                assets: [
                    NormalizedAsset(
                        id: "asset-local",
                        relativePath: "file:///Users/private/asset.txt",
                        mediaType: "text/plain",
                        extensionPayload: [:]
                    )
                ],
                maps: [],
                characters: [],
                extensionPayload: [
                    "draft": .string("discarded draft")
                ]
            ),
            manifest: NormalizedManifest(files: [], recordIDs: records.map(\.id)),
            extensionPayload: [:]
        )
    }

    private func record(
        id: String,
        name: String,
        description: String = "A record description."
    ) -> NormalizedRecord {
        NormalizedRecord(
            id: id,
            fileTypeID: "lore",
            folderID: nil,
            fields: [
                NormalizedField(
                    id: "name",
                    value: .string(name),
                    extensionPayload: [:]
                ),
                NormalizedField(
                    id: "description",
                    value: .string(description),
                    extensionPayload: [:]
                )
            ],
            extensionPayload: [:]
        )
    }

    private func uuid(_ value: String) throws -> UUID {
        try #require(UUID(uuidString: value))
    }
}
