import CoreGraphics
import SwiftUI
import Testing
import UIKit
@testable import TrainTrackTycoon

@Suite("SwiftUI render smoke", .serialized)
@MainActor
struct SwiftUIRenderSmokeTests {
    private let portraitSize = CGSize(width: 390, height: 844)

    @Test("Game menu renders in both appearances without MapKit")
    func gameMenuAppearances() throws {
        let lightImage = try #require(renderGameMenu(colorScheme: .light))
        let darkImage = try #require(renderGameMenu(colorScheme: .dark))
        let lightMetrics = try #require(SwiftUIRenderMetrics(image: lightImage))
        let darkMetrics = try #require(SwiftUIRenderMetrics(image: darkImage))

        #expect(lightImage.width == Int(portraitSize.width))
        #expect(lightImage.height == Int(portraitSize.height))
        #expect(darkImage.width == Int(portraitSize.width))
        #expect(darkImage.height == Int(portraitSize.height))
        #expect(lightMetrics.opaquePixelFraction > 0.99)
        #expect(darkMetrics.opaquePixelFraction > 0.99)
        #expect(lightMetrics.luminanceSpan > 0.30)
        #expect(darkMetrics.luminanceSpan > 0.30)
        #expect(lightMetrics.quantizedColorCount >= 3)
        #expect(darkMetrics.quantizedColorCount >= 3)
        #expect(lightMetrics.meanLuminance > darkMetrics.meanLuminance + 0.12)
    }

    @Test("Destructive confirmation renders at accessibility text size")
    func confirmationAtAccessibilityTextSize() throws {
        let size = CGSize(width: 320, height: 568)
        let content = DeterministicRenderHost(
            colorScheme: .dark,
            dynamicTypeSize: .accessibility5
        ) {
            NewGameConfirmationOverlay(mode: .career, confirm: {}, cancel: {})
        }
        let image = try #require(SwiftUIRenderHarness.image(of: content, size: size))
        let metrics = try #require(SwiftUIRenderMetrics(image: image))

        #expect(image.width == Int(size.width))
        #expect(image.height == Int(size.height))
        #expect(metrics.opaquePixelFraction > 0.99)
        #expect(metrics.luminanceSpan > 0.30)
        #expect(metrics.quantizedColorCount >= 8)
    }

    @Test("Map station addition review reflows at accessibility text size")
    func mapStationAdditionAtAccessibilityTextSize() throws {
        let size = CGSize(width: 320, height: 568)
        let station = Station(
            crs: "SCY",
            name: "South Croydon",
            latitude: 51.362,
            longitude: -0.093
        )
        let proposal = MapStationAdditionProposal(
            station: station,
            options: [
                MapStationAdditionOption(
                    lineID: UUID(),
                    lineNumber: 1,
                    lineName: "East Croydon – Purley",
                    resultingStationCRSs: ["ECR", "SCY", "PUR"],
                    resultingStationNames: ["East Croydon", "South Croydon", "Purley"],
                    costPence: 200_000_000,
                    isAffordable: true,
                    servicePattern: .local
                ),
            ]
        )
        let content = DeterministicRenderHost(
            colorScheme: .dark,
            dynamicTypeSize: .accessibility5
        ) {
            MapStationAdditionOverlay(
                proposal: proposal,
                isLoading: false,
                confirm: { _ in },
                cancel: {}
            )
        }
        // The review is intentionally scroll-backed at Accessibility sizes. Mount it in UIKit
        // before capture so native ScrollView content is laid out deterministically.
        let image = try #require(SwiftUIRenderHarness.hostedImage(of: content, size: size))
        let metrics = try #require(SwiftUIRenderMetrics(image: image))

        #expect(image.width == Int(size.width))
        #expect(image.height == Int(size.height))
        #expect(metrics.opaquePixelFraction > 0.99)
        #expect(metrics.luminanceSpan > 0.30)
        #expect(metrics.quantizedColorCount >= 8)
    }

    @Test("Compact HUD renders at a narrow portrait width")
    func compactHUD() throws {
        let content = DeterministicRenderHost(
            colorScheme: .light,
            dynamicTypeSize: .large
        ) {
            VStack {
                TopStatusHUD(
                    session: GameSession(
                        stations: [],
                        clock: RenderTestSimulationClock()
                    ),
                    showLineDirectory: {},
                    showGameMenu: {}
                )
                    .padding(12)
                Spacer()
            }
        }
        let size = CGSize(width: 320, height: 160)
        let image = try #require(SwiftUIRenderHarness.image(of: content, size: size))
        let metrics = try #require(SwiftUIRenderMetrics(image: image))

        #expect(image.width == Int(size.width))
        #expect(image.height == Int(size.height))
        #expect(metrics.opaquePixelFraction > 0.99)
        #expect(metrics.luminanceSpan > 0.30)
        #expect(metrics.quantizedColorCount >= 8)
    }

