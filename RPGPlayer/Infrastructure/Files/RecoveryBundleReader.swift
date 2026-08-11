import Foundation

struct RecoveryBundleReader: Sendable {
    private let store: any CampaignStore
    private let applicationSupportDirectory: URL
    private let stager: ImportStager

    init(
        store: any CampaignStore,
        applicationSupportDirectory: URL? = nil
    ) {
        let support = (
            applicationSupportDirectory
                ?? FileManager.default.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                )[0]
        ).standardizedFileURL
        self.store = store
        self.applicationSupportDirectory = support
        stager = ImportStager(applicationSupportDirectory: support)
    }

    func restore(from archiveURL: URL) async throws -> UUID {
        let staged = try await stager.stage(.archive(archiveURL))
        do {
            let manifest = try verify(staged)
            let events = try decodeEvents(in: staged)
            guard let firstEvent = events.first,
                  firstEvent.campaignID == manifest.campaignID,
                  events.allSatisfy({ $0.campaignID == manifest.campaignID })
            else {
                throw RecoveryBundleError.invalidEventLog
            }
            _ = try decodeManualVoiceMappings(in: staged)
            let assets = try importedAssets(
                from: manifest,
                campaignID: manifest.campaignID
            )

            let stagedCampaignURL = staged.directoryURL
                .appendingPathComponent("campaign", isDirectory: true)
                .standardizedFileURL
            guard stagedCampaignURL.deletingLastPathComponent()
                == staged.directoryURL.standardizedFileURL,
                  FileManager.default.fileExists(
                    atPath: stagedCampaignURL.path
                  )
            else {
                throw RecoveryBundleError.invalidManifest
            }

            let campaignDirectory = CampaignDirectory(
                applicationSupportDirectory: applicationSupportDirectory
            )
            let destination = campaignDirectory.campaignURL(
                for: manifest.campaignID
            )
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: destination.path) == false else {
                throw RecoveryBundleError.destinationAlreadyExists(
                    manifest.campaignID
                )
            }
            try fileManager.createDirectory(
                at: campaignDirectory.campaignsRootURL,
                withIntermediateDirectories: true
            )
            do {
                try fileManager.moveItem(
                    at: stagedCampaignURL,
                    to: destination
                )
            } catch {
                throw RecoveryBundleError.unableToMoveCampaign
            }

            do {
                try await store.restoreCampaign(
                    events: events,
                    assets: assets
                )
            } catch {
                do {
                    try fileManager.moveItem(
                        at: destination,
                        to: stagedCampaignURL
                    )
                } catch {
                    discard(staged)
                    throw RecoveryBundleError.unableToMoveCampaign
                }
                throw RecoveryBundleError.persistenceFailed
            }

            discard(staged)
            return manifest.campaignID
        } catch {
            discard(staged)
            throw error
        }
    }

    private func verify(_ staged: StagedImport) throws -> RecoveryBundleManifest {
        let manifestURL = staged.directoryURL.appendingPathComponent(
            RecoveryBundle.manifestPath,
            isDirectory: false
        )
        guard FileManager.default.fileExists(atPath: manifestURL.path),
              let manifest = try? JSONDecoder().decode(
                RecoveryBundleManifest.self,
                from: Data(contentsOf: manifestURL)
              ),
              manifest.schemaVersion == RecoveryBundle.schemaVersion
        else {
            throw RecoveryBundleError.invalidManifest
        }

        var descriptorsByPath: [String: RecoveryBundleEntryDescriptor] = [:]
        for descriptor in manifest.entries {
            guard descriptorsByPath.updateValue(
                descriptor,
                forKey: descriptor.path
            ) == nil else {
                throw RecoveryBundleError.invalidManifest
            }
        }
        let declaredPaths = Set(descriptorsByPath.keys)
        for requiredPath in RecoveryBundle.requiredEntryPaths.dropFirst() {
            guard declaredPaths.contains(requiredPath) else {
                throw RecoveryBundleError.missingDeclaredEntry(requiredPath)
            }
        }

        let actualPaths = Set(staged.files.map(\.relativePath))
        let expectedPaths = declaredPaths.union([RecoveryBundle.manifestPath])
        if let missing = expectedPaths.subtracting(actualPaths).sorted().first {
            throw RecoveryBundleError.missingDeclaredEntry(missing)
        }
        if let unexpected = actualPaths.subtracting(expectedPaths).sorted().first {
            throw RecoveryBundleError.unexpectedEntry(unexpected)
        }

        let stagedByPath = Dictionary(
            uniqueKeysWithValues: staged.files.map { ($0.relativePath, $0) }
        )
        for descriptor in manifest.entries {
            guard let file = stagedByPath[descriptor.path] else {
                throw RecoveryBundleError.missingDeclaredEntry(
                    descriptor.path
                )
            }
            guard file.byteCount == descriptor.byteCount else {
                throw RecoveryBundleError.entryByteCountMismatch(
                    descriptor.path
                )
            }
            guard file.sha256 == descriptor.sha256.lowercased() else {
                throw RecoveryBundleError.entryHashMismatch(descriptor.path)
            }
        }
        return manifest
    }

    private func decodeEvents(
        in staged: StagedImport
    ) throws -> [CampaignEvent] {
        let data: Data
        do {
            data = try Data(
                contentsOf: staged.directoryURL.appendingPathComponent(
                    RecoveryBundle.eventsPath,
                    isDirectory: false
                )
            )
        } catch {
            throw RecoveryBundleError.invalidEventLog
        }
        let lines = data.split(separator: 0x0A)
        guard lines.isEmpty == false else {
            throw RecoveryBundleError.invalidEventLog
        }
        let decoder = JSONDecoder()
        do {
            return try lines.map {
                try decoder.decode(CampaignEvent.self, from: Data($0))
            }
        } catch {
            throw RecoveryBundleError.invalidEventLog
        }
    }

    private func decodeManualVoiceMappings(
        in staged: StagedImport
    ) throws -> [RecoveryVoiceMapping] {
        do {
            return try JSONDecoder().decode(
                [RecoveryVoiceMapping].self,
                from: Data(
                    contentsOf: staged.directoryURL.appendingPathComponent(
                        RecoveryBundle.manualVoiceMappingsPath,
                        isDirectory: false
                    )
                )
            )
        } catch {
            throw RecoveryBundleError.invalidManifest
        }
    }

    private func importedAssets(
        from manifest: RecoveryBundleManifest,
        campaignID: UUID
    ) throws -> [ImportedAsset] {
        try manifest.entries.compactMap { descriptor in
            guard descriptor.path.hasPrefix("campaign/") else {
                return nil
            }
            guard descriptor.path != RecoveryBundle.normalizedProjectPath,
                  let assetID = descriptor.assetID else {
                if descriptor.path == RecoveryBundle.normalizedProjectPath {
                    return nil
                }
                throw RecoveryBundleError.invalidManifest
            }
            let relativePath = String(
                descriptor.path.dropFirst("campaign/".count)
            )
            let canonical: CanonicalPath
            do {
                canonical = try CanonicalPath(
                    relativePath,
                    maximumDepth: ImportLimits.standard.maximumPathDepth
                )
            } catch {
                throw RecoveryBundleError.invalidAssetPath(relativePath)
            }
            guard let appRelativeURL = URL(
                string: "Campaigns/\(campaignID.uuidString.lowercased())/\(canonical.string)"
            ) else {
                throw RecoveryBundleError.invalidAssetPath(relativePath)
            }
            return ImportedAsset(
                assetID: assetID,
                sha256: descriptor.sha256.lowercased(),
                appRelativeURL: appRelativeURL
            )
        }.sorted { $0.appRelativeURL.relativeString < $1.appRelativeURL.relativeString }
    }

    private func discard(_ staged: StagedImport) {
        let expected = applicationSupportDirectory
            .appendingPathComponent("ImportStaging", isDirectory: true)
            .appendingPathComponent(
                staged.identifier.uuidString.lowercased(),
                isDirectory: true
            )
            .standardizedFileURL
        guard staged.directoryURL.standardizedFileURL == expected else {
            return
        }
        try? FileManager.default.removeItem(at: expected)
    }
}
