import SwiftUI

/// A restrained, decorative atmosphere layer for the map. It intentionally fades
/// before the attribution area and never participates in hit testing.
struct WorldEffectsView: View {
    let snapshot: WorldEnvironmentSnapshot
    var intensity: Double = 1
    var showsWeather = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: weatherAnimationInterval,
                paused: !shouldAnimateWeather
            )
        ) { timeline in
            Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
                let strength = min(max(intensity.isFinite ? intensity : 0, 0), 1)
                drawLight(in: &context, size: size, strength: strength)

                let movementTime = reduceMotion
                    ? 0
                    : timeline.date.timeIntervalSinceReferenceDate
                if showsWeather {
                    drawWeather(
                        snapshot.weather,
                        in: &context,
                        size: size,
                        time: movementTime,
                        strength: strength
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Static light, clear skies and overcast weather redraw only when their parent snapshot
    /// changes. A display-rate timeline is reserved for genuinely moving rain or fog.
    private var shouldAnimateWeather: Bool {
        guard showsWeather, !reduceMotion else { return false }
        return snapshot.weather == .rain || snapshot.weather == .fog
    }

    /// Rain benefits from a little more motion than fog, but neither needs to redraw a full-screen
    /// transparent canvas at the train simulation cadence.
    private var weatherAnimationInterval: TimeInterval {
        snapshot.weather == .fog ? 0.2 : 0.1
    }

    private func drawLight(
        in context: inout GraphicsContext,
        size: CGSize,
        strength: Double
    ) {
        guard size.width > 0, size.height > 0, strength > 0 else { return }

        let fadeHeight = size.height * 0.88
        let rect = CGRect(origin: .zero, size: CGSize(width: size.width, height: fadeHeight))
        let opacityScale = reduceTransparency ? 0.6 : 1
        let nightVisibility = snapshot.nightIntensity * strength * opacityScale
        let nightOpacity = nightVisibility * 0.28
        let moonlightOpacity = nightVisibility * 0.07
        let daylightOpacity = snapshot.daylightFraction * 0.032 * strength * opacityScale
        // Peak warmth at twilight's midpoint, fading continuously into full day or night.
        // This avoids another hard edge exactly when MapKit changes its native palette.
        let twilightVisibility = 1 - abs(snapshot.daylightFraction * 2 - 1)
        let duskWarmth = twilightVisibility * 0.09 * strength * opacityScale

        if daylightOpacity > 0.001 {
            context.fill(
                Path(rect),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: TycoonTheme.warmPaper.opacity(daylightOpacity), location: 0),
                        .init(color: .clear, location: 0.82),
                    ]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width * 0.8, y: fadeHeight)
                )
            )
        }

        if nightOpacity > 0.001 {
            context.fill(
                Path(rect),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 0.01, green: 0.055, blue: 0.14).opacity(nightOpacity), location: 0),
                        .init(color: Color(red: 0.015, green: 0.07, blue: 0.16).opacity(nightOpacity * 0.72), location: 0.68),
                        .init(color: .clear, location: 1),
                    ]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: fadeHeight)
                )
            )

            context.fill(
                Path(rect),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(
                            color: Color(red: 0.20, green: 0.32, blue: 0.48)
                                .opacity(moonlightOpacity),
                            location: 0
                        ),
                        .init(color: .clear, location: 0.76),
                    ]),
                    startPoint: CGPoint(x: size.width, y: 0),
                    endPoint: CGPoint(x: size.width * 0.12, y: fadeHeight)
                )
            )
        }

        if duskWarmth > 0.001, !differentiateWithoutColor {
            context.fill(
                Path(rect),
                with: .linearGradient(
                    Gradient(colors: [
                        TycoonTheme.construction.opacity(duskWarmth),
                        .clear,
                    ]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: size.width, y: fadeHeight)
                )
            )
        }
    }

    private func drawWeather(
        _ weather: WorldWeather,
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval,
        strength: Double
    ) {
        guard strength > 0 else { return }
        switch weather {
        case .clear:
            break
        case .overcast:
            drawOvercast(in: &context, size: size, strength: strength)
        case .rain:
            drawRain(in: &context, size: size, time: time, strength: strength)
        case .fog:
            drawFog(in: &context, size: size, time: time, strength: strength)
        }
    }

    private func drawOvercast(
        in context: inout GraphicsContext,
        size: CGSize,
        strength: Double
    ) {
        let height = size.height * 0.68
        let rect = CGRect(origin: .zero, size: CGSize(width: size.width, height: height))
        let opacity = (reduceTransparency ? 0.025 : 0.055) * strength
        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: [Color.gray.opacity(opacity), .clear]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: height)
            )
        )
    }

    private func drawRain(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval,
        strength: Double
    ) {
        let visibleHeight = size.height * 0.84
        let count = reduceMotion ? 30 : 48
        let strokeOpacity = (reduceTransparency ? 0.18 : 0.25) * strength
        let speed = reduceMotion ? 0 : 310.0

        for index in 0..<count {
            let seed = UInt64(index) &* 0x9E37_79B9
            let xUnit = unitSample(seed ^ 0xA341_316C)
            let yUnit = unitSample(seed ^ 0xC801_3EA4)
            let length = 8 + unitSample(seed ^ 0xAD90_777D) * 11
            let drift = time * (0.12 + unitSample(seed ^ 0x7E95_761E) * 0.08)
            let x = (xUnit * size.width + drift * 12)
                .truncatingRemainder(dividingBy: max(size.width + 20, 1)) - 10
            let y = (yUnit * visibleHeight + time * speed)
                .truncatingRemainder(dividingBy: max(visibleHeight + length, 1)) - length

            var streak = Path()
            streak.move(to: CGPoint(x: x, y: y))
            streak.addLine(to: CGPoint(x: x - 3.5, y: y + length))
            context.stroke(
                streak,
                with: .color(Color.white.opacity(strokeOpacity)),
                lineWidth: differentiateWithoutColor ? 1.15 : 0.85
            )
        }
    }

    private func drawFog(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval,
        strength: Double
    ) {
        let visibleHeight = size.height * 0.76

        if reduceTransparency {
            for index in 0..<4 {
                let y = visibleHeight * (0.18 + Double(index) * 0.18)
                var band = Path()
                band.move(to: CGPoint(x: 0, y: y))
                band.addCurve(
                    to: CGPoint(x: size.width, y: y + 2),
                    control1: CGPoint(x: size.width * 0.3, y: y - 8),
                    control2: CGPoint(x: size.width * 0.72, y: y + 9)
                )
                context.stroke(
                    band,
                    with: .color(Color.white.opacity(0.13 * strength)),
                    lineWidth: differentiateWithoutColor ? 2 : 1
                )
            }
            return
        }

        for index in 0..<4 {
            let seed = UInt64(index) &* 0x85EB_CA6B
            let width = size.width * (0.72 + unitSample(seed ^ 0x1234) * 0.35)
            let height = 46 + unitSample(seed ^ 0xABCD) * 44
            let travel = reduceMotion ? 0 : time * (3 + Double(index) * 0.45)
            let x = (unitSample(seed ^ 0x5678) * (size.width + width) + travel)
                .truncatingRemainder(dividingBy: max(size.width + width, 1)) - width
            let y = visibleHeight * (0.08 + Double(index) * 0.145)
            let rect = CGRect(x: x, y: y, width: width, height: height)
            context.fill(
                Path(ellipseIn: rect),
                with: .color(Color.white.opacity(0.045 * strength))
            )
        }
    }

    private func unitSample(_ seed: UInt64) -> Double {
        var value = seed &+ 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value & 0xFFFF) / Double(UInt16.max)
    }
}

