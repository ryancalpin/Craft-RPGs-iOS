import Foundation

public actor AnthropicProvider: AIProvider {
    public nonisolated let id: ProviderID = .anthropic
    public static let defaultBaseURL = URL(string: "https://api.anthropic.com/v1")!

    private let credentialReader: any ProviderCredentialReader
    private let credentialReference: ProviderCredentialReference
    private let baseURL: URL
    private let baseRequest: URLRequest?
    private let httpClient: StreamingHTTPClient
    private var activeStreams: [UUID: AnthropicStreamDriver] = [:]

    public init(credentialReader: any ProviderCredentialReader, credentialReference: ProviderCredentialReference? = nil, baseURL: URL = AnthropicProvider.defaultBaseURL) {
        self.credentialReader = credentialReader
        self.credentialReference = credentialReference ?? Self.defaultReference
        self.baseURL = baseURL
        self.baseRequest = nil
        self.httpClient = .live()
    }

    init(credentialReader: any ProviderCredentialReader, credentialReference: ProviderCredentialReference? = nil, baseRequest: URLRequest, httpClient: StreamingHTTPClient) {
        self.credentialReader = credentialReader
        self.credentialReference = credentialReference ?? Self.defaultReference
        self.baseURL = baseRequest.url?.deletingLastPathComponent() ?? Self.defaultBaseURL
        self.baseRequest = baseRequest
        self.httpClient = httpClient
    }

    public func models() async throws -> [ProviderModel] {
        let secret = try await credential()
        var request = makeRequest(path: "models")
        authenticate(secret, request: &request)
        do {
            let response = try JSONDecoder().decode(AnthropicWire.ModelsResponse.self, from: try await httpClient.boundedData(for: request))
            let discovered = response.data.compactMap(Self.model(for:))
            return discovered.isEmpty ? Self.fallbackModels : discovered
        } catch let error as ProviderError {
            throw error
        } catch {
            switch ProviderAdapterSupport.normalized(error) {
            case .invalidCredential, .cancelled: throw ProviderAdapterSupport.normalized(error)
            default: return Self.fallbackModels
            }
        }
    }

    public func streamTurn(_ request: TurnRequest) async throws -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        let secret = try await credential()
        if let previous = activeStreams.removeValue(forKey: request.requestID) { await previous.cancel() }
        var urlRequest = makeRequest(path: "messages")
        authenticate(secret, request: &urlRequest)
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try Self.requestBody(for: request)
        let driver = AnthropicStreamDriver(client: httpClient, request: urlRequest, requestID: request.requestID, onTerminal: { [weak self] in await self?.removeActiveStream(requestID: request.requestID) })
        activeStreams[request.requestID] = driver
        let source = AsyncThrowingStream<ProviderStreamEvent, Error>(unfolding: { [weak self, driver] in
            do { return try await driver.next() }
            catch { await driver.cancel(); await self?.removeActiveStream(requestID: request.requestID); throw ProviderAdapterSupport.normalized(error) }
        })
        return ProviderStreamContract.enforcing(source, onCancel: { [weak self] in await self?.cancel(requestID: request.requestID) })
    }

    public func cancel(requestID: UUID) async {
        guard let driver = activeStreams.removeValue(forKey: requestID) else { return }
        await driver.cancel()
    }

    private func removeActiveStream(requestID: UUID) { activeStreams.removeValue(forKey: requestID) }

    private func credential() async throws -> String {
        do {
            let data = try await credentialReader.credentialData(for: credentialReference)
            guard let value = String(data: data, encoding: .utf8), value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { throw ProviderError.invalidCredential }
            return value
        } catch let error as ProviderError { throw error }
        catch is CancellationError { throw ProviderError.cancelled }
        catch { throw Task.isCancelled ? ProviderError.cancelled : ProviderError.invalidCredential }
    }

    private func makeRequest(path: String) -> URLRequest {
        var request = baseRequest ?? URLRequest(url: baseURL.appendingPathComponent(path))
        if baseRequest != nil { request.url = baseURL.appendingPathComponent(path) }
        request.httpMethod = path == "models" ? "GET" : "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        return request
    }

    private func authenticate(_ secret: String, request: inout URLRequest) {
        request.setValue(secret, forHTTPHeaderField: "x-api-key")
    }

    private static func requestBody(for request: TurnRequest) throws -> Data {
        let context = ProviderAdapterSupport.context(for: request)
        let model = request.modelID ?? fallbackModels[0].id
        let maximumOutputTokens = fallbackModels.first(where: { $0.id == model })?.maximumOutputTokens ?? fallbackModels[0].maximumOutputTokens
        let body = AnthropicWire.Request(model: model, maxTokens: maximumOutputTokens, system: "Return only the versioned RPGPlayer turn envelope.\n\(context)", messages: [AnthropicWire.Message(role: "user", content: [AnthropicWire.TextContent(text: request.action.text)])], tools: tools, stream: true, outputConfig: AnthropicWire.OutputConfig(format: AnthropicWire.OutputFormat(schema: envelopeSchema)))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(body)
    }

    private static let defaultReference = try! ProviderCredentialReference(providerID: .anthropic)
    private static let fallbackModels = CuratedProviderModelCatalog.models(
        for: .anthropic
    )

    private static func model(for model: AnthropicWire.Model) -> ProviderModel? {
        try? ProviderModel(providerID: .anthropic, id: model.id, displayName: model.displayName ?? model.id, contextWindowTokens: 200_000, maximumOutputTokens: 64_000, supportsTools: true, supportsStructuredOutput: true)
    }

    private static let tools: [AnthropicWire.Tool] = ProviderNativeToolCatalog.definitions.map { definition in
        AnthropicWire.Tool(name: definition.name, description: definition.description, inputSchema: AnthropicWire.ObjectSchema(properties: definition.properties.mapValues { AnthropicWire.PropertySchema(type: $0.type, description: $0.description) }, required: definition.required))
    }

    private static func stringSchema(_ description: String, nullable: Bool = false) -> AnthropicWire.PropertySchema {
        AnthropicWire.PropertySchema(type: "string", description: description, nullable: nullable)
    }

    private static func optionalStringSchema(_ description: String) -> AnthropicWire.PropertySchema {
        stringSchema(description)
    }

    private static func integerSchema(_ description: String, nullable: Bool = false) -> AnthropicWire.PropertySchema {
        AnthropicWire.PropertySchema(type: "integer", description: description, nullable: nullable)
    }

    private static func optionalIntegerSchema(_ description: String) -> AnthropicWire.PropertySchema {
        integerSchema(description)
    }

    private static func objectSchema(
        _ description: String,
        properties: [String: AnthropicWire.PropertySchema],
        required: [String],
        nullable: Bool = false
    ) -> AnthropicWire.PropertySchema {
        AnthropicWire.PropertySchema(type: "object", description: description, properties: properties, required: required, additionalProperties: false, nullable: nullable)
    }

    private static func arraySchema(
        _ description: String,
        item: AnthropicWire.PropertySchema
    ) -> AnthropicWire.PropertySchema {
        AnthropicWire.PropertySchema(type: "array", description: description, items: item)
    }

    // Anthropic's strict structured-output profile caps union parameters at 16
    // and optional parameters at 24. The proposal data scalar avoids making
    // event-specific fields optional while keeping the outer envelope strict.
    private static let envelopeSchema: AnthropicWire.ObjectSchema = {
        let storyBlock = objectSchema(
            "A bounded narration block.",
            properties: [
                "id": stringSchema("The story block identifier."),
                "kind": stringSchema("The narration or dialogue kind."),
                "speakerRecordID": optionalStringSchema("The optional imported speaker record identifier."),
                "speakerName": optionalStringSchema("The optional speaker name."),
                "mood": optionalStringSchema("The optional presentation mood."),
                "text": stringSchema("The bounded story text.")
            ],
            required: ["id", "kind", "text"]
        )
        let beat = objectSchema(
            "A bounded visual-novel beat.",
            properties: [
                "id": stringSchema("The beat identifier."),
                "kind": stringSchema("The title, narration, or dialogue kind."),
                "title": optionalStringSchema("The optional beat title."),
                "subtitle": optionalStringSchema("The optional beat subtitle."),
                "speaker": optionalStringSchema("The optional beat speaker."),
                "mood": optionalStringSchema("The optional beat mood."),
                "text": stringSchema("The bounded beat text.")
            ],
            required: ["id", "kind", "text"]
        )
        // Anthropic strict structured outputs cannot express the event-data
        // discriminated union without making fields optional. Keep this
        // provider-local wire field as one bounded JSON string; normalization
        // below reconstructs the object before the shared strict decoder.
        let eventData = stringSchema(
            "A bounded JSON-encoded object for the discriminated event data."
        )
        let proposedEvent = objectSchema(
            "A typed, proposed campaign event.",
            properties: ["type": stringSchema("The proposed event discriminator."), "data": eventData],
            required: ["type", "data"]
        )
        let decisionOption = objectSchema(
            "A player decision option.",
            properties: ["title": stringSchema("The option title."), "detail": stringSchema("The option detail.")],
            required: ["title", "detail"]
        )
        let pendingDecision = objectSchema(
            "The optional pending player decision.",
            properties: ["id": stringSchema("The decision identifier."), "prompt": stringSchema("The decision prompt."), "options": arraySchema("The bounded decision options.", item: decisionOption)],
            required: ["id", "prompt", "options"],
            nullable: true
        )
        let voiceSegment = objectSchema(
            "A bounded voice segment.",
            properties: [
                "id": stringSchema("The voice segment identifier."),
                "sourceStoryBlockID": stringSchema("The source story block identifier."),
                "speakerRecordID": optionalStringSchema("The optional imported speaker identifier."),
                "speakerName": stringSchema("The speaker name."),
                "text": stringSchema("The bounded spoken text.")
            ],
            required: ["id", "sourceStoryBlockID", "speakerName", "text"]
        )
        let usage = objectSchema(
            "The optional normalized provider usage.",
            properties: ["inputTokens": integerSchema("The input token count."), "outputTokens": integerSchema("The output token count."), "cachedInputTokens": optionalIntegerSchema("The optional cached input count.")],
            required: ["inputTokens", "outputTokens"],
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
        return AnthropicWire.ObjectSchema(properties: ["schemaVersion": integerSchema("The versioned envelope schema number."), "envelope": envelope], required: ["schemaVersion", "envelope"])
    }()
}

