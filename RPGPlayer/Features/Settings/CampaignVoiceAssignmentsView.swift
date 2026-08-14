import Observation
import SwiftUI

enum CampaignVoiceChoice: Hashable, Sendable {
    case none
    case voice(String)

    var voiceID: String? {
        switch self {
        case .none:
            nil
        case .voice(let voiceID):
            voiceID
        }
    }
}

struct CampaignVoiceTargetOption: Identifiable, Equatable, Sendable {
    let target: VoiceTarget
    let displayName: String

    var id: String { target.storageKey }
}

@MainActor
@Observable
final class CampaignVoiceAssignmentsModel {
    private(set) var targets: [CampaignVoiceTargetOption] = []
    private(set) var voices: [VoiceDescriptor]
    private(set) var selections: [String: String?] = [:]
    private(set) var providerSelections: [String: VoiceProviderID?] = [:]
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var errorText: String?

    private let campaignID: UUID
    private let project: NormalizedProject
    private let projectionLoader: ProjectionLoader
    private let campaignStore: any CampaignStore
    private let voiceCatalog: any VoiceCatalogProviding

    init(
        campaignID: UUID,
        project: NormalizedProject,
        projectionLoader: ProjectionLoader,
        campaignStore: any CampaignStore,
        voiceCatalog: any VoiceCatalogProviding
    ) {
        self.campaignID = campaignID
        self.project = project
        self.projectionLoader = projectionLoader
        self.campaignStore = campaignStore
        self.voiceCatalog = voiceCatalog
        voices = [Self.systemDefaultVoice]
        targets = Self.targetOptions(project: project, assignedKeys: [])
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let projection = try await projectionLoader.load(
                campaignID: campaignID
            ).projection
            targets = Self.targetOptions(
                project: project,
                assignedKeys: Array(projection.voiceAssignments.keys)
            )
            selections = Dictionary(
                uniqueKeysWithValues: targets.map { target in
                    (
                        target.id,
                        projection.voiceAssignments[target.id]?.voiceID
                    )
                }
            )
            providerSelections = Dictionary(
                uniqueKeysWithValues: targets.map { target in
                    (
                        target.id,
                        projection.voiceAssignments[target.id]?.providerID
                    )
                }
            )
            errorText = nil
        } catch {
            errorText = "Campaign voice assignments could not be loaded."
        }
    }

    func refreshVoices() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let discovered = try await voiceCatalog.voices()
            voices = [Self.systemDefaultVoice] + discovered
            errorText = nil
        } catch {
            voices = [Self.systemDefaultVoice]
            errorText =
                "ElevenLabs voices could not be loaded. Apple Speech remains available."
        }
    }

    func choice(for target: VoiceTarget) -> CampaignVoiceChoice {
        guard let voiceID = selections[target.storageKey] ?? nil else {
            return .none
        }
        return .voice(voiceID)
    }

    func assign(
        _ choice: CampaignVoiceChoice,
        to target: VoiceTarget
    ) async {
        guard isSaving == false else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            let projection = try await projectionLoader.load(
                campaignID: campaignID
            ).projection
            let providerID = choice.voiceID.flatMap { voiceID in
                voices.first(where: { $0.id == voiceID })?.providerID
            }
            let event = VoiceAssignmentEventFactory.manualEvent(
                campaignID: campaignID,
                target: target,
                providerID: providerID,
                voiceID: choice.voiceID
            )
            _ = try await campaignStore.append(
                batch: [event],
                expectedSequence: projection.appliedThroughSequence
            )
            selections[target.storageKey] = choice.voiceID
            providerSelections[target.storageKey] = providerID
            errorText = nil
        } catch {
            errorText = "The voice assignment could not be saved."
        }
    }

    private static let systemDefaultVoice = VoiceDescriptor(
        providerID: .appleSpeech,
        id: "system-default",
        displayName: "System default",
        language: nil,
        category: "Apple Speech",
        supportsStreaming: false
    )

    private static func targetOptions(
        project: NormalizedProject,
        assignedKeys: [String]
    ) -> [CampaignVoiceTargetOption] {
        var targets: [VoiceTarget] = [.narrator, .gm, .player]
        for character in project.characters {
            let target = VoiceTarget.character(character.id)
            if targets.contains(target) == false {
                targets.append(target)
            }
        }
        for key in assignedKeys where targets.contains(.character(key)) == false {
            targets.append(.character(key))
        }

        return targets.map { target in
            CampaignVoiceTargetOption(
                target: target,
                displayName: displayName(for: target, project: project)
            )
        }
    }

    private static func displayName(
        for target: VoiceTarget,
        project: NormalizedProject
    ) -> String {
        guard case .character(let characterID) = target,
              let character = project.characters.first(where: {
                  $0.id == characterID
              }),
              let record = project.records.first(where: {
                  $0.id == character.recordID
              }),
              let nameField = record.fields.first(where: {
                  $0.id.caseInsensitiveCompare("name") == .orderedSame
              }),
              case .string(let name) = nameField.value,
              name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  == false else {
            return target.displayName
        }
        return name
    }
}

