import SwiftUI

enum PlayerTheme {
    static let canvas = Color(red: 0.018, green: 0.028, blue: 0.052)
    static let canvasRaised = Color(red: 0.035, green: 0.051, blue: 0.086)
    static let canvasMidnight = Color(red: 0.022, green: 0.045, blue: 0.090)
    static let panel = Color(red: 0.050, green: 0.073, blue: 0.116).opacity(0.90)
    static let opaquePanel = Color(red: 0.036, green: 0.054, blue: 0.092)
    static let panelStroke = Color.white.opacity(0.14)
    static let primaryText = Color.white.opacity(0.96)
    static let secondaryText = Color(red: 0.73, green: 0.77, blue: 0.86)
    static let tertiaryText = Color(red: 0.49, green: 0.55, blue: 0.67)
    static let accent = Color(red: 0.93, green: 0.70, blue: 0.28)
    static let accentSoft = Color(red: 0.98, green: 0.80, blue: 0.42)
    static let accentCool = Color(red: 0.33, green: 0.67, blue: 0.96)
    static let success = Color(red: 0.39, green: 0.84, blue: 0.68)
    static let pageInset: CGFloat = 16
    static let controlHeight: CGFloat = 52
    static let panelRadius: CGFloat = 22
    static let cardRadius: CGFloat = 26
    static let smallRadius: CGFloat = 14

    static let sceneGradient = LinearGradient(
        colors: [canvasMidnight, canvasRaised, canvas],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accentGradient = LinearGradient(
        colors: [accentSoft, accent, Color(red: 0.74, green: 0.40, blue: 0.14)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct PlayerReduceMotionOverrideKey: EnvironmentKey {
    static let defaultValue = false
}

private struct PlayerReduceTransparencyOverrideKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var playerReduceMotionOverride: Bool {
        get { self[PlayerReduceMotionOverrideKey.self] }
        set { self[PlayerReduceMotionOverrideKey.self] = newValue }
    }

    var playerReduceTransparencyOverride: Bool {
        get { self[PlayerReduceTransparencyOverrideKey.self] }
        set { self[PlayerReduceTransparencyOverrideKey.self] = newValue }
    }
}

enum PlayerAccessibilityPolicy {
    static func reducesMotion(
        systemEnabled: Bool,
        forcedForTesting: Bool
    ) -> Bool {
        systemEnabled || forcedForTesting
    }

    static func reducesTransparency(
        systemEnabled: Bool,
        forcedForTesting: Bool
    ) -> Bool {
        systemEnabled || forcedForTesting
    }

    static func lineLimit(
        compactLimit: Int,
        isAccessibilitySize: Bool
    ) -> Int? {
        isAccessibilitySize ? nil : compactLimit
    }

    static func minimumScaleFactor(
        compactValue: CGFloat,
        isAccessibilitySize: Bool
    ) -> CGFloat {
        isAccessibilitySize ? 1 : compactValue
    }

    static func presentationSafeAreaTop(
        baseSafeAreaTop: CGFloat,
        measuredHeaderHeight: CGFloat,
        isAccessibilitySize: Bool
    ) -> CGFloat {
        guard isAccessibilitySize else { return baseSafeAreaTop }
        return baseSafeAreaTop + max(
            0,
            measuredHeaderHeight - PlayerTheme.controlHeight
        )
    }

    static func animatesSpatialChanges(
        reducesMotion: Bool
    ) -> Bool {
        !reducesMotion
    }

    static func surfaceStrokeWidth(
        increasedContrast: Bool
    ) -> CGFloat {
        increasedContrast ? 2 : 1
    }

    static func surfaceStrokeOpacity(
        increasedContrast: Bool
    ) -> Double {
        increasedContrast ? 0.42 : 0.12
    }
}

struct PlayerSemanticSurface<SurfaceShape: InsettableShape>: View {
    enum Style {
        case solid
        case material(panelOverlayOpacity: Double)
    }

    let shape: SurfaceShape
    let style: Style
    var drawsStroke = true

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.playerReduceTransparencyOverride) private var reduceTransparencyOverride
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var usesOpaqueFill: Bool {
        PlayerAccessibilityPolicy.reducesTransparency(
            systemEnabled: reduceTransparency,
            forcedForTesting: reduceTransparencyOverride
        )
    }

    private var increasedContrast: Bool {
        colorSchemeContrast == .increased
    }

    var body: some View {
        ZStack {
            if usesOpaqueFill {
                shape.fill(PlayerTheme.opaquePanel)
            } else {
                switch style {
                case .solid:
                    shape.fill(PlayerTheme.panel)
                case .material(let panelOverlayOpacity):
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay {
                            shape.fill(
                                PlayerTheme.panel.opacity(panelOverlayOpacity)
                            )
                        }
                }
            }
        }
        .overlay {
            if drawsStroke {
                shape.stroke(
                    Color.white.opacity(
                        PlayerAccessibilityPolicy.surfaceStrokeOpacity(
                            increasedContrast: increasedContrast
                        )
                    ),
                    lineWidth: PlayerAccessibilityPolicy.surfaceStrokeWidth(
                        increasedContrast: increasedContrast
                    )
                )
            }
        }
        .shadow(
            color: Color.black.opacity(0.24),
            radius: 18,
            y: 8
        )
    }
}

struct PlayerEyebrow: View {
    let text: String
    var tint: Color = PlayerTheme.accent

    var body: some View {
        HStack(spacing: 7) {
            Capsule()
                .fill(tint)
                .frame(width: 18, height: 3)
            Text(text.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(PlayerTheme.secondaryText)
        }
    }
}

struct PlayerStatusPill: View {
    let text: String
    let systemName: String
    var tint: Color = PlayerTheme.success

    var body: some View {
        Label(text, systemImage: systemName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 11)
            .frame(minHeight: 30)
            .background {
                Capsule()
                    .fill(tint.opacity(0.13))
                    .overlay {
                        Capsule()
                            .stroke(tint.opacity(0.28), lineWidth: 1)
                    }
            }
    }
}
