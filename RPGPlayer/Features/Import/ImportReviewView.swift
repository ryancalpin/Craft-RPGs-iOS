import SwiftUI

@MainActor
struct ImportReviewView: View {
    @Environment(\.dismiss) private var dismiss

    let coordinator: ImportCoordinator
    let summary: ImportReviewSummary

    var body: some View {
        Form {
            ImportUnderstandingSection(summary: summary)
            ImportEntityCountsSection(summary: summary)
            ImportWarningsView(
                warnings: summary.warnings,
                fatalErrors: summary.fatalErrors
            )
            ImportHandoffSection(
                uncertainty: summary.handoffUncertainty,
                requiresApproval: summary.requiresHandoffApproval,
                approved: summary.handoffApproved,
                selectHandoff: coordinator.selectHandoff,
                reviewMapping: coordinator.mapHandoff
            )
            ImportScopeSection()
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(PlayerTheme.canvas)
        .navigationTitle("Review import")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    coordinator.cancel()
                    dismiss()
                }
                .disabled(coordinator.isCommitting)
                .accessibilityIdentifier("cancelImportButton")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Confirm") {
                    coordinator.confirm()
                }
                .disabled(summary.canCommit == false || coordinator.isCommitting)
                .accessibilityIdentifier("confirmImportButton")
            }
        }
        .accessibilityIdentifier("importReviewView")
    }
}

private struct ImportUnderstandingSection: View {
    let summary: ImportReviewSummary

    var body: some View {
        Section("What I understood") {
            ImportReviewValueRow(label: "Title", value: summary.title)
            ImportReviewValueRow(label: "World summary", value: summary.worldSummary)
            ImportReviewValueRow(label: "Player character", value: summary.playerCharacter)
            ImportReviewValueRow(label: "System", value: summary.system)
            ImportReviewValueRow(label: "Current scene", value: summary.scene)
        }
    }
}

private struct ImportReviewValueRow: View {
    let label: LocalizedStringResource
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(PlayerTheme.secondaryText)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(PlayerTheme.primaryText)
                .multilineTextAlignment(.trailing)
        }
        .listRowBackground(PlayerTheme.opaquePanel)
    }
}

private struct ImportEntityCountsSection: View {
    let summary: ImportReviewSummary

    var body: some View {
        Section("Content counts") {
            LabeledContent("Records", value: summary.recordCount, format: .number)
            LabeledContent("Assets", value: summary.assetCount, format: .number)
            LabeledContent("Folders", value: summary.folderCount, format: .number)
            LabeledContent(
                "Relationships",
                value: summary.relationshipCount,
                format: .number
            )
            LabeledContent("Schemas", value: summary.schemaCount, format: .number)
            LabeledContent("Maps", value: summary.mapCount, format: .number)
            LabeledContent(
                "Characters",
                value: summary.characterCount,
                format: .number
            )
        }
        .listRowBackground(PlayerTheme.opaquePanel)
    }
}

private struct ImportHandoffSection: View {
    let uncertainty: [String]
    let requiresApproval: Bool
    let approved: Bool
    let selectHandoff: () -> Void
    let reviewMapping: () -> Void

    var body: some View {
        Section("Transcript handoff") {
            if requiresApproval {
                Label(
                    approved ? "Mapping approved" : "Approval required",
                    systemImage: approved ? "checkmark.circle.fill" : "questionmark.circle"
                )
                .foregroundStyle(approved ? Color.green : PlayerTheme.accent)

                ForEach(uncertainty, id: \.self) { note in
                    Text(note)
                        .foregroundStyle(PlayerTheme.secondaryText)
                }

                Button("Review handoff mapping", action: reviewMapping)
            } else {
                Text("No transcript handoff is attached.")
                    .foregroundStyle(PlayerTheme.secondaryText)
                Button("Add transcript handoff", action: selectHandoff)
            }
        }
        .listRowBackground(PlayerTheme.opaquePanel)
    }
}

private struct ImportScopeSection: View {
    var body: some View {
        Section {
            Label {
                Text("This imports project and world content. It does not claim to restore an exact live save.")
                    .foregroundStyle(PlayerTheme.secondaryText)
            } icon: {
                Image(systemName: "info.circle")
                    .foregroundStyle(PlayerTheme.accent)
            }
        }
        .listRowBackground(PlayerTheme.opaquePanel)
    }
}
