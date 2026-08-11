import CryptoKit
import Foundation

public enum HandoffParsingError: Error, Equatable, Sendable {
    case invalidUTF8
}

public struct HandoffParser: Sendable {
    public init() {}

    public func parse(_ text: String) -> HandoffDraft {
        makeDraft(text: text, sourceData: Data(text.utf8))
    }

    public func parse(data: Data) throws -> HandoffDraft {
        guard let text = String(data: data, encoding: .utf8) else {
            throw HandoffParsingError.invalidUTF8
        }
        return makeDraft(text: text, sourceData: data)
    }

    private func makeDraft(text: String, sourceData: Data) -> HandoffDraft {
        let sourceHash = Self.sha256(sourceData)
        let trimmedInput = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedInput.isEmpty == false else {
            return HandoffDraft(
                originalHandoffSHA256: sourceHash,
                reviewFlags: [.emptyInput]
            )
        }

        let normalizedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalizedText.components(separatedBy: "\n")

        var sectionLines: [Section: [String]] = [:]
        var currentSection: Section?
        var foundRecognizedHeading = false
        var speakerNamesByCanonicalName: [String: String] = [:]

        for line in lines {
            let heading = Self.heading(in: line)
            if heading.isHeading {
                currentSection = heading.section
                foundRecognizedHeading = foundRecognizedHeading
                    || heading.section != nil
                continue
            }

            if let currentSection {
                sectionLines[currentSection, default: []].append(line)
            } else if let speaker = Self.speakerName(in: line) {
                speakerNamesByCanonicalName[speaker.lowercased()] = speaker
            }
        }

        let speakers = speakerNamesByCanonicalName.values.sorted {
            let left = $0.lowercased()
            let right = $1.lowercased()
            return left == right ? $0 < $1 : left < right
        }

        let summary: String
        if foundRecognizedHeading {
            summary = Self.paragraph(sectionLines[.summary])
        } else if speakers.isEmpty {
            summary = trimmedInput
        } else {
            summary = ""
        }

        var reviewFlags: [HandoffReviewFlag] = []
        if foundRecognizedHeading == false, speakers.isEmpty {
            reviewFlags.append(.unstructuredText)
        }
        if speakers.isEmpty == false {
            reviewFlags.append(.speakerMappingRequired)
            if speakers.count > 1 {
                reviewFlags.append(.ambiguousSpeakerNames)
            }
        }

        return HandoffDraft(
            originalHandoffSHA256: sourceHash,
            summary: summary,
            currentScene: Self.paragraph(sectionLines[.currentScene]),
            playerCharacter: Self.paragraph(sectionLines[.playerCharacter]),
            unresolvedThreads: Self.list(sectionLines[.unresolvedThreads]),
            inventoryDeltas: Self.inventory(
                sectionLines[.inventoryDeltas]
            ),
            lastKnownPlayerChoice: Self.paragraph(
                sectionLines[.lastKnownPlayerChoice]
            ),
            detectedSpeakers: speakers,
            reviewFlags: reviewFlags
        )
    }

    private static func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func paragraph(_ lines: [String]?) -> String {
        guard let lines else { return "" }
        return lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func list(_ lines: [String]?) -> [String] {
        guard let lines else { return [] }
        return lines.compactMap { line in
            var value = line.trimmingCharacters(in: .whitespaces)
            if let first = value.first,
               ["-", "*", "+"].contains(first) {
                value.removeFirst()
                value = value.trimmingCharacters(in: .whitespaces)
            }
            return value.isEmpty ? nil : value
        }
    }

    private static func inventory(_ lines: [String]?) -> [String: Int] {
        guard let lines else { return [:] }
        var result: [String: Int] = [:]

        for entry in list(lines) {
            guard let separator = entry.lastIndex(of: ":") else { continue }
            let name = entry[..<separator]
                .trimmingCharacters(in: .whitespaces)
            let deltaText = entry[entry.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
            guard name.isEmpty == false, let delta = Int(deltaText) else {
                continue
            }
            result[name] = delta
        }

        return result
    }

    private static func heading(
        in line: String
    ) -> (isHeading: Bool, section: Section?) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let hashCount = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(hashCount) else {
            return (false, nil)
        }

        let titleStart = trimmed.index(trimmed.startIndex, offsetBy: hashCount)
        guard titleStart < trimmed.endIndex,
              trimmed[titleStart].isWhitespace
        else {
            return (false, nil)
        }

        let title = trimmed[titleStart...]
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        return (true, Section(title: title))
    }

    private static func speakerName(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let colon = trimmed.firstIndex(of: ":"),
              colon < trimmed.index(before: trimmed.endIndex)
        else {
            return nil
        }

        let candidate = trimmed[..<colon]
            .trimmingCharacters(in: .whitespaces)
        let dialogue = trimmed[trimmed.index(after: colon)...]
            .trimmingCharacters(in: .whitespaces)
        guard candidate.isEmpty == false,
              candidate.count <= 48,
              candidate.first?.isLetter == true,
              dialogue.isEmpty == false,
              candidate.allSatisfy({ character in
                  character.isLetter
                      || character.isNumber
                      || character.isWhitespace
                      || "-'’.".contains(character)
              })
        else {
            return nil
        }
        return candidate
    }
}

private enum Section: Hashable {
    case summary
    case currentScene
    case playerCharacter
    case unresolvedThreads
    case inventoryDeltas
    case lastKnownPlayerChoice

    init?(title: String) {
        switch title {
        case "summary": self = .summary
        case "current scene": self = .currentScene
        case "player character": self = .playerCharacter
        case "unresolved threads": self = .unresolvedThreads
        case "inventory", "inventory deltas": self = .inventoryDeltas
        case "last choice", "last known player choice":
            self = .lastKnownPlayerChoice
        default: return nil
        }
    }
}
