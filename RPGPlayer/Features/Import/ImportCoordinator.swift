import CryptoKit
import Foundation
import Observation

enum ImportProgressPhase: Int, CaseIterable, Identifiable, Sendable {
    case copy
    case inspect
    case parse
    case validate
    case prepareReview

    var id: Int { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .copy: "Copy"
        case .inspect: "Inspect"
        case .parse: "Parse"
        case .validate: "Validate"
        case .prepareReview: "Prepare review"
        }
    }
}

struct ImportReviewSummary: Equatable, Sendable {
    var title: String
    var worldSummary: String
    var playerCharacter: String
    var system: String
    var scene: String
    var recordCount: Int
    var assetCount: Int
    var folderCount: Int
    var relationshipCount: Int
    var schemaCount: Int
    var mapCount: Int
    var characterCount: Int
    var warnings: [ImportIssue]
    var fatalErrors: [ImportIssue]
    var handoffUncertainty: [String]
    var requiresHandoffApproval: Bool
    var handoffApproved: Bool

    var missingReferenceCount: Int {
        warnings.filter { $0.code.contains("reference") }.count
    }

    var canCommit: Bool {
        fatalErrors.isEmpty
            && (requiresHandoffApproval == false || handoffApproved)
    }
}

@MainActor
@Observable
final class ImportCoordinator {
    enum SelectionPurpose: Equatable, Sendable {
        case project
        case handoff
    }

    enum State: Equatable {
        case idle
        case selecting(SelectionPurpose)
        case processing(ImportProgressPhase)
        case reviewing
        case mappingHandoff
        case committing
        case completed(UUID)
    }

    private(set) var state: State = .idle
    private(set) var review: ImportReviewSummary?
    private(set) var handoffDraft: HandoffDraft?
    private(set) var isCommitting = false
    private(set) var committedCampaignID: UUID?
    private(set) var copiedByteCount: Int64 = 0

    private let pipeline: ImportPipeline
    private let fixture: ImportFlowFixture?
    private var preparation: PreparedCampaignImport?
    private var pendingStagedImport: StagedImport?
    private var workTask: Task<Void, Never>?

    init(
        pipeline: ImportPipeline,
        fixture: ImportFlowFixture? = nil
    ) {
        self.pipeline = pipeline
        self.fixture = fixture
    }

    func start() {
        committedCampaignID = nil
        review = nil
        handoffDraft = nil
        preparation = nil
        pendingStagedImport = nil
        copiedByteCount = 0

        guard let fixture else {
            state = .selecting(.project)
            return
        }

        workTask = Task { [weak self] in
            guard let self else { return }
            do {
                let source = try await pipeline.makeFixtureSource(fixture)
                await prepareProject(source)
            } catch is CancellationError {
                return
            } catch {
                presentFatal(ImportPipeline.safeIssue(for: error))
            }
        }
    }

    func select(_ urls: [URL]) {
        guard let url = urls.first else { return }
        let purpose: SelectionPurpose
        if case .selecting(let currentPurpose) = state {
            purpose = currentPurpose
        } else {
            purpose = .project
        }
        workTask?.cancel()
        workTask = Task { [weak self] in
            guard let self else { return }
            switch purpose {
            case .project:
                await prepareProject(Self.source(for: url))
            case .handoff:
                await attachHandoff(.handoffDocument(url))
            }
        }
    }

    func selectionFailed(_ error: Error) {
        if (error as? CocoaError)?.code == .userCancelled {
            state = preparation == nil ? .selecting(.project) : .reviewing
            return
        }
        presentFatal(ImportPipeline.safeIssue(for: error))
    }

    func approveHandoff(_ checkpoint: ApprovedHandoffCheckpoint) {
        guard var preparation else { return }
        preparation.approvedHandoff = checkpoint
        preparation.review.worldSummary = checkpoint.summary
        preparation.review.playerCharacter = checkpoint.playerCharacter
        preparation.review.scene = checkpoint.currentScene
        preparation.review.handoffApproved = true
        self.preparation = preparation
        review = preparation.review
        state = .reviewing
    }

    func selectHandoff() {
        guard preparation != nil, isCommitting == false else { return }
        state = .selecting(.handoff)
    }

    func mapHandoff() {
        guard handoffDraft != nil else { return }
        state = .mappingHandoff
    }

