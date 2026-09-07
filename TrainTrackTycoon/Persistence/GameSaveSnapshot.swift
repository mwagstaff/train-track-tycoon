import Foundation

/// The durable, route-independent representation of a running game.
///
/// Route geometry is deliberately not stored. A restore resolves each physical corridor again
/// from its station CRS codes, which keeps save files small and lets the bundled railway graph
/// evolve independently from train services.
nonisolated struct GameSaveSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 12
    /// A generous corruption/safety ceiling rather than a gameplay-sized network limit. Five
    /// hundred services, each able to contain many calls, can represent the national network
    /// while still placing a deterministic upper bound on malformed save files.
    static let maximumServiceCount = 512
    /// Compatibility spelling retained while the game migrates from lines to explicit services.
    static let maximumLineCount = maximumServiceCount
    static let maximumCorridorCount = 1_024
    static let maximumStationsPerCorridor = 256
    /// Active timetables remain bounded to four visible trains, while destructive through-service
    /// merges retain the paid fleets from both source services as bounded spare rolling stock.
    static let maximumTrainsPerLine = 4
    /// Keep the per-service spare-fleet safety bound independent of the nationwide service-count
    /// ceiling. Raising the number of services must not silently allow one joined service to
    /// retain hundreds of trainsets.
    static let maximumOwnedTrainCountPerService = 48
    static let maximumActiveLoanCount = 3

    let schemaVersion: Int
    let savedAt: Date
    let isPlaying: Bool
    let simulationSpeed: SavedSimulationSpeed
    let corridors: [SavedRailwayCorridorRecord]
    /// Durable train services. The `lines` spelling remains for source compatibility.
    let lines: [SavedLineRecord]
    let stationProgress: [SavedStationProgressRecord]
    let stationPopulations: [SavedStationPopulationRecord]
    let economy: SavedEconomyLedger
    let financialState: SavedFinancialState
    let publicBetaHistory: PublicBetaDailyNetworkHistory

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        savedAt: Date = .now,
        isPlaying: Bool,
        simulationSpeed: SavedSimulationSpeed,
        lines: [SavedLineRecord],
        corridors: [SavedRailwayCorridorRecord]? = nil,
        stationProgress: [SavedStationProgressRecord] = [],
        stationPopulations: [SavedStationPopulationRecord] = [],
        economy: SavedEconomyLedger = .zero,
        financialState: SavedFinancialState = .zero,
        publicBetaHistory: PublicBetaDailyNetworkHistory = PublicBetaDailyNetworkHistory()
    ) {
        self.schemaVersion = schemaVersion
        self.savedAt = savedAt
        self.isPlaying = isPlaying
        self.simulationSpeed = simulationSpeed
        self.corridors = corridors ?? Self.compatibilityCorridors(for: lines)
        self.lines = lines
        self.stationProgress = stationProgress
        self.stationPopulations = stationPopulations
        self.economy = economy
        self.financialState = financialState
        self.publicBetaHistory = publicBetaHistory
    }

    /// Projects the historical one-line/one-corridor model into the separated infrastructure
    /// representation introduced in schema 11. Callers creating a through service across multiple
    /// corridors must pass the explicit `corridors` collection.
    private static func compatibilityCorridors(
        for lines: [SavedLineRecord]
    ) -> [SavedRailwayCorridorRecord] {
        var recordsByID = [UUID: SavedRailwayCorridorRecord]()
        for line in lines where line.corridorIDs.count == 1 {
            guard let corridorID = line.corridorIDs.first, recordsByID[corridorID] == nil else {
                continue
            }
            recordsByID[corridorID] = SavedRailwayCorridorRecord(
                id: corridorID,
                stationCRSs: line.stationCRSs,
                constructionProgress: line.constructionProgress,
                railwayClass: line.railwayClass,
                trackCapacity: line.trackCapacity
            )
        }
        return recordsByID.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}

