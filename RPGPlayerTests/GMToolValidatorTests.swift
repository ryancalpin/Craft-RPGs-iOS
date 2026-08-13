import Foundation
import Testing
@testable import RPGPlayer

struct GMToolValidatorTests {
    @Test
    func nativeClockToolSchemaUsesIntegerProperties() throws {
        let definition = try #require(
            ProviderNativeToolCatalog.definitions.first { $0.name == "updateClock" }
        )

        #expect(definition.properties["current"]?.type == "integer")
        #expect(definition.properties["maximum"]?.type == "integer")
        #expect(definition.properties["clockRecordID"]?.type == "string")
    }

    @Test
    func registryContainsOnlyTheEightAppOwnedTools() {
        #expect(
            Set(GMToolRegistry.all.names)
                == [
                    "readRecord",
                    "searchRecords",
                    "patchRecord",
                    "requestRoll",
                    "updateScene",
                    "updateClock",
                    "suggestVoice",
                    "attachAsset"
                ]
        )
        #expect(Set(GMToolRegistry.all.names) == ProviderNativeToolCatalog.names)
    }

    @Test
    func requestRollReturnsAProposalWithoutCallingAStore() throws {
        let campaignID = try uuid("22222222-2222-4222-8222-222222222222")
        let context = ToolTestFixture.context(campaignID: campaignID)
        let arguments = try ProviderToolArguments(values: [
            "expression": .string("1d20+3"),
            "prompt": .string("Slip past the sentry")
        ])

        let proposal = try ToolValidator().validate(
            toolName: "requestRoll",
            arguments: arguments,
            context: context,
            rollID: try uuid("33333333-3333-4333-8333-333333333333")
        )

        #expect(proposal.status == "Roll requested.")
        #expect(
            proposal.event
                == .rollRequest(
                    rollID: try uuid("33333333-3333-4333-8333-333333333333"),
                    expression: "1d20+3",
                    prompt: "Slip past the sentry"
                )
        )
    }

    @Test
    func requestRollRequiresAnExplicitRollIDAndIsDeterministicForSameInputs() throws {
        let context = ToolTestFixture.context(
            campaignID: try uuid("22222222-2222-4222-8222-222222222222")
        )
        let arguments = try ProviderToolArguments(values: [
            "expression": .string("1d20+3"),
            "prompt": .string("Slip past the sentry")
        ])
        let validator = ToolValidator()

        #expect(throws: ToolValidationError.missingRollID) {
            try validator.validate(
                toolName: "requestRoll",
                arguments: arguments,
                context: context
            )
        }

        let rollID = try uuid("33333333-3333-4333-8333-333333333333")
        let first = try validator.validate(
            toolName: "requestRoll",
            arguments: arguments,
            context: context,
            rollID: rollID
        )
        let second = try validator.validate(
            toolName: "requestRoll",
            arguments: arguments,
            context: context,
            rollID: rollID
        )
        #expect(first == second)
    }

    @Test(arguments: [
        "readRecord", "searchRecords", "patchRecord", "requestRoll",
        "updateScene", "updateClock", "suggestVoice", "attachAsset"
    ])
    func eachAllowlistedToolHasAValidationPath(_ toolName: String) throws {
        let campaignID = try uuid("22222222-2222-4222-8222-222222222222")
        let context = ToolTestFixture.context(campaignID: campaignID)
        let arguments = try ToolTestFixture.arguments(for: toolName)

        let proposal = try ToolValidator().validate(
            toolName: toolName,
            arguments: arguments,
            context: context,
            rollID: try uuid("33333333-3333-4333-8333-333333333333")
        )

        #expect(proposal.status.contains("proposed") || proposal.status.contains("read") || proposal.status.contains("searched") || proposal.status.contains("requested"))
        #expect(proposal.status.contains("http") == false)
    }

    @Test
    func rejectsUnknownMissingWrongTypeAndCrossCampaignArguments() throws {
        let campaignID = try uuid("22222222-2222-4222-8222-222222222222")
        let context = ToolTestFixture.context(campaignID: campaignID)
        let validator = ToolValidator()

        #expect(throws: ToolValidationError.unknownTool) {
            try validator.validate(
                toolName: "runShell",
                arguments: try ProviderToolArguments(values: [:]),
                context: context
            )
        }
        #expect(throws: ToolValidationError.missingArgument) {
            try validator.validate(
                toolName: "readRecord",
                arguments: try ProviderToolArguments(values: [:]),
                context: context
            )
        }
        #expect(throws: ToolValidationError.wrongArgumentType) {
            try validator.validate(
                toolName: "readRecord",
                arguments: try ProviderToolArguments(values: ["recordID": .integer(1)]),
                context: context
            )
        }
        #expect(throws: ToolValidationError.campaignOwnershipMismatch) {
            try validator.validate(
                toolName: "readRecord",
                arguments: try ProviderToolArguments(values: ["recordID": .string("scene-quay")]),
                context: ToolTestFixture.context(
                    campaignID: campaignID,
                    projectionCampaignID: try uuid("44444444-4444-4444-8444-444444444444")
                )
            )
        }

        let validGenerated = try ToolValidator().validate(
            toolName: "attachAsset",
            arguments: try ProviderToolArguments(values: [
                "assetID": .string("generated-map"),
                "targetRecordID": .string("scene-quay"),
                "fieldID": .string("mapAsset")
            ]),
            context: ToolTestFixture.context(
                campaignID: campaignID,
                assetReferences: [
                    GMToolAssetReference(
                        assetID: "generated-map",
                        sha256: String(repeating: "b", count: 64),
                        campaignID: campaignID,
                        origin: "generated",
                        path: "generated/map.png"
                    )
                ]
            )
        )
        #expect(validGenerated.event != nil)

        #expect(throws: ToolValidationError.invalidAssetReference) {
            try ToolValidator().validate(
                toolName: "attachAsset",
                arguments: try ProviderToolArguments(values: [
                    "assetID": .string("generated-map"),
                    "targetRecordID": .string("scene-quay"),
                    "fieldID": .string("mapAsset")
                ]),
                context: ToolTestFixture.context(
                    campaignID: campaignID,
                    assetReferences: [
                        GMToolAssetReference(
                            assetID: "generated-map",
                            sha256: String(repeating: "b", count: 64),
                            campaignID: campaignID,
                            origin: nil,
                            path: "generated/map.png"
                        )
                    ]
                )
            )
        }
    }

    @Test
    func identifierArgumentsRejectWrongJSONTypesAsWrongArgumentType() throws {
        let campaignID = try uuid("22222222-2222-4222-8222-222222222222")
        let context = ToolTestFixture.context(campaignID: campaignID)
        let validator = ToolValidator()

        #expect(throws: ToolValidationError.wrongArgumentType) {
            try validator.validate(
                toolName: "patchRecord",
                arguments: try ProviderToolArguments(values: [
                    "recordID": .integer(1),
                    "fieldsJSON": .string("{\"name\":\"Mara\"}")
                ]),
                context: context
            )
        }
        #expect(throws: ToolValidationError.wrongArgumentType) {
            try validator.validate(
                toolName: "updateScene",
                arguments: try ProviderToolArguments(values: [
                    "sceneRecordID": .bool(true),
                    "title": .string("The Quay"),
                    "summary": .null
                ]),
                context: context
            )
        }
        #expect(throws: ToolValidationError.wrongArgumentType) {
            try validator.validate(
                toolName: "updateClock",
                arguments: try ProviderToolArguments(values: [
                    "clockRecordID": .array([]),
                    "current": .integer(2),
                    "maximum": .integer(6)
                ]),
                context: context
            )
        }
        #expect(throws: ToolValidationError.wrongArgumentType) {
            try validator.validate(
                toolName: "suggestVoice",
                arguments: try ProviderToolArguments(values: [
                    "characterRecordID": .null,
                    "styleDescription": .string("Warm and cautious")
                ]),
                context: context
            )
        }
        #expect(throws: ToolValidationError.wrongArgumentType) {
            try validator.validate(
                toolName: "attachAsset",
                arguments: try ProviderToolArguments(values: [
                    "assetID": .integer(1),
                    "targetRecordID": .string("scene-quay"),
                    "fieldID": .string("mapAsset")
                ]),
                context: context
            )
        }
        #expect(throws: ToolValidationError.wrongArgumentType) {
            try validator.validate(
                toolName: "attachAsset",
                arguments: try ProviderToolArguments(values: [
                    "assetID": .string("asset-map"),
                    "targetRecordID": .bool(false),
                    "fieldID": .string("mapAsset")
                ]),
                context: context
            )
        }
        #expect(throws: ToolValidationError.wrongArgumentType) {
            try validator.validate(
                toolName: "attachAsset",
                arguments: try ProviderToolArguments(values: [
                    "assetID": .string("asset-map"),
                    "targetRecordID": .string("scene-quay"),
                    "fieldID": .array([])
                ]),
                context: context
            )
        }
    }

    @Test
    func validatesPatchSchemasTypesRelationshipsAndUnsafeFields() throws {
        let campaignID = try uuid("22222222-2222-4222-8222-222222222222")
        let context = ToolTestFixture.context(campaignID: campaignID)
        let validator = ToolValidator()

        let valid = try validator.validate(
            toolName: "patchRecord",
            arguments: try ProviderToolArguments(values: [
                "recordID": .string("character-guide"),
                "fieldsJSON": .string("{\"name\":\"Mara\",\"allyID\":\"scene-quay\"}")
            ]),
            context: context
        )
        #expect(valid.event == .recordPatch(recordID: "character-guide", fields: [
            "name": .string("Mara"),
            "allyID": .string("scene-quay")
        ]))

        let badType = try ProviderToolArguments(values: [
            "recordID": .string("character-guide"),
            "fieldsJSON": .string("{\"name\":true}")
        ])
        #expect(throws: ToolValidationError.invalidFieldValue) {
            try validator.validate(toolName: "patchRecord", arguments: badType, context: context)
        }

        let badRelationship = try ProviderToolArguments(values: [
            "recordID": .string("character-guide"),
            "fieldsJSON": .string("{\"allyID\":\"not-in-project\"}")
        ])
        #expect(throws: ToolValidationError.invalidRelationshipTarget) {
            try validator.validate(toolName: "patchRecord", arguments: badRelationship, context: context)
        }

        let secret = try ProviderToolArguments(values: [
            "recordID": .string("character-guide"),
            "fieldsJSON": .string("{\"apiKey\":\"do-not-store\"}")
        ])
        #expect(throws: ToolValidationError.unsafeArgument) {
            try validator.validate(toolName: "patchRecord", arguments: secret, context: context)
        }

        let unsafeNestedKey = try ProviderToolArguments(values: [
            "recordID": .string("character-guide"),
            "fieldsJSON": .string("{\"details\":{\"http:example\":\"hidden\"}}")
        ])
        #expect(throws: ToolValidationError.unsafeArgument) {
            try validator.validate(
                toolName: "patchRecord",
                arguments: unsafeNestedKey,
                context: context
            )
        }
    }

    @Test
    func recursivelyRejectsProviderTokensNormalizedSecretKeysAndDraftValues() throws {
        let context = ToolTestFixture.context(
            campaignID: try uuid("22222222-2222-4222-8222-222222222222")
        )
        let validator = ToolValidator()

        for value in ["sk-123456789", "AIza123456789"] {
            #expect(throws: ToolValidationError.unsafeArgument) {
                try validator.validate(
                    toolName: "patchRecord",
                    arguments: try ProviderToolArguments(values: [
                        "recordID": .string("character-guide"),
                        "fieldsJSON": .string("{\"name\":\"\(value)\"}")
                    ]),
                    context: context
                )
            }
        }

        for value in ["s e c r e t value", "pa.ss-word value", "author iz ation value"] {
            #expect(throws: ToolValidationError.unsafeArgument) {
                try validator.validate(
                    toolName: "patchRecord",
                    arguments: try ProviderToolArguments(values: [
                        "recordID": .string("character-guide"),
                        "fieldsJSON": .string("{\"name\":\"\(value)\"}")
                    ]),
                    context: context
                )
            }
        }

        for key in ["API Key", "api.key", "api key", "x-api-key"] {
            #expect(throws: ToolValidationError.unsafeArgument) {
                try validator.validate(
                    toolName: "patchRecord",
                    arguments: try ProviderToolArguments(values: [
                        "recordID": .string("character-guide"),
                        "fieldsJSON": .string("{\"\(key)\":\"hidden\"}")
                    ]),
                    context: context
                )
            }
        }

        #expect(throws: ToolValidationError.unsafeArgument) {
            try validator.validate(
                toolName: "patchRecord",
                arguments: try ProviderToolArguments(values: [
                    "recordID": .string("character-guide"),
                    "fieldsJSON": .string("{\"name\":\"discarded draft\"}")
                ]),
                context: context
            )
        }
    }

    @Test
    func sanitizesReadValuesAndOmitsUnsafeNestedData() throws {
        let campaignID = try uuid("22222222-2222-4222-8222-222222222222")
        let context = ToolTestFixture.context(
            campaignID: campaignID,
            projectionRecords: [
                "character-guide": [
                    "safe": .string("sk-123456789"),
                    "draftNote": .string("private draft"),
                    "details": .object([
                        "visible": .string("Guide"),
                        "secret.value": .string("hidden"),
                        "http:example": .string("hidden"),
                        "windows\\path": .string("hidden"),
                        "url": .string("https://example.com/private")
                    ])
                ]
            ]
        )

        let proposal = try ToolValidator().validate(
            toolName: "readRecord",
            arguments: try ProviderToolArguments(values: ["recordID": .string("character-guide")]),
            context: context
        )
        guard case .recordRead(let result) = proposal.result else {
            Issue.record("Expected a record read result")
            return
        }
        #expect(result.fields["safe"] == nil)
        #expect(result.fields["draftNote"] == nil)
        #expect(result.fields["details"] == .object(["visible": .string("Guide")]))
    }

    @Test
    func searchOmitsRecordsContainingUnsafeImportedData() throws {
        let context = ToolTestFixture.context(
            campaignID: try uuid("22222222-2222-4222-8222-222222222222"),
            characterName: "sk-123456789 Guide"
        )
        let proposal = try ToolValidator().validate(
            toolName: "searchRecords",
            arguments: try ProviderToolArguments(values: ["query": .string("sk")]),
            context: context
        )
        guard case .recordsFound(let matches) = proposal.result else {
            Issue.record("Expected search results")
            return
        }
        #expect(matches.isEmpty)
    }

    @Test
    func searchFailsClosedForUndeclaredInvalidAndEnumMismatchedProjectionFields() throws {
        let campaignID = try uuid("22222222-2222-4222-8222-222222222222")
        let validator = ToolValidator()

        let projectionVariants: [[String: JSONValue]] = [
            ["name": .string("Guide"), "undeclared": .string("Guide")],
            ["name": .integer(7)],
            ["name": .string("Guide"), "mood": .string("angry")]
        ]
        for projectionFields in projectionVariants {
            let proposal = try validator.validate(
                toolName: "searchRecords",
                arguments: try ProviderToolArguments(values: ["query": .string("guide")]),
                context: ToolTestFixture.context(
                    campaignID: campaignID,
                    projectionRecords: ["character-guide": projectionFields]
                )
            )
            guard case .recordsFound(let matches) = proposal.result else {
                Issue.record("Expected search results")
                continue
            }
            #expect(matches.isEmpty)
        }
    }

    @Test
    func searchNormalizationIsDeterministicAcrossRepeatedCalls() throws {
        let campaignID = try uuid("22222222-2222-4222-8222-222222222222")
        let context = ToolTestFixture.context(
            campaignID: campaignID,
            characterName: "İstanbul Guide"
        )
        let arguments = try ProviderToolArguments(values: [
            "query": .string("İSTANBUL")
        ])
        let validator = ToolValidator()
        let first = try validator.validate(
            toolName: "searchRecords",
            arguments: arguments,
            context: context
        )

        for _ in 0..<32 {
            #expect(try validator.validate(
                toolName: "searchRecords",
                arguments: arguments,
                context: context
            ) == first)
        }
    }

    @Test
    func rejectsUnsafeAssetURLAndCrossCampaignReference() throws {
        let campaignID = try uuid("22222222-2222-4222-8222-222222222222")
        let validator = ToolValidator()
        let arguments = try ToolTestFixture.arguments(for: "attachAsset")

        for url in [
            URL(string: "file:///private/map.png")!,
            URL(string: "../outside/map.png")!,
            URL(string: "https://example.com/map.png")!,
            URL(string: "assets/other.png")!,
            URL(string: "assets/run.sh")!,
            URL(string: "assets/map;touch.png")!
        ] {
            #expect(throws: ToolValidationError.invalidAssetReference) {
                try validator.validate(
                    toolName: "attachAsset",
                    arguments: arguments,
                    context: ToolTestFixture.context(campaignID: campaignID, assetURL: url)
                )
            }
        }

        let otherCampaign = try uuid("44444444-4444-4444-8444-444444444444")
        #expect(throws: ToolValidationError.campaignOwnershipMismatch) {
            try validator.validate(
                toolName: "attachAsset",
                arguments: try ProviderToolArguments(values: [
                    "assetID": .string("generated-map"),
                    "targetRecordID": .string("scene-quay"),
                    "fieldID": .string("mapAsset")
                ]),
                context: ToolTestFixture.context(
                    campaignID: campaignID,
                    assetReferences: [
                        GMToolAssetReference(
                            assetID: "generated-map",
                            sha256: String(repeating: "b", count: 64),
                            campaignID: otherCampaign,
                            origin: "generated",
                            path: "generated/map.png"
                        )
                    ]
                )
            )
        }
    }

    @Test
    func acceptsPersistedImportedAssetPathAndRejectsMalformedCampaignOrProjectPaths() throws {
        let campaignID = try uuid("ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF")
        let validator = ToolValidator()
        let arguments = try ToolTestFixture.arguments(for: "attachAsset")

        let valid = try validator.validate(
            toolName: "attachAsset",
            arguments: arguments,
            context: ToolTestFixture.context(campaignID: campaignID)
        )
        #expect(valid.event == .assetAttachment(
            assetID: "asset-map",
            targetRecordID: "scene-quay",
            fieldID: "mapAsset"
        ))

        let invalidURLs = [
            "Campaigns/ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF/assets/map.png",
            "Campaigns/abcdefab-cdef-4abc-8def-abcdefabcdee/assets/map.png",
            "Campaigns/not-a-uuid/assets/map.png",
            "Campaigns/abcdefab-cdef-4abc-8def-abcdefabcdef/../assets/map.png",
            "Campaigns/abcdefab-cdef-4abc-8def-abcdefabcdef/assets/%6dap.png",
            "Campaigns/abcdefab-cdef-4abc-8def-abcdefabcdef/assets/other.png",
            "file:///private/map.png",
            "https://example.com/map.png",
            "/Campaigns/abcdefab-cdef-4abc-8def-abcdefabcdef/assets/map.png"
        ]

        for value in invalidURLs {
            #expect(throws: ToolValidationError.invalidAssetReference) {
                try validator.validate(
                    toolName: "attachAsset",
                    arguments: arguments,
                    context: ToolTestFixture.context(
                        campaignID: campaignID,
                        assetURL: URL(string: value)!
                    )
                )
            }
        }
    }

    @Test
    func rejectsMissingRelationshipDeclarationsAndAcceptsDeclaredEdgesOnly() throws {
        let campaignID = try uuid("22222222-2222-4222-8222-222222222222")
        let arguments = try ProviderToolArguments(values: [
            "recordID": .string("character-guide"),
            "fieldsJSON": .string("{\"allyID\":\"scene-quay\"}")
        ])

        #expect(throws: ToolValidationError.invalidRelationshipTarget) {
            try ToolValidator().validate(
                toolName: "patchRecord",
                arguments: arguments,
                context: ToolTestFixture.context(campaignID: campaignID, relationships: [])
            )
        }
        let declared = try ToolValidator().validate(
            toolName: "patchRecord",
            arguments: arguments,
            context: ToolTestFixture.context(campaignID: campaignID)
        )
        #expect(declared.event != nil)
    }

    @Test
    func readOutputOmitsURLWithTokenSpacedSecretsAndOversizedValues() throws {
        let context = ToolTestFixture.context(
            campaignID: try uuid("22222222-2222-4222-8222-222222222222"),
            projectionRecords: [
                "character-guide": [
                    "link": .string("https://example.com?key=sk-123456789"),
                    "note": .string("s e c r e t value"),
                    "huge": .string(String(repeating: "a", count: 1_100_000)),
                    "name": .string("Guide")
                ]
            ]
        )

        let proposal = try ToolValidator().validate(
            toolName: "readRecord",
            arguments: try ProviderToolArguments(values: ["recordID": .string("character-guide")]),
            context: context
        )
        guard case .recordRead(let result) = proposal.result else {
            Issue.record("Expected a record read result")
            return
        }
        #expect(result.fields["link"] == nil)
        #expect(result.fields["note"] == nil)
        #expect(result.fields["huge"] == nil)
        #expect(result.fields["name"] == .string("Guide"))
    }

    @Test
    func attachAssetRejectsNonAssetTargetFields() throws {
        let context = ToolTestFixture.context(
            campaignID: try uuid("22222222-2222-4222-8222-222222222222")
        )
        #expect(throws: ToolValidationError.invalidFieldValue) {
            try ToolValidator().validate(
                toolName: "attachAsset",
                arguments: try ProviderToolArguments(values: [
                    "assetID": .string("asset-map"),
                    "targetRecordID": .string("scene-quay"),
                    "fieldID": .string("title")
                ]),
                context: context
            )
        }
    }

    @Test
    func attachAssetRejectsAssetIDsOutsideTargetFieldEnum() throws {
        let campaignID = try uuid("22222222-2222-4222-8222-222222222222")
        #expect(throws: ToolValidationError.invalidFieldValue) {
            try ToolValidator().validate(
                toolName: "attachAsset",
                arguments: try ToolTestFixture.arguments(for: "attachAsset"),
                context: ToolTestFixture.context(
                    campaignID: campaignID,
                    assetAllowedValues: ["another-asset"]
                )
            )
        }
    }

    @Test
    func validatesStringArraysRelationshipsEnumsAndExactKinds() throws {
        let campaignID = try uuid("22222222-2222-4222-8222-222222222222")
        let context = ToolTestFixture.context(
            campaignID: campaignID,
            relationships: [
                NormalizedRelationship(
                    id: "relationship-ally",
                    kind: "ally",
                    sourceRecordID: "character-guide",
                    targetRecordIDs: ["scene-quay"],
                    extensionPayload: [:]
                )
            ]
        )
        let validator = ToolValidator()

        #expect(throws: ToolValidationError.invalidFieldValue) {
            try validator.validate(
                toolName: "patchRecord",
                arguments: try ProviderToolArguments(values: [
                    "recordID": .string("character-guide"),
                    "fieldsJSON": .string("{\"tags\":[\"one\",2]}")
                ]),
                context: context
            )
        }
        #expect(throws: ToolValidationError.invalidRelationshipTarget) {
            try validator.validate(
                toolName: "patchRecord",
                arguments: try ProviderToolArguments(values: [
                    "recordID": .string("character-guide"),
                    "fieldsJSON": .string("{\"allyID\":\"clock-journey\"}")
                ]),
                context: context
            )
        }
        #expect(throws: ToolValidationError.invalidFieldValue) {
            try validator.validate(
                toolName: "patchRecord",
                arguments: try ProviderToolArguments(values: [
                    "recordID": .string("character-guide"),
                    "fieldsJSON": .string("{\"mood\":\"Calm\"}")
                ]),
                context: context
            )
        }
        #expect(throws: ToolValidationError.invalidIdentifier) {
            try validator.validate(
                toolName: "updateScene",
                arguments: try ProviderToolArguments(values: [
                    "sceneRecordID": .string("scene-quay"),
                    "title": .string("The Quay"),
                    "summary": .null
                ]),
                context: ToolTestFixture.context(
                    campaignID: campaignID,
                    sceneKind: "Scene"
                )
            )
        }
    }

    @Test
    func validatesSceneClockVoiceAssetAndHashBoundaries() throws {
        let campaignID = try uuid("22222222-2222-4222-8222-222222222222")
        let context = ToolTestFixture.context(campaignID: campaignID)
        let validator = ToolValidator()

        let scene = try validator.validate(
            toolName: "updateScene",
            arguments: try ToolTestFixture.arguments(for: "updateScene"),
            context: context
        )
        #expect(scene.event == .sceneChange(sceneRecordID: "scene-quay", title: "The Quay", summary: "Rain gathers."))

        let clock = try validator.validate(
            toolName: "updateClock",
            arguments: try ToolTestFixture.arguments(for: "updateClock"),
            context: context
        )
        #expect(clock.event == .clockUpdate(clockRecordID: "clock-journey", current: 2, maximum: 6))

        let voice = try validator.validate(
            toolName: "suggestVoice",
            arguments: try ToolTestFixture.arguments(for: "suggestVoice"),
            context: context
        )
        #expect(voice.event == .voiceSuggestion(characterRecordID: "character-guide", styleDescription: "Warm and cautious"))

        let asset = try validator.validate(
            toolName: "attachAsset",
            arguments: try ToolTestFixture.arguments(for: "attachAsset"),
            context: context
        )
        #expect(asset.event == .assetAttachment(assetID: "asset-map", targetRecordID: "scene-quay", fieldID: "mapAsset"))

        let invalidHashContext = ToolTestFixture.context(campaignID: campaignID, assetHash: "not-a-sha256")
        #expect(throws: ToolValidationError.invalidAssetReference) {
            try validator.validate(
                toolName: "attachAsset",
                arguments: try ToolTestFixture.arguments(for: "attachAsset"),
                context: invalidHashContext
            )
        }
        let uppercaseHashContext = ToolTestFixture.context(
            campaignID: campaignID,
            assetHash: String(repeating: "A", count: 64)
        )
        #expect(throws: ToolValidationError.invalidAssetReference) {
            try validator.validate(
                toolName: "attachAsset",
                arguments: try ToolTestFixture.arguments(for: "attachAsset"),
                context: uppercaseHashContext
            )
        }
        #expect(throws: ToolValidationError.invalidBounds) {
            try validator.validate(
                toolName: "updateClock",
                arguments: try ProviderToolArguments(values: [
                    "clockRecordID": .string("clock-journey"),
                    "current": .integer(7),
                    "maximum": .integer(6)
                ]),
                context: context
            )
        }
    }

    @Test
    func allowsDistinctAssetsToShareAContentHashWhileKeepingAssetBoundaries() throws {
        let campaignID = try uuid("22222222-2222-4222-8222-222222222222")
        let context = ToolTestFixture.context(
            campaignID: campaignID,
            duplicateHashAsset: true
        )

        let proposal = try ToolValidator().validate(
            toolName: "attachAsset",
            arguments: try ToolTestFixture.arguments(for: "attachAsset"),
            context: context
        )
        #expect(proposal.event == .assetAttachment(
            assetID: "asset-map",
            targetRecordID: "scene-quay",
            fieldID: "mapAsset"
        ))

        #expect(throws: ToolValidationError.invalidAssetReference) {
            try ToolValidator().validate(
                toolName: "attachAsset",
                arguments: try ToolTestFixture.arguments(for: "attachAsset"),
                context: ToolTestFixture.context(
                    campaignID: campaignID,
                    duplicateHashAsset: true,
                    assetURL: URL(string: "assets/other.png")!
                )
            )
        }
    }

    @Test
    func encodedArgumentCapAcceptsExactlyOneMegabyteForKnownToolAndRejectsOneByteMore() throws {
        let exact = Data(repeating: 0x78, count: 1_000_000)
        var oversized = exact
        oversized.append(Data([0x20]))

        try ToolValidator().validateEncodedArgumentCap(
            toolName: "readRecord",
            encodedArguments: exact
        )
        #expect(throws: ToolValidationError.argumentsTooLarge(maximumBytes: 1_000_000, actualBytes: 1_000_001)) {
            try ToolValidator().validateEncodedArgumentCap(
                toolName: "readRecord",
                encodedArguments: oversized
            )
        }
    }

    @Test
    func malformedFuzzValuesAreRejectedWithoutUnsafeStatusEchoes() throws {
        let context = ToolTestFixture.context(
            campaignID: try uuid("22222222-2222-4222-8222-222222222222")
        )
        let values: [JSONValue] = [
            .null,
            .bool(true),
            .integer(-1),
            .number(1.5),
            .array([.object(["draft": .string("hidden")])]),
            .object(["path": .string("file:///private/secret")])
        ]

        for value in values {
            let arguments = try ProviderToolArguments(values: ["recordID": value])
            do {
                _ = try ToolValidator().validate(
                    toolName: "readRecord",
                    arguments: arguments,
                    context: context
                )
                #expect(Bool(false))
            } catch let error as ToolValidationError {
                #expect(error != .unknownTool)
            }
        }

        for seed in 0..<128 {
            let generated: JSONValue
            switch seed % 4 {
            case 0:
                generated = .integer(Int64(seed))
            case 1:
                generated = .bool(seed.isMultiple(of: 2))
            case 2:
                generated = .array([.integer(Int64(seed)), .null])
            default:
                generated = .object(["unknown": .string("value-\(seed)")])
            }
            #expect(throws: ToolValidationError.self) {
                try ToolValidator().validate(
                    toolName: "readRecord",
                    arguments: try ProviderToolArguments(values: ["recordID": generated]),
                    context: context
                )
            }
        }

        let encodedInputs = [
            "",
            "null",
            "[]",
            "{",
            "{\"recordID\":}",
            "{\"recordID\":\"character-guide\"} trailing",
            "{\"recordID\":{\"nested\":true}}",
            "{\"recordID\":\"character-guide\",\"unknown\":1}",
            "{\"recordID\":\"https%3A%2F%2Fexample.com\"}",
            "{\"recordID\":\"sk%2Dencoded-token\"}",
            "{\"recordID\":[1,null]}",
            "{\"recordID\":\"character-guide\",\"recordID\":\"duplicate\"}"
        ]
        for encoded in encodedInputs {
            #expect(throws: ToolValidationError.self) {
                try ToolValidator().validate(
                    toolName: "readRecord",
                    encodedArguments: encoded,
                    context: context
                )
            }
        }
    }

    @Test
    func rejectsDuplicateKeysAndMalformedRawJSONBeforeDecoding() throws {
        let context = ToolTestFixture.context(
            campaignID: try uuid("22222222-2222-4222-8222-222222222222")
        )
        let validator = ToolValidator()

        #expect(throws: ToolValidationError.malformedArguments) {
            try validator.validate(
                toolName: "readRecord",
                encodedArguments: "{\"recordID\":\"https://example.com\",\"recordID\":\"scene-quay\"}",
                context: context
            )
        }

        for fieldsJSON in [
            "{\"name\":\"sk-123456789\",\"name\":\"Mara\"}",
            "{\"details\":{\"visible\":\"https://example.com\",\"visible\":\"one\"}}"
        ] {
            #expect(throws: ToolValidationError.malformedArguments) {
                try validator.validate(
                    toolName: "patchRecord",
                    arguments: try ProviderToolArguments(values: [
                        "recordID": .string("character-guide"),
                        "fieldsJSON": .string(fieldsJSON)
                    ]),
                    context: context
                )
            }
        }

        for encoded in [
            "{\"recordID\":\"character\\qguide\"}",
            "{\"recordID\":\"character\\u12\"}",
            "{\"recordID\":\"character-guide\"} trailing"
        ] {
            #expect(throws: ToolValidationError.malformedArguments) {
                try validator.validate(
                    toolName: "readRecord",
                    encodedArguments: encoded,
                    context: context
                )
            }
        }
    }

    @Test
    func rejectsDeepRawJSONWithinTheByteCapBeforeBuildingAJSONValueTree() throws {
        let context = ToolTestFixture.context(
            campaignID: try uuid("22222222-2222-4222-8222-222222222222")
        )
        var nested = "\"safe\""
        for _ in 0..<9 {
            nested = "[\(nested)]"
        }
        let fieldsJSON = "{\"details\":\(nested)}"
        #expect(fieldsJSON.utf8.count < ToolValidator.maximumArgumentBytes)

        let encodedArguments = "{\"recordID\":\(nested)}"
        #expect(encodedArguments.utf8.count < ToolValidator.maximumArgumentBytes)
        #expect(throws: ToolValidationError.unsafeArgument) {
            try ToolValidator().validate(
                toolName: "readRecord",
                encodedArguments: encodedArguments,
                context: context
            )
        }

        #expect(throws: ToolValidationError.unsafeArgument) {
            try ToolValidator().validate(
                toolName: "patchRecord",
                arguments: try ProviderToolArguments(values: [
                    "recordID": .string("character-guide"),
                    "fieldsJSON": .string(fieldsJSON)
                ]),
                context: context
            )
        }
    }

    @Test
    func rejectsURLsPathsShellExecutableSecretDraftOversizeAndDeepJSONPayloads() throws {
        let context = ToolTestFixture.context(
            campaignID: try uuid("22222222-2222-4222-8222-222222222222")
        )
        let validator = ToolValidator()
        let unsafePrompts = [
            "https://example.com/secret",
            "https%3A%2F%2Fexample.com/secret",
            "sk%2Dencoded-token",
            "http:example",
            "file:///private/notes.txt",
            "folder\\notes.txt",
            "sh -c whoami",
            "cmd /c whoami",
            "powershell -NoProfile",
            "python3 -c whoami",
            "assets/map image.png",
            "run; rm -rf ./save",
            "#!/bin/sh\necho unsafe",
            "payload.exe"
        ]

        for prompt in unsafePrompts {
            #expect(throws: ToolValidationError.unsafeArgument) {
                try validator.validate(
                    toolName: "requestRoll",
                    arguments: try ProviderToolArguments(values: [
                        "expression": .string("1d20"),
                        "prompt": .string(prompt)
                    ]),
                    context: context
                )
            }
        }

        for fieldsJSON in [
            "{\"https%3A%2F%2Fexample.com\":\"safe\"}",
            "{\"name\":\"sk%2Dencoded-token\"}",
            "{\"details\":{\"assets%2Fmap image.png\":\"safe\"}}"
        ] {
            #expect(throws: ToolValidationError.unsafeArgument) {
                try validator.validate(
                    toolName: "patchRecord",
                    arguments: try ProviderToolArguments(values: [
                        "recordID": .string("character-guide"),
                        "fieldsJSON": .string(fieldsJSON)
                    ]),
                    context: context
                )
            }
        }

        #expect(throws: ToolValidationError.unsafeArgument) {
            try validator.validate(
                toolName: "searchRecords",
                arguments: try ProviderToolArguments(values: [
                    "query": .string(String(repeating: "q", count: 257))
                ]),
                context: context
            )
        }

        var nested = "1"
        for _ in 0..<10 { nested = "[\(nested)]" }
        #expect(throws: ToolValidationError.unsafeArgument) {
            try validator.validate(
                toolName: "patchRecord",
                arguments: try ProviderToolArguments(values: [
                    "recordID": .string("character-guide"),
                    "fieldsJSON": .string("{\"name\":\(nested)}")
                ]),
                context: context
            )
        }
    }

    @Test
    func rejectsStandaloneExecutableTokensAndBareCommandFormsIncludingNestedValues() throws {
        let context = ToolTestFixture.context(
            campaignID: try uuid("22222222-2222-4222-8222-222222222222")
        )
        let validator = ToolValidator()

        for prompt in [
            "script.py", "payload.bin", "tool.command", "echo hello",
            "git status", "ls notes", "rm save.dat", "node -e"
        ] {
            #expect(throws: ToolValidationError.unsafeArgument) {
                try validator.validate(
                    toolName: "requestRoll",
                    arguments: try ProviderToolArguments(values: [
                        "expression": .string("1d20"),
                        "prompt": .string(prompt)
                    ]),
                    context: context
                )
            }
        }

        for prompt in [
            "The script.py clue is part of the status.",
            "Node is a city in the status."
        ] {
            let safeNarrative = try validator.validate(
                toolName: "requestRoll",
                arguments: try ProviderToolArguments(values: [
                    "expression": .string("1d20"),
                    "prompt": .string(prompt)
                ]),
                context: context,
                rollID: try uuid("33333333-3333-4333-8333-333333333333")
            )
            #expect(safeNarrative.event != nil)
        }

        for value in [
            "script.py", "payload.bin", "tool.command", "echo hello",
            "git status", "ls notes", "rm save.dat", "node -e"
        ] {
            #expect(throws: ToolValidationError.unsafeArgument) {
                try validator.validate(
                    toolName: "patchRecord",
                    arguments: try ProviderToolArguments(values: [
                        "recordID": .string("character-guide"),
                        "fieldsJSON": .string("{\"details\":{\"value\":\"\\(value)\"}}")
                    ]),
                    context: context
                )
            }
        }

        for prompt in ["git status", "ls notes", "rm save.dat", "node -e"] {
            #expect(throws: ToolValidationError.unsafeArgument) {
                try validator.validate(
                    toolName: "requestRoll",
                    arguments: try ProviderToolArguments(values: [
                        "expression": .string("1d20"),
                        "prompt": .string(percentEncoded(prompt, passes: 2))
                    ]),
                    context: context
                )
            }
            #expect(throws: ToolValidationError.unsafeArgument) {
                try validator.validate(
                    toolName: "patchRecord",
                    arguments: try ProviderToolArguments(values: [
                        "recordID": .string("character-guide"),
                        "fieldsJSON": .string("{\"details\":{\"value\":\"\(percentEncoded(prompt, passes: 2))\"}}")
                    ]),
                    context: context
                )
            }
        }
    }

    @Test
    func rejectsFourLayerAndDeepLayerEncodedUnsafePayloads() throws {
        let context = ToolTestFixture.context(
            campaignID: try uuid("22222222-2222-4222-8222-222222222222")
        )
        let validator = ToolValidator()

        for payload in [
            "http:example",
            "token",
            "sh -c whoami",
            "line\ncontrol"
        ] {
            #expect(throws: ToolValidationError.unsafeArgument) {
                try validator.validate(
                    toolName: "requestRoll",
                    arguments: try ProviderToolArguments(values: [
                        "expression": .string("1d20"),
                        "prompt": .string(percentEncoded(payload, passes: 4))
                    ]),
                    context: context
                )
            }
        }

        #expect(throws: ToolValidationError.unsafeArgument) {
            try validator.validate(
                toolName: "requestRoll",
                arguments: try ProviderToolArguments(values: [
                    "expression": .string("1d20"),
                    "prompt": .string(percentEncoded("http:example", passes: 12))
                ]),
                context: context
            )
        }
    }

    @Test
    func rejectsUnsafeIdentifierPayloadsAcrossReadPatchSceneAndAssetTools() throws {
        let context = ToolTestFixture.context(
            campaignID: try uuid("22222222-2222-4222-8222-222222222222")
        )
        let validator = ToolValidator()
        let values = [
            "http:example", "file:foo", "secret", "token", "draft", "private",
            "credential", "password", "API-key", "sh:whoami", "assets:map.png",
            "http%3Aexample", "%74oken"
        ]

        for value in values {
            #expect(throws: ToolValidationError.invalidIdentifier) {
                try validator.validate(
                    toolName: "readRecord",
                    arguments: try ProviderToolArguments(values: [
                        "recordID": .string(value)
                    ]),
                    context: context
                )
            }
            #expect(throws: ToolValidationError.invalidIdentifier) {
                try validator.validate(
                    toolName: "patchRecord",
                    arguments: try ProviderToolArguments(values: [
                        "recordID": .string(value),
                        "fieldsJSON": .string("{\"name\":\"Mara\"}")
                    ]),
                    context: context
                )
            }
            #expect(throws: ToolValidationError.invalidIdentifier) {
                try validator.validate(
                    toolName: "updateScene",
                    arguments: try ProviderToolArguments(values: [
                        "sceneRecordID": .string(value),
                        "title": .string("The Quay"),
                        "summary": .null
                    ]),
                    context: context
                )
            }
            #expect(throws: ToolValidationError.invalidIdentifier) {
                try validator.validate(
                    toolName: "attachAsset",
                    arguments: try ProviderToolArguments(values: [
                        "assetID": .string(value),
                        "targetRecordID": .string("scene-quay"),
                        "fieldID": .string("mapAsset")
                    ]),
                    context: context
                )
            }
        }
    }

    @Test
    func readRecordExcludesUndeclaredProjectionFieldsAndInvalidDeclaredValues() throws {
        let context = ToolTestFixture.context(
            campaignID: try uuid("22222222-2222-4222-8222-222222222222"),
            projectionRecords: [
                "character-guide": [
                    "name": .integer(7),
                    "undeclared": .string("must not escape")
                ]
            ]
        )

        let proposal = try ToolValidator().validate(
            toolName: "readRecord",
            arguments: try ProviderToolArguments(values: [
                "recordID": .string("character-guide")
            ]),
            context: context
        )
        guard case .recordRead(let result) = proposal.result else {
            Issue.record("Expected a record read result")
            return
        }
        #expect(result.fields["name"] == nil)
        #expect(result.fields["undeclared"] == nil)
    }

    private func uuid(_ value: String) throws -> UUID {
        try #require(UUID(uuidString: value))
    }
}

