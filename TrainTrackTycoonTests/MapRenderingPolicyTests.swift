import CoreLocation
import Foundation
import MapKit
import Testing
@testable import TrainTrackTycoon

@Suite("Country-scale map rendering policy")
struct MapRenderingPolicyTests {
    @Test("Catalogue and built markers are bounded while active selections are retained")
    func stationCullingKeepsSelections() {
        let centre = CLLocationCoordinate2D(latitude: 51.50, longitude: -0.12)
        let candidates = (0..<420).map { index in
            Station(
                crs: String(format: "%03X", index),
                name: "Candidate \(index)",
                latitude: centre.latitude + Double(index % 20) * 0.000_1,
                longitude: centre.longitude + Double(index / 20) * 0.000_1
            )
        }
        let selected = Station(
            crs: "EDB",
            name: "Edinburgh",
            latitude: 55.952,
            longitude: -3.189
        )
        let viewport = mapRect(around: centre, halfSize: 30_000)

        let distantBuilt = Station(
            crs: "ABD",
            name: "Aberdeen",
            latitude: 57.15,
            longitude: -2.10
        )
        let builtCRSs = Set(candidates.map(\.crs)).union([distantBuilt.crs])

        for detailLevel in RailwayMapRenderingDetailLevel.allCases {
            let rendered = RailwayMapRenderingPolicy.renderedStations(
                from: candidates + [selected, distantBuilt],
                builtStationCRSs: builtCRSs,
                selectedStationCRSs: ["edb"],
                visibleMapRect: viewport,
                detailLevel: detailLevel
            )

            #expect(rendered.count == detailLevel.builtStationLimit + 1)
            #expect(rendered.last?.crs == "EDB")
            #expect(!rendered.contains { $0.crs == "ABD" })
            #expect(Set(rendered.map(\.crs)).count == rendered.count)
        }
    }

    @Test("Built stations are preferred without consuming the candidate budget")
    func builtStationsHaveIndependentBudget() {
        let centre = CLLocationCoordinate2D(latitude: 51.50, longitude: -0.12)
        let stations = (0..<600).map { index in
            Station(
                crs: String(format: "%03X", index),
                name: "Station \(index)",
                latitude: centre.latitude + Double(index % 25) * 0.000_1,
                longitude: centre.longitude + Double(index / 25) * 0.000_1
            )
        }
        let builtCRSs = Set(stations.prefix(300).map(\.crs))
        let detailLevel = RailwayMapRenderingDetailLevel.regional

        let rendered = RailwayMapRenderingPolicy.renderedStations(
            from: stations,
            builtStationCRSs: builtCRSs,
            selectedStationCRSs: [],
            visibleMapRect: mapRect(around: centre, halfSize: 30_000),
            detailLevel: detailLevel
        )

        #expect(rendered.count == detailLevel.builtStationLimit + detailLevel.candidateStationLimit)
        #expect(rendered.filter { builtCRSs.contains($0.crs) }.count == detailLevel.builtStationLimit)
    }

    @Test("Route level of detail has a deterministic hard point bound")
    func routeSimplification() {
        let coordinates = (0..<20_000).map { index in
            CLLocationCoordinate2D(
                latitude: 50 + Double(index) * 0.000_01,
                longitude: -5 + sin(Double(index) / 20) * 0.01
            )
        }

        let first = RailwayMapRenderingPolicy.simplifiedCoordinates(
            coordinates,
            maximumPointCount: 384
        )
        let second = RailwayMapRenderingPolicy.simplifiedCoordinates(
            coordinates,
            maximumPointCount: 384
        )

        #expect(first.count == 384)
        #expect(first.map(\.latitude) == second.map(\.latitude))
        #expect(first.map(\.longitude) == second.map(\.longitude))
        #expect(first.first?.latitude == coordinates.first?.latitude)
        #expect(first.last?.latitude == coordinates.last?.latitude)
        #expect(first.last?.longitude == coordinates.last?.longitude)
    }

    @Test("Only trains near the viewport are returned and selection is preserved")
    func trainCullingKeepsSelection() {
        let lineID = UUID()
        let centre = CLLocationCoordinate2D(latitude: 51.50, longitude: -0.12)
        let nearby = (0..<100).map { index in
            TrainState(
                id: UUID(),
                lineID: lineID,
                coordinate: CLLocationCoordinate2D(
                    latitude: centre.latitude + Double(index % 10) * 0.000_1,
                    longitude: centre.longitude + Double(index / 10) * 0.000_1
                ),
                bearing: 0
            )
        }
        let selected = TrainState(
            id: UUID(),
            lineID: lineID,
            coordinate: CLLocationCoordinate2D(latitude: 57.15, longitude: -2.10),
            bearing: 0
        )

        let rendered = RailwayMapRenderingPolicy.renderedTrains(
            from: nearby + [selected],
            selectedTrainID: selected.id,
            visibleMapRect: mapRect(around: centre, halfSize: 30_000),
            maximumCount: 12
        )

        #expect(rendered.count == 13)
        #expect(rendered.last?.id == selected.id)
    }

