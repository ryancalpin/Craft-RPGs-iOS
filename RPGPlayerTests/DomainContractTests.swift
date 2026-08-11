import Foundation
import Testing
@testable import RPGPlayer

struct DomainContractTests {
    @Test(arguments: EventFixture.allCases)
    func decodesEverySupportedPayloadFamily(_ fixture: EventFixture) throws {
        let event = try decodeEvent(fixture)

        #expect(event.schemaVersion == 1)
        #expect(event.payload.kind.rawValue == fixture.rawValue)
    }

    @Test(arguments: EventFixture.allCases)
    func schemaVersionOneFixtureRoundTripsWithoutDataLoss(
        _ fixture: EventFixture
    ) throws {
        let fixtureData = try Data(contentsOf: fixtureURL(for: fixture))
        let event = try decoder.decode(CampaignEvent.self, from: fixtureData)
        let reencoded = try encoder.encode(event)
        let expected = try normalizedJSON(fixtureData)

        #expect(reencoded == expected)
    }

    @Test
    func campaignEventEnvelopeMatchesTheFrozenCrossPhaseContract() throws {
        let event = try decodeEvent(.campaignImported)

        #expect(event.id == UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        #expect(event.campaignID == UUID(uuidString: "00000000-0000-0000-0000-000000000100"))
        #expect(event.sequence == 1)
        #expect(event.requestID == UUID(uuidString: "00000000-0000-0000-0000-000000000200"))
        let expectedTimestamp = try Date(
            "2026-08-09T12:00:00Z",
            strategy: .iso8601
        )
        #expect(event.timestamp == expectedTimestamp)
        #expect(event.schemaVersion == 1)
    }

    @Test
    func unknownCampaignImportFieldsSurviveReexport() throws {
        let event = try decodeEvent(.campaignImported)
        guard case .campaignImported(let imported) = event.payload else {
            Issue.record("Expected a campaignImported payload")
            return
        }

        #expect(
            imported.extensionPayload["futureImporterMetadata"]
                == .object([
                    "format": .string("cdf-v3-preview"),
                    "preserve": .bool(true)
                ])
        )

        let reencoded = try encoder.encode(event)
        let json = try #require(
            try JSONSerialization.jsonObject(with: reencoded) as? [String: Any]
        )
        let payload = try #require(json["payload"] as? [String: Any])
        let data = try #require(payload["data"] as? [String: Any])
        let future = try #require(
            data["futureImporterMetadata"] as? [String: Any]
        )

        #expect(future["format"] as? String == "cdf-v3-preview")
        #expect(future["preserve"] as? Bool == true)
    }

    @Test
    func importSourceClassifiesInfrastructureURLsWithoutOwningSecurityScope() {
        let folderURL = URL(fileURLWithPath: "/tmp/campaign-folder")
        let archiveURL = URL(fileURLWithPath: "/tmp/campaign.zip")
        let handoffURL = URL(fileURLWithPath: "/tmp/handoff.md")

        let sources: [(ImportSource, ImportSource.Kind, URL)] = [
            (.folder(folderURL), .folder, folderURL),
            (.archive(archiveURL), .archive, archiveURL),
            (.handoffDocument(handoffURL), .handoffDocument, handoffURL)
        ]

        for (source, expectedKind, expectedURL) in sources {
            #expect(source.kind == expectedKind)
            #expect(source.url == expectedURL)
        }
    }

    @Test
    func standardImportLimitsMatchTheBoundedImportContract() {
        let limits = ImportLimits.standard

        #expect(limits.maximumTotalExpandedBytes == 1_000_000_000)
        #expect(limits.maximumEntryCount == 10_000)
        #expect(limits.maximumFileBytes == 100_000_000)
        #expect(limits.maximumPathDepth == 30)
        #expect(limits.maximumArchiveExpansionRatio == 20)
    }

    @Test
    func fatalImportIssuesPreventCommitWhileWarningsDoNot() {
        let warning = ImportIssue(
            code: "missing-optional-asset",
            message: "An optional portrait is unavailable.",
            relativePath: "portraits/guide.png"
        )
        let fatal = ImportIssue(
            code: "unreadable-root-project",
            message: "The root project could not be read.",
            relativePath: "project.json"
        )

        let reviewable = ImportReport(
            projectTitle: "Fog Over Greyhaven",
            recordCount: 12,
            assetCount: 3,
            warnings: [warning],
            fatalErrors: []
        )
        let blocked = ImportReport(
            projectTitle: nil,
            recordCount: 0,
            assetCount: 0,
            warnings: [],
            fatalErrors: [fatal]
        )

        #expect(reviewable.canCommit)
        #expect(blocked.canCommit == false)
    }

    @Test
    func newProjectionStartsBeforeTheFirstStoredEvent() throws {
        let campaignID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000100")
        )

        let projection = CampaignProjection(campaignID: campaignID)

        #expect(projection.campaignID == campaignID)
        #expect(projection.appliedThroughSequence == 0)
        #expect(projection.campaignTitle == nil)
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private func decodeEvent(_ fixture: EventFixture) throws -> CampaignEvent {
        try decoder.decode(
            CampaignEvent.self,
            from: Data(contentsOf: fixtureURL(for: fixture))
        )
    }

    private func fixtureURL(for fixture: EventFixture) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("RPGPlayer/Fixtures/Events/v1")
            .appendingPathComponent(fixture.filename)
    }

    private func normalizedJSON(_ data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data)
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
    }
}

enum EventFixture: String, CaseIterable, Sendable {
    case campaignImported
    case playerActionSubmitted
    case gmStatusChanged
    case gmMessageCommitted
    case recordPatched
    case rollRequested
    case rollResolved
    case sceneChanged
    case voiceAssignmentChanged
    case turnCancelled
    case turnFailed

    var filename: String {
        switch self {
        case .campaignImported: "campaign-imported.json"
        case .playerActionSubmitted: "player-action-submitted.json"
        case .gmStatusChanged: "gm-status-changed.json"
        case .gmMessageCommitted: "gm-message-committed.json"
        case .recordPatched: "record-patched.json"
        case .rollRequested: "roll-requested.json"
        case .rollResolved: "roll-resolved.json"
        case .sceneChanged: "scene-changed.json"
        case .voiceAssignmentChanged: "voice-assignment-changed.json"
        case .turnCancelled: "turn-cancelled.json"
        case .turnFailed: "turn-failed.json"
        }
    }
}
