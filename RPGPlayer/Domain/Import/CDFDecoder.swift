import Foundation

public enum CDFDecodingError: Error, Equatable, Sendable {
    case invalidMetadata
    case invalidFileTypes
    case invalidContent
    case unsupportedCDFVersion(Int)
    case duplicateIdentifier(kind: String, id: String)
    case unreadableRoot(String)
    case invalidAssetPath(String)
}

/// Decodes RPGPlayer's documented, plan-owned CDF v2 subset from a staged
/// source. A successful result is project/world content, not recovered play.
public struct CDFDecoder: Sendable {
    public init() {}

    public func decode(_ stagedImport: StagedImport) throws -> CDFDecodeResult {
        guard stagedImport.files.contains(where: {
            $0.relativePath == "project.json"
        }) else {
            throw CDFDecodingError.unreadableRoot("Missing project.json")
        }

        let projectURL = stagedImport.directoryURL.appendingPathComponent(
            "project.json",
            isDirectory: false
        )
        let data: Data
        do {
            data = try Data(contentsOf: projectURL)
        } catch {
            throw CDFDecodingError.unreadableRoot("Unreadable project.json")
        }

        let decoder = JSONDecoder()
        let metadata: CDFMetadataEnvelope
        do {
            metadata = try decoder.decode(CDFMetadataEnvelope.self, from: data)
        } catch {
            throw CDFDecodingError.invalidMetadata
        }

        guard metadata.cdfVersion == 2 else {
            throw CDFDecodingError.unsupportedCDFVersion(metadata.cdfVersion)
        }
        try validateRootMetadata(metadata.project)

        let fileTypes: [CDFFileType]
        do {
            fileTypes = try decoder.decode(
                CDFFileTypesEnvelope.self,
                from: data
            ).fileTypes
        } catch {
            throw CDFDecodingError.invalidFileTypes
        }
        try validateFileTypeIdentifiers(fileTypes)

        let content: CDFContent
        do {
            content = try decoder.decode(
                CDFContentEnvelope.self,
                from: data
            ).content
        } catch {
            throw CDFDecodingError.invalidContent
        }
        try validateContentIdentifiers(content)

        let document = CDFDocument(
            cdfVersion: metadata.cdfVersion,
            project: metadata.project,
            fileTypes: fileTypes,
            content: content,
            extensionPayload: metadata.extensionPayload
        )
        let normalized = try normalize(document, stagedImport: stagedImport)
        guard normalized.folders.contains(where: {
            $0.id == normalized.rootFolderID
        }) else {
            throw CDFDecodingError.unreadableRoot(
                "Missing root folder \(normalized.rootFolderID)"
            )
        }

        let warnings = ReferenceValidator().warnings(
            for: normalized,
            stagedRelativePaths: Set(
                stagedImport.files.map(\.relativePath)
            )
        )
        return CDFDecodeResult(
            project: normalized,
            report: ImportReport(
                projectTitle: normalized.title,
                recordCount: normalized.records.count,
                assetCount: normalized.assets.count,
                warnings: warnings,
                fatalErrors: []
            )
        )
    }

    private func validateRootMetadata(_ project: CDFProject) throws {
        guard project.id.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false else {
            throw CDFDecodingError.unreadableRoot("Project id is blank")
        }
        guard project.title.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false else {
            throw CDFDecodingError.unreadableRoot("Project title is blank")
        }
        guard project.rootFolderID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false else {
            throw CDFDecodingError.unreadableRoot("Root folder id is blank")
        }
    }

    private func validateFileTypeIdentifiers(
        _ fileTypes: [CDFFileType]
    ) throws {
        try requireUniqueIDs(fileTypes, kind: "file type", id: \.id)
        for fileType in fileTypes {
            try requireUniqueIDs(
                fileType.fields,
                kind: "field descriptor in \(fileType.id)",
                id: \.id
            )
        }
    }

    private func validateContentIdentifiers(_ content: CDFContent) throws {
        try requireUniqueIDs(content.folders, kind: "folder", id: \.id)
        try requireUniqueIDs(content.records, kind: "record", id: \.id)
        try requireUniqueIDs(
            content.relationships,
            kind: "relationship",
            id: \.id
        )
        try requireUniqueIDs(content.assets, kind: "asset", id: \.id)
        try requireUniqueIDs(content.maps, kind: "map", id: \.id)
        try requireUniqueIDs(content.characters, kind: "character", id: \.id)
        for record in content.records {
            try requireUniqueIDs(
                record.fields,
                kind: "field in \(record.id)",
                id: \.id
            )
        }
    }

