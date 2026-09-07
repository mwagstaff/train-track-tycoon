import CoreLocation
import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Game session high-speed rail", .serialized)
@MainActor
struct GameSessionHighSpeedTests {
    @Test("A route preview can switch infrastructure class and expose the complete HSR quote")
    func previewSwitchingAndQuote() async throws {
        let session = makeSession(routeLength: 80_000)
        await createPreview(in: session)

        let previewID = try #require(session.preview?.id)
        let conventionalJourneyMinutes = try #require(session.previewEstimatedJourneyMinutes)
        let conventionalQuote = try #require(session.previewCapitalQuote)
        #expect(session.preview?.railwayClass == .conventional)
        #expect(session.previewHighSpeedInvestmentQuote == nil)
        #expect(session.previewProjectedPrestigeGain == 0)
        #expect(conventionalQuote.trackAndInfrastructurePence == 12_000_000_000)
        #expect(conventionalQuote.stationConstructionPence == 400_000_000)
        #expect(conventionalQuote.rollingStockPence == 800_000_000)
        #expect(conventionalQuote.totalPence == 13_200_000_000)

        session.setPreviewRailwayClass(.highSpeed)

        let highSpeedQuote = try #require(session.previewHighSpeedInvestmentQuote)
        let capitalQuote = try #require(session.previewCapitalQuote)
        let highSpeedJourneyMinutes = try #require(session.previewEstimatedJourneyMinutes)
        #expect(session.preview?.id == previewID)
        #expect(session.preview?.railwayClass == .highSpeed)
        #expect(highSpeedQuote.conventionalTrackReferencePence == 12_000_000_000)
        #expect(highSpeedQuote.trackAndInfrastructurePence == 36_000_000_000)
        #expect(highSpeedQuote.premiumStationUpgradesPence == 4_000_000_000)
        #expect(highSpeedQuote.rollingStockPence == 4_000_000_000)
        #expect(highSpeedQuote.totalPence == 44_000_000_000)
        #expect(capitalQuote.trackAndInfrastructurePence == 36_000_000_000)
        #expect(capitalQuote.stationConstructionPence == 4_000_000_000)
        #expect(capitalQuote.rollingStockPence == 4_000_000_000)
        #expect(capitalQuote.totalPence == highSpeedQuote.totalPence)
        #expect(highSpeedJourneyMinutes < conventionalJourneyMinutes)
        #expect(session.previewProjectedPrestigeGain == 25)

        session.setPreviewRailwayClass(.conventional)

        #expect(session.preview?.id == previewID)
        #expect(session.preview?.railwayClass == .conventional)
        #expect(session.previewHighSpeedInvestmentQuote == nil)
        #expect(session.previewCapitalQuote == conventionalQuote)
        #expect(session.previewProjectedPrestigeGain == 0)
        #expect(session.previewEstimatedJourneyMinutes == conventionalJourneyMinutes)
    }

    @Test("Zen construction creates a dedicated express double-track HSR service")
    func zenConstructionDefaults() async throws {
        let session = makeSession(routeLength: 80_000)
        await createHighSpeedPreview(in: session)
        let quote = try #require(session.previewHighSpeedInvestmentQuote)

        session.confirmPreview()

        let line = try #require(session.lines.first)
        let operations = try #require(session.operationsSnapshot(forLineID: line.id))
        let savedLine = try #require(session.makeSaveSnapshot().lines.first)
        #expect(session.phase == .operating)
        #expect(line.railwayClass == .highSpeed)
        #expect(line.servicePattern == .express)
        #expect(line.trackCapacity == .doubleTrack)
        #expect(line.serviceFrequency == .halfHourly)
        #expect(line.ownedTrainCount == 2)
        #expect(line.trains.count == 2)
        #expect(operations.railwayClass == .highSpeed)
        #expect(operations.servicePattern == .express)
        #expect(operations.trackCapacity == .doubleTrack)
        #expect(operations.localTrainCount == 0)
        #expect(operations.expressTrainCount == 2)
        #expect(operations.advertisedMaximumSpeedMilesPerHour == 215)
        #expect(abs(operations.journeyTimeMultiplier - 0.55) < 0.000_000_001)
        #expect(line.trains.allSatisfy { session.trainServiceRole(for: $0.id) == .express })
        #expect(session.premiumHighSpeedStationCRSs == [origin.crs, destination.crs])
        #expect(session.activePremiumHighSpeedStationCRSs == [origin.crs, destination.crs])
        #expect(session.financeLedger.cashBalancePence == 0)
        #expect(session.financeLedger.lifetimeConstructionSpendPence == quote.constructionPence)
        #expect(session.financeLedger.lifetimeRollingStockSpendPence == quote.rollingStockPence)
        #expect(savedLine.railwayClass == .highSpeed)
        #expect(savedLine.servicePattern == .express)
        #expect(savedLine.trackCapacity == .doubleTrack)
    }