private enum ToolTestFixture {
    static func context(
        campaignID: UUID,
        assetHash: String = String(repeating: "a", count: 64),
        assetURL: URL? = nil,
        duplicateHashAsset: Bool = false,
        assetReferences: [GMToolAssetReference] = [],
        assetAllowedValues: [String]? = nil,
        relationships: [NormalizedRelationship]? = nil,
        projectionRecords: [String: [String: JSONValue]]? = nil,
        characterName: String = "Guide",
        projectionCampaignID: UUID? = nil,
        sceneKind: String = "scene"
    ) -> GMToolValidationContext {
        GMToolValidationContext(
            campaignID: campaignID,
            project: NormalizedProject(
                cdfVersion: 2,
                importScope: .projectWorldContent,
                id: "project-alpha",
                title: "Fog Over Greyhaven",
                summary: nil,
                system: "Test system",
                rootFolderID: "root",
                currentSceneRecordID: "scene-quay",
                playerCharacterRecordID: "character-guide",
                projectExtensionPayload: [:],
                schemas: [
                    NormalizedSchemaDescriptor(
                        id: "scene-schema",
                        name: "Scene",
                        recordKind: sceneKind,
                        fields: [
                            NormalizedFieldDescriptor(
                                id: "title",
                                name: "Title",
                                valueType: "string",
                                isRequired: true,
                                extensionPayload: [:]
                            ),
                            NormalizedFieldDescriptor(
                                id: "mapAsset",
                                name: "Map Asset",
                                valueType: "assetID",
                                isRequired: false,
                                extensionPayload: assetAllowedValues.map { allowedValues -> [String: JSONValue] in
                                    ["allowedValues": .array(allowedValues.map(JSONValue.string))]
                                } ?? [:]
                            )
                        ],
                        extensionPayload: [:]
                    ),
                    NormalizedSchemaDescriptor(
                        id: "clock-schema",
                        name: "Clock",
                        recordKind: "clock",
                        fields: [],
                        extensionPayload: [:]
                    ),
                    NormalizedSchemaDescriptor(
                        id: "character-schema",
                        name: "Character",
                        recordKind: "character",
                        fields: [
                            NormalizedFieldDescriptor(
                                id: "name",
                                name: "Name",
                                valueType: "string",
                                isRequired: true,
                                extensionPayload: [:]
                            ),
                            NormalizedFieldDescriptor(
                                id: "tags",
                                name: "Tags",
                                valueType: "string[]",
                                isRequired: false,
                                extensionPayload: [:]
                            ),
                            NormalizedFieldDescriptor(
                                id: "mood",
                                name: "Mood",
                                valueType: "string",
                                isRequired: false,
                                extensionPayload: [
                                    "enumValues": .array([
                                        .string("calm"),
                                        .string("stern")
                                    ])
                                ]
                            ),
                            NormalizedFieldDescriptor(
                                id: "allyID",
                                name: "Ally",
                                valueType: "recordID",
                                isRequired: false,
                                extensionPayload: [
                                    "relationshipKind": .string("ally")
                                ]
                            ),
                            NormalizedFieldDescriptor(
                                id: "details",
                                name: "Details",
                                valueType: "object",
                                isRequired: false,
                                extensionPayload: [:]
                            )
                        ],
                        extensionPayload: [:]
                    )
                ],
                content: NormalizedContent(
                    folders: [],
                    records: [
                        NormalizedRecord(
                            id: "scene-quay",
                            fileTypeID: "scene-schema",
                            folderID: nil,
                            fields: [
                                NormalizedField(
                                    id: "title",
                                    value: .string("The Quay"),
                                    extensionPayload: [:]
                                )
                            ],
                            extensionPayload: [:]
                        ),
                        NormalizedRecord(
                            id: "clock-journey",
                            fileTypeID: "clock-schema",
                            folderID: nil,
                            fields: [],
                            extensionPayload: [:]
                        ),
                        NormalizedRecord(
                            id: "character-guide",
                            fileTypeID: "character-schema",
                            folderID: nil,
                            fields: [
                                NormalizedField(
                                    id: "name",
                                    value: .string(characterName),
                                    extensionPayload: [:]
                                ),
                                NormalizedField(
                                    id: "allyID",
                                    value: .string("scene-quay"),
                                    extensionPayload: [:]
                                )
                            ],
                            extensionPayload: [:]
                        )
                    ],
                    relationships: relationships ?? [
                        NormalizedRelationship(
                            id: "relationship-ally",
                            kind: "ally",
                            sourceRecordID: "character-guide",
                            targetRecordIDs: ["scene-quay"],
                            extensionPayload: [:]
                        )
                    ],
                    assets: [
                        NormalizedAsset(
                            id: "asset-map",
                            relativePath: "assets/map.png",
                            mediaType: "image/png",
                            extensionPayload: [:]
                        )
                    ] + (duplicateHashAsset ? [
                        NormalizedAsset(
                            id: "asset-other",
                            relativePath: "assets/other.png",
                            mediaType: "image/png",
                            extensionPayload: [:]
                        )
                    ] : []),
                    maps: [],
                    characters: [
                        NormalizedCharacter(
                            id: "character-guide",
                            recordID: "character-guide",
                            portraitAssetID: nil,
                            extensionPayload: [:]
                        )
                    ],
                    extensionPayload: [:]
                ),
                manifest: NormalizedManifest(
                    files: [],
                    recordIDs: ["scene-quay", "clock-journey", "character-guide"]
                ),
                extensionPayload: [:]
            ),
            projection: CampaignProjection(
                campaignID: projectionCampaignID ?? campaignID,
                importedProjectID: "project-alpha",
                records: projectionRecords ?? [
                    "character-guide": [
                        "name": .string("Guide"),
                        "allyID": .string("scene-quay")
                    ]
                ]
            ),
            importedAssets: [
                ImportedAsset(
                    assetID: "asset-map",
                    sha256: assetHash,
                    appRelativeURL: assetURL ?? URL(
                        string: "Campaigns/\(campaignID.uuidString.lowercased())/assets/map.png"
                        )!
                )
            ] + (duplicateHashAsset ? [
                ImportedAsset(
                    assetID: "asset-other",
                    sha256: assetHash,
                    appRelativeURL: URL(
                        string: "Campaigns/\(campaignID.uuidString.lowercased())/assets/other.png"
                    )!
                )
            ] : []),
            assetReferences: assetReferences
        )
    }

