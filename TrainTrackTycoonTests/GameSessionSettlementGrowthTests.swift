import CoreLocation
import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Game session settlement growth", .serialized)
@MainActor
struct GameSessionSettlementGrowthTests {
    @Test("Population advances once per operating day and changes the following forecast")
    func dailyGrowthFeedsNextPassengerForecast() async throws {
        let clock = SettlementGrowthManualClock()
        let session = makeSession(clock: clock)
        await createLine(in: session)

        let initialPopulation = session.networkPopulation
        let initialPotential = session.passengerSnapshot.potentialDailyJourneys
        #expect(initialPopulation == 30_000)
        #expect(session.latestNetworkPopulationChange == 0)

        clock.advance(by: 9.9)
        #expect(session.economyLedger.completedOperatingDays == 0)
        #expect(session.networkPopulation == initialPopulation)

        session.togglePlayPause()
        clock.advance(by: 100)
        #expect(session.networkPopulation == initialPopulation)
        session.togglePlayPause()

        clock.advance(by: 0.1)

        #expect(session.economyLedger.completedOperatingDays == 1)
        #expect(session.networkPopulation > initialPopulation)
        #expect(
            session.latestNetworkPopulationChange
                == session.networkPopulation - initialPopulation
        )
        #expect(session.passengerSnapshot.potentialDailyJourneys > initialPotential)

        let history = try #require(session.publicBetaHistory.records.last)
        #expect(history.operatingDay == 1)
        #expect(history.totalNetworkPopulation == session.networkPopulation)
        #expect(history.latestPopulationChange == session.latestNetworkPopulationChange)
    }

    @Test("Tick partitioning and save restoration preserve exact population state")
    func cadenceAndPersistenceAreDeterministic() async throws {
        let coarseClock = SettlementGrowthManualClock()
        let fineClock = SettlementGrowthManualClock()
        let coarse = makeSession(clock: coarseClock)
        let fine = makeSession(clock: fineClock)
        await createLine(in: coarse)
        await createLine(in: fine)

        coarseClock.advance(by: 100)
        for _ in 0..<1_000 {
            fineClock.advance(by: 0.1)
        }

        #expect(coarse.economyLedger.completedOperatingDays == 10)
        #expect(fine.economyLedger.completedOperatingDays == 10)
        #expect(coarse.settlementPopulationByCRS == fine.settlementPopulationByCRS)
        #expect(
            coarse.passengerSnapshot.potentialDailyJourneys
                == fine.passengerSnapshot.potentialDailyJourneys
        )
        #expect(
            coarse.passengerSnapshot.passengersPerDay
                == fine.passengerSnapshot.passengersPerDay
        )
        #expect(
            coarse.passengerSnapshot.unservedDailyJourneys
                == fine.passengerSnapshot.unservedDailyJourneys
        )
        #expect(
            coarse.passengerSnapshot.averagePeakOccupancyRatio
                == fine.passengerSnapshot.averagePeakOccupancyRatio
        )
        #expect(
            coarse.passengerSnapshot.stationsByCRS
                == fine.passengerSnapshot.stationsByCRS
        )
        #expect(coarse.happinessSnapshot == fine.happinessSnapshot)
        #expect(coarse.publicBetaHistory == fine.publicBetaHistory)

        let snapshot = coarse.makeSaveSnapshot()
        #expect(snapshot.stationPopulations.count == 2)
        let restored = makeSession(clock: SettlementGrowthManualClock())
        try await restored.restore(from: snapshot)

        #expect(restored.settlementPopulationByCRS == coarse.settlementPopulationByCRS)
        #expect(restored.networkPopulation == coarse.networkPopulation)
        #expect(
            restored.latestNetworkPopulationChange
                == coarse.latestNetworkPopulationChange
        )
        #expect(restored.passengerSnapshot == coarse.passengerSnapshot)
        #expect(restored.publicBetaHistory == coarse.publicBetaHistory)
    }

    @Test("Disconnected catalogue settlements remain at baseline and reset clears durable growth")
    func disconnectedSettlementAndReset() async throws {
        let clock = SettlementGrowthManualClock()
        let session = makeSession(clock: clock, includesDisconnectedStation: true)
        await createLine(in: session)

        let disconnected = try #require(
            session.settlementGrowthStatus(forStationCRS: "CCC")
        )
        #expect(!disconnected.isConnected)
        #expect(disconnected.currentPopulation == 5_000)
        #expect(disconnected.latestDailyChange == 0)
        #expect(disconnected.passengerDemandMultiplier == 1)
        #expect(disconnected.feedback == .noRailAccess)
        #expect(session.settlementPopulationByCRS["CCC"] == nil)

        clock.advance(by: 50)

        let afterFiveDays = try #require(
            session.settlementGrowthStatus(forStationCRS: "CCC")
        )
        #expect(afterFiveDays.currentPopulation == 5_000)
        #expect(afterFiveDays.latestDailyChange == 0)
        #expect(session.settlementPopulationByCRS["CCC"] == nil)

        session.reset()
        #expect(session.networkPopulation == 0)
        #expect(session.latestNetworkPopulationChange == 0)
        #expect(session.settlementPopulationByCRS.isEmpty)
        #expect(session.publicBetaHistory.records.isEmpty)
    }

    private func makeSession(
        clock: SettlementGrowthManualClock,
        includesDisconnectedStation: Bool = false
    ) -> GameSession {
        let stations = includesDisconnectedStation
            ? [origin, destination, disconnected]
            : [origin, destination]
        return GameSession(
            stations: stations,
            routingProvider: SettlementGrowthRoutingProvider(route: route),
            settlementGrowth: SettlementGrowth(
                configuration: SettlementGrowthConfiguration(
                    baselinePopulationByCRS: [
                        "AAA": 10_000,
                        "BBB": 20_000,
                        "CCC": 5_000,
                    ],
                    fallbackBaselinePopulation: 8_000,
                    minimumHappinessScoreForGrowth: 0,
                    happinessScoreForFullGrowth: 100,
                    reachableDestinationsForFullGrowth: 1,
                    happinessWeight: 1,
                    maximumDailyGrowthRate: 0.01,
                    maximumDailyPopulationIncrease: 1_000,
                    maximumPopulationMultiplier: 1.5,
                    maximumPassengerDemandMultiplier: 1.25,
                    strongGrowthPotentialThreshold: 0.72
                )
            ),
            clock: clock,
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 20,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000,
                operatingDayDuration: 10
            )
        )
    }

    private func createLine(in session: GameSession) async {
        session.startBuilding()
        session.selectStation(origin)
        session.selectStation(destination)
        await session.waitForRouteCalculation()
        #expect(session.phase == .preview)
        session.confirmPreview()
        #expect(session.phase == .operating)
    }

    private var origin: Station {
        Station(crs: "AAA", name: "Alpha", latitude: 51.5, longitude: -0.14)
    }

    private var destination: Station {
        Station(crs: "BBB", name: "Bravo", latitude: 51.4, longitude: -0.10)
    }

    private var disconnected: Station {
        Station(crs: "CCC", name: "Charlie", latitude: 51.3, longitude: -0.06)
    }

    private var route: ServiceRailwayRoute {
        ServiceRailwayRoute(
            coordinates: [origin.coordinate, destination.coordinate],
            cumulativeDistances: [0, 10_000],
            stationCoordinateIndices: [0, 1]
        )
    }
}

private nonisolated struct SettlementGrowthRoutingProvider: RailwayRouteProviding {
    let route: ServiceRailwayRoute

    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        route
    }
}

@MainActor
private final class SettlementGrowthManualClock: SimulationClock {
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
