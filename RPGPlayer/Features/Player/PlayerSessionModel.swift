import CryptoKit
import Foundation
import Observation

struct PlayerPresentationState: Codable, Equatable, Sendable {
    let campaignID: UUID
    let mode: PlayerMode
    let latestMessageID: UUID
    let beatIndex: Int
}

protocol PlayerPresentationPersisting: Sendable {
    func presentation(
        for campaignID: UUID
    ) async throws -> PlayerPresentationState?

    func savePresentation(
        _ presentation: PlayerPresentationState
    ) async throws
}

actor PlayerPresentationStore: PlayerPresentationPersisting {
    private struct Document: Codable {
        var activeCampaignID: UUID?
        var campaigns: [String: PlayerPresentationState]

        static let empty = Document(
            activeCampaignID: nil,
            campaigns: [:]
        )
    }

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL) {
        self.fileURL = fileURL.standardizedFileURL
        encoder.outputFormatting = [.sortedKeys]
    }

    func presentation(
        for campaignID: UUID
    ) throws -> PlayerPresentationState? {
        try document().campaigns[Self.key(for: campaignID)]
    }

    func savePresentation(
        _ presentation: PlayerPresentationState
    ) throws {
        var document = try document()
        document.campaigns[Self.key(for: presentation.campaignID)] = presentation
        try write(document)
    }

    func activeCampaignID() throws -> UUID? {
        try document().activeCampaignID
    }

    func setActiveCampaign(_ campaignID: UUID?) throws {
        var document = try document()
        document.activeCampaignID = campaignID
        try write(document)
    }

    func clearCampaign(_ campaignID: UUID) throws {
        var document = try document()
        document.campaigns[Self.key(for: campaignID)] = nil
        if document.activeCampaignID == campaignID {
            document.activeCampaignID = nil
        }
        try write(document)
    }

    private func document() throws -> Document {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty
        }
        return try decoder.decode(
            Document.self,
            from: Data(contentsOf: fileURL)
        )
    }

    private func write(_ document: Document) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(document).write(to: fileURL, options: .atomic)
    }

    private static func key(for campaignID: UUID) -> String {
        campaignID.uuidString.lowercased()
    }
}

enum PlayerSessionModelError: Error, Equatable, Sendable {
    case missingNormalizedProject
    case unreadableNormalizedProject
    case campaignStoreUnavailable
    case rollNotPending
    case rollAlreadyResolved
    case invalidRollExpression
    case rollPersistenceFailed
}

@MainActor
@Observable
final class PlayerSessionModel {
    private(set) var state: PlayerSessionState?
    private(set) var project: NormalizedProject?
    private(set) var projection: CampaignProjection?

    let campaignID: UUID

    private let projectionLoader: ProjectionLoader
    private let campaignDirectory: CampaignDirectory
    private let presentationStore: any PlayerPresentationPersisting
    private let campaignStore: (any CampaignStore)?
    private let decoder = JSONDecoder()
    private var resolvingRollIDs = Set<UUID>()

    init(
        campaignID: UUID,
        projectionLoader: ProjectionLoader,
        campaignDirectory: CampaignDirectory,
        presentationStore: any PlayerPresentationPersisting,
        campaignStore: (any CampaignStore)? = nil
    ) {
        self.campaignID = campaignID
        self.projectionLoader = projectionLoader
        self.campaignDirectory = campaignDirectory
        self.presentationStore = presentationStore
        self.campaignStore = campaignStore
    }

    func load() async throws {
        let project = try loadNormalizedProject()
        let loadResult = try await projectionLoader.load(campaignID: campaignID)
        let projection = loadResult.projection
        let storedPresentation = try await presentationStore.presentation(
            for: campaignID
        )

        self.project = project
        self.projection = projection
        state = Self.makeState(
            campaignID: campaignID,
            project: project,
            projection: projection,
            storedPresentation: storedPresentation
        )
    }

    func refresh() async throws {
        try await refreshCanonicalState()
    }

