import Foundation
import SwiftData

@MainActor
final class AppDependencyGraph {
    let applicationSupportDirectory: URL
    let modelContainer: ModelContainer
    let store: SwiftDataCampaignStore
    let projectionLoader: ProjectionLoader
    let campaignDirectory: CampaignDirectory
    let presentationStore: PlayerPresentationStore
    let importCoordinator: ImportCoordinator
    let recoveryBundleReader: RecoveryBundleReader
    let recoveryBundleWriter: RecoveryBundleWriter
    let campaignDataManager: CampaignDataManager
    let providerCredentialSettingsStore: any ProviderCredentialSettingsStore
    let providerCredentialReader: any ProviderCredentialReader
    let providerCredentialValidator: any ProviderCredentialValidator
    let startsAtLibrary: Bool

    init(arguments: [String]) {
        let support = Self.applicationSupportDirectory(arguments: arguments)
        applicationSupportDirectory = support
        startsAtLibrary = arguments.contains("-ui-testing")
            && arguments.contains("-start-at-library")
        let credentialDependencies = Self.providerCredentialDependencies(
            arguments: arguments
        )
        providerCredentialSettingsStore = credentialDependencies.settingsStore
        providerCredentialReader = credentialDependencies.reader
        providerCredentialValidator = credentialDependencies.validator

        do {
            try FileManager.default.createDirectory(
                at: support,
                withIntermediateDirectories: true
            )
            let storeDirectory = support.appendingPathComponent(
                "Store",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: storeDirectory,
                withIntermediateDirectories: true
            )
            let configuration = ModelConfiguration(
                "RPGPlayer",
                url: storeDirectory.appendingPathComponent(
                    "RPGPlayer.store",
                    isDirectory: false
                )
            )
            modelContainer = try ModelContainer(
                for: CampaignEventRecord.self,
                ImportedAssetRecord.self,
                ProjectionCheckpointRecord.self,
                configurations: configuration
            )
        } catch {
            preconditionFailure("Unable to open the campaign store")
        }

        let store = SwiftDataCampaignStore(modelContainer: modelContainer)
        let campaignDirectory = CampaignDirectory(
            applicationSupportDirectory: support
        )
        let recoveryBundleWriter = RecoveryBundleWriter(
            store: store,
            campaignDirectory: campaignDirectory
        )
        let campaignDataManager = CampaignDataManager(
            store: store,
            campaignDirectory: campaignDirectory
        )

        self.store = store
        projectionLoader = ProjectionLoader(store: store)
        self.campaignDirectory = campaignDirectory
        presentationStore = PlayerPresentationStore(
            fileURL: support
                .appendingPathComponent("Presentation", isDirectory: true)
                .appendingPathComponent("player-state.json", isDirectory: false)
        )
        self.recoveryBundleWriter = recoveryBundleWriter
        self.campaignDataManager = campaignDataManager
        recoveryBundleReader = RecoveryBundleReader(
            store: store,
            applicationSupportDirectory: support
        )
        importCoordinator = ImportCoordinator(
            pipeline: ImportPipeline(
                store: store,
                applicationSupportDirectory: support
            ),
            fixture: ImportFlowFixture(arguments: arguments)
        )
    }

    func makePlayerSessionModel(campaignID: UUID) -> PlayerSessionModel {
        PlayerSessionModel(
            campaignID: campaignID,
            projectionLoader: projectionLoader,
            campaignDirectory: campaignDirectory,
            presentationStore: presentationStore
        )
    }

    func campaignDataContext(
        campaignID: UUID,
        title: String
    ) -> CampaignDataContext {
        CampaignDataContext(
            campaignID: campaignID,
            campaignTitle: title,
            manager: campaignDataManager,
            recoveryBundleWriter: recoveryBundleWriter
        )
    }

    private static func applicationSupportDirectory(
        arguments: [String]
    ) -> URL {
        let defaultSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].standardizedFileURL
        guard arguments.contains("-ui-testing"),
              let flag = arguments.firstIndex(of: "-persistence-test-store"),
              arguments.indices.contains(flag + 1)
        else {
            return defaultSupport
        }

        let identifier = arguments[flag + 1]
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-_")
        )
        guard identifier.isEmpty == false,
              identifier.count <= 64,
              identifier.unicodeScalars.allSatisfy(allowed.contains)
        else {
            preconditionFailure("Invalid persistence test store identifier")
        }

        let root = defaultSupport
            .appendingPathComponent("RPGPlayerUITestStores", isDirectory: true)
            .standardizedFileURL
        let scoped = root
            .appendingPathComponent(identifier, isDirectory: true)
            .standardizedFileURL
        guard scoped.deletingLastPathComponent() == root,
              scoped.lastPathComponent == identifier
        else {
            preconditionFailure("Invalid persistence test store path")
        }

        if arguments.contains("-reset-persistence-test-store"),
           FileManager.default.fileExists(atPath: scoped.path) {
            do {
                try FileManager.default.removeItem(at: scoped)
            } catch {
                preconditionFailure("Unable to reset persistence test store")
            }
        }
        return scoped
    }

    private static func providerCredentialDependencies(
        arguments: [String]
    ) -> (
        settingsStore: any ProviderCredentialSettingsStore,
        reader: any ProviderCredentialReader,
        validator: any ProviderCredentialValidator
    ) {
        guard let fixture = providerSettingsFixture(arguments: arguments)
        else {
            let store = KeychainCredentialStore()
            return (
                settingsStore: store,
                reader: store,
                validator: UnavailableProviderCredentialValidator()
            )
        }

        do {
            let store = try KeychainCredentialStore(
                testStoreIdentifier: fixture.storeIdentifier
            )
            return (
                settingsStore: store,
                reader: store,
                validator: ProviderSettingsUITestValidator(
                    outcome: fixture.outcome
                )
            )
        } catch {
            preconditionFailure("Invalid provider settings fixture scope")
        }
    }

    private static func providerSettingsFixture(
        arguments: [String]
    ) -> ProviderSettingsFixture? {
        guard arguments.contains("-ui-testing"),
              let fixtureFlag = arguments.firstIndex(
                of: "-provider-settings-fixture"
              )
        else {
            return nil
        }
        guard arguments.indices.contains(fixtureFlag + 1),
              let storeFlag = arguments.firstIndex(
                of: "-persistence-test-store"
              ),
              arguments.indices.contains(storeFlag + 1)
        else {
            preconditionFailure("Incomplete provider settings fixture")
        }

        let outcome: ProviderSettingsUITestValidationOutcome
        switch arguments[fixtureFlag + 1] {
        case "accepting":
            outcome = .accepting
        case "rejecting":
            outcome = .rejecting
        default:
            preconditionFailure("Unknown provider settings fixture")
        }
        return ProviderSettingsFixture(
            storeIdentifier: arguments[storeFlag + 1],
            outcome: outcome
        )
    }

    private struct ProviderSettingsFixture {
        let storeIdentifier: String
        let outcome: ProviderSettingsUITestValidationOutcome
    }
}
