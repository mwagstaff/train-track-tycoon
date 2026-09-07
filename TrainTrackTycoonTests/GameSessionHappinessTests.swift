import CoreLocation
import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Game session happiness", .serialized)
@MainActor
struct GameSessionHappinessTests {
    @Test("Initial and reset snapshots include every catalogue station")
    func catalogueWideZeroStateSurvivesReset() async throws {
        let session = makeSession()

        #expect(session.happinessSnapshot.globalHappinessScore == 0)
        for station in stations {
            let local = try #require(session.happinessSnapshot(forStationCRS: station.crs))
            #expect(local.happinessScore == 0)
        }
        #expect(session.happinessSnapshot != .empty)

        await createAndConfirmLine(in: session)
        #expect(session.happinessSnapshot != .empty)
        session.reset()

        #expect(session.lines.isEmpty)
        #expect(session.happinessSnapshot.globalHappinessScore == 0)
        for station in stations {
            let local = try #require(session.happinessSnapshot(forStationCRS: station.crs))
            #expect(local.happinessScore == 0)
        }
        #expect(session.happinessSnapshot != .empty)
    }

    @Test("An unconnected catalogue station can be inspected")
    func unconnectedStationInspection() async throws {
        let session = makeSession()
        await createAndConfirmLine(in: session)

        session.selectStationForInspection(unconnectedStation.crs.lowercased())

        #expect(session.selectedStation?.crs == unconnectedStation.crs)
        let happiness = try #require(
            session.happinessSnapshot(forStationCRS: unconnectedStation.crs)
        )
        #expect(happiness.happinessScore == 0)
        #expect(session.passengerSnapshot(forStationCRS: unconnectedStation.crs) == nil)
    }

    @Test("Opening a line and changing its frequency recompute happiness")
    func serviceChangesRecomputeHappiness() async throws {
        let session = makeSession()
        let initial = session.happinessSnapshot

        await createAndConfirmLine(in: session)
        let opened = session.happinessSnapshot
        #expect(opened != initial)

        let lineID = try #require(session.lines.first?.id)
        session.setServiceFrequency(.quarterHourly, forLineID: lineID)

        #expect(session.happinessSnapshot != opened)
    }

    @Test("Train animation alone leaves the derived happiness snapshot unchanged")
    func trainAnimationDoesNotRecomputeHappiness() async {
        let clock = HappinessManualClock()
        let session = makeSession(clock: clock)
        await createAndConfirmLine(in: session)
        let beforeTick = session.happinessSnapshot

        clock.advance(by: 1)

        #expect(session.happinessSnapshot == beforeTick)
    }

    @Test("Happiness is derived consistently after save restoration")
    func restoreRecreatesHappiness() async throws {
        let source = makeSession()
        await createAndConfirmLine(in: source)
        let lineID = try #require(source.lines.first?.id)
        source.setServiceFrequency(.quarterHourly, forLineID: lineID)

        let save = source.makeSaveSnapshot()
        let sourceHappiness = source.happinessSnapshot
        let restored = makeSession()
        try await restored.restore(from: save)

        #expect(restored.happinessSnapshot == sourceHappiness)
        for station in stations {
            _ = try #require(restored.happinessSnapshot(forStationCRS: station.crs))
        }
    }

    private var origin: Station {
        Station(
            crs: "VIC",
            name: "London Victoria",
            latitude: 51.4952,
            longitude: -0.1441
        )
    }

    private var destination: Station {
        Station(
            crs: "ECR",
            name: "East Croydon",
            latitude: 51.3752,
            longitude: -0.0923
        )
    }

    private var unconnectedStation: Station {
        Station(
            crs: "SRS",
            name: "Selhurst",
            latitude: 51.3920,
            longitude: -0.0887
        )
    }

    private var stations: [Station] {
        [origin, destination, unconnectedStation]
    }

    private func makeSession(
        clock: HappinessManualClock? = nil
    ) -> GameSession {
        let clock = clock ?? HappinessManualClock()
        let route = ServiceRailwayRoute(
            coordinates: [origin.coordinate, destination.coordinate],
            cumulativeDistances: [0, 10_000],
            stationCoordinateIndices: [0, 1]
        )
        return GameSession(
            stations: stations,
            routingProvider: HappinessRoutingProvider(route: route),
            clock: clock,
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 50,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000,
                operatingDayDuration: 30
            )
        )
    }

    private func createAndConfirmLine(in session: GameSession) async {
        session.startBuilding()
        session.selectStation(origin)
        session.selectStation(destination)
        await session.waitForRouteCalculation()
        #expect(session.phase == .preview)
        session.confirmPreview()
        #expect(session.phase == .operating)
    }
}

private nonisolated struct HappinessRoutingProvider: RailwayRouteProviding {
    let route: ServiceRailwayRoute

    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        route
    }
}

@MainActor
private final class HappinessManualClock: SimulationClock {
    private var tickHandler: (@MainActor (TimeInterval) -> Void)?

    func start(tick: @escaping @MainActor (TimeInterval) -> Void) {
        tickHandler = tick
    }

    func stop() {
        tickHandler = nil
    }

    func advance(by delta: TimeInterval) {
        tickHandler?(delta)
    }
}
