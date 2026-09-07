import SwiftUI
import UIKit

enum TycoonTheme {
    static let linePaletteCount = 12
    static let railGreen = Color(red: 0.08, green: 0.29, blue: 0.22)
    static let railGreenBright = Color(red: 0.20, green: 0.56, blue: 0.38)
    /// Semantic accent for text and symbols placed on adaptive panels.
    static let panelAccent = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.42, green: 0.88, blue: 0.64, alpha: 1)
        }
        return UIColor(red: 0.08, green: 0.29, blue: 0.22, alpha: 1)
    })
    /// Semantic warning colour with readable contrast on both adaptive panel appearances.
    static let panelWarning = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.95, green: 0.64, blue: 0.12, alpha: 1)
        }
        return UIColor(red: 0.54, green: 0.30, blue: 0.015, alpha: 1)
    })
    static let warmPaper = Color(red: 0.96, green: 0.95, blue: 0.90)
    static let ink = Color(red: 0.035, green: 0.08, blue: 0.075)
    static let construction = Color(red: 0.95, green: 0.64, blue: 0.12)
    static let highSpeedViolet = Color(red: 0.38, green: 0.19, blue: 0.72)
    static let highSpeedElectric = Color(red: 0.20, green: 0.83, blue: 0.94)
    static let highSpeedGold = Color(red: 0.97, green: 0.72, blue: 0.20)
    static let opaquePanel = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.075, green: 0.105, blue: 0.10, alpha: 1)
        }
        return UIColor(red: 0.96, green: 0.95, blue: 0.90, alpha: 1)
    })

    static func happinessColor(for score: Double) -> Color {
        switch min(max(score.isFinite ? score : 0, 0), 100) {
        case ..<40:
            Color(red: 0.82, green: 0.24, blue: 0.20)
        case ..<70:
            construction
        default:
            railGreenBright
        }
    }

    static func lineColor(for styleIndex: Int) -> Color {
        let paletteIndex = ((styleIndex % linePaletteCount) + linePaletteCount)
            % linePaletteCount
        return switch paletteIndex {
        case 0:
            Color(red: 0.06, green: 0.45, blue: 0.78)
        case 1:
            Color(red: 0.80, green: 0.17, blue: 0.14)
        case 2:
            Color(red: 0.38, green: 0.24, blue: 0.65)
        case 3:
            Color(red: 0.10, green: 0.43, blue: 0.20)
        case 4:
            Color(red: 0.64, green: 0.30, blue: 0.06)
        case 5:
            Color(red: 0.02, green: 0.42, blue: 0.43)
        case 6:
            Color(red: 0.64, green: 0.16, blue: 0.43)
        case 7:
            Color(red: 0.18, green: 0.31, blue: 0.62)
        case 8:
            Color(red: 0.48, green: 0.31, blue: 0.16)
        case 9:
            Color(red: 0.02, green: 0.39, blue: 0.60)
        case 10:
            Color(red: 0.49, green: 0.22, blue: 0.50)
        default:
            Color(red: 0.36, green: 0.38, blue: 0.10)
        }
    }
}

struct RailPanelModifier: ViewModifier {
    var cornerRadius: CGFloat = 24

    @Environment(\.colorSchemeContrast) private var accessibilityContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background(
                reduceTransparency
                    ? AnyShapeStyle(TycoonTheme.opaquePanel)
                    : AnyShapeStyle(.regularMaterial),
                in: .rect(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        accessibilityContrast == .increased
                            ? Color.primary.opacity(0.72)
                            : Color.white.opacity(0.34),
                        lineWidth: accessibilityContrast == .increased ? 1.5 : 0.75
                    )
            }
            .shadow(
                color: TycoonTheme.ink.opacity(
                    reduceTransparency || accessibilityContrast == .increased ? 0.24 : 0.16
                ),
                radius: reduceTransparency ? 8 : 18,
                y: reduceTransparency ? 3 : 8
            )
    }
}

extension View {
    func railPanel(cornerRadius: CGFloat = 24) -> some View {
        modifier(RailPanelModifier(cornerRadius: cornerRadius))
    }
}

struct RailwayGlyph: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(TycoonTheme.railGreen)

            ZStack {
                HStack(spacing: 7) {
                    Capsule()
                    Capsule()
                }
                .foregroundStyle(TycoonTheme.warmPaper)
                .frame(width: 10, height: 22)

                VStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { _ in
                        Capsule()
                            .fill(TycoonTheme.warmPaper.opacity(0.94))
                            .frame(width: 19, height: 2)
                    }
                }
            }
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }
}

#Preview("Theme") {
    ZStack {
        Color.green.opacity(0.15).ignoresSafeArea()
        RailwayGlyph()
    }
}