/// Durable settlement-growth state for one station used by a saved service.
///
/// Baseline catalogue population is deliberately reconciled by `GameSession` when an older save
/// migrates. Schema 11 and later contain one explicit record for every station in a saved corridor;
/// stations under construction remain at baseline until their service opens.
nonisolated struct SavedStationPopulationRecord: Codable, Equatable, Sendable {
    let stationCRS: String
    let currentPopulation: Int64
    let latestOperatingDayChange: Int64

    init(
        stationCRS: String,
        currentPopulation: Int64,
        latestOperatingDayChange: Int64
    ) {
        self.stationCRS = stationCRS
        self.currentPopulation = currentPopulation
        self.latestOperatingDayChange = latestOperatingDayChange
    }
}

nonisolated enum SavedStationLevel: String, CaseIterable, Codable, Equatable, Sendable {
    case halt
    case localStation
    case townStation
    case majorStation
    case interchange
    case terminus
}

nonisolated struct SavedStationProgressRecord: Codable, Equatable, Sendable {
    let stationCRS: String
    let level: SavedStationLevel
    let lifetimePassengerVisits: Int64

    init(
        stationCRS: String,
        level: SavedStationLevel,
        lifetimePassengerVisits: Int64
    ) {
        self.stationCRS = stationCRS
        self.level = level
        self.lifetimePassengerVisits = lifetimePassengerVisits
    }
}

nonisolated struct SavedEconomyLedger: Codable, Equatable, Sendable {
    let completedOperatingDays: UInt64
    let operatingDayProgress: Double
    let lifetimeRevenuePence: Int64
    let lifetimeOperatingCostPence: Int64

    init(
        completedOperatingDays: UInt64,
        operatingDayProgress: Double,
        lifetimeRevenuePence: Int64,
        lifetimeOperatingCostPence: Int64
    ) {
        self.completedOperatingDays = completedOperatingDays
        self.operatingDayProgress = operatingDayProgress
        self.lifetimeRevenuePence = lifetimeRevenuePence
        self.lifetimeOperatingCostPence = lifetimeOperatingCostPence
    }

    static let zero = SavedEconomyLedger(
        completedOperatingDays: 0,
        operatingDayProgress: 0,
        lifetimeRevenuePence: 0,
        lifetimeOperatingCostPence: 0
    )
}

