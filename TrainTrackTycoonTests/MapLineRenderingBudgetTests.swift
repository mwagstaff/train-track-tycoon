import CoreLocation
import Foundation
import MapKit
import Testing
@testable import TrainTrackTycoon

@Suite("Map line rendering budgets")
struct MapLineRenderingBudgetTests {
    @Test("Dense networks respect the global line cap and retain focus")
    func denseNetworkIsBounded() {
        let london = MKMapPoint(CLLocationCoordinate2D(latitude: 51.507, longitude: -0.128))
        let viewport = MKMapRect(
            x: london.x - 20_000,
            y: london.y - 20_000,
            width: 40_000,
            height: 40_000
        )
        let nearby = (0..<400).map { index in
            RailwayMapLineCandidate(
                id: deterministicUUID(index),
                mapRect: MKMapRect(
                    x: london.x + Double(index % 20) * 100,
                    y: london.y + Double(index / 20) * 100,
                    width: 1_000,
                    height: 1_000
                )
            )
        }
        let focused = RailwayMapLineCandidate(
            id: deterministicUUID(999),
            mapRect: MKMapRect(x: 10, y: 10, width: 100, height: 100)
        )

        for detailLevel in RailwayMapRenderingDetailLevel.allCases {
            let rendered = RailwayMapRenderingPolicy.renderedLineIDs(
                from: nearby + [focused],
                focusedLineID: focused.id,
                visibleMapRect: viewport,
                maximumCount: detailLevel.maximumVisibleLineCount
            )

            #expect(rendered.count == detailLevel.maximumVisibleLineCount)
            #expect(rendered.last == focused.id)
            #expect(Set(rendered).count == rendered.count)
        }
    }

    @Test("Line selection is deterministic and ignores distant routes")
    func lineSelectionIsStable() {
        let london = MKMapPoint(CLLocationCoordinate2D(latitude: 51.507, longitude: -0.128))
        let viewport = MKMapRect(
            x: london.x - 10_000,
            y: london.y - 10_000,
            width: 20_000,
            height: 20_000
        )
        let candidates = (0..<20).map { index in
            RailwayMapLineCandidate(
                id: deterministicUUID(index),
                mapRect: MKMapRect(
                    x: london.x + Double(index) * 200,
                    y: london.y,
                    width: 50,
                    height: 50
                )
            )
        } + [
            RailwayMapLineCandidate(
                id: deterministicUUID(500),
                mapRect: MKMapRect(x: 10, y: 10, width: 50, height: 50)
            ),
        ]

        let first = RailwayMapRenderingPolicy.renderedLineIDs(
            from: candidates,
            focusedLineID: nil,
            visibleMapRect: viewport,
            maximumCount: 8
        )
        let second = RailwayMapRenderingPolicy.renderedLineIDs(
            from: Array(candidates.reversed()),
            focusedLineID: nil,
            visibleMapRect: viewport,
            maximumCount: 8
        )

        #expect(first == second)
        #expect(first.count == 8)
        #expect(!first.contains(deterministicUUID(500)))
    }

    @Test("Rendering tiers reduce geometry as the camera moves out")
    func distantTiersUseSmallerBudgets() {
        #expect(
            RailwayMapRenderingDetailLevel.country.maximumRoutePointCount
                < RailwayMapRenderingDetailLevel.regional.maximumRoutePointCount
        )
        #expect(
            RailwayMapRenderingDetailLevel.regional.maximumRoutePointCount
                < RailwayMapRenderingDetailLevel.local.maximumRoutePointCount
        )
        #expect(
            RailwayMapRenderingDetailLevel.country.maximumVisibleLineCount
                < RailwayMapRenderingDetailLevel.local.maximumVisibleLineCount
        )
    }

    private func deterministicUUID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
    }
}
