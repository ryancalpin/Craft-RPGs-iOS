import Foundation
import Testing
@testable import RPGPlayer

struct CampaignAssistantTests {
    @Test
    func answersFromLiveProjectRecordsAndDoesNotInventUnknownFacts() async {
        let project = Fixture.project
        let context = LiveCampaignAssistantContext(
            campaignTitle: "The Ascendant Road",
            project: project,
            projection: CampaignProjection(campaignID: UUID()),
            importedAssets: []
        )
        let service = CampaignAssistantService()

        let known = await service.answer(
            prompt: "What do you know about the watchtower?",
            context: context
        )
        #expect(known.references == ["watchtower"])
        #expect(known.text.contains("watchtower"))

        let unknown = await service.answer(
            prompt: "Tell me about a dragon",
            context: context
        )
        #expect(unknown.references.isEmpty)
        #expect(unknown.text.contains("couldn't find"))
    }
}

private enum Fixture {
    static let project = NormalizedProject(
        cdfVersion: 2,
        importScope: .projectWorldContent,
        id: "project-1",
        title: "The Ascendant Road",
        summary: nil,
        system: nil,
        rootFolderID: "root",
        currentSceneRecordID: "watchtower",
        playerCharacterRecordID: nil,
        projectExtensionPayload: [:],
        schemas: [],
        content: NormalizedContent(
            folders: [],
            records: [
                NormalizedRecord(
                    id: "watchtower",
                    fileTypeID: "scene",
                    folderID: nil,
                    fields: [
                        NormalizedField(
                            id: "title",
                            value: .string("Broken watchtower"),
                            extensionPayload: [:]
                        )
                    ],
                    extensionPayload: [:]
                )
            ],
            relationships: [],
            assets: [],
            maps: [],
            characters: [],
            extensionPayload: [:]
        ),
        manifest: NormalizedManifest(files: [], recordIDs: ["watchtower"]),
        extensionPayload: [:]
    )
}
