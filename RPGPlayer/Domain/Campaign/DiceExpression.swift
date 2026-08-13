import Foundation

public enum DiceExpressionError: Error, Codable, Equatable, Sendable {
    case empty
    case malformed
    case invalidDiceCount
    case invalidSides
    case invalidModifier
    case inputTooLong
    case overflow
}

/// A deliberately small, bounded dice expression accepted by the player.
public struct DiceExpression: Codable, Equatable, Hashable, Sendable,
    CustomStringConvertible {
    public static let maximumDiceCount = 100
    public static let maximumSides = 1_000
    public static let maximumModifierMagnitude = 100_000
    public static let maximumInputBytes = 64
    public static let minimumTotal = -100_000
    public static let maximumTotal = 200_000

    public let diceCount: Int
    public let sides: Int
    public let modifier: Int

    public init(_ notation: String) throws {
        let bytes = Array(notation.utf8)
        guard bytes.isEmpty == false else {
            throw DiceExpressionError.empty
        }
        guard bytes.count <= Self.maximumInputBytes else {
            throw DiceExpressionError.inputTooLong
        }

        var index = 0
        let diceCount = try Self.parseUnsigned(bytes, index: &index)
        guard index < bytes.count, bytes[index] == 100 else {
            throw DiceExpressionError.malformed
        }
        index += 1

        let sides = try Self.parseUnsigned(bytes, index: &index)
        var modifier = 0
        if index < bytes.count {
            let sign = bytes[index]
            guard sign == 43 || sign == 45 else {
                throw DiceExpressionError.malformed
            }
            index += 1
            let magnitude = try Self.parseUnsigned(bytes, index: &index)
            guard magnitude <= Self.maximumModifierMagnitude else {
                throw DiceExpressionError.invalidModifier
            }
            modifier = sign == 45 ? -magnitude : magnitude
        }
        guard index == bytes.count else {
            throw DiceExpressionError.malformed
        }
        guard (1...Self.maximumDiceCount).contains(diceCount) else {
            throw DiceExpressionError.invalidDiceCount
        }
        guard (1...Self.maximumSides).contains(sides) else {
            throw DiceExpressionError.invalidSides
        }
        let minimumPossibleTotal = diceCount + modifier
        let maximumPossibleTotal = diceCount * sides + modifier
        guard (Self.minimumTotal...Self.maximumTotal).contains(
                  minimumPossibleTotal
              ),
              (Self.minimumTotal...Self.maximumTotal).contains(
                  maximumPossibleTotal
              )
        else {
            throw DiceExpressionError.invalidModifier
        }

        self.diceCount = diceCount
        self.sides = sides
        self.modifier = modifier
    }

    public init(
        diceCount: Int,
        sides: Int,
        modifier: Int = 0
    ) throws {
        try self.init(
            Self.notation(
                diceCount: diceCount,
                sides: sides,
                modifier: modifier
            )
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(canonicalNotation)
    }

    public var canonicalNotation: String {
        Self.notation(
            diceCount: diceCount,
            sides: sides,
            modifier: modifier
        )
    }

    /// Stable copy for compact UI surfaces and accessibility announcements.
    public var displayString: String {
        if modifier == 0 {
            return "\(canonicalNotation): \(diceCount) die\(diceCount == 1 ? "" : "s"), \(sides)-sided"
        }
        let sign = modifier > 0 ? "+" : "−"
        return "\(diceCount)d\(sides) \(sign) \(abs(modifier))"
    }

    public var description: String { canonicalNotation }

    private static func notation(
        diceCount: Int,
        sides: Int,
        modifier: Int
    ) -> String {
        let modifierText: String
        if modifier > 0 {
            modifierText = "+\(modifier)"
        } else if modifier < 0 {
            modifierText = "\(modifier)"
        } else {
            modifierText = ""
        }
        return "\(diceCount)d\(sides)\(modifierText)"
    }

    private static func parseUnsigned(
        _ bytes: [UInt8],
        index: inout Int
    ) throws -> Int {
        let start = index
        var value = 0
        while index < bytes.count {
            let byte = bytes[index]
            guard (48...57).contains(byte) else { break }
            let digit = Int(byte - 48)
            guard value <= (Int.max - digit) / 10 else {
                throw DiceExpressionError.overflow
            }
            value = value * 10 + digit
            index += 1
        }
        guard index > start else {
            throw DiceExpressionError.malformed
        }
        guard index - start == 1 || bytes[start] != 48 else {
            throw DiceExpressionError.malformed
        }
        return value
    }
}
