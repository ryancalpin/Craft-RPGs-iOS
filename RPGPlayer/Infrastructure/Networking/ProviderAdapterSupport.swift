import Foundation

enum ProviderAdapterSupport {
    static func context(for request: TurnRequest) -> String {
        request.context.sections.map { section in
            let items = section.items.map { item in [item.name, item.text].compactMap { $0 }.joined(separator: ": ") }.joined(separator: "\n")
            return "[\(section.kind.rawValue)]\n\(items)"
        }.joined(separator: "\n\n")
    }

    static func normalizedEnvelopeData(from data: Data) throws -> Data {
        try normalizeEnvelopeData(from: data, anthropicEventDataIsString: false)
    }

    static func normalizedAnthropicEnvelopeData(from data: Data) throws -> Data {
        try normalizeEnvelopeData(from: data, anthropicEventDataIsString: true)
    }

    private static func normalizeEnvelopeData(
        from data: Data,
        anthropicEventDataIsString: Bool
    ) throws -> Data {
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case .object(var root) = decoded, case .object(var envelope) = root["envelope"], case .array(let proposedEvents) = envelope["proposedEvents"] else { return data }
        var normalizedEvents: [JSONValue] = []
        for proposedEvent in proposedEvents {
            guard case .object(var event) = proposedEvent else { throw ProviderError.malformedResponse }
            if anthropicEventDataIsString {
                guard case .string(let encodedData) = event["data"],
                      encodedData.utf8.count <= ProviderToolArguments.maximumEncodedBytes,
                      let eventData = encodedData.data(using: .utf8),
                      case .object(let decodedData) = try JSONDecoder().decode(JSONValue.self, from: eventData) else {
                    throw ProviderError.malformedResponse
                }
                event["data"] = .object(decodedData)
            }
            if case .some(.string("recordPatch")) = event["type"] {
                guard case .object(var eventData) = event["data"], let fields = eventData["fields"] else { throw ProviderError.malformedResponse }
                if case .string(let encodedFields) = fields {
                    guard let fieldsData = encodedFields.data(using: .utf8), let decodedFields = try? JSONDecoder().decode([String: JSONValue].self, from: fieldsData) else { throw ProviderError.malformedResponse }
                    eventData["fields"] = .object(decodedFields); event["data"] = .object(eventData)
                }
            }
            normalizedEvents.append(.object(event))
        }
        envelope["proposedEvents"] = .array(normalizedEvents); root["envelope"] = .object(envelope)
        return try JSONEncoder().encode(JSONValue.object(root))
    }

    static func encodedArguments(_ values: [String: JSONValue]) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(values), as: UTF8.self)
    }

    static func normalized(_ error: Error) -> ProviderError {
        if let error = error as? ProviderError { return error }
        if error is CancellationError || Task.isCancelled { return .cancelled }
        guard let error = error as? StreamingHTTPError else { return .malformedResponse }
        switch error {
        case .httpStatus(401), .httpStatus(403): return .invalidCredential
        case .httpStatus(429): return .rateLimited(retryAfter: nil)
        case .httpStatus(let status): return .serviceFailure(statusCode: status)
        case .transport: return .connectivity
        case .invalidResponse, .malformedUTF8, .truncatedFrame, .frameTooLarge: return .malformedResponse
        }
    }
}
