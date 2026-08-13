import Foundation

public struct GMToolDefinition: Equatable, Sendable {
    public let tool: GMTool
    public let name: String
    public let requiredArguments: Set<String>
    public let allowedArguments: Set<String>

    public init(
        tool: GMTool,
        requiredArguments: Set<String>,
        allowedArguments: Set<String>
    ) {
        self.tool = tool
        name = tool.rawValue
        self.requiredArguments = requiredArguments
        self.allowedArguments = allowedArguments
    }
}

public struct GMToolRegistry: Sendable {
    public static let all = GMToolRegistry()

    public let definitions: [GMToolDefinition]

    public init() {
        definitions = [
            GMToolDefinition(
                tool: .readRecord,
                requiredArguments: ["recordID"],
                allowedArguments: ["recordID"]
            ),
            GMToolDefinition(
                tool: .searchRecords,
                requiredArguments: ["query"],
                allowedArguments: ["query"]
            ),
            GMToolDefinition(
                tool: .patchRecord,
                requiredArguments: ["recordID", "fieldsJSON"],
                allowedArguments: ["recordID", "fieldsJSON"]
            ),
            GMToolDefinition(
                tool: .requestRoll,
                requiredArguments: ["expression", "prompt"],
                allowedArguments: ["expression", "prompt"]
            ),
            GMToolDefinition(
                tool: .updateScene,
                requiredArguments: ["sceneRecordID", "title", "summary"],
                allowedArguments: ["sceneRecordID", "title", "summary"]
            ),
            GMToolDefinition(
                tool: .updateClock,
                requiredArguments: ["clockRecordID", "current", "maximum"],
                allowedArguments: ["clockRecordID", "current", "maximum"]
            ),
            GMToolDefinition(
                tool: .suggestVoice,
                requiredArguments: ["characterRecordID", "styleDescription"],
                allowedArguments: ["characterRecordID", "styleDescription"]
            ),
            GMToolDefinition(
                tool: .attachAsset,
                requiredArguments: ["assetID", "targetRecordID", "fieldID"],
                allowedArguments: ["assetID", "targetRecordID", "fieldID"]
            )
        ]
    }

    public var names: [String] { definitions.map(\.name) }

    public func resolve(_ name: String) -> GMTool? {
        definitions.first { $0.name == name }?.tool
    }

    public func definition(for tool: GMTool) -> GMToolDefinition {
        switch tool {
        case .readRecord: return definitions[0]
        case .searchRecords: return definitions[1]
        case .patchRecord: return definitions[2]
        case .requestRoll: return definitions[3]
        case .updateScene: return definitions[4]
        case .updateClock: return definitions[5]
        case .suggestVoice: return definitions[6]
        case .attachAsset: return definitions[7]
        }
    }
}
