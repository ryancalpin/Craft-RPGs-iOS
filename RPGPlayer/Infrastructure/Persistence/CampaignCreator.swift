import Foundation

struct NewCampaignDraft: Equatable, Sendable {
    let title: String
    let premise: String
    let playerCharacter: String

    init(title: String, premise: String = "", playerCharacter: String = "") {
        self.title = title
        self.premise = premise
        self.playerCharacter = playerCharacter
    }
}

enum CampaignCreationError: Error, Equatable, Sendable {
    case titleRequired
    case invalidCampaignDirectory
    case campaignAlreadyExists
    case unableToCreateCampaignDirectory
    case unableToWriteProject
    case persistenceFailed
}

struct CampaignCreator: Sendable {
    private let store: any CampaignStore
    private let campaignDirectory: CampaignDirectory

    init(store: any CampaignStore, campaignDirectory: CampaignDirectory) {
        self.store = store
        self.campaignDirectory = campaignDirectory
    }

    func create(_ draft: NewCampaignDraft) async throws -> UUID {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false else {
            throw CampaignCreationError.titleRequired
        }

        let campaignID = UUID()
        let destination = campaignDirectory.campaignURL(for: campaignID)
        guard campaignDirectory.isExactCampaignURL(
            destination,
            for: campaignID
        ) else {
            throw CampaignCreationError.invalidCampaignDirectory
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: destination.path) == false else {
            throw CampaignCreationError.campaignAlreadyExists
        }

        var shouldRemoveDirectory = false
        defer {
            if shouldRemoveDirectory {
                try? fileManager.removeItem(at: destination)
            }
        }

        do {
            try fileManager.createDirectory(
                at: campaignDirectory.campaignsRootURL,
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: destination,
                withIntermediateDirectories: false
            )
            shouldRemoveDirectory = true
        } catch {
            throw CampaignCreationError.unableToCreateCampaignDirectory
        }

        let project = Self.project(
            for: draft,
            title: title,
            campaignID: campaignID
        )
        let projectURL = destination.appendingPathComponent(
            "normalized-project.json",
            isDirectory: false
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(project).write(to: projectURL, options: .atomic)
        } catch {
            throw CampaignCreationError.unableToWriteProject
        }

        let manifestHash: String
        do {
            manifestHash = "sha256:" + (try FileHashing.sha256(of: projectURL))
        } catch {
            throw CampaignCreationError.unableToWriteProject
        }

        let event = CampaignEvent(
            id: UUID(),
            campaignID: campaignID,
            sequence: 0,
            requestID: UUID(),
            timestamp: Date(),
            schemaVersion: 1,
            payload: .campaignImported(
                CampaignImportedPayload(
                    projectID: project.id,
                    campaignTitle: project.title,
                    manifestHash: manifestHash,
                    extensionPayload: [
                        "creationSource": .string("native"),
                        "importScope": .string(
                            CDFImportScope.projectWorldContent.rawValue
                        )
                    ]
                )
            )
        )

        do {
            _ = try await store.append(
                batch: [event],
                assets: [],
                expectedSequence: 0
            )
        } catch {
            throw CampaignCreationError.persistenceFailed
        }

        shouldRemoveDirectory = false
        return campaignID
    }

    private static func project(
        for draft: NewCampaignDraft,
        title: String,
        campaignID: UUID
    ) -> NormalizedProject {
        let token = campaignID.uuidString.lowercased()
        let rootFolderID = "root"
        let sceneRecordID = "scene-\(token)"
        let characterRecordID = "character-\(token)"
        let premise = draft.premise.trimmingCharacters(in: .whitespacesAndNewlines)
        let playerCharacter = draft.playerCharacter.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        var sceneFields = [
            NormalizedField(
                id: "title",
                value: .string(title),
                extensionPayload: [:]
            )
        ]
        if premise.isEmpty == false {
            sceneFields.append(
                NormalizedField(
                    id: "description",
                    value: .string(premise),
                    extensionPayload: [:]
                )
            )
        }

        var records = [
            NormalizedRecord(
                id: sceneRecordID,
                fileTypeID: "scene",
                folderID: rootFolderID,
                fields: sceneFields,
                extensionPayload: [:]
            )
        ]
        var characters: [NormalizedCharacter] = []
        var playerCharacterRecordID: String?
        if playerCharacter.isEmpty == false {
            playerCharacterRecordID = characterRecordID
            records.append(
                NormalizedRecord(
                    id: characterRecordID,
                    fileTypeID: "character",
                    folderID: rootFolderID,
                    fields: [
                        NormalizedField(
                            id: "name",
                            value: .string(playerCharacter),
                            extensionPayload: [:]
                        )
                    ],
                    extensionPayload: [:]
                )
            )
            characters.append(
                NormalizedCharacter(
                    id: characterRecordID,
                    recordID: characterRecordID,
                    portraitAssetID: nil,
                    extensionPayload: [:]
                )
            )
        }

        let schemas = [
            NormalizedSchemaDescriptor(
                id: "scene",
                name: "Scene",
                recordKind: "scene",
                fields: [
                    NormalizedFieldDescriptor(
                        id: "title",
                        name: "Title",
                        valueType: "string",
                        isRequired: true,
                        extensionPayload: [:]
                    ),
                    NormalizedFieldDescriptor(
                        id: "description",
                        name: "Description",
                        valueType: "string",
                        isRequired: false,
                        extensionPayload: [:]
                    )
                ],
                extensionPayload: [:]
            ),
            NormalizedSchemaDescriptor(
                id: "character",
                name: "Character",
                recordKind: "character",
                fields: [
                    NormalizedFieldDescriptor(
                        id: "name",
                        name: "Name",
                        valueType: "string",
                        isRequired: true,
                        extensionPayload: [:]
                    )
                ],
                extensionPayload: [:]
            )
        ]

        return NormalizedProject(
            cdfVersion: 2,
            importScope: .projectWorldContent,
            id: "native-\(token)",
            title: title,
            summary: premise.isEmpty ? nil : premise,
            system: nil,
            rootFolderID: rootFolderID,
            currentSceneRecordID: sceneRecordID,
            playerCharacterRecordID: playerCharacterRecordID,
            projectExtensionPayload: [
                "creationSource": .string("native")
            ],
            schemas: schemas,
            content: NormalizedContent(
                folders: [
                    NormalizedFolder(
                        id: rootFolderID,
                        name: "World",
                        parentID: nil,
                        extensionPayload: [:]
                    )
                ],
                records: records,
                relationships: [],
                assets: [],
                maps: [],
                characters: characters,
                extensionPayload: [
                    "creationSource": .string("native")
                ]
            ),
            manifest: NormalizedManifest(
                files: [],
                recordIDs: records.map(\.id)
            ),
            extensionPayload: [
                "creationSource": .string("native")
            ]
        )
    }
}