    @Test("Station population remains legible across appearances and accessibility sizes")
    func stationPopulationAcrossAppearances() throws {
        try assertStationPopulationRender(
            colorScheme: .light,
            dynamicTypeSize: .large,
            size: CGSize(width: 320, height: 180)
        )
        try assertStationPopulationRender(
            colorScheme: .dark,
            dynamicTypeSize: .large,
            size: CGSize(width: 320, height: 180)
        )
        try assertStationPopulationRender(
            colorScheme: .light,
            dynamicTypeSize: .accessibility3,
            size: CGSize(width: 320, height: 290)
        )
        try assertStationPopulationRender(
            colorScheme: .dark,
            dynamicTypeSize: .accessibility3,
            size: CGSize(width: 320, height: 290)
        )
    }

    @Test("Panel accent meets normal-text contrast on opaque station panels")
    func stationPanelAccentContrast() throws {
        for interfaceStyle in [UIUserInterfaceStyle.light, .dark] {
            for accessibilityContrast in [UIAccessibilityContrast.normal, .high] {
                let traits = UITraitCollection(mutations: { mutableTraits in
                    mutableTraits.userInterfaceStyle = interfaceStyle
                    mutableTraits.accessibilityContrast = accessibilityContrast
                })
                let accent = UIColor(TycoonTheme.panelAccent).resolvedColor(with: traits)
                let panel = UIColor(TycoonTheme.opaquePanel).resolvedColor(with: traits)

                #expect(try contrastRatio(accent, panel) >= 4.5)
            }
        }
    }

    @Test("Panel warning meets normal-text contrast on opaque panels")
    func panelWarningContrast() throws {
        for interfaceStyle in [UIUserInterfaceStyle.light, .dark] {
            for accessibilityContrast in [UIAccessibilityContrast.normal, .high] {
                let traits = UITraitCollection(mutations: { mutableTraits in
                    mutableTraits.userInterfaceStyle = interfaceStyle
                    mutableTraits.accessibilityContrast = accessibilityContrast
                })
                let warning = UIColor(TycoonTheme.panelWarning).resolvedColor(with: traits)
                let panel = UIColor(TycoonTheme.opaquePanel).resolvedColor(with: traits)

                #expect(try contrastRatio(warning, panel) >= 4.5)
            }
        }
    }

    @Test("Line palette provides twelve distinct reusable identities")
    func expandedLinePalette() throws {
        var resolvedColors = Set<String>()
        for styleIndex in 0..<TycoonTheme.linePaletteCount {
            let color = UIColor(TycoonTheme.lineColor(for: styleIndex))
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            try #require(
                color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            )
            resolvedColors.insert("\(red)-\(green)-\(blue)-\(alpha)")
            #expect(try contrastRatio(color, .white) >= 4.5)
        }

        #expect(TycoonTheme.linePaletteCount == 12)
        #expect(resolvedColors.count == TycoonTheme.linePaletteCount)

