import CryptoKit
import Foundation

private func privacySafeMetadata(_ value: String?) -> String? {
    guard let value else { return nil }
    if value.range(of: "file://", options: [.caseInsensitive]) != nil {
        return nil
    }
    guard NetworkDiagnosticRedactor().redact(value) == value,
          isUnsafeMetadataKey(value) == false
    else { return nil }
    return value
}

private func normalizedMetadataKey(_ value: String) -> String {
    value.lowercased().filter { $0.isLetter || $0.isNumber }
}

private func isUnsafeMetadataKey(_ value: String) -> Bool {
    let normalized = normalizedMetadataKey(value)
    return normalized.contains("draft")
        || normalized.contains("private")
        || [
            "apikey", "authorization", "proxyauthorization", "token",
            "password", "secret", "credential"
        ].contains { normalized.contains($0) }
}

private func omissionSafeMetadata(_ value: String?) -> String? {
    guard let value,
          privacySafeMetadata(value) != nil
    else { return nil }
    return value
}

/// The immutable, Sendable input to `TurnContextAssembler`.
///
/// It deliberately accepts normalized project content and the persisted
/// campaign projection. An optional unapproved draft can be supplied only so
/// the assembler can report that it was discarded; it is never serialized.
/// Provider credentials, URLs, imported asset contents, and one-turn private
/// action context are not context sources and cannot be serialized accidentally.
public struct TurnContextSource: Sendable {
    public let project: NormalizedProject
    public let projection: CampaignProjection
    public let safetySystemContract: String
    public let referencedRecordIDs: [String]
    public let discardedHandoffDraft: HandoffDraft?

    public init(
        project: NormalizedProject,
        projection: CampaignProjection,
        safetySystemContract: String,
        referencedRecordIDs: [String] = [],
        discardedHandoffDraft: HandoffDraft? = nil
    ) {
        self.project = project
        self.projection = projection
        self.safetySystemContract = safetySystemContract
        self.referencedRecordIDs = referencedRecordIDs
        self.discardedHandoffDraft = discardedHandoffDraft
    }
}

public typealias TurnContextInput = TurnContextSource

public struct ContextOmission: Codable, Equatable, Sendable {
    public enum Reason: String, Codable, Equatable, Sendable {
        case budgetExceeded
        case itemLimitExceeded
        case recencyLimitExceeded
        case secretExcluded
        case localFileURLExcluded
        case discardedDraftExcluded
        case privateOptionalContextExcluded
    }

    public let kind: ContextSection.Kind
    public let itemID: String?
    public let itemName: String?
    public let reason: Reason

    public init(
        kind: ContextSection.Kind,
        itemID: String? = nil,
        itemName: String? = nil,
        reason: Reason
    ) {
        self.kind = kind
        self.itemID = itemID
        self.itemName = itemName
        self.reason = reason
    }
}

public struct ContextAssemblyMetadata: Codable, Equatable, Sendable {
    public let omittedSections: [ContextSection.Kind]
    public let omittedItems: [ContextOmission]
    public let wasTruncated: Bool

    public init(
        omittedSections: [ContextSection.Kind],
        omittedItems: [ContextOmission],
        wasTruncated: Bool
    ) {
        self.omittedSections = omittedSections
        self.omittedItems = omittedItems
        self.wasTruncated = wasTruncated
    }
}

public struct TurnContextAssembly: Codable, Equatable, Sendable {
    public let context: TurnContext
    public let budget: ContextBudget
    public let metadata: ContextAssemblyMetadata

    public init(
        context: TurnContext,
        budget: ContextBudget,
        metadata: ContextAssemblyMetadata
    ) {
        self.context = context
        self.budget = budget
        self.metadata = metadata
    }
}

/// Builds a bounded context without changing the canonical campaign history.
///
/// Candidates are generated in the fixed priority order below. Stable IDs and
/// names order set-like sections, while recent transcript items retain the
/// projection's event order. Items that do not fit are omitted as whole items;
/// their text is never silently truncated or summarized. The one permitted
/// summary is the explicit `approvedHandoffCheckpoint` already in the
/// projection.
public struct TurnContextAssembler: Sendable {
    private static let priority: [ContextSection.Kind] = [
        .systemContract,
        .playerCharacter,
        .currentScene,
        .pendingDecision,
        .recentTranscript,
        .referencedRecords,
        .unresolvedThreads,
        .worldRecords
    ]

