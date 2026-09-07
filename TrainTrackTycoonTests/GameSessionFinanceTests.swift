import CoreLocation
import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Game session finance", .serialized)
@MainActor
struct GameSessionFinanceTests {
    @Test("Career construction atomically charges track, stations and the opening fleet")
    func careerConstructionPurchase() async throws {
        let session = makeSession(routeLength: 80_000, mode: .career)

        await createPreview(in: session)
        let quote = try #require(session.previewCapitalQuote)
        #expect(quote.trackAndInfrastructurePence == 12_000_000_000)
        #expect(quote.stationConstructionPence == 400_000_000)
        #expect(quote.rollingStockPence == 800_000_000)
        #expect(quote.totalPence == 13_200_000_000)
        #expect(session.canAffordPreview)

        session.confirmPreview()

        #expect(session.lines.count == 1)
        #expect(session.lines[0].ownedTrainCount == 2)
        #expect(session.financeLedger.cashBalancePence == 1_800_000_000)
        #expect(session.financeLedger.lifetimeConstructionSpendPence == 12_400_000_000)
        #expect(session.financeLedger.lifetimeRollingStockSpendPence == 800_000_000)
    }

    @Test("An unaffordable Career build is a true network and treasury no-op")
    func unaffordableConstructionIsAtomic() async {
        let session = makeSession(routeLength: 200_000, mode: .career)
        await createPreview(in: session)
        let originalFinance = session.financeLedger
        let originalRevision = session.persistenceRevision

        #expect(!session.canAffordPreview)
        #expect(session.previewFundingShortfallPence == 16_200_000_000)
        session.confirmPreview()

        #expect(session.lines.isEmpty)
        #expect(session.financeLedger == originalFinance)
        #expect(session.persistenceRevision == originalRevision)
        #expect(session.phase == .error)
    }

    @Test("Frequency reductions retain purchased trains and later increases only buy the gap")
    func rollingStockOwnership() async throws {
        let session = makeSession(routeLength: 10_000, mode: .career)
        await createPreview(in: session)
        session.confirmPreview()
        let lineID = try #require(session.lines.first?.id)
        let openingSpend = session.financeLedger.lifetimeRollingStockSpendPence

        session.setServiceFrequency(.hourly, forLineID: lineID)
        #expect(session.lines[0].ownedTrainCount == 2)
        #expect(session.financeLedger.lifetimeRollingStockSpendPence == openingSpend)

        session.setServiceFrequency(.quarterHourly, forLineID: lineID)
        #expect(session.lines[0].ownedTrainCount == 4)
        #expect(
            session.financeLedger.lifetimeRollingStockSpendPence
                == openingSpend + 800_000_000
        )
        let cashAfterPurchase = session.financeLedger.cashBalancePence