        let first = UIColor(TycoonTheme.lineColor(for: 0))
        let repeated = UIColor(
            TycoonTheme.lineColor(for: TycoonTheme.linePaletteCount)
        )
        #expect(first == repeated)
    }

    @Test("Connecting journey panels render across appearances at narrow portrait width")
    func connectingJourneyPanelsAcrossAppearances() throws {
        for colorScheme in [ColorScheme.light, .dark] {
            try assertConnectingJourneyPanelsRender(
                colorScheme: colorScheme,
                dynamicTypeSize: .large,
                size: CGSize(width: 320, height: 300)
            )
        }
    }

    @Test("Connecting journey panels reflow at Accessibility Dynamic Type")
    func connectingJourneyPanelsAtAccessibilityTextSize() throws {
        try assertConnectingJourneyPanelsRender(
            colorScheme: .dark,
            dynamicTypeSize: .accessibility5,
            size: CGSize(width: 320, height: 568)
        )
    }

    @Test("Station capacity panels render across appearances at narrow portrait width")
    func stationCapacityPanelsAcrossAppearances() throws {
        for colorScheme in [ColorScheme.light, .dark] {
            try assertStationCapacityPanelsRender(
                colorScheme: colorScheme,
                dynamicTypeSize: .large,
                size: CGSize(width: 320, height: 330)
            )
        }
    }

    @Test("Station capacity panels reflow at Accessibility Dynamic Type")
    func stationCapacityPanelsAtAccessibilityTextSize() throws {
        try assertStationCapacityPanelsRender(
            colorScheme: .dark,
            dynamicTypeSize: .accessibility5,
            size: CGSize(width: 320, height: 568)
        )
    }

    private func assertStationPopulationRender(
        colorScheme: ColorScheme,
        dynamicTypeSize: DynamicTypeSize,
        size: CGSize
    ) throws {
        let content = DeterministicRenderHost(
            colorScheme: colorScheme,
            dynamicTypeSize: dynamicTypeSize
        ) {
            SettlementGrowthPanel(
                presentation: SettlementGrowthUIPresentation(
                    population: 128_450,
                    latestChange: 1_240,
                    demandMultiplier: 1.18,
                    reason: "Strong rail accessibility is supporting faster local growth."
                )
            )
            .padding(12)
        }
        let image = try #require(SwiftUIRenderHarness.image(of: content, size: size))
        let metrics = try #require(SwiftUIRenderMetrics(image: image))

        #expect(image.width == Int(size.width))
        #expect(image.height == Int(size.height))
        #expect(metrics.opaquePixelFraction > 0.99)
        #expect(metrics.luminanceSpan > 0.28)
        #expect(metrics.quantizedColorCount >= 8)
    }

    private func assertConnectingJourneyPanelsRender(
        colorScheme: ColorScheme,
        dynamicTypeSize: DynamicTypeSize,
        size: CGSize
    ) throws {
        let content = DeterministicRenderHost(
            colorScheme: colorScheme,
            dynamicTypeSize: dynamicTypeSize
        ) {
            VStack(spacing: 12) {
                ConnectingRidersPanel(
                    presentation: ConnectingRidersUIPresentation(
                        directRidersPerDay: 12_450,
                        connectingRidersPerDay: 2_680
                    )
                )
                InterchangeDemandPanel(
                    presentation: InterchangeDemandUIPresentation(
                        transferJourneysPerDay: 2_680
                    )
                )
            }
            .padding(12)
        }
        let image = try #require(SwiftUIRenderHarness.image(of: content, size: size))
        let metrics = try #require(SwiftUIRenderMetrics(image: image))

        #expect(image.width == Int(size.width))
        #expect(image.height == Int(size.height))
        #expect(metrics.opaquePixelFraction > 0.99)
        #expect(metrics.luminanceSpan > 0.28)
        #expect(metrics.quantizedColorCount >= 8)
    }

    private func assertStationCapacityPanelsRender(
        colorScheme: ColorScheme,
        dynamicTypeSize: DynamicTypeSize,
        size: CGSize
    ) throws {
        let content = DeterministicRenderHost(
            colorScheme: colorScheme,
            dynamicTypeSize: dynamicTypeSize
        ) {
            VStack(spacing: 12) {
                StationCapacityPanel(
                    presentation: StationCapacityUIPresentation(
                        platformCount: 1,
                        scheduledTrainCallsPerHour: 8,
                        effectiveTrainCallsPerHour: 4,
                        trainCallCapacityPerHour: 4,
                        isConstrained: true,
                        nextLevelName: "Local Station",
                        nextLevelPlatformCount: 2
                    )
                )
                LineStationCapacityPanel(
                    presentation: LineStationCapacityUIPresentation(
                        scheduledDeparturesPerHour: 2,
                        effectiveDeparturesPerHour: 1,
                        limitingStationNames: ["East Croydon"],
                        isOperating: true
                    )
                )
            }
            .padding(12)
        }
        let image = try #require(SwiftUIRenderHarness.image(of: content, size: size))
        let metrics = try #require(SwiftUIRenderMetrics(image: image))

        #expect(image.width == Int(size.width))
        #expect(image.height == Int(size.height))
        #expect(metrics.opaquePixelFraction > 0.99)
        #expect(metrics.luminanceSpan > 0.28)
        #expect(metrics.quantizedColorCount >= 8)
    }

    private func contrastRatio(_ first: UIColor, _ second: UIColor) throws -> Double {
        let firstLuminance = try relativeLuminance(first)
        let secondLuminance = try relativeLuminance(second)
        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ color: UIColor) throws -> Double {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        try #require(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))

        func linearized(_ component: CGFloat) -> Double {
            let component = Double(component)
            return component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        return linearized(red) * 0.2126
            + linearized(green) * 0.7152
            + linearized(blue) * 0.0722
    }

    @Test("Population statistics adapt to Accessibility Dynamic Type")
    func populationStatisticsAtAccessibilityTextSize() throws {
        var points: [PopulationHistoryPoint] = []
        for day in 1...30 {
            let population = Int64(100_000 + day * day * 18)
            let change = Int64((day * 2 - 1) * 18)
            points.append(
                PopulationHistoryPoint(
                operatingDay: UInt64(day),
                    population: population,
                    change: change
                )
            )
        }
        let content = DeterministicRenderHost(
            colorScheme: .light,
            dynamicTypeSize: .accessibility3
        ) {
            VStack(spacing: 12) {
                PopulationSummaryPanel(
                    population: points.last?.population ?? 0,
                    latestChange: points.last?.change ?? 0
                )
                PopulationTrendPanel(points: points)
            }
            .padding(12)
        }
        let size = CGSize(width: 320, height: 568)
        let image = try #require(SwiftUIRenderHarness.image(of: content, size: size))
        let metrics = try #require(SwiftUIRenderMetrics(image: image))

        #expect(image.width == Int(size.width))
        #expect(image.height == Int(size.height))
        #expect(metrics.opaquePixelFraction > 0.99)
        #expect(metrics.luminanceSpan > 0.28)
        #expect(metrics.quantizedColorCount >= 8)
    }

    private func renderGameMenu(colorScheme: ColorScheme) -> CGImage? {
        let content = DeterministicRenderHost(
            colorScheme: colorScheme,
            dynamicTypeSize: .large
        ) {
            GameMenuOverlay(
                currentMode: .career,
                showProgress: {},
                showSettings: {},
                startNewGame: { _ in },
                cancel: {}
            )
        }
        return SwiftUIRenderHarness.image(of: content, size: portraitSize)
    }
}