    private let toolTokenReserve: Int
    private let safetyMarginTokens: Int
    private let maximumItemsPerSection: Int
    private let recentTranscriptItemLimit: Int

    public init(
        toolTokenReserve: Int = 2_048,
        safetyMarginTokens: Int = 256,
        maximumItemsPerSection: Int = 128,
        recentTranscriptItemLimit: Int = 32
    ) {
        self.toolTokenReserve = max(0, toolTokenReserve)
        self.safetyMarginTokens = max(0, safetyMarginTokens)
        self.maximumItemsPerSection = max(1, maximumItemsPerSection)
        self.recentTranscriptItemLimit = max(1, recentTranscriptItemLimit)
    }

    public func assemble(
        source: TurnContextSource,
        model: ProviderModel
    ) -> TurnContextAssembly {
        let initialBudget = ContextBudget(
            model: model,
            toolTokenReserve: toolTokenReserve,
            safetyMarginTokens: safetyMarginTokens
        )
        var build = CandidateBuild()
        buildCandidates(from: source, into: &build)

        var selectedSections: [ContextSection] = []
        var selectedKinds: Set<ContextSection.Kind> = []
        var usedTokens = 0

        for kind in Self.priority {
            let candidates: [Candidate]
            if kind == .recentTranscript {
                candidates = build.candidates[kind] ?? []
            } else {
                candidates = (build.candidates[kind] ?? []).sorted(
                    by: candidateComesBefore
                )
            }
            guard candidates.isEmpty == false else { continue }

            var selectedItems: [ContextSection.Item] = []
            for (index, candidate) in candidates.enumerated() {
                if index >= maximumItemsPerSection {
                    build.omissions.append(
                        ContextOmission(
                            kind: kind,
                            itemID: omissionMetadata(candidate.item.id),
                            itemName: omissionMetadata(candidate.item.name),
                            reason: .itemLimitExceeded
                        )
                    )
                    continue
                }

                let itemTokens = ContextBudget.estimateTokens(for: candidate.item)
                let sectionTokens = selectedItems.isEmpty
                    ? ContextBudget.sectionOverheadTokens
                    : 0
                let remainingTokens = initialBudget.inputTokenBudget - usedTokens
                guard sectionTokens <= remainingTokens,
                      itemTokens <= remainingTokens - sectionTokens
                else {
                    build.omissions.append(
                        ContextOmission(
                            kind: kind,
                            itemID: omissionMetadata(candidate.item.id),
                            itemName: omissionMetadata(candidate.item.name),
                            reason: .budgetExceeded
                        )
                    )
                    continue
                }

                selectedItems.append(candidate.item)
                usedTokens += sectionTokens + itemTokens
            }

            if selectedItems.isEmpty == false {
                selectedKinds.insert(kind)
                selectedSections.append(
                    ContextSection(kind: kind, items: selectedItems)
                )
            }
        }

        let omittedSections = Self.priority.filter {
            build.candidateKinds.contains($0) && selectedKinds.contains($0)
                == false
        }
        let sortedOmissions = build.omissions.sorted(by: omissionComesBefore)
        let metadata = ContextAssemblyMetadata(
            omittedSections: omittedSections,
            omittedItems: sortedOmissions,
            wasTruncated: sortedOmissions.contains {
                $0.reason == .budgetExceeded
                    || $0.reason == .itemLimitExceeded
                    || $0.reason == .recencyLimitExceeded
            }
        )
        let finalBudget = initialBudget.recording(
            estimatedInputTokens: usedTokens
        )
        let contextHash = Self.canonicalHash(
            sections: selectedSections,
            budget: finalBudget,
            metadata: metadata
        )
        return TurnContextAssembly(
            context: TurnContext(
                contextHash: contextHash,
                sections: selectedSections
            ),
            budget: finalBudget,
            metadata: metadata
        )
    }

    private struct Candidate: Sendable {
        let kind: ContextSection.Kind
        let item: ContextSection.Item
    }

    private struct CandidateBuild: Sendable {
        var candidates: [ContextSection.Kind: [Candidate]] = [:]
        var candidateKinds: Set<ContextSection.Kind> = []
        var omissions: [ContextOmission] = []

        mutating func add(_ candidate: Candidate) {
            candidateKinds.insert(candidate.kind)
            candidates[candidate.kind, default: []].append(candidate)
        }

