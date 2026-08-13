import Foundation

public enum TurnEnvelopeValidationError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case campaignOwnershipMismatch
    case requestIDMismatch(expected: UUID, actual: UUID)
    case payloadTooLarge(maximumBytes: Int, actualBytes: Int)
    case tooManyItems
    case textTooLarge
    case unsafeText
    case duplicateContent(UUID)
    case duplicateProposal
    case transcriptBeatMismatch
    case invalidToolProposal(index: Int, error: ToolValidationError)
    case invalidUsage
    case malformedEncoding
    case rollLineageCountMismatch(expected: Int, actual: Int)
    case rollLineageMismatch(index: Int, expected: UUID, actual: UUID)
}

public struct TurnRollLineage: Equatable, Sendable {
    public let rollID: UUID
    public let expression: String
    public let prompt: String

    public init(rollID: UUID, expression: String, prompt: String) {
        self.rollID = rollID
        self.expression = expression
        self.prompt = prompt
    }
}

/// Validates the complete provider result against the request and an immutable
/// app-owned world snapshot. It never reads or mutates a store.
public struct TurnEnvelopeValidator: Sendable {
    public static let maximumItems = 256
    public static let maximumDecisionOptions = 32
    public static let maximumTextBytes = 16_384
    public static let maximumTotalTextBytes = 2_000_000

    private let context: GMToolValidationContext
    private let toolValidator: ToolValidator

    public init(
        context: GMToolValidationContext,
        toolValidator: ToolValidator = ToolValidator()
    ) {
        self.context = context
        self.toolValidator = toolValidator
    }

