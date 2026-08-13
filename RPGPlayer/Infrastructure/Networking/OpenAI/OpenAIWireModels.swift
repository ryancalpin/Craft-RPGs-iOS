import Foundation

enum OpenAIWire {
    struct Request: Encodable {
        let model: String
        let input: [InputItem]
        let stream: Bool
        let tools: [Tool]
        let text: TextConfiguration
    }

    struct InputItem: Encodable {
        let role: String
        let content: [Content]
    }

    struct Content: Encodable {
        let type: String
        let text: String
    }

    struct TextConfiguration: Encodable {
        let format: JSONSchemaFormat
    }

    struct JSONSchemaFormat: Encodable {
        let type = "json_schema"
        let name = "rpgplayer_turn_envelope"
        let strict = true
        let schema: ObjectSchema
    }

    struct Tool: Encodable {
        let type = "function"
        let name: String
        let description: String
        let parameters: ObjectSchema
        let strict = true
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

    struct StreamEvent: Decodable {
        let type: String
        let delta: String?
        let item: OutputItem?
        let itemID: String?
        let arguments: String?
        let response: CompletedResponse?
        let error: ErrorPayload?

        private enum CodingKeys: String, CodingKey {
            case type
            case delta
            case item
            case itemID = "item_id"
            case arguments
            case response
            case error
        }
    }

    struct OutputItem: Decodable {
        let type: String
        let itemID: String?
        let callID: String?
        let name: String?

        private enum CodingKeys: String, CodingKey {
            case type
            case itemID = "id"
            case callID = "call_id"
            case name
        }
    }

    struct CompletedResponse: Decodable {
        let status: String?
        let incompleteDetails: IncompleteDetails?
        let usage: Usage?

        private enum CodingKeys: String, CodingKey {
            case status
            case incompleteDetails = "incomplete_details"
            case usage
        }
    }

    struct IncompleteDetails: Decodable {
        let reason: String?
    }

    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let inputTokensDetails: InputTokensDetails?

        private enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case inputTokensDetails = "input_tokens_details"
        }
    }

    struct InputTokensDetails: Decodable {
        let cachedTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case cachedTokens = "cached_tokens"
        }
    }

    struct ErrorPayload: Decodable {
        let code: String?
        let message: String?
    }
}