    static func arguments(for toolName: String) throws -> ProviderToolArguments {
        let values: [String: JSONValue]
        switch toolName {
        case "readRecord":
            values = ["recordID": .string("scene-quay")]
        case "searchRecords":
            values = ["query": .string("quay")]
        case "patchRecord":
            values = [
                "recordID": .string("character-guide"),
                "fieldsJSON": .string("{\"name\":\"Mara\"}")
            ]
        case "requestRoll":
            values = [
                "expression": .string("1d20+3"),
                "prompt": .string("Slip past the sentry")
            ]
        case "updateScene":
            values = [
                "sceneRecordID": .string("scene-quay"),
                "title": .string("The Quay"),
                "summary": .string("Rain gathers.")
            ]
        case "updateClock":
            values = [
                "clockRecordID": .string("clock-journey"),
                "current": .integer(2),
                "maximum": .integer(6)
            ]
        case "suggestVoice":
            values = [
                "characterRecordID": .string("character-guide"),
                "styleDescription": .string("Warm and cautious")
            ]
        case "attachAsset":
            values = [
                "assetID": .string("asset-map"),
                "targetRecordID": .string("scene-quay"),
                "fieldID": .string("mapAsset")
            ]
        default:
            values = [:]
        }
        return try ProviderToolArguments(values: values)
    }

}

private func percentEncoded(_ value: String, passes: Int) -> String {
    var encoded = value
    for _ in 0..<passes {
        encoded = encoded.addingPercentEncoding(
            withAllowedCharacters: CharacterSet()
        ) ?? encoded
    }
    return encoded
}
