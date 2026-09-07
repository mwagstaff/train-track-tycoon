import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Capital economy")
struct CapitalEconomyTests {
    private let firstLoanID = UUID(
        uuidString: "10000000-0000-0000-0000-000000000001"
    )!
    private let secondLoanID = UUID(
        uuidString: "20000000-0000-0000-0000-000000000002"
    )!

    @Test("The POC 80 km line quote is exactly £132m")
    func documentedPOCQuote() {
        let quote = CapitalEconomy().quoteForNewLine(
            constructionCostPounds: 120_000_000,
            originCRS: " VIC ",
            destinationCRS: "btn",
            existingStationCRSs: [],
            initialTrainCount: 2
        )

        #expect(quote.trackAndInfrastructurePence == 12_000_000_000)
        #expect(quote.stationConstructionPence == 400_000_000)
        #expect(quote.rollingStockPence == 800_000_000)
        #expect(quote.constructionPence == 12_400_000_000)
        #expect(quote.totalPence == 13_200_000_000)
    }

    @Test("A multi-stop line charges each distinct new selected station once")
    func multiStopStationConstructionQuote() {
        let quote = CapitalEconomy().quoteForNewLine(
            constructionCostPounds: 10_000_000,
            originCRS: "VIC",
            destinationCRS: "KTH",
            stationCRSs: ["VIC", "BRX", "HNH", "BRX", "KTH"],
            existingStationCRSs: ["VIC", "HNH"],
            initialTrainCount: 2
        )

        #expect(quote.stationConstructionPence == 400_000_000)
    }