    @Test("Polyline intersection rejects distant routes")
    func polylineVisibility() {
        let london = CLLocationCoordinate2D(latitude: 51.50, longitude: -0.12)
        let nearbyRoute = [
            CLLocationCoordinate2D(latitude: 51.49, longitude: -0.13),
            CLLocationCoordinate2D(latitude: 51.51, longitude: -0.11),
        ]
        let scotlandRoute = [
            CLLocationCoordinate2D(latitude: 55.85, longitude: -4.26),
            CLLocationCoordinate2D(latitude: 55.95, longitude: -3.19),
        ]
        let viewport = mapRect(around: london, halfSize: 30_000)

        #expect(RailwayMapRenderingPolicy.polyline(nearbyRoute, intersects: viewport))
        #expect(!RailwayMapRenderingPolicy.polyline(scotlandRoute, intersects: viewport))
    }

    @Test("Camera distance selects stable rendering tiers")
    func renderingTiers() {
        #expect(RailwayMapRenderingDetailLevel(cameraDistanceMetres: 20_000) == .local)
        #expect(RailwayMapRenderingDetailLevel(cameraDistanceMetres: 120_000) == .regional)
        #expect(RailwayMapRenderingDetailLevel(cameraDistanceMetres: 800_000) == .country)
        #expect(RailwayMapRenderingDetailLevel(cameraDistanceMetres: .nan) == .country)
    }