    func returnToReview() {
        guard review != nil else { return }
        state = .reviewing
    }

    func confirm() {
        guard isCommitting == false,
              let preparation,
              preparation.review.canCommit
        else {
            return
        }

        isCommitting = true
        state = .committing
        workTask?.cancel()
        workTask = Task { [weak self] in
            guard let self else { return }
            do {
                let campaignID = try await pipeline.commit(preparation)
                isCommitting = false
                committedCampaignID = campaignID
                state = .completed(campaignID)
            } catch {
                var recovered = preparation
                recovered.review.warnings.append(
                    ImportPipeline.safeIssue(for: error)
                )
                self.preparation = recovered
                review = recovered.review
                state = .reviewing
                isCommitting = false
            }
        }
    }

    func cancel() {
        guard isCommitting == false else { return }
        workTask?.cancel()
        let discarded = [preparation?.stagedImport, pendingStagedImport]
            .compactMap { $0 }
        preparation = nil
        pendingStagedImport = nil
        review = nil
        handoffDraft = nil
        state = .idle

        for staged in discarded {
            Task { await pipeline.discard(staged) }
        }
    }

    private func prepareProject(_ source: ImportSource) async {
        do {
            copiedByteCount = 0
            state = .processing(.copy)
            let staged = try await pipeline.stage(source) { [weak self] bytes in
                Task { @MainActor in
                    self?.copiedByteCount += bytes
                }
            }
            pendingStagedImport = staged
            try Task.checkCancellation()

            state = .processing(.inspect)
            let inspected = try await pipeline.inspect(staged, source: source)
            try Task.checkCancellation()

            state = .processing(.parse)
            let parsed = try await pipeline.parse(inspected)
            try Task.checkCancellation()

            state = .processing(.validate)
            let validated = await pipeline.validate(parsed)
            try Task.checkCancellation()

            state = .processing(.prepareReview)
            let prepared = try await pipeline.prepareReview(validated)
            try Task.checkCancellation()

            preparation = prepared
            pendingStagedImport = nil
            review = prepared.review
            state = .reviewing
        } catch is CancellationError {
            return
        } catch {
            presentFatal(ImportPipeline.safeIssue(for: error))
        }
    }

    private func attachHandoff(_ source: ImportSource) async {
        guard var preparation else { return }
        do {
            copiedByteCount = 0
            state = .processing(.copy)
            let staged = try await pipeline.stage(source) { [weak self] bytes in
                Task { @MainActor in
                    self?.copiedByteCount += bytes
                }
            }
            pendingStagedImport = staged
            try Task.checkCancellation()
            state = .processing(.inspect)
            let inspected = try await pipeline.inspectHandoff(staged)
            try Task.checkCancellation()
            state = .processing(.parse)
            let draft = try await pipeline.parseHandoff(inspected)
            await pipeline.discard(staged)
            pendingStagedImport = nil
            try Task.checkCancellation()
            state = .processing(.validate)
            let validated = await pipeline.validateHandoff(draft)
            try Task.checkCancellation()
            state = .processing(.prepareReview)
            preparation.review = await pipeline.prepareHandoffReview(
                validated,
                applyingTo: preparation.review
            )
            try Task.checkCancellation()

            handoffDraft = draft
            preparation.approvedHandoff = nil
            self.preparation = preparation
            review = preparation.review
            state = .reviewing
        } catch is CancellationError {
            return
        } catch {
            var failed = preparation
            failed.review.fatalErrors.append(ImportPipeline.safeIssue(for: error))
            self.preparation = failed
            review = failed.review
            state = .reviewing
        }
    }

    private func presentFatal(_ issue: ImportIssue) {
        let summary = ImportReviewSummary(
            title: "Import could not be prepared",
            worldSummary: "",
            playerCharacter: "",
            system: "",
            scene: "",
            recordCount: 0,
            assetCount: 0,
            folderCount: 0,
            relationshipCount: 0,
            schemaCount: 0,
            mapCount: 0,
            characterCount: 0,
            warnings: [],
            fatalErrors: [issue],
            handoffUncertainty: [],
            requiresHandoffApproval: false,
            handoffApproved: false
        )
        review = summary
        state = .reviewing
    }

    private static func source(for url: URL) -> ImportSource {
        if url.hasDirectoryPath {
            return .folder(url)
        }
        if url.pathExtension.lowercased() == "zip" {
            return .archive(url)
        }
        return .handoffDocument(url)
    }
}

