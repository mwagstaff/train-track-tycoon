import CoreLocation
import Testing
@testable import TrainTrackTycoon

@Suite("Milestone 17 national-scale simulation scope", .serialized)
@MainActor
struct M17NationalScaleTests {
    @Test("A national catalogue simulates only the railway the player has built")
    func nationalCatalogueUsesBuiltNetworkScope() async throws {
        let stations = makeStations(count: 300)
        let session = GameSession(
            stations: stations,
            routingProvider: M17NationalRoutingProvider(),
            gameMode: .zen,
            clock: M17NationalClock(),
            configuration: GameConfiguration(
                maximumLineCount: 64,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 40,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000,
                maximumServiceCallCount: 64,
                maximumGloballySimulatedCatalogueStationCount: 256
            )
        )

        #expect(session.happinessSnapshot.stationsByCRS.isEmpty)
        #expect(session.settlementPopulationByCRS.isEmpty)

        session.startBuilding()
        session.selectStation(stations[0])
        session.selectStation(stations[1])
        await session.waitForRouteCalculation()
        #expect(session.phase == .preview)
        session.confirmPreview()

        #expect(session.happinessSnapshot(forStationCRS: stations[0].crs) != nil)
        #expect(session.happinessSnapshot(forStationCRS: stations[1].crs) != nil)
        #expect(session.happinessSnapshot(forStationCRS: stations[299].crs) == nil)
        #expect(Set(session.settlementPopulationByCRS.keys) == [
            stations[0].crs,
            stations[1].crs,
        ])
    }

    @Test("Compact fixtures retain full-catalogue happiness behavior")
    func compactCatalogueRemainsFullySimulated() {
        let stations = makeStations(count: 3)
        let session = GameSession(
            stations: stations,
            routingProvider: M17NationalRoutingProvider(),
            gameMode: .zen,
            clock: M17NationalClock(),
            configuration: GameConfiguration(
                maximumLineCount: 4,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 40,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000
            )
        )

        #expect(stations.allSatisfy {
            session.happinessSnapshot(forStationCRS: $0.crs) != nil
        })
    }

    private func makeStations(count: Int) -> [Station] {
        (0..<count).map { index in
            Station(
                crs: String(format: "S%03d", index),
                name: "Scale Station \(index)",
                latitude: 50 + Double(index) * 0.001,
                longitude: -1
            )
        }
    }
}

private nonisolated struct M17NationalRoutingProvider: RailwayRouteProviding {
    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        let coordinates = stationCRSs.indices.map { index in
            CLLocationCoordinate2D(
                latitude: 50 + Double(index) * 0.01,
                longitude: -1
            )
        }
        return ServiceRailwayRoute(
            coordinates: coordinates,
            cumulativeDistances: stationCRSs.indices.map { Double($0) * 1_000 },
            stationCoordinateIndices: Array(stationCRSs.indices)
        )
    }
}

@MainActor
private final class M17NationalClock: SimulationClock {
    func start(tick: @escaping @MainActor (TimeInterval) -> Void) {}
    func stop() {}
}