        mutating func mark(
            kind: ContextSection.Kind,
            itemID: String? = nil,
            itemName: String? = nil,
            reason: ContextOmission.Reason,
            preserveItemID: Bool = false
        ) {
            candidateKinds.insert(kind)
            omissions.append(
                ContextOmission(
                    kind: kind,
                    itemID: preserveItemID
                        ? itemID
                        : omissionSafeMetadata(itemID)
                            ?? itemID.map { _ in "[redacted]" },
                    itemName: omissionSafeMetadata(itemName) ?? itemName.map { _ in "[redacted]" },
                    reason: reason
                )
            )
        }
    }

    private enum UnsafeTextReason: Error {
        case secret
        case localFileURL
    }

    private func buildCandidates(
        from source: TurnContextSource,
        into build: inout CandidateBuild
    ) {
        if source.discardedHandoffDraft != nil {
            build.mark(
                kind: .recentTranscript,
                itemID: "discarded-handoff-draft",
                itemName: "Unapproved handoff draft",
                reason: .discardedDraftExcluded
            )
        }
        markDiscardedDraftPayloads(from: source, into: &build)
        addText(
            source.safetySystemContract,
            kind: .systemContract,
            id: "safety-system-contract",
            name: "Safety and system contract",
            into: &build
        )
        addText(
            source.project.system,
            kind: .systemContract,
            id: "system-\(source.project.id)",
            name: "Game system",
            into: &build
        )

        let playerRecordID = source.project.playerCharacterRecordID
        addCheckpointText(
            source.projection.approvedHandoffCheckpoint?.playerCharacter,
            kind: .playerCharacter,
            id: "approved-handoff-player-character",
            name: "Approved handoff player character",
            into: &build
        )
        if let playerRecordID {
            addRecord(
                id: playerRecordID,
                kind: .playerCharacter,
                source: source,
                into: &build
            )
        }

        let sceneRecordID = source.project.currentSceneRecordID
        addCheckpointText(
            source.projection.approvedHandoffCheckpoint?.currentScene,
            kind: .currentScene,
            id: "approved-handoff-current-scene",
            name: "Approved handoff current scene",
            into: &build
        )
        if let currentScene = source.projection.currentScene {
            let text = [
                currentScene.title,
                currentScene.summary
            ].compactMap { $0 }.joined(separator: "\n")
            addText(
                text,
                kind: .currentScene,
                id: currentScene.sceneID,
                name: currentScene.title,
                into: &build
            )
        }
        if let sceneRecordID {
            addRecord(
                id: sceneRecordID,
                kind: .currentScene,
                source: source,
                into: &build
            )
        }

        addText(
            source.projection.pendingDecision,
            kind: .pendingDecision,
            id: "pending-decision",
            name: "Pending decision",
            into: &build
        )
        if source.projection.pendingDecision == nil {
            addCheckpointText(
                source.projection.approvedHandoffCheckpoint?.lastKnownPlayerChoice,
                kind: .pendingDecision,
                id: "approved-handoff-last-choice",
                name: "Approved handoff last choice",
                into: &build
            )
        }

        addCheckpointText(
            source.projection.approvedHandoffCheckpoint?.summary,
            kind: .recentTranscript,
            id: "approved-handoff-summary",
            name: "Approved handoff summary",
            into: &build
        )
        let recentActions = source.projection.submittedActions.suffix(
            recentTranscriptItemLimit
        )
        for action in source.projection.submittedActions.dropLast(
            recentActions.count
        ) {
            build.mark(
                kind: .recentTranscript,
                itemID: action.requestID.uuidString,
                itemName: "Player action",
                reason: .recencyLimitExceeded
            )
        }
        for action in recentActions {
            if let privateContext = action.additionalContext,
               privateContext.isEmpty == false {
                build.mark(
                    kind: .recentTranscript,
                    itemID: action.requestID.uuidString,
                    itemName: "Private optional context",
                    reason: .privateOptionalContextExcluded
                )
            }
            addText(
                action.action,
                kind: .recentTranscript,
                id: "action-\(action.requestID.uuidString)",
                name: "Player action",
                into: &build
            )
        }
        let recentMessages = source.projection.gmMessages.suffix(
            recentTranscriptItemLimit
        )
        for message in source.projection.gmMessages.dropLast(
            recentMessages.count
        ) {
            build.mark(
                kind: .recentTranscript,
                itemID: message.messageID.uuidString,
                itemName: "GM message",
                reason: .recencyLimitExceeded
            )
        }
        for message in recentMessages {
            let text = transcriptText(for: message)
            addText(
                text,
                kind: .recentTranscript,
                id: "gm-\(message.messageID.uuidString)",
                name: "GM message",
                into: &build
            )
        }

        let referencedIDs = Set(source.referencedRecordIDs).sorted()
        for recordID in referencedIDs {
            addRecord(
                id: recordID,
                kind: .referencedRecords,
                source: source,
                into: &build
            )
        }

        if let checkpoint = source.projection.approvedHandoffCheckpoint {
            for (index, thread) in checkpoint.unresolvedThreads.sorted()
                .enumerated()
            {
                addText(
                    thread,
                    kind: .unresolvedThreads,
                    id: "approved-thread-\(index)",
                    name: "Unresolved thread",
                    into: &build
                )
            }
            let inventoryDeltas = checkpoint.inventoryDeltas.sorted(
                by: { $0.key < $1.key }
            )
            for (index, entry) in inventoryDeltas.enumerated() {
                let (name, delta) = entry
                addText(
                    "\(name): \(delta)",
                    kind: .unresolvedThreads,
                    id: "approved-inventory-\(index)",
                    name: "Approved inventory change",
                    into: &build
                )
            }
        }

        addText(
            source.project.summary,
            kind: .worldRecords,
            id: "project-summary-\(source.project.id)",
            name: source.project.title,
            into: &build
        )
        let reservedRecordIDs = Set(
            [playerRecordID, sceneRecordID].compactMap { $0 }
                + referencedIDs
        )
        let projectRecordIDs = Set(source.project.records.map(\.id))
        for record in source.project.records.sorted(by: recordComesBefore) {
            guard reservedRecordIDs.contains(record.id) == false else {
                continue
            }
            addRecord(
                id: record.id,
                kind: .worldRecords,
                source: source,
                into: &build
            )
        }
        for recordID in source.projection.records.keys.sorted()
        where projectRecordIDs.contains(recordID) == false
        && reservedRecordIDs.contains(recordID) == false {
            addRecord(
                id: recordID,
                kind: .worldRecords,
                source: source,
                into: &build
            )
        }
    }

