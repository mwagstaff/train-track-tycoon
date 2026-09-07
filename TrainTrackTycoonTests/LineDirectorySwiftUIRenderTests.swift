import CoreGraphics
import CoreLocation
import SwiftUI
import Testing
@testable import TrainTrackTycoon

@Suite("Line directory SwiftUI rendering", .serialized)
@MainActor
struct LineDirectorySwiftUIRenderTests {
    private let narrowPortraitSize = CGSize(width: 320, height: 568)

    @Test("Line directory remains legible and bounded across portrait contexts")
    func portraitContexts() throws {
        let lines = makeLines(count: 6)

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

                    BottomControlsViewport(
                        maximumHeight: GameRootPresentationPolicy.maximumBottomPanelHeight(
                            containerHeight: narrowPortraitSize.height,
                            usesAccessibilityTextSize: dynamicTypeSize.isAccessibilitySize
                        )
                    ) {
                        LineDirectoryPanel(
                            lines: lines,
                            maximumHeight: GameRootPresentationPolicy.maximumBottomPanelHeight(
                                containerHeight: narrowPortraitSize.height,
                                usesAccessibilityTextSize: dynamicTypeSize.isAccessibilitySize
                            ),
                            manageLine: { _ in },
                            close: {}
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 5)
            }

            let image = try #require(
                SwiftUIRenderHarness.hostedImage(of: content, size: narrowPortraitSize)
            )
            let metrics = try #require(SwiftUIRenderMetrics(image: image))

            #expect(image.width == Int(narrowPortraitSize.width))
            #expect(image.height == Int(narrowPortraitSize.height))
            #expect(metrics.opaquePixelFraction > 0.99)
            #expect(metrics.luminanceSpan > 0.28)
            #expect(metrics.quantizedColorCount >= 8)

            let maximumHeight = GameRootPresentationPolicy.maximumBottomPanelHeight(
                containerHeight: narrowPortraitSize.height,
                usesAccessibilityTextSize: dynamicTypeSize.isAccessibilitySize
            )
            #expect(maximumHeight < narrowPortraitSize.height)
            #expect(
                narrowPortraitSize.height - maximumHeight + 0.001
                    >= narrowPortraitSize.height * 0.40
            )
        }
    }

    @Test("Repeated focus requests for one line remain observable")
    func repeatedFocusRequests() {
        let lineID = UUID(uuidString: "B673A31A-07C6-49D3-BF70-706A34A6A8BA")!
        let first = LineMapFocusRequest(lineID: lineID, sequence: 1)
        let repeatRequest = LineMapFocusRequest(lineID: lineID, sequence: 2)

        #expect(first.lineID == repeatRequest.lineID)
        #expect(first != repeatRequest)
    }

    private func makeLines(count: Int) -> [BuiltLine] {
        (0..<count).map { index in
            let origin = Station(
                crs: "O\(index)",
                name: index == 0 ? "London Victoria" : "Station \(index)",
                latitude: 51.50 - (Double(index) * 0.015),
                longitude: -0.14 + (Double(index) * 0.012)
            )
            let destination = Station(
                crs: "D\(index)",
                name: index == count - 1 ? "Brighton" : "Destination \(index)",
                latitude: origin.latitude - 0.08,
                longitude: origin.longitude + 0.03
            )
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
                styleIndex: index,
                railwayClass: index == 4 ? .highSpeed : .conventional,
                servicePattern: ServicePattern.allCases[index % ServicePattern.allCases.count],
                serviceFrequency: ServiceFrequency.allCases[
                    index % ServiceFrequency.allCases.count
                ],
                ownedTrainCount: 2,
                constructionProgress: 1,
                trains: []
            )
        }
    }
}