/// Durable source state for capital spending, borrowing and Career-mode solvency.
///
/// Projected profit, total debt and network value are deliberately derived rather than
/// duplicated here. This keeps the save internally consistent when routes or tuning evolve.
nonisolated struct SavedFinancialState: Codable, Equatable, Sendable {
    let mode: GameMode
    let cashBalancePence: Int64
    let loans: [SavedLoanAccount]
    let lifetimeConstructionSpendPence: Int64
    let lifetimeRollingStockSpendPence: Int64
    let lifetimeLoanProceedsPence: Int64
    let lifetimePrincipalRepaidPence: Int64
    let lifetimeInterestPaidPence: Int64
    /// True when a migrated game already contained assets whose original prices are unknowable.
    let hasIncompleteCapitalHistory: Bool
    let consecutiveNegativeCashDays: Int
    let bankruptcyOperatingDay: UInt64?
    /// The first completed operating day for which capital statistics are complete.
    /// Legacy saves can contain assets whose historical purchase prices are unknowable.
    let trackingStartedOnOperatingDay: UInt64

    init(
        mode: GameMode,
        cashBalancePence: Int64,
        loans: [SavedLoanAccount],
        lifetimeConstructionSpendPence: Int64,
        lifetimeRollingStockSpendPence: Int64,
        lifetimeLoanProceedsPence: Int64,
        lifetimePrincipalRepaidPence: Int64,
        lifetimeInterestPaidPence: Int64,
        hasIncompleteCapitalHistory: Bool = false,
        consecutiveNegativeCashDays: Int,
        bankruptcyOperatingDay: UInt64?,
        trackingStartedOnOperatingDay: UInt64
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
        self.consecutiveNegativeCashDays = consecutiveNegativeCashDays
        self.bankruptcyOperatingDay = bankruptcyOperatingDay
        self.trackingStartedOnOperatingDay = trackingStartedOnOperatingDay
    }

    init(
        ledger: FinanceLedger,
        trackingStartedOnOperatingDay: UInt64
    ) {
        self.init(
            mode: ledger.mode,
            cashBalancePence: ledger.cashBalancePence,
            loans: ledger.loans
                .map(SavedLoanAccount.init)
                .sorted { $0.id.uuidString < $1.id.uuidString },
            lifetimeConstructionSpendPence: ledger.lifetimeConstructionSpendPence,
            lifetimeRollingStockSpendPence: ledger.lifetimeRollingStockSpendPence,
            lifetimeLoanProceedsPence: ledger.lifetimeLoanProceedsPence,
            lifetimePrincipalRepaidPence: ledger.lifetimePrincipalRepaidPence,
            lifetimeInterestPaidPence: ledger.lifetimeInterestPaidPence,
            hasIncompleteCapitalHistory: ledger.hasIncompleteCapitalHistory,
            consecutiveNegativeCashDays: ledger.consecutiveNegativeCashDays,
            bankruptcyOperatingDay: ledger.bankruptcyOperatingDay,
            trackingStartedOnOperatingDay: trackingStartedOnOperatingDay
        )
    }

    static let zero = migratedZen(trackingStartedOnOperatingDay: 0)

    static func migratedZen(
        trackingStartedOnOperatingDay: UInt64,
        hasIncompleteCapitalHistory: Bool = false
    ) -> SavedFinancialState {
        SavedFinancialState(
            mode: .zen,
            cashBalancePence: 0,
            loans: [],
            lifetimeConstructionSpendPence: 0,
            lifetimeRollingStockSpendPence: 0,
            lifetimeLoanProceedsPence: 0,
            lifetimePrincipalRepaidPence: 0,
            lifetimeInterestPaidPence: 0,
            hasIncompleteCapitalHistory: hasIncompleteCapitalHistory,
            consecutiveNegativeCashDays: 0,
            bankruptcyOperatingDay: nil,
            trackingStartedOnOperatingDay: trackingStartedOnOperatingDay
        )
    }

    var financeLedger: FinanceLedger {
        FinanceLedger(
            mode: mode,
            cashBalancePence: cashBalancePence,
            loans: loans
                .map(\.loanAccount)
                .sorted { $0.id.uuidString < $1.id.uuidString },
            lifetimeConstructionSpendPence: lifetimeConstructionSpendPence,
            lifetimeRollingStockSpendPence: lifetimeRollingStockSpendPence,
            lifetimeLoanProceedsPence: lifetimeLoanProceedsPence,
            lifetimePrincipalRepaidPence: lifetimePrincipalRepaidPence,
            lifetimeInterestPaidPence: lifetimeInterestPaidPence,
            hasIncompleteCapitalHistory: hasIncompleteCapitalHistory,
            trackingStartedOnOperatingDay: trackingStartedOnOperatingDay,
            consecutiveNegativeCashDays: consecutiveNegativeCashDays,
            bankruptcyOperatingDay: bankruptcyOperatingDay
        )
    }
}

