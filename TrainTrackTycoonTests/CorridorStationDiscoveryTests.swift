import CoreLocation
import Testing
@testable import TrainTrackTycoon

@Suite(.serialized)
struct CorridorStationDiscoveryTests {
    @Test func routeProjectionReportsDistanceProgressVertexAndOffset() throws {
        let route = ServiceRailwayRoute(
            coordinates: [
                CLLocationCoordinate2D(latitude: 51, longitude: 0),
                CLLocationCoordinate2D(latitude: 51, longitude: 0.01),
                CLLocationCoordinate2D(latitude: 51, longitude: 0.02),
            ]
        )

        let projection = try #require(route.projection(closestTo: CLLocationCoordinate2D(
            latitude: 51.0005,
            longitude: 0.012
        )))

        #expect((0.55...0.65).contains(projection.routeProgress))
        #expect(projection.routeCoordinateIndex == 1)
        #expect((50...60).contains(projection.offsetFromRoute))
        #expect((0.0119...0.0121).contains(projection.coordinate.longitude))
    }

    @Test func fallbackDiscoveryOrdersStationsAndExcludesEndpointsAndImplausibleCandidates() {
        let route = eastboundFixtureRoute
        let stations = [
            station("END", longitude: 0),
            station("TWO", longitude: 0.02),
            station("FAR", latitude: 51.01, longitude: 0.015),
            station("ONE", latitude: 51.0005, longitude: 0.01),
            station("DST", longitude: 0.03),
            // A duplicate CRS cannot create a duplicate calling point.
            station("ONE", longitude: 0.011),
        ]

        let matches = CorridorStationDiscovery.discover(
            on: route,
            endpointCRSs: [" end ", "dst"],
            catalogStations: stations
        )

        #expect(matches.map(\.station.crs) == ["ONE", "TWO"])
        #expect(matches.map(\.routeProgress) == matches.map(\.routeProgress).sorted())
        #expect(matches.allSatisfy { (0..<route.coordinates.count).contains($0.routeCoordinateIndex) })
    }

    @Test func graphAnchorsAdmitPlatformCentresButRejectNearbyBranches() {
        let route = eastboundFixtureRoute
        let platformCentre = station("ONR", latitude: 51.0027, longitude: 0.01)
        let nearbyBranch = station("OFF", latitude: 51.0005, longitude: 0.02)
        let anchors = [
            "ONR": [CorridorStationAnchor(
                coordinate: CLLocationCoordinate2D(latitude: 51, longitude: 0.01),
                stationOffset: 300,
                stableIndex: 0
            )],
            "OFF": [CorridorStationAnchor(
                coordinate: CLLocationCoordinate2D(latitude: 51.005, longitude: 0.02),
                stationOffset: 20,
                stableIndex: 0
            )],
        ]

        let matches = CorridorStationDiscovery.discover(
            on: route,
            endpointCRSs: ["END", "DST"],
            catalogStations: [nearbyBranch, platformCentre],
            anchorsByCRS: anchors
        )

        #expect(matches.map(\.station.crs) == ["ONR"])
        #expect((290...310).contains(matches[0].offsetFromRoute))
    }

    @Test func resultCountIsBoundedAfterRouteOrdering() {
        let route = eastboundFixtureRoute
        let configuration = CorridorStationDiscoveryConfiguration(
            maximumStationOffsetFromRoute: 400,
            maximumAnchorOffsetFromRoute: 40,
            maximumFallbackOffsetFromRoute: 180,
            endpointClearance: 100,
            maximumIntermediateStationCount: 2
        )
        let matches = CorridorStationDiscovery.discover(
            on: route,
            endpointCRSs: ["END", "DST"],
            catalogStations: [
                station("C", longitude: 0.025),
                station("A", longitude: 0.005),
                station("B", longitude: 0.015),
            ],
            configuration: configuration
        )

        #expect(matches.map(\.station.crs) == ["A", "B"])
    }

    @Test func victoriaToKentHouseFindsRealStationsInCorridorOrderWithoutChangingRoute() async throws {
        let catalog = try StationCatalog(bundle: .main)
        let routing = RailwayRoutingService(bundle: .main)
        let route = try await routing.route(forStationCRSs: ["VIC", "KTH"])
        let originalCoordinates = route.coordinates
        let originalStationIndices = route.stationCoordinateIndices

        let matches = try await routing.discoverIntermediateStations(
            on: route,
            endpointCRSs: ["VIC", "KTH"],
            catalogStations: catalog.allStations
        )
        let crss = matches.map(\.station.crs)
        #expect(crss == ["WWR", "CLP", "BRX", "HNH", "WDU", "SYH", "PNE"])

        #expect(route.stationCount == 2)
        #expect(route.stationCoordinateIndices == originalStationIndices)
        #expect(coordinatesEqual(route.coordinates, originalCoordinates))
        #expect(!crss.contains("VIC"))
        #expect(!crss.contains("KTH"))
        #expect(crss.contains("BRX"))
        #expect(crss.contains("HNH"))
        let brixtonIndex = try #require(crss.firstIndex(of: "BRX"))
        let herneHillIndex = try #require(crss.firstIndex(of: "HNH"))
        #expect(brixtonIndex < herneHillIndex)
        #expect(matches.map(\.routeDistance) == matches.map(\.routeDistance).sorted())
    }

    @Test func playableCatalogSupportsVictoriaToKentHouseMilestoneRoute() async throws {
        let catalog = try StationCatalog(bundle: .main)
        let playableCRSs = Set(catalog.curatedStations.map(\.crs))
        #expect(["VIC", "BRX", "HNH", "KTH"].allSatisfy(playableCRSs.contains))

        let routing = RailwayRoutingService(bundle: .main)
        let route = try await routing.route(forStationCRSs: ["VIC", "KTH"])
        let matches = try await routing.discoverIntermediateStations(
            on: route,
            endpointCRSs: ["VIC", "KTH"],
            catalogStations: catalog.curatedStations
        )

        #expect(matches.map(\.station.crs) == ["BRX", "HNH"])
    }

    @Test func eastCroydonToPurleyDiscoversSouthCroydonAsAnIntermediateStation() async throws {
        let catalog = try StationCatalog(bundle: .main)
        let southCroydon = try #require(catalog["SCY"])
        #expect(southCroydon.name == "South Croydon")

        let routing = RailwayRoutingService(bundle: .main)
        let route = try await routing.route(forStationCRSs: ["ECR", "PUR"])
        let matches = try await routing.discoverIntermediateStations(
            on: route,
            endpointCRSs: ["ECR", "PUR"],
            catalogStations: [southCroydon]
        )

        let match = try #require(matches.first)
        #expect(matches.count == 1)
        #expect(match.station.crs == "SCY")
        #expect((0..<route.totalLength).contains(match.routeDistance))
        #expect((0..<1).contains(match.routeProgress))
        #expect((0..<route.coordinates.count).contains(match.routeCoordinateIndex))
    }

    @Test func reverseRouteProducesTheReverseIntermediateOrder() async throws {
        let catalog = try StationCatalog(bundle: .main)
        let routing = RailwayRoutingService(bundle: .main)
        let forwardRoute = try await routing.route(forStationCRSs: ["VIC", "KTH"])
        let reverseRoute = try await routing.route(forStationCRSs: ["KTH", "VIC"])
        let forward = try await routing.discoverIntermediateStations(
            on: forwardRoute,
            endpointCRSs: ["VIC", "KTH"],
            catalogStations: catalog.allStations
        )
        let reverse = try await routing.discoverIntermediateStations(
            on: reverseRoute,
            endpointCRSs: ["KTH", "VIC"],
            catalogStations: catalog.allStations
        )

        #expect(reverse.map(\.station.crs) == Array(forward.map(\.station.crs).reversed()))
    }

    private var eastboundFixtureRoute: ServiceRailwayRoute {
        ServiceRailwayRoute(coordinates: [
            CLLocationCoordinate2D(latitude: 51, longitude: 0),
            CLLocationCoordinate2D(latitude: 51, longitude: 0.01),
            CLLocationCoordinate2D(latitude: 51, longitude: 0.02),
            CLLocationCoordinate2D(latitude: 51, longitude: 0.03),
        ])
    }

    private func station(
        _ crs: String,
        latitude: Double = 51,
        longitude: Double
    ) -> Station {
        Station(
            crs: crs,
            name: "Station \(crs)",
            latitude: latitude,
            longitude: longitude
        )
    }

    private func coordinatesEqual(
        _ lhs: [CLLocationCoordinate2D],
        _ rhs: [CLLocationCoordinate2D]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy {
            $0.latitude == $1.latitude && $0.longitude == $1.longitude
        }
    }
}
