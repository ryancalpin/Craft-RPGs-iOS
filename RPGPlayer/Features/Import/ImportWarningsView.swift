import SwiftUI

struct ImportWarningsView: View {
    private let missingReferences: [ImportIssuePresentation]
    private let otherWarnings: [ImportIssuePresentation]
    private let fatalErrors: [ImportIssuePresentation]

    init(warnings: [ImportIssue], fatalErrors: [ImportIssue]) {
        missingReferences = warnings
            .filter { $0.code.contains("reference") }
            .map(ImportIssuePresentation.init)
        otherWarnings = warnings
            .filter { $0.code.contains("reference") == false }
            .map(ImportIssuePresentation.init)
        self.fatalErrors = fatalErrors.map(ImportIssuePresentation.init)
    }

    var body: some View {
        if missingReferences.isEmpty == false {
            Section("Missing references") {
                ForEach(missingReferences) { item in
                    ImportIssueRow(issue: item.issue, isFatal: false)
                }
            }
        }

        if otherWarnings.isEmpty == false {
            Section("Warnings") {
                ForEach(otherWarnings) { item in
                    ImportIssueRow(issue: item.issue, isFatal: false)
                }
            }
        }

        if fatalErrors.isEmpty == false {
            Section("Import blocked") {
                ForEach(fatalErrors) { item in
                    ImportIssueRow(issue: item.issue, isFatal: true)
                }
            }
        }
    }
}

private struct ImportIssuePresentation: Identifiable {
    let issue: ImportIssue

    var id: String {
        [issue.code, issue.relativePath ?? "", issue.message]
            .joined(separator: "|")
    }

    init(_ issue: ImportIssue) {
        self.issue = issue
    }
}

private struct ImportIssueRow: View {
    let issue: ImportIssue
    let isFatal: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isFatal ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isFatal ? Color.red : PlayerTheme.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(issue.code)
                    .font(.caption.monospaced())
                    .foregroundStyle(PlayerTheme.primaryText)
                if let relativePath = issue.relativePath {
                    Text(relativePath)
                        .font(.caption)
                        .foregroundStyle(PlayerTheme.accent)
                }
                Text(issue.message)
                    .foregroundStyle(PlayerTheme.secondaryText)
            }
        }
        .listRowBackground(PlayerTheme.opaquePanel)
    }
}
