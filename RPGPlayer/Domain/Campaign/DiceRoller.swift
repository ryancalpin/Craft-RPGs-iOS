import Foundation

public struct DiceRoll: Codable, Equatable, Sendable {
    public let expression: DiceExpression
    public let results: [Int]

    public init(expression: DiceExpression, results: [Int]) {
        self.expression = expression
        self.results = results
    }

    public var modifier: Int { expression.modifier }

    public var total: Int {
        results.reduce(expression.modifier, +)
    }

    public var displayString: String {
        "\(expression.canonicalNotation) = \(total)"
    }
}

/// Rolls bounded expressions without owning global or shared mutable RNG state.
public struct DiceRoller: Sendable {
    public init() {}

    public func roll(_ expression: DiceExpression) -> DiceRoll {
        var generator = SystemRandomNumberGenerator()
        return Self.roll(expression, using: &generator)
    }

    public static func roll<G: RandomNumberGenerator>(
        _ expression: DiceExpression,
        using generator: inout G
    ) -> DiceRoll {
        var results: [Int] = []
        results.reserveCapacity(expression.diceCount)
        for _ in 0..<expression.diceCount {
            results.append(
                Int.random(
                    in: 1...expression.sides,
                    using: &generator
                )
            )
        }
        return DiceRoll(expression: expression, results: results)
    }

    public func roll<G: RandomNumberGenerator>(
        _ expression: DiceExpression,
        using generator: inout G
    ) -> DiceRoll {
        Self.roll(expression, using: &generator)
    }
}
