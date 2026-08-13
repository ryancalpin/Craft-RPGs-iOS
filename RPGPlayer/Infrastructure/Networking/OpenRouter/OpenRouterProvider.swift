import Foundation

public actor OpenRouterProvider: AIProvider {
    public nonisolated let id: ProviderID = .openRouter

    public static let defaultBaseURL = URL(string: "https://openrouter.ai/api/v1")!

    private let credentialReader: any ProviderCredentialReader
    private let credentialReference: ProviderCredentialReference
    private let baseURL: URL
    private let baseRequest: URLRequest?
    private let httpClient: StreamingHTTPClient
    private var activeStreams: [UUID: OpenRouterStreamDriver] = [:]

    public init(
        credentialReader: any ProviderCredentialReader,
        credentialReference: ProviderCredentialReference? = nil,
        baseURL: URL = OpenRouterProvider.defaultBaseURL
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
                OpenRouterWire.ModelsResponse.self,
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

        var urlRequest = makeRequest(path: "chat/completions")
        addAuthentication(credential, to: &urlRequest)
        urlRequest.httpBody = try Self.requestBody(for: request)

        let driver = OpenRouterStreamDriver(
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
        request.setValue(
            "https://rpgplayer.invalid",
            forHTTPHeaderField: "HTTP-Referer"
        )
        request.setValue("RPGPlayer", forHTTPHeaderField: "X-Title")
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
        let body = OpenRouterWire.Request(
            model: Self.fallbackModels[0].id,
            messages: [
                OpenRouterWire.Message(
                    role: "system",
                    content: "Return only the versioned RPGPlayer turn envelope.\n\(context)"
                ),
                OpenRouterWire.Message(
                    role: "user",
                    content: request.action.text
                )
            ],
            stream: true,
            tools: Self.tools,
            responseFormat: OpenRouterWire.ResponseFormat(
                jsonSchema: OpenRouterWire.JSONSchema(
                    schema: Self.envelopeSchema
                )
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(body)
    }

    private static let defaultReference: ProviderCredentialReference = {
        try! ProviderCredentialReference(providerID: .openRouter)
    }()

    private static let fallbackModels: [ProviderModel] = [
        try! ProviderModel(
            providerID: .openRouter,
            id: "openai/gpt-5.1",
            displayName: "OpenAI GPT-5.1 via OpenRouter",
            contextWindowTokens: 400_000,
            maximumOutputTokens: 128_000,
            supportsTools: true,
            supportsStructuredOutput: true
        ),
        try! ProviderModel(
            providerID: .openRouter,
            id: "openai/gpt-4.1-mini",
            displayName: "OpenAI GPT-4.1 mini via OpenRouter",
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
            providerID: .openRouter,
            id: id,
            displayName: id,
            contextWindowTokens: 128_000,
            maximumOutputTokens: 16_000,
            supportsTools: true,
            supportsStructuredOutput: true
        )
    }

    private static let tools: [OpenRouterWire.Tool] =
        ProviderNativeToolCatalog.definitions.map { definition in
            OpenRouterWire.Tool(
                function: OpenRouterWire.Function(
                    name: definition.name,
                    description: definition.description,
                    parameters: OpenRouterWire.ObjectSchema(
                        properties: definition.properties.mapValues {
                            OpenRouterWire.PropertySchema(
                                type: $0.type,
                                description: $0.description
                            )
                        },
                        required: definition.required
                    )
                )
            )
        }

    private static func stringSchema(
        _ description: String,
        nullable: Bool = false
    ) -> OpenRouterWire.PropertySchema {
        OpenRouterWire.PropertySchema(
            type: "string",
            description: description,
            nullable: nullable
        )
    }

    private static func integerSchema(
        _ description: String,
        nullable: Bool = false
    ) -> OpenRouterWire.PropertySchema {
        OpenRouterWire.PropertySchema(
            type: "integer",
            description: description,
            nullable: nullable
        )
    }

    private static func objectSchema(
        _ description: String,
        properties: [String: OpenRouterWire.PropertySchema],
        required: [String],
        nullable: Bool = false
    ) -> OpenRouterWire.PropertySchema {
        OpenRouterWire.PropertySchema(
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
        item: OpenRouterWire.PropertySchema
    ) -> OpenRouterWire.PropertySchema {
        OpenRouterWire.PropertySchema(
            type: "array",
            description: description,
            items: item
        )
    }

    private static let envelopeSchema: OpenRouterWire.ObjectSchema = {
        let nullableString = { (description: String) in
            stringSchema(description, nullable: true)
        }
        let storyBlock = objectSchema(
            "A bounded narration block.",
            properties: [
                "id": stringSchema("The story block identifier."),
                "kind": stringSchema("The narration or dialogue kind."),
                "speakerRecordID": nullableString("The optional imported speaker record identifier."),
                "speakerName": nullableString("The optional speaker name."),
                "mood": nullableString("The optional presentation mood."),
                "text": stringSchema("The bounded story text.")
            ],
            required: ["id", "kind", "speakerRecordID", "speakerName", "mood", "text"]
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
            required: ["requestID", "narration", "beats", "proposedEvents", "pendingDecision", "voiceSegments", "usage"]
        )
        return OpenRouterWire.ObjectSchema(
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

private actor OpenRouterStreamDriver {
    private let client: StreamingHTTPClient
    private let request: URLRequest
    private let requestID: UUID
    private let onTerminal: @Sendable () async -> Void
    private var iterator: StreamingHTTPSequence<ServerSentEventDecoder>.AsyncIterator?
    private var pending: [ProviderStreamEvent] = []
    private var calls: [Int: CallState] = [:]
    private var text = ""
    private var textBytes = 0
    private var terminal = false
    private var cancelled = false
    private var currentPull: Task<ServerSentEvent?, Error>?
    private var nextCompletionSequence = 0

    private struct CallState {
        let callID: String
        let toolName: String
        var arguments: String
        var completed: Bool
        var completionSequence: Int?
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
        let chunk: OpenRouterWire.Chunk
        do {
            chunk = try JSONDecoder().decode(
                OpenRouterWire.Chunk.self,
                from: frame.data
            )
        } catch {
            throw ProviderError.malformedResponse
        }
        for choice in chunk.choices {
            if let refusal = choice.delta.refusal, refusal.isEmpty == false {
                throw ProviderError.safetyRefusal
            }
            if let content = choice.delta.content {
                appendText(content)
                pending.append(.textDelta(content))
            }
            for call in choice.delta.toolCalls ?? [] {
                try process(call)
            }
            if choice.finishReason == "tool_calls" {
                try await finishTools(chunk.usage)
            } else if choice.finishReason == "length" {
                appendUsage(chunk.usage)
                terminal = true
                await closeTransport()
                await onTerminal()
                pending.append(.finished(.maximumOutputTokens))
            } else if choice.finishReason == "stop" {
                try await finishText(chunk.usage)
            }
        }
        if chunk.choices.isEmpty, let usage = chunk.usage {
            appendUsage(usage)
        }
    }

    private func process(_ call: OpenRouterWire.ToolCall) throws {
        if calls[call.index] == nil {
            guard let callID = call.id,
                  let name = call.function.name,
                  ProviderNativeToolCatalog.names.contains(name) else {
                throw ProviderError.malformedResponse
            }
            calls[call.index] = CallState(
                callID: callID,
                toolName: name,
                arguments: "",
                completed: false,
                completionSequence: nil
            )
            pending.append(.toolCallStarted(callID: callID, toolName: name))
        }
        guard var state = calls[call.index], state.completed == false else {
            throw ProviderError.malformedResponse
        }
        if let fragment = call.function.arguments, fragment.isEmpty == false {
            guard state.arguments.utf8.count + fragment.utf8.count
                <= ProviderToolArguments.maximumEncodedBytes else {
                throw ProviderError.malformedResponse
            }
            state.arguments.append(fragment)
            if state.completionSequence == nil,
               Self.isCompleteArguments(state.arguments) {
                state.completionSequence = nextCompletionSequence
                nextCompletionSequence += 1
            }
            pending.append(
                .toolCallArgumentFragment(
                    callID: state.callID,
                    fragment: fragment
                )
            )
        }
        calls[call.index] = state
    }

    private func finishTools(_ usage: OpenRouterWire.Usage?) async throws {
        guard calls.isEmpty == false,
              calls.values.allSatisfy({ $0.completed == false }) else {
            throw ProviderError.malformedResponse
        }
        let orderedIndexes = calls.keys.sorted { left, right in
            let leftSequence = calls[left]?.completionSequence ?? Int.max
            let rightSequence = calls[right]?.completionSequence ?? Int.max
            return (leftSequence, left) < (rightSequence, right)
        }
        for index in orderedIndexes {
            guard var state = calls[index],
                  let data = state.arguments.data(using: .utf8) else {
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
            let arguments: ProviderToolArguments
            do {
                arguments = try ProviderToolArguments(values: values)
            } catch {
                throw ProviderError.malformedResponse
            }
            state.completed = true
            calls[index] = state
            pending.append(
                .toolCallCompleted(
                    callID: state.callID,
                    toolName: state.toolName,
                    arguments: arguments
                )
            )
        }
        appendUsage(usage)
        terminal = true
        await closeTransport()
        await onTerminal()
        pending.append(.finished(.requiresToolResults))
    }

    private func finishText(_ usage: OpenRouterWire.Usage?) async throws {
        appendUsage(usage)
        guard calls.isEmpty, let data = text.data(using: .utf8),
              textBytes > 0 else {
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

    private static func isCompleteArguments(_ arguments: String) -> Bool {
        guard let data = arguments.data(using: .utf8) else { return false }
        return (try? JSONDecoder().decode(
            [String: JSONValue].self,
            from: data
        )) != nil
    }

    private func appendUsage(_ usage: OpenRouterWire.Usage?) {
        guard let usage,
              let input = usage.promptTokens,
              let output = usage.completionTokens else { return }
        pending.append(
            .usage(
                ProviderUsage(
                    inputTokens: input,
                    outputTokens: output,
                    cachedInputTokens: usage.promptTokensDetails?.cachedTokens
                )
            )
        )
    }

    private func appendText(_ delta: String) throws {
        textBytes += delta.utf8.count
        guard textBytes <= VersionedTurnEnvelope.maximumEncodedBytes else {
            throw ProviderError.malformedResponse
        }
        text.append(delta)
    }
}
