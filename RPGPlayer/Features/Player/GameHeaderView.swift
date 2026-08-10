import SwiftUI

enum GameHeaderFocus: Hashable {
    case project
    case overview
}

struct GameHeaderView: View {
    @AccessibilityFocusState private var accessibilityFocus: GameHeaderFocus?

    let title: String
    @Binding var focusRequest: GameHeaderFocus?
    let openProject: () -> Void
    let openOverview: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .padding(.horizontal, 56)

            HStack {
                HeaderIconButton(
                    systemName: "line.3.horizontal",
                    accessibilityLabel: "Open project files",
                    accessibilityIdentifier: "projectDrawerButton",
                    action: openProject
                )
                .accessibilityFocused($accessibilityFocus, equals: .project)

                Spacer()

                HeaderIconButton(
                    systemName: "sidebar.right",
                    accessibilityLabel: "Open campaign overview",
                    accessibilityIdentifier: "overviewDrawerButton",
                    action: openOverview
                )
                .accessibilityFocused($accessibilityFocus, equals: .overview)
            }
        }
        .frame(minHeight: 52)
        .foregroundStyle(PlayerTheme.primaryText)
        .padding(.horizontal, 8)
        .onChange(of: focusRequest) { _, newValue in
            guard let newValue else { return }
            accessibilityFocus = newValue
            focusRequest = nil
        }
    }
}

private struct HeaderIconButton: View {
    let systemName: String
    let accessibilityLabel: LocalizedStringKey
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

#Preview {
    ZStack {
        PlayerTheme.canvas
        GameHeaderView(
            title: "The Ascendant Road",
            focusRequest: .constant(nil),
            openProject: {},
            openOverview: {}
        )
    }
    .preferredColorScheme(.dark)
}
