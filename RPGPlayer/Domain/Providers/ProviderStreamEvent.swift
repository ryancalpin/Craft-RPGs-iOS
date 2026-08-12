import Foundation

public enum ProviderWarning: String, Equatable, Sendable {
    case contentFiltered
    case toolCallDiscarded
    case responseRecovered
}

public enum ProviderFinishReason: Equatable, Sendable {
    case completed(TurnEnvelope)
    case requiresToolResults
    case maximumOutputTokens
}

public enum ProviderStreamEvent: Equatable, Sendable {
    case textDelta(String)
    case toolCallStarted(callID: String, toolName: String)
    case toolCallArgumentFragment(callID: String, fragment: String)
    case toolCallCompleted(
        callID: String,
        toolName: String,
        arguments: ProviderToolArguments
    )
    case usage(ProviderUsage)
    case warning(ProviderWarning)
    case finished(ProviderFinishReason)
}

public enum ProviderStreamContract {
    public static func enforcing(
        _ source: AsyncThrowingStream<ProviderStreamEvent, Error>,
        onCancel: @escaping @Sendable () async -> Void
    ) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        let state = ProviderStreamContractState(
            source: source,
            onCancel: onCancel
        )
        return AsyncThrowingStream(unfolding: {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                let event = try await state.next()
                try Task.checkCancellation()
                return event
            } onCancel: {
                Task {
                    await state.cancel()
                }
            }
        })
    }
}

private actor ProviderStreamContractState {
    private var source: ProviderStreamSource?
    private var reachedTerminal = false
    private var didCancel = false
    private let onCancel: @Sendable () async -> Void

    init(
        source: AsyncThrowingStream<ProviderStreamEvent, Error>,
        onCancel: @escaping @Sendable () async -> Void
    ) {
        self.source = ProviderStreamSource(source.makeAsyncIterator())
        self.onCancel = onCancel
    }

    func next() async throws -> ProviderStreamEvent? {
        try Task.checkCancellation()
        guard reachedTerminal == false,
              didCancel == false,
              let source else { return nil }

        let event = try await source.next()
        try Task.checkCancellation()

        guard let event else {
            self.source = nil
            throw ProviderError.malformedResponse
        }
        if case .finished = event {
            reachedTerminal = true
            self.source = nil
        }
        return event
    }

    func cancel() async {
        guard didCancel == false else { return }
        didCancel = true
        source = nil
        await onCancel()
    }
}

private final class ProviderStreamSource: @unchecked Sendable {
    private var iterator: AsyncThrowingStream<
        ProviderStreamEvent,
        Error
    >.Iterator

    init(
        _ iterator: AsyncThrowingStream<ProviderStreamEvent, Error>.Iterator
    ) {
        self.iterator = iterator
    }

    func next() async throws -> ProviderStreamEvent? {
        var iterator = iterator
        let event = try await iterator.next()
        self.iterator = iterator
        return event
    }
}

public struct ProviderUsage: Codable, Equatable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cachedInputTokens: Int?

    public init(
        inputTokens: Int,
        outputTokens: Int,
        cachedInputTokens: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedInputTokens = cachedInputTokens
    }
}

public struct ProviderToolArguments: Codable, Equatable, Sendable {
    public enum ValidationError: Error, Equatable, Sendable {
        case payloadTooLarge(maximumBytes: Int, actualBytes: Int)
    }

    public static let maximumEncodedBytes = 1_000_000

    public let values: [String: JSONValue]

    public init(values: [String: JSONValue]) throws {
        try Self.validateEncodedSize(of: values)
        self.values = values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(
            values: container.decode([String: JSONValue].self)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }

    private static func validateEncodedSize(
        of values: [String: JSONValue]
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let actualBytes = try encoder.encode(values).count
        guard actualBytes <= maximumEncodedBytes else {
            throw ValidationError.payloadTooLarge(
                maximumBytes: maximumEncodedBytes,
                actualBytes: actualBytes
            )
        }
    }
}