enum PreparedImportContent: Equatable, Sendable {
    case cdf(NormalizedProject)
    case unreadable
}

struct PreparedCampaignImport: Equatable, Sendable {
    let campaignID: UUID
    let stagedImport: StagedImport
    let content: PreparedImportContent
    let manifestHash: String
    var approvedHandoff: ApprovedHandoffCheckpoint?
    var review: ImportReviewSummary
}

enum CampaignImportCommitError: Error, Equatable, Sendable {
    case invalidStagingLocation
    case campaignAlreadyExists
    case unableToMoveCampaign
    case persistenceFailed
}

struct InspectedProjectImport: Equatable, Sendable {
    let stagedImport: StagedImport
}

struct ParsedProjectImport: Equatable, Sendable {
    let stagedImport: StagedImport
    let project: NormalizedProject
}

struct ValidatedProjectImport: Equatable, Sendable {
    let stagedImport: StagedImport
    let project: NormalizedProject
    let report: ImportReport

    var canCommit: Bool { report.canCommit }
}

struct InspectedHandoffImport: Equatable, Sendable {
    let stagedImport: StagedImport
    let relativePath: String
}

struct ValidatedHandoffImport: Equatable, Sendable {
    let draft: HandoffDraft
    let uncertainty: [String]
}

actor ImportPipeline {
    private let store: any CampaignStore
    private let applicationSupportDirectory: URL
    private let stager: ImportStager

    init(
        store: any CampaignStore,
        applicationSupportDirectory: URL? = nil
    ) {
        let support = applicationSupportDirectory
            ?? FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
        self.store = store
        self.applicationSupportDirectory = support
        stager = ImportStager(applicationSupportDirectory: support)
    }

    func stage(
        _ source: ImportSource,
        progress: @escaping @Sendable (Int64) -> Void = { _ in }
    ) async throws -> StagedImport {
        try await stager.stage(source, progress: progress)
    }

    func inspect(
        _ stagedImport: StagedImport,
        source: ImportSource
    ) throws -> InspectedProjectImport {
        let staged = try normalizeSingleJSONDocumentIfNeeded(
            stagedImport,
            source: source
        )
        guard staged.files.contains(where: {
            $0.relativePath == "project.json"
        }) else {
            throw CDFDecodingError.unreadableRoot("Missing project.json")
        }
        return InspectedProjectImport(stagedImport: staged)
    }

    func parse(
        _ inspected: InspectedProjectImport
    ) throws -> ParsedProjectImport {
        ParsedProjectImport(
            stagedImport: inspected.stagedImport,
            project: try CDFDecoder().decodeProject(inspected.stagedImport)
        )
    }

    func validate(
        _ parsed: ParsedProjectImport
    ) -> ValidatedProjectImport {
        let warnings = ReferenceValidator().warnings(
            for: parsed.project,
            stagedRelativePaths: Set(
                parsed.stagedImport.files.map(\.relativePath)
            )
        )
        let report = ImportReport(
            projectTitle: parsed.project.title,
            recordCount: parsed.project.records.count,
            assetCount: parsed.project.assets.count,
            warnings: warnings,
            fatalErrors: []
        )
        return ValidatedProjectImport(
            stagedImport: parsed.stagedImport,
            project: parsed.project,
            report: report
        )
    }

    func prepareReview(
        _ validated: ValidatedProjectImport
    ) throws -> PreparedCampaignImport {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let normalizedData = try encoder.encode(validated.project)
        try normalizedData.write(
            to: validated.stagedImport.directoryURL.appendingPathComponent(
                "normalized-project.json",
                isDirectory: false
            ),
            options: .atomic
        )
        let manifestHash = "sha256:" + FileHashing.hexadecimal(
            SHA256.hash(data: try encoder.encode(validated.project.manifest))
        )
        return PreparedCampaignImport(
            campaignID: UUID(),
            stagedImport: validated.stagedImport,
            content: .cdf(validated.project),
            manifestHash: manifestHash,
            approvedHandoff: nil,
            review: Self.review(
                for: validated.project,
                report: validated.report
            )
        )
    }

    func inspectHandoff(
        _ staged: StagedImport
    ) throws -> InspectedHandoffImport {
        guard staged.files.count == 1, let file = staged.files.first
        else {
            throw ImportValidationError.unsupportedSource
        }
        _ = try CanonicalPath(
            file.relativePath,
            maximumDepth: ImportLimits.standard.maximumPathDepth
        )
        return InspectedHandoffImport(
            stagedImport: staged,
            relativePath: file.relativePath
        )
    }

    func parseHandoff(
        _ inspected: InspectedHandoffImport
    ) throws -> HandoffDraft {
        let url = inspected.stagedImport.directoryURL.appendingPathComponent(
            inspected.relativePath
        )
        return try HandoffParser().parse(data: Data(contentsOf: url))
    }

    func validateHandoff(_ draft: HandoffDraft) -> ValidatedHandoffImport {
        ValidatedHandoffImport(
            draft: draft,
            uncertainty: Self.uncertainty(for: draft)
        )
    }

    func prepareHandoffReview(
        _ validated: ValidatedHandoffImport,
        applyingTo current: ImportReviewSummary
    ) -> ImportReviewSummary {
        var review = current
        let draft = validated.draft
        review.worldSummary = draft.summary.isEmpty
            ? review.worldSummary
            : draft.summary
        review.playerCharacter = draft.playerCharacter.isEmpty
            ? review.playerCharacter
            : draft.playerCharacter
        review.scene = draft.currentScene.isEmpty
            ? review.scene
            : draft.currentScene
        review.handoffUncertainty = validated.uncertainty
        review.requiresHandoffApproval = true
        review.handoffApproved = false
        return review
    }

    func commit(_ preparation: PreparedCampaignImport) async throws -> UUID {
        guard preparation.review.canCommit else {
            throw CampaignImportCommitError.persistenceFailed
        }

        let event = Self.initialEvent(for: preparation)
        let importedAssets = Self.importedAssets(
            for: preparation,
            campaignComponent: preparation.campaignID.uuidString.lowercased()
        )

        let identifier = preparation.stagedImport.identifier.uuidString.lowercased()
        let expectedStage = applicationSupportDirectory
            .appendingPathComponent("ImportStaging", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
            .standardizedFileURL
        let stage = preparation.stagedImport.directoryURL.standardizedFileURL
        guard stage == expectedStage else {
            throw CampaignImportCommitError.invalidStagingLocation
        }

        let campaignsRoot = applicationSupportDirectory.appendingPathComponent(
            "Campaigns",
            isDirectory: true
        )
        let campaignComponent = preparation.campaignID.uuidString.lowercased()
        let destination = campaignsRoot
            .appendingPathComponent(campaignComponent, isDirectory: true)
            .standardizedFileURL
        guard destination.deletingLastPathComponent() == campaignsRoot.standardizedFileURL,
              destination.lastPathComponent == campaignComponent
        else {
            throw CampaignImportCommitError.invalidStagingLocation
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: campaignsRoot,
            withIntermediateDirectories: true
        )
        guard fileManager.fileExists(atPath: destination.path) == false else {
            throw CampaignImportCommitError.campaignAlreadyExists
        }

        do {
            try fileManager.moveItem(at: stage, to: destination)
        } catch {
            throw CampaignImportCommitError.unableToMoveCampaign
        }

        do {
            _ = try await store.append(
                batch: [event],
                assets: importedAssets,
                expectedSequence: 0
            )
            return preparation.campaignID
        } catch {
            do {
                try fileManager.moveItem(at: destination, to: stage)
            } catch {
                throw CampaignImportCommitError.unableToMoveCampaign
            }
            throw CampaignImportCommitError.persistenceFailed
        }
    }

    func discard(_ staged: StagedImport) {
        let identifier = staged.identifier.uuidString.lowercased()
        let expected = applicationSupportDirectory
            .appendingPathComponent("ImportStaging", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
            .standardizedFileURL
        guard staged.directoryURL.standardizedFileURL == expected else { return }
        try? FileManager.default.removeItem(at: expected)
    }

    func makeFixtureSource(_ fixture: ImportFlowFixture) throws -> ImportSource {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RPGPlayerImportFlow", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let data = Data(fixture.projectJSON.utf8)
        try data.write(
            to: root.appendingPathComponent("project.json"),
            options: .atomic
        )
        return .folder(root)
    }

    static func safeIssue(for error: Error) -> ImportIssue {
        if let decodingError = error as? CDFDecodingError {
            return safeCDFIssue(decodingError)
        }
        if let validationError = error as? ImportValidationError {
            return safeImportValidationIssue(validationError)
        }
        return switch error {
        case CampaignImportCommitError.invalidStagingLocation:
            ImportIssue(
                code: "invalid_staging_location",
                message: "The app-owned staging location is invalid.",
                relativePath: nil
            )
        case CampaignImportCommitError.campaignAlreadyExists:
            ImportIssue(
                code: "campaign_already_exists",
                message: "A campaign already exists at this destination.",
                relativePath: nil
            )
        case CampaignImportCommitError.unableToMoveCampaign:
            ImportIssue(
                code: "campaign_move_failed",
                message: "The campaign files could not be moved safely.",
                relativePath: nil
            )
        case CampaignImportCommitError.persistenceFailed:
            ImportIssue(
                code: "campaign_commit_failed",
                message: "The campaign was not committed. Review and try again.",
                relativePath: nil
            )
        default:
            ImportIssue(
                code: "import_failed",
                message: "The selected source could not be imported.",
                relativePath: nil
            )
        }
    }

    private static func safeImportValidationIssue(
        _ error: ImportValidationError
    ) -> ImportIssue {
        switch error {
        case .absolutePath(let path):
            ImportIssue(
                code: "absolute_path",
                message: "An absolute path is not allowed.",
                relativePath: safeRelativePath(path)
            )
        case .nullByte(let path):
            ImportIssue(
                code: "invalid_path_character",
                message: "A path contains an invalid character.",
                relativePath: safeRelativePath(path)
            )
        case .pathTraversal(let path):
            ImportIssue(
                code: "path_traversal",
                message: "A path leaves the import root.",
                relativePath: safeRelativePath(path)
            )
        case .pathDepthExceeded(let path):
            ImportIssue(
                code: "path_depth_exceeded",
                message: "A path exceeds the nesting limit.",
                relativePath: safeRelativePath(path)
            )
        case .emptyPath:
            ImportIssue(
                code: "empty_path",
                message: "An import entry has no usable path."
            )
        case .duplicateCanonicalPath(let path):
            ImportIssue(
                code: "duplicate_path",
                message: "Two import entries resolve to the same path.",
                relativePath: safeRelativePath(path)
            )
        case .escapingSymbolicLink(let path):
            ImportIssue(
                code: "escaping_symbolic_link",
                message: "A symbolic link leaves the import root.",
                relativePath: safeRelativePath(path)
            )
        case .fileTooLarge(let path):
            ImportIssue(
                code: "file_too_large",
                message: "A file exceeds the import size limit.",
                relativePath: safeRelativePath(path)
            )
        case .tooManyEntries:
            ImportIssue(
                code: "too_many_entries",
                message: "The import contains too many entries."
            )
        case .totalExpandedSizeExceeded:
            ImportIssue(
                code: "expanded_size_exceeded",
                message: "The expanded import exceeds the total size limit."
            )
        case .archiveExpansionRatioExceeded:
            ImportIssue(
                code: "archive_expansion_ratio_exceeded",
                message: "The archive expansion ratio exceeds the safe limit."
            )
        case .executableEntry(let path):
            ImportIssue(
                code: "executable_entry",
                message: "Executable files cannot be imported.",
                relativePath: safeRelativePath(path)
            )
        case .unsupportedSymbolicLink(let path):
            ImportIssue(
                code: "unsupported_symbolic_link",
                message: "Symbolic links cannot be imported.",
                relativePath: safeRelativePath(path)
            )
        case .invalidArchive:
            ImportIssue(
                code: "invalid_archive",
                message: "The selected archive could not be inspected."
            )
        case .unsupportedSource:
            ImportIssue(
                code: "unsupported_source",
                message: "The selected source type is not supported."
            )
        case .stagingDirectoryAlreadyExists:
            ImportIssue(
                code: "staging_conflict",
                message: "A new app-owned staging directory could not be created."
            )
        }
    }

    private static func safeRelativePath(_ rawPath: String) -> String? {
        let withoutControls = String(
            rawPath.unicodeScalars.filter {
                CharacterSet.controlCharacters.contains($0) == false
            }
        )
        let normalizedSeparators = withoutControls.replacingOccurrences(
            of: "\\",
            with: "/"
        )
        let components = normalizedSeparators.split(
            separator: "/",
            omittingEmptySubsequences: true
        )
        guard let last = components.last else { return nil }

        let isAbsolute = (normalizedSeparators as NSString).isAbsolutePath
            || normalizedSeparators.first == "/"
            || (components.first?.hasSuffix(":") == true)
        let traverses = components.contains("..")
        if isAbsolute || traverses {
            return String(last)
        }

        if let canonical = try? CanonicalPath(
            normalizedSeparators,
            maximumDepth: ImportLimits.standard.maximumPathDepth
        ) {
            return canonical.string
        }
        return String(last)
    }

    private static func safeCDFIssue(
        _ error: CDFDecodingError
    ) -> ImportIssue {
        switch error {
        case .invalidMetadata:
            ImportIssue(
                code: "invalid_metadata",
                message: "The project metadata could not be read.",
                relativePath: "project.json"
            )
        case .invalidFileTypes:
            ImportIssue(
                code: "invalid_file_types",
                message: "The project file types could not be read.",
                relativePath: "project.json"
            )
        case .invalidContent:
            ImportIssue(
                code: "invalid_content",
                message: "The project content could not be read.",
                relativePath: "project.json"
            )
        case .unsupportedCDFVersion:
            ImportIssue(
                code: "unsupported_cdf_version",
                message: "This CDF version is not supported.",
                relativePath: "project.json"
            )
        case .duplicateIdentifier:
            ImportIssue(
                code: "duplicate_identifier",
                message: "The project contains a duplicate identifier.",
                relativePath: "project.json"
            )
        case .unreadableRoot:
            ImportIssue(
                code: "unreadable_root",
                message: "The project root could not be read.",
                relativePath: "project.json"
            )
        case .invalidAssetPath:
            ImportIssue(
                code: "invalid_asset_path",
                message: "An asset path is not safe to import.",
                relativePath: nil
            )
        }
    }

    private static func review(
        for project: NormalizedProject,
        report: ImportReport
    ) -> ImportReviewSummary {
        ImportReviewSummary(
            title: project.title,
            worldSummary: project.summary ?? "Not specified",
            playerCharacter: recordLabel(
                id: project.playerCharacterRecordID,
                preferredField: "name",
                project: project
            ),
            system: project.system ?? "Not specified",
            scene: recordLabel(
                id: project.currentSceneRecordID,
                preferredField: "title",
                project: project
            ),
            recordCount: report.recordCount,
            assetCount: report.assetCount,
            folderCount: project.folders.count,
            relationshipCount: project.relationships.count,
            schemaCount: project.schemas.count,
            mapCount: project.maps.count,
            characterCount: project.characters.count,
            warnings: report.warnings,
            fatalErrors: report.fatalErrors,
            handoffUncertainty: [],
            requiresHandoffApproval: false,
            handoffApproved: false
        )
    }

    private static func uncertainty(for draft: HandoffDraft) -> [String] {
        draft.reviewFlags.map { flag in
            switch flag {
            case .emptyInput: "The handoff is empty."
            case .unstructuredText: "Plain text needs your review."
            case .speakerMappingRequired: "Speaker labels need mapping."
            case .ambiguousSpeakerNames: "The player character is ambiguous."
            }
        }
    }

    private static func recordLabel(
        id: String?,
        preferredField: String,
        project: NormalizedProject
    ) -> String {
        guard let id,
              let record = project.records.first(where: { $0.id == id })
        else {
            return "Not identified"
        }
        let preferred = record.fields.first {
            $0.id.caseInsensitiveCompare(preferredField) == .orderedSame
        }
        guard case .string(let value)? = preferred?.value else {
            return id
        }
        return value
    }

    private static func initialEvent(
        for preparation: PreparedCampaignImport
    ) -> CampaignEvent {
        let projectID: String
        switch preparation.content {
        case .cdf(let project):
            projectID = project.id
        case .unreadable:
            projectID = "unreadable"
        }
        var payload = CampaignImportedPayload(
            projectID: projectID,
            campaignTitle: preparation.review.title,
            manifestHash: preparation.manifestHash,
            extensionPayload: [
                "importScope": .string(CDFImportScope.projectWorldContent.rawValue)
            ]
        )
        if let checkpoint = preparation.approvedHandoff {
            payload = checkpoint.applying(to: payload)
        }
        return CampaignEvent(
            id: UUID(),
            campaignID: preparation.campaignID,
            sequence: 0,
            requestID: UUID(),
            timestamp: Date(),
            schemaVersion: 1,
            payload: .campaignImported(payload)
        )
    }

    private static func importedAssets(
        for preparation: PreparedCampaignImport,
        campaignComponent: String
    ) -> [ImportedAsset] {
        guard case .cdf(let project) = preparation.content else { return [] }
        let files = Dictionary(
            uniqueKeysWithValues: preparation.stagedImport.files.map {
                ($0.relativePath, $0)
            }
        )
        return project.assets.compactMap { asset in
            guard let file = files[asset.relativePath],
                  let relativeURL = URL(
                    string: "Campaigns/\(campaignComponent)/\(asset.relativePath)"
                  )
            else {
                return nil
            }
            return ImportedAsset(
                assetID: asset.id,
                sha256: file.sha256,
                appRelativeURL: relativeURL
            )
        }
    }

    private func normalizeSingleJSONDocumentIfNeeded(
        _ staged: StagedImport,
        source: ImportSource
    ) throws -> StagedImport {
        guard source.kind == .handoffDocument,
              source.url.pathExtension.lowercased() == "json",
              staged.files.count == 1,
              let file = staged.files.first,
              file.relativePath != "project.json"
        else {
            return staged
        }
        let sourceURL = staged.directoryURL.appendingPathComponent(
            file.relativePath,
            isDirectory: false
        )
        let destinationURL = staged.directoryURL.appendingPathComponent(
            "project.json",
            isDirectory: false
        )
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        return StagedImport(
            identifier: staged.identifier,
            directoryURL: staged.directoryURL,
            files: [
                StagedFile(
                    relativePath: "project.json",
                    byteCount: file.byteCount,
                    sha256: file.sha256
                )
            ]
        )
    }
}

enum ImportFlowFixture: String, Sendable {
    case cancel
    case warning
    case fatal
    case success

    init?(arguments: [String]) {
        guard arguments.contains("-ui-testing") else { return nil }
        guard let index = arguments.firstIndex(of: "-import-flow-fixture"),
              arguments.indices.contains(index + 1)
        else {
            return nil
        }
        self.init(rawValue: arguments[index + 1])
    }

    var projectJSON: String {
        switch self {
        case .fatal:
            """
            { "PRIVATE SOURCE CONTENT": true, "project": "broken" }
            """
        case .warning:
            Self.validProject(
                title: "Greyhaven Warning",
                currentSceneID: "missing-scene"
            )
        case .cancel, .success:
            Self.validProject(
                title: "Greyhaven Ready",
                currentSceneID: "scene-1"
            )
        }
    }

    private static func validProject(
        title: String,
        currentSceneID: String
    ) -> String {
        """
        {
          "cdfVersion": 2,
          "project": {
            "id": "greyhaven-project",
            "title": "\(title)",
            "summary": "A harbor mystery prepared as project-world content.",
            "system": "D20 Fantasy",
            "rootFolderID": "folder-root",
            "currentSceneRecordID": "\(currentSceneID)",
            "playerCharacterRecordID": "hero-1"
          },
          "fileTypes": [
            {
              "id": "scene",
              "name": "Scene",
              "recordKind": "scene",
              "fields": [
                { "id": "title", "name": "Title", "valueType": "string", "required": true }
              ]
            },
            {
              "id": "character",
              "name": "Character",
              "recordKind": "character",
              "fields": [
                { "id": "name", "name": "Name", "valueType": "string", "required": true }
              ]
            }
          ],
          "content": {
            "folders": [
              { "id": "folder-root", "name": "Greyhaven" }
            ],
            "records": [
              {
                "id": "scene-1",
                "fileTypeID": "scene",
                "folderID": "folder-root",
                "fields": [
                  { "id": "title", "value": "The Fogbound Harbor" }
                ]
              },
              {
                "id": "hero-1",
                "fileTypeID": "character",
                "folderID": "folder-root",
                "fields": [
                  { "id": "name", "value": "Mara Venn" }
                ]
              }
            ],
            "relationships": [],
            "assets": [],
            "maps": [],
            "characters": [
              { "id": "character-hero", "recordID": "hero-1" }
            ]
          }
        }
        """
    }
}