    private func requireUniqueIDs<Value>(
        _ values: [Value],
        kind: String,
        id: KeyPath<Value, String>
    ) throws {
        var seen: Set<String> = []
        for value in values {
            let identifier = value[keyPath: id]
            guard seen.insert(identifier).inserted else {
                throw CDFDecodingError.duplicateIdentifier(
                    kind: kind,
                    id: identifier
                )
            }
        }
    }

    private func normalize(
        _ document: CDFDocument,
        stagedImport: StagedImport
    ) throws -> NormalizedProject {
        let schemas = document.fileTypes.map { fileType in
            NormalizedSchemaDescriptor(
                id: fileType.id,
                name: fileType.name,
                recordKind: fileType.recordKind,
                fields: fileType.fields.map { field in
                    NormalizedFieldDescriptor(
                        id: field.id,
                        name: field.name,
                        valueType: field.valueType,
                        isRequired: field.isRequired,
                        extensionPayload: field.extensionPayload
                    )
                }.sorted { $0.id < $1.id },
                extensionPayload: fileType.extensionPayload
            )
        }.sorted { $0.id < $1.id }

        let folders = document.content.folders.map {
            NormalizedFolder(
                id: $0.id,
                name: $0.name,
                parentID: $0.parentID,
                extensionPayload: $0.extensionPayload
            )
        }.sorted { $0.id < $1.id }

        let records = document.content.records.map { record in
            NormalizedRecord(
                id: record.id,
                fileTypeID: record.fileTypeID,
                folderID: record.folderID,
                fields: record.fields.map {
                    NormalizedField(
                        id: $0.id,
                        value: $0.value,
                        extensionPayload: $0.extensionPayload
                    )
                }.sorted { $0.id < $1.id },
                extensionPayload: record.extensionPayload
            )
        }.sorted { $0.id < $1.id }

        let relationships = document.content.relationships.map {
            NormalizedRelationship(
                id: $0.id,
                kind: $0.kind,
                sourceRecordID: $0.sourceRecordID,
                targetRecordIDs: $0.targetRecordIDs.sorted(),
                extensionPayload: $0.extensionPayload
            )
        }.sorted { $0.id < $1.id }

        let assets = try document.content.assets.map { asset in
            let path: CanonicalPath
            do {
                path = try CanonicalPath(
                    asset.relativePath,
                    maximumDepth: ImportLimits.standard.maximumPathDepth
                )
            } catch {
                throw CDFDecodingError.invalidAssetPath(asset.relativePath)
            }
            return NormalizedAsset(
                id: asset.id,
                relativePath: path.string,
                mediaType: asset.mediaType,
                extensionPayload: asset.extensionPayload
            )
        }.sorted { $0.id < $1.id }

        let maps = document.content.maps.map {
            NormalizedMap(
                id: $0.id,
                recordID: $0.recordID,
                assetID: $0.assetID,
                extensionPayload: $0.extensionPayload
            )
        }.sorted { $0.id < $1.id }

        let characters = document.content.characters.map {
            NormalizedCharacter(
                id: $0.id,
                recordID: $0.recordID,
                portraitAssetID: $0.portraitAssetID,
                extensionPayload: $0.extensionPayload
            )
        }.sorted { $0.id < $1.id }

        let manifest = NormalizedManifest(
            files: stagedImport.files.map {
                NormalizedManifestFile(
                    relativePath: $0.relativePath,
                    byteCount: $0.byteCount,
                    sha256: $0.sha256
                )
            }.sorted { lhs, rhs in
                lhs.relativePath < rhs.relativePath
            },
            recordIDs: records.map(\.id).sorted()
        )

        return NormalizedProject(
            cdfVersion: document.cdfVersion,
            importScope: .projectWorldContent,
            id: document.project.id,
            title: document.project.title,
            summary: document.project.summary,
            system: document.project.system,
            rootFolderID: document.project.rootFolderID,
            currentSceneRecordID: document.project.currentSceneRecordID,
            playerCharacterRecordID: document.project.playerCharacterRecordID,
            projectExtensionPayload: document.project.extensionPayload,
            schemas: schemas,
            content: NormalizedContent(
                folders: folders,
                records: records,
                relationships: relationships,
                assets: assets,
                maps: maps,
                characters: characters,
                extensionPayload: document.content.extensionPayload
            ),
            manifest: manifest,
            extensionPayload: document.extensionPayload
        )
    }
}