@MainActor
struct CampaignVoiceAssignmentsView: View {
    @State private var model: CampaignVoiceAssignmentsModel

    init(
        campaignID: UUID,
        project: NormalizedProject,
        projectionLoader: ProjectionLoader,
        campaignStore: any CampaignStore,
        voiceCatalog: any VoiceCatalogProviding
    ) {
        _model = State(
            initialValue: CampaignVoiceAssignmentsModel(
                campaignID: campaignID,
                project: project,
                projectionLoader: projectionLoader,
                campaignStore: campaignStore,
                voiceCatalog: voiceCatalog
            )
        )
    }

    var body: some View {
        Form {
            Section {
                Button("Refresh ElevenLabs voices") {
                    Task { await model.refreshVoices() }
                }
                .disabled(model.isLoading || model.isSaving)
                .accessibilityIdentifier("refreshCampaignVoicesButton")

                if model.isLoading {
                    ProgressView("Loading campaign voices…")
                }

                if model.voices.count == 1 {
                    Text(
                        "System default is available now. Add and validate an ElevenLabs key in Settings to browse more voices."
                    )
                    .font(.footnote)
                    .foregroundStyle(PlayerTheme.secondaryText)
                }
            } header: {
                Text("Voice catalog")
            }
            .listRowBackground(PlayerTheme.opaquePanel)

            Section {
                if model.targets.isEmpty && model.isLoading {
                    ProgressView("Loading assignments…")
                } else {
                    ForEach(model.targets) { target in
                        HStack {
                            Text(target.displayName)
                                .accessibilityIdentifier(
                                    "voiceAssignmentTarget-\(target.id)"
                                )
                            Spacer(minLength: 12)
                            Picker(
                                "Voice",
                                selection: Binding(
                                    get: { model.choice(for: target.target) },
                                    set: { choice in
                                        Task {
                                            await model.assign(
                                                choice,
                                                to: target.target
                                            )
                                        }
                                    }
                                )
                            ) {
                                Text("No voice")
                                    .tag(CampaignVoiceChoice.none)
                                ForEach(model.voices) { voice in
                                    Text(voiceLabel(voice))
                                        .tag(
                                            CampaignVoiceChoice.voice(voice.id)
                                        )
                                }
                            }
                            .labelsHidden()
                            .accessibilityIdentifier(
                                "voiceAssignment-\(target.id)"
                            )
                        }
                    }
                }
            } header: {
                Text("Campaign assignments")
            } footer: {
                Text(
                    "Assignments are saved as manual campaign events and are included in recovery bundles. A later accepted suggestion cannot replace a manual assignment."
                )
            }
            .listRowBackground(PlayerTheme.opaquePanel)

            if let errorText = model.errorText {
                Section {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(PlayerTheme.secondaryText)
                        .accessibilityIdentifier("campaignVoiceAssignmentsError")
                }
                .listRowBackground(PlayerTheme.opaquePanel)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(PlayerTheme.canvas)
        .foregroundStyle(PlayerTheme.primaryText)
        .tint(PlayerTheme.accent)
        .navigationTitle("Voice assignments")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("campaignVoiceAssignmentsView")
        .task {
            await model.load()
        }
    }

    private func voiceLabel(_ voice: VoiceDescriptor) -> String {
        if voice.providerID == .appleSpeech {
            return voice.displayName
        }
        return "ElevenLabs · \(voice.displayName)"
    }
}
