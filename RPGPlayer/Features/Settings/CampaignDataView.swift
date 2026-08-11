import SwiftUI

struct CampaignDataContext: Sendable {
    let campaignID: UUID
    let campaignTitle: String
    let manager: CampaignDataManager
    let recoveryBundleWriter: RecoveryBundleWriter
}

@MainActor
struct CampaignDataView: View {
    @Environment(\.dismiss) private var dismiss

    let context: CampaignDataContext
    let campaignDeleted: @MainActor () -> Void

    @State private var isDeleteConfirmationPresented = false
    @State private var isDeleting = false
    @State private var isExporting = false
    @State private var preparedRecoveryBundleURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Recovery") {
                Button(action: exportRecoveryBundle) {
                    Label(
                        isExporting
                            ? "Preparing Recovery Bundle"
                            : "Export Recovery Bundle",
                        systemImage: "square.and.arrow.up"
                    )
                }
                .disabled(isExporting || isDeleting)
                .accessibilityIdentifier("exportRecoveryBundleButton")

                if let preparedRecoveryBundleURL {
                    ShareLink(item: preparedRecoveryBundleURL) {
                        Label(
                            "Share Recovery Bundle",
                            systemImage: "square.and.arrow.up"
                        )
                    }
                    .accessibilityIdentifier("shareRecoveryBundleButton")
                }

                Text(
                    "The recovery bundle includes this campaign's event history, normalized import, manual voice mappings, and imported assets."
                )
                .font(.footnote)
                .foregroundStyle(PlayerTheme.secondaryText)

                Text("API keys and cached narration are not included.")
                    .font(.footnote)
                    .foregroundStyle(PlayerTheme.secondaryText)
            }
            .listRowBackground(PlayerTheme.opaquePanel)

            Section {
                Button(role: .destructive) {
                    isDeleteConfirmationPresented = true
                } label: {
                    Label(
                        isDeleting ? "Deleting Campaign" : "Delete Campaign",
                        systemImage: "trash"
                    )
                }
                .disabled(isDeleting || isExporting)
                .accessibilityIdentifier("deleteCampaignButton")
                .foregroundStyle(.red)
            } footer: {
                Text("Deletion cannot be undone. Export a recovery bundle first if you may need this campaign again.")
            }
            .listRowBackground(PlayerTheme.opaquePanel)
        }
        .scrollContentBackground(.hidden)
        .background(PlayerTheme.canvas)
        .foregroundStyle(PlayerTheme.primaryText)
        .tint(PlayerTheme.accent)
        .navigationTitle("Campaign Data")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: dismiss.callAsFunction)
                    .disabled(isDeleting || isExporting)
            }
        }
        .alert(
            "Delete \u{201c}\(context.campaignTitle)\u{201d}?",
            isPresented: $isDeleteConfirmationPresented
        ) {
            Button("Delete Campaign", role: .destructive) {
                deleteCampaign()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This permanently deletes its events, imported assets, cached narration, and campaign key references."
            )
        }
        .alert(
            "Campaign Data Error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { presented in
                    if presented == false {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "The operation could not be completed.")
        }
        .interactiveDismissDisabled(isDeleting || isExporting)
        .onDisappear(perform: removePreparedRecoveryBundle)
        .accessibilityIdentifier("campaignDataView")
    }

    private func exportRecoveryBundle() {
        guard isExporting == false else { return }
        isExporting = true
        Task {
            removePreparedRecoveryBundle()
            let archiveURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "campaign-recovery-\(UUID().uuidString.lowercased()).zip",
                    isDirectory: false
                )
            do {
                try await context.recoveryBundleWriter.write(
                    campaignID: context.campaignID,
                    to: archiveURL
                )
                preparedRecoveryBundleURL = archiveURL
            } catch {
                errorMessage = "The recovery bundle could not be prepared."
            }
            isExporting = false
        }
    }

    private func removePreparedRecoveryBundle() {
        guard let preparedRecoveryBundleURL else { return }
        try? FileManager.default.removeItem(at: preparedRecoveryBundleURL)
        self.preparedRecoveryBundleURL = nil
    }

    private func deleteCampaign() {
        guard isDeleting == false else { return }
        isDeleting = true
        Task {
            do {
                try await context.manager.deleteCampaign(context.campaignID)
                dismiss()
                campaignDeleted()
            } catch {
                isDeleting = false
                errorMessage = "The campaign could not be deleted."
            }
        }
    }
}
