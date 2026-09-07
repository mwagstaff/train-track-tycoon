import CoreGraphics
import CoreLocation
import SwiftUI
import Testing
@testable import TrainTrackTycoon

@Suite("Intermediate station SwiftUI rendering", .serialized)
@MainActor
struct IntermediateStationSwiftUIRenderTests {
    private let narrowPortraitSize = CGSize(width: 320, height: 568)

    @Test("Preview call selector remains bounded across portrait contexts")
    func previewCallSelectorPortraitContexts() throws {
        let stations = sampleStations

        for (colorScheme, dynamicTypeSize) in [
            (ColorScheme.light, DynamicTypeSize.large),
            (.dark, .large),
            (.dark, .accessibility5),
        ] {
            let content = DeterministicRenderHost(
                colorScheme: colorScheme,
                dynamicTypeSize: dynamicTypeSize
            ) {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)

                    BottomControlsViewport(maximumHeight: maximumHeight(dynamicTypeSize)) {
                        ScrollView {
                            PreviewCallingPointsSection(
                                origin: stations[0],
                                destination: stations[4],
                                intermediateStations: Array(stations[1...3]),
                                selectedStationCRSs: ["VIC", "BRX", "HNH", "KTH"],
                                maximumStopCount: 16,
                                isUpdatingRoute: false,
                                isExpanded: .constant(true),
                                toggleIntermediateStation: { _ in }
                            )
                        }
                        .frame(height: maximumHeight(dynamicTypeSize))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 5)
            }

            try assertPortraitRender(content)
            #expect(
                narrowPortraitSize.height - maximumHeight(dynamicTypeSize) + 0.001
                    >= narrowPortraitSize.height * 0.40
            )
        }
    }

    @Test("Built service stop additions show route, prices, and actions")
    func builtServiceStopAdditions() throws {
        let stations = sampleStations
        let line = makeLine(origin: stations[0], destination: stations[4])

        for (colorScheme, dynamicTypeSize) in [
            (ColorScheme.light, DynamicTypeSize.large),
            (.dark, .large),
            (.dark, .accessibility5),
        ] {
            let content = DeterministicRenderHost(
                colorScheme: colorScheme,
                dynamicTypeSize: dynamicTypeSize
            ) {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)

                    BottomControlsViewport(maximumHeight: maximumHeight(dynamicTypeSize)) {
                        ScrollView {
                            BuiltLineStopsSection(
                                line: line,
                                stationCatalog: stations,
                                availableIntermediateStations: Array(stations[1...3]),
                                maximumStopCount: 16,
                                isEditing: true,
                                isUpdating: false,
                                gameMode: .career,
                                beginEditing: {},
                                addStation: { _ in },
                                finishEditing: {},
                                additionCostPence: { _ in 12_500_000 },
                                canAfford: { station in station.crs != "SYD" }
                            )
                        }
                        .frame(height: maximumHeight(.large))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 5)
            }

            try assertPortraitRender(content)
            #expect(
                narrowPortraitSize.height - maximumHeight(dynamicTypeSize) + 0.001
                    >= narrowPortraitSize.height * 0.40
            )
        }
    }

    @Test("Permanent stop confirmation names the station and price")
    func permanentStopConfirmationCopy() {
        let station = sampleStations[1]
        let copy = StopAdditionConfirmationCopy(
            station: station,
            costPence: 12_500_000
        )

        #expect(copy.title == "Add Brixton permanently?")
        #expect(copy.actionTitle == "Add for £125,000")
        #expect(copy.message.contains("£125,000"))
        #expect(copy.message.contains("Brixton"))
        #expect(copy.message.contains("Removing stops arrives in a later milestone"))
    }

    private func assertPortraitRender<Content: View>(_ content: Content) throws {
        let image = try #require(
            SwiftUIRenderHarness.hostedImage(of: content, size: narrowPortraitSize)
        )
        let metrics = try #require(SwiftUIRenderMetrics(image: image))

        #expect(image.width == Int(narrowPortraitSize.width))
        #expect(image.height == Int(narrowPortraitSize.height))
        #expect(metrics.opaquePixelFraction > 0.99)
        #expect(metrics.luminanceSpan > 0.28)
        #expect(metrics.quantizedColorCount >= 8)
    }

    private func maximumHeight(_ dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        GameRootPresentationPolicy.maximumBottomPanelHeight(
            containerHeight: narrowPortraitSize.height,
            usesAccessibilityTextSize: dynamicTypeSize.isAccessibilitySize
        )
    }

    private var sampleStations: [Station] {
        [
            Station(
                crs: "VIC",
                name: "London Victoria",
                latitude: 51.4952,
                longitude: -0.1441
            ),
            Station(crs: "BRX", name: "Brixton", latitude: 51.4627, longitude: -0.1145),
            Station(crs: "HNH", name: "Herne Hill", latitude: 51.4533, longitude: -0.1025),
            Station(crs: "SYD", name: "Sydenham Hill", latitude: 51.4327, longitude: -0.0803),
            Station(crs: "KTH", name: "Kent House", latitude: 51.4122, longitude: -0.0452),
        ]
    }

    private func makeLine(origin: Station, destination: Station) -> BuiltLine {
        let route = ServiceRailwayRoute(
            coordinates: [origin.coordinate, destination.coordinate]
        )
        return BuiltLine(
            id: UUID(),
            name: "\(origin.name) – \(destination.name)",
            origin: origin,
            destination: destination,
            route: route,
            distanceMetres: route.totalLength,
            indicativeCost: 1_000_000,
            styleIndex: 0,
            railwayClass: .conventional,
            formation: .sixCar,
            servicePattern: .local,
            serviceFrequency: .halfHourly,
            ownedTrainCount: 2,
            constructionProgress: 1,
            trains: [],
            stationCRSs: [origin.crs, destination.crs]
        )
    }
}
