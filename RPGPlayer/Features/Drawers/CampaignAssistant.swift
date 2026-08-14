import Observation
import SwiftUI

struct LiveCampaignAssistantContext: Sendable {
    let campaignTitle: String
    let project: NormalizedProject
    let projection: CampaignProjection
    let importedAssets: [ImportedAsset]
}

struct CampaignAssistantResponse: Sendable {
    let text: String
    let references: [String]
}

/// A local, source-backed assistant for campaign questions. It deliberately
/// reads the normalized project and projection instead of presenting fixture
/// copy or inventing a provider-backed write operation.
actor CampaignAssistantService {
    func answer(
        prompt: String,
        context: LiveCampaignAssistantContext
    ) -> CampaignAssistantResponse {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = Set(
            trimmed
                .lowercased()
                .split { $0.isLetter == false && $0.isNumber == false }
                .map(String.init)
                .filter { $0.count > 2 }
        )

        let matchingRecords = context.project.records.filter { record in
            let searchable = ([record.id] + record.fields.map {
                Self.stringValue($0.value)
            }).joined(separator: " ").lowercased()
            return tokens.isEmpty || tokens.contains(where: searchable.contains)
        }
        let sceneTitle = context.projection.currentScene?.title
            ?? context.project.currentSceneRecordID.flatMap { sceneID in
                context.project.records.first(where: { $0.id == sceneID })?.id
            }
            ?? "No scene selected"
        let references = matchingRecords.prefix(4).map(\.id)
        let assetCount = context.project.assets.count
            + context.importedAssets.count

        let text: String
        if trimmed.isEmpty {
            text = "Ask about the current scene, a record, a character, or the campaign's visual assets."
        } else if matchingRecords.isEmpty {
            text = "I couldn't find a matching record in the imported campaign. I can answer from the campaign's normalized project, but I won't invent facts outside it."
        } else {
            let names = matchingRecords.prefix(3).map(\.id).joined(separator: ", ")
            text = "The current scene is \(sceneTitle). Matching campaign records: \(names). This campaign currently exposes \(assetCount) visual assets. I found these results from the local campaign state; no changes were applied."
        }
        return CampaignAssistantResponse(text: text, references: references)
    }

    private static func stringValue(_ value: JSONValue) -> String {
        switch value {
        case .string(let value): value
        case .integer(let value): String(value)
        case .number(let value): String(value)
        case .bool(let value): String(value)
        case .array(let values): values.map(stringValue).joined(separator: " ")
        case .object(let values): values.values.map(stringValue).joined(separator: " ")
        case .null: ""
        }
    }
}

@MainActor
@Observable
final class LiveCampaignAssistantModel {
    struct Message: Identifiable, Equatable {
        enum Role { case user, assistant }

        let id: Int
        let role: Role
        let text: String
        let references: [String]
    }

    private(set) var messages: [Message]
    var draft = ""
    private(set) var isResponding = false

    private let context: LiveCampaignAssistantContext
    private let service: CampaignAssistantService

    init(
        context: LiveCampaignAssistantContext,
        service: CampaignAssistantService = CampaignAssistantService()
    ) {
        self.context = context
        self.service = service
        messages = [
            Message(
                id: 0,
                role: .assistant,
                text: "I'm connected to this campaign's local project and event state. Ask me about the current scene or its records.",
                references: []
            )
        ]
    }

    func send() async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, isResponding == false else { return }
        let nextID = (messages.map(\.id).max() ?? 0) + 1
        messages.append(
            Message(id: nextID, role: .user, text: trimmed, references: [])
        )
        draft = ""
        isResponding = true
        defer { isResponding = false }
        let response = await service.answer(prompt: trimmed, context: context)
        messages.append(
            Message(
                id: nextID + 1,
                role: .assistant,
                text: response.text,
                references: response.references
            )
        )
    }
}

@MainActor
struct LiveCampaignAssistantContent: View {
    @State private var model: LiveCampaignAssistantModel

    init(context: LiveCampaignAssistantContext) {
        _model = State(
            initialValue: LiveCampaignAssistantModel(context: context)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(PlayerTheme.accent)
                Text("Local campaign context")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("Read-only")
                    .font(.caption2)
                    .foregroundStyle(PlayerTheme.secondaryText)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)

            Divider().overlay(PlayerTheme.panelStroke)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.messages) { message in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(message.role == .user ? "You" : "Campaign assistant")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(
                                    message.role == .user
                                        ? PlayerTheme.accentSoft
                                        : PlayerTheme.secondaryText
                                )
                            Text(message.text)
                                .font(.subheadline)
                                .foregroundStyle(PlayerTheme.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            if message.references.isEmpty == false {
                                Text("Sources: " + message.references.joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundStyle(PlayerTheme.tertiaryText)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            message.role == .user
                                ? PlayerTheme.accent.opacity(0.10)
                                : Color.white.opacity(0.055),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .accessibilityIdentifier("liveAssistantMessage-\(message.id)")
                    }
                }
                .padding(12)
            }

            Divider().overlay(PlayerTheme.panelStroke)

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask about this campaign…", text: $model.draft, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("liveAssistantComposer")

                Button {
                    Task { await model.send() }
                } label: {
                    Image(systemName: model.isResponding ? "hourglass" : "arrow.up")
                        .frame(width: 44, height: 44)
                        .background(PlayerTheme.accent, in: Circle())
                        .foregroundStyle(.black.opacity(0.75))
                }
                .disabled(
                    model.isResponding
                        || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .accessibilityLabel("Ask campaign assistant")
                .accessibilityIdentifier("sendLiveAssistantMessage")
            }
            .padding(10)
        }
        .accessibilityIdentifier("liveCampaignAssistant")
    }
}
