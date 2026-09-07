import CoreLocation
import Foundation
import Testing
@testable import TrainTrackTycoon

/// Long-running and work-budget coverage deliberately avoids elapsed wall-clock assertions.
/// These tests fail only when deterministic state, bounded storage, or a structural work limit
/// regresses, so they remain useful across simulator and CI hardware of different speeds.
@Suite("Game session deterministic soak", .serialized)
@MainActor
struct GameSessionSimulationSoakTests {
    private let operatingDayDuration: TimeInterval = 30

    @Test("A maximum POC network remains valid through a two-year deterministic soak")
    func twoYearMaximumNetworkSoak() async throws {
        let clock = SoakManualClock()
        let session = try await makeMaximumNetwork(
            clock: clock,
            operatingDayDuration: operatingDayDuration
        )
        var previousVisits = session.stationProgressByCRS.mapValues(\.lifetimePassengerVisits)
        var previousLevels = session.stationProgressByCRS.mapValues(\.level)

        for day in 1...730 {
            clock.advance(by: operatingDayDuration)

            #expect(session.economyLedger.completedOperatingDays == UInt64(day))
            for (crs, progress) in session.stationProgressByCRS {
                #expect(progress.lifetimePassengerVisits >= previousVisits[crs, default: 0])
                #expect(progress.level >= previousLevels[crs, default: .halt])
                previousVisits[crs] = progress.lifetimePassengerVisits
                previousLevels[crs] = progress.level
            }
            if day == 1 || day.isMultiple(of: 30) {
                expectValidMaximumNetwork(session)
            }
        }

        expectValidMaximumNetwork(session)
        #expect(session.publicBetaHistory.records.count == 120)
        #expect(session.publicBetaHistory.records.first?.operatingDay == 611)
        #expect(session.publicBetaHistory.records.last?.operatingDay == 730)
        #expect(
            session.publicBetaHistory.records.map(\.operatingDay)
                == Array(UInt64(611)...UInt64(730))
        )
        #expect(session.presentationEvents(after: 0).count == 32)
        #expect(session.financeLedger.cashBalancePence == 0)
        #expect(session.financeLedger.loans.isEmpty)
        #expect(!session.financeLedger.isBankrupt)
        #expect(session.publicBetaFacts.completedLineCount == 2)
        #expect(session.publicBetaFacts.stationCount == 3)
        #expect(session.publicBetaFacts.completedHighSpeedCorridorCount == 1)
        #expect(
            session.networkPopulation
                > session.settlementPopulationByCRS.values.reduce(0) {
                    $0 + $1.baselinePopulation
                }
        )
        #expect(
            session.publicBetaHistory.records.last?.totalNetworkPopulation
                == session.networkPopulation
        )
    }

    @Test("Twelve thousand display-sized ticks match one bounded coarse tick")
    func displayCadencePartitionEquivalence() async throws {
        let seedClock = SoakManualClock()
        let seed = try await makeMaximumNetwork(
            clock: seedClock,
            operatingDayDuration: 10_000
        )
        let snapshot = seed.makeSaveSnapshot()

        let coarseClock = SoakManualClock()
        let fineClock = SoakManualClock()
        let coarse = makeSession(clock: coarseClock, operatingDayDuration: 10_000)
        let fine = makeSession(clock: fineClock, operatingDayDuration: 10_000)
        try await coarse.restore(from: snapshot)
        try await fine.restore(from: snapshot)
        let coarseRevision = coarse.persistenceRevision
        let fineRevision = fine.persistenceRevision

        let displayTickCount = 12_000
        let displayTickDelta: TimeInterval = 0.05
        let totalElapsed = TimeInterval(displayTickCount) * displayTickDelta
        coarseClock.advance(by: totalElapsed)
        for _ in 0..<displayTickCount {
            fineClock.advance(by: displayTickDelta)
        }

        #expect(coarse.economyLedger.completedOperatingDays == 0)
        #expect(fine.economyLedger.completedOperatingDays == 0)
        #expect(abs(coarse.economyLedger.operatingDayProgress - 0.06) < 0.000_000_001)
        #expect(abs(fine.economyLedger.operatingDayProgress - 0.06) < 0.000_000_001)
        #expect(coarse.persistenceRevision == coarseRevision)
        #expect(fine.persistenceRevision == fineRevision)
        #expect(coarse.financeLedger == fine.financeLedger)
        #expect(coarse.stationProgressByCRS == fine.stationProgressByCRS)
        #expect(coarse.passengerSnapshot == fine.passengerSnapshot)
        #expect(coarse.stationCapacitySnapshot == fine.stationCapacitySnapshot)
        #expect(coarse.happinessSnapshot == fine.happinessSnapshot)
        #expect(coarse.operationsSnapshotsByLineID == fine.operationsSnapshotsByLineID)
        #expect(coarse.economySnapshot == fine.economySnapshot)
        #expect(coarse.publicBetaHistory == fine.publicBetaHistory)
        expectEquivalentTrainStates(coarse.lines, fine.lines)
        expectValidMaximumNetwork(coarse)
        expectValidMaximumNetwork(fine)
    }

    @Test("Extreme input respects simulation, feedback, and retained-history work budgets")
    func structuralWorkBudgets() async throws {
        let arrivalClock = SoakManualClock()
        let arrivalSession = try await makeMaximumNetwork(
            clock: arrivalClock,
            operatingDayDuration: 10_000
        )
        let eventCursor = arrivalSession.latestPresentationEvent?.sequence ?? 0

        arrivalClock.advance(by: .greatestFiniteMagnitude)

        let newEvents = arrivalSession.presentationEvents(after: eventCursor)
        let arrivalEvents = newEvents.filter { event in
            if case .trainArrived = event.kind { return true }
            return false
        }
        #expect(arrivalSession.economyLedger.completedOperatingDays == 0)
        #expect(abs(arrivalSession.economyLedger.operatingDayProgress - 0.36) < 0.000_000_001)
        #expect(newEvents.count == 12)
        #expect(arrivalEvents.count == 12)
        #expect(arrivalSession.presentationEvents(after: 0).count <= 32)
        expectValidMaximumNetwork(arrivalSession)

        let settlementClock = SoakManualClock()
        let settlementSession = try await makeMaximumNetwork(
            clock: settlementClock,
            operatingDayDuration: operatingDayDuration
        )
        for batch in 1...8 {
            let previousDay = settlementSession.economyLedger.completedOperatingDays
            settlementClock.advance(by: .greatestFiniteMagnitude)

            #expect(
                settlementSession.economyLedger.completedOperatingDays - previousDay == 120
            )
            #expect(settlementSession.economyLedger.completedOperatingDays == UInt64(batch * 120))
            #expect(settlementSession.publicBetaHistory.records.count <= 120)
            #expect(settlementSession.presentationEvents(after: 0).count <= 32)
            expectValidMaximumNetwork(settlementSession)
        }

        #expect(settlementSession.economyLedger.completedOperatingDays == 960)
        #expect(settlementSession.publicBetaHistory.records.count == 120)
        #expect(settlementSession.publicBetaHistory.records.first?.operatingDay == 841)
        #expect(settlementSession.publicBetaHistory.records.last?.operatingDay == 960)
    }

    private func expectValidMaximumNetwork(_ session: GameSession) {
        #expect(session.phase == .operating)
        #expect(session.isPlaying)
        #expect(session.lines.count == 2)
        #expect(session.trains.count == 8)
        #expect(Set(session.lines.map(\.id)).count == session.lines.count)
        #expect(Set(session.trains.map(\.id)).count == session.trains.count)
        #expect(session.passengerSnapshot.linesByID.count == session.lines.count)
        #expect(session.stationCapacitySnapshot.linesByID.count == session.lines.count)
        #expect(session.stationCapacitySnapshot.stationsByCRS.count == 3)
        #expect(session.operationsSnapshotsByLineID.count == session.lines.count)
        #expect(session.economySnapshot.lineSnapshotsByID.count == session.lines.count)
        #expect(session.stationProgressByCRS.count == 3)
        #expect(session.settlementPopulationByCRS.count == 3)
        #expect(session.publicBetaHistory.records.count <= 120)
        #expect(
            session.publicBetaHistory.records.map(\.operatingDay)
                == session.publicBetaHistory.records.map(\.operatingDay).sorted()
        )

        #expect(session.passengerSnapshot.potentialDailyJourneys >= 0)
        #expect(session.passengerSnapshot.passengersPerDay >= 0)
        #expect(session.passengerSnapshot.unservedDailyJourneys >= 0)
        #expect(session.passengerSnapshot.connectingJourneysPerDay > 0)
        #expect(session.passengerSnapshot.connectingJourneySnapshots.count == 1)
        #expect(
            session.passengerSnapshot.connectingJourneySnapshots
                .reduce(0) { $0 + $1.passengersPerDay }
                == session.passengerSnapshot.connectingJourneysPerDay
        )
        #expect(
            session.passengerSnapshot.lineSnapshots.reduce(0) {
                $0 + $1.passengersPerDay
            } == session.passengerSnapshot.passengersPerDay
        )
        #expect(session.passengerSnapshot.lineSnapshots.allSatisfy {
            $0.passengersPerDay
                == $0.directPassengersPerDay + $0.connectingPassengersPerDay
        })
        #expect(
            session.passengerSnapshot(forStationCRS: "ECR")?.transferJourneysPerDay
                == session.passengerSnapshot.connectingJourneysPerDay
        )
        #expect(session.passengerSnapshot.averagePeakOccupancyRatio.isFinite)
        #expect((0...1).contains(session.passengerSnapshot.averagePeakOccupancyRatio))
        #expect(session.happinessSnapshot.globalHappinessScore.isFinite)
        #expect((0...100).contains(session.happinessSnapshot.globalHappinessScore))
        #expect(session.economySnapshot.totalRevenuePencePerDay >= 0)
        #expect(session.economySnapshot.totalOperatingCostPencePerDay >= 0)
        #expect(
            session.networkPopulation
                == session.settlementPopulationByCRS.values.reduce(0) {
                    $0 + $1.currentPopulation
                }
        )
        #expect(session.latestNetworkPopulationChange >= 0)

        for state in session.settlementPopulationByCRS.values {
            #expect(state.currentPopulation >= state.baselinePopulation)
            #expect(
                state.currentPopulation
                    <= Int64(Double(state.baselinePopulation) * 1.5)
            )
            #expect(state.latestDailyChange >= 0)
            #expect(state.latestDailyChange <= 500)
            let multiplier = Double(state.currentPopulation)
                / Double(state.baselinePopulation)
            #expect(multiplier >= 1)
        }

        for line in session.lines {
            #expect(line.isConstructed)
            #expect(line.route.totalLength.isFinite)
            #expect(line.route.totalLength > 0)
            #expect(line.trains.count == line.serviceFrequency.visibleTrainCount)
            #expect(line.ownedTrainCount >= line.trains.count)
            #expect(session.operationsSnapshot(forLineID: line.id) != nil)
            #expect(session.passengerSnapshot(forLineID: line.id) != nil)
            let capacity = session.stationCapacitySnapshot(forLineID: line.id)
            #expect(capacity != nil)
            #expect(capacity?.scheduledDeparturesPerHour
                == Double(line.serviceFrequency.departuresPerHour))
            #expect(capacity?.effectiveDeparturesPerHour.isFinite == true)
            #expect((capacity?.effectiveDeparturesPerHour ?? -1) >= 0)
            #expect((capacity?.effectiveDeparturesPerHour ?? .greatestFiniteMagnitude)
                <= Double(line.serviceFrequency.departuresPerHour))
            #expect(session.passengerSnapshot(forLineID: line.id)?
                .effectiveDeparturesPerHour == capacity?.effectiveDeparturesPerHour)
            #expect(session.economySnapshot(forLineID: line.id) != nil)

            for train in line.trains {
                #expect(train.lineID == line.id)
                #expect(train.distanceAlongRoute.isFinite)
                #expect(train.distanceAlongRoute >= -0.000_001)
                #expect(train.distanceAlongRoute <= line.route.totalLength + 0.000_001)
                #expect(train.dwellRemaining.isFinite)
                #expect(train.dwellRemaining >= 0)
                #expect(train.dwellRemaining <= 3.000_001)
                #expect(train.bearing.isFinite)
                #expect((0..<360).contains(train.bearing))
                #expect(train.coordinate.latitude.isFinite)
                #expect(train.coordinate.longitude.isFinite)
            }
        }

        for progress in session.stationProgressByCRS.values {
            #expect(progress.lifetimePassengerVisits >= 0)
            #expect(StationLevel.allCases.contains(progress.level))
        }

        for (crs, capacity) in session.stationCapacitySnapshot.stationsByCRS {
            #expect(capacity.platformCount
                == session.stationProgressByCRS[crs]?.level.platformCount)
            #expect(capacity.scheduledTrainCallsPerHour.isFinite)
            #expect(capacity.effectiveTrainCallsPerHour.isFinite)
            #expect(capacity.scheduledTrainCallsPerHour >= 0)
            #expect(capacity.effectiveTrainCallsPerHour >= 0)
            #expect(capacity.effectiveTrainCallsPerHour
                <= capacity.scheduledTrainCallsPerHour + 0.000_000_001)
            if let trainCallCapacityPerHour = capacity.trainCallCapacityPerHour {
                #expect(trainCallCapacityPerHour.isFinite)
                #expect(capacity.effectiveTrainCallsPerHour
                    <= trainCallCapacityPerHour + 0.000_000_001)
            }
        }
    }

    private func expectEquivalentTrainStates(
        _ lhsLines: [BuiltLine],
        _ rhsLines: [BuiltLine]
    ) {
        #expect(lhsLines.map(\.id) == rhsLines.map(\.id))
        for (lhsLine, rhsLine) in zip(lhsLines, rhsLines) {
            #expect(lhsLine.trains.map(\.id) == rhsLine.trains.map(\.id))
            for (lhs, rhs) in zip(lhsLine.trains, rhsLine.trains) {
                #expect(lhs.direction == rhs.direction)
                #expect(abs(lhs.distanceAlongRoute - rhs.distanceAlongRoute) < 0.000_001)
                #expect(abs(lhs.dwellRemaining - rhs.dwellRemaining) < 0.000_001)
                #expect(abs(lhs.bearing - rhs.bearing) < 0.000_001)
                #expect(abs(lhs.coordinate.latitude - rhs.coordinate.latitude) < 0.000_000_001)
                #expect(abs(lhs.coordinate.longitude - rhs.coordinate.longitude) < 0.000_000_001)
            }
        }
    }

    private func makeMaximumNetwork(
        clock: SoakManualClock,
        operatingDayDuration: TimeInterval
    ) async throws -> GameSession {
        let session = makeSession(
            clock: clock,
            operatingDayDuration: operatingDayDuration
        )
        try await addLine(
            from: victoria,
            to: eastCroydon,
            railwayClass: .conventional,
            in: session
        )
        let conventionalID = try #require(session.lines.last?.id)
        session.setServiceFrequency(.quarterHourly, forLineID: conventionalID)
        session.setServicePattern(.balanced, forLineID: conventionalID)
        #expect(session.upgradeTrackCapacity(forLineID: conventionalID))

        try await addLine(
            from: eastCroydon,
            to: brighton,
            railwayClass: .highSpeed,
            in: session
        )
        let highSpeedID = try #require(session.lines.last?.id)
        session.setServiceFrequency(.quarterHourly, forLineID: highSpeedID)

        #expect(session.lines.count == 2)
        #expect(session.trains.count == 8)
        return session
    }

    private func makeSession(
        clock: SoakManualClock,
        operatingDayDuration: TimeInterval
    ) -> GameSession {
        GameSession(
            stations: [victoria, eastCroydon, brighton],
            routingProvider: SoakRoutingProvider(route: route),
            gameMode: .zen,
            clock: clock,
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 20,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000,
                operatingDayDuration: operatingDayDuration
            )
        )
    }

    private func addLine(
        from origin: Station,
        to destination: Station,
        railwayClass: RailwayClass,
        in session: GameSession
    ) async throws {
        session.startBuilding()
        session.selectStation(origin)
        session.selectStation(destination)
        await session.waitForRouteCalculation()
        #expect(session.phase == .preview)
        session.setPreviewRailwayClass(railwayClass)
        session.confirmPreview()
        #expect(session.phase == .operating)
    }

    private var victoria: Station {
        Station(
            crs: "VIC",
            name: "London Victoria",
            latitude: 51.4952,
            longitude: -0.1441
        )
    }

    private var eastCroydon: Station {
        Station(
            crs: "ECR",
            name: "East Croydon",
            latitude: 51.3755,
            longitude: -0.0928
        )
    }

    private var brighton: Station {
        Station(crs: "BTN", name: "Brighton", latitude: 50.829, longitude: -0.141)
    }

    private var route: ServiceRailwayRoute {
        ServiceRailwayRoute(
            coordinates: [
                CLLocationCoordinate2D(latitude: 51.5, longitude: -0.14),
                CLLocationCoordinate2D(latitude: 51.25, longitude: -0.12),
                CLLocationCoordinate2D(latitude: 50.83, longitude: -0.14),
            ],
            cumulativeDistances: [0, 600, 1_200],
            stationCoordinateIndices: [0, 2]
        )
    }
}

private nonisolated struct SoakRoutingProvider: RailwayRouteProviding {
    let route: ServiceRailwayRoute

    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        route
    }
}

@MainActor
private final class SoakManualClock: SimulationClock {
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
