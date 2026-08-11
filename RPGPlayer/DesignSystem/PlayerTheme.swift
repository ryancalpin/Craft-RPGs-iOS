import SwiftUI

enum PlayerTheme {
    static let canvas = Color(red: 0.025, green: 0.04, blue: 0.065)
    static let panel = Color(red: 0.045, green: 0.075, blue: 0.12).opacity(0.92)
    static let opaquePanel = Color(red: 0.041, green: 0.067, blue: 0.105)
    static let panelStroke = Color.white.opacity(0.12)
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.62)
    static let accent = Color(red: 0.88, green: 0.66, blue: 0.19)
    static let pageInset: CGFloat = 16
    static let controlHeight: CGFloat = 52
    static let panelRadius: CGFloat = 22
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
    }
}
