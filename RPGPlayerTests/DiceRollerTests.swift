import Foundation
import Testing
@testable import RPGPlayer

struct DiceRollerTests {
    @Test
    func deterministicGeneratorProducesEachDieModifierAndTotal() throws {
        let expression = try DiceExpression("3d6-2")
        var generator = SequenceGenerator(values: [0, 1, 2])

        let roll = DiceRoller.roll(expression, using: &generator)

        #expect(roll.results == [1, 2, 3])
        #expect(roll.modifier == -2)
        #expect(roll.total == 4)
        #expect(roll.displayString == "3d6-2 = 4")
    }

    @Test
    func canonicalizesAndCodifiesBoundedExpressions() throws {
        let expression = try DiceExpression("1d20+5")

        #expect(expression.diceCount == 1)
        #expect(expression.sides == 20)
        #expect(expression.modifier == 5)
        #expect(expression.canonicalNotation == "1d20+5")
        #expect(expression.description == "1d20+5")
        #expect(
            try JSONDecoder().decode(
                DiceExpression.self,
                from: JSONEncoder().encode(expression)
            ) == expression
        )
    }

    @Test
    func acceptsMaximumBoundsAndRejectsOutOfBoundsValues() throws {
        let maximum = try DiceExpression("100d1000+100000")
        #expect(maximum.diceCount == 100)
        #expect(maximum.sides == 1_000)
        #expect(
            maximum.diceCount * maximum.sides + maximum.modifier
                == DiceExpression.maximumTotal
        )

        for invalid in [
            "0d20", "101d20", "1d0", "1d1001", "1d20+100001",
            "1d20-100001", "1d20+999999999999999999999999", "1d20+"
        ] {
            #expect(throws: DiceExpressionError.self) {
                _ = try DiceExpression(invalid)
            }
        }
    }

    @Test
    func rejectsWhitespaceUnsafeAndUnboundedForms() throws {
        for invalid in [
            " 1d20", "1d20 ", "1D20", "1d20*2", "1d20+1d4",
            "01d20", "1d020", "-1d20", "1d-20", "1d20\n", "1d20/2",
            String(repeating: "9", count: DiceExpression.maximumInputBytes + 1)
        ] {
            #expect(throws: DiceExpressionError.self) {
                _ = try DiceExpression(invalid)
            }
        }
    }

    @Test
    func productionRollerKeepsEveryResultWithinTheExpressionBounds() throws {
        let expression = try DiceExpression("8d4+7")

        let roll = DiceRoller().roll(expression)

        #expect(roll.results.count == 8)
        #expect(roll.results.allSatisfy { (1...4).contains($0) })
        #expect(roll.total == roll.results.reduce(7, +))
        #expect((15...39).contains(roll.total))
    }
}

private struct SequenceGenerator: RandomNumberGenerator {
    var values: [UInt64]

    mutating func next() -> UInt64 {
        guard values.isEmpty == false else { return 0 }
        return values.removeFirst()
    }
}