    public func validate(
        _ versionedEnvelope: VersionedTurnEnvelope,
        for request: TurnRequest,
        expectedRollIDs: [UUID]? = nil,
        expectedRolls: [TurnRollLineage]? = nil
    ) throws -> VersionedTurnEnvelope {
        guard versionedEnvelope.schemaVersion == 1 else {
            throw TurnEnvelopeValidationError.unsupportedSchemaVersion(
                versionedEnvelope.schemaVersion
            )
        }
        guard versionedEnvelope.envelope.requestID == request.requestID else {
            throw TurnEnvelopeValidationError.requestIDMismatch(
                expected: request.requestID,
                actual: versionedEnvelope.envelope.requestID
            )
        }
        guard context.campaignID == request.campaignID,
              context.projection.campaignID == request.campaignID else {
            throw TurnEnvelopeValidationError.campaignOwnershipMismatch
        }
        guard Self.isSafeText(request.action.text),
              request.action.text.utf8.count <= Self.maximumTextBytes,
              request.action.additionalContext.map({
                  Self.isSafeText($0) && $0.utf8.count <= Self.maximumTextBytes
              }) ?? true else {
            throw TurnEnvelopeValidationError.unsafeText
        }

        do {
            let encodedBytes = try versionedEnvelope.encoded().count
            guard encodedBytes <= VersionedTurnEnvelope.maximumEncodedBytes else {
                throw TurnEnvelopeValidationError.payloadTooLarge(
                    maximumBytes: VersionedTurnEnvelope.maximumEncodedBytes,
                    actualBytes: encodedBytes
                )
            }
        } catch let error as TurnEnvelopeValidationError {
            throw error
        } catch let error as VersionedTurnEnvelope.CodingError {
            switch error {
            case .payloadTooLarge(let maximumBytes, let actualBytes):
                throw TurnEnvelopeValidationError.payloadTooLarge(
                    maximumBytes: maximumBytes,
                    actualBytes: actualBytes
                )
            case .malformedEncoding:
                throw TurnEnvelopeValidationError.malformedEncoding
            case .unsupportedSchemaVersion(let version):
                throw TurnEnvelopeValidationError.unsupportedSchemaVersion(version)
            }
        } catch {
            throw TurnEnvelopeValidationError.malformedEncoding
        }

        let envelope = versionedEnvelope.envelope
        guard envelope.narration.count <= Self.maximumItems,
              envelope.beats.count <= Self.maximumItems,
              envelope.proposedEvents.count <= Self.maximumItems,
              envelope.voiceSegments.count <= Self.maximumItems else {
            throw TurnEnvelopeValidationError.tooManyItems
        }
        if let decision = envelope.pendingDecision {
            guard decision.options.count <= Self.maximumDecisionOptions else {
                throw TurnEnvelopeValidationError.tooManyItems
            }
        }

        var totalTextBytes = 0
        func check(_ text: String?) throws {
            guard let text else { return }
            guard Self.isSafeText(text),
                  text.utf8.count <= Self.maximumTextBytes else {
                throw TurnEnvelopeValidationError.unsafeText
            }
            totalTextBytes += text.utf8.count
            guard totalTextBytes <= Self.maximumTotalTextBytes else {
                throw TurnEnvelopeValidationError.textTooLarge
            }
        }

        var contentIDs = Set<UUID>()
        for block in envelope.narration {
            guard contentIDs.insert(block.id).inserted else {
                throw TurnEnvelopeValidationError.duplicateContent(block.id)
            }
            try check(block.speakerRecordID)
            try check(block.speakerName)
            try check(block.mood)
            try check(block.text)
        }
        for beat in envelope.beats {
            guard contentIDs.insert(beat.id).inserted else {
                throw TurnEnvelopeValidationError.duplicateContent(beat.id)
            }
            try check(beat.title)
            try check(beat.subtitle)
            try check(beat.speaker)
            try check(beat.mood)
            try check(beat.text)
        }
        var voiceIDs = Set<UUID>()
        for segment in envelope.voiceSegments {
            guard voiceIDs.insert(segment.id).inserted else {
                throw TurnEnvelopeValidationError.duplicateContent(segment.id)
            }
            try check(segment.speakerRecordID)
            try check(segment.speakerName)
            try check(segment.text)
        }
        if let decision = envelope.pendingDecision {
            try check(decision.prompt)
            for option in decision.options {
                try check(option.title)
                try check(option.detail)
            }
        }
        if let usage = envelope.usage,
           usage.inputTokens < 0 || usage.outputTokens < 0
                || (usage.cachedInputTokens ?? 0) < 0 {
            throw TurnEnvelopeValidationError.invalidUsage
        }

        try validateTranscriptReconstruction(envelope)
        try validateProposals(
            envelope.proposedEvents,
            expectedRollIDs: expectedRollIDs,
            expectedRolls: expectedRolls
        )
        return versionedEnvelope
    }

