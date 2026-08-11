import CryptoKit
import Foundation
import ZIPFoundation

struct RecoveryBundleWriter: Sendable {
    private struct SourceEntry {
        let archivePath: String
        let assetID: String?
        let source: Source

        enum Source {
            case data(Data)
            case file(URL)
        }
    }

    private let store: any CampaignStore
    private let campaignDirectory: CampaignDirectory

    init(
        store: any CampaignStore,
        campaignDirectory: CampaignDirectory = CampaignDirectory()
    ) {
        self.store = store
        self.campaignDirectory = campaignDirectory
    }

    func write(campaignID: UUID, to archiveURL: URL) async throws {
        let events = try await allEvents(for: campaignID)
        guard events.isEmpty == false else {
            throw RecoveryBundleError.campaignHasNoEvents(campaignID)
        }

        let campaignURL = campaignDirectory.campaignURL(for: campaignID)
        let normalizedURL = campaignURL.appendingPathComponent(
            "normalized-project.json",
            isDirectory: false
        )
        guard FileManager.default.fileExists(atPath: normalizedURL.path) else {
            throw RecoveryBundleError.missingCampaignFile(
                "normalized-project.json"
            )
        }

        let assets = try await store.importedAssets(for: campaignID)
        var sourceEntries = [
            SourceEntry(
                archivePath: RecoveryBundle.eventsPath,
                assetID: nil,
                source: .data(try encodeEvents(events))
            ),
            SourceEntry(
                archivePath: RecoveryBundle.manualVoiceMappingsPath,
                assetID: nil,
                source: .data(try encodeManualVoiceMappings(events))
            ),
            SourceEntry(
                archivePath: RecoveryBundle.normalizedProjectPath,
                assetID: nil,
                source: .file(normalizedURL)
            )
        ]

        for asset in assets.sorted(by: { $0.appRelativeURL.relativeString < $1.appRelativeURL.relativeString }) {
            let relativePath = try campaignRelativePath(
                for: asset,
                campaignID: campaignID
            )
            let sourceURL = campaignURL
                .appendingPathComponent(relativePath, isDirectory: false)
                .standardizedFileURL
            guard sourceURL.deletingLastPathComponent().path.hasPrefix(
                campaignURL.path
            ), FileManager.default.fileExists(atPath: sourceURL.path) else {
                throw RecoveryBundleError.missingCampaignFile(relativePath)
            }
            let actualHash = try FileHashing.sha256(of: sourceURL)
            guard actualHash == asset.sha256.lowercased() else {
                throw RecoveryBundleError.assetHashMismatch(relativePath)
            }
            sourceEntries.append(
                SourceEntry(
                    archivePath: "campaign/\(relativePath)",
                    assetID: asset.assetID,
                    source: .file(sourceURL)
                )
            )
        }
        sourceEntries.sort { $0.archivePath < $1.archivePath }

        let descriptors = try sourceEntries.map(descriptor)
        let manifest = RecoveryBundleManifest(
            campaignID: campaignID,
            entries: descriptors
        )
        let manifestData = try jsonEncoder().encode(manifest)

        guard FileManager.default.fileExists(atPath: archiveURL.path) == false else {
            throw RecoveryBundleError.unableToCreateArchive
        }
        let archive: Archive
        do {
            archive = try Archive(
                url: archiveURL,
                accessMode: .create,
                pathEncoding: nil
            )
        } catch {
            throw RecoveryBundleError.unableToCreateArchive
        }

        try add(data: manifestData, path: RecoveryBundle.manifestPath, to: archive)
        for entry in sourceEntries {
            switch entry.source {
            case .data(let data):
                try add(data: data, path: entry.archivePath, to: archive)
            case .file(let url):
                try add(file: url, path: entry.archivePath, to: archive)
            }
        }
    }