    private func markDiscardedDraftPayloads(
        from source: TurnContextSource,
        into build: inout CandidateBuild
    ) {
        let payloads: [(String, [String: JSONValue])] = [
            ("project", source.project.projectExtensionPayload),
            ("content", source.project.content.extensionPayload),
            ("project-extension", source.project.extensionPayload)
        ]
        for (scope, payload) in payloads {
            for key in payload.keys.sorted()
            where isDraftKey(key) || containsDraftData(payload[key]!) {
                build.mark(
                    kind: .worldRecords,
                    itemID: omissionMetadata("\(scope).\(key)"),
                    itemName: omissionMetadata(key),
                    reason: .discardedDraftExcluded
                )
            }
        }
        for record in source.project.records.sorted(by: recordComesBefore) {
            for key in record.extensionPayload.keys.sorted()
            where isDraftKey(key)
                || containsDraftData(record.extensionPayload[key]!) {
                build.mark(
                    kind: .worldRecords,
                    itemID: omissionMetadata("\(record.id).\(key)"),
                    itemName: omissionMetadata(key),
                    reason: .discardedDraftExcluded
                )
            }
            for field in record.fields.sorted(by: { $0.id < $1.id }) {
                guard isDraftKey(field.id)
                    || containsDraftData(field.value)
                    || containsDraftPayload(field.extensionPayload)
                else { continue }
                build.mark(
                    kind: .worldRecords,
                    itemID: omissionMetadata("\(record.id).\(field.id)"),
                    itemName: omissionMetadata(field.id),
                    reason: .discardedDraftExcluded
                )
            }
        }
        for recordID in source.projection.records.keys.sorted() {
            for fieldID in source.projection.records[recordID]!.keys.sorted()
            where isDraftKey(fieldID)
                || containsDraftData(source.projection.records[recordID]![fieldID]!) {
                build.mark(
                    kind: .worldRecords,
                    itemID: omissionMetadata("\(recordID).\(fieldID)"),
                    itemName: omissionMetadata(fieldID),
                    reason: .discardedDraftExcluded
                )
            }
        }
    }

    private func isDraftKey(_ key: String) -> Bool {
        key.lowercased().contains("draft")
    }

