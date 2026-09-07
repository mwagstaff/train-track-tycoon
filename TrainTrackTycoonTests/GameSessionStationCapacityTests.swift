import CoreLocation
import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Game session station capacity", .serialized)
@MainActor
struct GameSessionStationCapacityTests {
    @Test("A half-hourly service fits a one-platform Halt exactly")
    func legacyHalfHourlyHaltCapacity() async throws {
        let session = makeSession()
        await buildLine(from: westernStation, to: interchangeStation, in: session)

        let lineID = try #require(session.lines.first?.id)
        let lineCapacity = try #require(
            session.stationCapacitySnapshot(forLineID: lineID)
        )
        let stationCapacity = try #require(
            session.stationCapacitySnapshot(forStationCRS: westernStation.crs)
        )
        let passengers = try #require(session.passengerSnapshot(forLineID: lineID))

        #expect(lineCapacity.scheduledDeparturesPerHour == 2)
        #expect(lineCapacity.effectiveDeparturesPerHour == 2)
        #expect(lineCapacity.throughputRatio == 1)
        #expect(!lineCapacity.isPlatformConstrained)
        #expect(stationCapacity.platformCount == 1)
        #expect(stationCapacity.scheduledTrainCallsPerHour == 4)
        #expect(stationCapacity.trainCallCapacityPerHour == 4)
        #expect(stationCapacity.effectiveTrainCallsPerHour == 4)
        #expect(!stationCapacity.isPlatformConstrained)
        #expect(passengers.effectiveDeparturesPerHour == 2)
        #expect(passengers.feedback != .stationCapacityConstrained)
        #expect(session.stationCapacitySnapshot.constrainedStationCount == 0)
    }

    @Test("A shared Halt constrains both services through the same hub")
    func sharedHaltConstrainsBothLines() async throws {
        let session = makeSession()
        await buildLine(from: westernStation, to: interchangeStation, in: session)

        let firstLineID = try #require(session.lines.first?.id)
        let directOnly = try #require(session.passengerSnapshot(forLineID: firstLineID))
        await buildLine(from: interchangeStation, to: easternStation, in: session)

        let secondLineID = try #require(session.lines.last?.id)
        let hub = try #require(
            session.stationCapacitySnapshot(forStationCRS: interchangeStation.crs)
        )
        let firstCapacity = try #require(
            session.stationCapacitySnapshot(forLineID: firstLineID)
        )
        let secondCapacity = try #require(
            session.stationCapacitySnapshot(forLineID: secondLineID)
        )
        let firstPassengers = try #require(
            session.passengerSnapshot(forLineID: firstLineID)
        )
        let secondPassengers = try #require(
            session.passengerSnapshot(forLineID: secondLineID)
        )

        #expect(hub.platformCount == 1)
        #expect(hub.scheduledTrainCallsPerHour == 8)
        #expect(hub.trainCallCapacityPerHour == 4)
        #expect(hub.effectiveTrainCallsPerHour == 4)
        #expect(hub.throughputFactor == 0.5)
        #expect(hub.blockedTrainCallsPerHour == 4)
        #expect(hub.isPlatformConstrained)
        #expect(session.stationCapacitySnapshot.constrainedStationCount == 1)

        for capacity in [firstCapacity, secondCapacity] {
            #expect(capacity.scheduledDeparturesPerHour == 2)
            #expect(capacity.effectiveDeparturesPerHour == 1)
            #expect(capacity.limitingStationCRSs == [interchangeStation.crs])
            #expect(capacity.isPlatformConstrained)
        }
        #expect(firstPassengers.effectiveDeparturesPerHour == 1)
        #expect(secondPassengers.effectiveDeparturesPerHour == 1)
        #expect(firstPassengers.feedback == .stationCapacityConstrained)
        #expect(secondPassengers.feedback == .stationCapacityConstrained)
        #expect(firstPassengers.directPassengersPerDay < directOnly.directPassengersPerDay)
        #expect(session.passengerSnapshot.connectingJourneysPerDay > 0)
    }

    @Test("An unsupported timetable raises cost without inventing platform throughput")
    func excessFrequencyDoesNotBypassPlatforms() async throws {
        let session = makeSession()
        await buildLine(from: westernStation, to: interchangeStation, in: session)

        let lineID = try #require(session.lines.first?.id)
        let halfHourlyPassengers = try #require(
            session.passengerSnapshot(forLineID: lineID)
        )
        let halfHourlyEconomy = try #require(session.economySnapshot(forLineID: lineID))

        session.setServiceFrequency(.quarterHourly, forLineID: lineID)

        let capacity = try #require(session.stationCapacitySnapshot(forLineID: lineID))
        let quarterHourlyPassengers = try #require(
            session.passengerSnapshot(forLineID: lineID)
        )
        let quarterHourlyEconomy = try #require(
            session.economySnapshot(forLineID: lineID)
        )

        #expect(capacity.scheduledDeparturesPerHour == 4)
        #expect(capacity.effectiveDeparturesPerHour == 2)
        #expect(capacity.throughputRatio == 0.5)
        #expect(capacity.isPlatformConstrained)
        #expect(quarterHourlyPassengers.effectiveDeparturesPerHour == 2)
        #expect(quarterHourlyPassengers.dailyCapacity == halfHourlyPassengers.dailyCapacity)
        #expect(quarterHourlyPassengers.passengersPerDay
            <= halfHourlyPassengers.passengersPerDay)
        #expect(quarterHourlyPassengers.feedback == .stationCapacityConstrained)
        #expect(quarterHourlyEconomy.trainOperatingCostPencePerDay
            > halfHourlyEconomy.trainOperatingCostPencePerDay)
        #expect(quarterHourlyEconomy.revenuePencePerDay
            <= halfHourlyEconomy.revenuePencePerDay)
    }

    @Test("Automatic promotion expands next-day capacity without a capital purchase")
    func promotionExpandsCapacityAtTheDayBoundary() async throws {
        let clock = StationCapacityManualClock()
        let stationEvolution = StationEvolution(
            configuration: StationEvolutionConfiguration(
                localStationThreshold: 1,
                townStationThreshold: 100_000,
                majorStationThreshold: 200_000,
                interchangeThreshold: 600_000,
                terminusThreshold: 1_500_000
            )
        )
        let session = makeSession(
            clock: clock,
            stationEvolution: stationEvolution,
            gameMode: .career
        )
        await buildLine(from: westernStation, to: interchangeStation, in: session)
        await buildLine(from: interchangeStation, to: easternStation, in: session)

        let firstLineID = try #require(session.lines.first?.id)
        let capacityBefore = try #require(
            session.stationCapacitySnapshot(forLineID: firstLineID)
        )
        let passengersBefore = session.passengerSnapshot.passengersPerDay
        let economyBefore = session.economySnapshot
        let financeBefore = session.financeLedger
        let stationValueBefore = session.financeSnapshot.stationValuePence

        #expect(capacityBefore.effectiveDeparturesPerHour == 1)
        #expect(session.stationProgressByCRS.values.allSatisfy { $0.level == .halt })
        clock.advance(by: 30)

        let capacityAfter = try #require(
            session.stationCapacitySnapshot(forLineID: firstLineID)
        )
        let hubAfter = try #require(
            session.stationCapacitySnapshot(forStationCRS: interchangeStation.crs)
        )

        #expect(session.economyLedger.completedOperatingDays == 1)
        #expect(session.stationProgressByCRS.values.allSatisfy {
            $0.level == .localStation
        })
        #expect(capacityAfter.effectiveDeparturesPerHour == 2)
        #expect(!capacityAfter.isPlatformConstrained)
        #expect(hubAfter.platformCount == 2)
        #expect(hubAfter.trainCallCapacityPerHour == 8)
        #expect(session.passengerSnapshot.passengersPerDay > passengersBefore)
        #expect(session.economySnapshot.stationUpkeepPencePerDay
            > economyBefore.stationUpkeepPencePerDay)
        #expect(session.financeSnapshot.stationValuePence > stationValueBefore)
        #expect(session.financeLedger.lifetimeConstructionSpendPence
            == financeBefore.lifetimeConstructionSpendPence)
        #expect(session.financeLedger.lifetimeRollingStockSpendPence
            == financeBefore.lifetimeRollingStockSpendPence)
        #expect(session.financeLedger.cashBalancePence
            == financeBefore.cashBalancePence + economyBefore.operatingResultPencePerDay)
        #expect(session.economyLedger.lifetimeRevenuePence
            == economyBefore.totalRevenuePencePerDay)
        #expect(session.economyLedger.lifetimeOperatingCostPence
            == economyBefore.totalOperatingCostPencePerDay)
    }

    @Test("Station capacity is derived identically after a schema-11 restore")
    func stationCapacityRoundTrip() async throws {
        let sourceClock = StationCapacityManualClock()
        let source = makeSession(
            clock: sourceClock,
            stationEvolution: StationEvolution(
                configuration: StationEvolutionConfiguration(
                    localStationThreshold: 1,
                    townStationThreshold: 100_000,
                    majorStationThreshold: 200_000,
                    interchangeThreshold: 600_000,
                    terminusThreshold: 1_500_000
                )
            )
        )
        await buildLine(from: westernStation, to: interchangeStation, in: source)
        await buildLine(from: interchangeStation, to: easternStation, in: source)
        sourceClock.advance(by: 30)
        let saved = source.makeSaveSnapshot()

        #expect(saved.schemaVersion == GameSaveSnapshot.currentSchemaVersion)
        let encoded = try JSONEncoder().encode(saved)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("stationCapacity"))

        let restored = makeSession()
        try await restored.restore(from: saved)

        #expect(restored.stationCapacitySnapshot == source.stationCapacitySnapshot)
        #expect(restored.passengerSnapshot == source.passengerSnapshot)
        #expect(restored.economySnapshot == source.economySnapshot)
        #expect(restored.stationProgressByCRS == source.stationProgressByCRS)
        #expect(restored.stationCapacitySnapshot(forStationCRS: interchangeStation.crs)?
            .platformCount == 2)
    }

    private var westernStation: Station {
        Station(crs: "VIC", name: "London Victoria", latitude: 51.4952, longitude: -0.1441)
    }

    private var interchangeStation: Station {
        Station(crs: "ECR", name: "East Croydon", latitude: 51.3752, longitude: -0.0923)
    }

    private var easternStation: Station {
        Station(crs: "BTN", name: "Brighton", latitude: 50.829, longitude: -0.141)
    }

    private func makeSession(
        clock: StationCapacityManualClock? = nil,
        stationEvolution: StationEvolution = StationEvolution(),
        gameMode: GameMode = .zen
    ) -> GameSession {
        GameSession(
            stations: [westernStation, interchangeStation, easternStation],
            routingProvider: StationCapacityRoutingProvider(
                route: ServiceRailwayRoute(
                    coordinates: [
                        CLLocationCoordinate2D(latitude: 51, longitude: -0.1),
                        CLLocationCoordinate2D(latitude: 51, longitude: 0.1),
                    ],
                    cumulativeDistances: [0, 1_000],
                    stationCoordinateIndices: [0, 1]
                )
            ),
            stationEvolution: stationEvolution,
            gameMode: gameMode,
            clock: clock ?? StationCapacityManualClock(),
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 10,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000,
                operatingDayDuration: 30
            )
        )
    }

    private func buildLine(
        from origin: Station,
        to destination: Station,
        in session: GameSession
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

private nonisolated struct StationCapacityRoutingProvider: RailwayRouteProviding {
    let route: ServiceRailwayRoute

    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        route
    }
}

@MainActor
private final class StationCapacityManualClock: SimulationClock {
    private var tickHandler: (@MainActor (TimeInterval) -> Void)?

    func start(tick: @escaping @MainActor (TimeInterval) -> Void) {
        tickHandler = tick
    }

    func stop() {
        tickHandler = nil
    }

    func setSuspended(_ isSuspended: Bool) {}

    func advance(by delta: TimeInterval) {
        tickHandler?(delta)
    }
}
