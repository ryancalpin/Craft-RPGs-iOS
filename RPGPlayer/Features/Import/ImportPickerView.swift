import SwiftUI
import UniformTypeIdentifiers

enum ImportSheetDestination: Identifiable {
    case campaignImport

    var id: String { "campaign-import" }
}

@MainActor
struct ImportLibraryHostView: View {
    @State private var presentedSheet: ImportSheetDestination?

    let coordinator: ImportCoordinator
    let launchCampaign: (UUID) -> Void

    var body: some View {
        NavigationStack {
            ImportPickerView {
                presentedSheet = .campaignImport
            }
        }
        .sheet(item: $presentedSheet) { _ in
            ImportFlowSheet(coordinator: coordinator)
                .presentationSizing(.form)
        }
        .onChange(of: coordinator.committedCampaignID) { _, campaignID in
            if let campaignID {
                launchCampaign(campaignID)
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("importLibraryHost")
    }
}

struct ImportPickerView: View {
    let beginImport: () -> Void

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Bring in a campaign", systemImage: "square.and.arrow.down")
                        .font(.headline)
                        .foregroundStyle(PlayerTheme.primaryText)
                    Text("Choose a CDF v2 folder, ZIP archive, or JSON project. You will review everything before it is saved.")
                        .foregroundStyle(PlayerTheme.secondaryText)
                    Button(action: beginImport) {
                        Label("Import campaign", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PlayerTheme.accent)
                    .foregroundStyle(Color.black)
                    .controlSize(.large)
                    .accessibilityIdentifier("importCampaignButton")
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(PlayerTheme.opaquePanel)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PlayerTheme.canvas)
        .navigationTitle("Campaigns")
    }
}

@MainActor
struct ImportFlowSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isFileImporterPresented = false

    let coordinator: ImportCoordinator

    var body: some View {
        NavigationStack {
            switch coordinator.state {
            case .idle:
                ProgressView()
                    .tint(PlayerTheme.accent)
            case .selecting(let purpose):
                ImportSourcePickerContent(
                    purpose: purpose,
                    chooseSource: { isFileImporterPresented = true },
                    cancel: cancel
                )
                .onAppear { isFileImporterPresented = true }
            case .processing(let phase):
                ImportProgressView(
                    currentPhase: phase,
                    copiedByteCount: coordinator.copiedByteCount,
                    cancel: coordinator.cancel
                )
            case .reviewing:
                if let review = coordinator.review {
                    ImportReviewView(
                        coordinator: coordinator,
                        summary: review
                    )
                }
            case .mappingHandoff:
                if let draft = coordinator.handoffDraft {
                    HandoffMappingView(
                        draft: draft,
                        onApprove: coordinator.approveHandoff
                    )
                    .navigationTitle("Map handoff")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Back", action: coordinator.returnToReview)
                        }
                    }
                }
            case .committing:
                ImportCommitProgressView()
            case .completed:
                ImportCommitProgressView()
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                coordinator.select(urls)
            case .failure(let error):
                coordinator.selectionFailed(error)
            }
        }
        .interactiveDismissDisabled(coordinator.isCommitting)
        .task { coordinator.start() }
        .onDisappear {
            if coordinator.committedCampaignID == nil,
               coordinator.isCommitting == false {
                coordinator.cancel()
            }
        }
    }

    private var allowedContentTypes: [UTType] {
        guard case .selecting(let purpose) = coordinator.state else {
            return [.folder, .zip, .json]
        }
        switch purpose {
        case .project:
            return [.folder, .zip, .json]
        case .handoff:
            return [Self.markdownType, .plainText]
        }
    }

    private static let markdownType = UTType(
        filenameExtension: "md",
        conformingTo: .plainText
    ) ?? .plainText

    private func cancel() {
        coordinator.cancel()
        dismiss()
    }
}

private struct ImportSourcePickerContent: View {
    let purpose: ImportCoordinator.SelectionPurpose
    let chooseSource: () -> Void
    let cancel: () -> Void

    var body: some View {
        Form {
            Section {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(PlayerTheme.primaryText)
                Text(detail)
                    .foregroundStyle(PlayerTheme.secondaryText)
                Button("Choose source", action: chooseSource)
                    .buttonStyle(.borderedProminent)
                    .tint(PlayerTheme.accent)
                    .foregroundStyle(Color.black)
            }
            .listRowBackground(PlayerTheme.opaquePanel)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(PlayerTheme.canvas)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: cancel)
                    .accessibilityIdentifier("cancelImportButton")
            }
        }
    }

    private var title: LocalizedStringResource {
        switch purpose {
        case .project: "Choose your CDF project"
        case .handoff: "Choose a transcript handoff"
        }
    }

    private var detail: LocalizedStringResource {
        switch purpose {
        case .project: "Folders, ZIP archives, and JSON projects are supported."
        case .handoff: "Markdown and plain-text handoffs are mapped only from structural signals."
        }
    }

    private var navigationTitle: LocalizedStringResource {
        switch purpose {
        case .project: "Import campaign"
        case .handoff: "Add handoff"
        }
    }

    private var systemImage: String {
        switch purpose {
        case .project: "folder"
        case .handoff: "doc.plaintext"
        }
    }
}

private struct ImportCommitProgressView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(PlayerTheme.accent)
            Text("Saving campaign")
                .font(.headline)
                .foregroundStyle(PlayerTheme.primaryText)
            Text("The final file move and campaign event are completing together.")
                .multilineTextAlignment(.center)
                .foregroundStyle(PlayerTheme.secondaryText)
        }
        .padding(PlayerTheme.pageInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PlayerTheme.canvas)
        .navigationTitle("Import campaign")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("importCommitProgressView")
    }
}