nonisolated struct SavedLoanAccount: Codable, Equatable, Sendable {
    let id: UUID
    let originalPrincipalPence: Int64
    let outstandingPrincipalPence: Int64
    let annualInterestBasisPoints: Int
    let termOperatingDays: Int
    let remainingOperatingDays: Int
    let originatedOnOperatingDay: UInt64

    init(
        id: UUID,
        originalPrincipalPence: Int64,
        outstandingPrincipalPence: Int64,
        annualInterestBasisPoints: Int,
        termOperatingDays: Int,
        remainingOperatingDays: Int,
        originatedOnOperatingDay: UInt64
    ) {
        self.id = id
        self.originalPrincipalPence = originalPrincipalPence
        self.outstandingPrincipalPence = outstandingPrincipalPence
        self.annualInterestBasisPoints = annualInterestBasisPoints
        self.termOperatingDays = termOperatingDays
        self.remainingOperatingDays = remainingOperatingDays
        self.originatedOnOperatingDay = originatedOnOperatingDay
    }

    init(_ loan: LoanAccount) {
        self.init(
            id: loan.id,
            originalPrincipalPence: loan.originalPrincipalPence,
            outstandingPrincipalPence: loan.outstandingPrincipalPence,
            annualInterestBasisPoints: loan.annualInterestBasisPoints,
            termOperatingDays: loan.termOperatingDays,
            remainingOperatingDays: loan.remainingOperatingDays,
            originatedOnOperatingDay: loan.originatedOnOperatingDay
        )
    }

    var loanAccount: LoanAccount {
        LoanAccount(
            id: id,
            originalPrincipalPence: originalPrincipalPence,
            outstandingPrincipalPence: outstandingPrincipalPence,
            annualInterestBasisPoints: annualInterestBasisPoints,
            termOperatingDays: termOperatingDays,
            remainingOperatingDays: remainingOperatingDays,
            originatedOnOperatingDay: originatedOnOperatingDay
        )
    }
}

nonisolated enum SavedSimulationSpeed: String, Codable, Equatable, Sendable {
    case oneX
    case threeX
}

nonisolated enum SavedServiceFrequency: String, CaseIterable, Codable, Equatable, Sendable {
    case hourly
    case halfHourly
    case quarterHourly

    var visibleTrainCount: Int {
        switch self {
        case .hourly: 1
        case .halfHourly: 2
        case .quarterHourly: 4
        }
    }
}

extension SavedServiceFrequency {
    init(_ frequency: ServiceFrequency) {
        switch frequency {
        case .hourly: self = .hourly
        case .halfHourly: self = .halfHourly
        case .quarterHourly: self = .quarterHourly
        }
    }
}

extension ServiceFrequency {
    init(_ frequency: SavedServiceFrequency) {
        switch frequency {
        case .hourly: self = .hourly
        case .halfHourly: self = .halfHourly
        case .quarterHourly: self = .quarterHourly
        }
    }
}

nonisolated enum SavedServicePattern: String, CaseIterable, Codable, Equatable, Sendable {
    case local
    case balanced
    case express
}

nonisolated enum SavedTrainServiceRole: String, CaseIterable, Codable, Equatable, Sendable {
    case local
    case express
}

extension SavedTrainServiceRole {
    nonisolated init(_ role: TrainServiceRole) {
        switch role {
        case .local: self = .local
        case .express: self = .express
        }
    }
}

extension TrainServiceRole {
    nonisolated init(_ role: SavedTrainServiceRole) {
        switch role {
        case .local: self = .local
        case .express: self = .express
        }
    }
}

/// One durable Local or Express operating plan keyed to a stable timetable slot rather than a
/// replaceable train identity.
nonisolated struct SavedTrainServicePlan: Codable, Equatable, Sendable {
    let slotIndex: Int
    let role: SavedTrainServiceRole
    let stationCRSs: [String]

    init(
        slotIndex: Int,
        role: SavedTrainServiceRole,
        stationCRSs: [String]
    ) {
        self.slotIndex = slotIndex
        self.role = role
        self.stationCRSs = stationCRSs
    }

    init(_ plan: TrainServicePlan) {
        self.init(
            slotIndex: plan.slotIndex,
            role: SavedTrainServiceRole(plan.role),
            stationCRSs: plan.stationCRSs
        )
    }

    var trainServicePlan: TrainServicePlan {
        TrainServicePlan(
            slotIndex: slotIndex,
            role: TrainServiceRole(role),
            stationCRSs: stationCRSs
        )
    }

    static func legacyDefaults(
        servicePattern: SavedServicePattern,
        serviceStationCRSs: [String],
        slotCount: Int = GameSaveSnapshot.maximumTrainsPerLine
    ) -> [Self] {
        TrainServicePlan.legacyDefaults(
            servicePattern: ServicePattern(servicePattern),
            serviceStationCRSs: serviceStationCRSs,
            slotCount: slotCount
        ).map(Self.init)
    }
}

