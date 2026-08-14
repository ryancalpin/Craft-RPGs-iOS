import Foundation

/// The fixed, tokenizer-independent budget policy used by the context assembler.
///
/// Estimates use UTF-8 bytes / 3, rounded up, plus fixed JSON/message framing
/// overhead (8 tokens per item and 4 per section). Three bytes per token is
/// intentionally conservative for ordinary prose and makes the result stable
/// without depending on a provider tokenizer. The model's complete maximum
/// output and the configured tool reserve are never available to input.
public struct ContextBudget: Codable, Equatable, Sendable {
    public static let itemOverheadTokens = 8
    public static let sectionOverheadTokens = 4

    public let contextWindowTokens: Int
    public let reservedOutputTokens: Int
    public let reservedToolTokens: Int
    public let safetyMarginTokens: Int
    public let inputTokenBudget: Int
    public let estimatedInputTokens: Int

    public init(
        model: ProviderModel,
        toolTokenReserve: Int = 2_048,
        safetyMarginTokens: Int = 256,
        estimatedInputTokens: Int = 0
    ) {
        let computedToolReserve = model.supportsTools
            ? max(0, toolTokenReserve)
            : 0
        contextWindowTokens = model.contextWindowTokens
        reservedOutputTokens = model.maximumOutputTokens
        reservedToolTokens = computedToolReserve
        self.safetyMarginTokens = max(0, safetyMarginTokens)
        let afterOutput = model.contextWindowTokens
            - model.maximumOutputTokens
        let afterTools = max(0, afterOutput - computedToolReserve)
        inputTokenBudget = max(0, afterTools - self.safetyMarginTokens)
        self.estimatedInputTokens = max(0, estimatedInputTokens)
    }

    public func recording(estimatedInputTokens: Int) -> ContextBudget {
        ContextBudget(
            contextWindowTokens: contextWindowTokens,
            reservedOutputTokens: reservedOutputTokens,
            reservedToolTokens: reservedToolTokens,
            safetyMarginTokens: safetyMarginTokens,
            inputTokenBudget: inputTokenBudget,
            estimatedInputTokens: max(0, estimatedInputTokens)
        )
    }

    /// Conservative and deterministic estimate for one unencoded text value.
    public static func estimateTokens(for text: String) -> Int {
        estimateTokens(forUTF8ByteCount: text.utf8.count)
    }

    /// Estimates the encoded item, including optional IDs/names and JSON
    /// framing. The additional item overhead remains reserved for the
    /// provider's surrounding message representation.
    public static func estimateTokens(for item: ContextSection.Item) -> Int {
        guard let data = try? encodedItem(item) else {
            return estimateTokens(for: item.text)
                + estimateTokens(for: item.id ?? "")
                + estimateTokens(for: item.name ?? "")
                + itemOverheadTokens
        }
        return estimateTokens(forUTF8ByteCount: data.count)
            + itemOverheadTokens
    }

    /// Estimates the same provider-facing context representation used by the
    /// assembler, including one section frame for every encoded section.
    public static func estimateTokens(for sections: [ContextSection]) -> Int {
        sections.reduce(into: 0) { total, section in
            total = saturatingAdd(total, sectionOverheadTokens)
            for item in section.items {
                total = saturatingAdd(total, estimateTokens(for: item))
            }
        }
    }

    private static func encodedItem(_ item: ContextSection.Item) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(item)
    }

    private static func estimateTokens(forUTF8ByteCount byteCount: Int) -> Int {
        let quotient = byteCount / 3
        let remainder = byteCount % 3
        return max(1, quotient + (remainder == 0 ? 0 : 1))
    }

    private static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? Int.max : result.partialValue
    }

    init(
        contextWindowTokens: Int,
        reservedOutputTokens: Int,
        reservedToolTokens: Int,
        safetyMarginTokens: Int,
        inputTokenBudget: Int,
        estimatedInputTokens: Int
    ) {
        self.contextWindowTokens = contextWindowTokens
        self.reservedOutputTokens = reservedOutputTokens
        self.reservedToolTokens = reservedToolTokens
        self.safetyMarginTokens = safetyMarginTokens
        self.inputTokenBudget = inputTokenBudget
        self.estimatedInputTokens = estimatedInputTokens
    }
}
