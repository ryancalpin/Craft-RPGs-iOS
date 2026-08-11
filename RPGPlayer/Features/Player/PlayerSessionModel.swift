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
    private let decoder = JSONDecoder()

    init(
        campaignID: UUID,
        projectionLoader: ProjectionLoader,
        campaignDirectory: CampaignDirectory,
        presentationStore: any PlayerPresentationPersisting
    ) {
        self.campaignID = campaignID
        self.projectionLoader = projectionLoader
        self.campaignDirectory = campaignDirectory
        self.presentationStore = presentationStore
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

    func send(_ action: PlayerAction) async throws {
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
        let restoredMode = validStoredPresentation?.mode ?? defaultMode
        let restoredBeat = min(
            max(0, validStoredPresentation?.beatIndex ?? 0),
            max(0, latestMessage.beats.count - 1)
        )

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
            completedRequestIDs: []
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
        GMMessage(
            id: payload.messageID,
            prose: payload.narration,
            dialogue: payload.dialogue.map {
                DialogueBlock(
                    id: $0.id,
                    speaker: $0.speaker,
                    mood: $0.mood,
                    text: $0.text
                )
            },
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
            }
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
