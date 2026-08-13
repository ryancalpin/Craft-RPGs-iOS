import Foundation

public struct GMToolAssetReference: Codable, Equatable, Sendable {
    public let assetID: String
    public let sha256: String
    public let campaignID: UUID?
    public let origin: String?
    public let path: String?

    public init(
        assetID: String,
        sha256: String,
        campaignID: UUID? = nil,
        origin: String? = nil,
        path: String? = nil
    ) {
        self.assetID = assetID
        self.sha256 = sha256
        self.campaignID = campaignID
        self.origin = origin
        self.path = path
    }
}

/// A value snapshot supplied by the turn engine. Validators never load or mutate it.
public struct GMToolValidationContext: Equatable, Sendable {
    public let campaignID: UUID
    public let project: NormalizedProject
    public let projection: CampaignProjection
    public let importedAssets: [ImportedAsset]
    public let assetReferences: [GMToolAssetReference]

    public init(
        campaignID: UUID,
        project: NormalizedProject,
        projection: CampaignProjection,
        importedAssets: [ImportedAsset] = [],
        assetReferences: [GMToolAssetReference] = []
    ) {
        self.campaignID = campaignID
        self.project = project
        self.projection = projection
        self.importedAssets = importedAssets
        self.assetReferences = assetReferences
    }

    public init(
        campaignID: UUID,
        project: NormalizedProject,
        projection: CampaignProjection,
        assets: [ImportedAsset],
        assetReferences: [GMToolAssetReference] = []
    ) {
        self.init(
            campaignID: campaignID,
            project: project,
            projection: projection,
            importedAssets: assets,
            assetReferences: assetReferences
        )
    }

    public var assets: [ImportedAsset] { importedAssets }
}

public typealias ToolValidationContext = GMToolValidationContext

public struct GMToolRecordResult: Codable, Equatable, Sendable {
    public let recordID: String
    public let fields: [String: JSONValue]

    public init(recordID: String, fields: [String: JSONValue]) {
        self.recordID = recordID
        self.fields = fields
    }
}

public struct GMToolRecordMatch: Codable, Equatable, Sendable {
    public let recordID: String
    public let recordKind: String

    public init(recordID: String, recordKind: String) {
        self.recordID = recordID
        self.recordKind = recordKind
    }
}

public enum GMToolProposalResult: Equatable, Sendable {
    case recordRead(GMToolRecordResult)
    case recordsFound([GMToolRecordMatch])
    case proposedEvent(ProposedCampaignEvent)
}

public struct ToolProposal: Equatable, Sendable {
    public let tool: GMTool
    public let status: String
    public let result: GMToolProposalResult

    public init(tool: GMTool, status: String, result: GMToolProposalResult) {
        self.tool = tool
        self.status = status
        self.result = result
    }

    public var event: ProposedCampaignEvent? {
        guard case .proposedEvent(let event) = result else { return nil }
        return event
    }
}
