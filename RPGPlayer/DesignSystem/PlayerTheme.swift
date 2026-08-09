import SwiftUI

enum PlayerTheme {
    static let canvas = Color(red: 0.025, green: 0.04, blue: 0.065)
    static let panel = Color(red: 0.045, green: 0.075, blue: 0.12).opacity(0.92)
    static let panelStroke = Color.white.opacity(0.12)
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.62)
    static let accent = Color(red: 0.88, green: 0.66, blue: 0.19)
    static let pageInset: CGFloat = 16
    static let controlHeight: CGFloat = 52
    static let panelRadius: CGFloat = 22
}
