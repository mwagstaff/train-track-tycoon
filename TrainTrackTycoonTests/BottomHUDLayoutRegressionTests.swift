import CoreGraphics
import SwiftUI
import Testing
@testable import TrainTrackTycoon

@Suite("Bottom HUD layout regression", .serialized)
@MainActor
struct BottomHUDLayoutRegressionTests {
    @Test("Station dismissal returns a completed network summary to the bottom thumb zone")
    func completedNetworkStationDismissal() async throws {
        let session = makeSession()
        await buildLine(in: session, from: stations[0], to: stations[1])
        await buildLine(in: session, from: stations[1], to: stations[2])
        #expect(!session.canBuildAnotherLine)

        session.selectStationForInspection(stations[1].crs)
        #expect(session.selectedStation?.crs == stations[1].crs)
        #expect(
            BottomPanelPresentationPolicy.presentation(
                isBankrupt: session.financeLedger.isBankrupt,
                phase: session.phase,
                selectedTrainID: session.selectedTrainID,
                selectedStationCRS: session.selectedStationID,
                showsNetworkPerformance: false,
                hasLines: !session.lines.isEmpty
            ) == .station(stations[1].crs)
        )

        session.selectStationForInspection(nil)
        #expect(session.selectedStation == nil)
        let dismissedPresentation = BottomPanelPresentationPolicy.presentation(
            isBankrupt: session.financeLedger.isBankrupt,
            phase: session.phase,
            selectedTrainID: session.selectedTrainID,
            selectedStationCRS: session.selectedStationID,
            showsNetworkPerformance: false,
            hasLines: !session.lines.isEmpty
        )
        #expect(dismissedPresentation == .build)
        #expect(
            !BottomPanelPresentationPolicy.showsBuildAction(
                for: dismissedPresentation,
                canBuildAnotherLine: session.canBuildAnotherLine
            )
        )

        let portraitSize = CGSize(width: 390, height: 844)
        let dismissedImage = try #require(
            renderBottomControls(
                session: session,
                size: portraitSize,
                dynamicTypeSize: .large
            )
        )
        let dismissedBounds = try #require(significantContentBounds(in: dismissedImage))

        // With the dead completion control removed, only the pulse and attribution remain. This
        // returns the pulse to the thumb zone and releases most of the portrait map for pan. The
        // selected station panel itself is intentionally not snapshot-rendered here because its
        // native ProgressView cannot be flattened reliably by ImageRenderer on every iOS runtime.
        #expect(dismissedBounds.height < 210)
        #expect(distanceFromNearestVerticalEdge(dismissedBounds, image: dismissedImage) < 28)

        let narrowSize = CGSize(width: 320, height: 568)
        let narrowImage = try #require(
            renderBottomControls(
                session: session,
                size: narrowSize,
                dynamicTypeSize: .large
            )
        )
        let narrowBounds = try #require(significantContentBounds(in: narrowImage))
        #expect(narrowBounds.height < 210)
        #expect(distanceFromNearestVerticalEdge(narrowBounds, image: narrowImage) < 28)

        let accessibilityMaximumHeight = GameRootPresentationPolicy.maximumBottomPanelHeight(
            containerHeight: portraitSize.height,
            usesAccessibilityTextSize: true
        )
        #expect(accessibilityMaximumHeight == portraitSize.height * 0.60)
        #expect(accessibilityMaximumHeight < portraitSize.height)
    }

    private func renderBottomControls(
        session: GameSession,
        size: CGSize,
        dynamicTypeSize: DynamicTypeSize
    ) -> CGImage? {
        let maximumHeight = GameRootPresentationPolicy.maximumBottomPanelHeight(
            containerHeight: size.height,
            usesAccessibilityTextSize: dynamicTypeSize.isAccessibilitySize
        )
        let content = DeterministicRenderHost(
            colorScheme: .dark,
            dynamicTypeSize: dynamicTypeSize
        ) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                    .allowsHitTesting(false)

                BottomControlsViewport(maximumHeight: maximumHeight) {
                    BottomControlPanel(
                        session: session,
                        showsHappinessHeatmap: .constant(false),
                        isShowingNetworkPerformance: .constant(false)
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 5)
        }
        return SwiftUIRenderHarness.image(of: content, size: size)
    }

    private func significantContentBounds(in image: CGImage) -> CGRect? {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return nil }

        let background = (pixels[0], pixels[1], pixels[2])
        let minimumChangedPixels = max(width / 8, 1)
        var firstRow: Int?
        var lastRow: Int?

        for row in 0..<height {
            var changedPixels = 0
            for column in 0..<width {
                let index = row * bytesPerRow + column * bytesPerPixel
                let difference = abs(Int(pixels[index]) - Int(background.0))
                    + abs(Int(pixels[index + 1]) - Int(background.1))
                    + abs(Int(pixels[index + 2]) - Int(background.2))
                if difference > 18 {
                    changedPixels += 1
                }
            }
            guard changedPixels >= minimumChangedPixels else { continue }
            firstRow = firstRow ?? row
            lastRow = row
        }

        guard let firstRow, let lastRow else { return nil }
        return CGRect(
            x: 0,
            y: CGFloat(firstRow),
            width: CGFloat(width),
            height: CGFloat(lastRow - firstRow + 1)
        )
    }

    private func distanceFromNearestVerticalEdge(_ bounds: CGRect, image: CGImage) -> Int {
        min(
            Int(bounds.minY),
            max(image.height - 1 - Int(bounds.maxY), 0)
        )
    }

    private func makeSession() -> GameSession {
        GameSession(
            stations: stations,
            routingProvider: BottomHUDRoutingProvider(route: route),
            clock: RenderTestSimulationClock(),
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 20,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000
            )
        )
    }

    private func buildLine(
        in session: GameSession,
        from origin: Station,
        to destination: Station
    ) async {
        session.startBuilding()
        session.selectStation(origin)
        session.selectStation(destination)
        await session.waitForRouteCalculation()
        #expect(session.phase == .preview)
        session.confirmPreview()
        #expect(session.phase == .operating)
    }

    private var stations: [Station] {
        [
            Station(crs: "SEL", name: "Selhurst", latitude: 51.3919, longitude: -0.0891),
            Station(
                crs: "ECR",
                name: "East Croydon",
                latitude: 51.3755,
                longitude: -0.0928
            ),
            Station(crs: "PUR", name: "Purley", latitude: 51.3376, longitude: -0.1140),
        ]
    }

    private var route: ServiceRailwayRoute {
        ServiceRailwayRoute(
            coordinates: [stations[0].coordinate, stations[1].coordinate],
            cumulativeDistances: [0, 10_000],
            stationCoordinateIndices: [0, 1]
        )
    }
}

private nonisolated struct BottomHUDRoutingProvider: RailwayRouteProviding {
    let route: ServiceRailwayRoute

    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        route
    }
}
