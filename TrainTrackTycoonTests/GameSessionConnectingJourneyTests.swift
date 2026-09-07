import CoreLocation
import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Game session connecting journeys", .serialized)
@MainActor
struct GameSessionConnectingJourneyTests {
    @Test("A connecting market starts only when both legs are open and rewards the interchange")
    func connectionOpensWithSecondLeg() async throws {
        let secondLegOnly = makeSession(
            clock: ConnectingJourneyManualClock(),
            constructionDuration: 0
        )
        await buildLine(from: interchangeStation, to: easternStation, in: secondLegOnly)
        let standaloneSecondLineID = try #require(secondLegOnly.lines.first?.id)
        let standaloneSecondRevenue = try #require(
            secondLegOnly.economySnapshot(forLineID: standaloneSecondLineID)?
                .revenuePencePerDay
        )

        let clock = ConnectingJourneyManualClock()
        let session = makeSession(clock: clock, constructionDuration: 10)

        await buildLine(from: westernStation, to: interchangeStation, in: session)
        #expect(session.phase == .constructing)
        clock.advance(by: 10)

        let firstLineID = try #require(session.lines.first?.id)
        let directOnlyLine = try #require(session.passengerSnapshot(forLineID: firstLineID))
        let directOnlyEconomy = try #require(session.economySnapshot(forLineID: firstLineID))
        let directOnlyWesternHappiness = try #require(
            session.happinessSnapshot(forStationCRS: westernStation.crs)
        )
        let directOnlyInterchangeVisits = try #require(
            session.passengerSnapshot(forStationCRS: interchangeStation.crs)?.servedDailyJourneys
        )
        #expect(directOnlyLine.connectingPassengersPerDay == 0)
        #expect(session.passengerSnapshot.connectingJourneysPerDay == 0)

        await buildLine(from: interchangeStation, to: easternStation, in: session)
        let secondLineID = try #require(session.lines.last?.id)
        #expect(session.phase == .constructing)
        #expect(session.passengerSnapshot(forLineID: secondLineID)?.passengersPerDay == 0)
        #expect(session.passengerSnapshot.connectingJourneysPerDay == 0)
        #expect(session.passengerSnapshot.connectingJourneySnapshots.isEmpty)

        clock.advance(by: 9)
        #expect(session.passengerSnapshot.connectingJourneysPerDay == 0)
        clock.advance(by: 1)

        let connection = try #require(
            session.passengerSnapshot.connectingJourneySnapshots.first
        )
        let openedFirstLine = try #require(session.passengerSnapshot(forLineID: firstLineID))
        let openedSecondLine = try #require(session.passengerSnapshot(forLineID: secondLineID))
        let interchange = try #require(
            session.passengerSnapshot(forStationCRS: interchangeStation.crs)
        )

        #expect(session.phase == .operating)
        #expect(
            Set([connection.originCRS, connection.destinationCRS])
                == Set([westernStation.crs, easternStation.crs])
        )
        #expect(connection.interchangeCRS == interchangeStation.crs)
        #expect(connection.passengersPerDay > 0)
        #expect(session.passengerSnapshot.connectingJourneysPerDay == connection.passengersPerDay)
        #expect(openedFirstLine.directPassengersPerDay == directOnlyLine.directPassengersPerDay)
        #expect(openedFirstLine.connectingPassengersPerDay == connection.passengersPerDay)
        #expect(openedSecondLine.connectingPassengersPerDay == connection.passengersPerDay)
        #expect(openedFirstLine.peakOccupancyRatio > directOnlyLine.peakOccupancyRatio)
        #expect(
            openedFirstLine.passengersPerDay
                == openedFirstLine.directPassengersPerDay
                    + openedFirstLine.connectingPassengersPerDay
        )
        #expect(
            openedSecondLine.passengersPerDay
                == openedSecondLine.directPassengersPerDay
                    + openedSecondLine.connectingPassengersPerDay
        )
        #expect(interchange.transferJourneysPerDay == connection.passengersPerDay)
        #expect(interchange.servedDailyJourneys > directOnlyInterchangeVisits)
        #expect(interchange.activity > 0)
        #expect(
            session.economySnapshot(forLineID: firstLineID)?.revenuePencePerDay ?? 0
                > directOnlyEconomy.revenuePencePerDay
        )
        #expect(
            session.economySnapshot(forLineID: secondLineID)?.revenuePencePerDay ?? 0
                > standaloneSecondRevenue
        )

        let westernHappiness = try #require(
            session.happinessSnapshot(forStationCRS: westernStation.crs)
        )
        #expect(westernHappiness.reachableDestinationCRSs.contains(easternStation.crs))
        #expect(westernHappiness.happinessScore.isFinite)
        #expect((0...100).contains(westernHappiness.happinessScore))
        #expect(
            westernHappiness.componentScores.crowding
                < directOnlyWesternHappiness.componentScores.crowding
        )

        let dailyHubVisits = interchange.servedDailyJourneys
        clock.advance(by: 30)
        #expect(
            session.stationProgressByCRS[interchangeStation.crs]?.lifetimePassengerVisits
                == Int64(dailyHubVisits)
        )
        #expect(session.settlementGrowthStatus(forStationCRS: interchangeStation.crs) != nil)
    }

    @Test("Disjoint services never create transfers and reset clears the derived market")
    func disjointServicesAndReset() async throws {
        let session = makeSession(
            clock: ConnectingJourneyManualClock(),
            constructionDuration: 0,
            stations: [westernStation, interchangeStation, easternStation, separateStation]
        )

        await buildLine(from: westernStation, to: interchangeStation, in: session)
        await buildLine(from: easternStation, to: separateStation, in: session)

        #expect(session.lines.count == 2)
        #expect(session.passengerSnapshot.connectingJourneysPerDay == 0)
        #expect(session.passengerSnapshot.connectingJourneySnapshots.isEmpty)
        #expect(session.passengerSnapshot.lineSnapshots.allSatisfy {
            $0.connectingPassengersPerDay == 0
                && $0.passengersPerDay == $0.directPassengersPerDay
        })
        #expect(session.passengerSnapshot.stationSnapshots.allSatisfy {
            $0.transferJourneysPerDay == 0
        })

        session.reset()
        #expect(session.passengerSnapshot == .empty)
        #expect(session.economySnapshot == .zero)
        #expect(session.happinessSnapshot.statistics.operatingServiceCount == 0)
        #expect(session.happinessSnapshot.statistics.connectedSettlementCount == 0)
        #expect(session.happinessSnapshot.stationSnapshots.allSatisfy {
            $0.reachableDestinationCount == 0
        })
    }

    @Test("Changes on either leg immediately recalculate the connecting market")
    func serviceChangesRecalculateConnection() async throws {
        let session = makeSession(
            clock: ConnectingJourneyManualClock(),
            constructionDuration: 0
        )
        await buildLine(from: westernStation, to: interchangeStation, in: session)
        await buildLine(from: interchangeStation, to: easternStation, in: session)

        let firstLineID = try #require(session.lines.first?.id)
        let secondLineID = try #require(session.lines.last?.id)
        let initialConnection = try #require(
            session.passengerSnapshot.connectingJourneySnapshots.first
        )
        let initialFirstEconomy = try #require(session.economySnapshot(forLineID: firstLineID))

        session.setServiceFrequency(.hourly, forLineID: firstLineID)
        let hourlyConnection = try #require(
            session.passengerSnapshot.connectingJourneySnapshots.first
        )
        #expect(hourlyConnection != initialConnection)
        #expect(
            session.economySnapshot(forLineID: firstLineID)?.revenuePencePerDay
                != initialFirstEconomy.revenuePencePerDay
        )

        session.setServiceFrequency(.halfHourly, forLineID: firstLineID)
        let beforeOperationsChange = try #require(
            session.passengerSnapshot.connectingJourneySnapshots.first
        )
        let beforeSecondOperations = try #require(session.operationsSnapshot(forLineID: secondLineID))
        session.setServicePattern(.express, forLineID: secondLineID)
        let afterOperationsChange = try #require(
            session.passengerSnapshot.connectingJourneySnapshots.first
        )
        let afterSecondOperations = try #require(session.operationsSnapshot(forLineID: secondLineID))

        #expect(afterSecondOperations != beforeSecondOperations)
        #expect(afterOperationsChange != beforeOperationsChange)
        #expect(afterOperationsChange.combinedReliability.isFinite)
        #expect((0...1).contains(afterOperationsChange.combinedReliability))
        #expect(session.passengerSnapshot.averagePeakOccupancyRatio.isFinite)
        #expect((0...1).contains(session.passengerSnapshot.averagePeakOccupancyRatio))
    }

    @Test("Export and restore deterministically recompute connecting journeys")
    func persistenceRoundTrip() async throws {
        let source = makeSession(
            clock: ConnectingJourneyManualClock(),
            constructionDuration: 0
        )
        await buildLine(from: westernStation, to: interchangeStation, in: source)
        await buildLine(from: interchangeStation, to: easternStation, in: source)
        let secondLineID = try #require(source.lines.last?.id)
        source.setServicePattern(.express, forLineID: secondLineID)
        source.togglePlayPause()
        let saved = source.makeSaveSnapshot()
        #expect(source.passengerSnapshot.connectingJourneysPerDay > 0)

        let restored = makeSession(
            clock: ConnectingJourneyManualClock(),
            constructionDuration: 0
        )
        try await restored.restore(from: saved)

        #expect(restored.lines.map(\.id) == source.lines.map(\.id))
        #expect(restored.passengerSnapshot == source.passengerSnapshot)
        #expect(restored.operationsSnapshotsByLineID == source.operationsSnapshotsByLineID)
        #expect(restored.happinessSnapshot == source.happinessSnapshot)
        #expect(restored.economySnapshot == source.economySnapshot)
        #expect(restored.settlementPopulationByCRS == source.settlementPopulationByCRS)
        #expect(!restored.isPlaying)
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

    private var separateStation: Station {
        Station(crs: "GTW", name: "Gatwick Airport", latitude: 51.1565, longitude: -0.161)
    }

    private func makeSession(
        clock: ConnectingJourneyManualClock,
        constructionDuration: TimeInterval,
        stations: [Station]? = nil
    ) -> GameSession {
        GameSession(
            stations: stations ?? [westernStation, interchangeStation, easternStation],
            routingProvider: ConnectingJourneyRoutingProvider(
                route: ServiceRailwayRoute(
                    coordinates: [
                        CLLocationCoordinate2D(latitude: 51, longitude: -0.1),
                        CLLocationCoordinate2D(latitude: 51, longitude: 0.1),
                    ],
                    cumulativeDistances: [0, 35_000],
                    stationCoordinateIndices: [0, 1]
                )
            ),
            // Connection tests isolate train-seat residual capacity; station-platform sharing
            // is covered by GameSessionStationCapacityTests.
            stationCapacitySimulation: StationCapacitySimulation(
                configuration: StationCapacityConfiguration(
                    trainCallsPerPlatformPerHour: 1_000_000
                )
            ),
            clock: clock,
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: constructionDuration,
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
    }
}

private nonisolated struct ConnectingJourneyRoutingProvider: RailwayRouteProviding {
    let route: ServiceRailwayRoute

    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        route
    }
}

@MainActor
private final class ConnectingJourneyManualClock: SimulationClock {
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