    @Test("An unaffordable Career HSR build leaves network and finances untouched")
    func careerInsufficientFundsIsAtomic() async throws {
        let session = makeSession(routeLength: 80_000, mode: .career)
        await createHighSpeedPreview(in: session)
        let quote = try #require(session.previewHighSpeedInvestmentQuote)
        let financeBeforeFailure = session.financeLedger
        let snapshotBeforeFailure = session.makeSaveSnapshot()
        let revisionBeforeFailure = session.persistenceRevision

        #expect(quote.totalPence == 44_000_000_000)
        #expect(session.financeLedger.cashBalancePence == 15_000_000_000)
        #expect(!session.canAffordPreview)
        #expect(session.previewFundingShortfallPence == 29_000_000_000)

        session.confirmPreview()

        #expect(session.lines.isEmpty)
        #expect(session.financeLedger == financeBeforeFailure)
        #expect(session.makeSaveSnapshot().lines == snapshotBeforeFailure.lines)
        #expect(session.makeSaveSnapshot().financialState == snapshotBeforeFailure.financialState)
        #expect(session.persistenceRevision == revisionBeforeFailure)
        #expect(session.prestigeSnapshot.score == 0)
        #expect(session.premiumHighSpeedStationCRSs.isEmpty)
        #expect(session.phase == .error)
        #expect(session.errorMessage?.contains("more funding") == true)
        #expect(session.preview?.railwayClass == .highSpeed)
    }