    @Test("High-speed capital quotes delegate to the shared investment policy")
    func highSpeedQuoteMatchesSharedPolicy() {
        let highSpeedRail = HighSpeedRail()
        let economy = CapitalEconomy(highSpeedRail: highSpeedRail)
        let quote = economy.quoteForNewLine(
            constructionCostPounds: 120_000_000,
            originCRS: " VIC ",
            destinationCRS: "btn",
            existingStationCRSs: ["VIC", "BTN"],
            initialTrainCount: 2,
            railwayClass: .highSpeed,
            existingPremiumStationCRSs: []
        )
        let policyQuote = highSpeedRail.investmentQuote(
            constructionCostPounds: 120_000_000,
            originCRS: " VIC ",
            destinationCRS: "btn",
            existingPremiumStationCRSs: [],
            trainCount: 2
        )

        #expect(quote.trackAndInfrastructurePence == 36_000_000_000)
        #expect(quote.stationConstructionPence == 4_000_000_000)
        #expect(quote.rollingStockPence == 4_000_000_000)
        #expect(quote.totalPence == 44_000_000_000)
        #expect(quote.trackAndInfrastructurePence
            == policyQuote.trackAndInfrastructurePence)
        #expect(quote.stationConstructionPence
            == policyQuote.premiumStationUpgradesPence)
        #expect(quote.rollingStockPence == policyQuote.rollingStockPence)

        let sharedPremiumEndpoint = economy.quoteForNewLine(
            constructionCostPounds: 0,
            originCRS: " vic ",
            destinationCRS: "BTN",
            existingStationCRSs: [],
            initialTrainCount: 0,
            railwayClass: .highSpeed,
            existingPremiumStationCRSs: ["VIC"]
        )
        #expect(sharedPremiumEndpoint.stationConstructionPence == 2_000_000_000)
    }

    @Test("High-speed assets use class-aware values and unique premium stations")
    func highSpeedNetworkValue() {
        let economy = CapitalEconomy()
        let snapshot = economy.evaluate(
            lines: [
                CapitalLineInput(
                    id: firstLoanID,
                    constructionCostPounds: 120_000_000,
                    ownedTrainCount: 2,
                    // HSR's 3x policy already includes its mandatory dedicated double track.
                    infrastructureUpgradeValuePence: 10_200_000_000,
                    railwayClass: .highSpeed
                ),
            ],
            stationLevelsByCRS: [
                " vic ": .halt,
                "BTN": .halt,
            ],
            operatingEconomy: .zero,
            ledger: FinanceLedger(mode: .zen),
            premiumStationCRSs: ["VIC", " vic ", "btn", "NOT-IN-NETWORK"]
        )

        #expect(economy.rollingStockCost(
            forTrainCount: 2,
            railwayClass: .highSpeed
        ) == 4_000_000_000)
        #expect(snapshot.trackAndInfrastructureValuePence == 36_000_000_000)
        #expect(snapshot.stationValuePence == 4_400_000_000)
        #expect(snapshot.rollingStockValuePence == 4_000_000_000)
        #expect(snapshot.networkValuePence == 44_400_000_000)

        let saturatedQuote = economy.quoteForNewLine(
            constructionCostPounds: .max,
            originCRS: "AAA",
            destinationCRS: "BBB",
            existingStationCRSs: [],
            initialTrainCount: .max,
            railwayClass: .highSpeed
        )
        #expect(saturatedQuote.trackAndInfrastructurePence == .max)
        #expect(saturatedQuote.rollingStockPence == .max)
        #expect(saturatedQuote.totalPence == .max)
    }

    @Test("Shared stations are only charged once and CRS matching is normalized")
    func sharedStationConstructionCost() {
        let economy = CapitalEconomy()
        let oneSharedEndpoint = economy.quoteForNewLine(
            constructionCostPounds: 1_000,
            originCRS: " vic ",
            destinationCRS: "ecr",
            existingStationCRSs: ["VIC", " clj "],
            initialTrainCount: 0
        )
        let sameNewEndpointTwice = economy.quoteForNewLine(
            constructionCostPounds: 0,
            originCRS: "abc",
            destinationCRS: " ABC ",
            existingStationCRSs: [],
            initialTrainCount: 0
        )
        let blankEndpoints = economy.quoteForNewLine(
            constructionCostPounds: -1,
            originCRS: "  ",
            destinationCRS: "\n",
            existingStationCRSs: [],
            initialTrainCount: -2
        )

        #expect(oneSharedEndpoint.stationConstructionPence == 200_000_000)
        #expect(sameNewEndpointTwice.stationConstructionPence == 200_000_000)
        #expect(blankEndpoints == .zero)
    }

    @Test("Career purchases debit cash and reject an unaffordable purchase atomically")
    func careerPurchases() {
        let economy = CapitalEconomy(configuration: configuration(startingCashPence: 1_000))
        let affordable = CapitalPurchaseQuote(
            trackAndInfrastructurePence: 400,
            stationConstructionPence: 100,
            rollingStockPence: 200
        )
        let unaffordable = CapitalPurchaseQuote(
            trackAndInfrastructurePence: 301,
            stationConstructionPence: 0,
            rollingStockPence: 0
        )
        var ledger = economy.newLedger(mode: .career)

        #expect(economy.canAfford(affordable, ledger: ledger))
        #expect(economy.fundingShortfall(for: affordable.totalPence, ledger: ledger) == 0)
        #expect(economy.recordPurchase(affordable, in: &ledger))
        #expect(ledger.cashBalancePence == 300)
        #expect(ledger.lifetimeConstructionSpendPence == 500)
        #expect(ledger.lifetimeRollingStockSpendPence == 200)
        #expect(ledger.lifetimeCapitalSpendPence == 700)

        let beforeRejection = ledger
        #expect(!economy.canAfford(unaffordable, ledger: ledger))
        #expect(economy.fundingShortfall(for: unaffordable.totalPence, ledger: ledger) == 1)
        #expect(!economy.recordPurchase(unaffordable, in: &ledger))
        #expect(ledger == beforeRejection)
    }

    @Test("Zen purchases retain statistics without constraining or changing cash")
    func zenPurchases() {
        let economy = CapitalEconomy(configuration: configuration(startingCashPence: 999))
        var ledger = economy.newLedger(mode: .zen)
        let quote = CapitalPurchaseQuote(
            trackAndInfrastructurePence: .max,
            stationConstructionPence: 10,
            rollingStockPence: 20
        )

        #expect(ledger.cashBalancePence == 0)
        #expect(economy.canAfford(quote, ledger: ledger))
        #expect(economy.fundingShortfall(for: .max, ledger: ledger) == 0)
        #expect(economy.recordPurchase(quote, in: &ledger))
        #expect(ledger.cashBalancePence == 0)
        #expect(ledger.lifetimeConstructionSpendPence == .max)
        #expect(ledger.lifetimeRollingStockSpendPence == 20)
        #expect(ledger.lifetimeCapitalSpendPence == .max)
    }

    @Test("Malformed negative quote components cannot create cash")
    func negativeQuoteComponentsAreClamped() {
        let economy = CapitalEconomy(configuration: configuration(startingCashPence: 100))
        let quote = CapitalPurchaseQuote(
            trackAndInfrastructurePence: -100,
            stationConstructionPence: 50,
            rollingStockPence: -20
        )
        var ledger = economy.newLedger(mode: .career)

        #expect(quote.constructionPence == 50)
        #expect(quote.totalPence == 50)
        #expect(economy.recordPurchase(quote, in: &ledger))
        #expect(ledger.cashBalancePence == 50)
        #expect(ledger.lifetimeConstructionSpendPence == 50)
        #expect(ledger.lifetimeRollingStockSpendPence == 0)
    }

    @Test("Rolling stock purchases use the same Career and Zen transaction rules")
    func rollingStockPurchases() {
        let economy = CapitalEconomy(configuration: configuration(startingCashPence: 500))
        var career = economy.newLedger(mode: .career)
        var zen = economy.newLedger(mode: .zen)

        #expect(economy.recordRollingStockPurchase(costPence: 200, in: &career))
        #expect(career.cashBalancePence == 300)
        #expect(career.lifetimeRollingStockSpendPence == 200)
        #expect(!economy.recordRollingStockPurchase(costPence: 301, in: &career))
        #expect(career.cashBalancePence == 300)
        #expect(career.lifetimeRollingStockSpendPence == 200)

        #expect(economy.recordRollingStockPurchase(costPence: .max, in: &zen))
        #expect(zen.cashBalancePence == 0)
        #expect(zen.lifetimeRollingStockSpendPence == .max)
    }

    @Test("Loans add proceeds, respect eligibility, and have deterministic ordering")
    func loanOrigination() {
        let economy = CapitalEconomy(configuration: configuration(
            startingCashPence: 100,
            loanPrincipalPence: 1_000,
            maximumConcurrentLoans: 2
        ))
        var ledger = economy.newLedger(mode: .career)

        #expect(economy.originateLoan(
            in: &ledger,
            onOperatingDay: 4,
            id: secondLoanID
        ))
        #expect(economy.originateLoan(
            in: &ledger,
            onOperatingDay: 5,
            id: firstLoanID
        ))
        #expect(!economy.originateLoan(
            in: &ledger,
            onOperatingDay: 6,
            id: UUID()
        ))
        #expect(ledger.loans.map(\.id) == [firstLoanID, secondLoanID])
        #expect(ledger.cashBalancePence == 2_100)
        #expect(ledger.lifetimeLoanProceedsPence == 2_000)
        #expect(ledger.loans.map(\.originatedOnOperatingDay) == [5, 4])

        var zen = economy.newLedger(mode: .zen)
        #expect(!economy.originateLoan(in: &zen, onOperatingDay: 0))
        var bankrupt = FinanceLedger(mode: .career, bankruptcyOperatingDay: 3)
        #expect(!economy.originateLoan(in: &bankrupt, onOperatingDay: 4))
    }

    @Test("The standard loan offer discloses configured terms and its first payment")
    func standardLoanOfferDisclosure() {
        let economy = CapitalEconomy(configuration: configuration(
            loanPrincipalPence: 10_001,
            loanAnnualInterestBasisPoints: 36_000,
            loanTermOperatingDays: 2
        ))

        let offer = economy.standardLoanOffer

        #expect(offer.principalPence == 10_001)
        #expect(offer.annualInterestBasisPoints == 36_000)
        #expect(offer.termOperatingDays == 2)
        #expect(offer.firstDayInterestPence == 101)
        #expect(offer.firstDayPrincipalPence == 5_001)
        #expect(offer.firstDayPaymentPence == 5_102)
    }

    @Test("Scheduled debt service charges opening-balance interest and clears principal on term")
    func scheduledLoanPayments() throws {
        // 36,000 basis points over a 360-day convention is exactly 1% per day.
        let economy = CapitalEconomy(configuration: configuration(
            startingCashPence: 0,
            loanPrincipalPence: 10_001,
            loanAnnualInterestBasisPoints: 36_000,
            loanTermOperatingDays: 2
        ))
        var ledger = economy.newLedger(mode: .career)
        #expect(economy.originateLoan(
            in: &ledger,
            onOperatingDay: 0,
            id: firstLoanID
        ))

        #expect(!economy.settleOperatingDay(
            operatingResultPence: 6_000,
            completedOperatingDay: 1,
            ledger: &ledger
        ))
        let remainingLoan = try #require(ledger.loans.first)
        #expect(remainingLoan.outstandingPrincipalPence == 5_000)
        #expect(remainingLoan.remainingOperatingDays == 1)
        #expect(ledger.cashBalancePence == 10_899)
        #expect(ledger.lifetimeInterestPaidPence == 101)
        #expect(ledger.lifetimePrincipalRepaidPence == 5_001)

        #expect(!economy.settleOperatingDay(
            operatingResultPence: 6_000,
            completedOperatingDay: 2,
            ledger: &ledger
        ))
        #expect(ledger.loans.isEmpty)
        #expect(ledger.cashBalancePence == 11_849)
        #expect(ledger.lifetimeInterestPaidPence == 151)
        #expect(ledger.lifetimePrincipalRepaidPence == 10_001)
    }

    @Test("Early repayment targets loans by stable ID order and never overpays")
    func earlyRepaymentOrdering() {
        let economy = CapitalEconomy(configuration: configuration(
            earlyRepaymentPence: 5_000
        ))
        let first = loan(
            id: firstLoanID,
            principal: 4_000,
            remainingDays: 4
        )
        let second = loan(
            id: secondLoanID,
            principal: 6_000,
            remainingDays: 6
        )
        var ledger = FinanceLedger(
            mode: .career,
            cashBalancePence: 8_000,
            loans: [second, first]
        )

        #expect(economy.makeEarlyRepayment(in: &ledger))
        #expect(ledger.cashBalancePence == 3_000)
        #expect(ledger.loans.map(\.id) == [secondLoanID])
        #expect(ledger.loans.first?.outstandingPrincipalPence == 5_000)
        #expect(ledger.lifetimePrincipalRepaidPence == 5_000)

        ledger.cashBalancePence = 10_000
        #expect(economy.makeEarlyRepayment(in: &ledger))
        #expect(ledger.loans.isEmpty)
        #expect(ledger.cashBalancePence == 5_000)
        #expect(ledger.lifetimePrincipalRepaidPence == 10_000)
        #expect(!economy.makeEarlyRepayment(in: &ledger))
    }

    @Test("Early repayment disclosure is capped by cash, standard amount and final debt")
    func availableEarlyRepaymentAmount() {
        let economy = CapitalEconomy(configuration: configuration(
            earlyRepaymentPence: 5_000
        ))
        var partialCash = FinanceLedger(
            mode: .career,
            cashBalancePence: 2_000,
            loans: [loan(id: firstLoanID, principal: 4_000, remainingDays: 4)]
        )
        #expect(economy.availableEarlyRepaymentPence(in: partialCash) == 2_000)
        #expect(economy.makeEarlyRepayment(in: &partialCash))
        #expect(partialCash.cashBalancePence == 0)
        #expect(partialCash.loans.first?.outstandingPrincipalPence == 2_000)

        let finalSmallBalance = FinanceLedger(
            mode: .career,
            cashBalancePence: 10_000,
            loans: [loan(id: secondLoanID, principal: 300, remainingDays: 1)]
        )
        #expect(economy.availableEarlyRepaymentPence(in: finalSmallBalance) == 300)

        let bankrupt = FinanceLedger(
            mode: .career,
            cashBalancePence: 10_000,
            loans: [loan(id: firstLoanID, principal: 300, remainingDays: 1)],
            bankruptcyOperatingDay: 1
        )
        #expect(economy.availableEarlyRepaymentPence(in: bankrupt) == 0)
    }

    @Test("Network value, debt, net worth and projections reconcile exactly")
    func networkValueAndNetWorth() {
        let economy = CapitalEconomy(configuration: configuration(
            rollingStockUnitCostPence: 100,
            lowCashThresholdPence: 1_000,
            stationValuePenceByLevel: [
                .halt: 10,
                .localStation: 20,
                .townStation: 30,
            ]
        ))
        let loan = LoanAccount(
            id: firstLoanID,
            originalPrincipalPence: 2_000,
            annualInterestBasisPoints: 0,
            termOperatingDays: 2,
            remainingOperatingDays: 2,
            originatedOnOperatingDay: 0
        )
        let ledger = FinanceLedger(
            mode: .career,
            cashBalancePence: 5_000,
            loans: [loan]
        )
        let lines = [
            CapitalLineInput(
                id: secondLoanID,
                constructionCostPounds: 1_000,
                ownedTrainCount: 2
            ),
            CapitalLineInput(
                id: firstLoanID,
                constructionCostPounds: 500,
                ownedTrainCount: 1
            ),
        ]
        let snapshot = economy.evaluate(
            lines: lines,
            stationLevelsByCRS: [
                " vic ": .localStation,
                "VIC": .townStation,
                "ECR": .halt,
                "   ": .terminus,
            ],
            operatingEconomy: operatingSnapshot(resultPencePerDay: 200_000),
            ledger: ledger
        )

        #expect(snapshot.trackAndInfrastructureValuePence == 150_000)
        #expect(snapshot.stationValuePence == 40)
        #expect(snapshot.rollingStockValuePence == 300)
        #expect(snapshot.networkValuePence == 150_340)
        #expect(snapshot.outstandingDebtPence == 2_000)
        #expect(snapshot.projectedInterestPencePerDay == 0)
        #expect(snapshot.projectedPrincipalRepaymentPencePerDay == 1_000)
        #expect(snapshot.projectedProfitPencePerDay == 200_000)
        #expect(snapshot.projectedCashChangePencePerDay == 199_000)
        #expect(snapshot.netCompanyValuePence == 153_340)
        #expect(snapshot.commercialViability == .profitable)
        #expect(snapshot.financialHealth == .healthy)
        #expect(snapshot.canBorrow)
        #expect(snapshot.canMakeEarlyRepayment)
    }

    @Test("Zen valuation omits cash constraints while retaining financial statistics")
    func zenValuation() {
        let economy = CapitalEconomy(configuration: configuration(
            rollingStockUnitCostPence: 25,
            stationValuePenceByLevel: [.halt: 50]
        ))
        let ledger = FinanceLedger(mode: .zen, cashBalancePence: .max)
        let snapshot = economy.evaluate(
            lines: [
                CapitalLineInput(
                    id: firstLoanID,
                    constructionCostPounds: 10,
                    ownedTrainCount: 2
                ),
            ],
            stationLevelsByCRS: ["AAA": .halt],
            operatingEconomy: operatingSnapshot(resultPencePerDay: -1),
            ledger: ledger
        )

        #expect(snapshot.networkValuePence == 1_100)
        #expect(snapshot.netCompanyValuePence == 1_100)
        #expect(snapshot.commercialViability == .lossMaking)
        #expect(snapshot.financialHealth == .zen)
        #expect(!snapshot.canBorrow)
        #expect(!snapshot.canMakeEarlyRepayment)
    }

    @Test("Insolvency uses consecutive days, recovery resets the grace period, and bankruptcy freezes")
    func insolvencyAndBankruptcyGrace() {
        let economy = CapitalEconomy(configuration: configuration(
            startingCashPence: 0,
            insolvencyGraceOperatingDays: 3,
            lowCashThresholdPence: 10
        ))
        var ledger = economy.newLedger(mode: .career)

        #expect(!economy.settleOperatingDay(
            operatingResultPence: -1,
            completedOperatingDay: 1,
            ledger: &ledger
        ))
        #expect(ledger.consecutiveNegativeCashDays == 1)
        #expect(financialHealth(economy: economy, ledger: ledger) == .insolvent(daysRemaining: 2))

        #expect(!economy.settleOperatingDay(
            operatingResultPence: 1,
            completedOperatingDay: 2,
            ledger: &ledger
        ))
        #expect(ledger.cashBalancePence == 0)
        #expect(ledger.consecutiveNegativeCashDays == 0)
        #expect(financialHealth(economy: economy, ledger: ledger) == .lowCash)

        #expect(!economy.settleOperatingDay(
            operatingResultPence: -1,
            completedOperatingDay: 3,
            ledger: &ledger
        ))
        #expect(!economy.settleOperatingDay(
            operatingResultPence: 0,
            completedOperatingDay: 4,
            ledger: &ledger
        ))
        #expect(economy.settleOperatingDay(
            operatingResultPence: 0,
            completedOperatingDay: 5,
            ledger: &ledger
        ))
        #expect(ledger.bankruptcyOperatingDay == 5)
        #expect(financialHealth(economy: economy, ledger: ledger) == .bankrupt)
        #expect(!economy.canAfford(0, ledger: ledger))

        let bankruptState = ledger
        #expect(!economy.settleOperatingDay(
            operatingResultPence: .max,
            completedOperatingDay: 6,
            ledger: &ledger
        ))
        #expect(ledger == bankruptState)
    }

    @Test("Capital calculations saturate instead of overflowing")
    func saturatingArithmetic() {
        let economy = CapitalEconomy(configuration: configuration(
            startingCashPence: .max,
            stationConstructionCostPence: .max,
            rollingStockUnitCostPence: .max,
            loanPrincipalPence: .max,
            earlyRepaymentPence: .max,
            stationValuePenceByLevel: [.terminus: .max]
        ))
        let quote = economy.quoteForNewLine(
            constructionCostPounds: .max,
            originCRS: "AAA",
            destinationCRS: "BBB",
            existingStationCRSs: [],
            initialTrainCount: .max
        )

        #expect(quote.trackAndInfrastructurePence == .max)
        #expect(quote.stationConstructionPence == .max)
        #expect(quote.rollingStockPence == .max)
        #expect(quote.totalPence == .max)

        var ledger = FinanceLedger(
            mode: .career,
            cashBalancePence: .max,
            loans: [loan(id: firstLoanID, principal: .max, remainingDays: 1)],
            lifetimeConstructionSpendPence: .max,
            lifetimeRollingStockSpendPence: .max,
            lifetimeLoanProceedsPence: .max,
            lifetimePrincipalRepaidPence: .max,
            lifetimeInterestPaidPence: .max
        )
        #expect(ledger.lifetimeCapitalSpendPence == .max)
        #expect(economy.totalDebt(in: ledger) == .max)
        #expect(!economy.canAfford(.max, ledger: ledger))
        #expect(economy.fundingShortfall(for: .max, ledger: ledger) == 0)

        _ = economy.settleOperatingDay(
            operatingResultPence: .max,
            completedOperatingDay: 1,
            ledger: &ledger
        )
        #expect(ledger.lifetimePrincipalRepaidPence == .max)
        #expect(ledger.lifetimeInterestPaidPence == .max)

        let value = economy.evaluate(
            lines: [
                CapitalLineInput(
                    id: firstLoanID,
                    constructionCostPounds: .max,
                    ownedTrainCount: .max
                ),
            ],
            stationLevelsByCRS: ["AAA": .terminus],
            operatingEconomy: operatingSnapshot(resultPencePerDay: .max),
            ledger: ledger
        )
        #expect(value.networkValuePence == .max)
        #expect(value.projectedProfitPencePerDay == .max)
        #expect(value.netCompanyValuePence == .max)

        let divisor: Int64 = 3_600_000
        let expectedLargeFraction = Int64.max - (Int64.max / divisor + 1)
        #expect(EconomyArithmetic.scaled(
            divisor - 1,
            multiplier: .max,
            divisor: divisor
        ) == expectedLargeFraction)
        #expect(EconomyArithmetic.scaled(
            .max,
            multiplier: .max,
            divisor: divisor
        ) == .max)
        #expect(EconomyArithmetic.scaledCeiling(1, multiplier: 1, divisor: 2) == 1)
        #expect(EconomyArithmetic.scaledCeiling(2, multiplier: 1, divisor: 2) == 1)
    }

    @Test("Line and loan input ordering cannot change an evaluation or settlement")
    func orderingIsDeterministic() {
        let economy = CapitalEconomy(configuration: configuration(
            rollingStockUnitCostPence: 10,
            loanAnnualInterestBasisPoints: 36_000
        ))
        let firstLine = CapitalLineInput(
            id: firstLoanID,
            constructionCostPounds: 100,
            ownedTrainCount: 1
        )
        let secondLine = CapitalLineInput(
            id: secondLoanID,
            constructionCostPounds: 200,
            ownedTrainCount: 2
        )
        let first = loan(id: firstLoanID, principal: 4_000, remainingDays: 4)
        let second = loan(id: secondLoanID, principal: 6_000, remainingDays: 6)
        let forwardLedger = FinanceLedger(
            mode: .career,
            cashBalancePence: 10_000,
            loans: [first, second]
        )
        let reverseLedger = FinanceLedger(
            mode: .career,
            cashBalancePence: 10_000,
            loans: [second, first]
        )

        let forwardSnapshot = economy.evaluate(
            lines: [firstLine, secondLine],
            stationLevelsByCRS: ["AAA": .localStation, "BBB": .townStation],
            operatingEconomy: operatingSnapshot(resultPencePerDay: 10_000),
            ledger: forwardLedger
        )
        let reverseSnapshot = economy.evaluate(
            lines: [secondLine, firstLine],
            stationLevelsByCRS: ["BBB": .townStation, "AAA": .localStation],
            operatingEconomy: operatingSnapshot(resultPencePerDay: 10_000),
            ledger: reverseLedger
        )
        #expect(forwardSnapshot == reverseSnapshot)

        var forwardSettlement = forwardLedger
        var reverseSettlement = reverseLedger
        _ = economy.settleOperatingDay(
            operatingResultPence: 10_000,
            completedOperatingDay: 1,
            ledger: &forwardSettlement
        )
        _ = economy.settleOperatingDay(
            operatingResultPence: 10_000,
            completedOperatingDay: 1,
            ledger: &reverseSettlement
        )
        #expect(forwardSettlement == reverseSettlement)
        #expect(forwardSettlement.loans.map(\.id) == [firstLoanID, secondLoanID])
    }

    private func financialHealth(
        economy: CapitalEconomy,
        ledger: FinanceLedger
    ) -> FinancialHealth {
        economy.evaluate(
            lines: [],
            stationLevelsByCRS: [:],
            operatingEconomy: .zero,
            ledger: ledger
        ).financialHealth
    }

    private func loan(
        id: UUID,
        principal: Int64,
        remainingDays: Int
    ) -> LoanAccount {
        LoanAccount(
            id: id,
            originalPrincipalPence: principal,
            annualInterestBasisPoints: 0,
            termOperatingDays: remainingDays,
            remainingOperatingDays: remainingDays,
            originatedOnOperatingDay: 0
        )
    }

    private func operatingSnapshot(
        resultPencePerDay: Int64
    ) -> NetworkOperatingEconomySnapshot {
        NetworkOperatingEconomySnapshot(
            lineSnapshotsByID: [:],
            stationUpkeepPencePerDay: 0,
            totalRevenuePencePerDay: max(resultPencePerDay, 0),
            totalEnergyCostPencePerDay: 0,
            totalRollingStockMaintenanceCostPencePerDay: 0,
            totalTrainOperatingCostPencePerDay: 0,
            totalTrackUpkeepPencePerDay: 0,
            totalOperatingCostPencePerDay: max(-resultPencePerDay, 0),
            operatingResultPencePerDay: resultPencePerDay
        )
    }

    private func configuration(
        startingCashPence: Int64 = 0,
        stationConstructionCostPence: Int64 = 200,
        rollingStockUnitCostPence: Int64 = 100,
        loanPrincipalPence: Int64 = 1_000,
        earlyRepaymentPence: Int64 = 500,
        loanAnnualInterestBasisPoints: Int = 0,
        loanTermOperatingDays: Int = 10,
        maximumConcurrentLoans: Int = 3,
        insolvencyGraceOperatingDays: Int = 3,
        lowCashThresholdPence: Int64 = 100,
        stationValuePenceByLevel: [StationLevel: Int64] = [
            .halt: 200,
            .localStation: 300,
            .townStation: 500,
            .majorStation: 1_000,
            .interchange: 2_000,
            .terminus: 3_500,
        ]
    ) -> CapitalEconomyConfiguration {
        CapitalEconomyConfiguration(
            startingCashPence: startingCashPence,
            stationConstructionCostPence: stationConstructionCostPence,
            rollingStockUnitCostPence: rollingStockUnitCostPence,
            loanPrincipalPence: loanPrincipalPence,
            earlyRepaymentPence: earlyRepaymentPence,
            loanAnnualInterestBasisPoints: loanAnnualInterestBasisPoints,
            loanTermOperatingDays: loanTermOperatingDays,
            maximumConcurrentLoans: maximumConcurrentLoans,
            insolvencyGraceOperatingDays: insolvencyGraceOperatingDays,
            lowCashThresholdPence: lowCashThresholdPence,
            stationValuePenceByLevel: stationValuePenceByLevel
        )
    }
}
