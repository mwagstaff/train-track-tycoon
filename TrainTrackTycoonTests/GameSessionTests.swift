import CoreLocation
import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Game session", .serialized)
@MainActor
struct GameSessionTests {
    @Test("Station choices produce a priced route preview")
    func routePreviewStateMachine() async {
        let route = makeRoute(length: 10_000)
        let clock = ManualSimulationClock()
        let session = makeSession(route: route, clock: clock)

        #expect(clock.isRunning)
        #expect(session.phase == .idle)

        session.startBuilding()
        #expect(session.phase == .selectingOrigin)

        session.selectStation(origin)
        #expect(session.phase == .selectingDestination)
        #expect(session.selectedOrigin == origin)

        session.selectStation(destination)
        #expect(session.phase == .calculating)
        await session.waitForRouteCalculation()

        #expect(session.phase == .preview)
        #expect(session.preview?.origin == origin)
        #expect(session.preview?.destination == destination)
        #expect(session.preview?.distanceMetres == 10_000)
        #expect(session.preview?.indicativeCost == 15_000_000)
    }

    @Test("Construction and playback consume deterministic elapsed time")
    func deterministicConstructionAndPlayback() async {
        let route = makeRoute(length: 100)
        let clock = ManualSimulationClock()
        let configuration = GameConfiguration(
            maximumLineCount: 2,
            constructionDuration: 2,
            trainSpeedMetresPerSecond: 10,
            terminalDwellDuration: 2,
            indicativeCostPerKilometre: 1_500_000
        )
        let session = makeSession(
            route: route,
            clock: clock,
            configuration: configuration
        )
        await createPreview(in: session)

        session.confirmPreview()
        #expect(session.phase == .constructing)
        #expect(session.lines.count == 1)
        #expect(session.lines[0].constructionProgress == 0)
        #expect(session.trains.isEmpty)

        clock.advance(by: 1)
        #expect(session.lines[0].constructionProgress == 0.5)

        session.togglePlayPause()
        #expect(clock.isSuspended)
        clock.advance(by: 5)
        #expect(session.lines[0].constructionProgress == 0.5)

        session.togglePlayPause()
        #expect(!clock.isSuspended)
        session.setSimulationSpeed(.threeX)
        clock.advance(by: 0.5)

        #expect(session.phase == .operating)
        #expect(session.lines[0].constructionProgress == 1)
        // Of the 1.5 simulated seconds, 1 finishes construction and 0.5 moves the train.
        #expect(abs(session.trains[0].distanceAlongRoute - 5) < 0.000_001)
    }

    @Test("Train shuttles, dwells, and reverses its bearing")
    func trainShuttleMovement() async {
        let route = makeRoute(length: 100)
        let clock = ManualSimulationClock()
        let configuration = GameConfiguration(
            maximumLineCount: 2,
            constructionDuration: 0,
            trainSpeedMetresPerSecond: 10,
            terminalDwellDuration: 2,
            indicativeCostPerKilometre: 1_500_000
        )
        let session = makeSession(
            route: route,
            clock: clock,
            configuration: configuration
        )
        await createPreview(in: session)
        session.confirmPreview()

        clock.advance(by: 5)
        #expect(abs(session.trains[0].distanceAlongRoute - 50) < 0.000_001)
        #expect(session.trains[0].direction == .forward)
        #expect(abs(session.trains[0].bearing - 90) < 0.1)

        clock.advance(by: 5)
        #expect(session.trains[0].distanceAlongRoute == 100)
        #expect(session.trains[0].direction == .reverse)
        #expect(session.trains[0].dwellRemaining == 2)
        #expect(abs(session.trains[0].bearing - 270) < 0.1)

        clock.advance(by: 1)
        #expect(session.trains[0].distanceAlongRoute == 100)
        #expect(session.trains[0].dwellRemaining == 1)

        clock.advance(by: 2)
        #expect(abs(session.trains[0].distanceAlongRoute - 90) < 0.000_001)
        #expect(session.trains[0].dwellRemaining == 0)
        #expect(session.trains[0].direction == .reverse)
    }

    @Test("Terminal arrivals emit reward feedback without settling revenue twice")
    func terminalArrivalPresentationEvent() async throws {
        let route = makeRoute(length: 100)
        let clock = ManualSimulationClock()
        let session = makeSession(
            route: route,
            clock: clock,
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 10,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000
            )
        )
        await createAndConfirmLine(in: session)
        let line = try #require(session.lines.first)
        session.setServiceFrequency(.hourly, forLineID: line.id)
        let train = try #require(session.trains.first)
        let eventCursor = session.latestPresentationEvent?.sequence ?? 0
        let lifetimeRevenueBeforeArrival = session.economyLedger.lifetimeRevenuePence

