import Foundation

nonisolated enum GameMode: String, CaseIterable, Codable, Equatable, Sendable {
    case career
    case zen

    var title: String {
        switch self {
        case .career: "Career"
        case .zen: "Zen"
        }
    }

    var subtitle: String {
        switch self {
        case .career: "Budget, loans and bankruptcy"
        case .zen: "Unlimited budget with full statistics"
        }
    }
}

nonisolated struct LoanAccount: Identifiable, Equatable, Sendable {
    let id: UUID
    let originalPrincipalPence: Int64
    var outstandingPrincipalPence: Int64
    let annualInterestBasisPoints: Int
    let termOperatingDays: Int
    var remainingOperatingDays: Int
    let originatedOnOperatingDay: UInt64

    init(
        id: UUID = UUID(),
        originalPrincipalPence: Int64,
        outstandingPrincipalPence: Int64? = nil,
        annualInterestBasisPoints: Int,
        termOperatingDays: Int,
        remainingOperatingDays: Int? = nil,
        originatedOnOperatingDay: UInt64
    ) {
        self.id = id
        self.originalPrincipalPence = originalPrincipalPence
        self.outstandingPrincipalPence = outstandingPrincipalPence
            ?? originalPrincipalPence
        self.annualInterestBasisPoints = annualInterestBasisPoints
        self.termOperatingDays = termOperatingDays
        self.remainingOperatingDays = remainingOperatingDays ?? termOperatingDays
        self.originatedOnOperatingDay = originatedOnOperatingDay
    }
}

nonisolated struct FinanceLedger: Equatable, Sendable {
    var mode: GameMode
    var cashBalancePence: Int64
    var loans: [LoanAccount]
    var lifetimeConstructionSpendPence: Int64
    var lifetimeRollingStockSpendPence: Int64
    var lifetimeLoanProceedsPence: Int64
    var lifetimePrincipalRepaidPence: Int64
    var lifetimeInterestPaidPence: Int64
    var hasIncompleteCapitalHistory: Bool
    var trackingStartedOnOperatingDay: UInt64
    var consecutiveNegativeCashDays: Int
    var bankruptcyOperatingDay: UInt64?

    init(
        mode: GameMode = .zen,
        cashBalancePence: Int64 = 0,
        loans: [LoanAccount] = [],
        lifetimeConstructionSpendPence: Int64 = 0,
        lifetimeRollingStockSpendPence: Int64 = 0,
        lifetimeLoanProceedsPence: Int64 = 0,
        lifetimePrincipalRepaidPence: Int64 = 0,
        lifetimeInterestPaidPence: Int64 = 0,
        hasIncompleteCapitalHistory: Bool = false,
        trackingStartedOnOperatingDay: UInt64 = 0,
        consecutiveNegativeCashDays: Int = 0,
        bankruptcyOperatingDay: UInt64? = nil
    ) {
        self.mode = mode
        self.cashBalancePence = cashBalancePence
        self.loans = loans
        self.lifetimeConstructionSpendPence = lifetimeConstructionSpendPence
        self.lifetimeRollingStockSpendPence = lifetimeRollingStockSpendPence
        self.lifetimeLoanProceedsPence = lifetimeLoanProceedsPence
        self.lifetimePrincipalRepaidPence = lifetimePrincipalRepaidPence
        self.lifetimeInterestPaidPence = lifetimeInterestPaidPence
        self.hasIncompleteCapitalHistory = hasIncompleteCapitalHistory
        self.trackingStartedOnOperatingDay = trackingStartedOnOperatingDay
        self.consecutiveNegativeCashDays = consecutiveNegativeCashDays
        self.bankruptcyOperatingDay = bankruptcyOperatingDay
    }

    static let zero = Self()

    var isBankrupt: Bool { bankruptcyOperatingDay != nil }

    var lifetimeCapitalSpendPence: Int64 {
        EconomyArithmetic.add(
            lifetimeConstructionSpendPence,
            lifetimeRollingStockSpendPence
        )
    }
}

