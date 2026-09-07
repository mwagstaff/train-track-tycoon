import CoreGraphics
import SwiftUI
import Testing
import UIKit
@testable import TrainTrackTycoon

@Suite("Rolling stock SwiftUI rendering", .serialized)
@MainActor
struct RollingStockSwiftUIRenderTests {
    private let narrowPortraitSize = CGSize(width: 320, height: 568)

    @Test("Formation preview remains legible and map-first at narrow portrait width")
    func formationPreviewAtNarrowPortraitWidth() async throws {
        let session = makeSession()
        await preparePreview(in: session)
        #expect(session.phase == .preview)

        for (colorScheme, formation) in [
            (ColorScheme.light, RollingStockFormation.twoCar),
            (.dark, .twelveCar),
        ] {
            session.setPreviewFormation(formation)
            #expect(session.preview?.formation == formation)

            let image = try #require(
                renderBottomControls(
                    session: session,
                    colorScheme: colorScheme,
                    dynamicTypeSize: .large
                )
            )
            try assertUsefulRender(image)
            assertMapFirstBottomPanel(dynamicTypeSize: .large)
        }
    }

    @Test("Formation preview reflows at Accessibility Dynamic Type in both appearances")
    func formationPreviewAtAccessibilityTextSize() async throws {
        let session = makeSession()
        await preparePreview(in: session)
        session.setPreviewFormation(.twelveCar)

        for colorScheme in [ColorScheme.light, .dark] {
            let image = try #require(
                renderBottomControls(
                    session: session,
                    colorScheme: colorScheme,
                    dynamicTypeSize: .accessibility5
                )
            )
            try assertUsefulRender(image)
            assertMapFirstBottomPanel(dynamicTypeSize: .accessibility5)
        }
    }

    @Test("Purchased formation controls render after construction at Accessibility Dynamic Type")
    func purchasedFormationControlsAtAccessibilityTextSize() async throws {
        let session = makeSession()
        await preparePreview(in: session)
        session.setPreviewFormation(.tenCar)
        session.confirmPreview()

        let line = try #require(session.lines.first)
        #expect(line.formation == .tenCar)
        let train = try #require(line.trains.first)
        session.selectTrain(train.id)
        #expect(session.selectedTrainID == train.id)

        for colorScheme in [ColorScheme.light, .dark] {
            let image = try #require(
                renderBottomControls(
                    session: session,
                    colorScheme: colorScheme,
                    dynamicTypeSize: .accessibility5
                )
            )
            try assertUsefulRender(image)
            assertMapFirstBottomPanel(dynamicTypeSize: .accessibility5)
        }
    }

    private func renderBottomControls(
        session: GameSession,
        colorScheme: ColorScheme,
        dynamicTypeSize: DynamicTypeSize
    ) -> CGImage? {
        let maximumHeight = GameRootPresentationPolicy.maximumBottomPanelHeight(
            containerHeight: narrowPortraitSize.height,
            usesAccessibilityTextSize: dynamicTypeSize.isAccessibilitySize
        )
        let content = DeterministicRenderHost(
            colorScheme: colorScheme,
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
        return SwiftUIRenderHarness.hostedImage(of: content, size: narrowPortraitSize)
    }

    private func assertUsefulRender(_ image: CGImage) throws {
        let metrics = try #require(SwiftUIRenderMetrics(image: image))
        #expect(image.width == Int(narrowPortraitSize.width))
        #expect(image.height == Int(narrowPortraitSize.height))
        #expect(metrics.opaquePixelFraction > 0.99)
        #expect(metrics.luminanceSpan > 0.28)
        #expect(metrics.quantizedColorCount >= 8)
    }

    private func assertMapFirstBottomPanel(dynamicTypeSize: DynamicTypeSize) {
        let maximumHeight = GameRootPresentationPolicy.maximumBottomPanelHeight(
            containerHeight: narrowPortraitSize.height,
            usesAccessibilityTextSize: dynamicTypeSize.isAccessibilitySize
        )
        let expectedFraction = dynamicTypeSize.isAccessibilitySize ? 0.60 : 0.56
        let freeMapHeight = narrowPortraitSize.height - maximumHeight

        // The viewport owns only the production policy's bounded bottom region. Its ScrollView
        // therefore cannot become a full-screen hit surface, leaving at least 40% of this compact
        // portrait available for direct map pan and pinch even at the largest text size.
        #expect(
            abs(maximumHeight - narrowPortraitSize.height * expectedFraction) < 0.001
        )
        #expect(maximumHeight < narrowPortraitSize.height)
        #expect(freeMapHeight + 0.001 >= narrowPortraitSize.height * 0.40)
    }

    private func preparePreview(in session: GameSession) async {
        session.startBuilding()
        session.selectStation(stations[0])
        session.selectStation(stations[1])
        await session.waitForRouteCalculation()
    }

    private func makeSession() -> GameSession {
        GameSession(
            stations: stations,
            routingProvider: RollingStockRenderRoutingProvider(route: route),
            clock: RenderTestSimulationClock(),
            configuration: GameConfiguration(
                maximumLineCount: 3,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 20,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000
            )
        )
    }

    private var stations: [Station] {
        [
            Station(
                crs: "VIC",
                name: "London Victoria",
                latitude: 51.4952,
                longitude: -0.1441
            ),
            Station(
                crs: "ECR",
                name: "East Croydon",
                latitude: 51.3755,
                longitude: -0.0928
            ),
        ]
    }

    private var route: ServiceRailwayRoute {
        ServiceRailwayRoute(
            coordinates: [stations[0].coordinate, stations[1].coordinate],
            cumulativeDistances: [0, 16_000],
            stationCoordinateIndices: [0, 1]
        )
    }
}

private nonisolated struct RollingStockRenderRoutingProvider: RailwayRouteProviding {
    let route: ServiceRailwayRoute

    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        route
    }
}
