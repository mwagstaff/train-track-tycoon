import CoreLocation
import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Game session rolling stock", .serialized)
@MainActor
struct GameSessionRollingStockTests {
    @Test("A route recommends a formation while preserving an explicit preview choice")
    func previewRecommendationAndOverride() async throws {
        let session = makeSession()
        await createPreview(from: westernStation, to: interchangeStation, in: session)

        let automatic = try #require(session.preview)
        let automaticQuote = try #require(session.previewCapitalQuote)
        #expect(automatic.formation == automatic.recommendedFormation)
        #expect(automatic.recommendedFormation == .eightCar)
        #expect(RollingStockFormation.supported(for: automatic.railwayClass)
            .contains(automatic.formation))

        session.setPreviewFormation(.twoCar)

        let overridden = try #require(session.preview)
        let overriddenQuote = try #require(session.previewCapitalQuote)
        #expect(overridden.id == automatic.id)
        #expect(overridden.formation == .twoCar)
        #expect(overridden.recommendedFormation == automatic.recommendedFormation)
        #expect(
            overridden.passengerEstimate.passengersPerDay
                < automatic.passengerEstimate.passengersPerDay
        )
        #expect(overriddenQuote.rollingStockPence < automaticQuote.rollingStockPence)

        session.confirmPreview()
        let line = try #require(session.lines.first)
        #expect(line.formation == .twoCar)
        #expect(session.trainCapacity(forLineID: line.id) == 80)
        #expect(session.trainFormationSnapshot(for: line.trains[0].id)?.carriageCount == 2)
    }

    @Test("Changing railway class keeps or clamps the player's formation and refreshes quotes")
    func railwayClassClampsFormation() async throws {
        let session = makeSession()
        await createPreview(from: westernStation, to: interchangeStation, in: session)
        session.setPreviewFormation(.twoCar)
        let conventional = try #require(session.preview)
        let conventionalQuote = try #require(session.previewCapitalQuote)

        session.setPreviewRailwayClass(.highSpeed)

        let highSpeed = try #require(session.preview)
        let highSpeedQuote = try #require(session.previewCapitalQuote)
        #expect(highSpeed.formation == .sixCar)
        #expect(highSpeed.recommendedFormation == .eightCar)
        #expect(highSpeed.passengerEstimate.journeyMinutes < conventional.passengerEstimate.journeyMinutes)
        #expect(highSpeedQuote != conventionalQuote)

        session.setPreviewFormation(.twoCar)
        #expect(session.preview?.formation == .sixCar)
        session.setPreviewFormation(.twelveCar)
        session.setPreviewRailwayClass(.conventional)
        #expect(session.preview?.formation == .twelveCar)
    }

    @Test("Purchased carriages drive line capacity, revenue and operating cost")
    func formationFlowsIntoPassengerAndEconomyInputs() async throws {
        let shortSession = makeSession()
        await buildLine(
            from: westernStation,
            to: interchangeStation,
            formation: .twoCar,
            in: shortSession
        )
        let longSession = makeSession()
        await buildLine(
            from: westernStation,
            to: interchangeStation,
            formation: .twelveCar,
            in: longSession
        )

        let shortLine = try #require(shortSession.lines.first)
        let longLine = try #require(longSession.lines.first)
        let shortPassengers = try #require(shortSession.passengerSnapshot(forLineID: shortLine.id))
        let longPassengers = try #require(longSession.passengerSnapshot(forLineID: longLine.id))
        let shortEconomy = try #require(shortSession.economySnapshot(forLineID: shortLine.id))
        let longEconomy = try #require(longSession.economySnapshot(forLineID: longLine.id))

        #expect(shortPassengers.dailyCapacity == 5_760)
        #expect(longPassengers.dailyCapacity == 34_560)
        #expect(shortPassengers.passengersPerDay < longPassengers.passengersPerDay)
        #expect(shortEconomy.revenuePencePerDay < longEconomy.revenuePencePerDay)
        #expect(shortEconomy.trainOperatingCostPencePerDay < longEconomy.trainOperatingCostPencePerDay)
        #expect(shortSession.financeSnapshot.rollingStockValuePence
            < longSession.financeSnapshot.rollingStockValuePence)
    }

    @Test("Formation extensions are atomic and commute with later trainset purchases")
    func atomicExtensionAndPurchaseOrdering() async throws {
        let beforeOpening = makeSession(constructionDuration: 10)
        await createPreview(from: westernStation, to: interchangeStation, in: beforeOpening)
        beforeOpening.setPreviewFormation(.twoCar)
        beforeOpening.confirmPreview()
        let constructingLine = try #require(beforeOpening.lines.first)
        let constructingFinance = beforeOpening.financeLedger
        let constructingRevision = beforeOpening.persistenceRevision
        #expect(!beforeOpening.extendFormation(forLineID: constructingLine.id))
        #expect(beforeOpening.lines.first?.formation == .twoCar)
        #expect(beforeOpening.financeLedger == constructingFinance)
        #expect(beforeOpening.persistenceRevision == constructingRevision)

        let extendThenBuy = makeSession()
        await buildLine(
            from: westernStation,
            to: interchangeStation,
            formation: .twoCar,
            in: extendThenBuy
        )
        let firstID = try #require(extendThenBuy.lines.first?.id)
        let firstPassengerCount = try #require(
            extendThenBuy.passengerSnapshot(forLineID: firstID)?.passengersPerDay
        )
        let extensionCost = try #require(
            extendThenBuy.formationExtensionCost(forLineID: firstID)
        )
        let spendBeforeExtension = extendThenBuy.financeLedger.lifetimeRollingStockSpendPence
        #expect(extendThenBuy.extendFormation(forLineID: firstID))
        #expect(extendThenBuy.lines.first?.formation == .fourCar)
        #expect(extendThenBuy.financeLedger.cashBalancePence == 0)
        #expect(
            extendThenBuy.financeLedger.lifetimeRollingStockSpendPence
                == spendBeforeExtension + extensionCost
        )
        #expect(
            extendThenBuy.passengerSnapshot(forLineID: firstID)?.passengersPerDay ?? 0
                > firstPassengerCount
        )
        extendThenBuy.setServiceFrequency(.quarterHourly, forLineID: firstID)

        let buyThenExtend = makeSession()
        await buildLine(
            from: westernStation,
            to: interchangeStation,
            formation: .twoCar,
            in: buyThenExtend
        )
        let secondID = try #require(buyThenExtend.lines.first?.id)
        buyThenExtend.setServiceFrequency(.quarterHourly, forLineID: secondID)
        #expect(buyThenExtend.extendFormation(forLineID: secondID))

        #expect(extendThenBuy.lines.first?.ownedTrainCount == 4)
        #expect(buyThenExtend.lines.first?.ownedTrainCount == 4)
        #expect(extendThenBuy.lines.first?.formation == .fourCar)
        #expect(buyThenExtend.lines.first?.formation == .fourCar)
        #expect(
            extendThenBuy.financeLedger.lifetimeRollingStockSpendPence
                == buyThenExtend.financeLedger.lifetimeRollingStockSpendPence
        )
        #expect(
            extendThenBuy.financeSnapshot.rollingStockValuePence
                == buyThenExtend.financeSnapshot.rollingStockValuePence
        )

        while extendThenBuy.formationExtensionCost(forLineID: firstID) != nil {
            #expect(extendThenBuy.extendFormation(forLineID: firstID))
        }
        let maximumFinance = extendThenBuy.financeLedger
        let maximumRevision = extendThenBuy.persistenceRevision
        #expect(extendThenBuy.lines.first?.formation == .twelveCar)
        #expect(extendThenBuy.formationExtensionCost(forLineID: firstID) == nil)
        #expect(!extendThenBuy.extendFormation(forLineID: firstID))
        #expect(extendThenBuy.financeLedger == maximumFinance)
        #expect(extendThenBuy.persistenceRevision == maximumRevision)
    }

    @Test("An unaffordable Career extension does not mutate the fleet or treasury")
    func careerExtensionAffordability() async throws {
        let capitalEconomy = CapitalEconomy(configuration: capitalConfiguration(
            startingCashPence: 800_000_000
        ))
        let session = makeSession(
            routeLength: 100,
            gameMode: .career,
            capitalEconomy: capitalEconomy
        )
        await buildLine(
            from: westernStation,
            to: interchangeStation,
            formation: .twoCar,
            in: session
        )
        let line = try #require(session.lines.first)
        let cost = try #require(session.formationExtensionCost(forLineID: line.id))
        #expect(cost > session.financeLedger.cashBalancePence)
        let originalFinance = session.financeLedger
        let originalRevision = session.persistenceRevision

        #expect(!session.extendFormation(forLineID: line.id))

        #expect(session.lines.first?.formation == .twoCar)
        #expect(session.financeLedger == originalFinance)
        #expect(session.persistenceRevision == originalRevision)
        #expect(session.phase == .error)
        #expect(session.errorMessage?.contains("more funding") == true)
    }

    @Test("The smaller train is the connecting capacity bottleneck")
    func connectingJourneyFormationBottleneck() async throws {
        let session = makeSession()
        await buildLine(
            from: westernStation,
            to: interchangeStation,
            formation: .twoCar,
            in: session
        )
        await buildLine(
            from: interchangeStation,
            to: easternStation,
            formation: .twelveCar,
            in: session
        )
        let constrainedLineID = try #require(session.lines.first?.id)
        let roomyLineID = try #require(session.lines.last?.id)
        let constrainedConnection = try #require(
            session.passengerSnapshot.connectingJourneySnapshots.first
        )
        #expect(constrainedConnection.passengersPerDay > 0)
        #expect(
            session.passengerSnapshot(forLineID: constrainedLineID)?.connectingPassengersPerDay
                == constrainedConnection.passengersPerDay
        )
        #expect(
            session.passengerSnapshot(forLineID: roomyLineID)?.connectingPassengersPerDay
                == constrainedConnection.passengersPerDay
        )

        #expect(session.extendFormation(forLineID: constrainedLineID))
        let improvedConnection = try #require(
            session.passengerSnapshot.connectingJourneySnapshots.first
        )
        #expect(improvedConnection.passengersPerDay > constrainedConnection.passengersPerDay)
        #expect(session.lines.last?.formation == .twelveCar)
    }

    @Test("Schema 11 restores the purchased formation exactly and later demand does not resize it")
    func formationPersistenceAndStability() async throws {
        let clock = RollingStockManualClock()
        let source = makeSession(clock: clock)
        await buildLine(
            from: westernStation,
            to: interchangeStation,
            formation: .fourCar,
            in: source
        )
        let lineID = try #require(source.lines.first?.id)
        #expect(source.extendFormation(forLineID: lineID))
        source.setServiceFrequency(.quarterHourly, forLineID: lineID)
        source.setServicePattern(.express, forLineID: lineID)
        clock.advance(by: 30)
        #expect(source.lines.first?.formation == .sixCar)

        let saved = source.makeSaveSnapshot()
        #expect(saved.schemaVersion == GameSaveSnapshot.currentSchemaVersion)
        #expect(saved.lines.first?.formation == .sixCar)
        let restored = makeSession()
        try await restored.restore(from: saved)

        let restoredLine = try #require(restored.lines.first)
        #expect(restoredLine.id == lineID)
        #expect(restoredLine.formation == .sixCar)
        #expect(restoredLine.serviceFrequency == .quarterHourly)
        #expect(restoredLine.servicePattern == .express)
        #expect(restoredLine.ownedTrainCount == 4)
        #expect(restored.trainCapacity(forLineID: lineID) == 240)
        #expect(restored.passengerSnapshot(forLineID: lineID)?.dailyCapacity == 34_560)
        #expect(restored.financeLedger == source.financeLedger)
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
        routeLength: CLLocationDistance = 35_000,
        constructionDuration: TimeInterval = 0,
        gameMode: GameMode = .zen,
        capitalEconomy: CapitalEconomy = CapitalEconomy(),
        clock: RollingStockManualClock? = nil
    ) -> GameSession {
        GameSession(
            stations: [westernStation, interchangeStation, easternStation],
            routingProvider: RollingStockRoutingProvider(route: route(length: routeLength)),
            // Rolling-stock tests vary seats while keeping endpoint throughput out of scope.
            stationCapacitySimulation: StationCapacitySimulation(
                configuration: StationCapacityConfiguration(
                    trainCallsPerPlatformPerHour: 1_000_000
                )
            ),
            capitalEconomy: capitalEconomy,
            gameMode: gameMode,
            clock: clock ?? RollingStockManualClock(),
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

    private func createPreview(
        from origin: Station,
        to destination: Station,
        in session: GameSession
    ) async {
        session.startBuilding()
        session.selectStation(origin)
        session.selectStation(destination)
        await session.waitForRouteCalculation()
        #expect(session.phase == .preview)
    }

    private func buildLine(
        from origin: Station,
        to destination: Station,
        formation: RollingStockFormation,
        in session: GameSession
    ) async {
        await createPreview(from: origin, to: destination, in: session)
        session.setPreviewFormation(formation)
        session.confirmPreview()
        #expect(session.phase == .operating || session.phase == .constructing)
    }

    private func route(length: CLLocationDistance) -> ServiceRailwayRoute {
        ServiceRailwayRoute(
            coordinates: [
                CLLocationCoordinate2D(latitude: 51, longitude: -0.1),
                CLLocationCoordinate2D(latitude: 51, longitude: 0.1),
            ],
            cumulativeDistances: [0, length],
            stationCoordinateIndices: [0, 1]
        )
    }

    private func capitalConfiguration(
        startingCashPence: Int64
    ) -> CapitalEconomyConfiguration {
        CapitalEconomyConfiguration(
            startingCashPence: startingCashPence,
            stationConstructionCostPence: 200_000_000,
            rollingStockUnitCostPence: 400_000_000,
            loanPrincipalPence: 4_000_000_000,
            earlyRepaymentPence: 1_000_000_000,
            loanAnnualInterestBasisPoints: 420,
            loanTermOperatingDays: 7_200,
            maximumConcurrentLoans: 3,
            insolvencyGraceOperatingDays: 7,
            lowCashThresholdPence: 1_000_000_000,
            stationValuePenceByLevel: Dictionary(
                uniqueKeysWithValues: StationLevel.allCases.map { ($0, 200_000_000) }
            )
        )
    }
}

private nonisolated struct RollingStockRoutingProvider: RailwayRouteProviding {
    let route: ServiceRailwayRoute

    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        route
    }
}

@MainActor
private final class RollingStockManualClock: SimulationClock {
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