nonisolated struct CapitalPurchaseQuote: Equatable, Sendable {
    let trackAndInfrastructurePence: Int64
    let stationConstructionPence: Int64
    let rollingStockPence: Int64

    static let zero = Self(
        trackAndInfrastructurePence: 0,
        stationConstructionPence: 0,
        rollingStockPence: 0
    )

    var constructionPence: Int64 {
        EconomyArithmetic.add(
            max(trackAndInfrastructurePence, 0),
            max(stationConstructionPence, 0)
        )
    }

    var totalPence: Int64 {
        EconomyArithmetic.add(constructionPence, max(rollingStockPence, 0))
    }
}

nonisolated struct StandardLoanOffer: Equatable, Sendable {
    let principalPence: Int64
    let annualInterestBasisPoints: Int
    let termOperatingDays: Int
    let firstDayInterestPence: Int64
    let firstDayPrincipalPence: Int64

    var firstDayPaymentPence: Int64 {
        EconomyArithmetic.add(firstDayInterestPence, firstDayPrincipalPence)
    }
}

nonisolated enum CommercialViability: Equatable, Sendable {
    case profitable
    case marginal
    case lossMaking

    var label: String {
        switch self {
        case .profitable: "Profitable"
        case .marginal: "Marginal"
        case .lossMaking: "Loss-making"
        }
    }
}

nonisolated enum FinancialHealth: Equatable, Sendable {
    case zen
    case healthy
    case lowCash
    case insolvent(daysRemaining: Int)
    case bankrupt
}

nonisolated struct NetworkFinanceSnapshot: Equatable, Sendable {
    let trackAndInfrastructureValuePence: Int64
    let stationValuePence: Int64
    let rollingStockValuePence: Int64
    let networkValuePence: Int64
    let outstandingDebtPence: Int64
    let projectedInterestPencePerDay: Int64
    let projectedPrincipalRepaymentPencePerDay: Int64
    let projectedProfitPencePerDay: Int64
    let projectedCashChangePencePerDay: Int64
    let netCompanyValuePence: Int64
    let commercialViability: CommercialViability
    let financialHealth: FinancialHealth
    let canBorrow: Bool
    let canMakeEarlyRepayment: Bool
}

nonisolated struct CapitalLineInput: Identifiable, Equatable, Sendable {
    let id: UUID
    let constructionCostPounds: Int64
    let ownedTrainCount: Int
    let formation: RollingStockFormation
    let infrastructureUpgradeValuePence: Int64
    let railwayClass: RailwayClass

    init(
        id: UUID,
        constructionCostPounds: Int64,
        ownedTrainCount: Int,
        formation: RollingStockFormation = .legacyBaseline,
        infrastructureUpgradeValuePence: Int64 = 0,
        railwayClass: RailwayClass = .conventional
    ) {
        self.id = id
        self.constructionCostPounds = constructionCostPounds
        self.ownedTrainCount = ownedTrainCount
        self.formation = formation
        self.infrastructureUpgradeValuePence = infrastructureUpgradeValuePence
        self.railwayClass = railwayClass
    }
}

/// A fleet-wide purchase that lengthens every owned trainset on one line by two carriages.
nonisolated struct RollingStockFormationExtensionQuote: Equatable, Sendable {
    let currentFormation: RollingStockFormation
    let upgradedFormation: RollingStockFormation
    let ownedTrainCount: Int
    let totalCostPence: Int64
}