extension SavedServicePattern {
    nonisolated init(_ pattern: ServicePattern) {
        switch pattern {
        case .local: self = .local
        case .balanced: self = .balanced
        case .express: self = .express
        }
    }
}

extension ServicePattern {
    nonisolated init(_ pattern: SavedServicePattern) {
        switch pattern {
        case .local: self = .local
        case .balanced: self = .balanced
        case .express: self = .express
        }
    }
}

nonisolated enum SavedTrackCapacity: String, CaseIterable, Codable, Equatable, Sendable {
    case singleTrack
    case passingLoop
    case doubleTrack
}

nonisolated enum SavedRailwayClass: String, CaseIterable, Codable, Equatable, Sendable {
    case conventional
    case highSpeed
}

extension SavedRailwayClass {
    init(_ railwayClass: RailwayClass) {
        switch railwayClass {
        case .conventional: self = .conventional
        case .highSpeed: self = .highSpeed
        }
    }
}

extension RailwayClass {
    nonisolated init(_ railwayClass: SavedRailwayClass) {
        switch railwayClass {
        case .conventional: self = .conventional
        case .highSpeed: self = .highSpeed
        }
    }
}

extension SavedTrackCapacity {
    init(_ capacity: TrackCapacity) {
        switch capacity {
        case .singleTrack: self = .singleTrack
        case .passingLoop: self = .passingLoop
        case .doubleTrack: self = .doubleTrack
        }
    }
}

extension TrackCapacity {
    init(_ capacity: SavedTrackCapacity) {
        switch capacity {
        case .singleTrack: self = .singleTrack
        case .passingLoop: self = .passingLoop
        case .doubleTrack: self = .doubleTrack
        }
    }
}

/// Durable physical railway infrastructure, independent from the services that operate over it.
///
/// Geometry and cost are derived when restoring. Construction progress and infrastructure
/// choices are sources of truth, while historical capital totals remain untouched by migration.
nonisolated struct SavedRailwayCorridorRecord: Codable, Equatable, Sendable {
    let id: UUID
    /// Ordered physical stations defining the route through the bundled railway graph.
    let stationCRSs: [String]
    let constructionProgress: Double
    let railwayClass: SavedRailwayClass
    let trackCapacity: SavedTrackCapacity

    init(
        id: UUID,
        stationCRSs: [String],
        constructionProgress: Double,
        railwayClass: SavedRailwayClass = .conventional,
        trackCapacity: SavedTrackCapacity = .singleTrack
    ) {
        self.id = id
        self.stationCRSs = stationCRSs
        self.constructionProgress = constructionProgress
        self.railwayClass = railwayClass
        self.trackCapacity = trackCapacity
    }
}