    @Test("Small camera-follow movements reuse the padded station set")
    func stationRefreshHysteresis() {
        let centre = CLLocationCoordinate2D(latitude: 51.50, longitude: -0.12)
        let previous = mapRect(around: centre, halfSize: 30_000)
        let smallMove = MKMapRect(
            x: previous.origin.x + previous.width * 0.05,
            y: previous.origin.y + previous.height * 0.05,
            width: previous.width,
            height: previous.height
        )
        let materialMove = MKMapRect(
            x: previous.origin.x + previous.width * 0.3,
            y: previous.origin.y,
            width: previous.width,
            height: previous.height
        )

        #expect(!RailwayMapRenderingPolicy.viewportRequiresStationRefresh(
            previous: previous,
            current: smallMove
        ))
        #expect(RailwayMapRenderingPolicy.viewportRequiresStationRefresh(
            previous: previous,
            current: materialMove
        ))
        #expect(RailwayMapRenderingPolicy.viewportRequiresStationRefresh(
            previous: nil,
            current: previous
        ))
    }

    @Test("Station targets remain accessible and favour the active build action")
    func stationInteractionTargets() {
        for detailLevel in RailwayMapRenderingDetailLevel.allCases {
            let selectionDiameter = StationMapInteractionPolicy.targetDiameter(
                detailLevel: detailLevel,
                isSelectionCandidate: true
            )
            let inspectionDiameter = StationMapInteractionPolicy.targetDiameter(
                detailLevel: detailLevel,
                isSelectionCandidate: false
            )

            #expect(selectionDiameter >= StationMapInteractionPolicy.minimumTargetDiameter)
            #expect(inspectionDiameter >= StationMapInteractionPolicy.minimumTargetDiameter)
            #expect(selectionDiameter > inspectionDiameter)
        }

        #expect(
            StationMapInteractionPolicy.targetDiameter(
                detailLevel: .local,
                isSelectionCandidate: true
            ) > StationMapInteractionPolicy.targetDiameter(
                detailLevel: .country,
                isSelectionCandidate: true
            )
        )
    }

    @Test("An unserved station on a completed conventional corridor is offered as an intermediate call")
    func potentialIntermediateStationIsIncluded() {
        let fixture = intermediateStationFixture()
        let lineID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let line = intermediateStationLine(
            id: lineID,
            origin: fixture.origin,
            destination: fixture.destination,
            route: fixture.route
        )

        let candidates = RailwayMapRenderingPolicy.potentialIntermediateLineIDs(
            for: [fixture.intermediate, fixture.offRoute, fixture.origin],
            among: [line],
            maximumServiceCallCount: 8
        )

        #expect(candidates[fixture.intermediate.crs] == [lineID])
        #expect(candidates[fixture.offRoute.crs] == nil)
        #expect(candidates[fixture.origin.crs] == nil)
    }

    @Test("A station already built elsewhere keeps its station-inspection action")
    func builtStationIsNotOfferedByMapShortcut() {
        let fixture = intermediateStationFixture()
        let candidateLine = intermediateStationLine(
            id: UUID(uuidString: "11000000-0000-0000-0000-000000000001")!,
            origin: fixture.origin,
            destination: fixture.destination,
            route: fixture.route
        )
        let otherDestination = Station(
            crs: "OTH",
            name: "Other",
            latitude: fixture.intermediate.latitude + 0.01,
            longitude: fixture.intermediate.longitude
        )
        let existingLine = intermediateStationLine(
            id: UUID(uuidString: "11000000-0000-0000-0000-000000000002")!,
            origin: fixture.intermediate,
            destination: otherDestination,
            route: ServiceRailwayRoute(coordinates: [
                fixture.intermediate.coordinate,
                otherDestination.coordinate,
            ])
        )

        let candidates = RailwayMapRenderingPolicy.potentialIntermediateLineIDs(
            for: [fixture.intermediate],
            among: [candidateLine, existingLine],
            maximumServiceCallCount: 8
        )

        #expect(candidates[fixture.intermediate.crs] == nil)
    }

    @Test("Ineligible service shapes are not offered for an intermediate station")
    func ineligibleIntermediateStationLinesAreExcluded() {
        let fixture = intermediateStationFixture()
        let constructing = intermediateStationLine(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            origin: fixture.origin,
            destination: fixture.destination,
            route: fixture.route,
            constructionProgress: 0.75
        )
        let highSpeed = intermediateStationLine(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
            origin: fixture.origin,
            destination: fixture.destination,
            route: fixture.route,
            railwayClass: .highSpeed
        )
        let joined = intermediateStationLine(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000003")!,
            origin: fixture.origin,
            destination: fixture.destination,
            route: fixture.route,
            corridorIDs: [
                UUID(uuidString: "21000000-0000-0000-0000-000000000001")!,
                UUID(uuidString: "21000000-0000-0000-0000-000000000002")!,
            ]
        )
        let full = intermediateStationLine(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000004")!,
            origin: fixture.origin,
            destination: fixture.destination,
            route: fixture.route,
            stationCRSs: [fixture.origin.crs, "ZZZ", fixture.destination.crs]
        )

        let candidates = RailwayMapRenderingPolicy.potentialIntermediateLineIDs(
            for: [fixture.intermediate],
            among: [constructing, highSpeed, joined, full],
            maximumServiceCallCount: 3
        )

        #expect(candidates.isEmpty)
    }

    @Test("Intermediate-station service choices have deterministic display order")
    func potentialIntermediateLineOrderingIsDeterministic() {
        let fixture = intermediateStationFixture()
        let firstID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
        let thirdID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
        let fourthID = UUID(uuidString: "30000000-0000-0000-0000-000000000004")!
        let lines = [
            intermediateStationLine(
                id: fourthID,
                name: "Alpha",
                styleIndex: 1,
                origin: fixture.origin,
                destination: fixture.destination,
                route: fixture.route
            ),
            intermediateStationLine(
                id: thirdID,
                name: "Zulu",
                styleIndex: 0,
                origin: fixture.origin,
                destination: fixture.destination,
                route: fixture.route
            ),
            intermediateStationLine(
                id: secondID,
                name: "Alpha",
                styleIndex: 0,
                origin: fixture.origin,
                destination: fixture.destination,
                route: fixture.route
            ),
            intermediateStationLine(
                id: firstID,
                name: "Alpha",
                styleIndex: 0,
                origin: fixture.origin,
                destination: fixture.destination,
                route: fixture.route
            ),
        ]

        let candidates = RailwayMapRenderingPolicy.potentialIntermediateLineIDs(
            for: [fixture.intermediate],
            among: lines,
            maximumServiceCallCount: 8
        )

        #expect(candidates[fixture.intermediate.crs] == [firstID, secondID, thirdID, fourthID])
    }

    @Test("Overlapping station targets select the closest marker")
    func nearestStationHitTarget() {
        let candidates = [
            StationMapHitCandidate(point: CGPoint(x: 100, y: 100), targetDiameter: 72),
            StationMapHitCandidate(point: CGPoint(x: 124, y: 100), targetDiameter: 72),
            StationMapHitCandidate(point: CGPoint(x: 260, y: 260), targetDiameter: 72),
        ]

        #expect(
            StationMapInteractionPolicy.nearestCandidateIndex(
                to: CGPoint(x: 119, y: 101),
                candidates: candidates
            ) == 1
        )
        #expect(
            StationMapInteractionPolicy.nearestCandidateIndex(
                to: CGPoint(x: 180, y: 180),
                candidates: candidates
            ) == nil
        )
    }

    @Test("Restored-network framing reuses bounded country geometry")
    @MainActor
    func restoredNetworkFramingIsBounded() {
        let coordinates = (0..<20_000).map { index in
            CLLocationCoordinate2D(
                latitude: 50 + Double(index) * 0.000_02,
                longitude: -5 + sin(Double(index) / 30) * 0.08
            )
        }
        let origin = Station(crs: "PNZ", name: "Penzance", latitude: 50, longitude: -5)
        let destinationCoordinate = coordinates.last!
        let destination = Station(
            crs: "ABD",
            name: "Aberdeen",
            latitude: destinationCoordinate.latitude,
            longitude: destinationCoordinate.longitude
        )
        let route = ServiceRailwayRoute(coordinates: coordinates)
        let line = BuiltLine(
            id: UUID(),
            name: "Penzance – Aberdeen",
            origin: origin,
            destination: destination,
            route: route,
            distanceMetres: route.totalLength,
            indicativeCost: 1_000_000,
            styleIndex: 0,
            railwayClass: .conventional,
            servicePattern: .express,
            serviceFrequency: .hourly,
            ownedTrainCount: 1,
            constructionProgress: 1,
            trains: []
        )
        let expectedCoordinates = RailwayMapRenderingPolicy.simplifiedCoordinates(
            coordinates,
            maximumPointCount: RailwayMapRenderingDetailLevel.country.maximumRoutePointCount
        )
        let expected = RailwayMapRenderingPolicy.mapRect(containing: expectedCoordinates)
        let cache = RailwayMapRenderingCache()

        let first = cache.framingMapRect(for: line)
        let second = cache.framingMapRect(for: line)

        #expect(first.origin.x == expected.origin.x)
        #expect(first.origin.y == expected.origin.y)
        #expect(first.width == expected.width)
        #expect(first.height == expected.height)
        #expect(second.origin.x == first.origin.x)
        #expect(second.origin.y == first.origin.y)
        #expect(second.width == first.width)
        #expect(second.height == first.height)
        #expect(first.contains(MKMapPoint(coordinates.first!)))
        #expect(first.contains(MKMapPoint(coordinates.last!)))
    }

    private func mapRect(
        around coordinate: CLLocationCoordinate2D,
        halfSize: Double
    ) -> MKMapRect {
        let centre = MKMapPoint(coordinate)
        return MKMapRect(
            x: centre.x - halfSize,
            y: centre.y - halfSize,
            width: halfSize * 2,
            height: halfSize * 2
        )
    }

    private func intermediateStationFixture() -> (
        origin: Station,
        intermediate: Station,
        destination: Station,
        offRoute: Station,
        route: ServiceRailwayRoute
    ) {
        let origin = Station(
            crs: "ECR",
            name: "East Croydon",
            latitude: 51.3753,
            longitude: -0.0928
        )
        let intermediate = Station(
            crs: "SCY",
            name: "South Croydon",
            latitude: 51.3628,
            longitude: -0.0938
        )
        let destination = Station(
            crs: "PUR",
            name: "Purley",
            latitude: 51.3376,
            longitude: -0.1140
        )
        let offRoute = Station(
            crs: "OFF",
            name: "Off Route",
            latitude: intermediate.latitude,
            longitude: intermediate.longitude + 0.02
        )
        return (
            origin,
            intermediate,
            destination,
            offRoute,
            ServiceRailwayRoute(coordinates: [
                origin.coordinate,
                intermediate.coordinate,
                destination.coordinate,
            ])
        )
    }

    private func intermediateStationLine(
        id: UUID,
        name: String = "Test line",
        styleIndex: Int = 0,
        origin: Station,
        destination: Station,
        route: ServiceRailwayRoute,
        constructionProgress: Double = 1,
        railwayClass: RailwayClass = .conventional,
        corridorIDs: [UUID]? = nil,
        stationCRSs: [String]? = nil
    ) -> BuiltLine {
        BuiltLine(
            id: id,
            name: name,
            origin: origin,
            destination: destination,
            route: route,
            distanceMetres: route.totalLength,
            indicativeCost: 1_000_000,
            styleIndex: styleIndex,
            railwayClass: railwayClass,
            serviceFrequency: .hourly,
            ownedTrainCount: 1,
            constructionProgress: constructionProgress,
            trains: [],
            corridorIDs: corridorIDs,
            stationCRSs: stationCRSs
        )
    }
}
