import Foundation

public enum CDFImportScope: String, Codable, Equatable, Sendable {
    /// CDF describes importable project/world content, not live-save history.
    case projectWorldContent
}

public struct CDFDecodeResult: Codable, Equatable, Sendable {
    public let project: NormalizedProject
    public let report: ImportReport

    public init(project: NormalizedProject, report: ImportReport) {
        self.project = project
        self.report = report
    }
}

public struct NormalizedProject: Codable, Equatable, Sendable {
    public let cdfVersion: Int
    public let importScope: CDFImportScope
    public let id: String
    public let title: String
    public let summary: String?
    public let system: String?
    public let rootFolderID: String
    public let currentSceneRecordID: String?
    public let playerCharacterRecordID: String?
    public let projectExtensionPayload: [String: JSONValue]
    public let schemas: [NormalizedSchemaDescriptor]
    public let content: NormalizedContent
    public let manifest: NormalizedManifest
    public let extensionPayload: [String: JSONValue]

    public var folders: [NormalizedFolder] { content.folders }
    public var records: [NormalizedRecord] { content.records }
    public var relationships: [NormalizedRelationship] {
        content.relationships
    }
    public var assets: [NormalizedAsset] { content.assets }
    public var maps: [NormalizedMap] { content.maps }
    public var characters: [NormalizedCharacter] { content.characters }

    public init(
        cdfVersion: Int,
        importScope: CDFImportScope,
        id: String,
        title: String,
        summary: String?,
        system: String?,
        rootFolderID: String,
        currentSceneRecordID: String?,
        playerCharacterRecordID: String?,
        projectExtensionPayload: [String: JSONValue],
        schemas: [NormalizedSchemaDescriptor],
        content: NormalizedContent,
        manifest: NormalizedManifest,
        extensionPayload: [String: JSONValue]
    ) {
        self.cdfVersion = cdfVersion
        self.importScope = importScope
        self.id = id
        self.title = title
        self.summary = summary
        self.system = system
        self.rootFolderID = rootFolderID
        self.currentSceneRecordID = currentSceneRecordID
        self.playerCharacterRecordID = playerCharacterRecordID
        self.projectExtensionPayload = projectExtensionPayload
        self.schemas = schemas
        self.content = content
        self.manifest = manifest
        self.extensionPayload = extensionPayload
    }
}

public struct NormalizedContent: Codable, Equatable, Sendable {
    public let folders: [NormalizedFolder]
    public let records: [NormalizedRecord]
    public let relationships: [NormalizedRelationship]
    public let assets: [NormalizedAsset]
    public let maps: [NormalizedMap]
    public let characters: [NormalizedCharacter]
    public let extensionPayload: [String: JSONValue]

    public init(
        folders: [NormalizedFolder],
        records: [NormalizedRecord],
        relationships: [NormalizedRelationship],
        assets: [NormalizedAsset],
        maps: [NormalizedMap],
        characters: [NormalizedCharacter],
        extensionPayload: [String: JSONValue]
    ) {
        self.folders = folders
        self.records = records
        self.relationships = relationships
        self.assets = assets
        self.maps = maps
        self.characters = characters
        self.extensionPayload = extensionPayload
    }
}

public struct NormalizedSchemaDescriptor: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let recordKind: String
    public let fields: [NormalizedFieldDescriptor]
    public let extensionPayload: [String: JSONValue]

    public init(
        id: String,
        name: String,
        recordKind: String,
        fields: [NormalizedFieldDescriptor],
        extensionPayload: [String: JSONValue]
    ) {
        self.id = id
        self.name = name
        self.recordKind = recordKind
        self.fields = fields
        self.extensionPayload = extensionPayload
    }
}

public struct NormalizedFieldDescriptor: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let valueType: String
    public let isRequired: Bool
    public let extensionPayload: [String: JSONValue]

    public init(
        id: String,
        name: String,
        valueType: String,
        isRequired: Bool,
        extensionPayload: [String: JSONValue]
    ) {
        self.id = id
        self.name = name
        self.valueType = valueType
        self.isRequired = isRequired
        self.extensionPayload = extensionPayload
    }
}