    private func containsDraftPayload(_ payload: [String: JSONValue]) -> Bool {
        payload.contains { key, value in
            isDraftKey(key) || containsDraftData(value)
        }
    }

    private func containsDraftData(_ value: JSONValue) -> Bool {
        switch value {
        case .object(let values):
            values.contains { key, nestedValue in
                isDraftKey(key) || containsDraftData(nestedValue)
            }
        case .array(let values):
            values.contains(where: containsDraftData)
        case .string, .integer, .number, .bool, .null:
            false
        }
    }

    private func addCheckpointText(
        _ text: String?,
        kind: ContextSection.Kind,
        id: String,
        name: String,
        into build: inout CandidateBuild
    ) {
        addText(text, kind: kind, id: id, name: name, into: &build)
    }

    private func addText(
        _ text: String?,
        kind: ContextSection.Kind,
        id: String,
        name: String,
        into build: inout CandidateBuild
    ) {
        guard let text, text.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false else { return }
        let safeID = safeMetadata(id)
        let safeName = safeMetadata(name)
        do {
            guard let safeText = try safeText(text) else { return }
            build.add(
                Candidate(
                    kind: kind,
                    item: ContextSection.Item(
                        id: safeID,
                        name: safeName,
                        text: safeText
                    )
                )
            )
        } catch UnsafeTextReason.secret {
            build.mark(
                kind: kind,
                itemID: omissionMetadata(id),
                itemName: omissionMetadata(name),
                reason: .secretExcluded
            )
        } catch UnsafeTextReason.localFileURL {
            build.mark(
                kind: kind,
                itemID: omissionMetadata(id),
                itemName: omissionMetadata(name),
                reason: .localFileURLExcluded
            )
        } catch {
            build.mark(
                kind: kind,
                itemID: omissionMetadata(id),
                itemName: omissionMetadata(name),
                reason: .secretExcluded
            )
        }
    }

    private func addRecord(
        id: String,
        kind: ContextSection.Kind,
        source: TurnContextSource,
        into build: inout CandidateBuild
    ) {
        let record = source.project.records.first { $0.id == id }
        let projectionValues = source.projection.records[id] ?? [:]
        let safeID = safeMetadata(id)
        let name = record.flatMap { recordName($0) }
        var values: [String: JSONValue] = [:]
        var unsafeFields: [(String, ContextOmission.Reason, Bool)] = []
        if let record {
            for field in record.fields.sorted(by: { $0.id < $1.id }) {
                guard isDraftKey(field.id) == false,
                      containsDraftData(field.value) == false,
                      containsDraftPayload(field.extensionPayload) == false
                else { continue }
                if let reason = unsafeReason(for: field.value, fieldID: field.id) {
                    unsafeFields.append((
                        field.id,
                        reason,
                        containsProviderTokenKey(field.value)
                    ))
                    continue
                }
                values[field.id] = field.value
            }
        }
        for fieldID in projectionValues.keys.sorted() {
            guard let value = projectionValues[fieldID],
                  isDraftKey(fieldID) == false,
                  containsDraftData(value) == false
            else { continue }
            if let reason = unsafeReason(for: value, fieldID: fieldID) {
                unsafeFields.append((
                    fieldID,
                    reason,
                    containsProviderTokenKey(value)
                ))
                continue
            }
            values[fieldID] = value
        }
        for (fieldID, reason, preserveItemID) in unsafeFields {
            build.mark(
                kind: kind,
                itemID: preserveItemID
                    ? "\(id).\(fieldID)"
                    : omissionMetadata("\(id).\(fieldID)"),
                itemName: omissionMetadata(fieldID),
                reason: reason,
                preserveItemID: preserveItemID
            )
        }
        var lines: [String] = []
        if let record {
            if let safeType = safeMetadata(record.fileTypeID) {
                lines.append("Record type: \(safeType)")
            }
        }
        for fieldID in values.keys.sorted() {
            guard let value = values[fieldID] else { continue }
            guard let safeFieldID = safeMetadata(fieldID) else {
                build.mark(
                    kind: kind,
                    itemID: omissionMetadata("\(id).\(fieldID)"),
                    itemName: omissionMetadata(fieldID),
                    reason: containsLocalFileURL(fieldID)
                        ? .localFileURLExcluded
                        : .secretExcluded
                )
                continue
            }
            do {
                guard let safeValue = try safeJSONText(
                    value,
                    fieldID: safeFieldID
                ) else { continue }
                lines.append("\(safeFieldID): \(safeValue)")
            } catch UnsafeTextReason.secret {
                build.mark(
                    kind: kind,
                    itemID: omissionMetadata("\(id).\(fieldID)"),
                    itemName: omissionMetadata(fieldID),
                    reason: .secretExcluded
                )
            } catch UnsafeTextReason.localFileURL {
                build.mark(
                    kind: kind,
                    itemID: omissionMetadata("\(id).\(fieldID)"),
                    itemName: omissionMetadata(fieldID),
                    reason: .localFileURLExcluded
                )
            } catch {
                build.mark(
                    kind: kind,
                    itemID: omissionMetadata("\(id).\(fieldID)"),
                    itemName: omissionMetadata(fieldID),
                    reason: .secretExcluded
                )
            }
        }
        guard lines.isEmpty == false else { return }
        build.add(
            Candidate(
                kind: kind,
                item: ContextSection.Item(
                    id: safeID,
                    name: name,
                    text: lines.joined(separator: "\n")
                )
            )
        )
    }

