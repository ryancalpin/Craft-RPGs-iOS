import Foundation

public struct NetworkDiagnosticRedactor: Sendable {
    private static let redaction = "<redacted>"
    private static let sensitiveHeaderNames: Set<String> = [
        "authorization",
        "proxy-authorization",
        "x-api-key",
        "x-goog-api-key",
        "xi-api-key"
    ]
    private static let providerTokenPatterns = [
        #"(?<![A-Za-z0-9_-])sk-[A-Za-z0-9_-]{8,}(?![A-Za-z0-9_-])"#,
        #"(?<![A-Za-z0-9_-])AIza[A-Za-z0-9_-]{8,}(?![A-Za-z0-9_-])"#,
        #"(?<![A-Za-z0-9_-])sk_[A-Za-z0-9_-]{8,}(?![A-Za-z0-9_-])"#
    ]

    public init() {}

    public func redactedHeaders(
        _ headers: [String: String],
        knownSecrets: [String] = []
    ) -> [String: String] {
        headers.reduce(into: [:]) { redacted, header in
            if Self.sensitiveHeaderNames.contains(header.key.lowercased()) {
                redacted[header.key] = Self.redaction
            } else {
                redacted[header.key] = redact(
                    header.value,
                    knownSecrets: knownSecrets
                )
            }
        }
    }

    public func redact(
        _ diagnostic: String,
        knownSecrets: [String] = []
    ) -> String {
        var redacted = knownSecrets
            .filter { $0.isEmpty == false }
            .sorted { $0.count > $1.count }
            .reduce(diagnostic) { text, secret in
                text.replacingOccurrences(of: secret, with: Self.redaction)
            }

        for pattern in Self.providerTokenPatterns {
            guard let expression = try? NSRegularExpression(pattern: pattern)
            else {
                continue
            }
            let range = NSRange(redacted.startIndex..., in: redacted)
            redacted = expression.stringByReplacingMatches(
                in: redacted,
                range: range,
                withTemplate: Self.redaction
            )
        }
        return redacted
    }
}