    public static func isSafeText(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            scalar.value == 9 || scalar.value == 10 || scalar.value == 13
                || scalar.value >= 32
        }
    }

    private func validateTranscriptReconstruction(_ envelope: TurnEnvelope) throws {
        guard envelope.beats.isEmpty == false else { return }
        let transcript = envelope.narration.map { block in
            "\(block.kind.rawValue)\u{0}\(block.text)"
        }
        let visualNovel = envelope.beats.compactMap { beat -> String? in
            guard beat.kind != .title else { return nil }
            return "\(beat.kind.rawValue)\u{0}\(beat.text)"
        }
        guard transcript == visualNovel else {
            throw TurnEnvelopeValidationError.transcriptBeatMismatch
        }
    }

    private func validateProposals(
        _ proposals: [ProposedCampaignEvent],
        expectedRollIDs: [UUID]?,
        expectedRolls: [TurnRollLineage]?
    ) throws {
        var encodedProposals = Set<Data>()
        var rollIDs = Set<UUID>()
        var actualRollIDs: [UUID] = []
        var actualRolls: [TurnRollLineage] = []
        for (index, proposal) in proposals.enumerated() {
            guard let encoded = try? encode(proposal),
                  encodedProposals.insert(encoded).inserted else {
                throw TurnEnvelopeValidationError.duplicateProposal
            }
            if case .rollRequest(let rollID, _, _) = proposal,
               rollIDs.insert(rollID).inserted == false {
                throw TurnEnvelopeValidationError.duplicateProposal
            } else if case .rollRequest(let rollID, let expression, let prompt) = proposal {
                actualRollIDs.append(rollID)
                actualRolls.append(
                    TurnRollLineage(
                        rollID: rollID,
                        expression: expression,
                        prompt: prompt
                    )
                )
            }
            do {
                _ = try validateProposal(proposal)
            } catch let error as ToolValidationError {
                throw TurnEnvelopeValidationError.invalidToolProposal(
                    index: index,
                    error: error
                )
            } catch {
                throw TurnEnvelopeValidationError.invalidToolProposal(
                    index: index,
                    error: .malformedArguments
                )
            }
        }
        if let expectedRolls {
            guard expectedRolls.count == actualRolls.count else {
                throw TurnEnvelopeValidationError.rollLineageCountMismatch(
                    expected: expectedRolls.count,
                    actual: actualRolls.count
                )
            }
            for (index, (expected, actual)) in zip(expectedRolls, actualRolls).enumerated()
            where expected != actual {
                throw TurnEnvelopeValidationError.rollLineageMismatch(
                    index: index,
                    expected: expected.rollID,
                    actual: actual.rollID
                )
            }
        } else if let expectedRollIDs {
            guard expectedRollIDs.count == actualRollIDs.count else {
                throw TurnEnvelopeValidationError.rollLineageCountMismatch(
                    expected: expectedRollIDs.count,
                    actual: actualRollIDs.count
                )
            }
            for (index, (expected, actual)) in zip(expectedRollIDs, actualRollIDs).enumerated()
            where expected != actual {
                throw TurnEnvelopeValidationError.rollLineageMismatch(
                    index: index,
                    expected: expected,
                    actual: actual
                )
            }
        }
    }

    private func validateProposal(
        _ proposal: ProposedCampaignEvent
    ) throws -> ToolProposal {
        switch proposal {
        case .recordPatch(let recordID, let fields):
            return try toolValidator.validate(
                tool: .patchRecord,
                arguments: try ProviderToolArguments(values: [
                    "recordID": .string(recordID),
                    "fieldsJSON": .string(String(
                        data: try encode(fields),
                        encoding: .utf8
                    ) ?? "{}")
                ]),
                context: context
            )
        case .rollRequest(let rollID, let expression, let prompt):
            return try toolValidator.validate(
                tool: .requestRoll,
                arguments: try ProviderToolArguments(values: [
                    "expression": .string(expression),
                    "prompt": .string(prompt)
                ]),
                context: context,
                rollID: rollID
            )
        case .sceneChange(let sceneRecordID, let title, let summary):
            return try toolValidator.validate(
                tool: .updateScene,
                arguments: try ProviderToolArguments(values: [
                    "sceneRecordID": .string(sceneRecordID),
                    "title": .string(title),
                    "summary": summary.map(JSONValue.string) ?? .null
                ]),
                context: context
            )
        case .clockUpdate(let clockRecordID, let current, let maximum):
            return try toolValidator.validate(
                tool: .updateClock,
                arguments: try ProviderToolArguments(values: [
                    "clockRecordID": .string(clockRecordID),
                    "current": .integer(Int64(current)),
                    "maximum": .integer(Int64(maximum))
                ]),
                context: context
            )
        case .voiceSuggestion(let characterRecordID, let styleDescription):
            return try toolValidator.validate(
                tool: .suggestVoice,
                arguments: try ProviderToolArguments(values: [
                    "characterRecordID": .string(characterRecordID),
                    "styleDescription": .string(styleDescription)
                ]),
                context: context
            )
        case .assetAttachment(let assetID, let targetRecordID, let fieldID):
            return try toolValidator.validate(
                tool: .attachAsset,
                arguments: try ProviderToolArguments(values: [
                    "assetID": .string(assetID),
                    "targetRecordID": .string(targetRecordID),
                    "fieldID": .string(fieldID)
                ]),
                context: context
            )
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}
