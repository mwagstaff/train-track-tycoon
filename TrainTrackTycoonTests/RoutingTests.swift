import CoreLocation
import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite(.serialized)
struct RoutingTests {
    @Test func routeSamplingInterpolatesCoordinatesAndBearings() throws {
        let route = ServiceRailwayRoute(
            coordinates: [
                CLLocationCoordinate2D(latitude: 0, longitude: 0),
                CLLocationCoordinate2D(latitude: 0, longitude: 0.001),
                CLLocationCoordinate2D(latitude: 0.001, longitude: 0.001),
            ],
            cumulativeDistances: [0, 100, 200],
            stationCoordinateIndices: [0, 2]
        )

        let eastbound = try #require(route.sample(atDistance: 50))
        #expect(abs(eastbound.coordinate.latitude) < 0.000_001)
        #expect(abs(eastbound.coordinate.longitude - 0.000_5) < 0.000_001)
        #expect(approximately(eastbound.bearing, 90, tolerance: 0.1))

        let northbound = try #require(route.sample(atDistance: 150))
        #expect(abs(northbound.coordinate.latitude - 0.000_5) < 0.000_001)
        #expect(abs(northbound.coordinate.longitude - 0.001) < 0.000_001)
        #expect(approximately(northbound.bearing, 0, tolerance: 0.1))
    }

    @Test func reverseSamplingStartsAtTheFarTerminalAndReversesBearing() throws {
        let route = ServiceRailwayRoute(
            coordinates: [
                CLLocationCoordinate2D(latitude: 0, longitude: 0),
                CLLocationCoordinate2D(latitude: 0, longitude: 0.001),
                CLLocationCoordinate2D(latitude: 0.001, longitude: 0.001),
            ],
            cumulativeDistances: [0, 100, 200],
            stationCoordinateIndices: [0, 2]
        )

        let terminal = try #require(route.sample(atDistance: 0, direction: .reverse))
        #expect(abs(terminal.coordinate.latitude - 0.001) < 0.000_001)
        #expect(abs(terminal.coordinate.longitude - 0.001) < 0.000_001)
        #expect(approximately(terminal.bearing, 180, tolerance: 0.1))

        let halfwayBack = try #require(route.sample(atDistance: 150, direction: .reverse))
        #expect(abs(halfwayBack.coordinate.latitude) < 0.000_001)
        #expect(abs(halfwayBack.coordinate.longitude - 0.000_5) < 0.000_001)
        #expect(approximately(halfwayBack.bearing, 270, tolerance: 0.1))
    }

    @Test func constructionRevealIncludesAnInterpolatedEndpoint() throws {
        let route = ServiceRailwayRoute(
            coordinates: [
                CLLocationCoordinate2D(latitude: 0, longitude: 0),
                CLLocationCoordinate2D(latitude: 0, longitude: 0.001),
                CLLocationCoordinate2D(latitude: 0.001, longitude: 0.001),
            ],
            cumulativeDistances: [0, 100, 200],
            stationCoordinateIndices: [0, 2]
        )

        let forward = route.coordinates(upToDistance: 150)
        #expect(forward.count == 3)
        #expect(abs(try #require(forward.last).latitude - 0.000_5) < 0.000_001)

        let reverse = route.coordinates(upToDistance: 50, direction: .reverse)
        #expect(reverse.count == 2)
        #expect(abs(try #require(reverse.last).latitude - 0.000_5) < 0.000_001)
        #expect(abs(try #require(reverse.last).longitude - 0.001) < 0.000_001)

        #expect(route.sample(atDistance: .nan) == nil)
        #expect(route.coordinates(upToDistance: .infinity).isEmpty)
    }

    @Test func stationCatalogHasStableSouthEastSelectionAndLookup() throws {
        let catalog = try StationCatalog(bundle: .main)

        #expect(catalog.allStations.count == 2_606)
        #expect(Set(catalog.allStations.map(\.crs)).count == catalog.allStations.count)
        #expect(catalog.curatedStations.map(\.crs) == StationCatalog.southEastStationCRSs)
        #expect(catalog.station(forCRS: " btn ")?.name == "Brighton")
        #expect(catalog["VIC"]?.coordinate.latitude ?? 0 > 51)
        #expect(catalog["ABD"] != nil)
        #expect(catalog["EDB"] != nil)
        #expect(catalog["PNZ"] != nil)
    }

    @Test func londonVictoriaToBrightonUsesTheProvenMainlineGeometry() async throws {
        let routing = RailwayRoutingService(bundle: .main)
        try await routing.prepare()
        let route = try await routing.route(forStationCRSs: [
            "VIC", "CLJ", "SRS", "ECR", "PUR", "HOR", "GTW", "TBD", "HHE", "BTN",
        ])

        #expect(route.stationCount == 10)
        #expect((80_000...83_000).contains(route.totalLength))
        #expect(route.coordinates.count > 100)

        let origin = try #require(route.coordinate(atStation: 0))
        let destination = try #require(route.coordinate(atStation: 9))
        let startSample = try #require(route.sample(atDistance: 0))
        let endSample = try #require(route.sample(atDistance: route.totalLength))
        #expect(coordinatesAreClose(origin, startSample.coordinate))
        #expect(coordinatesAreClose(destination, endSample.coordinate))
    }