    func resolveRoll(
        rollID: UUID,
        roller: DiceRoller = DiceRoller()
    ) async throws -> RollResolvedPayload {
        guard resolvingRollIDs.insert(rollID).inserted else {
            throw PlayerSessionModelError.rollAlreadyResolved
        }
        defer { resolvingRollIDs.remove(rollID) }

        guard let projection,
              let pending = projection.pendingRolls[rollID] else {
            throw PlayerSessionModelError.rollNotPending
        }
        guard projection.resolvedRolls[rollID] == nil else {
            throw PlayerSessionModelError.rollAlreadyResolved
        }
        guard let requestID = projection.activeTurnRequestID else {
            throw PlayerSessionModelError.rollNotPending
        }
        guard let campaignStore else {
            throw PlayerSessionModelError.campaignStoreUnavailable
        }

        try Task.checkCancellation()
        let expression: DiceExpression
        do {
            expression = try DiceExpression(pending.expression)
        } catch {
            throw PlayerSessionModelError.invalidRollExpression
        }
        let roll = roller.roll(expression)
        try Task.checkCancellation()

        let event = CampaignEvent(
            id: UUID(),
            campaignID: campaignID,
            sequence: 0,
            requestID: requestID,
            timestamp: Date(),
            schemaVersion: 1,
            payload: .rollResolved(
                RollResolvedPayload(
                    rollID: rollID,
                    results: roll.results,
                    modifier: roll.modifier,
                    total: roll.total
                )
            )
        )

        do {
            let appended = try await campaignStore.appendRollResolution(
                batch: [event],
                expectedSequence: projection.appliedThroughSequence
            )
            guard let resolved = appended.first,
                  case .rollResolved(let payload) = resolved.payload else {
                throw PlayerSessionModelError.rollPersistenceFailed
            }
            try await refreshCanonicalState()
            return payload
        } catch let error as PlayerSessionModelError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            do {
                try await refreshCanonicalState()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw PlayerSessionModelError.rollPersistenceFailed
            }

            guard let canonicalProjection = self.projection else {
                throw PlayerSessionModelError.rollPersistenceFailed
            }
            if let canonicalResolution = canonicalProjection.resolvedRolls[rollID] {
                return canonicalResolution
            }
            guard canonicalProjection.pendingRolls[rollID] != nil else {
                throw PlayerSessionModelError.rollNotPending
            }
            throw PlayerSessionModelError.rollPersistenceFailed
        }
    }

    private func refreshCanonicalState() async throws {
        let loadResult = try await projectionLoader.load(campaignID: campaignID)
        let storedPresentation = try await presentationStore.presentation(
            for: campaignID
        )
        guard let project else { return }
        projection = loadResult.projection
        state = Self.makeState(
            campaignID: campaignID,
            project: project,
            projection: loadResult.projection,
            storedPresentation: storedPresentation
        )
    }

    func send(_ action: PlayerSessionAction) async throws {
        guard let currentState = state else { return }
        var candidate = currentState
        candidate.reduce(action)

        let currentPresentation = Self.presentation(
            campaignID: campaignID,
            state: currentState
        )
        let candidatePresentation = Self.presentation(
            campaignID: campaignID,
            state: candidate
        )
        if candidatePresentation != currentPresentation {
            try await presentationStore.savePresentation(
                candidatePresentation
            )
        }
        state = candidate
    }

    private func loadNormalizedProject() throws -> NormalizedProject {
        let projectURL = campaignDirectory.campaignURL(for: campaignID)
            .appendingPathComponent(
                "normalized-project.json",
                isDirectory: false
            )
        guard FileManager.default.fileExists(atPath: projectURL.path) else {
            throw PlayerSessionModelError.missingNormalizedProject
        }
        do {
            return try decoder.decode(
                NormalizedProject.self,
                from: Data(contentsOf: projectURL)
            )
        } catch {
            throw PlayerSessionModelError.unreadableNormalizedProject
        }
    }

    private static func makeState(
        campaignID: UUID,
        project: NormalizedProject,
        projection: CampaignProjection,
        storedPresentation: PlayerPresentationState?
    ) -> PlayerSessionState {
        let messages = projection.gmMessages.isEmpty
            ? [
                openingMessage(
                    campaignID: campaignID,
                    project: project,
                    projection: projection
                )
            ]
            : projection.gmMessages.map {
                message(from: $0, actionCount: projection.submittedActions.count)
            }
        let latestMessage = messages[messages.count - 1]
        let validStoredPresentation: PlayerPresentationState? = if
            storedPresentation?.latestMessageID == latestMessage.id {
            storedPresentation
        } else {
            nil
        }
        let defaultMode: PlayerMode = projection.gmMessages.isEmpty
            ? .visualNovel
            : .transcript
        let restoredMode: PlayerMode = projection.pendingRolls.isEmpty
            ? (validStoredPresentation?.mode ?? defaultMode)
            : .transcript
        let restoredBeat = min(
            max(0, validStoredPresentation?.beatIndex ?? 0),
            max(0, latestMessage.beats.count - 1)
        )

        let pendingRoll = projection.pendingRolls.values.sorted {
            $0.rollID.uuidString < $1.rollID.uuidString
        }.first
        let lastResolvedRoll = projection.latestResolvedRollID
            .flatMap { projection.resolvedRolls[$0] }
            ?? (projection.resolvedRolls.count == 1
                ? projection.resolvedRolls.first?.value
                : nil)

        return PlayerSessionState(
            campaignTitle: projection.campaignTitle ?? project.title,
            mode: restoredMode,
            drawer: .none,
            beatIndex: restoredBeat,
            messages: messages,
            choices: [],
            isTurnSheetPresented: false,
            generation: projection.gmStatus.flatMap {
                GenerationPhase(rawValue: $0.phase.rawValue)
            },
            activeRequestID: projection.activeTurnRequestID?.uuidString,
            completedRequestIDs: [],
            pendingRoll: pendingRoll,
            resolvedRolls: projection.resolvedRolls,
            lastResolvedRoll: lastResolvedRoll
        )
    }

    private static func openingMessage(
        campaignID: UUID,
        project: NormalizedProject,
        projection: CampaignProjection
    ) -> GMMessage {
        let importedScene = project.currentSceneRecordID.flatMap { sceneID in
            project.records.first { $0.id == sceneID }
        }
        let projectedRecord = project.currentSceneRecordID.flatMap {
            projection.records[$0]
        }
        let importedTitle = stringField("title", in: importedScene)
        let importedDescription = stringField("description", in: importedScene)
        let recordTitle = stringValue(projectedRecord?["title"])
            ?? importedTitle
        let recordDescription = stringValue(projectedRecord?["description"])
            ?? stringValue(projectedRecord?["summary"])
            ?? importedDescription
        let sceneTitle = projection.currentScene?.title
            ?? recordTitle
            ?? project.title
        let sceneDescription = projection.currentScene?.summary
            ?? recordDescription
        let narration = if let sceneDescription,
                           sceneDescription.isEmpty == false {
            "\(sceneTitle)\n\n\(sceneDescription)"
        } else if let summary = project.summary,
                  summary.isEmpty == false {
            "\(sceneTitle)\n\n\(summary)"
        } else {
            sceneTitle
        }
        let seed = "\(campaignID.uuidString.lowercased())|\(project.id)"

        return GMMessage(
            id: stableUUID(seed: "\(seed)|opening-message"),
            prose: [narration],
            dialogue: [],
            actionCount: 0,
            finalQuestion: "What do you do?",
            beats: [
                VisualNovelBeat(
                    id: stableUUID(seed: "\(seed)|opening-title"),
                    kind: .title,
                    title: project.title.uppercased(),
                    subtitle: project.summary,
                    speaker: nil,
                    mood: nil,
                    text: project.title
                ),
                VisualNovelBeat(
                    id: stableUUID(seed: "\(seed)|opening-scene"),
                    kind: .narration,
                    title: nil,
                    subtitle: nil,
                    speaker: "Narrator",
                    mood: nil,
                    text: narration
                )
            ]
        )
    }

    private static func message(
        from payload: GMMessageCommittedPayload,
        actionCount: Int
    ) -> GMMessage {
        let dialogue = payload.dialogue.map {
            DialogueBlock(
                id: $0.id,
                speaker: $0.speaker,
                mood: $0.mood,
                text: $0.text
            )
        }
        let transcript = payload.orderedTranscript?.map {
            TranscriptBlock(
                id: $0.id,
                kind: $0.kind == .narration ? .narration : .dialogue,
                speaker: $0.speaker,
                mood: $0.mood,
                text: $0.text
            )
        }
        return GMMessage(
            id: payload.messageID,
            prose: payload.narration,
            dialogue: dialogue,
            actionCount: actionCount,
            finalQuestion: payload.finalQuestion,
            beats: payload.beats.map {
                VisualNovelBeat(
                    id: $0.id,
                    kind: beatKind(from: $0.kind),
                    title: $0.title,
                    subtitle: $0.subtitle,
                    speaker: $0.speaker,
                    mood: $0.mood,
                    text: $0.text
                )
            },
            transcript: transcript
        )
    }

    private static func beatKind(
        from kind: CampaignStoryBeat.Kind
    ) -> VisualNovelBeat.Kind {
        switch kind {
        case .title: .title
        case .narration: .narration
        case .dialogue: .dialogue
        }
    }

    private static func presentation(
        campaignID: UUID,
        state: PlayerSessionState
    ) -> PlayerPresentationState {
        PlayerPresentationState(
            campaignID: campaignID,
            mode: state.mode,
            latestMessageID: state.latestMessage.id,
            beatIndex: state.beatIndex
        )
    }

    private static func stringField(
        _ identifier: String,
        in record: NormalizedRecord?
    ) -> String? {
        guard let field = record?.fields.first(where: {
            $0.id.caseInsensitiveCompare(identifier) == .orderedSame
        }), case .string(let value) = field.value else {
            return nil
        }
        return value
    }

    private static func stringValue(_ value: JSONValue?) -> String? {
        guard case .string(let text)? = value else { return nil }
        return text
    }

    private static func stableUUID(seed: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            )
        )
    }
}
