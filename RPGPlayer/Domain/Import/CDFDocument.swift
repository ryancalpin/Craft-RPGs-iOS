import Foundation

/// Raw models for RPGPlayer's small, plan-owned CDF v2 import contract.
/// This is intentionally not presented as an unpublished Craft save schema.
struct CDFDocument: Sendable {
    let cdfVersion: Int
    let project: CDFProject
    let fileTypes: [CDFFileType]
    let content: CDFContent
    let extensionPayload: [String: JSONValue]
}

struct CDFMetadataEnvelope: Decodable, Sendable {
    let cdfVersion: Int
    let project: CDFProject
    let extensionPayload: [String: JSONValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CDFCodingKey.self)
        cdfVersion = try container.decode(Int.self, forKey: .cdfVersion)
        project = try container.decode(CDFProject.self, forKey: .project)
        extensionPayload = try container.extensionPayload(
            excluding: [.cdfVersion, .project, .fileTypes, .content]
        )
    }
}

struct CDFFileTypesEnvelope: Decodable, Sendable {
    let fileTypes: [CDFFileType]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CDFCodingKey.self)
        fileTypes = try container.decode(
            [CDFFileType].self,
            forKey: .fileTypes
        )
    }
}

struct CDFContentEnvelope: Decodable, Sendable {
    let content: CDFContent

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CDFCodingKey.self)
        content = try container.decode(CDFContent.self, forKey: .content)
    }
}

struct CDFProject: Decodable, Sendable {
    let id: String
    let title: String
    let summary: String?
    let system: String?
    let rootFolderID: String
    let currentSceneRecordID: String?
    let playerCharacterRecordID: String?
    let extensionPayload: [String: JSONValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CDFCodingKey.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        system = try container.decodeIfPresent(String.self, forKey: .system)
        rootFolderID = try container.decode(
            String.self,
            forKey: .rootFolderID
        )
        currentSceneRecordID = try container.decodeIfPresent(
            String.self,
            forKey: .currentSceneRecordID
        )
        playerCharacterRecordID = try container.decodeIfPresent(
            String.self,
            forKey: .playerCharacterRecordID
        )
        extensionPayload = try container.extensionPayload(
            excluding: [
                .id,
                .title,
                .summary,
                .system,
                .rootFolderID,
                .currentSceneRecordID,
                .playerCharacterRecordID
            ]
        )
    }
}

struct CDFFileType: Decodable, Sendable {
    let id: String
    let name: String
    let recordKind: String
    let fields: [CDFFieldDescriptor]
    let extensionPayload: [String: JSONValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CDFCodingKey.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        recordKind = try container.decode(String.self, forKey: .recordKind)
        fields = try container.decodeIfPresent(
            [CDFFieldDescriptor].self,
            forKey: .fields
        ) ?? []
        extensionPayload = try container.extensionPayload(
            excluding: [.id, .name, .recordKind, .fields]
        )
    }
}

struct CDFFieldDescriptor: Decodable, Sendable {
    let id: String
    let name: String
    let valueType: String
    let isRequired: Bool
    let extensionPayload: [String: JSONValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CDFCodingKey.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        valueType = try container.decode(String.self, forKey: .valueType)
        isRequired = try container.decodeIfPresent(
            Bool.self,
            forKey: .required
        ) ?? false
        extensionPayload = try container.extensionPayload(
            excluding: [.id, .name, .valueType, .required]
        )
    }
}

struct CDFContent: Decodable, Sendable {
    let folders: [CDFFolder]
    let records: [CDFRecord]
    let relationships: [CDFRelationship]
    let assets: [CDFAsset]
    let maps: [CDFMap]
    let characters: [CDFCharacter]
    let extensionPayload: [String: JSONValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CDFCodingKey.self)
        folders = try container.decodeIfPresent(
            [CDFFolder].self,
            forKey: .folders
        ) ?? []
        records = try container.decodeIfPresent(
            [CDFRecord].self,
            forKey: .records
        ) ?? []
        relationships = try container.decodeIfPresent(
            [CDFRelationship].self,
            forKey: .relationships
        ) ?? []
        assets = try container.decodeIfPresent(
            [CDFAsset].self,
            forKey: .assets
        ) ?? []
        maps = try container.decodeIfPresent(
            [CDFMap].self,
            forKey: .maps
        ) ?? []
        characters = try container.decodeIfPresent(
            [CDFCharacter].self,
            forKey: .characters
        ) ?? []
        extensionPayload = try container.extensionPayload(
            excluding: [
                .folders,
                .records,
                .relationships,
                .assets,
                .maps,
                .characters
            ]
        )
    }
}

struct CDFFolder: Decodable, Sendable {
    let id: String
    let name: String
    let parentID: String?
    let extensionPayload: [String: JSONValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CDFCodingKey.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        parentID = try container.decodeIfPresent(String.self, forKey: .parentID)
        extensionPayload = try container.extensionPayload(
            excluding: [.id, .name, .parentID]
        )
    }
}

