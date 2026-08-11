import SwiftUI

struct HandoffMappingView: View {
    @State private var draft: HandoffDraft
    @State private var threadRows: [EditableThreadRow]
    @State private var inventoryRows: [EditableInventoryRow]

    let onApprove: (ApprovedHandoffCheckpoint) -> Void

    init(
        draft: HandoffDraft,
        onApprove: @escaping (ApprovedHandoffCheckpoint) -> Void
    ) {
        _draft = State(initialValue: draft)
        _threadRows = State(
            initialValue: draft.unresolvedThreads.map {
                EditableThreadRow(text: $0)
            }
        )
        _inventoryRows = State(
            initialValue: draft.inventoryDeltas
                .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
                .map { EditableInventoryRow(name: $0.key, delta: $0.value) }
        )
        self.onApprove = onApprove
    }

    var body: some View {
        Form {
            if draft.reviewFlags.isEmpty == false
                || draft.detectedSpeakers.isEmpty == false {
                HandoffReviewSection(
                    reviewFlags: draft.reviewFlags,
                    detectedSpeakers: draft.detectedSpeakers
                )
            }

            HandoffStorySection(
                summary: $draft.summary,
                lastKnownPlayerChoice: $draft.lastKnownPlayerChoice
            )
            HandoffPositionSection(
                currentScene: $draft.currentScene,
                playerCharacter: $draft.playerCharacter
            )
            HandoffThreadsSection(rows: $threadRows)
            HandoffInventorySection(rows: $inventoryRows)

            Section {
                Button(action: approve) {
                    Label("Approve checkpoint", systemImage: "checkmark")
                        .font(.headline)
                        .foregroundStyle(Color.black.opacity(0.84))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(PlayerTheme.accent, in: Capsule())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .accessibilityHint(
                    "Uses these reviewed fields as the campaign starting point"
                )
                .accessibilityIdentifier("approveHandoffCheckpoint")
            } footer: {
                Text(
                    "This does not restore an exact prior save. Only the fields you reviewed will become the starting checkpoint."
                )
                .foregroundStyle(PlayerTheme.secondaryText)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(PlayerTheme.canvas)
        .tint(PlayerTheme.accent)
        .navigationTitle("Map handoff")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
    }

    private func approve() {
        var reviewedDraft = draft
        reviewedDraft.unresolvedThreads = threadRows
            .map(\.text)
            .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        reviewedDraft.inventoryDeltas = inventoryRows.reduce(into: [:]) {
            inventory, row in
            guard row.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty == false
            else {
                return
            }
            inventory[row.name] = row.delta
        }

        do {
            let checkpoint = try reviewedDraft.approvedCheckpoint(
                confirmingUserApproval: true
            )
            onApprove(checkpoint)
        } catch {
            assertionFailure("Explicit handoff approval did not complete")
        }
    }
}

private struct HandoffReviewSection: View {
    let reviewFlags: [HandoffReviewFlag]
    let detectedSpeakers: [String]

    var body: some View {
        Section("Review notes") {
            ForEach(reviewFlags, id: \.self) { flag in
                Label {
                    reviewMessage(for: flag)
                        .foregroundStyle(PlayerTheme.secondaryText)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(PlayerTheme.accent)
                }
            }

            if detectedSpeakers.isEmpty == false {
                LabeledContent("Detected speakers") {
                    Text(detectedSpeakers.formatted(.list(type: .and)))
                        .foregroundStyle(PlayerTheme.primaryText)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .listRowBackground(PlayerTheme.opaquePanel)
    }

    @ViewBuilder
    private func reviewMessage(for flag: HandoffReviewFlag) -> some View {
        switch flag {
        case .emptyInput:
            Text("The handoff was empty. Add the details you want to keep.")
        case .unstructuredText:
            Text("Plain text was placed in Summary for you to review.")
        case .speakerMappingRequired:
            Text("Speaker labels were detected but no player was inferred.")
        case .ambiguousSpeakerNames:
            Text("Choose the player character; several speakers were found.")
        }
    }
}

private struct HandoffStorySection: View {
    @Binding var summary: String
    @Binding var lastKnownPlayerChoice: String

    var body: some View {
        Section("Story") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Summary")
                    .font(.caption)
                    .foregroundStyle(PlayerTheme.secondaryText)
                TextEditor(text: $summary)
                    .frame(minHeight: 96)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(PlayerTheme.primaryText)
                    .accessibilityIdentifier("handoffSummaryEditor")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Last known player choice")
                    .font(.caption)
                    .foregroundStyle(PlayerTheme.secondaryText)
                TextEditor(text: $lastKnownPlayerChoice)
                    .frame(minHeight: 72)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(PlayerTheme.primaryText)
                    .accessibilityIdentifier("handoffLastChoiceEditor")
            }
        }
        .listRowBackground(PlayerTheme.opaquePanel)
    }
}

private struct HandoffPositionSection: View {
    @Binding var currentScene: String
    @Binding var playerCharacter: String

    var body: some View {
        Section("Position") {
            TextField("Current scene", text: $currentScene, axis: .vertical)
                .foregroundStyle(PlayerTheme.primaryText)
            TextField(
                "Player character",
                text: $playerCharacter,
                axis: .vertical
            )
            .foregroundStyle(PlayerTheme.primaryText)
        }
        .listRowBackground(PlayerTheme.opaquePanel)
    }
}

private struct HandoffThreadsSection: View {
    @Binding var rows: [EditableThreadRow]

    var body: some View {
        Section("Unresolved threads") {
            ForEach($rows) { $row in
                HStack(spacing: 10) {
                    TextField("Thread", text: $row.text, axis: .vertical)
                        .foregroundStyle(PlayerTheme.primaryText)
                    Button {
                        rows.removeAll { $0.id == row.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(PlayerTheme.secondaryText)
                    .accessibilityLabel("Remove thread")
                }
            }

            Button {
                rows.append(EditableThreadRow(text: ""))
            } label: {
                Label("Add thread", systemImage: "plus")
            }
        }
        .listRowBackground(PlayerTheme.opaquePanel)
    }
}

private struct HandoffInventorySection: View {
    @Binding var rows: [EditableInventoryRow]

    var body: some View {
        Section("Inventory changes") {
            ForEach($rows) { $row in
                HStack(spacing: 10) {
                    TextField("Item", text: $row.name)
                        .foregroundStyle(PlayerTheme.primaryText)
                    TextField("Change", value: $row.delta, format: .number)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 72)
                        .foregroundStyle(PlayerTheme.primaryText)
                    Button {
                        rows.removeAll { $0.id == row.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(PlayerTheme.secondaryText)
                    .accessibilityLabel("Remove inventory change")
                }
            }

            Button {
                rows.append(EditableInventoryRow(name: "", delta: 0))
            } label: {
                Label("Add inventory change", systemImage: "plus")
            }
        }
        .listRowBackground(PlayerTheme.opaquePanel)
    }
}

private struct EditableThreadRow: Identifiable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

private struct EditableInventoryRow: Identifiable {
    let id: UUID
    var name: String
    var delta: Int

    init(id: UUID = UUID(), name: String, delta: Int) {
        self.id = id
        self.name = name
        self.delta = delta
    }
}

#Preview {
    NavigationStack {
        HandoffMappingView(
            draft: HandoffParser().parse(
                """
                ## Summary
                The party reached Greyhaven.
                ## Current Scene
                Outside the western gate.
                ## Player Character
                Mara Voss
                """
            ),
            onApprove: { _ in }
        )
    }
    .preferredColorScheme(.dark)
}
