import Foundation

public actor OpenAIProvider: AIProvider {
    public nonisolated let id: ProviderID = .openAI

    public static let defaultBaseURL = URL(string: "https://api.openai.com/v1")!

    private let credentialReader: any ProviderCredentialReader
    private let credentialReference: ProviderCredentialReference
    private let baseURL: URL
    private let baseRequest: URLRequest?
    private let httpClient: StreamingHTTPClient
    private var activeStreams: [UUID: OpenAIStreamDriver] = [:]

    public init(
        credentialReader: any ProviderCredentialReader,
        credentialReference: ProviderCredentialReference? = nil,
        baseURL: URL = OpenAIProvider.defaultBaseURL
    ) {
        self.credentialReader = credentialReader
        self.credentialReference = credentialReference ?? Self.defaultReference
        self.baseURL = baseURL
        baseRequest = nil
        httpClient = .live()
    }

    init(
        credentialReader: any ProviderCredentialReader,
        credentialReference: ProviderCredentialReference? = nil,
        baseRequest: URLRequest,
        httpClient: StreamingHTTPClient
    ) {
        self.credentialReader = credentialReader
        self.credentialReference = credentialReference ?? Self.defaultReference
        self.baseURL = baseRequest.url?.deletingLastPathComponent()
            ?? Self.defaultBaseURL
        self.baseRequest = baseRequest
        self.httpClient = httpClient
    }

    public func models() async throws -> [ProviderModel] {
        let credential = try await credential()
        var request = makeRequest(path: "models")
        addAuthentication(credential, to: &request)

        do {
            let data = try await httpClient.boundedData(for: request)
            let response = try JSONDecoder().decode(
                OpenAIWire.ModelsResponse.self,
                from: data
            )
            let discovered = response.data.compactMap {
                Self.model(for: $0.id)
            }
            return discovered.isEmpty ? Self.fallbackModels : discovered
        } catch let error as ProviderError {
            throw error
        } catch {
            let normalized = Self.normalize(error)
            switch normalized {
            case .invalidCredential, .cancelled:
                throw normalized
            default:
                return Self.fallbackModels
            }
        }
    }

    public func streamTurn(
        _ request: TurnRequest
    ) async throws -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        let credential = try await credential()
        if let previous = activeStreams.removeValue(forKey: request.requestID) {
            await previous.cancel()
        }

        var urlRequest = makeRequest(path: "responses")
        addAuthentication(credential, to: &urlRequest)
        urlRequest.httpBody = try Self.requestBody(for: request)

        let driver = OpenAIStreamDriver(
            client: httpClient,
            request: urlRequest,
            requestID: request.requestID,
            onTerminal: { [weak self] in
                await self?.removeActiveStream(requestID: request.requestID)
            }
        )
        activeStreams[request.requestID] = driver

        let source = AsyncThrowingStream<ProviderStreamEvent, Error>(
            unfolding: { [weak self, driver] in
                do {
                    return try await driver.next()
                } catch {
                    await driver.cancel()
                    await self?.removeActiveStream(requestID: request.requestID)
                    throw Self.normalize(error)
                }
            }
        )
        return ProviderStreamContract.enforcing(
            source,
            onCancel: { [weak self] in
                await self?.cancel(requestID: request.requestID)
            }
        )
    }

    public func cancel(requestID: UUID) async {
        guard let driver = activeStreams.removeValue(forKey: requestID) else {
            return
        }
        await driver.cancel()
    }

    private func removeActiveStream(requestID: UUID) {
        activeStreams.removeValue(forKey: requestID)
    }

    private func credential() async throws -> String {
        do {
            let data = try await credentialReader.credentialData(
                for: credentialReference
            )
            guard let value = String(data: data, encoding: .utf8),
                  value.trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty == false else {
                throw ProviderError.invalidCredential
            }
            return value
        } catch let error as ProviderError {
            throw error
        } catch is CancellationError {
            throw ProviderError.cancelled
        } catch {
            if Task.isCancelled {
                throw ProviderError.cancelled
            }
            throw ProviderError.invalidCredential
        }
    }

    private func makeRequest(path: String) -> URLRequest {
        var request = baseRequest ?? URLRequest(
            url: baseURL.appendingPathComponent(path)
        )
        if baseRequest != nil {
            request.url = baseURL.appendingPathComponent(path)
        }
        request.httpMethod = path == "models" ? "GET" : "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        return request
    }

    private func addAuthentication(
        _ credential: String,
        to request: inout URLRequest
    ) {
        request.setValue(
            "Bearer \(credential)",
            forHTTPHeaderField: "Authorization"
        )
    }

    private static func requestBody(for request: TurnRequest) throws -> Data {
        let context = request.context.sections.map { section in
            let items = section.items.map { item in
                [item.name, item.text].compactMap { $0 }.joined(separator: ": ")
            }.joined(separator: "\n")
            return "[\(section.kind.rawValue)]\n\(items)"
        }.joined(separator: "\n\n")
        let input = [
            OpenAIWire.InputItem(
                role: "system",
                content: [
                    OpenAIWire.Content(
                        type: "input_text",
                        text: "Return only the versioned RPGPlayer turn envelope.\n\(context)"
                    )
                ]
            ),
            OpenAIWire.InputItem(
                role: "user",
                content: [
                    OpenAIWire.Content(
                        type: "input_text",
                        text: request.action.text
                    )
                ]
            )
        ]
        let body = OpenAIWire.Request(
            model: Self.fallbackModels[0].id,
            input: input,
            stream: true,
            tools: Self.tools,
            text: OpenAIWire.TextConfiguration(
                format: OpenAIWire.JSONSchemaFormat(
                    schema: Self.envelopeSchema
                )
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(body)
    }

    private static let defaultReference: ProviderCredentialReference = {
        try! ProviderCredentialReference(providerID: .openAI)
    }()

    private static let fallbackModels: [ProviderModel] = [
        try! ProviderModel(
            providerID: .openAI,
            id: "gpt-5.1",
            displayName: "GPT-5.1",
            contextWindowTokens: 400_000,
            maximumOutputTokens: 128_000,
            supportsTools: true,
            supportsStructuredOutput: true
        ),
        try! ProviderModel(
            providerID: .openAI,
            id: "gpt-4.1",
            displayName: "GPT-4.1",
            contextWindowTokens: 1_047_576,
            maximumOutputTokens: 32_768,
            supportsTools: true,
            supportsStructuredOutput: true
        )
    ]

    private static func model(for id: String) -> ProviderModel? {
        if let fallback = fallbackModels.first(where: { $0.id == id }) {
            return fallback
        }
        return try? ProviderModel(
            providerID: .openAI,
            id: id,
            displayName: id,
            contextWindowTokens: 128_000,
            maximumOutputTokens: 16_000,
            supportsTools: true,
            supportsStructuredOutput: true
        )
    }

    private static let tools: [OpenAIWire.Tool] =
        ProviderNativeToolCatalog.definitions.map { definition in
            OpenAIWire.Tool(
                name: definition.name,
                description: definition.description,
                parameters: OpenAIWire.ObjectSchema(
                    properties: definition.properties.mapValues {
                        OpenAIWire.PropertySchema(
                            type: $0.type,
                            description: $0.description
                        )
                    },
                    required: definition.required
                )
            )
        }

    private static func stringSchema(
        _ description: String,
        nullable: Bool = false
    ) -> OpenAIWire.PropertySchema {
        OpenAIWire.PropertySchema(
            type: "string",
            description: description,
            nullable: nullable
        )
    }

    private static func integerSchema(
        _ description: String,
        nullable: Bool = false
    ) -> OpenAIWire.PropertySchema {
        OpenAIWire.PropertySchema(
            type: "integer",
            description: description,
            nullable: nullable
        )
    }

    private static func objectSchema(
        _ description: String,
        properties: [String: OpenAIWire.PropertySchema],
        required: [String],
        nullable: Bool = false
    ) -> OpenAIWire.PropertySchema {
        OpenAIWire.PropertySchema(
            type: "object",
            description: description,
            properties: properties,
            required: required,
            additionalProperties: false,
            nullable: nullable
        )
    }

    private static func arraySchema(
        _ description: String,
        item: OpenAIWire.PropertySchema
    ) -> OpenAIWire.PropertySchema {
        OpenAIWire.PropertySchema(
            type: "array",
            description: description,
            items: item
        )
    }

    private static let envelopeSchema: OpenAIWire.ObjectSchema = {
        let nullableString = { (description: String) in
            stringSchema(description, nullable: true)
        }
        let storyBlock = objectSchema(
            "A bounded narration block.",
            properties: [
                "id": stringSchema("The story block identifier."),
                "kind": stringSchema("The narration or dialogue kind."),
                "speakerRecordID": nullableString(
                    "The optional imported speaker record identifier."
                ),
                "speakerName": nullableString("The optional speaker name."),
                "mood": nullableString("The optional presentation mood."),
                "text": stringSchema("The bounded story text.")
            ],
            required: [
                "id", "kind", "speakerRecordID", "speakerName", "mood", "text"
            ]
        )
        let beat = objectSchema(
            "A bounded visual-novel beat.",
            properties: [
                "id": stringSchema("The beat identifier."),
                "kind": stringSchema("The title, narration, or dialogue kind."),
                "title": nullableString("The optional beat title."),
                "subtitle": nullableString("The optional beat subtitle."),
                "speaker": nullableString("The optional beat speaker."),
                "mood": nullableString("The optional beat mood."),
                "text": stringSchema("The bounded beat text.")
            ],
            required: ["id", "kind", "title", "subtitle", "speaker", "mood", "text"]
        )
        let eventData = objectSchema(
            "The versioned data for one proposed campaign event.",
            properties: [
                "recordID": nullableString("A record patch target."),
                "fields": stringSchema(
                    "A bounded JSON-encoded object of arbitrary campaign fields.",
                    nullable: true
                ),
                "rollID": nullableString("The requested roll identifier."),
                "expression": nullableString("The requested dice expression."),
                "prompt": nullableString("The reason for the requested roll."),
                "sceneRecordID": nullableString("The proposed scene record identifier."),
                "title": nullableString("The proposed scene title."),
                "summary": nullableString("The proposed scene summary."),
                "clockRecordID": nullableString("The campaign clock identifier."),
                "current": integerSchema("The proposed clock value.", nullable: true),
                "maximum": integerSchema("The clock maximum.", nullable: true),
                "characterRecordID": nullableString("The character record identifier."),
                "styleDescription": nullableString("The suggested voice style."),
                "assetID": nullableString("The asset identifier."),
                "targetRecordID": nullableString("The asset target record identifier."),
                "fieldID": nullableString("The asset target field identifier.")
            ],
            required: [
                "recordID", "fields", "rollID", "expression", "prompt",
                "sceneRecordID", "title", "summary", "clockRecordID", "current",
                "maximum", "characterRecordID", "styleDescription", "assetID",
                "targetRecordID", "fieldID"
            ]
        )
        let proposedEvent = objectSchema(
            "A typed, proposed campaign event.",
            properties: [
                "type": stringSchema("The proposed event discriminator."),
                "data": eventData
            ],
            required: ["type", "data"]
        )
        let decisionOption = objectSchema(
            "A player decision option.",
            properties: [
                "title": stringSchema("The option title."),
                "detail": stringSchema("The option detail.")
            ],
            required: ["title", "detail"]
        )
        let pendingDecision = objectSchema(
            "The optional pending player decision.",
            properties: [
                "id": stringSchema("The decision identifier."),
                "prompt": stringSchema("The decision prompt."),
                "options": arraySchema("The bounded decision options.", item: decisionOption)
            ],
            required: ["id", "prompt", "options"],
            nullable: true
        )
        let voiceSegment = objectSchema(
            "A bounded voice segment.",
            properties: [
                "id": stringSchema("The voice segment identifier."),
                "sourceStoryBlockID": stringSchema("The source story block identifier."),
                "speakerRecordID": nullableString("The optional imported speaker identifier."),
                "speakerName": stringSchema("The speaker name."),
                "text": stringSchema("The bounded spoken text.")
            ],
            required: ["id", "sourceStoryBlockID", "speakerRecordID", "speakerName", "text"]
        )
        let usage = objectSchema(
            "The optional normalized provider usage.",
            properties: [
                "inputTokens": integerSchema("The input token count."),
                "outputTokens": integerSchema("The output token count."),
                "cachedInputTokens": integerSchema("The optional cached input count.", nullable: true)
            ],
            required: ["inputTokens", "outputTokens", "cachedInputTokens"],
            nullable: true
        )
        let envelope = objectSchema(
            "The complete version 1 RPGPlayer turn envelope.",
            properties: [
                "requestID": stringSchema("The request identifier."),
                "narration": arraySchema("The bounded narration blocks.", item: storyBlock),
                "beats": arraySchema("The bounded visual-novel beats.", item: beat),
                "proposedEvents": arraySchema("The bounded proposed events.", item: proposedEvent),
                "pendingDecision": pendingDecision,
                "voiceSegments": arraySchema("The bounded voice segments.", item: voiceSegment),
                "usage": usage
            ],
            required: [
                "requestID", "narration", "beats", "proposedEvents", "pendingDecision",
                "voiceSegments", "usage"
            ]
        )
        return OpenAIWire.ObjectSchema(
            properties: [
                "schemaVersion": integerSchema("The versioned envelope schema number."),
                "envelope": envelope
            ],
            required: ["schemaVersion", "envelope"]
        )
    }()

    nonisolated private static func normalize(_ error: Error) -> ProviderError {
        if let error = error as? ProviderError { return error }
        if error is CancellationError || Task.isCancelled {
            return .cancelled
        }
        guard let error = error as? StreamingHTTPError else {
            return .malformedResponse
        }
        switch error {
        case .httpStatus(401), .httpStatus(403):
            return .invalidCredential
        case .httpStatus(429):
            return .rateLimited(retryAfter: nil)
        case .httpStatus(let status):
            return .serviceFailure(statusCode: status)
        case .transport:
            return .connectivity
        case .invalidResponse, .malformedUTF8, .truncatedFrame,
             .frameTooLarge:
            return .malformedResponse
        }
    }
}

private actor OpenAIStreamDriver {
    private let client: StreamingHTTPClient
    private let request: URLRequest
    private let requestID: UUID
    private let onTerminal: @Sendable () async -> Void
    private var iterator: StreamingHTTPSequence<ServerSentEventDecoder>.AsyncIterator?
    private var pending: [ProviderStreamEvent] = []
    private var calls: [String: CallState] = [:]
    private var text = ""
    private var textBytes = 0
    private var terminal = false
    private var cancelled = false
    private var currentPull: Task<ServerSentEvent?, Error>?

    private struct CallState {
        let callID: String
        let toolName: String
        var arguments: String
        var completed: Bool
    }

    init(
        client: StreamingHTTPClient,
        request: URLRequest,
        requestID: UUID,
        onTerminal: @escaping @Sendable () async -> Void
    ) {
        self.client = client
        self.request = request
        self.requestID = requestID
        self.onTerminal = onTerminal
    }

    func next() async throws -> ProviderStreamEvent? {
        guard cancelled == false else { throw ProviderError.cancelled }
        while pending.isEmpty, terminal == false {
            if iterator == nil {
                iterator = try await client.serverSentEvents(for: request)
                    .makeAsyncIterator()
            }
            do {
                let frame = try await pullFrame()
                guard let frame else { throw ProviderError.malformedResponse }
                try await process(frame)
            } catch is CancellationError {
                throw cancelled ? ProviderError.cancelled : CancellationError()
            }
        }
        return pending.isEmpty ? nil : pending.removeFirst()
    }

    func cancel() async {
        cancelled = true
        currentPull?.cancel()
        await closeTransport()
    }

    private func pullFrame() async throws -> ServerSentEvent? {
        let task = Task { [weak self] in
            guard let self else { return nil }
            return try await self.pullFromIterator()
        }
        currentPull = task
        defer { currentPull = nil }
        return try await task.value
    }

    private func pullFromIterator() async throws -> ServerSentEvent? {
        guard var iterator else { return nil }
        let frame = try await iterator.next()
        self.iterator = iterator
        return frame
    }

    private func process(_ frame: ServerSentEvent) async throws {
        if frame.data == Data("[DONE]".utf8) { return }
        let event: OpenAIWire.StreamEvent
        do {
            event = try JSONDecoder().decode(
                OpenAIWire.StreamEvent.self,
                from: frame.data
            )
        } catch {
            throw ProviderError.malformedResponse
        }

        switch event.type {
        case "response.output_text.delta":
            guard let delta = event.delta else {
                throw ProviderError.malformedResponse
            }
            appendText(delta)
            pending.append(.textDelta(delta))
        case "response.refusal.delta", "response.refusal.done":
            throw ProviderError.safetyRefusal
        case "response.output_item.added":
            try startCall(event.item)
        case "response.function_call_arguments.delta":
            try appendArguments(
                itemID: event.itemID,
                fragment: event.delta
            )
        case "response.function_call_arguments.done":
            try completeCall(
                itemID: event.itemID,
                arguments: event.arguments
            )
        case "response.completed":
            try await finish(event.response)
        case "response.error", "error":
            if event.error?.code == "safety_violation"
                || event.error?.code == "content_filter" {
                throw ProviderError.safetyRefusal
            }
            throw ProviderError.serviceFailure(statusCode: nil)
        default:
            break
        }
    }

    private func startCall(_ item: OpenAIWire.OutputItem?) throws {
        guard let item, item.type == "function_call",
              let itemID = item.itemID,
              let callID = item.callID,
              let toolName = item.name,
              ProviderNativeToolCatalog.names.contains(toolName),
              calls[itemID] == nil else {
            throw ProviderError.malformedResponse
        }
        calls[itemID] = CallState(
            callID: callID,
            toolName: toolName,
            arguments: "",
            completed: false
        )
        pending.append(
            .toolCallStarted(callID: callID, toolName: toolName)
        )
    }

    private func appendArguments(
        itemID: String?,
        fragment: String?
    ) throws {
        guard let itemID, let fragment, var call = calls[itemID],
              call.completed == false else {
            throw ProviderError.malformedResponse
        }
        guard call.arguments.utf8.count + fragment.utf8.count
            <= ProviderToolArguments.maximumEncodedBytes else {
            throw ProviderError.malformedResponse
        }
        call.arguments.append(fragment)
        calls[itemID] = call
        pending.append(
            .toolCallArgumentFragment(
                callID: call.callID,
                fragment: fragment
            )
        )
    }

    private func completeCall(
        itemID: String?,
        arguments: String?
    ) throws {
        guard let itemID, var call = calls[itemID],
              call.completed == false else {
            throw ProviderError.malformedResponse
        }
        if let arguments {
            guard arguments.utf8.count
                <= ProviderToolArguments.maximumEncodedBytes else {
                throw ProviderError.malformedResponse
            }
            call.arguments = arguments
        }
        guard let data = call.arguments.data(using: .utf8) else {
            throw ProviderError.malformedResponse
        }
        let values: [String: JSONValue]
        do {
            values = try JSONDecoder().decode(
                [String: JSONValue].self,
                from: data
            )
        } catch {
            throw ProviderError.malformedResponse
        }
        let parsed: ProviderToolArguments
        do {
            parsed = try ProviderToolArguments(values: values)
        } catch {
            throw ProviderError.malformedResponse
        }
        call.completed = true
        calls[itemID] = call
        pending.append(
            .toolCallCompleted(
                callID: call.callID,
                toolName: call.toolName,
                arguments: parsed
            )
        )
    }

    private func finish(_ response: OpenAIWire.CompletedResponse?) async throws {
        guard terminal == false else { return }
        if let usage = response?.usage,
           let input = usage.inputTokens,
           let output = usage.outputTokens {
            pending.append(
                .usage(
                    ProviderUsage(
                        inputTokens: input,
                        outputTokens: output,
                        cachedInputTokens: usage.inputTokensDetails?.cachedTokens
                    )
                )
            )
        }
        if response?.status == "incomplete" {
            terminal = true
            await closeTransport()
            await onTerminal()
            pending.append(.finished(.maximumOutputTokens))
            return
        }
        if calls.isEmpty == false {
            guard calls.values.allSatisfy(\.completed) else {
                throw ProviderError.malformedResponse
            }
            terminal = true
            await closeTransport()
            await onTerminal()
            pending.append(.finished(.requiresToolResults))
            return
        }
        guard textBytes > 0, let data = text.data(using: .utf8) else {
            throw ProviderError.malformedResponse
        }
        let versioned: VersionedTurnEnvelope
        do {
            let normalizedData = try Self.normalizedEnvelopeData(from: data)
            versioned = try VersionedTurnEnvelope.decode(from: normalizedData)
        } catch {
            throw ProviderError.malformedResponse
        }
        guard versioned.envelope.requestID == requestID else {
            throw ProviderError.malformedResponse
        }
        terminal = true
        await closeTransport()
        await onTerminal()
        pending.append(.finished(.completed(versioned.envelope)))
    }

    private static func normalizedEnvelopeData(from data: Data) throws -> Data {
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case .object(var root) = decoded,
              case .object(var envelope) = root["envelope"],
              case .array(let proposedEvents) = envelope["proposedEvents"] else {
            return data
        }

        var normalizedEvents: [JSONValue] = []
        for proposedEvent in proposedEvents {
            guard case .object(var event) = proposedEvent else {
                throw ProviderError.malformedResponse
            }
            if case .some(.string("recordPatch")) = event["type"] {
                guard case .object(var eventData) = event["data"],
                      let fields = eventData["fields"] else {
                    throw ProviderError.malformedResponse
                }
                if case .string(let encodedFields) = fields {
                    guard let fieldsData = encodedFields.data(using: .utf8),
                          let decodedFields = try? JSONDecoder().decode(
                              [String: JSONValue].self,
                              from: fieldsData
                          ) else {
                        throw ProviderError.malformedResponse
                    }
                    eventData["fields"] = .object(decodedFields)
                    event["data"] = .object(eventData)
                }
            }
            normalizedEvents.append(.object(event))
        }
        envelope["proposedEvents"] = .array(normalizedEvents)
        root["envelope"] = .object(envelope)
        return try JSONEncoder().encode(JSONValue.object(root))
    }

    private func closeTransport() async {
        currentPull?.cancel()
        guard var iterator else { return }
        await iterator.cancel()
        self.iterator = iterator
    }

    private func appendText(_ delta: String) throws {
        textBytes += delta.utf8.count
        guard textBytes <= VersionedTurnEnvelope.maximumEncodedBytes else {
            throw ProviderError.malformedResponse
        }
        text.append(delta)
    }
}