    private func allEvents(for campaignID: UUID) async throws -> [CampaignEvent] {
        let latest = try await store.latestSequence(for: campaignID)
        var events: [CampaignEvent] = []
        var cursor: Int64 = 0
        while cursor < latest {
            let page = try await store.events(
                for: campaignID,
                after: cursor,
                limit: 256
            )
            guard let last = page.last else { break }
            events.append(contentsOf: page)
            cursor = last.sequence
        }
        return events
    }

    private func encodeEvents(_ events: [CampaignEvent]) throws -> Data {
        let encoder = jsonEncoder()
        return try events.sorted(by: { $0.sequence < $1.sequence }).reduce(
            into: Data()
        ) { data, event in
            data.append(try encoder.encode(event))
            data.append(0x0A)
        }
    }

    private func encodeManualVoiceMappings(
        _ events: [CampaignEvent]
    ) throws -> Data {
        let projection = CampaignReducer().reduce(
            CampaignProjection(campaignID: events[0].campaignID),
            events: events
        ).projection
        let mappings = projection.voiceAssignments.values.compactMap {
            assignment -> RecoveryVoiceMapping? in
            guard assignment.source == .manual,
                  let voiceID = assignment.voiceID else {
                return nil
            }
            return RecoveryVoiceMapping(
                characterID: assignment.characterID,
                voiceID: voiceID
            )
        }.sorted { $0.characterID < $1.characterID }
        return try jsonEncoder().encode(mappings)
    }

    private func campaignRelativePath(
        for asset: ImportedAsset,
        campaignID: UUID
    ) throws -> String {
        let prefix = "Campaigns/\(campaignID.uuidString.lowercased())/"
        let storedPath = asset.appRelativeURL.relativeString
        guard storedPath.hasPrefix(prefix) else {
            throw RecoveryBundleError.invalidAssetPath(storedPath)
        }
        let relativePath = String(storedPath.dropFirst(prefix.count))
        let canonical: CanonicalPath
        do {
            canonical = try CanonicalPath(
                relativePath,
                maximumDepth: ImportLimits.standard.maximumPathDepth
            )
        } catch {
            throw RecoveryBundleError.invalidAssetPath(relativePath)
        }
        return canonical.string
    }

    private func descriptor(
        for entry: SourceEntry
    ) throws -> RecoveryBundleEntryDescriptor {
        switch entry.source {
        case .data(let data):
            RecoveryBundleEntryDescriptor(
                path: entry.archivePath,
                byteCount: Int64(data.count),
                sha256: FileHashing.hexadecimal(SHA256.hash(data: data)),
                assetID: entry.assetID
            )
        case .file(let url):
            RecoveryBundleEntryDescriptor(
                path: entry.archivePath,
                byteCount: try fileSize(at: url),
                sha256: try FileHashing.sha256(of: url),
                assetID: entry.assetID
            )
        }
    }

    private func add(data: Data, path: String, to archive: Archive) throws {
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(data.count),
            modificationDate: Self.fixedModificationDate,
            permissions: 0o644,
            compressionMethod: .deflate
        ) { position, size in
            let start = Int(position)
            let end = min(start + size, data.count)
            return data.subdata(in: start..<end)
        }
    }

    private func add(file url: URL, path: String, to archive: Archive) throws {
        let size = try fileSize(at: url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: size,
            modificationDate: Self.fixedModificationDate,
            permissions: 0o644,
            compressionMethod: .deflate,
            bufferSize: FileHashing.chunkSize
        ) { position, requestedSize in
            try handle.seek(toOffset: UInt64(position))
            return try handle.read(upToCount: requestedSize) ?? Data()
        }
    }

    private func fileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        guard let number = attributes[.size] as? NSNumber else {
            throw RecoveryBundleError.missingCampaignFile(
                url.lastPathComponent
            )
        }
        return number.int64Value
    }

    private func jsonEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static let fixedModificationDate = Date(
        timeIntervalSince1970: 315_532_800
    )
}
