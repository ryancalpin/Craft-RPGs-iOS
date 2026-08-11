import Foundation

public enum HandoffReviewFlag: String, Codable, Equatable, Sendable {
    case emptyInput
    case unstructuredText
    case speakerMappingRequired
    case ambiguousSpeakerNames
}

public enum HandoffApprovalError: Error, Equatable, Sendable {
    case explicitApprovalRequired
}

/// An editable, review-only interpretation of a handoff document.
///
/// It intentionally stores mapped fields rather than the original transcript.
public struct HandoffDraft: Equatable, Sendable {
    public let originalHandoffSHA256: String
    public var summary: String
    public var currentScene: String
    public var playerCharacter: String
    public var unresolvedThreads: [String]
    public var inventoryDeltas: [String: Int]
    public var lastKnownPlayerChoice: String
    public let detectedSpeakers: [String]
    public let reviewFlags: [HandoffReviewFlag]

    public init(
        originalHandoffSHA256: String,
        summary: String = "",
        currentScene: String = "",
        playerCharacter: String = "",
        unresolvedThreads: [String] = [],
        inventoryDeltas: [String: Int] = [:],
        lastKnownPlayerChoice: String = "",
        detectedSpeakers: [String] = [],
        reviewFlags: [HandoffReviewFlag] = []
    ) {
        self.originalHandoffSHA256 = originalHandoffSHA256
        self.summary = summary
        self.currentScene = currentScene
        self.playerCharacter = playerCharacter
        self.unresolvedThreads = unresolvedThreads
        self.inventoryDeltas = inventoryDeltas
        self.lastKnownPlayerChoice = lastKnownPlayerChoice
        self.detectedSpeakers = detectedSpeakers
        self.reviewFlags = reviewFlags
    }

    public func approvedCheckpoint(
        confirmingUserApproval: Bool
    ) throws -> ApprovedHandoffCheckpoint {
        guard confirmingUserApproval else {
            throw HandoffApprovalError.explicitApprovalRequired
        }

        return ApprovedHandoffCheckpoint(
            originalHandoffSHA256: originalHandoffSHA256,
            summary: summary,
            currentScene: currentScene,
            playerCharacter: playerCharacter,
            unresolvedThreads: unresolvedThreads,
            inventoryDeltas: inventoryDeltas,
            lastKnownPlayerChoice: lastKnownPlayerChoice
        )
    }
}

/// The versioned handoff state that may be written into `campaignImported`.
/// Its memberwise initializer is intentionally not public; callers create it
/// only by explicitly approving a `HandoffDraft` or decoding persisted data.
public struct ApprovedHandoffCheckpoint: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let originalHandoffSHA256: String
    public let summary: String
    public let currentScene: String
    public let playerCharacter: String
    public let unresolvedThreads: [String]
    public let inventoryDeltas: [String: Int]
    public let lastKnownPlayerChoice: String

    init(
        schemaVersion: Int = 1,
        originalHandoffSHA256: String,
        summary: String,
        currentScene: String,
        playerCharacter: String,
        unresolvedThreads: [String],
        inventoryDeltas: [String: Int],
        lastKnownPlayerChoice: String
    ) {
        self.schemaVersion = schemaVersion
        self.originalHandoffSHA256 = originalHandoffSHA256
        self.summary = summary
        self.currentScene = currentScene
        self.playerCharacter = playerCharacter
        self.unresolvedThreads = unresolvedThreads
        self.inventoryDeltas = inventoryDeltas
        self.lastKnownPlayerChoice = lastKnownPlayerChoice
    }

    public func applying(
        to payload: CampaignImportedPayload
    ) -> CampaignImportedPayload {
        var extensionPayload = payload.extensionPayload
        extensionPayload["handoffCheckpoint"] = jsonValue

        return CampaignImportedPayload(
            projectID: payload.projectID,
            campaignTitle: payload.campaignTitle,
            manifestHash: payload.manifestHash,
            extensionPayload: extensionPayload
        )
    }

    private var jsonValue: JSONValue {
        .object([
            "schemaVersion": .integer(Int64(schemaVersion)),
            "originalHandoffSHA256": .string(originalHandoffSHA256),
            "summary": .string(summary),
            "currentScene": .string(currentScene),
            "playerCharacter": .string(playerCharacter),
            "unresolvedThreads": .array(
                unresolvedThreads.map(JSONValue.string)
            ),
            "inventoryDeltas": .object(
                inventoryDeltas.mapValues { .integer(Int64($0)) }
            ),
            "lastKnownPlayerChoice": .string(lastKnownPlayerChoice)
        ])
    }

    init?(jsonValue: JSONValue) {
        guard case .object(let object) = jsonValue,
              case .integer(let schemaVersion)? = object["schemaVersion"],
              let exactSchemaVersion = Int(exactly: schemaVersion),
              case .string(let sourceHash)? = object["originalHandoffSHA256"],
              case .string(let summary)? = object["summary"],
              case .string(let currentScene)? = object["currentScene"],
              case .string(let playerCharacter)? = object["playerCharacter"],
              case .array(let unresolvedValues)? = object["unresolvedThreads"],
              case .object(let inventoryValues)? = object["inventoryDeltas"],
              case .string(let lastChoice)? = object["lastKnownPlayerChoice"]
        else {
            return nil
        }

        let unresolvedThreads: [String] = unresolvedValues.compactMap { value in
            guard case .string(let thread) = value else { return nil }
            return thread
        }
        guard unresolvedThreads.count == unresolvedValues.count else {
            return nil
        }

        var inventoryDeltas: [String: Int] = [:]
        for (name, value) in inventoryValues {
            guard case .integer(let delta) = value,
                  let exactDelta = Int(exactly: delta)
            else {
                return nil
            }
            inventoryDeltas[name] = exactDelta
        }

        self.init(
            schemaVersion: exactSchemaVersion,
            originalHandoffSHA256: sourceHash,
            summary: summary,
            currentScene: currentScene,
            playerCharacter: playerCharacter,
            unresolvedThreads: unresolvedThreads,
            inventoryDeltas: inventoryDeltas,
            lastKnownPlayerChoice: lastChoice
        )
    }
}

public extension CampaignImportedPayload {
    var handoffCheckpoint: ApprovedHandoffCheckpoint? {
        guard let value = extensionPayload["handoffCheckpoint"] else {
            return nil
        }
        return ApprovedHandoffCheckpoint(jsonValue: value)
    }
}
