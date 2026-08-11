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
        AsyncThrowingStream { continuation in
            let relayTask = Task {
                do {
                    for try await event in source {
                        continuation.yield(event)
                        if case .finished = event {
                            continuation.finish()
                            return
                        }
                    }
                    continuation.finish(
                        throwing: ProviderError.malformedResponse
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { termination in
                guard case .cancelled = termination else { return }
                relayTask.cancel()
                Task {
                    await onCancel()
                }
            }
        }
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