struct CDFRecord: Decodable, Sendable {
    let id: String
    let fileTypeID: String
    let folderID: String?
    let fields: [CDFField]
    let extensionPayload: [String: JSONValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CDFCodingKey.self)
        id = try container.decode(String.self, forKey: .id)
        fileTypeID = try container.decode(String.self, forKey: .fileTypeID)
        folderID = try container.decodeIfPresent(String.self, forKey: .folderID)
        fields = try container.decodeIfPresent(
            [CDFField].self,
            forKey: .fields
        ) ?? []
        extensionPayload = try container.extensionPayload(
            excluding: [.id, .fileTypeID, .folderID, .fields]
        )
    }
}

struct CDFField: Decodable, Sendable {
    let id: String
    let value: JSONValue
    let extensionPayload: [String: JSONValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CDFCodingKey.self)
        id = try container.decode(String.self, forKey: .id)
        value = try container.decode(JSONValue.self, forKey: .value)
        extensionPayload = try container.extensionPayload(
            excluding: [.id, .value]
        )
    }
}

struct CDFRelationship: Decodable, Sendable {
    let id: String
    let kind: String
    let sourceRecordID: String
    let targetRecordIDs: [String]
    let extensionPayload: [String: JSONValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CDFCodingKey.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(String.self, forKey: .kind)
        sourceRecordID = try container.decode(
            String.self,
            forKey: .sourceRecordID
        )
        targetRecordIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .targetRecordIDs
        ) ?? []
        extensionPayload = try container.extensionPayload(
            excluding: [
                .id,
                .kind,
                .sourceRecordID,
                .targetRecordIDs
            ]
        )
    }
}

struct CDFAsset: Decodable, Sendable {
    let id: String
    let relativePath: String
    let mediaType: String?
    let extensionPayload: [String: JSONValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CDFCodingKey.self)
        id = try container.decode(String.self, forKey: .id)
        relativePath = try container.decode(String.self, forKey: .relativePath)
        mediaType = try container.decodeIfPresent(
            String.self,
            forKey: .mediaType
        )
        extensionPayload = try container.extensionPayload(
            excluding: [.id, .relativePath, .mediaType]
        )
    }
}

struct CDFMap: Decodable, Sendable {
    let id: String
    let recordID: String
    let assetID: String?
    let extensionPayload: [String: JSONValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CDFCodingKey.self)
        id = try container.decode(String.self, forKey: .id)
        recordID = try container.decode(String.self, forKey: .recordID)
        assetID = try container.decodeIfPresent(String.self, forKey: .assetID)
        extensionPayload = try container.extensionPayload(
            excluding: [.id, .recordID, .assetID]
        )
    }
}

struct CDFCharacter: Decodable, Sendable {
    let id: String
    let recordID: String
    let portraitAssetID: String?
    let extensionPayload: [String: JSONValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CDFCodingKey.self)
        id = try container.decode(String.self, forKey: .id)
        recordID = try container.decode(String.self, forKey: .recordID)
        portraitAssetID = try container.decodeIfPresent(
            String.self,
            forKey: .portraitAssetID
        )
        extensionPayload = try container.extensionPayload(
            excluding: [.id, .recordID, .portraitAssetID]
        )
    }
}

private struct CDFCodingKey: CodingKey, Hashable, Sendable {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }

    static let cdfVersion = CDFCodingKey("cdfVersion")
    static let project = CDFCodingKey("project")
    static let fileTypes = CDFCodingKey("fileTypes")
    static let content = CDFCodingKey("content")
    static let id = CDFCodingKey("id")
    static let title = CDFCodingKey("title")
    static let summary = CDFCodingKey("summary")
    static let system = CDFCodingKey("system")
    static let rootFolderID = CDFCodingKey("rootFolderID")
    static let currentSceneRecordID = CDFCodingKey("currentSceneRecordID")
    static let playerCharacterRecordID = CDFCodingKey(
        "playerCharacterRecordID"
    )
    static let name = CDFCodingKey("name")
    static let recordKind = CDFCodingKey("recordKind")
    static let fields = CDFCodingKey("fields")
    static let valueType = CDFCodingKey("valueType")
    static let required = CDFCodingKey("required")
    static let folders = CDFCodingKey("folders")
    static let records = CDFCodingKey("records")
    static let relationships = CDFCodingKey("relationships")
    static let assets = CDFCodingKey("assets")
    static let maps = CDFCodingKey("maps")
    static let characters = CDFCodingKey("characters")
    static let parentID = CDFCodingKey("parentID")
    static let fileTypeID = CDFCodingKey("fileTypeID")
    static let folderID = CDFCodingKey("folderID")
    static let value = CDFCodingKey("value")
    static let kind = CDFCodingKey("kind")
    static let sourceRecordID = CDFCodingKey("sourceRecordID")
    static let targetRecordIDs = CDFCodingKey("targetRecordIDs")
    static let relativePath = CDFCodingKey("relativePath")
    static let mediaType = CDFCodingKey("mediaType")
    static let recordID = CDFCodingKey("recordID")
    static let assetID = CDFCodingKey("assetID")
    static let portraitAssetID = CDFCodingKey("portraitAssetID")
}

private extension KeyedDecodingContainer where Key == CDFCodingKey {
    func extensionPayload(
        excluding knownKeys: Set<CDFCodingKey>
    ) throws -> [String: JSONValue] {
        try allKeys.reduce(into: [:]) { payload, key in
            guard knownKeys.contains(key) == false else { return }
            payload[key.stringValue] = try decode(JSONValue.self, forKey: key)
        }
    }
}
