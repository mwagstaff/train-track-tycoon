import CoreLocation
import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("M13 scalable game session", .serialized)
@MainActor
struct M13GameSessionIntegrationTests {
    @Test("Twelve services build, simulate, save and restore with stable corridor identities")
    func twelveServiceRoundTrip() async throws {
        let stations = makeStations(count: 13)
        let routing = M13RoutingProvider(stations: stations)
        let session = makeSession(stations: stations, routing: routing)

        for index in 0..<12 {
            await buildLine(
                in: session,
                origin: stations[index],
                destination: stations[index + 1]
            )
        }

        #expect(session.lines.count == 12)
        #expect(session.corridors.count == 12)
        #expect(session.lines.map(\.styleIndex) == Array(0..<12))
        #expect(Set(session.lines.map(\.serviceID)).count == 12)
        #expect(Set(session.corridors.map(\.id)).count == 12)
        #expect(session.lines.allSatisfy {
            $0.corridorIDs.count == 1
                && $0.stationCRSs == [$0.origin.crs, $0.destination.crs]
        })
        #expect(session.passengerSnapshot.lineSnapshots.count == 12)
        #expect(session.passengerSnapshot.connectingJourneySnapshots.count == 11)
        #expect(!session.canBuildAnotherLine)

        session.startBuilding()
        #expect(session.phase == .error)
        #expect(session.errorMessage?.contains("up to 12 lines") == true)
        session.dismissError()

        let snapshot = session.makeSaveSnapshot()
        #expect(snapshot.schemaVersion == 12)
        #expect(snapshot.lines.count == 12)
        #expect(snapshot.corridors.count == 12)
        #expect(Set(snapshot.lines.flatMap(\.corridorIDs)) == Set(snapshot.corridors.map(\.id)))

        let restored = makeSession(stations: stations, routing: routing)
        try await restored.restore(from: snapshot)

        #expect(restored.lines.map(\.id) == session.lines.map(\.id))
        #expect(restored.lines.map(\.corridorIDs) == session.lines.map(\.corridorIDs))
        #expect(restored.lines.map(\.stationCRSs) == session.lines.map(\.stationCRSs))
        #expect(restored.lines.map(\.styleIndex) == Array(0..<12))
        #expect(restored.corridors.map(\.id) == session.corridors.map(\.id))
        #expect(restored.passengerSnapshot == session.passengerSnapshot)
        #expect(!restored.canBuildAnotherLine)
    }

    private func makeStations(count: Int) -> [Station] {
        (0..<count).map { index in
            Station(
                crs: String(format: "S%02d", index),
                name: "Station \(index + 1)",
                latitude: 50.8 + Double(index) * 0.015,
                longitude: -0.20 + Double(index) * 0.012
            )
        }
    }

    private func makeSession(
        stations: [Station],
        routing: M13RoutingProvider
    ) -> GameSession {
        GameSession(
            stations: stations,
            routingProvider: routing,
            stationCapacitySimulation: StationCapacitySimulation(
                configuration: StationCapacityConfiguration(
                    trainCallsPerPlatformPerHour: 1_000_000
                )
            ),
            clock: M13ManualSimulationClock(),
            configuration: GameConfiguration(
                maximumLineCount: 12,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 45,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000
            )
        )
    }

    private func buildLine(
        in session: GameSession,
        origin: Station,
        destination: Station
    ) async {
        session.startBuilding()
        session.selectStation(origin)
        session.selectStation(destination)
        await session.waitForRouteCalculation()
        #expect(session.phase == .preview)
        session.confirmPreview()
        #expect(session.phase == .operating)
    }
}

private nonisolated struct M13RoutingProvider: RailwayRouteProviding {
    let coordinatesByCRS: [String: CLLocationCoordinate2D]

    init(stations: [Station]) {
        coordinatesByCRS = Dictionary(
            uniqueKeysWithValues: stations.map { ($0.crs, $0.coordinate) }
        )
    }

    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        let coordinates = try stationCRSs.map { crs in
            guard let coordinate = coordinatesByCRS[crs] else {
                throw M13RoutingError.missingStation(crs)
            }
            return coordinate
        }
        guard coordinates.count >= 2 else { throw M13RoutingError.tooFewStations }

        return ServiceRailwayRoute(
            coordinates: coordinates,
            cumulativeDistances: coordinates.indices.map { Double($0) * 1_000 },
            stationCoordinateIndices: Array(coordinates.indices)
        )
    }
}

private nonisolated enum M13RoutingError: Error {
    case missingStation(String)
    case tooFewStations
}

@MainActor
private final class M13ManualSimulationClock: SimulationClock {
    func start(tick: @escaping @MainActor (TimeInterval) -> Void) {}
    func stop() {}
    func setSuspended(_ isSuspended: Bool) {}
}