/// A compact confirmation that the cosmetic world simulation is active. The badge is
/// deliberately noninteractive so a drag that begins over it still manipulates the map.
struct WorldStatusBadge: View {
    let snapshot: WorldEnvironmentSnapshot
    var showsWeather = true

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var accessibilityContrast

    var body: some View {
        ViewThatFits(in: .horizontal) {
            fullStatus
            stackedStatus
        }
        .font(.caption2.weight(.bold))
        .textCase(.uppercase)
        .lineLimit(1)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .foregroundStyle(.primary)
        .background(
            reduceTransparency
                ? AnyShapeStyle(TycoonTheme.opaquePanel)
                : AnyShapeStyle(.regularMaterial),
            in: .capsule
        )
        .overlay {
            Capsule()
                .strokeBorder(
                    accessibilityContrast == .increased
                        ? Color.primary.opacity(0.72)
                        : Color.white.opacity(0.30),
                    lineWidth: accessibilityContrast == .increased ? 1.5 : 0.75
                )
        }
        .shadow(color: TycoonTheme.ink.opacity(0.14), radius: 10, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("World effects")
        .accessibilityValue(accessibilityValue)
        .allowsHitTesting(false)
    }

    private var fullStatus: some View {
        HStack(spacing: 7) {
            phaseLabel

            if showsWeather {
                separator
                weatherLabel
            }
        }
    }

    private var stackedStatus: some View {
        VStack(alignment: .leading, spacing: 2) {
            phaseLabel
            if showsWeather {
                weatherLabel
            }
        }
    }

    private var phaseLabel: some View {
        Label {
            Text("\(snapshot.clockText) · \(snapshot.phase.displayName)")
                .monospacedDigit()
        } icon: {
            Image(systemName: snapshot.phase.systemImageName)
                .foregroundStyle(phaseAccent)
        }
    }

    private var weatherLabel: some View {
        Label(snapshot.weather.displayName, systemImage: snapshot.weather.systemImageName)
            .foregroundStyle(.secondary)
    }

    private var separator: some View {
        Capsule()
            .fill(.secondary.opacity(0.42))
            .frame(width: 1, height: 12)
            .accessibilityHidden(true)
    }

    private var phaseAccent: Color {
        switch snapshot.phase {
        case .dawn, .dusk:
            TycoonTheme.construction
        case .day:
            TycoonTheme.panelAccent
        case .night:
            Color(red: 0.67, green: 0.76, blue: 0.90)
        }
    }

    private var accessibilityValue: String {
        let phase = "\(snapshot.clockText), \(snapshot.phase.displayName)"
        guard showsWeather else { return phase }
        return "\(phase), \(snapshot.weather.displayName) weather"
    }
}

private extension WorldDayPhase {
    var systemImageName: String {
        switch self {
        case .dawn: "sunrise.fill"
        case .day: "sun.max.fill"
        case .dusk: "sunset.fill"
        case .night: "moon.stars.fill"
        }
    }
}

private extension WorldWeather {
    var systemImageName: String {
        switch self {
        case .clear: "sparkles"
        case .overcast: "cloud.fill"
        case .rain: "cloud.rain.fill"
        case .fog: "cloud.fog.fill"
        }
    }
}

#Preview("Rain at dusk") {
    Color.green.opacity(0.35)
        .overlay {
            WorldEffectsView(snapshot: WorldEnvironmentSnapshot(
                elapsedWorldSeconds: 19 * 3_600,
                day: 3,
                secondsIntoDay: 19 * 3_600,
                phase: .dusk,
                weather: .rain,
                daylightFraction: 0.5,
                nightIntensity: 0.5
            ))
        }
        .ignoresSafeArea()
}

#Preview("Clear night status") {
    let snapshot = WorldEnvironmentSnapshot(
        elapsedWorldSeconds: 22.5 * 3_600,
        day: 4,
        secondsIntoDay: 22.5 * 3_600,
        phase: .night,
        weather: .clear,
        daylightFraction: 0,
        nightIntensity: 1
    )

    ZStack(alignment: .topTrailing) {
        Color(red: 0.10, green: 0.22, blue: 0.18)
        WorldEffectsView(snapshot: snapshot)
        WorldStatusBadge(snapshot: snapshot)
            .padding()
    }
    .ignoresSafeArea()
}