nonisolated struct CapitalEconomyConfiguration: Equatable, Sendable {
    let startingCashPence: Int64
    let stationConstructionCostPence: Int64
    /// Purchase price of one conventional six-car trainset.
    let rollingStockUnitCostPence: Int64
    let loanPrincipalPence: Int64
    let earlyRepaymentPence: Int64
    let loanAnnualInterestBasisPoints: Int
    let loanTermOperatingDays: Int
    let maximumConcurrentLoans: Int
    let insolvencyGraceOperatingDays: Int
    let lowCashThresholdPence: Int64
    let stationValuePenceByLevel: [StationLevel: Int64]

    init(
        startingCashPence: Int64,
        stationConstructionCostPence: Int64,
        rollingStockUnitCostPence: Int64,
        loanPrincipalPence: Int64,
        earlyRepaymentPence: Int64,
        loanAnnualInterestBasisPoints: Int,
        loanTermOperatingDays: Int,
        maximumConcurrentLoans: Int,
        insolvencyGraceOperatingDays: Int,
        lowCashThresholdPence: Int64,
        stationValuePenceByLevel: [StationLevel: Int64]
    ) {
        self.startingCashPence = startingCashPence
        self.stationConstructionCostPence = stationConstructionCostPence
        self.rollingStockUnitCostPence = rollingStockUnitCostPence
        self.loanPrincipalPence = loanPrincipalPence
        self.earlyRepaymentPence = earlyRepaymentPence
        self.loanAnnualInterestBasisPoints = loanAnnualInterestBasisPoints
        self.loanTermOperatingDays = loanTermOperatingDays
        self.maximumConcurrentLoans = maximumConcurrentLoans
        self.insolvencyGraceOperatingDays = insolvencyGraceOperatingDays
        self.lowCashThresholdPence = lowCashThresholdPence
        self.stationValuePenceByLevel = stationValuePenceByLevel
    }

    static let poc = Self(
        startingCashPence: 15_000_000_000,
        stationConstructionCostPence: 200_000_000,
        rollingStockUnitCostPence: 400_000_000,
        loanPrincipalPence: 4_000_000_000,
        earlyRepaymentPence: 1_000_000_000,
        loanAnnualInterestBasisPoints: 420,
        loanTermOperatingDays: 7_200,
        maximumConcurrentLoans: 3,
        insolvencyGraceOperatingDays: 7,
        lowCashThresholdPence: 1_000_000_000,
        stationValuePenceByLevel: [
            .halt: 200_000_000,
            .localStation: 300_000_000,
            .townStation: 500_000_000,
            .majorStation: 1_000_000_000,
            .interchange: 2_000_000_000,
            .terminus: 3_500_000_000,
        ]
    )
}