    private func safeText(_ text: String) throws -> String? {
        if containsSecret(text) { throw UnsafeTextReason.secret }
        if containsLocalFileURL(text) {
            throw UnsafeTextReason.localFileURL
        }
        return text
    }

    private func safeMetadata(_ value: String?) -> String? {
        privacySafeMetadata(value)
    }

    private func omissionMetadata(_ value: String?) -> String? {
        guard let value else { return nil }
        return omissionSafeMetadata(value) ?? "[redacted]"
    }

    private func safeJSONText(
        _ value: JSONValue,
        fieldID: String
    ) throws -> String? {
        if containsLocalFileURL(fieldID) || containsLocalFileURL(value) {
            throw UnsafeTextReason.localFileURL
        }
        if sensitiveFieldName(fieldID) {
            throw UnsafeTextReason.secret
        }
        if containsSecret(value) { throw UnsafeTextReason.secret }
        return jsonText(value)
    }

    private func unsafeReason(
        for value: JSONValue,
        fieldID: String
    ) -> ContextOmission.Reason? {
        if containsLocalFileURL(fieldID) || containsLocalFileURL(value) {
            return .localFileURLExcluded
        }
        if sensitiveFieldName(fieldID)
            || containsProviderTokenKey(value)
            || containsSecret(value) {
            return .secretExcluded
        }
        return nil
    }

    private func containsSecret(_ text: String) -> Bool {
        let redacted = NetworkDiagnosticRedactor().redact(text)
        return redacted != text
    }

    private func containsSecret(_ value: JSONValue) -> Bool {
        switch value {
        case .string(let value): containsSecret(value)
        case .array(let values): values.contains(where: containsSecret)
        case .object(let values):
            values.contains { key, nestedValue in
                sensitiveFieldName(key)
                    || isProviderToken(key)
                    || containsSecret(key)
                    || containsSecret(nestedValue)
            }
        case .integer, .number, .bool, .null: false
        }
    }

    private func containsProviderTokenKey(_ value: JSONValue) -> Bool {
        switch value {
        case .array(let values):
            return values.contains { containsProviderTokenKey($0) }
        case .object(let values):
            for key in values.keys {
                let lowercasedKey = key.lowercased()
                if lowercasedKey.hasPrefix("sk-")
                    || lowercasedKey.hasPrefix("aiza") {
                    return true
                }
                if let nestedValue = values[key],
                   containsProviderTokenKey(nestedValue) {
                    return true
                }
            }
            return false
        case .string, .integer, .number, .bool, .null:
            return false
        }
    }

    private func containsLocalFileURL(_ text: String) -> Bool {
        text.range(of: "file://", options: [.caseInsensitive]) != nil
    }

    private func containsLocalFileURL(_ value: JSONValue) -> Bool {
        switch value {
        case .string(let value): containsLocalFileURL(value)
        case .array(let values): values.contains(where: containsLocalFileURL)
        case .object(let values):
            values.contains {
                containsLocalFileURL($0.key)
                    || containsLocalFileURL($0.value)
            }
        case .integer, .number, .bool, .null: false
        }
    }

    private func sensitiveFieldName(_ fieldID: String) -> Bool {
        return isUnsafeMetadataKey(fieldID)
            || isProviderToken(fieldID)
    }

