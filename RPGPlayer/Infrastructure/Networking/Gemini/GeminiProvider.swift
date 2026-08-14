import Foundation

public actor GeminiProvider: AIProvider {
    public nonisolated let id: ProviderID = .gemini
    public static let defaultBaseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!

    private let credentialReader: any ProviderCredentialReader
    private let credentialReference: ProviderCredentialReference
    private let baseURL: URL
    private let baseRequest: URLRequest?
    private let httpClient: StreamingHTTPClient
    private var activeStreams: [UUID: GeminiStreamDriver] = [:]

    public init(credentialReader: any ProviderCredentialReader, credentialReference: ProviderCredentialReference? = nil, baseURL: URL = GeminiProvider.defaultBaseURL) {
        self.credentialReader = credentialReader
        self.credentialReference = credentialReference ?? Self.defaultReference
        self.baseURL = baseURL
        self.baseRequest = nil
        self.httpClient = .live()
    }

    init(credentialReader: any ProviderCredentialReader, credentialReference: ProviderCredentialReference? = nil, baseRequest: URLRequest, httpClient: StreamingHTTPClient) {
        self.credentialReader = credentialReader
        self.credentialReference = credentialReference ?? Self.defaultReference
        if let url = baseRequest.url {
            self.baseURL = url.lastPathComponent == "models"
                ? url.deletingLastPathComponent()
                : url.deletingLastPathComponent().deletingLastPathComponent()
        } else {
            self.baseURL = Self.defaultBaseURL
        }
        self.baseRequest = baseRequest
        self.httpClient = httpClient
    }

    public func models() async throws -> [ProviderModel] {
        let secret = try await credential()
        var request = makeRequest(path: "models")
        authenticate(secret, request: &request)
        do {
            let response = try JSONDecoder().decode(GeminiWire.ModelsResponse.self, from: try await httpClient.boundedData(for: request))
            let discovered = response.models.compactMap(Self.model(for:))
            return discovered.isEmpty ? Self.fallbackModels : discovered
        } catch let error as ProviderError { throw error }
        catch {
            switch ProviderAdapterSupport.normalized(error) {
            case .invalidCredential, .cancelled: throw ProviderAdapterSupport.normalized(error)
            default: return Self.fallbackModels
            }
        }
    }

    public func streamTurn(_ request: TurnRequest) async throws -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        let secret = try await credential()
        if let previous = activeStreams.removeValue(forKey: request.requestID) { await previous.cancel() }
        var urlRequest = makeRequest(path: "models/\(request.modelID ?? Self.fallbackModels[0].id):streamGenerateContent")
        authenticate(secret, request: &urlRequest)
        urlRequest.httpBody = try Self.requestBody(for: request)
        let driver = GeminiStreamDriver(
            client: httpClient,
            request: urlRequest,
            requestID: request.requestID,
            continuationLineage: request.context.contextHash.rawValue,
            onTerminal: { [weak self] in
                await self?.removeActiveStream(requestID: request.requestID)
            }
        )
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
        if path.contains(":streamGenerateContent"), var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false) {
            components.queryItems = [URLQueryItem(name: "alt", value: "sse")]
            request.url = components.url
        }
        request.httpMethod = path == "models" ? "GET" : "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        return request
    }

    private func authenticate(_ secret: String, request: inout URLRequest) { request.setValue(secret, forHTTPHeaderField: "x-goog-api-key") }

    private static func requestBody(for request: TurnRequest) throws -> Data {
        let context = ProviderAdapterSupport.context(for: request)
        let body = GeminiWire.Request(contents: [GeminiWire.Content(role: "user", parts: [GeminiWire.Part(text: request.action.text)])], systemInstruction: GeminiWire.Content(role: nil, parts: [GeminiWire.Part(text: "Return only the versioned RPGPlayer turn envelope.\n\(context)")]), tools: [GeminiWire.Tool(functionDeclarations: tools)], generationConfig: GeminiWire.GenerationConfig(responseJsonSchema: envelopeSchema))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(body)
    }

    private static let defaultReference = try! ProviderCredentialReference(providerID: .gemini)
    private static let fallbackModels = CuratedProviderModelCatalog.models(
        for: .gemini
    )

    private static func model(for model: GeminiWire.Model) -> ProviderModel? {
        let id = model.name.hasPrefix("models/") ? String(model.name.dropFirst("models/".count)) : model.name
        return try? ProviderModel(providerID: .gemini, id: id, displayName: model.displayName ?? id, contextWindowTokens: model.inputTokenLimit ?? 1_000_000, maximumOutputTokens: model.outputTokenLimit ?? 65_536, supportsTools: true, supportsStructuredOutput: true)
    }

    private static let tools: [GeminiWire.FunctionDeclaration] = ProviderNativeToolCatalog.definitions.map { definition in
        GeminiWire.FunctionDeclaration(name: definition.name, description: definition.description, parameters: GeminiWire.Schema(properties: definition.properties.mapValues { GeminiWire.PropertySchema(type: $0.type.uppercased(), description: $0.description) }, required: definition.required))
    }

    private static func stringSchema(_ description: String, nullable: Bool = false) -> GeminiWire.ResponsePropertySchema {
        GeminiWire.ResponsePropertySchema(type: "string", description: description, nullable: nullable)
    }

    private static func integerSchema(_ description: String, nullable: Bool = false) -> GeminiWire.ResponsePropertySchema {
        GeminiWire.ResponsePropertySchema(type: "integer", description: description, nullable: nullable)
    }

    private static func objectSchema(
        _ description: String,
        properties: [String: GeminiWire.ResponsePropertySchema],
        required: [String],
        nullable: Bool = false
    ) -> GeminiWire.ResponsePropertySchema {
        GeminiWire.ResponsePropertySchema(type: "object", description: description, properties: properties, required: required, additionalProperties: false, nullable: nullable)
    }

    private static func arraySchema(
        _ description: String,
        item: GeminiWire.ResponsePropertySchema
    ) -> GeminiWire.ResponsePropertySchema {
        GeminiWire.ResponsePropertySchema(type: "array", description: description, items: item)
    }

    private static let envelopeSchema: GeminiWire.ResponseObjectSchema = {
        let nullableString = { (description: String) in stringSchema(description, nullable: true) }
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
                "fields": stringSchema("A bounded JSON-encoded object of arbitrary campaign fields.", nullable: true),
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
            required: ["recordID", "fields", "rollID", "expression", "prompt", "sceneRecordID", "title", "summary", "clockRecordID", "current", "maximum", "characterRecordID", "styleDescription", "assetID", "targetRecordID", "fieldID"]
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
                "speakerRecordID": nullableString("The optional imported speaker identifier."),
                "speakerName": stringSchema("The speaker name."),
                "text": stringSchema("The bounded spoken text.")
            ],
            required: ["id", "sourceStoryBlockID", "speakerRecordID", "speakerName", "text"]
        )
        let usage = objectSchema(
            "The optional normalized provider usage.",
            properties: ["inputTokens": integerSchema("The input token count."), "outputTokens": integerSchema("The output token count."), "cachedInputTokens": integerSchema("The optional cached input count.", nullable: true)],
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
        return GeminiWire.ResponseObjectSchema(properties: ["schemaVersion": integerSchema("The versioned envelope schema number."), "envelope": envelope], required: ["schemaVersion", "envelope"])
    }()
}