    @Test func aberdeenToPenzanceCanUseTheBundledNationalRailway() async throws {
        let routing = RailwayRoutingService(bundle: .main)
        let route = try await routing.route(forStationCRSs: ["ABD", "PNZ"])

        #expect(route.stationCount == 2)
        #expect(route.totalLength > 900_000)
        #expect(route.coordinates.count > 1_000)
        #expect(route.coordinate(atStation: 0) != nil)
        #expect(route.coordinate(atStation: 1) != nil)
    }

    @Test func islandLineRemainsAValidSeparateRailwayComponent() async throws {
        let routing = RailwayRoutingService(bundle: .main)
        let islandRoute = try await routing.route(forStationCRSs: ["BDN", "RYD"])
        #expect(islandRoute.totalLength > 1_000)

        do {
            _ = try await routing.route(forStationCRSs: ["RYD", "VIC"])
            Issue.record("Expected the Isle of Wight and mainland graphs to remain disconnected")
        } catch let error as RailwayRoutingError {
            #expect(error == .routeUnavailable("RYD", "VIC"))
        }
    }

    @Test func stationEligibilityUsesGraphComponentsWithoutFindingEveryRoute() async throws {
        let routing = RailwayRoutingService(bundle: .main)
        let candidates: Set<String> = ["VIC", "BTN", "RYD", "BDN", "ZZZ"]

        let validOrigins = try await routing.connectedStationCRSs(
            to: nil,
            among: candidates
        )
        #expect(validOrigins == ["VIC", "BTN", "RYD", "BDN"])

        let mainland = try await routing.connectedStationCRSs(
            to: " vic ",
            among: candidates
        )
        #expect(mainland.contains("BTN"))
        #expect(!mainland.contains("VIC"))
        #expect(!mainland.contains("RYD"))
        #expect(!mainland.contains("BDN"))

        let island = try await routing.connectedStationCRSs(
            to: "RYD",
            among: candidates
        )
        #expect(island == ["BDN"])
        let unavailable = try await routing.connectedStationCRSs(
            to: "ZZZ",
            among: candidates
        )
        #expect(unavailable.isEmpty)
    }

    @Test func directStationEligibilityRejectsASevereNearbyDetour() async throws {
        let routing = RailwayRoutingService(bundle: .main)
        let direct = try await routing.directlyRoutableStationCRSs(
            to: "ECR",
            among: ["WCY", "PUR", "VIC"]
        )

        #expect(!direct.contains("WCY"))
        #expect(direct.contains("PUR"))
        #expect(direct.contains("VIC"))
    }

    @Test func directStationEligibilityPreservesAValidNationalCorridor() async throws {
        let routing = RailwayRoutingService(bundle: .main)
        let direct = try await routing.directlyRoutableStationCRSs(
            to: "ABD",
            among: ["PNZ"]
        )

        #expect(direct == ["PNZ"])
    }

    @Test func directEligibilityAllowsARealCityCentreJunctionApproach() async throws {
        let routing = RailwayRoutingService(bundle: .main)
        let direct = try await routing.directlyRoutableStationCRSs(
            to: "MAN",
            among: ["MCV"]
        )

        #expect(direct == ["MCV"])
    }

    @Test func directEligibilityDoesNotBorrowAnAdjacentTerminalsTracks() async throws {
        let routing = RailwayRoutingService(bundle: .main)

        let londonTerminals = try await routing.directlyRoutableStationCRSs(
            to: "KGX",
            among: ["STP"]
        )
        #expect(!londonTerminals.contains("STP"))
        let londonTerminalRoute = try await routing.route(forStationCRSs: ["KGX", "STP"])
        #expect((2_500...3_200).contains(londonTerminalRoute.totalLength))
    }

    @Test func routingDoesNotSnapEastCroydonOntoWestCroydonTracks() async throws {
        let routing = RailwayRoutingService(bundle: .main)
        let route = try await routing.route(forStationCRSs: ["ECR", "WCY"])

        #expect(route.totalLength > 3_000)
        let catalog = try StationCatalog(bundle: .main)
        let eastCroydon = try #require(catalog["ECR"])
        let westCroydon = try #require(catalog["WCY"])
        let routeOrigin = try #require(route.coordinate(atStation: 0))
        let routeDestination = try #require(route.coordinate(atStation: 1))
        #expect(CLLocation(latitude: routeOrigin.latitude, longitude: routeOrigin.longitude)
            .distance(from: CLLocation(
                latitude: eastCroydon.coordinate.latitude,
                longitude: eastCroydon.coordinate.longitude
            )) < 300)
        #expect(CLLocation(latitude: routeDestination.latitude, longitude: routeDestination.longitude)
            .distance(from: CLLocation(
                latitude: westCroydon.coordinate.latitude,
                longitude: westCroydon.coordinate.longitude
            )) < 300)
    }

    private func approximately(
        _ first: Double,
        _ second: Double,
        tolerance: Double
    ) -> Bool {
        let rawDifference = abs(first - second).truncatingRemainder(dividingBy: 360)
        return min(rawDifference, 360 - rawDifference) <= tolerance
    }

    private func coordinatesAreClose(
        _ first: CLLocationCoordinate2D,
        _ second: CLLocationCoordinate2D
    ) -> Bool {
        abs(first.latitude - second.latitude) < 0.000_001
            && abs(first.longitude - second.longitude) < 0.000_001
    }
}
