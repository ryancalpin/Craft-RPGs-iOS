import Foundation

struct CampaignDirectory: Sendable {
    private let applicationSupportDirectory: URL

    init(applicationSupportDirectory: URL? = nil) {
        self.applicationSupportDirectory = (
            applicationSupportDirectory
                ?? FileManager.default.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                )[0]
        ).standardizedFileURL
    }

    var campaignsRootURL: URL {
        applicationSupportDirectory
            .appendingPathComponent("Campaigns", isDirectory: true)
            .standardizedFileURL
    }

    func campaignURL(for campaignID: UUID) -> URL {
        campaignsRootURL
            .appendingPathComponent(
                campaignID.uuidString.lowercased(),
                isDirectory: true
            )
            .standardizedFileURL
    }

    func isExactCampaignURL(_ url: URL, for campaignID: UUID) -> Bool {
        url.standardizedFileURL == campaignURL(for: campaignID)
    }
}