        session.setServiceFrequency(.hourly, forLineID: lineID)
        session.setServiceFrequency(.quarterHourly, forLineID: lineID)
        #expect(session.financeLedger.cashBalancePence == cashAfterPurchase)
        #expect(session.lines[0].ownedTrainCount == 4)
    }

    @Test("An insolvent company can reduce frequency during its recovery grace period")
    func insolventCompanyCanReduceFrequency() async throws {
        let clock = FinanceManualClock()
        let capitalConfiguration = makeCapitalConfiguration(
            startingCashPence: 1_215_000_000,
            insolvencyGraceOperatingDays: 7
        )
        let deliberatelyLossMakingEconomy = OperatingEconomy(
            configuration: OperatingEconomyConfiguration(
                baseFarePencePerJourney: 0,
                farePencePerPassengerKilometre: 0,
                serviceHoursPerDay: 18,
                directionCount: 2,
                energyCostPencePerTrainKilometre: 100_000,
                variableRollingStockMaintenancePencePerTrainKilometre: 100_000,
                fixedRollingStockMaintenancePencePerAssignedTrainPerDay: 1_000_000,
                trackUpkeepPencePerKilometrePerDay: 1_000_000,
                stationUpkeepPencePerDayByLevel: Dictionary(
                    uniqueKeysWithValues: StationLevel.allCases.map { ($0, 1_000_000) }
                )
            )
        )
        let session = makeSession(
            routeLength: 100,
            mode: .career,
            clock: clock,
            capitalEconomy: CapitalEconomy(configuration: capitalConfiguration),
            operatingEconomy: deliberatelyLossMakingEconomy
        )
        await createPreview(in: session)
        session.confirmPreview()
        let lineID = try #require(session.lines.first?.id)

        clock.advance(by: 30)
        #expect(session.financeLedger.cashBalancePence < 0)
        #expect(session.financeLedger.consecutiveNegativeCashDays == 1)

        session.setServiceFrequency(.hourly, forLineID: lineID)

        #expect(session.lines.first?.serviceFrequency == .hourly)
        #expect(session.phase == .operating)
        #expect(session.errorMessage == nil)
    }

    @Test("Bankruptcy pauses immediately and a large tick cannot settle more days")
    func bankruptcyStopsTickLoop() async {
        let clock = FinanceManualClock()
        let capitalConfiguration = makeCapitalConfiguration(
            startingCashPence: 1_215_000_000,
            insolvencyGraceOperatingDays: 2
        )
        let deliberatelyLossMakingEconomy = OperatingEconomy(
            configuration: OperatingEconomyConfiguration(
                baseFarePencePerJourney: 0,
                farePencePerPassengerKilometre: 0,
                serviceHoursPerDay: 18,
                directionCount: 2,
                energyCostPencePerTrainKilometre: 100_000,
                variableRollingStockMaintenancePencePerTrainKilometre: 100_000,
                fixedRollingStockMaintenancePencePerAssignedTrainPerDay: 1_000_000,
                trackUpkeepPencePerKilometrePerDay: 1_000_000,
                stationUpkeepPencePerDayByLevel: Dictionary(
                    uniqueKeysWithValues: StationLevel.allCases.map { ($0, 1_000_000) }
                )
            )
        )
        let session = makeSession(
            routeLength: 100,
            mode: .career,
            clock: clock,
            capitalEconomy: CapitalEconomy(configuration: capitalConfiguration),
            operatingEconomy: deliberatelyLossMakingEconomy
        )
        await createPreview(in: session)
        session.confirmPreview()
        #expect(session.financeLedger.cashBalancePence == 0)

        clock.advance(by: 30)
        #expect(session.economyLedger.completedOperatingDays == 1)
        #expect(!session.financeLedger.isBankrupt)
        #expect(session.financeLedger.consecutiveNegativeCashDays == 1)

        clock.advance(by: 3_000)
        #expect(session.financeLedger.isBankrupt)
        #expect(session.economyLedger.completedOperatingDays == 2)
        #expect(!session.isPlaying)
        let bankruptLedger = session.financeLedger

        session.togglePlayPause()
        clock.advance(by: 3_000)
        #expect(!session.isPlaying)
        #expect(session.economyLedger.completedOperatingDays == 2)
        #expect(session.financeLedger == bankruptLedger)
    }

    @Test("Saved insolvency and bankruptcy survive grace-period tuning changes")
    func financeRestoreDoesNotReinterpretGracePeriod() async throws {
        let operatingEconomy = deliberatelyLossMakingOperatingEconomy()

        let bankruptClock = FinanceManualClock()
        let shortGraceSource = makeSession(
            routeLength: 100,
            mode: .career,
            clock: bankruptClock,
            capitalEconomy: CapitalEconomy(configuration: makeCapitalConfiguration(
                startingCashPence: 1_215_000_000,
                insolvencyGraceOperatingDays: 3
            )),
            operatingEconomy: operatingEconomy
        )
        await createPreview(in: shortGraceSource)
        shortGraceSource.confirmPreview()
        bankruptClock.advance(by: 90)
        #expect(shortGraceSource.financeLedger.isBankrupt)

        let longGraceTarget = makeSession(
            routeLength: 100,
            mode: .career,
            capitalEconomy: CapitalEconomy(configuration: makeCapitalConfiguration(
                startingCashPence: 1_215_000_000,
                insolvencyGraceOperatingDays: 7
            )),
            operatingEconomy: operatingEconomy
        )
        try await longGraceTarget.restore(from: shortGraceSource.makeSaveSnapshot())
        #expect(longGraceTarget.financeLedger.isBankrupt)
        #expect(longGraceTarget.financeLedger.consecutiveNegativeCashDays == 3)

        let graceClock = FinanceManualClock()
        let longGraceSource = makeSession(
            routeLength: 100,
            mode: .career,
            clock: graceClock,
            capitalEconomy: CapitalEconomy(configuration: makeCapitalConfiguration(
                startingCashPence: 1_215_000_000,
                insolvencyGraceOperatingDays: 7
            )),
            operatingEconomy: operatingEconomy
        )
        await createPreview(in: longGraceSource)
        longGraceSource.confirmPreview()
        graceClock.advance(by: 90)
        #expect(!longGraceSource.financeLedger.isBankrupt)
        #expect(longGraceSource.financeLedger.consecutiveNegativeCashDays == 3)

        let shortGraceTarget = makeSession(
            routeLength: 100,
            mode: .career,
            capitalEconomy: CapitalEconomy(configuration: makeCapitalConfiguration(
                startingCashPence: 1_215_000_000,
                insolvencyGraceOperatingDays: 2
            )),
            operatingEconomy: operatingEconomy
        )
        try await shortGraceTarget.restore(from: longGraceSource.makeSaveSnapshot())
        #expect(!shortGraceTarget.financeLedger.isBankrupt)
        #expect(shortGraceTarget.financeLedger.consecutiveNegativeCashDays == 3)

        let baseSnapshot = longGraceSource.makeSaveSnapshot()
        let baseFinancialState = baseSnapshot.financialState
        let extremeSnapshot = GameSaveSnapshot(
            savedAt: baseSnapshot.savedAt,
            isPlaying: true,
            simulationSpeed: baseSnapshot.simulationSpeed,
            lines: baseSnapshot.lines,
            stationProgress: baseSnapshot.stationProgress,
            economy: baseSnapshot.economy,
            financialState: SavedFinancialState(
                mode: .career,
                cashBalancePence: baseFinancialState.cashBalancePence,
                loans: baseFinancialState.loans,
                lifetimeConstructionSpendPence:
                    baseFinancialState.lifetimeConstructionSpendPence,
                lifetimeRollingStockSpendPence:
                    baseFinancialState.lifetimeRollingStockSpendPence,
                lifetimeLoanProceedsPence: baseFinancialState.lifetimeLoanProceedsPence,
                lifetimePrincipalRepaidPence:
                    baseFinancialState.lifetimePrincipalRepaidPence,
                lifetimeInterestPaidPence: baseFinancialState.lifetimeInterestPaidPence,
                consecutiveNegativeCashDays: .max,
                bankruptcyOperatingDay: nil,
                trackingStartedOnOperatingDay:
                    baseFinancialState.trackingStartedOnOperatingDay
            )
        )
        let extremeClock = FinanceManualClock()
        let extremeTarget = makeSession(
            routeLength: 100,
            mode: .career,
            clock: extremeClock,
            capitalEconomy: CapitalEconomy(configuration: makeCapitalConfiguration(
                startingCashPence: 1_215_000_000,
                insolvencyGraceOperatingDays: 2
            )),
            operatingEconomy: operatingEconomy
        )
        try await extremeTarget.restore(from: extremeSnapshot)
        extremeClock.advance(by: 30)
        #expect(extremeTarget.financeLedger.isBankrupt)
        #expect(extremeTarget.financeLedger.consecutiveNegativeCashDays == 2)
    }

    @Test("Zen records capital statistics without changing a cash balance")
    func zenCapitalStatistics() async {
        let session = makeSession(routeLength: 80_000, mode: .zen)
        await createPreview(in: session)
        #expect(session.canAffordPreview)
        session.confirmPreview()

        #expect(session.financeLedger.mode == .zen)
        #expect(session.financeLedger.cashBalancePence == 0)
        #expect(session.financeLedger.lifetimeCapitalSpendPence == 13_200_000_000)
        #expect(session.financeSnapshot.networkValuePence == 13_200_000_000)
    }

    @Test("Starting a new game clears the company and applies the selected mode")
    func resetAppliesSelectedGameMode() async throws {
        let session = makeSession(routeLength: 10_000, mode: .zen)
        await createPreview(in: session)
        session.confirmPreview()
        #expect(session.takeStandardLoan() == false)
        #expect(!session.lines.isEmpty)

        session.reset(gameMode: .career)

        #expect(session.gameMode == .career)
        #expect(session.financeLedger.cashBalancePence == 15_000_000_000)
        #expect(session.financeLedger.loans.isEmpty)
        #expect(session.lines.isEmpty)
        #expect(session.phase == .idle)
        #expect(session.isPlaying)

        session.reset(gameMode: .zen)

        #expect(session.gameMode == .zen)
        #expect(session.financeLedger.cashBalancePence == 0)
        #expect(session.lines.isEmpty)
    }

    @Test("Career treasury, loans and owned rolling stock survive a route-independent restore")
    func financePersistenceRoundTrip() async throws {
        let source = makeSession(routeLength: 10_000, mode: .career)
        await createPreview(in: source)
        source.confirmPreview()
        #expect(source.takeStandardLoan())
        let lineID = try #require(source.lines.first?.id)
        source.setServiceFrequency(.quarterHourly, forLineID: lineID)
        source.setServiceFrequency(.hourly, forLineID: lineID)
        let snapshot = source.makeSaveSnapshot()

        let restored = makeSession(routeLength: 10_000, mode: .zen)
        try await restored.restore(from: snapshot)

        #expect(restored.gameMode == .career)
        #expect(restored.financeLedger == source.financeLedger)
        #expect(restored.lines.first?.ownedTrainCount == 4)
        #expect(restored.lines.first?.serviceFrequency == .hourly)
        #expect(restored.financeSnapshot == source.financeSnapshot)
    }

    private var origin: Station {
        Station(crs: "VIC", name: "London Victoria", latitude: 51.4952, longitude: -0.1441)
    }

    private var destination: Station {
        Station(crs: "BTN", name: "Brighton", latitude: 50.829, longitude: -0.141)
    }

    private func makeSession(
        routeLength: CLLocationDistance,
        mode: GameMode,
        clock: FinanceManualClock? = nil,
        capitalEconomy: CapitalEconomy = CapitalEconomy(),
        operatingEconomy: OperatingEconomy = OperatingEconomy()
    ) -> GameSession {
        let resolvedClock = clock ?? FinanceManualClock()
        return GameSession(
            stations: [origin, destination],
            routingProvider: FinanceFixedRoutingProvider(route: makeRoute(length: routeLength)),
            operatingEconomy: operatingEconomy,
            capitalEconomy: capitalEconomy,
            gameMode: mode,
            clock: resolvedClock,
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

    private func createPreview(in session: GameSession) async {
        session.startBuilding()
        session.selectStation(origin)
        session.selectStation(destination)
        await session.waitForRouteCalculation()
        #expect(session.phase == .preview)
        // These finance goldens predate demand-sized rolling stock. Pin the historical fleet so
        // they continue to isolate treasury behavior rather than the recommendation policy.
        session.setPreviewFormation(.legacyBaseline)
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

    private func makeCapitalConfiguration(
        startingCashPence: Int64,
        insolvencyGraceOperatingDays: Int
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
            insolvencyGraceOperatingDays: insolvencyGraceOperatingDays,
            lowCashThresholdPence: 1_000_000_000,
            stationValuePenceByLevel: Dictionary(
                uniqueKeysWithValues: StationLevel.allCases.map { ($0, 200_000_000) }
            )
        )
    }

    private func deliberatelyLossMakingOperatingEconomy() -> OperatingEconomy {
        OperatingEconomy(
            configuration: OperatingEconomyConfiguration(
                baseFarePencePerJourney: 0,
                farePencePerPassengerKilometre: 0,
                serviceHoursPerDay: 18,
                directionCount: 2,
                energyCostPencePerTrainKilometre: 100_000,
                variableRollingStockMaintenancePencePerTrainKilometre: 100_000,
                fixedRollingStockMaintenancePencePerAssignedTrainPerDay: 1_000_000,
                trackUpkeepPencePerKilometrePerDay: 1_000_000,
                stationUpkeepPencePerDayByLevel: Dictionary(
                    uniqueKeysWithValues: StationLevel.allCases.map { ($0, 1_000_000) }
                )
            )
        )
    }
}

private nonisolated struct FinanceFixedRoutingProvider: RailwayRouteProviding {
    let route: ServiceRailwayRoute

    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        route
    }
}

@MainActor
private final class FinanceManualClock: SimulationClock {
    private var tick: (@MainActor (TimeInterval) -> Void)?

    func start(tick: @escaping @MainActor (TimeInterval) -> Void) {
        self.tick = tick
    }

    func setSuspended(_ isSuspended: Bool) {}

    func stop() {
        tick = nil
    }

    func advance(by delta: TimeInterval) {
        tick?(delta)
    }
}
