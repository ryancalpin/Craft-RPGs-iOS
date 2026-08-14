import SwiftUI

@MainActor
struct NewCampaignSheet: View {
    private enum Field: Hashable {
        case title
        case premise
        case playerCharacter
    }

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var title = ""
    @State private var premise = ""
    @State private var playerCharacter = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    let creator: CampaignCreator
    let onCreated: @MainActor (UUID) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Start a new story", systemImage: "sparkles")
                            .font(.headline)
                            .foregroundStyle(PlayerTheme.primaryText)
                        Text(
                            "Give your campaign a name and a starting idea. You can shape the world as you play."
                        )
                        .foregroundStyle(PlayerTheme.secondaryText)
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(PlayerTheme.opaquePanel)

                Section("Campaign") {
                    TextField("Campaign name", text: $title)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .focused($focusedField, equals: .title)
                        .accessibilityIdentifier("newCampaignTitleField")
                }
                .listRowBackground(PlayerTheme.opaquePanel)

                Section {
                    TextEditor(text: $premise)
                        .frame(minHeight: 110)
                        .focused($focusedField, equals: .premise)
                        .accessibilityIdentifier("newCampaignPremiseField")
                    Text("Optional. Describe the place, conflict, or feeling where the story begins.")
                        .font(.caption)
                        .foregroundStyle(PlayerTheme.tertiaryText)
                } header: {
                    Text("Opening premise")
                }
                .listRowBackground(PlayerTheme.opaquePanel)

                Section {
                    TextField("Character name", text: $playerCharacter)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($focusedField, equals: .playerCharacter)
                        .accessibilityIdentifier("newCampaignCharacterField")
                    Text("Optional. You can introduce your character during play instead.")
                        .font(.caption)
                        .foregroundStyle(PlayerTheme.tertiaryText)
                } header: {
                    Text("Your character")
                }
                .listRowBackground(PlayerTheme.opaquePanel)

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("newCampaignError")
                    }
                    .listRowBackground(PlayerTheme.opaquePanel)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(PlayerTheme.canvas)
            .foregroundStyle(PlayerTheme.primaryText)
            .tint(PlayerTheme.accent)
            .navigationTitle("New campaign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isCreating)
                        .accessibilityIdentifier("cancelNewCampaignButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create)
                        .disabled(canCreate == false)
                        .accessibilityIdentifier("createCampaignButton")
                }
            }
            .overlay {
                if isCreating {
                    ProgressView("Creating campaign…")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("newCampaignProgressView")
                }
            }
            .accessibilityIdentifier("newCampaignView")
        }
        .interactiveDismissDisabled(isCreating)
        .task {
            focusedField = .title
        }
    }

    private var canCreate: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && isCreating == false
    }

    private func create() {
        guard canCreate else { return }
        isCreating = true
        errorMessage = nil
        Task { @MainActor in
            do {
                let campaignID = try await creator.create(
                    NewCampaignDraft(
                        title: title,
                        premise: premise,
                        playerCharacter: playerCharacter
                    )
                )
                dismiss()
                onCreated(campaignID)
            } catch CampaignCreationError.titleRequired {
                isCreating = false
                errorMessage = "Enter a campaign name to continue."
            } catch {
                isCreating = false
                errorMessage = "The campaign could not be created."
            }
        }
    }
}