private actor GeminiStreamDriver {
    private struct CallState { let callID: String; let toolName: String; let arguments: String; var completed: Bool }
    private let client: StreamingHTTPClient
    private let request: URLRequest
    private let requestID: UUID
    /// The canonical context hash changes for each tool-result continuation,
    /// while remaining stable for retries of that exact subturn.
    private let continuationLineage: String
    private let onTerminal: @Sendable () async -> Void
    private var iterator: StreamingHTTPSequence<ServerSentEventDecoder>.AsyncIterator?
    private var pending: [ProviderStreamEvent] = []
    private var calls: [String: CallState] = [:]
    private var callOrder: [String] = []
    private var text = ""
    private var textBytes = 0
    private var usage: ProviderUsage?
    private var terminal = false
    private var cancelled = false
    private var currentPull: Task<ServerSentEvent?, Error>?

    init(
        client: StreamingHTTPClient,
        request: URLRequest,
        requestID: UUID,
        continuationLineage: String,
        onTerminal: @escaping @Sendable () async -> Void
    ) {
        self.client = client
        self.request = request
        self.requestID = requestID
        self.continuationLineage = continuationLineage
        self.onTerminal = onTerminal
    }

    func next() async throws -> ProviderStreamEvent? {
        guard cancelled == false else { throw ProviderError.cancelled }
        while pending.isEmpty, terminal == false {
            if iterator == nil { iterator = try await client.serverSentEvents(for: request).makeAsyncIterator() }
            do { guard let frame = try await pullFrame() else { throw ProviderError.malformedResponse }; try await process(frame) }
            catch is CancellationError { throw cancelled ? ProviderError.cancelled : CancellationError() }
        }
        return pending.isEmpty ? nil : pending.removeFirst()
    }

    func cancel() async { cancelled = true; currentPull?.cancel(); await closeTransport() }

    private func pullFrame() async throws -> ServerSentEvent? { let task: Task<ServerSentEvent?, Error> = Task { [weak self] in guard let self else { return nil }; return try await self.pullFromIterator() }; currentPull = task; defer { currentPull = nil }; return try await task.value }
    private func pullFromIterator() async throws -> ServerSentEvent? { guard var iterator else { return nil }; let frame = try await iterator.next(); self.iterator = iterator; return frame }

    private func process(_ frame: ServerSentEvent) async throws {
        let chunk: GeminiWire.StreamChunk
        do { chunk = try JSONDecoder().decode(GeminiWire.StreamChunk.self, from: frame.data) } catch { throw ProviderError.malformedResponse }
        if let block = chunk.promptFeedback?.blockReason, block != "BLOCK_REASON_UNSPECIFIED" { throw ProviderError.safetyRefusal }
        if let metadata = chunk.usageMetadata, let input = metadata.promptTokenCount, let output = metadata.candidatesTokenCount { usage = ProviderUsage(inputTokens: input, outputTokens: output, cachedInputTokens: metadata.cachedContentTokenCount) }
        for candidate in chunk.candidates ?? [] {
            for part in candidate.content?.parts ?? [] {
                if let text = part.text { try appendText(text); pending.append(.textDelta(text)) }
                if let call = part.functionCall { try process(call) }
            }
            if let reason = candidate.finishReason { try await finish(reason) }
        }
    }

    private func process(_ call: GeminiWire.FunctionCall) throws {
        guard ProviderNativeToolCatalog.names.contains(call.name) else { throw ProviderError.malformedResponse }
        // Gemini may omit IDs. Include the durable request and subturn
        // lineage so a fresh driver cannot reuse a prior driver's fallback.
        // Native provider IDs remain unchanged when present.
        let callID = call.id ?? "gemini-\(requestID.uuidString.lowercased())-\(continuationLineage)-\(calls.count)"
        guard calls[callID] == nil else { throw ProviderError.malformedResponse }
        let values = call.args ?? [:]
        let fragment = try ProviderAdapterSupport.encodedArguments(values)
        guard fragment.utf8.count <= ProviderToolArguments.maximumEncodedBytes else { throw ProviderError.malformedResponse }
        guard (try? ProviderToolArguments(values: values)) != nil else { throw ProviderError.malformedResponse }
        calls[callID] = CallState(callID: callID, toolName: call.name, arguments: fragment, completed: false)
        callOrder.append(callID)
    }

    private func finish(_ reason: String) async throws {
        switch reason {
        case "SAFETY", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII", "RECITATION", "IMAGE_SAFETY", "IMAGE_PROHIBITED_CONTENT", "ESCALATION": throw ProviderError.safetyRefusal
        case "MAX_TOKENS": await terminate(.maximumOutputTokens)
        case "MALFORMED_FUNCTION_CALL", "UNEXPECTED_TOOL_CALL": throw ProviderError.malformedResponse
        case "STOP":
            if calls.isEmpty { try await finishText() } else { try await finishTools() }
        default: break
        }
    }

    private func finishTools() async throws {
        guard calls.isEmpty == false,
              calls.values.allSatisfy({ $0.completed == false }) else {
            throw ProviderError.malformedResponse
        }
        // Gemini sends complete function-call packets without separate completion events.
        // Preserve the semantic packet order; call IDs are opaque and must not affect it.
        for callID in callOrder {
            guard let call = calls[callID] else { throw ProviderError.malformedResponse }
            pending.append(.toolCallStarted(callID: call.callID, toolName: call.toolName))
        }
        for callID in callOrder {
            guard let call = calls[callID] else { throw ProviderError.malformedResponse }
            pending.append(.toolCallArgumentFragment(callID: call.callID, fragment: call.arguments))
        }
        for callID in callOrder {
            guard var call = calls[callID],
                  let data = call.arguments.data(using: .utf8),
                  let values = try? JSONDecoder().decode([String: JSONValue].self, from: data),
                  let arguments = try? ProviderToolArguments(values: values) else {
                throw ProviderError.malformedResponse
            }
            call.completed = true
            calls[callID] = call
            pending.append(.toolCallCompleted(callID: call.callID, toolName: call.toolName, arguments: arguments))
        }
        await terminate(.requiresToolResults)
    }

    private func finishText() async throws {
        guard calls.isEmpty, textBytes > 0, let data = text.data(using: .utf8) else { throw ProviderError.malformedResponse }
        let versioned: VersionedTurnEnvelope
        do { versioned = try VersionedTurnEnvelope.decode(from: try ProviderAdapterSupport.normalizedEnvelopeData(from: data)) } catch { throw ProviderError.malformedResponse }
        guard versioned.envelope.requestID == requestID else { throw ProviderError.malformedResponse }
        await terminate(.completed(versioned.envelope))
    }

    private func terminate(_ reason: ProviderFinishReason) async { guard terminal == false else { return }; terminal = true; if let usage { pending.append(.usage(usage)) }; await closeTransport(); await onTerminal(); pending.append(.finished(reason)) }
    private func closeTransport() async { currentPull?.cancel(); guard var iterator else { return }; await iterator.cancel(); self.iterator = iterator }
    private func appendText(_ value: String) throws { textBytes += value.utf8.count; guard textBytes <= VersionedTurnEnvelope.maximumEncodedBytes else { throw ProviderError.malformedResponse }; text.append(value) }
}