    private func isProviderToken(_ value: String) -> Bool {
        let normalized = normalizedMetadataKey(value)
        return normalized.hasPrefix("sk") && normalized.count >= 10
            || normalized.hasPrefix("aiza") && normalized.count >= 12
    }

    private func jsonText(_ value: JSONValue) -> String {
        switch value {
        case .string(let value): return value
        case .integer(let value): return String(value)
        case .number(let value): return String(value)
        case .bool(let value): return String(value)
        case .array(let values):
            return "[" + values.map(jsonText).joined(separator: ", ") + "]"
        case .object(let values):
            let pairs = values.keys.sorted().compactMap { key -> String? in
                guard let value = values[key] else { return nil }
                return "\(key): \(jsonText(value))"
            }
            return "{" + pairs.joined(separator: ", ") + "}"
        case .null: return "null"
        }
    }

    private func transcriptText(for message: GMMessageCommittedPayload) -> String {
        var parts = if let orderedTranscript = message.orderedTranscript {
            orderedTranscript.map { block in
                if block.kind == .dialogue {
                    return "\(block.speaker ?? "Narrator"): \(block.text)"
                }
                return block.text
            }
        } else {
            message.narration + message.dialogue.map { dialogue in
                "\(dialogue.speaker): \(dialogue.text)"
            }
        }
        parts.append(contentsOf: message.beats.map(\.text))
        if message.finalQuestion.isEmpty == false {
            parts.append(message.finalQuestion)
        }
        return parts.joined(separator: "\n")
    }

    private func recordName(_ record: NormalizedRecord) -> String? {
        for preferredID in ["identity", "name", "title", "label"] {
            for field in record.fields
            where normalizedMetadataKey(field.id) == preferredID {
                guard case .string(let value) = field.value else { continue }
                let trimmedValue = value.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard trimmedValue.isEmpty == false,
                      let safeValue = safeMetadata(trimmedValue)
                else { continue }
                return safeValue
            }
        }
        return nil
    }

    private func candidateComesBefore(
        _ lhs: Candidate,
        _ rhs: Candidate
    ) -> Bool {
        itemComesBefore(lhs.item, rhs.item)
    }

    private func itemComesBefore(
        _ lhs: ContextSection.Item,
        _ rhs: ContextSection.Item
    ) -> Bool {
        let left = [lhs.id ?? "", lhs.name ?? "", lhs.text]
        let right = [rhs.id ?? "", rhs.name ?? "", rhs.text]
        return left.lexicographicallyPrecedes(right)
    }

    private func recordComesBefore(
        _ lhs: NormalizedRecord,
        _ rhs: NormalizedRecord
    ) -> Bool {
        let left = [lhs.id, recordName(lhs) ?? ""]
        let right = [rhs.id, recordName(rhs) ?? ""]
        return left.lexicographicallyPrecedes(right)
    }

    private func omissionComesBefore(
        _ lhs: ContextOmission,
        _ rhs: ContextOmission
    ) -> Bool {
        let left = [
            priorityIndex(lhs.kind), lhs.itemID ?? "", lhs.itemName ?? "",
            lhs.reason.rawValue
        ]
        let right = [
            priorityIndex(rhs.kind), rhs.itemID ?? "", rhs.itemName ?? "",
            rhs.reason.rawValue
        ]
        return left.lexicographicallyPrecedes(right)
    }

    private func priorityIndex(_ kind: ContextSection.Kind) -> String {
        String(Self.priority.firstIndex(of: kind) ?? Self.priority.count)
            .padding(toLength: 2, withPad: "0", startingAt: 0)
    }

    private struct CanonicalHashPayload: Codable {
        let sections: [ContextSection]
        let budget: ContextBudget
        let metadata: ContextAssemblyMetadata
    }

    /// Computes the canonical hash for any context assembled under the
    /// bounded-context contract. Continuations use this same payload shape;
    /// hashing sections alone would make equivalent contexts diverge.
    public static func canonicalHash(
        sections: [ContextSection],
        budget: ContextBudget,
        metadata: ContextAssemblyMetadata
    ) -> ContextHash {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = CanonicalHashPayload(
            sections: sections,
            budget: budget,
            metadata: metadata
        )
        guard let data = try? encoder.encode(payload) else {
            preconditionFailure("Context hash payload must be encodable")
        }
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        guard let hash = try? ContextHash(rawValue: hex) else {
            preconditionFailure("SHA-256 must produce a valid ContextHash")
        }
        return hash
    }
}
