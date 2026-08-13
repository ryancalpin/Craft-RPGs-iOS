import Foundation

enum OpenRouterWire {
    struct Request: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
        let tools: [Tool]
        let responseFormat: ResponseFormat

        private enum CodingKeys: String, CodingKey {
            case model
            case messages
            case stream
            case tools
            case responseFormat = "response_format"
        }
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct Tool: Encodable {
        let type = "function"
        let function: Function
    }

    struct Function: Encodable {
        let name: String
        let description: String
        let parameters: ObjectSchema
        let strict = true
    }

    struct ResponseFormat: Encodable {
        let type = "json_schema"
        let jsonSchema: JSONSchema

        private enum CodingKeys: String, CodingKey {
            case type
            case jsonSchema = "json_schema"
        }
    }

    struct JSONSchema: Encodable {
        let name = "rpgplayer_turn_envelope"
        let strict = true
        let schema: ObjectSchema

        private enum CodingKeys: String, CodingKey {
            case name
            case strict
            case schema = "schema"
        }
    }

    struct ObjectSchema: Encodable {
        let type = "object"
        let properties: [String: PropertySchema]
        let required: [String]
        let additionalProperties = false
    }

    struct PropertySchema: Encodable {
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
            try container.encodeIfPresent(
                additionalProperties,
                forKey: .additionalProperties
            )
            try container.encodeIfPresent(items, forKey: .items)
        }
    }

    struct ModelsResponse: Decodable {
        let data: [Model]
    }

    struct Model: Decodable {
        let id: String
    }

    struct Chunk: Decodable {
        let choices: [Choice]
        let usage: Usage?
    }

    struct Choice: Decodable {
        let delta: Delta
        let finishReason: String?

        private enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Decodable {
        let content: String?
        let refusal: String?
        let toolCalls: [ToolCall]?

        private enum CodingKeys: String, CodingKey {
            case content
            case refusal
            case toolCalls = "tool_calls"
        }
    }

    struct ToolCall: Decodable {
        let index: Int
        let id: String?
        let function: FunctionDelta
    }

    struct FunctionDelta: Decodable {
        let name: String?
        let arguments: String?
    }

    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?
        let promptTokensDetails: PromptTokensDetails?

        private enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case promptTokensDetails = "prompt_tokens_details"
        }
    }

    struct PromptTokensDetails: Decodable {
        let cachedTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case cachedTokens = "cached_tokens"
        }
    }
}