public struct NormalizedFolder: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let parentID: String?
    public let extensionPayload: [String: JSONValue]

    public init(
        id: String,
        name: String,
        parentID: String?,
        extensionPayload: [String: JSONValue]
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.extensionPayload = extensionPayload
    }
}

public struct NormalizedRecord: Codable, Equatable, Sendable {
    public let id: String
    public let fileTypeID: String
    public let folderID: String?
    public let fields: [NormalizedField]
    public let extensionPayload: [String: JSONValue]

    public init(
        id: String,
        fileTypeID: String,
        folderID: String?,
        fields: [NormalizedField],
        extensionPayload: [String: JSONValue]
    ) {
        self.id = id
        self.fileTypeID = fileTypeID
        self.folderID = folderID
        self.fields = fields
        self.extensionPayload = extensionPayload
    }
}

public struct NormalizedField: Codable, Equatable, Sendable {
    public let id: String
    public let value: JSONValue
    public let extensionPayload: [String: JSONValue]

    public init(
        id: String,
        value: JSONValue,
        extensionPayload: [String: JSONValue]
    ) {
        self.id = id
        self.value = value
        self.extensionPayload = extensionPayload
    }
}

public struct NormalizedRelationship: Codable, Equatable, Sendable {
    public let id: String
    public let kind: String
    public let sourceRecordID: String
    public let targetRecordIDs: [String]
    public let extensionPayload: [String: JSONValue]

    public init(
        id: String,
        kind: String,
        sourceRecordID: String,
        targetRecordIDs: [String],
        extensionPayload: [String: JSONValue]
    ) {
        self.id = id
        self.kind = kind
        self.sourceRecordID = sourceRecordID
        self.targetRecordIDs = targetRecordIDs
        self.extensionPayload = extensionPayload
    }
}

public struct NormalizedAsset: Codable, Equatable, Sendable {
    public let id: String
    public let relativePath: String
    public let mediaType: String?
    public let extensionPayload: [String: JSONValue]

    public init(
        id: String,
        relativePath: String,
        mediaType: String?,
        extensionPayload: [String: JSONValue]
    ) {
        self.id = id
        self.relativePath = relativePath
        self.mediaType = mediaType
        self.extensionPayload = extensionPayload
    }
}

public struct NormalizedMap: Codable, Equatable, Sendable {
    public let id: String
    public let recordID: String
    public let assetID: String?
    public let extensionPayload: [String: JSONValue]

    public init(
        id: String,
        recordID: String,
        assetID: String?,
        extensionPayload: [String: JSONValue]
    ) {
        self.id = id
        self.recordID = recordID
        self.assetID = assetID
        self.extensionPayload = extensionPayload
    }
}

public struct NormalizedCharacter: Codable, Equatable, Sendable {
    public let id: String
    public let recordID: String
    public let portraitAssetID: String?
    public let extensionPayload: [String: JSONValue]

    public init(
        id: String,
        recordID: String,
        portraitAssetID: String?,
        extensionPayload: [String: JSONValue]
    ) {
        self.id = id
        self.recordID = recordID
        self.portraitAssetID = portraitAssetID
        self.extensionPayload = extensionPayload
    }
}

public struct NormalizedManifest: Codable, Equatable, Sendable {
    public let files: [NormalizedManifestFile]
    public let recordIDs: [String]

    public init(files: [NormalizedManifestFile], recordIDs: [String]) {
        self.files = files
        self.recordIDs = recordIDs
    }
}

public struct NormalizedManifestFile: Codable, Equatable, Sendable {
    public let relativePath: String
    public let byteCount: Int64
    public let sha256: String

    public init(relativePath: String, byteCount: Int64, sha256: String) {
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}