    @Test("A high-speed train visibly outruns a conventional train on the same route")
    func highSpeedMovementIsVisiblyFaster() async throws {
        let conventionalClock = HighSpeedManualClock()
        let highSpeedClock = HighSpeedManualClock()
        let conventional = makeSession(routeLength: 10_000, clock: conventionalClock)
        let highSpeed = makeSession(routeLength: 10_000, clock: highSpeedClock)

        await createPreview(in: conventional)
        conventional.confirmPreview()
        await createHighSpeedPreview(in: highSpeed)
        highSpeed.confirmPreview()

        conventionalClock.advance(by: 5)
        highSpeedClock.advance(by: 5)

        let conventionalDistance = try #require(
            conventional.lines.first?.trains.first?.distanceAlongRoute
        )
        let highSpeedDistance = try #require(
            highSpeed.lines.first?.trains.first?.distanceAlongRoute
        )
        #expect(abs(conventionalDistance - 50) < 0.000_001)
        #expect(highSpeedDistance > conventionalDistance * 2)
        #expect(highSpeedDistance < conventionalDistance * 2.2)
        #expect(
            highSpeed.operationsSnapshot(forLineID: highSpeed.lines[0].id)?
                .advertisedMaximumSpeedMilesPerHour == 215
        )
    }

    @Test("Prestige and active premium stations appear only when construction completes")
    func prestigeRequiresCompletion() async throws {
        let clock = HighSpeedManualClock()
        let session = makeSession(
            routeLength: 80_000,
            clock: clock,
            constructionDuration: 2
        )
        await createHighSpeedPreview(in: session)

        #expect(session.previewProjectedPrestigeGain == 25)
        #expect(session.prestigeSnapshot.score == 0)
        session.confirmPreview()

        #expect(session.phase == .constructing)
        #expect(session.lines.first?.constructionProgress == 0)
        #expect(session.premiumHighSpeedStationCRSs == [origin.crs, destination.crs])
        #expect(session.activePremiumHighSpeedStationCRSs.isEmpty)
        #expect(session.prestigeSnapshot.score == 0)

        clock.advance(by: 1)
        #expect(session.lines.first?.constructionProgress == 0.5)
        #expect(session.prestigeSnapshot.score == 0)
        #expect(session.activePremiumHighSpeedStationCRSs.isEmpty)

        clock.advance(by: 1)
        #expect(session.phase == .operating)
        #expect(session.lines.first?.constructionProgress == 1)
        #expect(session.prestigeSnapshot.score == 25)
        #expect(session.prestigeSnapshot.tier == .pioneer)
        #expect(session.prestigeSnapshot.completedCorridorCount == 1)
        #expect(session.prestigeSnapshot.premiumEndpointCount == 2)
        #expect(session.activePremiumHighSpeedStationCRSs == [origin.crs, destination.crs])
    }

    @Test("HSR rejects conventional service-pattern and capacity mutations")
    func incompatibleOperationsMutationsAreRejected() async throws {
        let session = makeSession(routeLength: 10_000)
        await createHighSpeedPreview(in: session)
        session.confirmPreview()
        let lineID = try #require(session.lines.first?.id)
        let savedLineBefore = try #require(session.makeSaveSnapshot().lines.first)
        let operationsBefore = try #require(session.operationsSnapshot(forLineID: lineID))
        let financeBefore = session.financeLedger
        let revisionBefore = session.persistenceRevision

        #expect(session.trackUpgradeCost(forLineID: lineID) == nil)
        session.setServicePattern(.local, forLineID: lineID)
        #expect(!session.upgradeTrackCapacity(forLineID: lineID))

        #expect(session.makeSaveSnapshot().lines.first == savedLineBefore)
        #expect(session.operationsSnapshot(forLineID: lineID) == operationsBefore)
        #expect(session.financeLedger == financeBefore)
        #expect(session.persistenceRevision == revisionBefore)
        #expect(session.lines.first?.servicePattern == .express)
        #expect(session.lines.first?.trackCapacity == .doubleTrack)
        #expect(session.phase == .operating)
        #expect(session.errorMessage == nil)
    }

    @Test("A Career frequency increase buys £20m high-speed trains without refunds")
    func highSpeedFrequencyPurchaseCost() async throws {
        let capitalEconomy = CapitalEconomy(configuration: capitalConfiguration(
            startingCashPence: 50_000_000_000
        ))
        let session = makeSession(
            routeLength: 80_000,
            mode: .career,
            capitalEconomy: capitalEconomy
        )
        await createHighSpeedPreview(in: session)
        session.confirmPreview()
        let lineID = try #require(session.lines.first?.id)
        let openingRollingStockSpend = session.financeLedger.lifetimeRollingStockSpendPence

        #expect(session.financeLedger.cashBalancePence == 6_000_000_000)
        #expect(openingRollingStockSpend == 4_000_000_000)
        #expect(session.rollingStockPurchaseCost(
            for: .quarterHourly,
            lineID: lineID
        ) == 4_000_000_000)

        session.setServiceFrequency(.quarterHourly, forLineID: lineID)

        #expect(session.lines.first?.serviceFrequency == .quarterHourly)
        #expect(session.lines.first?.ownedTrainCount == 4)
        #expect(session.lines.first?.trains.count == 4)
        #expect(session.financeLedger.cashBalancePence == 2_000_000_000)
        #expect(
            session.financeLedger.lifetimeRollingStockSpendPence
                == openingRollingStockSpend + 4_000_000_000
        )

        session.setServiceFrequency(.hourly, forLineID: lineID)
        let cashAfterReduction = session.financeLedger.cashBalancePence
        #expect(session.lines.first?.ownedTrainCount == 4)
        #expect(session.rollingStockPurchaseCost(
            for: .quarterHourly,
            lineID: lineID
        ) == 0)

        session.setServiceFrequency(.quarterHourly, forLineID: lineID)
        #expect(session.financeLedger.cashBalancePence == cashAfterReduction)
        #expect(session.financeLedger.lifetimeRollingStockSpendPence
            == openingRollingStockSpend + 4_000_000_000)
    }

    @Test("Schema-seven save and restore preserve a live high-speed corridor")
    func highSpeedSaveRestoreRoundTrip() async throws {
        let sourceClock = HighSpeedManualClock()
        let source = makeSession(routeLength: 1_000, clock: sourceClock)
        await createHighSpeedPreview(in: source)
        source.confirmPreview()
        let sourceLineID = try #require(source.lines.first?.id)
        source.setServiceFrequency(.quarterHourly, forLineID: sourceLineID)
        sourceClock.advance(by: 5)

        let snapshot = source.makeSaveSnapshot()
        let savedLine = try #require(snapshot.lines.first)
        #expect(snapshot.schemaVersion == GameSaveSnapshot.currentSchemaVersion)
        #expect(savedLine.railwayClass == .highSpeed)
        #expect(savedLine.servicePattern == .express)
        #expect(savedLine.trackCapacity == .doubleTrack)
        #expect(savedLine.frequency == .quarterHourly)
        #expect(savedLine.ownedTrainCount == 4)

        let restored = makeSession(
            routeLength: 1_000,
            clock: HighSpeedManualClock()
        )
        try await restored.restore(from: snapshot)

        let restoredLine = try #require(restored.lines.first)
        let restoredOperations = try #require(
            restored.operationsSnapshot(forLineID: restoredLine.id)
        )
        #expect(restoredLine.id == sourceLineID)
        #expect(restoredLine.railwayClass == .highSpeed)
        #expect(restoredLine.servicePattern == .express)
        #expect(restoredLine.trackCapacity == .doubleTrack)
        #expect(restoredLine.serviceFrequency == .quarterHourly)
        #expect(restoredLine.ownedTrainCount == 4)
        #expect(restoredLine.trains.count == 4)
        #expect(restoredLine.trains.map(\.id) == source.lines[0].trains.map(\.id))
        #expect(zip(restoredLine.trains, source.lines[0].trains).allSatisfy {
            abs($0.distanceAlongRoute - $1.distanceAlongRoute) < 0.000_001
        })
        #expect(restoredOperations.railwayClass == .highSpeed)
        #expect(restoredOperations.servicePattern == .express)
        #expect(restoredOperations.trackCapacity == .doubleTrack)
        #expect(restoredOperations.advertisedMaximumSpeedMilesPerHour == 215)
        #expect(restored.prestigeSnapshot.score == 25)
        #expect(restored.activePremiumHighSpeedStationCRSs == [origin.crs, destination.crs])
        #expect(restored.financeLedger == source.financeLedger)
        #expect(restored.economyLedger == source.economyLedger)
        #expect(restored.makeSaveSnapshot().lines == snapshot.lines)
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
            crs: "BTN",
            name: "Brighton",
            latitude: 50.829,
            longitude: -0.141
        )
    }

    private func makeSession(
        routeLength: CLLocationDistance,
        mode: GameMode = .zen,
        clock: HighSpeedManualClock? = nil,
        constructionDuration: TimeInterval = 0,
        capitalEconomy: CapitalEconomy = CapitalEconomy()
    ) -> GameSession {
        let resolvedClock = clock ?? HighSpeedManualClock()
        return GameSession(
            stations: [origin, destination],
            routingProvider: HighSpeedFixedRoutingProvider(
                route: makeRoute(length: routeLength)
            ),
            capitalEconomy: capitalEconomy,
            gameMode: mode,
            clock: resolvedClock,
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

    private func createPreview(in session: GameSession) async {
        session.startBuilding()
        session.selectStation(origin)
        session.selectStation(destination)
        await session.waitForRouteCalculation()
        #expect(session.phase == .preview)
    }

    private func createHighSpeedPreview(in session: GameSession) async {
        await createPreview(in: session)
        session.setPreviewRailwayClass(.highSpeed)
        #expect(session.preview?.railwayClass == .highSpeed)
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

private nonisolated struct HighSpeedFixedRoutingProvider: RailwayRouteProviding {
    let route: ServiceRailwayRoute

    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        route
    }
}

@MainActor
private final class HighSpeedManualClock: SimulationClock {
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
