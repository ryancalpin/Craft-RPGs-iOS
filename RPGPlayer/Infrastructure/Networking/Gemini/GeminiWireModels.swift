import Foundation

enum GeminiWire {
    struct Request: Encodable {
        let contents: [Content]
        let systemInstruction: Content
        let tools: [Tool]
        let generationConfig: GenerationConfig

        private enum CodingKeys: String, CodingKey {
            case contents
            case systemInstruction
            case tools
            case generationConfig
        }
    }

    struct Content: Encodable {
        let role: String?
        let parts: [Part]
    }

    struct Part: Encodable {
        let text: String?

        init(text: String) { self.text = text }
    }

    struct Tool: Encodable {
        let functionDeclarations: [FunctionDeclaration]

        private enum CodingKeys: String, CodingKey {
            case functionDeclarations
        }
    }

    struct FunctionDeclaration: Encodable {
        let name: String
        let description: String
        let parameters: Schema
    }

    struct Schema: Encodable {
        let type = "OBJECT"
        let properties: [String: PropertySchema]
        let required: [String]
    }

    struct PropertySchema: Encodable {
        let type: String
        let description: String
    }

    struct GenerationConfig: Encodable {
        let responseMimeType = "application/json"
        let responseJsonSchema: ResponseObjectSchema
    }

    struct ResponseObjectSchema: Encodable {
        let type = "object"
        let properties: [String: ResponsePropertySchema]
        let required: [String]
        let additionalProperties = false
    }

    struct ResponsePropertySchema: Encodable {
        let type: String
        let description: String
        let properties: [String: ResponsePropertySchema]?
        let required: [String]?
        let additionalProperties: Bool?
        let items: ResponsePropertySchema?
        let nullable: Bool

        init(
            type: String,
            description: String,
            properties: [String: ResponsePropertySchema]? = nil,
            required: [String]? = nil,
            additionalProperties: Bool? = nil,
            items: ResponsePropertySchema? = nil,
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
        let models: [Model]
    }

    struct Model: Decodable {
        let name: String
        let displayName: String?
        let inputTokenLimit: Int?
        let outputTokenLimit: Int?

        private enum CodingKeys: String, CodingKey {
            case name
            case displayName
            case inputTokenLimit
            case outputTokenLimit
        }
    }

    struct StreamChunk: Decodable {
        let candidates: [Candidate]?
        let promptFeedback: PromptFeedback?
        let usageMetadata: UsageMetadata?

        private enum CodingKeys: String, CodingKey {
            case candidates
            case promptFeedback
            case usageMetadata
        }
    }

    struct Candidate: Decodable {
        let content: ContentResponse?
        let finishReason: String?

        private enum CodingKeys: String, CodingKey {
            case content
            case finishReason
        }
    }

    struct ContentResponse: Decodable {
        let parts: [ResponsePart]?
    }

    struct ResponsePart: Decodable {
        let text: String?
        let functionCall: FunctionCall?
    }

    struct FunctionCall: Decodable {
        let name: String
        let args: [String: JSONValue]?
        let id: String?
    }

    struct PromptFeedback: Decodable {
        let blockReason: String?
    }

    struct UsageMetadata: Decodable {
        let promptTokenCount: Int?
        let candidatesTokenCount: Int?
        let cachedContentTokenCount: Int?
    }
}