private actor AnthropicStreamDriver {
    private struct CallState { let callID: String; let toolName: String; var arguments: String; var completed: Bool }
    private let client: StreamingHTTPClient
    private let request: URLRequest
    private let requestID: UUID
    private let onTerminal: @Sendable () async -> Void
    private var iterator: StreamingHTTPSequence<ServerSentEventDecoder>.AsyncIterator?
    private var pending: [ProviderStreamEvent] = []
    private var calls: [Int: CallState] = [:]
    private var text = ""
    private var textBytes = 0
    private var inputTokens: Int?
    private var cachedInputTokens: Int?
    private var usageEmitted = false
    private var terminal = false
    private var cancelled = false
    private var currentPull: Task<ServerSentEvent?, Error>?

    init(client: StreamingHTTPClient, request: URLRequest, requestID: UUID, onTerminal: @escaping @Sendable () async -> Void) {
        self.client = client; self.request = request; self.requestID = requestID; self.onTerminal = onTerminal
    }

    func next() async throws -> ProviderStreamEvent? {
        guard cancelled == false else { throw ProviderError.cancelled }
        while pending.isEmpty, terminal == false {
            if iterator == nil { iterator = try await client.serverSentEvents(for: request).makeAsyncIterator() }
            do {
                guard let frame = try await pullFrame() else { throw ProviderError.malformedResponse }
                try await process(frame)
            } catch is CancellationError { throw cancelled ? ProviderError.cancelled : CancellationError() }
        }
        return pending.isEmpty ? nil : pending.removeFirst()
    }

    func cancel() async { cancelled = true; currentPull?.cancel(); await closeTransport() }

    private func pullFrame() async throws -> ServerSentEvent? {
        let task: Task<ServerSentEvent?, Error> = Task { [weak self] in guard let self else { return nil }; return try await self.pullFromIterator() }
        currentPull = task; defer { currentPull = nil }; return try await task.value
    }

    private func pullFromIterator() async throws -> ServerSentEvent? {
        guard var iterator else { return nil }; let frame = try await iterator.next(); self.iterator = iterator; return frame
    }

    private func process(_ frame: ServerSentEvent) async throws {
        let event: AnthropicWire.StreamEvent
        do { event = try JSONDecoder().decode(AnthropicWire.StreamEvent.self, from: frame.data) } catch { throw ProviderError.malformedResponse }
        switch event.type {
        case "message_start":
            inputTokens = event.message?.usage?.inputTokens
            cachedInputTokens = event.message?.usage?.cacheReadInputTokens
        case "content_block_start": try startBlock(event.index, event.contentBlock)
        case "content_block_delta": try delta(event.index, event.delta)
        case "content_block_stop": try completeCall(index: event.index)
        case "message_delta": try await finish(stopReason: event.delta?.stopReason, usage: event.usage)
        case "error":
            let type = event.error?.type ?? ""
            if ["safety_violation", "content_filter", "refusal"].contains(type) { throw ProviderError.safetyRefusal }
            if type == "overloaded_error" { throw ProviderError.serviceFailure(statusCode: 529) }
            throw ProviderError.serviceFailure(statusCode: nil)
        default: break
        }
    }

    private func startBlock(_ index: Int?, _ block: AnthropicWire.ContentBlock?) throws {
        guard let index, let block else { throw ProviderError.malformedResponse }
        if block.type == "refusal" { throw ProviderError.safetyRefusal }
        guard block.type == "tool_use" else { return }
        guard let callID = block.id, let name = block.name, ProviderNativeToolCatalog.names.contains(name), calls[index] == nil else { throw ProviderError.malformedResponse }
        var arguments = ""
        if let input = block.input, input.isEmpty == false { arguments = try ProviderAdapterSupport.encodedArguments(input) }
        guard arguments.utf8.count <= ProviderToolArguments.maximumEncodedBytes else { throw ProviderError.malformedResponse }
        calls[index] = CallState(callID: callID, toolName: name, arguments: arguments, completed: false)
        pending.append(.toolCallStarted(callID: callID, toolName: name))
    }

    private func delta(_ index: Int?, _ delta: AnthropicWire.Delta?) throws {
        guard let delta else { throw ProviderError.malformedResponse }
        if delta.type == "text_delta" { guard let value = delta.text else { throw ProviderError.malformedResponse }; try appendText(value); pending.append(.textDelta(value)); return }
        if delta.type == "input_json_delta" { guard let index, let fragment = delta.partialJSON, var call = calls[index], call.completed == false else { throw ProviderError.malformedResponse }; guard call.arguments.utf8.count + fragment.utf8.count <= ProviderToolArguments.maximumEncodedBytes else { throw ProviderError.malformedResponse }; call.arguments.append(fragment); calls[index] = call; pending.append(.toolCallArgumentFragment(callID: call.callID, fragment: fragment)) }
    }

    private func completeCall(index: Int?) throws {
        guard let index, var call = calls[index], call.completed == false else { return }
        let data = (call.arguments.isEmpty ? "{}" : call.arguments).data(using: .utf8)
        guard let data, let values = try? JSONDecoder().decode([String: JSONValue].self, from: data), let arguments = try? ProviderToolArguments(values: values) else { throw ProviderError.malformedResponse }
        call.completed = true; calls[index] = call
        pending.append(.toolCallCompleted(callID: call.callID, toolName: call.toolName, arguments: arguments))
    }

    private func finish(stopReason: String?, usage: AnthropicWire.Usage?) async throws {
        if let value = usage?.inputTokens { inputTokens = value }
        if let value = usage?.outputTokens, let input = inputTokens, usageEmitted == false { usageEmitted = true; pending.append(.usage(ProviderUsage(inputTokens: input, outputTokens: value, cachedInputTokens: cachedInputTokens)) ) }
        switch stopReason {
        case "refusal", "safety", "content_filter": throw ProviderError.safetyRefusal
        case "max_tokens": await terminate(.maximumOutputTokens)
        case "tool_use": try await finishTools()
        case "end_turn", "stop_sequence":
            if calls.isEmpty == false { try await finishTools() } else { try await finishText() }
        case nil: break
        default: throw ProviderError.malformedResponse
        }
    }

    private func finishTools() async throws {
        guard calls.isEmpty == false, calls.values.allSatisfy(\.completed) else { throw ProviderError.malformedResponse }
        await terminate(.requiresToolResults)
    }

    private func finishText() async throws {
        guard calls.isEmpty, textBytes > 0, let data = text.data(using: .utf8) else { throw ProviderError.malformedResponse }
        let versioned: VersionedTurnEnvelope
        do { versioned = try VersionedTurnEnvelope.decode(from: try ProviderAdapterSupport.normalizedAnthropicEnvelopeData(from: data)) } catch { throw ProviderError.malformedResponse }
        guard versioned.envelope.requestID == requestID else { throw ProviderError.malformedResponse }
        await terminate(.completed(versioned.envelope))
    }

    private func terminate(_ reason: ProviderFinishReason) async { guard terminal == false else { return }; terminal = true; await closeTransport(); await onTerminal(); pending.append(.finished(reason)) }

    private func closeTransport() async { currentPull?.cancel(); guard var iterator else { return }; await iterator.cancel(); self.iterator = iterator }

    private func appendText(_ value: String) throws { textBytes += value.utf8.count; guard textBytes <= VersionedTurnEnvelope.maximumEncodedBytes else { throw ProviderError.malformedResponse }; text.append(value) }
}
