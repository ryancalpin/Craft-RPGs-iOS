import Foundation

struct ProviderNativeToolProperty: Sendable {
    let type: String
    let description: String

    init(type: String, description: String) {
        self.type = type
        self.description = description
    }
}

struct ProviderNativeToolDefinition: Sendable {
    let name: String
    let description: String
    let properties: [String: ProviderNativeToolProperty]
    let required: [String]

    init(
        name: String,
        description: String,
        properties: [String: String],
        required: [String],
        propertyTypes: [String: String] = [:]
    ) {
        self.name = name
        self.description = description
        self.properties = Dictionary(uniqueKeysWithValues: properties.map {
            key, propertyDescription in
            (
                key,
                ProviderNativeToolProperty(
                    type: propertyTypes[key] ?? "string",
                    description: propertyDescription
                )
            )
        })
        self.required = required
    }
}

enum ProviderNativeToolCatalog {
    static let definitions: [ProviderNativeToolDefinition] = [
        ProviderNativeToolDefinition(
            name: "readRecord",
            description: "Read one imported campaign record.",
            properties: ["recordID": "The imported record identifier."],
            required: ["recordID"]
        ),
        ProviderNativeToolDefinition(
            name: "searchRecords",
            description: "Search imported campaign records.",
            properties: ["query": "A bounded search query."],
            required: ["query"]
        ),
        ProviderNativeToolDefinition(
            name: "patchRecord",
            description: "Propose a bounded field patch for one record.",
            properties: [
                "recordID": "The imported record identifier.",
                "fieldsJSON": "A bounded JSON object of proposed fields."
            ],
            required: ["recordID", "fieldsJSON"]
        ),
        ProviderNativeToolDefinition(
            name: "requestRoll",
            description: "Request a player-visible dice roll.",
            properties: [
                "expression": "A bounded dice expression.",
                "prompt": "Why the roll is needed."
            ],
            required: ["expression", "prompt"]
        ),
        ProviderNativeToolDefinition(
            name: "updateScene",
            description: "Propose a scene change.",
            properties: [
                "sceneRecordID": "The imported scene identifier.",
                "title": "The proposed scene title.",
                "summary": "The proposed scene summary."
            ],
            required: ["sceneRecordID", "title", "summary"]
        ),
        ProviderNativeToolDefinition(
            name: "updateClock",
            description: "Propose a bounded campaign clock update.",
            properties: [
                "clockRecordID": "The imported clock identifier.",
                "current": "The proposed current value.",
                "maximum": "The clock maximum."
            ],
            required: ["clockRecordID", "current", "maximum"],
            propertyTypes: ["current": "integer", "maximum": "integer"]
        ),
        ProviderNativeToolDefinition(
            name: "suggestVoice",
            description: "Suggest a voice style for an imported character.",
            properties: [
                "characterRecordID": "The imported character identifier.",
                "styleDescription": "A bounded style description."
            ],
            required: ["characterRecordID", "styleDescription"]
        ),
        ProviderNativeToolDefinition(
            name: "attachAsset",
            description: "Propose attaching an imported or generated asset.",
            properties: [
                "assetID": "The asset identifier.",
                "targetRecordID": "The imported target record identifier.",
                "fieldID": "The target field identifier."
            ],
            required: ["assetID", "targetRecordID", "fieldID"]
        )
    ]

    static let names = Set(definitions.map(\.name))
}