nonisolated struct SavedLineRecord: Codable, Equatable, Sendable {
    /// Stable service identity. The `id` spelling remains for source compatibility.
    let id: UUID
    /// Ordered identities of the physical corridors used by this service.
    ///
    /// Schema 1--10 migrations use the historical line ID, creating a deterministic one-service,
    /// one-corridor mapping without changing capital ownership or recording a transaction.
    let corridorIDs: [UUID]
    let originCRS: String
    let destinationCRS: String
    /// Ordered stations called at by this service, including both endpoints.
    let stationCRSs: [String]
    let styleIndex: Int
    let constructionProgress: Double
    let frequency: SavedServiceFrequency
    let servicePattern: SavedServicePattern
    /// Exactly four stable timetable-slot plans. Reducing frequency leaves inactive slot plans
    /// intact so a later increase restores the player's Local/Express service design.
    let trainServicePlans: [SavedTrainServicePlan]
    let trackCapacity: SavedTrackCapacity
    let railwayClass: SavedRailwayClass
    /// The purchased carriage count shared by every trainset assigned to this line.
    ///
    /// Schema 10 and later store this explicitly. Older schemas are migrated to the historical
    /// six-car capacity baseline without changing their recorded capital spend.
    let formation: RollingStockFormation
    let ownedTrainCount: Int
    let trains: [SavedTrainRecord]

    /// Temporary source-compatibility for code that still models one train per line.
    /// Persisted snapshots are validated to contain at least one train before they are returned.
    var train: SavedTrainRecord { trains[0] }

    init(
        id: UUID,
        originCRS: String,
        destinationCRS: String,
        styleIndex: Int,
        constructionProgress: Double,
        frequency: SavedServiceFrequency,
        railwayClass: SavedRailwayClass = .conventional,
        formation: RollingStockFormation = .legacyBaseline,
        servicePattern: SavedServicePattern = .balanced,
        trackCapacity: SavedTrackCapacity = .singleTrack,
        ownedTrainCount: Int? = nil,
        trains: [SavedTrainRecord],
        corridorIDs: [UUID]? = nil,
        stationCRSs: [String]? = nil,
        trainServicePlans: [SavedTrainServicePlan]? = nil
    ) {
        let resolvedStationCRSs = stationCRSs ?? [originCRS, destinationCRS]
        self.id = id
        self.corridorIDs = corridorIDs ?? [id]
        self.originCRS = originCRS
        self.destinationCRS = destinationCRS
        self.stationCRSs = resolvedStationCRSs
        self.styleIndex = styleIndex
        self.constructionProgress = constructionProgress
        self.frequency = frequency
        self.servicePattern = servicePattern
        self.trainServicePlans = trainServicePlans ?? SavedTrainServicePlan.legacyDefaults(
            servicePattern: servicePattern,
            serviceStationCRSs: resolvedStationCRSs
        )
        self.trackCapacity = trackCapacity
        self.railwayClass = railwayClass
        self.formation = formation
        self.ownedTrainCount = ownedTrainCount ?? trains.count
        self.trains = trains
    }

    /// Compatibility initializer for the schema-v1, single-train game model.
    init(
        id: UUID,
        originCRS: String,
        destinationCRS: String,
        styleIndex: Int,
        constructionProgress: Double,
        train: SavedTrainRecord
    ) {
        self.id = id
        corridorIDs = [id]
        self.originCRS = originCRS
        self.destinationCRS = destinationCRS
        stationCRSs = [originCRS, destinationCRS]
        self.styleIndex = styleIndex
        self.constructionProgress = constructionProgress
        frequency = .halfHourly
        servicePattern = .balanced
        trainServicePlans = SavedTrainServicePlan.legacyDefaults(
            servicePattern: .balanced,
            serviceStationCRSs: [originCRS, destinationCRS]
        )
        trackCapacity = .singleTrack
        railwayClass = .conventional
        formation = .legacyBaseline
        ownedTrainCount = SavedServiceFrequency.halfHourly.visibleTrainCount
        trains = [train]
    }

    /// Explicit service terminology for code migrating away from the overloaded `line.id` name.
    var serviceID: UUID { id }

    /// Source-compatible convenience for the historical one-service, one-corridor model.
    var corridorID: UUID { corridorIDs.first ?? id }
}

nonisolated struct SavedTrainRecord: Codable, Equatable, Sendable {
    let id: UUID
    /// Position along the line, where zero is the origin and one is the destination.
    let normalizedRouteProgress: Double
    let direction: SavedTrainDirection
    let dwellRemaining: TimeInterval

    init(
        id: UUID,
        normalizedRouteProgress: Double,
        direction: SavedTrainDirection,
        dwellRemaining: TimeInterval
    ) {
        self.id = id
        self.normalizedRouteProgress = normalizedRouteProgress
        self.direction = direction
        self.dwellRemaining = dwellRemaining
    }
}

nonisolated enum SavedTrainDirection: String, Codable, Equatable, Sendable {
    case forward
    case reverse
}
