import SwiftUI

struct ImportProgressView: View {
    @Environment(\.dismiss) private var dismiss

    let currentPhase: ImportProgressPhase
    let copiedByteCount: Int64
    let cancel: () -> Void

    var body: some View {
        List {
            Section {
                ForEach(ImportProgressPhase.allCases) { phase in
                    ImportProgressRow(
                        phase: phase,
                        currentPhase: currentPhase,
                        copiedByteCount: copiedByteCount
                    )
                }
            } header: {
                Text("Preparing your campaign")
            } footer: {
                Text("Your selected source is copied into app-owned staging before it is inspected or parsed.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PlayerTheme.canvas)
        .navigationTitle("Import campaign")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    cancel()
                    dismiss()
                }
                .accessibilityIdentifier("cancelImportButton")
            }
        }
        .accessibilityIdentifier("importProgressView")
    }
}

private struct ImportProgressRow: View {
    let phase: ImportProgressPhase
    let currentPhase: ImportProgressPhase
    let copiedByteCount: Int64

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(phase.title)
                    .foregroundStyle(PlayerTheme.primaryText)
                if phase == .copy, copiedByteCount > 0 {
                    Text(copiedByteCount, format: .byteCount(style: .file))
                        .font(.caption)
                        .foregroundStyle(PlayerTheme.secondaryText)
                }
            }

            Spacer(minLength: 8)

            Text(statusTitle)
                .font(.caption)
                .foregroundStyle(PlayerTheme.secondaryText)
        }
        .listRowBackground(PlayerTheme.opaquePanel)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if phase.rawValue < currentPhase.rawValue {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(PlayerTheme.accent)
        } else if phase == currentPhase {
            ProgressView()
                .tint(PlayerTheme.accent)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(PlayerTheme.secondaryText)
        }
    }

    private var statusTitle: LocalizedStringResource {
        if phase.rawValue < currentPhase.rawValue {
            "Complete"
        } else if phase == currentPhase {
            "Current"
        } else {
            "Pending"
        }
    }
}

#Preview {
    NavigationStack {
        ImportProgressView(
            currentPhase: .parse,
            copiedByteCount: 12_384,
            cancel: {}
        )
    }
    .preferredColorScheme(.dark)
}
