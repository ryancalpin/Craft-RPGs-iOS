import Foundation

public struct ReferenceValidator: Sendable {
    private static let supportedRecordKinds: Set<String> = [
        "record",
        "scene",
        "map",
        "character"
    ]

    public init() {}

    public func warnings(
        for project: NormalizedProject,
        stagedRelativePaths: Set<String>
    ) -> [ImportIssue] {
        let folderIDs = Set(project.folders.map(\.id))
        let recordIDs = Set(project.records.map(\.id))
        let schemaIDs = Set(project.schemas.map(\.id))
        let assetIDs = Set(project.assets.map(\.id))
        var issues: [ImportIssue] = []

        for schema in project.schemas
        where Self.supportedRecordKinds.contains(schema.recordKind) == false {
            issues.append(
                ImportIssue(
                    code: "unsupported-record-kind",
                    message: "Record kind \(schema.recordKind) requires review.",
                    relativePath: "fileTypes.\(schema.id)"
                )
            )
        }

        for folder in project.folders {
            if let parentID = folder.parentID,
               folderIDs.contains(parentID) == false {
                issues.append(
                    ImportIssue(
                        code: "broken-folder-reference",
                        message: "Folder \(folder.id) references missing parent \(parentID).",
                        relativePath: "content.folders.\(folder.id)"
                    )
                )
            }
        }

        for record in project.records {
            if let folderID = record.folderID,
               folderIDs.contains(folderID) == false {
                issues.append(
                    ImportIssue(
                        code: "broken-folder-reference",
                        message: "Record \(record.id) references missing folder \(folderID).",
                        relativePath: "content.records.\(record.id)"
                    )
                )
            }
            if schemaIDs.contains(record.fileTypeID) == false {
                issues.append(
                    ImportIssue(
                        code: "broken-file-type-reference",
                        message: "Record \(record.id) references missing file type \(record.fileTypeID).",
                        relativePath: "content.records.\(record.id)"
                    )
                )
            }
        }

        for relationship in project.relationships {
            if recordIDs.contains(relationship.sourceRecordID) == false {
                issues.append(
                    brokenRecordIssue(
                        owner: "Relationship \(relationship.id)",
                        missingID: relationship.sourceRecordID,
                        path: "content.relationships.\(relationship.id)"
                    )
                )
            }
            for targetID in relationship.targetRecordIDs
            where recordIDs.contains(targetID) == false {
                issues.append(
                    brokenRecordIssue(
                        owner: "Relationship \(relationship.id)",
                        missingID: targetID,
                        path: "content.relationships.\(relationship.id)"
                    )
                )
            }
        }

        if let sceneID = project.currentSceneRecordID,
           recordIDs.contains(sceneID) == false {
            issues.append(
                brokenRecordIssue(
                    owner: "Project current scene",
                    missingID: sceneID,
                    path: "project.currentSceneRecordID"
                )
            )
        }
        if let characterID = project.playerCharacterRecordID,
           recordIDs.contains(characterID) == false {
            issues.append(
                brokenRecordIssue(
                    owner: "Project player character",
                    missingID: characterID,
                    path: "project.playerCharacterRecordID"
                )
            )
        }

        for asset in project.assets
        where stagedRelativePaths.contains(asset.relativePath) == false {
            issues.append(
                ImportIssue(
                    code: "missing-asset-file",
                    message: "Asset \(asset.id) is missing \(asset.relativePath).",
                    relativePath: asset.relativePath
                )
            )
        }

        for map in project.maps {
            if recordIDs.contains(map.recordID) == false {
                issues.append(
                    brokenRecordIssue(
                        owner: "Map \(map.id)",
                        missingID: map.recordID,
                        path: "content.maps.\(map.id)"
                    )
                )
            }
            if let assetID = map.assetID,
               assetIDs.contains(assetID) == false {
                issues.append(
                    missingAssetReferenceIssue(
                        owner: "Map \(map.id)",
                        missingID: assetID,
                        path: "content.maps.\(map.id)"
                    )
                )
            }
        }

        for character in project.characters {
            if recordIDs.contains(character.recordID) == false {
                issues.append(
                    brokenRecordIssue(
                        owner: "Character \(character.id)",
                        missingID: character.recordID,
                        path: "content.characters.\(character.id)"
                    )
                )
            }
            if let assetID = character.portraitAssetID,
               assetIDs.contains(assetID) == false {
                issues.append(
                    missingAssetReferenceIssue(
                        owner: "Character \(character.id)",
                        missingID: assetID,
                        path: "content.characters.\(character.id)"
                    )
                )
            }
        }

        return issues.sorted(by: Self.issuePrecedes)
    }

    private func brokenRecordIssue(
        owner: String,
        missingID: String,
        path: String
    ) -> ImportIssue {
        ImportIssue(
            code: "broken-record-reference",
            message: "\(owner) references missing record \(missingID).",
            relativePath: path
        )
    }

    private func missingAssetReferenceIssue(
        owner: String,
        missingID: String,
        path: String
    ) -> ImportIssue {
        ImportIssue(
            code: "missing-asset-reference",
            message: "\(owner) references missing asset \(missingID).",
            relativePath: path
        )
    }

    private static func issuePrecedes(_ lhs: ImportIssue, _ rhs: ImportIssue) -> Bool {
        if lhs.code != rhs.code { return lhs.code < rhs.code }
        if lhs.relativePath != rhs.relativePath {
            return (lhs.relativePath ?? "") < (rhs.relativePath ?? "")
        }
        return lhs.message < rhs.message
    }
}
