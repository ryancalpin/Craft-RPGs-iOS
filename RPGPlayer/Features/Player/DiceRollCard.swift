import SwiftUI

struct DiceRollSheetItem: Identifiable, Equatable {
    let request: RollRequestedPayload
    let result: RollResolvedPayload?

    var id: UUID { request.rollID }
}

struct DiceRollCard: View {
    let request: RollRequestedPayload
    let resolved: RollResolvedPayload?
    let resolve: @MainActor () async throws -> RollResolvedPayload
    let onDismiss: () -> Void

    @State private var selectedItem: DiceRollSheetItem?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "dice.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(PlayerTheme.accent)
                .frame(width: 44, height: 44)
                .background {
                    Circle().fill(PlayerTheme.accent.opacity(0.14))
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(resolved == nil ? "A roll is waiting" : "Roll resolved")
                    .font(.headline)
                    .foregroundStyle(PlayerTheme.primaryText)
                Text(request.prompt)
                    .font(.subheadline)
                    .foregroundStyle(PlayerTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(request.expression)
                    .font(.caption.monospaced())
                    .foregroundStyle(PlayerTheme.accent)
            }

            Spacer(minLength: 8)

            Button(resolved == nil ? "Roll" : "View") {
                selectedItem = DiceRollSheetItem(request: request, result: resolved)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.black.opacity(0.82))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Capsule().fill(PlayerTheme.accent))
            .buttonStyle(.plain)
            .accessibilityLabel(resolved == nil ? "Roll \(request.expression)" : "View roll result")
            .accessibilityHint(resolved == nil ? "Opens the roll details" : "Opens the resolved roll")
            .accessibilityIdentifier("diceRollButton-\(request.rollID.uuidString)")
        }
        .padding(14)
        .background {
            PlayerSemanticSurface(
                shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
                style: .material(panelOverlayOpacity: 0.56)
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("diceRollCard-\(request.rollID.uuidString)")
        .sheet(item: $selectedItem, onDismiss: onDismiss) { item in
            DiceRollSheet(
                request: item.request,
                resolve: resolve,
                initialState: item.result.map { DiceRollSheet.SheetState.result($0) }
            )
                .presentationDetents([.height(360), .medium])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
                .presentationBackground(PlayerTheme.canvas)
        }
    }
}

#Preview("Pending roll") {
    DiceRollCard(
        request: DiceRollPreviewFixtures.request,
        resolved: nil,
        resolve: DiceRollPreviewFixtures.resolve,
        onDismiss: {}
    )
    .padding()
    .background(PlayerTheme.canvas)
    .preferredColorScheme(.dark)
}
