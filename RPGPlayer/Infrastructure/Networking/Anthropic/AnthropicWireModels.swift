import Foundation

enum AnthropicWire {
    struct Request: Encodable {
        let model: String
        let maxTokens: Int
        let system: String
        let messages: [Message]
        let tools: [Tool]
        let stream: Bool
        let outputConfig: OutputConfig

        private enum CodingKeys: String, CodingKey {
            case model
            case maxTokens = "max_tokens"
            case system
            case messages
            case tools
            case stream
            case outputConfig = "output_config"
        }
    }

    struct OutputConfig: Encodable {
        let format: OutputFormat
    }

    struct OutputFormat: Encodable {
        let type = "json_schema"
        let schema: ObjectSchema
    }

    struct Message: Encodable {
        let role: String
        let content: [TextContent]
    }

    struct TextContent: Encodable {
        let type = "text"
        let text: String
    }

    struct Tool: Encodable, Sendable {
        let name: String
        let description: String
        let inputSchema: ObjectSchema

        private enum CodingKeys: String, CodingKey {
            case name
            case description
            case inputSchema = "input_schema"
        }
    }

    struct ObjectSchema: Encodable, Sendable {
        let type = "object"
        let properties: [String: PropertySchema]
        let required: [String]
        let additionalProperties = false
    }

    final class PropertySchema: Encodable, Sendable {
        let type: String
        let description: String
        let properties: [String: PropertySchema]?
        let required: [String]?
        let additionalProperties: Bool?
        let items: PropertySchema?
        let nullable: Bool

        init(
            type: String,
            description: String,
            properties: [String: PropertySchema]? = nil,
            required: [String]? = nil,
            additionalProperties: Bool? = nil,
            items: PropertySchema? = nil,
            nullable: Bool = false
        ) {
            self.type = type
            self.description = description
            self.properties = properties
            self.required = required
            self.additionalProperties = additionalProperties
            self.items = items
            self.nullable = nullable
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case description
            case properties
            case required
            case additionalProperties
            case items
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if nullable {
                try container.encode([type, "null"], forKey: .type)
            } else {
                try container.encode(type, forKey: .type)
            }
            try container.encode(description, forKey: .description)
            try container.encodeIfPresent(properties, forKey: .properties)
            try container.encodeIfPresent(required, forKey: .required)
            try container.encodeIfPresent(additionalProperties, forKey: .additionalProperties)
            try container.encodeIfPresent(items, forKey: .items)
        }
    }

    struct ModelsResponse: Decodable {
        let data: [Model]
    }

    struct Model: Decodable {
        let id: String
        let displayName: String?

        private enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }

    struct StreamEvent: Decodable {
        let type: String
        let message: MessageStart?
        let index: Int?
        let contentBlock: ContentBlock?
        let delta: Delta?
        let usage: Usage?
        let error: ErrorPayload?

        private enum CodingKeys: String, CodingKey {
            case type
            case message
            case index
            case contentBlock = "content_block"
            case delta
            case usage
            case error
        }
    }

    struct MessageStart: Decodable {
        let usage: Usage?
    }

    struct ContentBlock: Decodable {
        let type: String
        let id: String?
        let name: String?
        let input: [String: JSONValue]?
    }

    struct Delta: Decodable {
        let type: String?
        let text: String?
        let partialJSON: String?
        let stopReason: String?

        private enum CodingKeys: String, CodingKey {
            case type
            case text
            case partialJSON = "partial_json"
            case stopReason = "stop_reason"
        }
    }

    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheReadInputTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
        }
    }

    struct ErrorPayload: Decodable {
        let type: String?
        let message: String?
    }
}
