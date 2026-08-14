import SwiftUI

struct DiceRollSheet: View {
    @Environment(\.dismiss) private var dismiss

    let request: RollRequestedPayload
    let resolve: @MainActor () async throws -> RollResolvedPayload

    private let expression: DiceExpression?
    @State private var sheetState: SheetState
    @State private var rollTask: Task<Void, Never>?

    enum SheetState: Equatable {
        case pending
        case rolling
        case result(RollResolvedPayload)
        case error(String)
    }

    init(
        request: RollRequestedPayload,
        resolve: @escaping @MainActor () async throws -> RollResolvedPayload,
        initialState: SheetState? = nil
    ) {
        self.request = request
        self.resolve = resolve
        let parsed = try? DiceExpression(request.expression)
        expression = parsed
        _sheetState = State(
            initialValue: initialState
                ?? (parsed == nil
                    ? .error("This roll request is invalid.")
                    : .pending)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("ROLL THE DICE")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PlayerTheme.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Close") { dismiss() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PlayerTheme.secondaryText)
                    .frame(minWidth: 44, minHeight: 44)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("closeDiceRollSheet")
            }

            Text(request.prompt)
                .font(.title3.weight(.semibold))
                .foregroundStyle(PlayerTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let expression {
                VStack(alignment: .leading, spacing: 5) {
                    Text(expression.canonicalNotation)
                        .font(.title2.monospaced().weight(.semibold))
                        .foregroundStyle(PlayerTheme.accent)
                    Text(expression.displayString)
                        .font(.subheadline)
                        .foregroundStyle(PlayerTheme.secondaryText)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Dice expression")
                .accessibilityValue(expression.canonicalNotation)
            }

            stateContent
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(PlayerTheme.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("diceRollSheet")
        .onDisappear {
            rollTask?.cancel()
            rollTask = nil
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch sheetState {
        case .pending:
            actionButton(title: "Roll Dice", identifier: "confirmDiceRoll") {
                beginRoll()
            }
        case .rolling:
            HStack(spacing: 10) {
                ProgressView()
                    .tint(PlayerTheme.accent)
                Text("Rolling…")
                    .foregroundStyle(PlayerTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .center)
            .accessibilityLabel("Rolling dice")
        case .result(let result):
            VStack(alignment: .leading, spacing: 10) {
                Text("Result")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PlayerTheme.secondaryText)
                Text(result.results.map(String.init).joined(separator: "  ·  "))
                    .font(.title3.monospaced())
                    .foregroundStyle(PlayerTheme.primaryText)
                Text("Total  \(result.total)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(PlayerTheme.accent)
                    .accessibilityIdentifier("diceRollTotal")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Roll result")
            .accessibilityValue("Total \(result.total)")
            actionButton(title: "Done", identifier: "doneDiceRoll") {
                dismiss()
            }
        case .error(let message):
            VStack(alignment: .leading, spacing: 12) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(PlayerTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if expression != nil {
                    actionButton(title: "Try Again", identifier: "retryDiceRoll") {
                        beginRoll()
                    }
                }
            }
            .accessibilityIdentifier("diceRollError")
        }
    }

    private func actionButton(
        title: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .font(.headline)
            .foregroundStyle(Color.black.opacity(0.82))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Capsule().fill(PlayerTheme.accent))
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier)
    }

    private func beginRoll() {
        guard sheetState != .rolling else {
            return
        }
        switch sheetState {
        case .pending, .error:
            break
        case .rolling, .result:
            return
        }
        guard expression != nil else { return }
        sheetState = .rolling
        rollTask?.cancel()
        rollTask = Task { @MainActor in
            do {
                let result = try await resolve()
                guard !Task.isCancelled else { return }
                sheetState = .result(result)
            } catch is CancellationError {
                // Dismissal/cancellation leaves the canonical pending roll
                // untouched and therefore available for a truthful retry.
                sheetState = .pending
            } catch let error as PlayerSessionModelError {
                switch error {
                case .invalidRollExpression:
                    sheetState = .error("This roll request is invalid.")
                case .rollNotPending, .rollAlreadyResolved:
                    sheetState = .error("This roll is no longer pending.")
                default:
                    sheetState = .error("The roll could not be saved. Try again.")
                }
            } catch {
                guard !Task.isCancelled else { return }
                sheetState = .error("The roll could not be saved. Try again.")
            }
            rollTask = nil
        }
    }
}

enum DiceRollPreviewFixtures {
    static let request = RollRequestedPayload(
        rollID: UUID(uuidString: "00000000-0000-4000-8000-000000000901")!,
        expression: "2d20+3",
        prompt: "Can you cross the rain-slick bridge unseen?"
    )

    static let resolved = RollResolvedPayload(
        rollID: request.rollID,
        results: [7, 16],
        modifier: 3,
        total: 26
    )

    static let resolve: @MainActor () async throws -> RollResolvedPayload = {
        resolved
    }
}

#Preview("Pending") {
    DiceRollSheet(
        request: DiceRollPreviewFixtures.request,
        resolve: DiceRollPreviewFixtures.resolve
    )
    .preferredColorScheme(.dark)
}

#Preview("Result") {
    DiceRollSheet(
        request: DiceRollPreviewFixtures.request,
        resolve: DiceRollPreviewFixtures.resolve,
        initialState: .result(DiceRollPreviewFixtures.resolved)
    )
    .preferredColorScheme(.dark)
}

#Preview("Error") {
    DiceRollSheet(
        request: DiceRollPreviewFixtures.request,
        resolve: DiceRollPreviewFixtures.resolve,
        initialState: .error("The roll could not be saved. Try again.")
    )
    .preferredColorScheme(.dark)
}