        // With one active train, a Balanced timetable operates as the remaining Local slot.
        // Allow enough simulated time for its slower stopping-service speed to reach the terminal.
        clock.advance(by: 20)

        let arrivalEvents = session.presentationEvents(after: eventCursor).filter { event in
            if case .trainArrived = event.kind { return true }
            return false
        }
        let arrival = try #require(arrivalEvents.first)
        guard case let .trainArrived(
            lineID,
            trainID,
            stationCRS,
            fareRevenuePence,
            soundsHorn
        ) = arrival.kind else {
            Issue.record("Expected a train-arrival presentation event")
            return
        }
        #expect(lineID == line.id)
        #expect(trainID == train.id)
        #expect(stationCRS == destination.crs)
        #expect(fareRevenuePence > 0)
        #expect(!soundsHorn)
        #expect(session.economyLedger.lifetimeRevenuePence == lifetimeRevenueBeforeArrival)
    }

    @Test("POC pacing keeps a long real-world route watchable")
    func proofOfConceptJourneyPacing() async {
        let route = makeRoute(length: 80_000)
        let clock = ManualSimulationClock()
        let session = makeSession(route: route, clock: clock)
        await createPreview(in: session)
        session.confirmPreview()

        clock.advance(by: 2.5)
        #expect(session.phase == .operating)

        clock.advance(by: 16)
        #expect(abs(session.trains[0].distanceAlongRoute - 40_000) < 0.000_001)

        clock.advance(by: 16)
        #expect(session.trains[0].distanceAlongRoute == 80_000)
        #expect(session.trains[0].direction == .reverse)
        #expect(session.trains[0].dwellRemaining == 2)
    }

    @Test("Cancelled route results cannot overwrite a newer request")
    func staleRouteResultIsIgnored() async {
        let provider = ControlledRoutingProvider()
        let session = GameSession(
            stations: [origin, destination, alternateDestination],
            routingProvider: provider,
            clock: ManualSimulationClock(),
            configuration: .poc
        )

        session.startBuilding()
        session.selectStation(origin)
        session.selectStation(destination)
        #expect(await waitForRequests(1, in: provider))

        session.cancelBuild()
        session.startBuilding()
        session.selectStation(origin)
        session.selectStation(alternateDestination)
        #expect(await waitForRequests(2, in: provider))

        await provider.succeedOldest(with: makeRoute(length: 1_000))
        await Task.yield()
        #expect(session.phase == .calculating)
        #expect(session.preview == nil)

        await provider.succeedOldest(with: makeRoute(length: 2_000))
        await session.waitForRouteCalculation()

        #expect(session.phase == .preview)
        #expect(session.preview?.destination == alternateDestination)
        #expect(session.preview?.distanceMetres == 2_000)
    }

    @Test("Routing failures enter a recoverable error state")
    func routeFailureRecovery() async {
        let session = GameSession(
            stations: [origin, destination],
            routingProvider: FailingRoutingProvider(),
            clock: ManualSimulationClock(),
            configuration: .poc
        )

        session.startBuilding()
        session.selectStation(origin)
        session.selectStation(destination)
        await session.waitForRouteCalculation()

        #expect(session.phase == .error)
        #expect(session.errorMessage == "The test route is unavailable.")

        session.dismissError()
        #expect(session.phase == .selectingDestination)
        #expect(session.selectedOrigin == origin)
        #expect(session.errorMessage == nil)
    }

    @Test("The POC enforces two lines and reset clears transient state")
    func lineLimitSelectionAndReset() async {
        let route = makeRoute(length: 100)
        let session = GameSession(
            stations: [origin, destination, alternateDestination],
            routingProvider: FixedRoutingProvider(route: route),
            clock: ManualSimulationClock(),
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 10,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000
            )
        )

        await createAndConfirmLine(in: session)
        await createAndConfirmLine(
            in: session,
            origin: destination,
            destination: alternateDestination
        )

        #expect(session.lines.count == 2)
        #expect(!session.canBuildAnotherLine)
        #expect(session.passengerSnapshot.station(forCRS: destination.crs)?.connectedLineCount == 2)
        #expect(
            session.passengerSnapshot.station(forCRS: destination.crs)?
                .connectedDestinationCount == 2
        )

        let trainID = session.trains[0].id
        session.selectTrain(trainID)
        session.setFollowingSelectedTrain(true)
        #expect(session.selectedTrainID == trainID)
        #expect(session.isFollowingSelectedTrain)

        session.startBuilding()
        #expect(session.phase == .error)
        #expect(session.errorMessage?.contains("up to 2 lines") == true)

        session.dismissError()
        #expect(session.phase == .operating)

        session.reset()
        #expect(session.phase == .idle)
        #expect(session.lines.isEmpty)
        #expect(session.selectedTrainID == nil)
        #expect(!session.isFollowingSelectedTrain)
        #expect(session.isPlaying)
        #expect(session.simulationSpeed == .oneX)
        #expect(session.stationProgressByCRS.isEmpty)
        #expect(session.economySnapshot == .zero)
        #expect(session.economyLedger == .zero)
        #expect(session.stationUpgradeEvent == nil)
    }

    @Test("A new service starts with projected demand and an evenly spaced fleet")
    func defaultPassengerService() async throws {
        let route = makeRoute(length: 80_000)
        let session = makeSession(
            route: route,
            clock: ManualSimulationClock(),
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 10,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000
            )
        )

        await createAndConfirmLine(in: session)

        let line = try #require(session.lines.first)
        let passengers = try #require(session.passengerSnapshot.line(for: line.id))
        #expect(line.serviceFrequency == .halfHourly)
        #expect(line.trains.count == 2)
        #expect(abs(line.trains[0].distanceAlongRoute - 0) < 0.000_001)
        #expect(abs(line.trains[1].distanceAlongRoute - 80_000) < 0.000_001)
        #expect(line.trains[1].direction == .reverse)
        #expect(passengers.passengersPerDay > 0)
        #expect(passengers.unservedDailyJourneys >= 0)
        #expect(session.passengerSnapshot.station(forCRS: origin.crs) != nil)

        session.selectStationForInspection(origin.crs.lowercased())
        #expect(session.selectedStation == origin)
    }

    @Test("Frequency changes resize the fleet and update passenger projections")
    func frequencyUpdatesFleetAndDemand() async throws {
        let clock = ManualSimulationClock()
        let session = makeSession(
            route: makeRoute(length: 80_000),
            clock: clock,
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 10,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000
            )
        )
        await createAndConfirmLine(in: session)

        let lineID = try #require(session.lines.first?.id)
        let halfHourly = try #require(session.passengerSnapshot.line(for: lineID))
        let revision = session.persistenceRevision

        session.setServiceFrequency(.hourly, forLineID: lineID)
        let hourly = try #require(session.passengerSnapshot.line(for: lineID))
        #expect(session.lines[0].trains.count == 1)
        #expect(hourly.passengersPerDay < halfHourly.passengersPerDay)
        #expect(hourly.averageWaitMinutes > halfHourly.averageWaitMinutes)
        #expect(session.persistenceRevision == revision + 1)

        session.setServiceFrequency(.quarterHourly, forLineID: lineID)
        let quarterHourly = try #require(session.passengerSnapshot.line(for: lineID))
        #expect(session.lines[0].trains.count == 4)
        #expect(quarterHourly.passengersPerDay > halfHourly.passengersPerDay)
        #expect(quarterHourly.averageWaitMinutes < halfHourly.averageWaitMinutes)
        #expect(session.persistenceRevision == revision + 2)

        let projection = session.passengerSnapshot
        clock.advance(by: 5)
        #expect(session.passengerSnapshot == projection)
        session.togglePlayPause()
        clock.advance(by: 5)
        #expect(session.passengerSnapshot == projection)
    }

    @Test("Public-beta history and presentation events follow completed gameplay")
    func publicBetaHistoryAndPresentationEvents() async throws {
        let clock = ManualSimulationClock()
        let session = makeSession(
            route: makeRoute(length: 80_000),
            clock: clock,
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: 2,
                trainSpeedMetresPerSecond: 10,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000,
                operatingDayDuration: 30
            )
        )
        await createPreview(in: session)

        session.confirmPreview()
        let line = try #require(session.lines.first)
        let constructionEvent = try #require(session.latestPresentationEvent)
        #expect(
            constructionEvent.kind
                == .constructionStarted(lineID: line.id, railwayClass: .conventional)
        )

        clock.advance(by: 2)
        let openingEvent = try #require(session.latestPresentationEvent)
        #expect(openingEvent.sequence > constructionEvent.sequence)
        #expect(
            openingEvent.kind == .lineOpened(lineID: line.id, railwayClass: .conventional)
        )
        #expect(
            session.presentationEvents(after: 0).map(\.kind) == [
                .constructionStarted(lineID: line.id, railwayClass: .conventional),
                .lineOpened(lineID: line.id, railwayClass: .conventional),
            ]
        )

        let settledOperatingResult = session.economySnapshot.operatingResultPencePerDay
        clock.advance(by: 30)
        let dailyRecord = try #require(session.publicBetaHistory.latestRecord)
        #expect(dailyRecord.operatingDay == 1)
        #expect(dailyRecord.facts.completedLineCount == 1)
        #expect(dailyRecord.facts.stationCount == 2)
        #expect(dailyRecord.facts.passengersPerDay == Int64(session.passengerSnapshot.passengersPerDay))
        #expect(dailyRecord.operatingResultPence == settledOperatingResult)
        #expect(session.makeSaveSnapshot().publicBetaHistory == session.publicBetaHistory)

        let dayEvent = try #require(session.latestPresentationEvent)
        #expect(dayEvent.sequence > openingEvent.sequence)
        #expect(
            dayEvent.kind
                == .operatingDayCompleted(
                    day: 1,
                    operatingResultPence: settledOperatingResult
                )
        )

        session.reset()
        #expect(session.publicBetaHistory.records.isEmpty)
        #expect(session.latestPresentationEvent == nil)
    }

    @Test("Operating days settle the economy and promote stations from served visits")
    func operatingDaySettlementAndStationPromotion() async throws {
        let clock = ManualSimulationClock()
        let session = makeSession(
            route: makeRoute(length: 80_000),
            clock: clock,
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 10,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000,
                operatingDayDuration: 30
            )
        )
        await createAndConfirmLine(in: session)

        let dailyPassengers = try #require(
            session.passengerSnapshot.station(forCRS: origin.crs)?.servedDailyJourneys
        )
        let dailyEconomy = session.economySnapshot
        #expect(dailyPassengers > 0)
        #expect(dailyEconomy.totalRevenuePencePerDay > 0)
        #expect(dailyEconomy.totalOperatingCostPencePerDay > 0)

        clock.advance(by: 30)
        #expect(session.economyLedger.completedOperatingDays == 1)
        #expect(session.economyLedger.operatingDayProgress == 0)
        #expect(session.economyLedger.lifetimeRevenuePence == dailyEconomy.totalRevenuePencePerDay)
        #expect(
            session.economyLedger.lifetimeOperatingCostPence
                == dailyEconomy.totalOperatingCostPencePerDay
        )
        #expect(
            session.stationProgressByCRS[origin.crs]?.lifetimePassengerVisits
                == Int64(dailyPassengers)
        )
        #expect(session.stationProgressByCRS[origin.crs]?.level == .halt)

        clock.advance(by: 30)
        #expect(session.economyLedger.completedOperatingDays == 2)
        #expect(session.stationProgressByCRS[origin.crs]?.level == .halt)

        clock.advance(by: 30)
        #expect(session.economyLedger.completedOperatingDays == 3)
        #expect(session.stationProgressByCRS[origin.crs]?.level == .localStation)
        #expect(session.stationProgressByCRS[destination.crs]?.level == .localStation)
        #expect(session.stationUpgradeEvent?.stationCRS == destination.crs)
        #expect(session.stationUpgradeEvent?.level == .localStation)

        let ledger = session.economyLedger
        let progress = session.stationProgressByCRS
        session.togglePlayPause()
        clock.advance(by: 90)
        #expect(session.economyLedger == ledger)
        #expect(session.stationProgressByCRS == progress)
    }

    @Test("Pause and resume preserve partial operating-day progress")
    func pauseResumePreservesOperatingDayProgress() async {
        let clock = ManualSimulationClock()
        let session = makeSession(
            route: makeRoute(length: 80_000),
            clock: clock,
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 10,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000,
                operatingDayDuration: 30
            )
        )
        await createAndConfirmLine(in: session)

        clock.advance(by: 7)
        let partialProgress = session.economyLedger.operatingDayProgress
        session.togglePlayPause()
        clock.advance(by: 100)
        #expect(session.economyLedger.operatingDayProgress == partialProgress)
        #expect(session.economyLedger.completedOperatingDays == 0)

        session.togglePlayPause()
        clock.advance(by: 23)
        #expect(session.economyLedger.completedOperatingDays == 1)
        #expect(session.economyLedger.operatingDayProgress == 0)
    }

    @Test("Three-times speed settles the same operating history as normal speed")
    func operatingDaySpeedEquivalence() async {
        let normalClock = ManualSimulationClock()
        let fastClock = ManualSimulationClock()
        let configuration = GameConfiguration(
            maximumLineCount: 2,
            constructionDuration: 0,
            trainSpeedMetresPerSecond: 10,
            terminalDwellDuration: 2,
            indicativeCostPerKilometre: 1_500_000,
            operatingDayDuration: 30
        )
        let normalSession = makeSession(
            route: makeRoute(length: 80_000),
            clock: normalClock,
            configuration: configuration
        )
        let fastSession = makeSession(
            route: makeRoute(length: 80_000),
            clock: fastClock,
            configuration: configuration
        )
        await createAndConfirmLine(in: normalSession)
        await createAndConfirmLine(in: fastSession)

        normalClock.advance(by: 60)
        fastSession.setSimulationSpeed(.threeX)
        fastClock.advance(by: 20)

        #expect(normalSession.economyLedger == fastSession.economyLedger)
        #expect(normalSession.stationProgressByCRS == fastSession.stationProgressByCRS)
        #expect(
            normalSession.stationUpgradeEvent?.stationCRS
                == fastSession.stationUpgradeEvent?.stationCRS
        )
        #expect(
            normalSession.stationUpgradeEvent?.level
                == fastSession.stationUpgradeEvent?.level
        )
    }

    @Test("Frequency is an immediate passenger and operating-cost tradeoff")
    func frequencyUpdatesOperatingForecast() async throws {
        let session = makeSession(
            route: makeRoute(length: 80_000),
            clock: ManualSimulationClock(),
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 10,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000,
                operatingDayDuration: 30
            )
        )
        await createAndConfirmLine(in: session)

        let lineID = try #require(session.lines.first?.id)
        let halfHourly = try #require(session.economySnapshot(forLineID: lineID))
        session.setServiceFrequency(.hourly, forLineID: lineID)
        let hourly = try #require(session.economySnapshot(forLineID: lineID))
        session.setServiceFrequency(.quarterHourly, forLineID: lineID)
        let quarterHourly = try #require(session.economySnapshot(forLineID: lineID))

        #expect(hourly.revenuePencePerDay < halfHourly.revenuePencePerDay)
        #expect(hourly.trainOperatingCostPencePerDay < halfHourly.trainOperatingCostPencePerDay)
        #expect(quarterHourly.revenuePencePerDay > halfHourly.revenuePencePerDay)
        #expect(
            quarterHourly.trainOperatingCostPencePerDay
                > halfHourly.trainOperatingCostPencePerDay
        )
        #expect(quarterHourly.trackUpkeepPencePerDay == halfHourly.trackUpkeepPencePerDay)
    }

    @Test("A timetable change preserves the current operating day")
    func timetableChangePreservesOperatingDay() async throws {
        let clock = ManualSimulationClock()
        let session = makeSession(
            route: makeRoute(length: 80_000),
            clock: clock,
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 10,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000,
                operatingDayDuration: 30
            )
        )
        await createAndConfirmLine(in: session)

        clock.advance(by: 29)
        #expect(session.economyLedger.operatingDayProgress > 0.96)
        let progressBeforeChange = session.economyLedger.operatingDayProgress
        let lineID = try #require(session.lines.first?.id)
        session.setServiceFrequency(.quarterHourly, forLineID: lineID)
        #expect(session.economyLedger.operatingDayProgress == progressBeforeChange)
        #expect(session.economyLedger.completedOperatingDays == 0)
        let expectedSettlementRevenue = session.economySnapshot.totalRevenuePencePerDay

        clock.advance(by: 1)
        #expect(session.economyLedger.completedOperatingDays == 1)
        #expect(session.economyLedger.lifetimeRevenuePence == expectedSettlementRevenue)
        #expect(session.economySnapshot.totalRevenuePencePerDay >= expectedSettlementRevenue)
    }

    @Test("A newly opened line starts a fresh operating day")
    func newlyOpenedLineRestartsOperatingDay() async {
        let clock = ManualSimulationClock()
        let session = GameSession(
            stations: [origin, destination, alternateDestination],
            routingProvider: FixedRoutingProvider(route: makeRoute(length: 80_000)),
            clock: clock,
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: 10,
                trainSpeedMetresPerSecond: 10,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000,
                operatingDayDuration: 30
            )
        )
        await createPreview(in: session)
        session.confirmPreview()
        clock.advance(by: 10)
        #expect(session.phase == .operating)
        clock.advance(by: 5)
        #expect(abs(session.economyLedger.operatingDayProgress - 1.0 / 6.0) < 0.000_001)

        session.startBuilding()
        session.selectStation(destination)
        session.selectStation(alternateDestination)
        await session.waitForRouteCalculation()
        #expect(session.phase == .preview)
        session.confirmPreview()
        #expect(session.phase == .constructing)
        clock.advance(by: 10)

        #expect(session.phase == .operating)
        #expect(session.economyLedger.completedOperatingDays == 0)
        #expect(session.economyLedger.operatingDayProgress == 0)
    }

    @Test("Large and partitioned ticks preserve the same day remainder")
    func operatingDayTickPartitionEquivalence() async {
        let largeClock = ManualSimulationClock()
        let slicedClock = ManualSimulationClock()
        let configuration = GameConfiguration(
            maximumLineCount: 2,
            constructionDuration: 0,
            trainSpeedMetresPerSecond: 10,
            terminalDwellDuration: 2,
            indicativeCostPerKilometre: 1_500_000,
            operatingDayDuration: 30
        )
        let large = makeSession(
            route: makeRoute(length: 80_000),
            clock: largeClock,
            configuration: configuration
        )
        let sliced = makeSession(
            route: makeRoute(length: 80_000),
            clock: slicedClock,
            configuration: configuration
        )
        await createAndConfirmLine(in: large)
        await createAndConfirmLine(in: sliced)

        largeClock.advance(by: 65)
        for _ in 0..<65 {
            slicedClock.advance(by: 1)
        }

        #expect(large.economyLedger.completedOperatingDays == 2)
        #expect(large.economyLedger.lifetimeRevenuePence == sliced.economyLedger.lifetimeRevenuePence)
        #expect(
            abs(
                large.economyLedger.operatingDayProgress
                    - sliced.economyLedger.operatingDayProgress
            ) < 0.000_001
        )
        #expect(large.stationProgressByCRS == sliced.stationProgressByCRS)
    }

    @Test("An extreme finite clock delta is bounded and returns")
    func extremeTickIsBounded() async {
        let clock = ManualSimulationClock()
        let session = makeSession(
            route: makeRoute(length: 80_000),
            clock: clock,
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 10,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000,
                operatingDayDuration: 30
            )
        )
        await createAndConfirmLine(in: session)

        clock.advance(by: .greatestFiniteMagnitude)

        #expect(session.economyLedger.completedOperatingDays == 120)
        #expect(session.economyLedger.operatingDayProgress == 0)
        #expect(session.stationProgressByCRS[origin.crs]?.level == .majorStation)
    }

    @Test("Tiny positive operating-day durations cannot make an extreme tick unbounded")
    func tinyOperatingDayDurationsAreBounded() async {
        for operatingDayDuration in [
            TimeInterval.leastNonzeroMagnitude,
            TimeInterval(0.000_001),
        ] {
            let clock = ManualSimulationClock()
            let session = makeSession(
                route: makeRoute(length: 80_000),
                clock: clock,
                configuration: GameConfiguration(
                    maximumLineCount: 2,
                    constructionDuration: 0,
                    trainSpeedMetresPerSecond: 10,
                    terminalDwellDuration: 2,
                    indicativeCostPerKilometre: 1_500_000,
                    operatingDayDuration: operatingDayDuration
                )
            )
            await createAndConfirmLine(in: session)

            clock.advance(by: .greatestFiniteMagnitude)

            #expect(session.economyLedger.completedOperatingDays == 120)
            #expect(session.economyLedger.operatingDayProgress == 0)
        }
    }

    @Test("Very large route values saturate instead of trapping")
    func largeRouteValuesSaturate() async throws {
        let route = makeRoute(length: Double(Int64.max))
        let session = makeSession(
            route: route,
            clock: ManualSimulationClock(),
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 10,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: .max,
                operatingDayDuration: 30
            )
        )

        await createPreview(in: session)
        #expect(session.preview?.indicativeCost == .max)
        session.confirmPreview()
        let lineID = try #require(session.lines.first?.id)
        #expect(session.economySnapshot(forLineID: lineID) != nil)
    }

    @Test("Station upgrade notices are queued once in stable station order")
    func stationUpgradeEventQueue() async throws {
        let clock = ManualSimulationClock()
        let session = makeSession(
            route: makeRoute(length: 80_000),
            clock: clock,
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 10,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000,
                operatingDayDuration: 30
            )
        )
        await createAndConfirmLine(in: session)
        clock.advance(by: 90)

        let first = try #require(session.stationUpgradeEvent)
        #expect(first.stationCRS == destination.crs)
        session.dismissStationUpgradeEvent(id: first.id)
        let second = try #require(session.stationUpgradeEvent)
        #expect(second.stationCRS == origin.crs)
        session.dismissStationUpgradeEvent(id: second.id)
        #expect(session.stationUpgradeEvent == nil)

        clock.advance(by: 1)
        #expect(session.stationUpgradeEvent == nil)
    }

    @Test("Reset clears both visible and queued station upgrade notices")
    func resetClearsQueuedUpgradeNotices() async throws {
        let clock = ManualSimulationClock()
        let session = makeSession(
            route: makeRoute(length: 80_000),
            clock: clock,
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 10,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000,
                operatingDayDuration: 30
            )
        )
        await createAndConfirmLine(in: session)
        clock.advance(by: 90)
        let oldNotice = try #require(session.stationUpgradeEvent)

        session.reset()
        #expect(session.stationUpgradeEvent == nil)
        session.dismissStationUpgradeEvent(id: oldNotice.id)
        #expect(session.stationUpgradeEvent == nil)

        await createAndConfirmLine(in: session)
        clock.advance(by: 90)
        let firstNewNotice = try #require(session.stationUpgradeEvent)
        session.dismissStationUpgradeEvent(id: firstNewNotice.id)
        let secondNewNotice = try #require(session.stationUpgradeEvent)
        session.dismissStationUpgradeEvent(id: secondNewNotice.id)
        #expect(session.stationUpgradeEvent == nil)
    }

    @Test("A reverse duplicate connection is rejected before routing")
    func duplicateConnectionRejected() async {
        let session = makeSession(
            route: makeRoute(length: 100),
            clock: ManualSimulationClock(),
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 10,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000
            )
        )
        await createAndConfirmLine(in: session)

        session.startBuilding()
        session.selectStation(destination)
        session.selectStation(origin)

        #expect(session.phase == .error)
        #expect(session.errorMessage?.contains("already has a service") == true)
        #expect(session.lines.count == 1)
    }

    @Test("Frequency changes preserve the lead train and phase fleets around the shuttle cycle")
    func frequencyRephasesWholeCycleWithoutTeleportingLeadTrain() async throws {
        let clock = ManualSimulationClock()
        let session = makeSession(
            route: makeRoute(length: 100),
            clock: clock,
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 10,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000
            )
        )
        await createAndConfirmLine(in: session)

        clock.advance(by: 10)
        let lineID = try #require(session.lines.first?.id)
        let leadID = try #require(session.lines.first?.trains.first?.id)
        #expect(session.lines[0].trains[0].distanceAlongRoute == 100)
        #expect(session.lines[0].trains[0].direction == .reverse)
        #expect(session.lines[0].trains[0].dwellRemaining == 2)

        session.setServiceFrequency(.quarterHourly, forLineID: lineID)

        let fleet = session.lines[0].trains
        #expect(fleet.count == 4)
        #expect(fleet[0].id == leadID)
        #expect(fleet[0].distanceAlongRoute == 100)
        #expect(fleet[0].direction == .reverse)
        #expect(fleet[0].dwellRemaining == 2)
        #expect(abs(fleet[1].distanceAlongRoute - 60) < 0.000_001)
        #expect(fleet[1].direction == .reverse)
        #expect(fleet[2].distanceAlongRoute == 0)
        #expect(fleet[2].direction == .forward)
        #expect(fleet[2].dwellRemaining == 2)
        #expect(abs(fleet[3].distanceAlongRoute - 40) < 0.000_001)
        #expect(fleet[3].direction == .forward)

        clock.advance(by: 5)
        let advancedFleet = session.lines[0].trains
        let expectedDistances: [Double] = [70, 10, 30, 90]
        for (train, expectedDistance) in zip(advancedFleet, expectedDistances) {
            #expect(abs(train.distanceAlongRoute - expectedDistance) < 0.000_001)
        }
    }

    @Test("Inactive scene time is excluded from simulation progress")
    func inactiveSceneSuspendsClock() async throws {
        let clock = ManualSimulationClock()
        let session = makeSession(
            route: makeRoute(length: 100),
            clock: clock,
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 10,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000
            )
        )
        await createAndConfirmLine(in: session)

        session.setSceneActive(false)
        #expect(clock.isSuspended)
        clock.advance(by: 100)
        #expect(session.lines[0].trains[0].distanceAlongRoute == 0)

        session.setSceneActive(true)
        #expect(!clock.isSuspended)
        clock.advance(by: 1)
        #expect(session.lines[0].trains[0].distanceAlongRoute == 10)
    }

    private var origin: Station {
        Station(crs: "VIC", name: "London Victoria", latitude: 51.4952, longitude: -0.1441)
    }

    private var destination: Station {
        Station(crs: "BTN", name: "Brighton", latitude: 50.829, longitude: -0.141)
    }

    private var alternateDestination: Station {
        Station(crs: "GTW", name: "Gatwick Airport", latitude: 51.1565, longitude: -0.161)
    }

    private func makeRoute(length: CLLocationDistance) -> ServiceRailwayRoute {
        ServiceRailwayRoute(
            coordinates: [
                CLLocationCoordinate2D(latitude: 51, longitude: -0.1),
                CLLocationCoordinate2D(latitude: 51, longitude: 0.1),
            ],
            cumulativeDistances: [0, length],
            stationCoordinateIndices: [0, 1]
        )
    }

    private func makeSession(
        route: ServiceRailwayRoute,
        clock: ManualSimulationClock,
        configuration: GameConfiguration = .poc
    ) -> GameSession {
        GameSession(
            stations: [origin, destination],
            routingProvider: FixedRoutingProvider(route: route),
            // This suite isolates the pre-existing session behaviours. Dedicated station-
            // capacity integration coverage exercises the default platform limits.
            stationCapacitySimulation: StationCapacitySimulation(
                configuration: StationCapacityConfiguration(
                    trainCallsPerPlatformPerHour: 1_000_000
                )
            ),
            clock: clock,
            configuration: configuration
        )
    }

    private func createPreview(in session: GameSession) async {
        session.startBuilding()
        session.selectStation(origin)
        session.selectStation(destination)
        await session.waitForRouteCalculation()
        #expect(session.phase == .preview)
    }

    private func createAndConfirmLine(in session: GameSession) async {
        await createPreview(in: session)
        session.confirmPreview()
        #expect(session.phase == .operating)
    }

    private func createAndConfirmLine(
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

    private func waitForRequests(
        _ count: Int,
        in provider: ControlledRoutingProvider
    ) async -> Bool {
        for _ in 0..<100 {
            if await provider.requestCount == count { return true }
            await Task.yield()
        }
        return false
    }
}