/// Capital spending, borrowing and company value for the milestone-four economy.
///
/// Every amount is stored as whole pence. The engine is deterministic and mutates only the
/// ledger passed to it, leaving `GameSession` as the owner of transaction boundaries.
nonisolated struct CapitalEconomy: Sendable {
    let configuration: CapitalEconomyConfiguration
    let highSpeedRail: HighSpeedRail

    init(
        configuration: CapitalEconomyConfiguration = .poc,
        highSpeedRail: HighSpeedRail = HighSpeedRail()
    ) {
        self.configuration = configuration
        self.highSpeedRail = highSpeedRail
    }

    func newLedger(mode: GameMode) -> FinanceLedger {
        FinanceLedger(
            mode: mode,
            cashBalancePence: mode == .career
                ? max(configuration.startingCashPence, 0)
                : 0
        )
    }

    func quoteForNewLine(
        constructionCostPounds: Int64,
        originCRS: String,
        destinationCRS: String,
        stationCRSs: [String]? = nil,
        existingStationCRSs: Set<String>,
        initialTrainCount: Int,
        initialFormation: RollingStockFormation = .legacyBaseline,
        railwayClass: RailwayClass = .conventional,
        existingPremiumStationCRSs: Set<String> = []
    ) -> CapitalPurchaseQuote {
        if railwayClass == .highSpeed {
            let quote = highSpeedRail.investmentQuote(
                constructionCostPounds: constructionCostPounds,
                originCRS: originCRS,
                destinationCRS: destinationCRS,
                existingPremiumStationCRSs: existingPremiumStationCRSs,
                trainCount: initialTrainCount,
                formation: initialFormation
            )
            return CapitalPurchaseQuote(
                trackAndInfrastructurePence: quote.trackAndInfrastructurePence,
                stationConstructionPence: quote.premiumStationUpgradesPence,
                rollingStockPence: quote.rollingStockPence
            )
        }

        let normalizedExisting = Set(existingStationCRSs.map(Self.normalizedCRS))
        let endpointCRSs = Set([
            Self.normalizedCRS(originCRS),
            Self.normalizedCRS(destinationCRS),
        ]).filter { !$0.isEmpty }
        let selectedStationCRSs = Set(
            (stationCRSs ?? Array(endpointCRSs)).map(Self.normalizedCRS)
        )
        .filter { !$0.isEmpty }
        .union(endpointCRSs)
        let newStationCount = selectedStationCRSs.subtracting(normalizedExisting).count
        let baseStationConstructionPence = EconomyArithmetic.multiply(
            Int64(newStationCount),
            max(configuration.stationConstructionCostPence, 0)
        )

        return CapitalPurchaseQuote(
            trackAndInfrastructurePence: EconomyArithmetic.multiply(
                max(constructionCostPounds, 0),
                100
            ),
            stationConstructionPence: baseStationConstructionPence,
            rollingStockPence: rollingStockCost(
                forTrainCount: initialTrainCount,
                formation: initialFormation,
                railwayClass: .conventional
            )
        )
    }

    func rollingStockCost(
        forTrainCount trainCount: Int,
        formation: RollingStockFormation = .legacyBaseline,
        railwayClass: RailwayClass = .conventional
    ) -> Int64 {
        if railwayClass == .highSpeed {
            return highSpeedRail.investmentQuote(
                constructionCostPounds: 0,
                originCRS: "",
                destinationCRS: "",
                existingPremiumStationCRSs: [],
                trainCount: trainCount,
                formation: formation
            ).rollingStockPence
        }
        let normalizedFormation = formation.clamped(for: .conventional)
        let unitCostPence = formationUnitCostPence(
            baseSixCarUnitCostPence: configuration.rollingStockUnitCostPence,
            formation: normalizedFormation
        )
        return EconomyArithmetic.multiply(
            Int64(clamping: max(trainCount, 0)),
            unitCostPence
        )
    }

    /// Quotes the difference between the current fleet value and the next supported formation.
    /// Every trainset owned by the line is extended together so active and spare stock cannot
    /// silently diverge. Returns nil when the formation is already at the class maximum.
    func quoteForFormationExtension(
        ownedTrainCount: Int,
        currentFormation: RollingStockFormation,
        railwayClass: RailwayClass = .conventional
    ) -> RollingStockFormationExtensionQuote? {
        let normalizedFormation = currentFormation.clamped(for: railwayClass)
        guard let upgradedFormation = normalizedFormation.next(for: railwayClass) else {
            return nil
        }
        let trainCount = max(ownedTrainCount, 0)
        let baseUnitCostPence = railwayClass == .highSpeed
            ? highSpeedRail.configuration.highSpeedTrainUnitCostPence
            : configuration.rollingStockUnitCostPence
        let incrementalUnitCostPence = formationIncrementalUnitCostPence(
            baseSixCarUnitCostPence: baseUnitCostPence,
            from: normalizedFormation,
            to: upgradedFormation
        )
        return RollingStockFormationExtensionQuote(
            currentFormation: normalizedFormation,
            upgradedFormation: upgradedFormation,
            ownedTrainCount: trainCount,
            totalCostPence: EconomyArithmetic.multiply(
                Int64(clamping: trainCount),
                incrementalUnitCostPence
            )
        )
    }

    var standardLoanOffer: StandardLoanOffer {
        let principal = max(configuration.loanPrincipalPence, 0)
        let interestBasisPoints = max(configuration.loanAnnualInterestBasisPoints, 0)
        let termDays = max(configuration.loanTermOperatingDays, 0)
        guard principal > 0, termDays > 0 else {
            return StandardLoanOffer(
                principalPence: principal,
                annualInterestBasisPoints: interestBasisPoints,
                termOperatingDays: termDays,
                firstDayInterestPence: 0,
                firstDayPrincipalPence: 0
            )
        }
        let loan = LoanAccount(
            originalPrincipalPence: principal,
            annualInterestBasisPoints: interestBasisPoints,
            termOperatingDays: termDays,
            originatedOnOperatingDay: 0
        )
        return StandardLoanOffer(
            principalPence: principal,
            annualInterestBasisPoints: interestBasisPoints,
            termOperatingDays: termDays,
            firstDayInterestPence: dailyInterest(for: loan),
            firstDayPrincipalPence: scheduledPrincipal(for: loan)
        )
    }

    func canAfford(_ quote: CapitalPurchaseQuote, ledger: FinanceLedger) -> Bool {
        canAfford(quote.totalPence, ledger: ledger)
    }

    func canAfford(_ amountPence: Int64, ledger: FinanceLedger) -> Bool {
        guard ledger.mode == .career else { return true }
        guard !ledger.isBankrupt else { return false }
        let amount = max(amountPence, 0)
        // Recovery actions such as reducing a timetable do not require a purchase and must
        // remain available while a Career company is in its insolvency grace period.
        guard amount > 0 else { return true }
        return amount != .max && ledger.cashBalancePence >= amount
    }

    func fundingShortfall(for amountPence: Int64, ledger: FinanceLedger) -> Int64 {
        guard ledger.mode == .career else { return 0 }
        return max(
            EconomyArithmetic.subtract(max(amountPence, 0), ledger.cashBalancePence),
            0
        )
    }

    @discardableResult
    func recordPurchase(
        _ quote: CapitalPurchaseQuote,
        in ledger: inout FinanceLedger
    ) -> Bool {
        guard canAfford(quote, ledger: ledger) else { return false }

        if ledger.mode == .career {
            ledger.cashBalancePence = EconomyArithmetic.subtract(
                ledger.cashBalancePence,
                quote.totalPence
            )
        }
        ledger.lifetimeConstructionSpendPence = EconomyArithmetic.add(
            ledger.lifetimeConstructionSpendPence,
            max(quote.constructionPence, 0)
        )
        ledger.lifetimeRollingStockSpendPence = EconomyArithmetic.add(
            ledger.lifetimeRollingStockSpendPence,
            max(quote.rollingStockPence, 0)
        )
        return true
    }

    @discardableResult
    func recordRollingStockPurchase(
        costPence: Int64,
        in ledger: inout FinanceLedger
    ) -> Bool {
        let cost = max(costPence, 0)
        guard canAfford(cost, ledger: ledger) else { return false }
        if ledger.mode == .career {
            ledger.cashBalancePence = EconomyArithmetic.subtract(
                ledger.cashBalancePence,
                cost
            )
        }
        ledger.lifetimeRollingStockSpendPence = EconomyArithmetic.add(
            ledger.lifetimeRollingStockSpendPence,
            cost
        )
        return true
    }

    @discardableResult
    func originateLoan(
        in ledger: inout FinanceLedger,
        onOperatingDay operatingDay: UInt64,
        id: UUID = UUID()
    ) -> Bool {
        guard ledger.mode == .career,
              !ledger.isBankrupt,
              !ledger.loans.contains(where: { $0.id == id }),
              ledger.loans.count < max(configuration.maximumConcurrentLoans, 0),
              configuration.loanPrincipalPence > 0,
              configuration.loanTermOperatingDays > 0 else { return false }

        let principal = configuration.loanPrincipalPence
        ledger.loans.append(
            LoanAccount(
                id: id,
                originalPrincipalPence: principal,
                annualInterestBasisPoints: max(
                    configuration.loanAnnualInterestBasisPoints,
                    0
                ),
                termOperatingDays: configuration.loanTermOperatingDays,
                originatedOnOperatingDay: operatingDay
            )
        )
        ledger.loans.sort { $0.id.uuidString < $1.id.uuidString }
        ledger.cashBalancePence = EconomyArithmetic.add(
            ledger.cashBalancePence,
            principal
        )
        ledger.lifetimeLoanProceedsPence = EconomyArithmetic.add(
            ledger.lifetimeLoanProceedsPence,
            principal
        )
        if ledger.cashBalancePence >= 0 {
            ledger.consecutiveNegativeCashDays = 0
        }
        return true
    }

    @discardableResult
    func makeEarlyRepayment(in ledger: inout FinanceLedger) -> Bool {
        let requested = availableEarlyRepaymentPence(in: ledger)
        guard requested > 0 else { return false }

        var remainingPayment = requested
        var principalRepaid: Int64 = 0
        ledger.loans.sort { $0.id.uuidString < $1.id.uuidString }
        for index in ledger.loans.indices where remainingPayment > 0 {
            let payment = min(
                ledger.loans[index].outstandingPrincipalPence,
                remainingPayment
            )
            ledger.loans[index].outstandingPrincipalPence -= payment
            remainingPayment -= payment
            principalRepaid = EconomyArithmetic.add(principalRepaid, payment)
        }
        ledger.loans.removeAll { $0.outstandingPrincipalPence == 0 }
        guard principalRepaid > 0 else { return false }

        ledger.cashBalancePence = EconomyArithmetic.subtract(
            ledger.cashBalancePence,
            principalRepaid
        )
        ledger.lifetimePrincipalRepaidPence = EconomyArithmetic.add(
            ledger.lifetimePrincipalRepaidPence,
            principalRepaid
        )
        return true
    }

    func availableEarlyRepaymentPence(in ledger: FinanceLedger) -> Int64 {
        guard ledger.mode == .career, !ledger.isBankrupt else { return 0 }
        return min(
            max(configuration.earlyRepaymentPence, 0),
            max(ledger.cashBalancePence, 0),
            totalDebt(in: ledger)
        )
    }

    /// Settles fare revenue, operating costs and scheduled loan payments for one day.
    /// Returns true only on the day the company first becomes bankrupt.
    @discardableResult
    func settleOperatingDay(
        operatingResultPence: Int64,
        completedOperatingDay: UInt64,
        ledger: inout FinanceLedger
    ) -> Bool {
        guard ledger.mode == .career, !ledger.isBankrupt else { return false }

        var interestPaid: Int64 = 0
        var principalRepaid: Int64 = 0
        ledger.loans.sort { $0.id.uuidString < $1.id.uuidString }
        for index in ledger.loans.indices {
            let interest = dailyInterest(for: ledger.loans[index])
            let principal = scheduledPrincipal(for: ledger.loans[index])
            interestPaid = EconomyArithmetic.add(interestPaid, interest)
            principalRepaid = EconomyArithmetic.add(principalRepaid, principal)
            ledger.loans[index].outstandingPrincipalPence -= principal
            ledger.loans[index].remainingOperatingDays = max(
                ledger.loans[index].remainingOperatingDays - 1,
                0
            )
        }
        ledger.loans.removeAll { $0.outstandingPrincipalPence == 0 }

        let debtService = EconomyArithmetic.add(interestPaid, principalRepaid)
        ledger.cashBalancePence = EconomyArithmetic.add(
            ledger.cashBalancePence,
            operatingResultPence
        )
        ledger.cashBalancePence = EconomyArithmetic.subtract(
            ledger.cashBalancePence,
            debtService
        )
        ledger.lifetimeInterestPaidPence = EconomyArithmetic.add(
            ledger.lifetimeInterestPaidPence,
            interestPaid
        )
        ledger.lifetimePrincipalRepaidPence = EconomyArithmetic.add(
            ledger.lifetimePrincipalRepaidPence,
            principalRepaid
        )

        let insolvencyGraceDays = max(configuration.insolvencyGraceOperatingDays, 1)
        if ledger.cashBalancePence < 0 {
            let previousDays = min(
                max(ledger.consecutiveNegativeCashDays, 0),
                insolvencyGraceDays
            )
            ledger.consecutiveNegativeCashDays = previousDays < insolvencyGraceDays
                ? previousDays + 1
                : insolvencyGraceDays
        } else {
            ledger.consecutiveNegativeCashDays = 0
        }

        let shouldBecomeBankrupt = ledger.consecutiveNegativeCashDays
            >= insolvencyGraceDays
        if shouldBecomeBankrupt {
            ledger.bankruptcyOperatingDay = completedOperatingDay
        }
        return shouldBecomeBankrupt
    }

    func evaluate(
        lines: [CapitalLineInput],
        stationLevelsByCRS: [String: StationLevel],
        operatingEconomy: NetworkOperatingEconomySnapshot,
        ledger: FinanceLedger,
        premiumStationCRSs: Set<String> = []
    ) -> NetworkFinanceSnapshot {
        let trackValue = lines.reduce(Int64(0)) { result, line in
            EconomyArithmetic.add(
                result,
                EconomyArithmetic.add(
                    trackConstructionCostPence(
                        constructionCostPounds: line.constructionCostPounds,
                        railwayClass: line.railwayClass
                    ),
                    line.railwayClass == .highSpeed
                        ? 0
                        : max(line.infrastructureUpgradeValuePence, 0)
                )
            )
        }
        let rollingStockValue = lines.reduce(Int64(0)) { result, line in
            EconomyArithmetic.add(
                result,
                rollingStockCost(
                    forTrainCount: line.ownedTrainCount,
                    formation: line.formation,
                    railwayClass: line.railwayClass
                )
            )
        }
        let normalizedLevels = stationLevelsByCRS.reduce(into: [String: StationLevel]()) {
            result,
            item in
            let crs = Self.normalizedCRS(item.key)
            guard !crs.isEmpty else { return }
            result[crs] = max(result[crs] ?? .halt, item.value)
        }
        let baseStationValue = normalizedLevels.values.reduce(Int64(0)) { result, level in
            EconomyArithmetic.add(
                result,
                max(configuration.stationValuePenceByLevel[level] ?? 0, 0)
            )
        }
        let normalizedPremiumStationCRSs = Set(
            premiumStationCRSs.map(Self.normalizedCRS).filter { !$0.isEmpty }
        ).intersection(normalizedLevels.keys)
        let premiumStationValue = EconomyArithmetic.multiply(
            Int64(clamping: normalizedPremiumStationCRSs.count),
            max(highSpeedRail.configuration.premiumStationUpgradeCostPence, 0)
        )
        let stationValue = EconomyArithmetic.add(baseStationValue, premiumStationValue)
        let networkValue = EconomyArithmetic.add(
            EconomyArithmetic.add(trackValue, stationValue),
            rollingStockValue
        )
        let debt = totalDebt(in: ledger)
        let interest = ledger.loans.reduce(Int64(0)) {
            EconomyArithmetic.add($0, dailyInterest(for: $1))
        }
        let principal = ledger.loans.reduce(Int64(0)) {
            EconomyArithmetic.add($0, scheduledPrincipal(for: $1))
        }
        let projectedProfit = EconomyArithmetic.subtract(
            operatingEconomy.operatingResultPencePerDay,
            interest
        )
        let projectedCashChange = EconomyArithmetic.subtract(
            projectedProfit,
            principal
        )
        let assetsAndCash = EconomyArithmetic.add(
            networkValue,
            ledger.mode == .career ? ledger.cashBalancePence : 0
        )
        let netCompanyValue = EconomyArithmetic.subtract(assetsAndCash, debt)

        return NetworkFinanceSnapshot(
            trackAndInfrastructureValuePence: trackValue,
            stationValuePence: stationValue,
            rollingStockValuePence: rollingStockValue,
            networkValuePence: networkValue,
            outstandingDebtPence: debt,
            projectedInterestPencePerDay: interest,
            projectedPrincipalRepaymentPencePerDay: principal,
            projectedProfitPencePerDay: projectedProfit,
            projectedCashChangePencePerDay: projectedCashChange,
            netCompanyValuePence: netCompanyValue,
            commercialViability: viability(for: projectedProfit),
            financialHealth: financialHealth(for: ledger),
            canBorrow: ledger.mode == .career
                && !ledger.isBankrupt
                && ledger.loans.count < max(configuration.maximumConcurrentLoans, 0),
            canMakeEarlyRepayment: ledger.mode == .career
                && !ledger.isBankrupt
                && ledger.cashBalancePence > 0
                && debt > 0
        )
    }

    func totalDebt(in ledger: FinanceLedger) -> Int64 {
        ledger.loans.reduce(Int64(0)) {
            EconomyArithmetic.add($0, max($1.outstandingPrincipalPence, 0))
        }
    }

    private func trackConstructionCostPence(
        constructionCostPounds: Int64,
        railwayClass: RailwayClass
    ) -> Int64 {
        let conventionalCost = EconomyArithmetic.multiply(
            max(constructionCostPounds, 0),
            100
        )
        guard railwayClass == .highSpeed else { return conventionalCost }
        return highSpeedRail.investmentQuote(
            constructionCostPounds: constructionCostPounds,
            originCRS: "",
            destinationCRS: "",
            existingPremiumStationCRSs: [],
            trainCount: 0
        ).trackAndInfrastructurePence
    }

    private func formationUnitCostPence(
        baseSixCarUnitCostPence: Int64,
        formation: RollingStockFormation
    ) -> Int64 {
        EconomyArithmetic.scaled(
            max(baseSixCarUnitCostPence, 0),
            multiplier: Int64(formation.carriageCount),
            divisor: Int64(RollingStockFormation.legacyBaseline.carriageCount)
        )
    }

    /// Computes `floor(base * newCars / 6) - floor(base * oldCars / 6)` without
    /// overflowing either full formation value. This keeps a two-car extension quote useful
    /// even when the eventual twelve-car asset value itself saturates.
    private func formationIncrementalUnitCostPence(
        baseSixCarUnitCostPence: Int64,
        from currentFormation: RollingStockFormation,
        to upgradedFormation: RollingStockFormation
    ) -> Int64 {
        let baseCost = max(baseSixCarUnitCostPence, 0)
        let divisor = Int64(RollingStockFormation.legacyBaseline.carriageCount)
        let whole = baseCost / divisor
        let remainder = baseCost % divisor
        let carriageDelta = Int64(
            max(upgradedFormation.carriageCount - currentFormation.carriageCount, 0)
        )
        let wholeDelta = EconomyArithmetic.multiply(whole, carriageDelta)
        let currentRemainder = remainder * Int64(currentFormation.carriageCount) / divisor
        let upgradedRemainder = remainder * Int64(upgradedFormation.carriageCount) / divisor
        return EconomyArithmetic.add(
            wholeDelta,
            max(upgradedRemainder - currentRemainder, 0)
        )
    }

    private func dailyInterest(for loan: LoanAccount) -> Int64 {
        EconomyArithmetic.scaledCeiling(
            max(loan.outstandingPrincipalPence, 0),
            multiplier: Int64(max(loan.annualInterestBasisPoints, 0)),
            divisor: 10_000 * 360
        )
    }

    private func scheduledPrincipal(for loan: LoanAccount) -> Int64 {
        let outstanding = max(loan.outstandingPrincipalPence, 0)
        guard outstanding > 0 else { return 0 }
        let remainingDays = max(loan.remainingOperatingDays, 1)
        let quotient = outstanding / Int64(remainingDays)
        let remainder = outstanding % Int64(remainingDays)
        return EconomyArithmetic.add(quotient, remainder == 0 ? 0 : 1)
    }

    private func viability(for projectedProfit: Int64) -> CommercialViability {
        if projectedProfit > 100_000 { return .profitable }
        if projectedProfit >= 0 { return .marginal }
        return .lossMaking
    }

    private func financialHealth(for ledger: FinanceLedger) -> FinancialHealth {
        guard ledger.mode == .career else { return .zen }
        if ledger.isBankrupt { return .bankrupt }
        if ledger.cashBalancePence < 0 {
            return .insolvent(
                daysRemaining: max(
                    configuration.insolvencyGraceOperatingDays
                        - ledger.consecutiveNegativeCashDays,
                    0
                )
            )
        }
        if ledger.cashBalancePence < max(configuration.lowCashThresholdPence, 0) {
            return .lowCash
        }
        return .healthy
    }

    private static func normalizedCRS(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

/// Saturating whole-number arithmetic shared by both operating and capital economics.
nonisolated enum EconomyArithmetic {
    static func add(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        guard overflow else { return result }
        return rhs >= 0 ? .max : .min
    }

    static func subtract(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (result, overflow) = lhs.subtractingReportingOverflow(rhs)
        guard overflow else { return result }
        return rhs >= 0 ? .min : .max
    }

    static func multiply(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        guard lhs != 0, rhs != 0 else { return 0 }
        let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard overflow else { return result }
        return (lhs > 0) == (rhs > 0) ? .max : .min
    }

    static func scaled(_ value: Int64, multiplier: Int64, divisor: Int64) -> Int64 {
        guard value > 0, multiplier > 0, divisor > 0 else { return 0 }

        let unsignedValue = UInt64(value)
        let unsignedMultiplier = UInt64(multiplier)
        let unsignedDivisor = UInt64(divisor)
        let product = unsignedValue.multipliedFullWidth(by: unsignedMultiplier)

        // `dividingFullWidth` requires the high word to be smaller than the divisor. If it is
        // not, the quotient cannot fit in one UInt64 and therefore cannot fit in Int64 either.
        guard product.high < unsignedDivisor else { return .max }
        let quotient = unsignedDivisor.dividingFullWidth(product).quotient
        guard quotient <= UInt64(Int64.max) else { return .max }
        return Int64(quotient)
    }

    static func scaledCeiling(
        _ value: Int64,
        multiplier: Int64,
        divisor: Int64
    ) -> Int64 {
        guard value > 0, multiplier > 0, divisor > 0 else { return 0 }

        let unsignedDivisor = UInt64(divisor)
        let product = UInt64(value).multipliedFullWidth(by: UInt64(multiplier))
        guard product.high < unsignedDivisor else { return .max }
        let division = unsignedDivisor.dividingFullWidth(product)
        let rounded: UInt64
        if division.remainder == 0 {
            rounded = division.quotient
        } else {
            let incremented = division.quotient.addingReportingOverflow(1)
            guard !incremented.overflow else { return .max }
            rounded = incremented.partialValue
        }
        guard rounded <= UInt64(Int64.max) else { return .max }
        return Int64(rounded)
    }
}