private nonisolated struct FixedRoutingProvider: RailwayRouteProviding {
    let route: ServiceRailwayRoute

    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        route
    }
}

private nonisolated struct FailingRoutingProvider: RailwayRouteProviding {
    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        throw StubRoutingError.unavailable
    }
}

private nonisolated enum StubRoutingError: LocalizedError {
    case unavailable

    var errorDescription: String? { "The test route is unavailable." }
}

private actor ControlledRoutingProvider: RailwayRouteProviding {
    private struct PendingRequest {
        let continuation: CheckedContinuation<ServiceRailwayRoute, any Error>
    }

    private var pendingRequests = [PendingRequest]()
    private(set) var requestCount = 0

    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        requestCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests.append(PendingRequest(continuation: continuation))
        }
    }

    func succeedOldest(with route: ServiceRailwayRoute) {
        pendingRequests.removeFirst().continuation.resume(returning: route)
    }
}

@MainActor
private final class ManualSimulationClock: SimulationClock {
    private var tickHandler: (@MainActor (TimeInterval) -> Void)?
    private(set) var isRunning = false
    private(set) var isSuspended = false

    func start(tick: @escaping @MainActor (TimeInterval) -> Void) {
        tickHandler = tick
        isRunning = true
    }

    func stop() {
        tickHandler = nil
        isRunning = false
    }

    func setSuspended(_ isSuspended: Bool) {
        self.isSuspended = isSuspended
    }

    func advance(by delta: TimeInterval) {
        guard !isSuspended else { return }
        tickHandler?(delta)
    }
}
