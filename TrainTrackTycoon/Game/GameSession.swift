import CoreLocation
import Foundation
import Observation

/// Presentation facts resolved in one network pass for the small set of trains MapKit will draw.
/// Keeping line lookup, service-role lookup and overtaking detection together prevents each
/// visible annotation from repeatedly searching the entire national network.
nonisolated struct TrainPresentationSnapshot: Identifiable {
    let train: TrainState
    let number: Int
    let lineName: String
    let lineStyleIndex: Int
    let railwayClass: RailwayClass
    let seatsPerTrain: Int
    let serviceRole: TrainServiceRole
    let formation: TrainFormationSnapshot
    let isOvertaking: Bool
    let passengerFeedbackTitle: String

    var id: UUID { train.id }
}

/// A transient, map-initiated request to add one real catalogue station to existing railway
/// infrastructure. The proposal is deliberately not persisted: only a confirmed station asset
/// and its resulting service calls belong in the save game.
nonisolated struct MapStationAdditionProposal: Identifiable, Equatable, Sendable {
    let station: Station
    let options: [MapStationAdditionOption]

    var id: String { station.crs }
}

/// One compatible service for a station selected directly on the map.
///
/// `resultingStationNames` is prepared by the domain layer from the same corridor insertion used
/// by confirmation. Presentation code therefore never has to guess where the new call belongs.
nonisolated struct MapStationAdditionOption: Identifiable, Equatable, Sendable {
    let lineID: UUID
    let lineNumber: Int
    let lineName: String
    let resultingStationCRSs: [String]
    let resultingStationNames: [String]
    let costPence: Int64
    let isAffordable: Bool
    let servicePattern: ServicePattern

    var id: UUID { lineID }
}

@MainActor
@Observable
final class GameSession {
    /// Display-link ticks should never represent offline catch-up. Bounding a single tick keeps
    /// malformed or synthetic deltas from turning the 30-second day loop into unbounded work.
    private static let maximumSimulatedSecondsPerTick: TimeInterval = 3_600
    private static let maximumOperatingDaySettlementsPerTick = 120
    private static let maximumBufferedPresentationEvents = 32
    private static let maximumTrainArrivalPresentationEventsPerTick = 12

    private struct TrainArrivalBatch {
        private(set) var stationIndices: [Int] = []
        private(set) var count = 0

        mutating func record(stationIndex: Int) {
            guard stationIndex >= 0 else { return }
            if count < .max {
                count += 1
            }
            if stationIndices.count < GameSession.maximumBufferedPresentationEvents {
                stationIndices.append(stationIndex)
            }
        }
    }

    private struct TrainMovementTopology {
        let stationDistances: [CLLocationDistance]
        let stationIndicesByCRS: [String: Int]
    }

    /// Immutable calling-point geometry prepared once for one active timetable slot.
    ///
    /// A national express can contain hundreds of calls. Keeping these resolved distances out of
    /// `advanceTrain` avoids remapping, filtering, and sorting that complete list for every train
    /// on every display-link tick.
    private struct TrainMovementPlanTopology {
        struct Call {
            let stationIndex: Int
            let distance: CLLocationDistance
        }

        struct Stop {
            /// Synthetic passing-loop stops deliberately have no station arrival to present.
            let stationIndex: Int?
            let distance: CLLocationDistance
        }

        let role: TrainServiceRole
        let lowerCall: Call?
        let upperCall: Call?
        let intermediateStops: [Stop]
    }

    private struct CorridorStationPosition {
        let crs: String
        let coordinateIndex: Int
    }

    private struct IntermediateStationInsertionPlan {
        let corridorStationCRSs: [String]
        let corridorRoute: ServiceRailwayRoute
        let serviceStationCRSs: [String]
        let serviceRoute: ServiceRailwayRoute
    }

    private struct MapStationAdditionDiscoveryInput: Sendable {
        let line: BuiltLine
        let lowerRouteDistance: CLLocationDistance
        let upperRouteDistance: CLLocationDistance
    }

    private struct MapStationAdditionDiscoveryResult: Sendable {
        let input: MapStationAdditionDiscoveryInput
        let match: CorridorStationMatch
    }

    private struct PendingMapStationAdditionOption {
        let sourceLine: BuiltLine
        let match: CorridorStationMatch
    }

    private struct ThroughServiceMergePlan {
        let option: ThroughServiceOption
        let assembly: RailwayCorridorChainAssembly
        let serviceRoute: ServiceRailwayRoute
        let primaryStationCRSs: [String]
        let primaryIsReversed: Bool
        let trainServicePlans: [TrainServicePlan]
    }

    private struct OrientedServiceCorridorChain {
        let corridors: [RailwayCorridor]
    }

    private struct LogicalServiceRun {
        let identifier: Int
        let stationCRSs: [String]
        let scheduledDeparturesPerHour: Double
    }

    let stations: [Station]

    private(set) var phase: GamePhase = .idle
    private(set) var selectedOrigin: Station?
    private(set) var selectedDestination: Station?
    /// Catalogue CRS codes that the player can select in the current builder step. The production
    /// router derives these from OSM connected components, so displaying this set never requires a
    /// shortest-path calculation per station.
    private(set) var eligibleBuildStationCRSs = Set<String>()
    private(set) var isLoadingBuildStationEligibility = false
    private(set) var hasResolvedBuildStationEligibility = false
    private(set) var preview: LinePreview?
    private(set) var previewIntermediateStations: [Station] = []
    private(set) var previewSelectedStationCRSs: [String] = []
    private(set) var isUpdatingPreviewRoute = false
    private(set) var lines: [BuiltLine] = []
    /// A structure-only count for chrome that must not subscribe to per-frame train mutations.
    private(set) var networkLineCount = 0
    /// Durable physical assets remain independent when two terminating services are reorganised
    /// into one through service.
    private(set) var corridors: [RailwayCorridor] = []
    private(set) var selectedTrainID: UUID?
    private(set) var selectedStationID: String?
    private(set) var editingStopsLineID: UUID?
    private(set) var editableIntermediateStations: [Station] = []
    private(set) var isUpdatingLineStops = false
    private(set) var mapStationAdditionProposal: MapStationAdditionProposal?
    private(set) var isLoadingMapStationAdditionProposal = false
    private(set) var isFollowingSelectedTrain = false
    private(set) var isPlaying = true
    private(set) var simulationSpeed: SimulationSpeed = .oneX
    private(set) var passengerSnapshot: NetworkPassengerSnapshot = .empty
    private(set) var stationCapacitySnapshot: NetworkStationCapacitySnapshot = .empty
    private(set) var happinessSnapshot: NetworkHappinessSnapshot = .empty
    private(set) var operationsSnapshotsByLineID: [UUID: LineOperationsSnapshot] = [:]
    private(set) var stationProgressByCRS: [String: StationProgress] = [:]
    private(set) var settlementPopulationByCRS: [String: SettlementPopulationState] = [:]
    private(set) var economySnapshot: NetworkOperatingEconomySnapshot = .zero
    private var economyLedgerObservationRevision: UInt64 = 0
    private(set) var economyLedger: EconomyLedger {
        get {
            _ = economyLedgerObservationRevision
            var value = economyLedgerStorage
            value.operatingDayProgress = operatingDayProgress
            return value
        }
        set {
            economyLedgerStorage = newValue
            operatingDayProgress = newValue.operatingDayProgress
            if economyLedgerObservationRevision < .max {
                economyLedgerObservationRevision += 1
            }
        }
    }
    private(set) var publicBetaHistory = PublicBetaDailyNetworkHistory()
    private(set) var financeLedger: FinanceLedger
    private(set) var stationUpgradeEvent: StationUpgradeEvent?
    private(set) var latestPresentationEvent: GamePresentationEvent?
    private(set) var errorMessage: String?
    /// Changes whenever user-visible gameplay state should be written to durable storage.
    ///
    /// Train animation and partial construction updates intentionally do not increment this on
    /// every frame. Callers can still export their latest positions when the app backgrounds.
    private(set) var persistenceRevision: UInt64 = 0

    @ObservationIgnored private let routingProvider: any RailwayRouteProviding
    @ObservationIgnored private let passengerSimulation: PassengerSimulation
    @ObservationIgnored private let stationCapacitySimulation: StationCapacitySimulation
    @ObservationIgnored private let accessibilityHappiness: AccessibilityHappiness
    @ObservationIgnored private let stationEvolution: StationEvolution
    @ObservationIgnored private let settlementGrowth: SettlementGrowth
    @ObservationIgnored private let operatingEconomy: OperatingEconomy
    @ObservationIgnored private let capitalEconomy: CapitalEconomy
    @ObservationIgnored private let trainOperations: TrainOperations
    @ObservationIgnored private let highSpeedRail: HighSpeedRail
    @ObservationIgnored private let automaticServicePlanner: AutomaticServicePlanner
    @ObservationIgnored private let clock: any SimulationClock
    @ObservationIgnored private let configuration: GameConfiguration
    @ObservationIgnored private var economyLedgerStorage: EconomyLedger = .zero
    /// Sub-day progress is not rendered anywhere. Keeping it outside Observation prevents a
    /// finance-HUD and map layout pass on every train-animation tick while preserving exact save,
    /// restore, pause, and coarse-tick semantics through the public ledger snapshot.
    @ObservationIgnored private var operatingDayProgress: Double = 0
    @ObservationIgnored private var isSceneActive = true
    @ObservationIgnored private var financeSnapshotCacheRevision: UInt64?
    @ObservationIgnored private var financeSnapshotCache: NetworkFinanceSnapshot?
    @ObservationIgnored private var prestigeSnapshotCacheRevision: UInt64?
    @ObservationIgnored private var prestigeSnapshotCache: HighSpeedPrestigeSnapshot?
    @ObservationIgnored private var routingTask: Task<Void, Never>?
    @ObservationIgnored private var routingRequestID: UUID?
    @ObservationIgnored private var buildStationEligibilityTask: Task<Void, Never>?
    @ObservationIgnored private var buildStationEligibilityRequestID: UUID?
    @ObservationIgnored private var previewIntermediateMatches: [CorridorStationMatch] = []
    @ObservationIgnored private var lineStopsTask: Task<Void, Never>?
    @ObservationIgnored private var lineStopsRequestID: UUID?
    @ObservationIgnored private var editableIntermediateMatches: [CorridorStationMatch] = []
    @ObservationIgnored private var mapStationAdditionTask: Task<Void, Never>?
    @ObservationIgnored private var mapStationAdditionRequestID: UUID?
    @ObservationIgnored private var pendingMapStationAdditionOptions = [
        UUID: PendingMapStationAdditionOption
    ]()
    @ObservationIgnored private var throughServiceAvailabilityCacheRevision: UInt64?
    @ObservationIgnored private var throughServiceAvailabilityCache = [
        UUID: ThroughServiceAvailability
    ]()
    @ObservationIgnored private var errorRecoveryPhase: GamePhase = .idle
    @ObservationIgnored private var pendingStationUpgradeEvents: [StationUpgradeEvent] = []
    @ObservationIgnored private var presentationEventSequence: UInt64 = 0
    @ObservationIgnored private var presentationEventBuffer: [GamePresentationEvent] = []
    @ObservationIgnored private var arrivalOrdinalsByTrainID: [UUID: UInt64] = [:]
    @ObservationIgnored private var trainArrivalPresentationEventsRemaining = 0
    @ObservationIgnored private var activeNetworkStationCRSCache = Set<String>()
    @ObservationIgnored private var trainMovementTopologyByLineID = [
        UUID: TrainMovementTopology
    ]()
    @ObservationIgnored private var trainMovementPlanTopologiesByLineID = [
        UUID: [Int: TrainMovementPlanTopology]
    ]()

    init(
        stations: [Station],
        routingProvider: any RailwayRouteProviding = RailwayRoutingService.shared,
        passengerSimulation: PassengerSimulation = PassengerSimulation(),
        stationCapacitySimulation: StationCapacitySimulation = StationCapacitySimulation(),
        accessibilityHappiness: AccessibilityHappiness = AccessibilityHappiness(
            configuration: .poc
        ),
        stationEvolution: StationEvolution = StationEvolution(),
        settlementGrowth: SettlementGrowth = SettlementGrowth(),
        operatingEconomy: OperatingEconomy = OperatingEconomy(),
        capitalEconomy: CapitalEconomy = CapitalEconomy(),
        trainOperations: TrainOperations = TrainOperations(),
        highSpeedRail: HighSpeedRail = HighSpeedRail(),
        automaticServicePlanner: AutomaticServicePlanner = AutomaticServicePlanner(),
        gameMode: GameMode = .zen,
        clock: (any SimulationClock)? = nil,
        configuration: GameConfiguration = .poc
    ) {
        self.stations = stations
        self.routingProvider = routingProvider
        self.passengerSimulation = passengerSimulation
        self.stationCapacitySimulation = stationCapacitySimulation
        self.accessibilityHappiness = accessibilityHappiness
        self.stationEvolution = stationEvolution
        self.settlementGrowth = settlementGrowth
        self.operatingEconomy = operatingEconomy
        self.capitalEconomy = capitalEconomy
        self.trainOperations = trainOperations
        self.highSpeedRail = highSpeedRail
        self.automaticServicePlanner = automaticServicePlanner
        financeLedger = capitalEconomy.newLedger(mode: gameMode)
        self.clock = clock ?? DisplayLinkSimulationClock()
        self.configuration = configuration

        recalculatePassengerSnapshot()
        self.clock.start { [weak self] delta in
            self?.tick(delta: delta)
        }
    }

    var canBuildAnotherLine: Bool {
        !financeLedger.isBankrupt
            && networkLineCount < max(configuration.maximumLineCount, 0)
    }

    /// Use this for both map annotations and catalogue search results. While graph metadata is
    /// loading, no candidate is presented as valid; direct method calls remain backwards-compatible
    /// with lightweight test providers and are checked as soon as a result has resolved.
    func isStationEligibleForCurrentBuild(_ station: Station) -> Bool {
        guard hasResolvedBuildStationEligibility else { return false }
        switch phase {
        case .selectingOrigin, .selectingDestination:
            return eligibleBuildStationCRSs.contains(
                StationEvolution.normalizedCRS(station.crs)
            )
        default:
            return false
        }
    }

    var canConfirmPreview: Bool {
        guard phase == .preview,
              let preview,
              !isUpdatingPreviewRoute,
              routingTask == nil else { return false }
        return previewIsPurchasable(preview)
    }

    var maximumServiceCallCount: Int {
        max(configuration.maximumServiceCallCount, 2)
    }

    var gameMode: GameMode { financeLedger.mode }

    var prestigeSnapshot: HighSpeedPrestigeSnapshot {
        let revision = persistenceRevision
        if prestigeSnapshotCacheRevision == revision,
           let prestigeSnapshotCache {
            return prestigeSnapshotCache
        }
        let value = highSpeedRail.prestigeSnapshot(lines: highSpeedPrestigeInputs)
        prestigeSnapshotCache = value
        prestigeSnapshotCacheRevision = revision
        return value
    }

    var premiumHighSpeedStationCRSs: Set<String> {
        Set(lines.filter { $0.railwayClass == .highSpeed }.flatMap { line in
            [
                StationEvolution.normalizedCRS(line.origin.crs),
                StationEvolution.normalizedCRS(line.destination.crs),
            ]
        })
        .filter { !$0.isEmpty }
    }

    var activePremiumHighSpeedStationCRSs: Set<String> {
        Set(lines.filter { $0.railwayClass == .highSpeed && $0.isConstructed }.flatMap { line in
            [
                StationEvolution.normalizedCRS(line.origin.crs),
                StationEvolution.normalizedCRS(line.destination.crs),
            ]
        })
        .filter { !$0.isEmpty }
    }

    func isPremiumHighSpeedStation(_ crs: String) -> Bool {
        premiumHighSpeedStationCRSs.contains(StationEvolution.normalizedCRS(crs))
    }

    var previewHighSpeedInvestmentQuote: HighSpeedInvestmentQuote? {
        guard let preview, preview.railwayClass == .highSpeed else { return nil }
        return highSpeedRail.investmentQuote(
            constructionCostPounds: preview.indicativeCost,
            originCRS: preview.origin.crs,
            destinationCRS: preview.destination.crs,
            existingPremiumStationCRSs: premiumHighSpeedStationCRSs,
            trainCount: ServiceFrequency.halfHourly.visibleTrainCount,
            formation: preview.formation
        )
    }

    var previewProjectedPrestigeGain: Int {
        guard let preview, preview.railwayClass == .highSpeed else { return 0 }
        return highSpeedRail.projectedPrestigeGain(
            for: HighSpeedPrestigeLineInput(
                id: preview.id,
                railwayClass: .highSpeed,
                originCRS: preview.origin.crs,
                destinationCRS: preview.destination.crs,
                isCompleted: true
            ),
            existingLines: highSpeedPrestigeInputs
        )
    }

    var previewEstimatedJourneyMinutes: Double? {
        guard let preview else { return nil }
        return preview.passengerEstimate.journeyMinutes
    }

    var financeSnapshot: NetworkFinanceSnapshot {
        let revision = persistenceRevision
        if financeSnapshotCacheRevision == revision,
           let financeSnapshotCache {
            return financeSnapshotCache
        }
        let corridorAssets = corridors.map { corridor in
            CapitalLineInput(
                id: corridor.id,
                constructionCostPounds: corridor.indicativeCost,
                ownedTrainCount: 0,
                infrastructureUpgradeValuePence: corridor.railwayClass == .conventional
                    ? trainOperations.infrastructureInvestmentPence(
                        for: corridor.trackCapacity,
                        constructionCostPounds: corridor.indicativeCost
                    )
                    : 0,
                railwayClass: corridor.railwayClass
            )
        }
        let rollingStockAssets = lines.map { line in
            CapitalLineInput(
                id: line.id,
                constructionCostPounds: 0,
                ownedTrainCount: line.ownedTrainCount,
                formation: line.formation,
                infrastructureUpgradeValuePence: 0,
                railwayClass: line.railwayClass
            )
        }
        let value = capitalEconomy.evaluate(
            lines: corridorAssets + rollingStockAssets,
            stationLevelsByCRS: stationProgressByCRS.mapValues(\.level),
            operatingEconomy: economySnapshot,
            ledger: financeLedger,
            premiumStationCRSs: premiumHighSpeedStationCRSs
        )
        financeSnapshotCache = value
        financeSnapshotCacheRevision = revision
        return value
    }

    var previewCapitalQuote: CapitalPurchaseQuote? {
        guard let preview else { return nil }
        return capitalQuote(for: preview)
    }

    var canAffordPreview: Bool {
        guard let quote = previewCapitalQuote else { return false }
        return capitalEconomy.canAfford(quote, ledger: financeLedger)
    }

    var previewFundingShortfallPence: Int64 {
        guard let quote = previewCapitalQuote else { return 0 }
        return capitalEconomy.fundingShortfall(
            for: quote.totalPence,
            ledger: financeLedger
        )
    }

    var standardLoanPence: Int64 {
        max(capitalEconomy.configuration.loanPrincipalPence, 0)
    }

    var standardLoanOffer: StandardLoanOffer {
        capitalEconomy.standardLoanOffer
    }

    var standardEarlyRepaymentPence: Int64 {
        max(capitalEconomy.configuration.earlyRepaymentPence, 0)
    }

    var availableEarlyRepaymentPence: Int64 {
        capitalEconomy.availableEarlyRepaymentPence(in: financeLedger)
    }

    var trains: [TrainState] {
        lines.flatMap { line in
            line.isConstructed ? line.trains : []
        }
    }

    var selectedTrain: TrainState? {
        guard let selectedTrainID else { return nil }
        return trains.first { $0.id == selectedTrainID }
    }

    var selectedStation: Station? {
        guard let selectedStationID else { return nil }
        return stations.first { $0.crs == selectedStationID }
    }

    var trainCapacity: Int {
        max(passengerSimulation.configuration.trainCapacity, 0)
    }

    func trainCapacity(forLineID lineID: UUID) -> Int? {
        lines.first(where: { $0.id == lineID })?.formation.seatsPerTrain
    }

    func passengerSnapshot(forLineID lineID: UUID) -> PassengerLineSnapshot? {
        passengerSnapshot.line(for: lineID)
    }

    func passengerSnapshot(forStationCRS crs: String) -> StationPassengerSnapshot? {
        passengerSnapshot.station(forCRS: crs)
    }

    func stationCapacitySnapshot(forLineID lineID: UUID) -> StationCapacityLineSnapshot? {
        stationCapacitySnapshot.line(for: lineID)
    }

    func stationCapacitySnapshot(
        forStationCRS crs: String
    ) -> StationCapacityStationSnapshot? {
        stationCapacitySnapshot.station(forCRS: crs)
    }

    func happinessSnapshot(forStationCRS crs: String) -> SettlementHappinessSnapshot? {
        happinessSnapshot.station(forCRS: crs)
    }

    /// The synthetic gameplay population currently reached by completed player services.
    var networkPopulation: Int64 {
        activeNetworkStationCRSs.reduce(0) { total, crs in
            saturatingAdd(
                total,
                settlementPopulationByCRS[crs]?.currentPopulation ?? 0
            )
        }
    }

    /// Population added on the most recently completed operating day.
    var latestNetworkPopulationChange: Int64 {
        activeNetworkStationCRSs.reduce(0) { total, crs in
            saturatingAdd(
                total,
                settlementPopulationByCRS[crs]?.latestDailyChange ?? 0
            )
        }
    }

    func settlementGrowthStatus(
        forStationCRS crs: String
    ) -> SettlementGrowthStatus? {
        let normalizedCRS = StationEvolution.normalizedCRS(crs)
        guard stations.contains(where: { $0.crs == normalizedCRS }) else { return nil }
        let localHappiness = happinessSnapshot(forStationCRS: normalizedCRS)
        return settlementGrowth.status(
            for: SettlementGrowthInput(
                stationCRS: normalizedCRS,
                isConnected: activeNetworkStationCRSs.contains(normalizedCRS),
                localHappinessScore: localHappiness?.happinessScore ?? 0,
                reachableDestinationCount: localHappiness?.reachableDestinationCount ?? 0
            ),
            state: settlementPopulationByCRS[normalizedCRS]
        )
    }

    func stationEvolutionStatus(forStationCRS crs: String) -> StationEvolutionStatus? {
        let normalizedCRS = StationEvolution.normalizedCRS(crs)
        guard let progress = stationProgressByCRS[normalizedCRS] else { return nil }
        return stationEvolution.status(
            for: progress,
            connectedDestinationCount: passengerSnapshot.station(forCRS: normalizedCRS)?
                .connectedDestinationCount ?? 0
        )
    }

    func economySnapshot(forLineID lineID: UUID) -> LineOperatingEconomySnapshot? {
        economySnapshot.lineSnapshot(for: lineID)
    }

    func operationsSnapshot(forLineID lineID: UUID) -> LineOperationsSnapshot? {
        operationsSnapshotsByLineID[lineID]
    }

    func trainServiceRole(for trainID: UUID) -> TrainServiceRole? {
        guard let line = lines.first(where: { line in
            line.trains.contains(where: { $0.id == trainID })
        }),
        let index = line.trains.firstIndex(where: { $0.id == trainID }) else {
            return nil
        }
        return line.servicePlan(forSlot: index)?.role
            ?? trainOperations.role(
                forTrainAt: index,
                trainCount: line.trains.count,
                pattern: line.servicePattern
            )
    }

    func trainServicePlan(for trainID: UUID) -> TrainServicePlan? {
        guard let line = lines.first(where: { line in
            line.trains.contains(where: { $0.id == trainID })
        }),
        let index = line.trains.firstIndex(where: { $0.id == trainID }) else {
            return nil
        }
        return line.servicePlan(forSlot: index)
    }

    func serviceStations(forLineID lineID: UUID) -> [Station] {
        guard let line = lines.first(where: { $0.id == lineID }) else { return [] }
        let byCRS = Dictionary(
            stations.map { (StationEvolution.normalizedCRS($0.crs), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return line.stationCRSs.compactMap {
            byCRS[StationEvolution.normalizedCRS($0)]
        }
    }

    func canCustomizeServicePlan(for trainID: UUID) -> Bool {
        guard let line = lines.first(where: { line in
            line.trains.contains(where: { $0.id == trainID })
        }) else { return false }
        return line.isConstructed
            && line.railwayClass == .conventional
            && line.stationCRSs.count >= 3
    }

    var selectedTrainServicePlan: TrainServicePlan? {
        selectedTrainID.flatMap(trainServicePlan(for:))
    }

    func trainFormationSnapshot(for trainID: UUID) -> TrainFormationSnapshot? {
        guard let line = lines.first(where: { line in
            line.trains.contains(where: { $0.id == trainID })
        }),
        let trainIndex = line.trains.firstIndex(where: { $0.id == trainID }) else {
            return nil
        }

        let role = line.servicePlan(forSlot: trainIndex)?.role
            ?? trainOperations.role(
                forTrainAt: trainIndex,
                trainCount: line.trains.count,
                pattern: line.servicePattern
            )
        return TrainFormationPolicy().evaluate(
            serviceRole: role,
            railwayClass: line.railwayClass,
            routeDistanceKilometres: line.distanceKilometres,
            peakOccupancyRatio: passengerSnapshot(forLineID: line.id)?.peakOccupancyRatio ?? 0,
            nominalTrainCapacity: line.formation.seatsPerTrain,
            purchasedFormation: line.formation
        )
    }

    func trainPresentationSnapshots(
        for requestedTrainIDs: Set<UUID>
    ) -> [TrainPresentationSnapshot] {
        guard !requestedTrainIDs.isEmpty else { return [] }

        var result = [TrainPresentationSnapshot]()
        result.reserveCapacity(requestedTrainIDs.count)
        var trainNumber = 0
        let formationPolicy = TrainFormationPolicy()

        for line in lines where line.isConstructed {
            guard line.trains.contains(where: { requestedTrainIDs.contains($0.id) }) else {
                trainNumber += line.trains.count
                continue
            }
            let roles = line.trains.indices.map { index in
                line.servicePlan(forSlot: index)?.role
                    ?? trainOperations.role(
                        forTrainAt: index,
                        trainCount: line.trains.count,
                        pattern: line.servicePattern
                    )
            }

            let linePassengerSnapshot = passengerSnapshot.linesByID[line.id]
            let occupancy = linePassengerSnapshot?.peakOccupancyRatio ?? 0
            var localFormation: TrainFormationSnapshot?
            var expressFormation: TrainFormationSnapshot?
            func formation(for role: TrainServiceRole) -> TrainFormationSnapshot {
                if role == .local, let localFormation { return localFormation }
                if role == .express, let expressFormation { return expressFormation }
                let formation = formationPolicy.evaluate(
                    serviceRole: role,
                    railwayClass: line.railwayClass,
                    routeDistanceKilometres: line.distanceKilometres,
                    peakOccupancyRatio: occupancy,
                    nominalTrainCapacity: line.formation.seatsPerTrain,
                    purchasedFormation: line.formation
                )
                if role == .local {
                    localFormation = formation
                } else {
                    expressFormation = formation
                }
                return formation
            }

            let routeLength = line.route.totalLength
            let encounterDistance = max(routeLength * 0.065, 250)
            let isWithinPassingZone: (TrainState) -> Bool = { candidate in
                guard line.trackCapacity == .passingLoop else { return true }
                return abs(candidate.distanceAlongRoute - routeLength * 0.5)
                    <= routeLength * 0.14
            }

            for (index, train) in line.trains.enumerated() {
                trainNumber += 1
                guard requestedTrainIDs.contains(train.id) else { continue }
                let role = roles[index]
                let isOvertaking = role == .express
                    && line.trackCapacity.allowsOvertaking
                    && routeLength.isFinite
                    && routeLength > 0
                    && isWithinPassingZone(train)
                    && line.trains.indices.contains { candidateIndex in
                        let candidate = line.trains[candidateIndex]
                        return candidate.id != train.id
                            && candidate.direction == train.direction
                            && roles[candidateIndex] == .local
                            && isWithinPassingZone(candidate)
                            && abs(candidate.distanceAlongRoute - train.distanceAlongRoute)
                                <= encounterDistance
                    }
                result.append(
                    TrainPresentationSnapshot(
                        train: train,
                        number: trainNumber,
                        lineName: line.name,
                        lineStyleIndex: line.styleIndex,
                        railwayClass: line.railwayClass,
                        seatsPerTrain: line.formation.seatsPerTrain,
                        serviceRole: role,
                        formation: formation(for: role),
                        isOvertaking: isOvertaking,
                        passengerFeedbackTitle: linePassengerSnapshot?.feedback.title
                            ?? "No demand estimate"
                    )
                )
            }
        }
        return result
    }

    func isTrainOvertaking(_ trainID: UUID) -> Bool {
        guard let line = lines.first(where: { line in
            line.trains.contains(where: { $0.id == trainID })
        }),
        line.trackCapacity.allowsOvertaking,
        let train = line.trains.first(where: { $0.id == trainID }),
        trainServiceRole(for: trainID) == .express else {
            return false
        }

        let routeLength = line.route.totalLength
        guard routeLength.isFinite, routeLength > 0 else { return false }
        let encounterDistance = max(routeLength * 0.065, 250)
        let isWithinPassingZone: (TrainState) -> Bool = { candidate in
            guard line.trackCapacity == .passingLoop else { return true }
            return abs(candidate.distanceAlongRoute - routeLength * 0.5)
                <= routeLength * 0.14
        }

        return isWithinPassingZone(train) && line.trains.contains { candidate in
            candidate.id != train.id
                && candidate.direction == train.direction
                && trainServiceRole(for: candidate.id) == .local
                && isWithinPassingZone(candidate)
                && abs(candidate.distanceAlongRoute - train.distanceAlongRoute)
                    <= encounterDistance
        }
    }

    func trackUpgradeCost(forLineID lineID: UUID) -> Int64? {
        guard canUpgradeTrack(forLineID: lineID),
              let line = lines.first(where: { $0.id == lineID }) else { return nil }
        return trainOperations.upgradeCostPence(
            from: line.trackCapacity,
            constructionCostPounds: line.corridorIndicativeCost
        )
    }

    func canEditStops(forLineID lineID: UUID) -> Bool {
        guard let line = lines.first(where: { $0.id == lineID }) else { return false }
        return line.isConstructed
            && line.railwayClass == .conventional
            && line.corridorIDs.count == 1
            && line.stationCRSs.count < maximumServiceCallCount
    }

    func canUpgradeTrack(forLineID lineID: UUID) -> Bool {
        guard let line = lines.first(where: { $0.id == lineID }) else { return false }
        return line.isConstructed
            && line.railwayClass == .conventional
            && line.corridorIDs.count == 1
            && line.trackCapacity.next != nil
    }

    func throughServiceOptions(forLineID lineID: UUID) -> [ThroughServiceOption] {
        throughServiceAvailability(forLineID: lineID).options
    }

    func throughServiceIncompatibilities(
        forLineID lineID: UUID
    ) -> [ThroughServiceIncompatibility] {
        throughServiceAvailability(forLineID: lineID).incompatibilities
    }

    /// One cached snapshot supplies both lists to the map UI. Train positions mutate `lines` on
    /// every display tick, while service topology/settings advance `persistenceRevision` only when
    /// their durable values change.
    func throughServiceAvailability(forLineID lineID: UUID) -> ThroughServiceAvailability {
        if throughServiceAvailabilityCacheRevision != persistenceRevision {
            throughServiceAvailabilityCacheRevision = persistenceRevision
            throughServiceAvailabilityCache.removeAll(keepingCapacity: true)
        }
        if let cached = throughServiceAvailabilityCache[lineID] {
            return throughServiceAvailabilityForCurrentState(cached)
        }
        guard let primary = lines.first(where: { $0.id == lineID }) else { return .empty }
        var options = [ThroughServiceOption]()
        var incompatibilities = [ThroughServiceIncompatibility]()

        for candidate in lines where candidate.id != primary.id {
            if let plan = throughServiceMergePlan(primary: primary, candidate: candidate) {
                options.append(plan.option)
            } else if let incompatibility = throughServiceIncompatibility(
                primary: primary,
                candidate: candidate
            ) {
                incompatibilities.append(incompatibility)
            }
        }
        options.sort { lhs, rhs in
            if lhs.candidateLineNumber != rhs.candidateLineNumber {
                return lhs.candidateLineNumber < rhs.candidateLineNumber
            }
            return lhs.candidateLineID.uuidString < rhs.candidateLineID.uuidString
        }
        incompatibilities.sort { lhs, rhs in
            if lhs.candidateLineNumber != rhs.candidateLineNumber {
                return lhs.candidateLineNumber < rhs.candidateLineNumber
            }
            return lhs.candidateLineID.uuidString < rhs.candidateLineID.uuidString
        }

        let availability = ThroughServiceAvailability(
            options: options,
            incompatibilities: incompatibilities
        )
        if throughServiceAvailabilityCache.count >= max(configuration.maximumLineCount, 1) {
            throughServiceAvailabilityCache.removeAll(keepingCapacity: true)
        }
        throughServiceAvailabilityCache[lineID] = availability
        return throughServiceAvailabilityForCurrentState(availability)
    }

    private func throughServiceAvailabilityForCurrentState(
        _ topology: ThroughServiceAvailability
    ) -> ThroughServiceAvailability {
        guard phase == .operating, !financeLedger.isBankrupt else {
            return ThroughServiceAvailability(
                options: [],
                incompatibilities: topology.incompatibilities
            )
        }
        // Affordability can change after an operating-day settlement without changing service
        // topology. Refresh these two presentation values from the live ledger even when the
        // expensive route assembly itself came from the topology cache.
        let options = topology.options.map { cached in
            var option = cached
            option.canAfford = capitalEconomy.canAfford(
                option.capitalQuote,
                ledger: financeLedger
            )
            option.fundingShortfallPence = capitalEconomy.fundingShortfall(
                for: option.capitalQuote.totalPence,
                ledger: financeLedger
            )
            return option
        }
        return ThroughServiceAvailability(
            options: options,
            incompatibilities: topology.incompatibilities
        )
    }

    private func throughServiceIncompatibility(
        primary: BuiltLine,
        candidate: BuiltLine
    ) -> ThroughServiceIncompatibility? {
        let primaryStations = primary.stationCRSs.map(StationEvolution.normalizedCRS)
        let candidateStations = candidate.stationCRSs.map(StationEvolution.normalizedCRS)
        let sharedStations = Set(primaryStations).intersection(candidateStations)
        guard !sharedStations.isEmpty else { return nil }

        let primaryEndpoints = Set([primaryStations.first, primaryStations.last].compactMap { $0 })
        let candidateEndpoints = Set(
            [candidateStations.first, candidateStations.last].compactMap { $0 }
        )
        let sharedEndpoints = primaryEndpoints.intersection(candidateEndpoints)
        let junctionCRS = sharedEndpoints.sorted().first ?? sharedStations.sorted().first ?? ""

        var reasons = [ThroughServiceIncompatibilityReason]()
        let primaryCorridors = primary.corridorIDs.compactMap { corridorID in
            corridors.first(where: { $0.id == corridorID })
        }
        let candidateCorridors = candidate.corridorIDs.compactMap { corridorID in
            corridors.first(where: { $0.id == corridorID })
        }
        if !primary.isConstructed || !candidate.isConstructed
            || primaryCorridors.contains(where: { !$0.isConstructed })
            || candidateCorridors.contains(where: { !$0.isConstructed }) {
            reasons.append(.incompleteConstruction)
        }
        if primary.railwayClass != .conventional
            || candidate.railwayClass != .conventional
            || primaryCorridors.contains(where: { $0.railwayClass != .conventional })
            || candidateCorridors.contains(where: { $0.railwayClass != .conventional }) {
            reasons.append(.conventionalServicesOnly)
        }

        let hasCompleteCorridorReferences = !primary.corridorIDs.isEmpty
            && !candidate.corridorIDs.isEmpty
            && primaryCorridors.count == primary.corridorIDs.count
            && candidateCorridors.count == candidate.corridorIDs.count
        let hasDisjointCorridors = Set(primary.corridorIDs)
            .isDisjoint(with: Set(candidate.corridorIDs))
        if sharedEndpoints.count != 1
            || sharedStations.count != 1
            || !hasDisjointCorridors {
            reasons.append(.overlappingOrBranchedRoute)
        }

        if sharedEndpoints.count == 1,
           sharedStations.count == 1,
           let junction = sharedEndpoints.first,
           let originCRS = primaryEndpoints.first(where: { $0 != junction }),
           let destinationCRS = candidateEndpoints.first(where: { $0 != junction }),
           let primaryCalls = orientedStationCRSs(
               primary.stationCRSs,
               from: originCRS,
               to: junction
           ),
           let candidateCalls = orientedStationCRSs(
               candidate.stationCRSs,
               from: junction,
               to: destinationCRS
           ) {
            let resultingCallCount = primaryCalls.count + candidateCalls.count - 1
            let ownedCount = primary.ownedTrainCount.addingReportingOverflow(
                candidate.ownedTrainCount
            )
            let corridorCount = primary.corridorIDs.count.addingReportingOverflow(
                candidate.corridorIDs.count
            )
            if resultingCallCount > maximumServiceCallCount
                || resultingCallCount > GameSaveSnapshot.maximumStationsPerCorridor
                || ownedCount.overflow
                || ownedCount.partialValue > GameSaveSnapshot.maximumOwnedTrainCountPerService
                || corridorCount.overflow
                || corridorCount.partialValue > GameSaveSnapshot.maximumCorridorCount {
                reasons.append(.serviceLimitExceeded)
            }
        }

        if !hasCompleteCorridorReferences {
            reasons.append(.unavailable)
        }
        if reasons.isEmpty {
            // The adjacent endpoints are valid, so a failed merge plan here means the retained
            // corridor union cannot be represented as one unambiguous linear service.
            reasons.append(.overlappingOrBranchedRoute)
        }

        return ThroughServiceIncompatibility(
            primaryLineID: primary.id,
            candidateLineID: candidate.id,
            primaryLineNumber: max(primary.styleIndex, 0) + 1,
            candidateLineNumber: max(candidate.styleIndex, 0) + 1,
            junctionCRS: junctionCRS,
            junctionName: station(forNormalizedCRS: junctionCRS)?.name ?? junctionCRS,
            reasons: reasons
        )
    }

    /// Replaces two adjacent terminating services with one outer-terminal service. Operating
    /// settings reconcile to the primary service, while purchased asset capability reconciles
    /// upwards. The quote and live affordability are revalidated before any mutation is committed.
    @discardableResult
    func joinThroughService(primaryLineID: UUID, withLineID candidateLineID: UUID) -> Bool {
        guard phase == .operating,
              !financeLedger.isBankrupt,
              let primary = lines.first(where: { $0.id == primaryLineID }),
              let candidate = lines.first(where: { $0.id == candidateLineID }),
              let plan = throughServiceMergePlan(primary: primary, candidate: candidate),
              let origin = station(forNormalizedCRS: plan.option.originCRS),
              let destination = station(forNormalizedCRS: plan.option.destinationCRS) else {
            return false
        }

        var updatedFinanceLedger = financeLedger
        guard capitalEconomy.recordPurchase(
            plan.option.capitalQuote,
            in: &updatedFinanceLedger
        ) else {
            let shortfall = capitalEconomy.fundingShortfall(
                for: plan.option.capitalQuote.totalPence,
                ledger: financeLedger
            )
            presentError(
                "Joining these services needs "
                    + "\(formattedPenceForMessage(shortfall)) more funding. "
                    + "Open Network finances to arrange a loan.",
                recoveringTo: .operating
            )
            return false
        }

        let orientedPrimaryRoute = plan.primaryIsReversed
            ? RailwayCorridorChainAssembler.reversedRoute(primary.route)
            : primary.route
        let orientedPrimaryTrains = plan.primaryIsReversed
            ? reversingTrains(primary.trains, on: primary.route)
            : primary.trains
        let retainedActiveTrains = remappingTrains(
            orientedPrimaryTrains,
            from: orientedPrimaryRoute,
            stationCRSs: plan.primaryStationCRSs,
            to: plan.serviceRoute,
            stationCRSs: plan.option.stationCRSs
        )
        var joinedLine = BuiltLine(
            id: primary.id,
            name: "\(origin.name) – \(destination.name)",
            origin: origin,
            destination: destination,
            route: plan.serviceRoute,
            distanceMetres: plan.serviceRoute.totalLength,
            indicativeCost: plan.assembly.indicativeCost,
            styleIndex: primary.styleIndex,
            railwayClass: primary.railwayClass,
            formation: plan.option.formation,
            servicePattern: primary.servicePattern,
            trackCapacity: plan.option.trackCapacity,
            serviceFrequency: primary.serviceFrequency,
            ownedTrainCount: plan.option.resultingOwnedTrainCount,
            constructionProgress: plan.assembly.constructionProgress,
            trains: retainedActiveTrains,
            corridorIDs: plan.assembly.corridorIDs,
            stationCRSs: plan.option.stationCRSs,
            trainServicePlans: plan.trainServicePlans,
            corridorStationCRSs: plan.assembly.stationCRSs,
            corridorRoute: plan.assembly.route,
            corridorDistanceMetres: plan.assembly.distanceMetres,
            corridorIndicativeCost: plan.assembly.indicativeCost
        )
        guard joinedLine.trainServicePlans.allSatisfy({ servicePlan in
            validatedServicePlan(servicePlan, on: joinedLine) == servicePlan
        }) else { return false }
        if !plan.option.preservesPrimaryCustomServicePlans,
           joinedLine.servicePattern == .balanced,
           joinedLine.trackCapacity.allowsOvertaking {
            joinedLine.trains = stagedOvertakingFleet(for: joinedLine)
        }
        joinedLine.trains = reconciledFleetWithServicePlans(for: joinedLine)

        var updatedCorridors = corridors
        for corridorID in plan.assembly.corridorIDs {
            guard let index = updatedCorridors.firstIndex(where: { $0.id == corridorID }) else {
                return false
            }
            updatedCorridors[index].trackCapacity = plan.option.trackCapacity
        }

        let removedTrainIDs = Set(candidate.trains.map(\.id))
        let updatedLines = lines.compactMap { line in
            if line.id == primary.id { return joinedLine }
            if line.id == candidate.id { return nil }
            return line
        }
        finishEditingStops()
        financeLedger = updatedFinanceLedger
        corridors = updatedCorridors
        lines = updatedLines
        if let selectedTrainID, removedTrainIDs.contains(selectedTrainID) {
            self.selectedTrainID = nil
            isFollowingSelectedTrain = false
        }
        for trainID in removedTrainIDs {
            arrivalOrdinalsByTrainID.removeValue(forKey: trainID)
        }
        restartOperatingDayForNetworkChange()
        reconcileStationProgress()
        reconcileSettlementPopulation()
        recalculatePassengerSnapshot()
        markPersistenceChanged()
        return true
    }

    func stationUpkeepPencePerDay(forStationCRS crs: String) -> Int64? {
        guard let level = stationEvolutionStatus(forStationCRS: crs)?.level else { return nil }
        let base = operatingEconomy.stationUpkeepPencePerDay(for: level)
        guard activePremiumHighSpeedStationCRSs.contains(
            StationEvolution.normalizedCRS(crs)
        ) else { return base }
        return EconomyArithmetic.add(
            base,
            max(operatingEconomy.configuration.premiumStationUpkeepPencePerDay, 0)
        )
    }

    func rollingStockPurchaseCost(
        for frequency: ServiceFrequency,
        lineID: UUID
    ) -> Int64? {
        guard let line = lines.first(where: { $0.id == lineID }) else { return nil }
        let additionalTrainCount = max(
            frequency.visibleTrainCount - line.ownedTrainCount,
            0
        )
        return capitalEconomy.rollingStockCost(
            forTrainCount: additionalTrainCount,
            formation: line.formation,
            railwayClass: line.railwayClass
        )
    }

    func formationExtensionCost(forLineID lineID: UUID) -> Int64? {
        guard let line = lines.first(where: { $0.id == lineID }) else { return nil }
        return capitalEconomy.quoteForFormationExtension(
            ownedTrainCount: line.ownedTrainCount,
            currentFormation: line.formation,
            railwayClass: line.railwayClass
        )?.totalCostPence
    }

    func startBuilding() {
        guard phase != .constructing else { return }
        guard !financeLedger.isBankrupt else {
            presentError(
                "This Career company is bankrupt. Start a new game from the menu to continue.",
                recoveringTo: .operating
            )
            return
        }
        guard canBuildAnotherLine else {
            presentError(
                "This version supports up to \(max(configuration.maximumLineCount, 0)) lines.",
                recoveringTo: lines.isEmpty ? .idle : .operating
            )
            return
        }

        cancelMapStationAddition()
        finishEditingStops()
        cancelPendingRoute()
        clearBuildSelection()
        selectedStationID = nil
        errorMessage = nil
        phase = .selectingOrigin
        beginBuildStationEligibility(connectedTo: nil)
    }

    func selectStation(_ station: Station) {
        switch phase {
        case .selectingOrigin:
            selectOrigin(station)
        case .selectingDestination:
            selectDestination(station)
        default:
            break
        }
    }

    func selectOrigin(_ station: Station) {
        guard phase == .selectingOrigin else { return }
        let stationCRS = StationEvolution.normalizedCRS(station.crs)
        guard !hasResolvedBuildStationEligibility
                || eligibleBuildStationCRSs.contains(stationCRS) else {
            presentError(
                "That station is not connected to another station in the railway map.",
                recoveringTo: .selectingOrigin
            )
            return
        }

        selectedOrigin = station
        selectedDestination = nil
        preview = nil
        clearPreviewStationSelection()
        errorMessage = nil
        phase = .selectingDestination
        beginBuildStationEligibility(connectedTo: station)
    }

    func selectDestination(_ station: Station) {
        guard phase == .selectingDestination, let origin = selectedOrigin else { return }
        let stationCRS = StationEvolution.normalizedCRS(station.crs)
        let originCRS = StationEvolution.normalizedCRS(origin.crs)
        guard stationCRS != originCRS else {
            presentError(
                "Choose a destination different from the origin.",
                recoveringTo: .selectingDestination
            )
            return
        }
        guard !hasLine(between: originCRS, and: stationCRS) else {
            presentError(
                "That connection already has a service. Tap one of its trains to adjust frequency.",
                recoveringTo: .selectingDestination
            )
            return
        }
        guard !hasResolvedBuildStationEligibility
                || eligibleBuildStationCRSs.contains(stationCRS) else {
            presentError(
                "No reasonably direct railway path is available from \(origin.name) to \(station.name).",
                recoveringTo: .selectingDestination
            )
            return
        }

        selectedDestination = station
        cancelBuildStationEligibility()
        beginRouteCalculation(from: origin, to: station)
    }

    func setPreviewRailwayClass(_ railwayClass: RailwayClass) {
        guard phase == .preview,
              let currentPreview = preview,
              !isUpdatingPreviewRoute,
              routingTask == nil,
              currentPreview.railwayClass != railwayClass else { return }

        let formation = currentPreview.formation.clamped(for: railwayClass)
        if railwayClass == .highSpeed, currentPreview.stationCRSs.count > 2 {
            let endpoints = [currentPreview.origin.crs, currentPreview.destination.crs]
                .map(StationEvolution.normalizedCRS)
            beginPreviewRouteUpdate(
                for: currentPreview,
                orderedStationCRSs: endpoints,
                targetRailwayClass: railwayClass,
                targetFormation: formation
            )
            return
        }

        let passengerEstimate = previewPassengerEstimate(
            origin: currentPreview.origin,
            destination: currentPreview.destination,
            route: currentPreview.route,
            stationCRSs: currentPreview.stationCRSs,
            railwayClass: railwayClass,
            formation: formation
        )
        preview = LinePreview(
            id: currentPreview.id,
            origin: currentPreview.origin,
            destination: currentPreview.destination,
            stationCRSs: currentPreview.stationCRSs,
            route: currentPreview.route,
            distanceMetres: currentPreview.distanceMetres,
            indicativeCost: currentPreview.indicativeCost,
            passengerEstimate: passengerEstimate,
            railwayClass: railwayClass,
            formation: formation,
            recommendedFormation: recommendedFormation(
                for: passengerEstimate,
                railwayClass: railwayClass
            )
        )
    }

    func setPreviewFormation(_ formation: RollingStockFormation) {
        guard phase == .preview,
              let currentPreview = preview,
              !isUpdatingPreviewRoute,
              routingTask == nil,
              currentPreview.formation != formation,
              RollingStockFormation.supported(for: currentPreview.railwayClass)
                .contains(formation) else { return }

        let passengerEstimate = previewPassengerEstimate(
            origin: currentPreview.origin,
            destination: currentPreview.destination,
            route: currentPreview.route,
            stationCRSs: currentPreview.stationCRSs,
            railwayClass: currentPreview.railwayClass,
            formation: formation
        )
        preview = LinePreview(
            id: currentPreview.id,
            origin: currentPreview.origin,
            destination: currentPreview.destination,
            stationCRSs: currentPreview.stationCRSs,
            route: currentPreview.route,
            distanceMetres: currentPreview.distanceMetres,
            indicativeCost: currentPreview.indicativeCost,
            passengerEstimate: passengerEstimate,
            railwayClass: currentPreview.railwayClass,
            formation: formation,
            recommendedFormation: currentPreview.recommendedFormation
        )
    }

    func togglePreviewIntermediateStation(_ station: Station) {
        guard phase == .preview,
              let currentPreview = preview,
              !isUpdatingPreviewRoute,
              routingTask == nil,
              currentPreview.railwayClass == .conventional,
              previewIntermediateMatches.contains(where: {
                  StationEvolution.normalizedCRS($0.station.crs)
                      == StationEvolution.normalizedCRS(station.crs)
              }) else { return }

        let stationCRS = StationEvolution.normalizedCRS(station.crs)
        let originCRS = StationEvolution.normalizedCRS(currentPreview.origin.crs)
        let destinationCRS = StationEvolution.normalizedCRS(currentPreview.destination.crs)
        var selectedIntermediateCRSs = Set(
            previewSelectedStationCRSs
                .map(StationEvolution.normalizedCRS)
                .filter { $0 != originCRS && $0 != destinationCRS }
        )
        if selectedIntermediateCRSs.contains(stationCRS) {
            selectedIntermediateCRSs.remove(stationCRS)
        } else {
            guard previewSelectedStationCRSs.count < maximumServiceCallCount else { return }
            selectedIntermediateCRSs.insert(stationCRS)
        }
        let orderedStationCRSs = [originCRS]
            + previewIntermediateMatches.compactMap { match in
                let crs = StationEvolution.normalizedCRS(match.station.crs)
                return selectedIntermediateCRSs.contains(crs) ? crs : nil
            }
            + [destinationCRS]
        guard orderedStationCRSs.count <= GameSaveSnapshot.maximumStationsPerCorridor else {
            return
        }

        previewSelectedStationCRSs = orderedStationCRSs
        beginPreviewRouteUpdate(
            for: currentPreview,
            orderedStationCRSs: orderedStationCRSs
        )
    }

    func beginEditingStops(forLineID lineID: UUID) {
        guard phase == .operating,
              let line = lines.first(where: { $0.id == lineID }),
              line.isConstructed,
              line.railwayClass == .conventional,
              line.corridorIDs.count == 1 else { return }

        cancelLineStopsTask()
        editingStopsLineID = lineID
        editableIntermediateMatches = []
        editableIntermediateStations = []
        isUpdatingLineStops = line.stationCRSs.count < maximumServiceCallCount

        guard isUpdatingLineStops else { return }

        let requestID = UUID()
        lineStopsRequestID = requestID
        let routingProvider = self.routingProvider
        let catalogStations = stations
        let route = line.corridorRoute
        let endpoints = [line.origin.crs, line.destination.crs]
        let existingCalls = Set(line.stationCRSs.map(StationEvolution.normalizedCRS))
        guard let serviceSpan = serviceCorridorDiscoverySpan(for: line) else {
            isUpdatingLineStops = false
            return
        }
        lineStopsTask = Task { [weak self] in
            do {
                let matches = try await routingProvider.discoverIntermediateStations(
                    on: route,
                    endpointCRSs: endpoints,
                    catalogStations: catalogStations
                ).filter {
                    $0.routeDistance.isFinite
                        && $0.routeDistance > serviceSpan.lowerDistance
                        && $0.routeDistance < serviceSpan.upperDistance
                        && !existingCalls.contains(
                            StationEvolution.normalizedCRS($0.station.crs)
                        )
                }.sorted { lhs, rhs in
                    if lhs.routeDistance == rhs.routeDistance {
                        return StationEvolution.normalizedCRS(lhs.station.crs)
                            < StationEvolution.normalizedCRS(rhs.station.crs)
                    }
                    return serviceSpan.isForward
                        ? lhs.routeDistance < rhs.routeDistance
                        : lhs.routeDistance > rhs.routeDistance
                }
                guard !Task.isCancelled else { return }
                self?.completeEditingStopsDiscovery(
                    requestID: requestID,
                    lineID: lineID,
                    matches: matches
                )
            } catch is CancellationError {
                // Closing or refreshing the editor intentionally replaces this request.
            } catch {
                self?.completeEditingStopsDiscovery(
                    requestID: requestID,
                    lineID: lineID,
                    matches: []
                )
            }
        }
    }

    func finishEditingStops() {
        cancelLineStopsTask()
        editingStopsLineID = nil
        editableIntermediateMatches = []
        editableIntermediateStations = []
        isUpdatingLineStops = false
    }

    /// Checks whether one catalogue station selected on the map can be inserted into any of the
    /// caller's bounded visible/nearby service candidates. Discovery receives only this station,
    /// so a tap never rescans the whole Great Britain catalogue for every built line.
    func beginMapStationAddition(
        _ station: Station,
        candidateLineIDs: Set<UUID>
    ) {
        cancelMapStationAddition()

        let stationCRS = StationEvolution.normalizedCRS(station.crs)
        guard phase == .operating,
              let catalogStation = stations.first(where: {
                  StationEvolution.normalizedCRS($0.crs) == stationCRS
              }) else { return }

        mapStationAdditionProposal = MapStationAdditionProposal(
            station: catalogStation,
            options: []
        )
        isLoadingMapStationAdditionProposal = true

        let inputs = lines.compactMap { line -> MapStationAdditionDiscoveryInput? in
            guard candidateLineIDs.contains(line.id),
                  line.isConstructed,
                  line.railwayClass == .conventional,
                  line.corridorIDs.count == 1,
                  line.stationCRSs.count < maximumServiceCallCount,
                  !line.stationCRSs.map(StationEvolution.normalizedCRS).contains(stationCRS),
                  let span = serviceCorridorDiscoverySpan(for: line) else {
                return nil
            }
            return MapStationAdditionDiscoveryInput(
                line: line,
                lowerRouteDistance: span.lowerDistance,
                upperRouteDistance: span.upperDistance
            )
        }.sorted { lhs, rhs in
            if lhs.line.styleIndex != rhs.line.styleIndex {
                return lhs.line.styleIndex < rhs.line.styleIndex
            }
            return lhs.line.id.uuidString < rhs.line.id.uuidString
        }

        guard !inputs.isEmpty else {
            isLoadingMapStationAdditionProposal = false
            return
        }

        let requestID = UUID()
        mapStationAdditionRequestID = requestID
        let routingProvider = self.routingProvider
        mapStationAdditionTask = Task { [weak self] in
            var results = [MapStationAdditionDiscoveryResult]()
            results.reserveCapacity(inputs.count)

            for input in inputs {
                do {
                    try Task.checkCancellation()
                    let matches = try await routingProvider.discoverIntermediateStations(
                        on: input.line.corridorRoute,
                        endpointCRSs: [input.line.origin.crs, input.line.destination.crs],
                        catalogStations: [catalogStation]
                    )
                    try Task.checkCancellation()
                    let exactMatches = matches.filter { match in
                        StationEvolution.normalizedCRS(match.station.crs) == stationCRS
                            && match.routeDistance.isFinite
                            && match.routeDistance > input.lowerRouteDistance
                            && match.routeDistance < input.upperRouteDistance
                    }.sorted { lhs, rhs in
                        if lhs.routeDistance != rhs.routeDistance {
                            return lhs.routeDistance < rhs.routeDistance
                        }
                        if lhs.offsetFromRoute != rhs.offsetFromRoute {
                            return lhs.offsetFromRoute < rhs.offsetFromRoute
                        }
                        return lhs.routeCoordinateIndex < rhs.routeCoordinateIndex
                    }
                    if let match = exactMatches.first {
                        results.append(MapStationAdditionDiscoveryResult(
                            input: input,
                            match: match
                        ))
                    }
                } catch is CancellationError {
                    return
                } catch {
                    // One malformed or temporarily unavailable corridor must not hide another
                    // compatible service from the same bounded map tap.
                    continue
                }
            }

            guard !Task.isCancelled else { return }
            self?.completeMapStationAdditionDiscovery(
                requestID: requestID,
                station: catalogStation,
                results: results
            )
        }
    }

    func cancelMapStationAddition() {
        mapStationAdditionRequestID = nil
        mapStationAdditionTask?.cancel()
        mapStationAdditionTask = nil
        pendingMapStationAdditionOptions = [:]
        mapStationAdditionProposal = nil
        isLoadingMapStationAdditionProposal = false
    }

    /// Applies the exact anchor-validated match retained by the selected proposal option. Every
    /// mutable precondition and the purchase quote are checked again by the shared transaction.
    @discardableResult
    func confirmMapStationAddition(onLineID lineID: UUID) -> Bool {
        guard let proposal = mapStationAdditionProposal,
              let pendingOption = pendingMapStationAdditionOptions[lineID],
              let currentLine = lines.first(where: { $0.id == lineID }),
              lineIsCompatibleWithMapStationAdditionSnapshot(
                  currentLine,
                  pendingOption.sourceLine
              ) else {
            cancelMapStationAddition()
            return false
        }

        let station = proposal.station
        let match = pendingOption.match
        cancelMapStationAddition()
        return commitIntermediateStation(station, toLineID: lineID, using: match)
    }

    func intermediateStationAdditionCostPence(
        _ station: Station,
        toLineID lineID: UUID
    ) -> Int64? {
        guard let line = lines.first(where: { $0.id == lineID }), line.isConstructed else {
            return nil
        }
        guard line.railwayClass == .conventional,
              line.corridorIDs.count == 1,
              line.stationCRSs.count < maximumServiceCallCount else { return nil }
        let crs = StationEvolution.normalizedCRS(station.crs)
        guard !crs.isEmpty,
              !line.stationCRSs.map(StationEvolution.normalizedCRS).contains(crs) else {
            return nil
        }
        return networkStationCRSs.contains(crs)
            ? 0
            : max(capitalEconomy.configuration.stationConstructionCostPence, 0)
    }

    func canAffordIntermediateStation(_ station: Station, toLineID lineID: UUID) -> Bool {
        guard let quote = intermediateStationAdditionQuote(station, toLineID: lineID) else {
            return false
        }
        var candidateLedger = financeLedger
        return capitalEconomy.recordPurchase(quote, in: &candidateLedger)
    }

    func addIntermediateStation(_ station: Station, toLineID lineID: UUID) {
        guard editingStopsLineID == lineID,
              !isUpdatingLineStops,
              let match = editableIntermediateMatches.first(where: {
                  StationEvolution.normalizedCRS($0.station.crs)
                      == StationEvolution.normalizedCRS(station.crs)
              }) else {
            return
        }

        _ = commitIntermediateStation(station, toLineID: lineID, using: match)
    }

    @discardableResult
    private func commitIntermediateStation(
        _ station: Station,
        toLineID lineID: UUID,
        using match: CorridorStationMatch
    ) -> Bool {
        guard let lineIndex = lines.firstIndex(where: { $0.id == lineID }),
              lines[lineIndex].isConstructed,
              lines[lineIndex].railwayClass == .conventional,
              lines[lineIndex].corridorIDs.count == 1,
              lines[lineIndex].stationCRSs.count < maximumServiceCallCount,
              let quote = intermediateStationAdditionQuote(station, toLineID: lineID) else {
            return false
        }
        let line = lines[lineIndex]
        guard let corridorID = line.corridorIDs.first,
              let corridorIndex = corridors.firstIndex(where: { $0.id == corridorID }) else {
            presentError(
                "That station could not be added because its railway corridor is unavailable.",
                recoveringTo: .operating
            )
            return false
        }
        let retainedCorridor = corridors[corridorIndex]
        guard let insertion = intermediateStationInsertionPlan(
            for: station,
            match: match,
            line: line
        ) else {
            presentError(
                "That station could not be added to a usable railway route.",
                recoveringTo: .operating
            )
            return false
        }
        let updatedCorridorRoute = insertion.corridorRoute
        let serviceStationCRSs = insertion.serviceStationCRSs
        let serviceRoute = insertion.serviceRoute

        let previousAutomaticPlans = defaultServicePlans(
            servicePattern: line.servicePattern,
            stationCRSs: line.stationCRSs,
            route: line.route,
            railwayClass: line.railwayClass
        )
        let updatedAutomaticPlans = defaultServicePlans(
            servicePattern: line.servicePattern,
            stationCRSs: serviceStationCRSs,
            route: serviceRoute,
            railwayClass: line.railwayClass
        )
        guard let proposedServicePlans = servicePlans(
            line.trainServicePlans,
            afterAddingStationsTo: serviceStationCRSs,
            replacing: previousAutomaticPlans,
            with: updatedAutomaticPlans
        ) else {
            presentError(
                "That station could not be added without creating an invalid timetable.",
                recoveringTo: .operating
            )
            return false
        }

        let serviceGeometryIsUnchanged = routesHaveEquivalentGeometry(
            line.route,
            serviceRoute
        )
        let updatedTrains = serviceGeometryIsUnchanged
            ? line.trains
            : remappingTrains(
                line.trains,
                from: line.route,
                stationCRSs: line.stationCRSs,
                to: serviceRoute,
                stationCRSs: serviceStationCRSs
            )
        var updatedLine = BuiltLine(
            id: line.id,
            name: line.name,
            origin: line.origin,
            destination: line.destination,
            route: serviceRoute,
            distanceMetres: serviceGeometryIsUnchanged
                ? line.distanceMetres
                : serviceRoute.totalLength,
            indicativeCost: line.corridorIndicativeCost,
            styleIndex: line.styleIndex,
            railwayClass: line.railwayClass,
            formation: line.formation,
            servicePattern: line.servicePattern,
            trackCapacity: line.trackCapacity,
            serviceFrequency: line.serviceFrequency,
            ownedTrainCount: line.ownedTrainCount,
            constructionProgress: line.constructionProgress,
            trains: updatedTrains,
            corridorIDs: line.corridorIDs,
            stationCRSs: serviceStationCRSs,
            trainServicePlans: proposedServicePlans,
            corridorStationCRSs: insertion.corridorStationCRSs,
            corridorRoute: updatedCorridorRoute,
            corridorDistanceMetres: line.corridorDistanceMetres,
            corridorIndicativeCost: line.corridorIndicativeCost
        )
        guard let safeServicePlans = servicePlans(
            preservingValidPlansFrom: proposedServicePlans,
            fallingBackTo: updatedAutomaticPlans,
            on: updatedLine
        ) else {
            presentError(
                "That station could not be added without creating an invalid timetable.",
                recoveringTo: .operating
            )
            return false
        }
        updatedLine.trainServicePlans = safeServicePlans
        updatedLine.trains = reconciledFleetWithServicePlans(for: updatedLine)

        let updatedRetainedCorridor = RailwayCorridor(
            id: retainedCorridor.id,
            stationCRSs: insertion.corridorStationCRSs,
            route: updatedCorridorRoute,
            distanceMetres: retainedCorridor.distanceMetres,
            indicativeCost: retainedCorridor.indicativeCost,
            railwayClass: retainedCorridor.railwayClass,
            trackCapacity: retainedCorridor.trackCapacity,
            constructionProgress: retainedCorridor.constructionProgress
        )

        // Validate and reconcile the complete replacement line before even staging its capital
        // transaction. This keeps a failed timetable migration fully atomic, including in Career.
        var updatedFinanceLedger = financeLedger
        guard capitalEconomy.recordPurchase(quote, in: &updatedFinanceLedger) else {
            let shortfall = capitalEconomy.fundingShortfall(
                for: quote.totalPence,
                ledger: financeLedger
            )
            presentError(
                "Adding that station needs \(formattedPenceForMessage(shortfall)) more funding.",
                recoveringTo: .operating
            )
            return false
        }

        let shouldRefreshStopEditor = editingStopsLineID == lineID
        cancelLineStopsTask()
        cancelMapStationAddition()
        financeLedger = updatedFinanceLedger
        corridors[corridorIndex] = updatedRetainedCorridor
        lines[lineIndex] = updatedLine
        restartOperatingDayForNetworkChange()
        reconcileStationProgress()
        reconcileSettlementPopulation()
        recalculatePassengerSnapshot()
        markPersistenceChanged()
        if shouldRefreshStopEditor {
            beginEditingStops(forLineID: lineID)
        }
        return true
    }

    func confirmPreview() {
        guard canConfirmPreview,
              let preview,
              previewIsPurchasable(preview) else { return }
        guard canBuildAnotherLine else {
            presentError(
                "This version supports up to \(max(configuration.maximumLineCount, 0)) lines.",
                recoveringTo: lines.isEmpty ? .idle : .operating
            )
            return
        }

        let capitalQuote = capitalQuote(for: preview)
        var updatedFinanceLedger = financeLedger
        guard capitalEconomy.recordPurchase(
            capitalQuote,
            in: &updatedFinanceLedger
        ) else {
            let shortfall = capitalEconomy.fundingShortfall(
                for: capitalQuote.totalPence,
                ledger: financeLedger
            )
            presentError(
                "This line needs \(formattedPenceForMessage(shortfall)) more funding. "
                    + "Open Network finances to arrange a loan.",
                recoveringTo: .preview
            )
            return
        }

        let lineID = UUID()
        let serviceFrequency = ServiceFrequency.halfHourly
        let railwayClass = preview.railwayClass
        let formation = preview.formation
        let trains = makeFleet(
            lineID: lineID,
            route: preview.route,
            frequency: serviceFrequency,
            fallbackCoordinate: preview.origin.coordinate
        )
        let isImmediatelyConstructed = configuration.constructionDuration <= 0
        var line = BuiltLine(
            id: lineID,
            name: "\(preview.origin.name) – \(preview.destination.name)",
            origin: preview.origin,
            destination: preview.destination,
            route: preview.route,
            distanceMetres: preview.distanceMetres,
            indicativeCost: preview.indicativeCost,
            styleIndex: nextAvailableStyleIndex(),
            railwayClass: railwayClass,
            formation: formation,
            servicePattern: railwayClass == .highSpeed ? .express : .balanced,
            trackCapacity: railwayClass == .highSpeed ? .doubleTrack : .singleTrack,
            serviceFrequency: serviceFrequency,
            ownedTrainCount: serviceFrequency.visibleTrainCount,
            constructionProgress: isImmediatelyConstructed ? 1 : 0,
            trains: trains,
            stationCRSs: preview.stationCRSs,
            trainServicePlans: defaultServicePlans(
                servicePattern: railwayClass == .highSpeed ? .express : .balanced,
                stationCRSs: preview.stationCRSs,
                route: preview.route,
                railwayClass: railwayClass
            ),
            corridorStationCRSs: preview.stationCRSs
        )
        line.trains = reconciledFleetWithServicePlans(for: line)

        financeLedger = updatedFinanceLedger
        corridors.append(line.corridor)
        lines.append(line)
        emitPresentationEvent(
            .constructionStarted(lineID: line.id, railwayClass: line.railwayClass)
        )
        reconcileStationProgress()
        self.preview = nil
        clearPreviewStationSelection()
        errorMessage = nil
        markPersistenceChanged()

        if isImmediatelyConstructed {
            finishConstruction()
        } else {
            phase = .constructing
            recalculatePassengerSnapshot()
        }
    }

    func cancelBuild() {
        guard phase != .constructing else { return }

        cancelPendingRoute()
        clearBuildSelection()
        errorMessage = nil
        errorRecoveryPhase = lines.isEmpty ? .idle : .operating
        phase = errorRecoveryPhase
    }

    func dismissError() {
        guard phase == .error else { return }

        errorMessage = nil
        phase = errorRecoveryPhase
        guard !hasResolvedBuildStationEligibility,
              !isLoadingBuildStationEligibility else { return }
        switch errorRecoveryPhase {
        case .selectingOrigin:
            beginBuildStationEligibility(connectedTo: nil)
        case .selectingDestination:
            if let selectedOrigin {
                beginBuildStationEligibility(connectedTo: selectedOrigin)
            }
        default:
            break
        }
    }

    func reset(gameMode: GameMode? = nil) {
        let nextMode = gameMode ?? financeLedger.mode
        cancelMapStationAddition()
        finishEditingStops()
        cancelPendingRoute()
        clearBuildSelection()
        corridors.removeAll()
        lines.removeAll()
        selectedTrainID = nil
        selectedStationID = nil
        isFollowingSelectedTrain = false
        isPlaying = true
        simulationSpeed = .oneX
        stationProgressByCRS = [:]
        settlementPopulationByCRS = [:]
        economyLedger = .zero
        publicBetaHistory = PublicBetaDailyNetworkHistory()
        financeLedger = capitalEconomy.newLedger(mode: nextMode)
        stationUpgradeEvent = nil
        pendingStationUpgradeEvents.removeAll()
        latestPresentationEvent = nil
        presentationEventBuffer.removeAll()
        arrivalOrdinalsByTrainID.removeAll()
        trainArrivalPresentationEventsRemaining = 0
        errorMessage = nil
        errorRecoveryPhase = .idle
        phase = .idle
        recalculatePassengerSnapshot()
        markPersistenceChanged()
        synchronizeClockSuspension()
    }

    @discardableResult
    func takeStandardLoan() -> Bool {
        var updatedFinanceLedger = financeLedger
        guard capitalEconomy.originateLoan(
            in: &updatedFinanceLedger,
            onOperatingDay: economyLedger.completedOperatingDays
        ) else { return false }

        financeLedger = updatedFinanceLedger
        markPersistenceChanged()
        return true
    }

    @discardableResult
    func makeStandardLoanRepayment() -> Bool {
        var updatedFinanceLedger = financeLedger
        guard capitalEconomy.makeEarlyRepayment(in: &updatedFinanceLedger) else {
            return false
        }

        financeLedger = updatedFinanceLedger
        markPersistenceChanged()
        return true
    }

    func togglePlayPause() {
        guard !financeLedger.isBankrupt else { return }
        isPlaying.toggle()
        synchronizeClockSuspension()
        markPersistenceChanged()
    }

    /// Keeps warm resume behavior aligned with a cold restore by discarding wall-clock time
    /// accumulated while the app is not active.
    func setSceneActive(_ isActive: Bool) {
        isSceneActive = isActive
        synchronizeClockSuspension()
    }

    func setSimulationSpeed(_ speed: SimulationSpeed) {
        guard simulationSpeed != speed else { return }
        simulationSpeed = speed
        markPersistenceChanged()
    }

    func toggleSimulationSpeed() {
        setSimulationSpeed(simulationSpeed == .oneX ? .threeX : .oneX)
    }

    /// Produces a compact, geometry-independent save. Routes are reconstructed from the current
    /// railway graph when the snapshot is restored.
    func makeSaveSnapshot() -> GameSaveSnapshot {
        let savedLines = lines.map { line in
            let routeLength = line.route.totalLength
            return SavedLineRecord(
                id: line.id,
                originCRS: line.origin.crs,
                destinationCRS: line.destination.crs,
                styleIndex: line.styleIndex,
                constructionProgress: min(max(line.constructionProgress, 0), 1),
                frequency: SavedServiceFrequency(line.serviceFrequency),
                railwayClass: SavedRailwayClass(line.railwayClass),
                formation: line.formation,
                servicePattern: SavedServicePattern(line.servicePattern),
                trackCapacity: SavedTrackCapacity(line.trackCapacity),
                ownedTrainCount: max(line.ownedTrainCount, line.trains.count),
                trains: line.trains.map { train in
                    let normalizedRouteProgress: Double
                    if routeLength.isFinite, routeLength > 0,
                       train.distanceAlongRoute.isFinite {
                        normalizedRouteProgress = min(
                            max(train.distanceAlongRoute / routeLength, 0),
                            1
                        )
                    } else {
                        normalizedRouteProgress = 0
                    }

                    return SavedTrainRecord(
                        id: train.id,
                        normalizedRouteProgress: normalizedRouteProgress,
                        direction: SavedTrainDirection(train.direction),
                        dwellRemaining: max(train.dwellRemaining, 0)
                    )
                },
                corridorIDs: line.corridorIDs,
                stationCRSs: line.stationCRSs,
                trainServicePlans: line.trainServicePlans.map(SavedTrainServicePlan.init)
            )
        }
        let savedCorridors = corridors.map { corridor in
            SavedRailwayCorridorRecord(
                id: corridor.id,
                stationCRSs: corridor.stationCRSs,
                constructionProgress: min(max(corridor.constructionProgress, 0), 1),
                railwayClass: SavedRailwayClass(corridor.railwayClass),
                trackCapacity: SavedTrackCapacity(corridor.trackCapacity)
            )
        }

        return GameSaveSnapshot(
            isPlaying: isPlaying,
            simulationSpeed: SavedSimulationSpeed(simulationSpeed),
            lines: savedLines,
            corridors: savedCorridors,
            stationProgress: stationProgressByCRS.keys.sorted().compactMap { crs in
                guard let progress = stationProgressByCRS[crs] else { return nil }
                return SavedStationProgressRecord(
                    stationCRS: crs,
                    level: SavedStationLevel(progress.level),
                    lifetimePassengerVisits: max(progress.lifetimePassengerVisits, 0)
                )
            },
            stationPopulations: settlementPopulationByCRS.keys.sorted().compactMap { crs in
                guard let state = settlementPopulationByCRS[crs] else { return nil }
                return SavedStationPopulationRecord(
                    stationCRS: crs,
                    currentPopulation: max(state.currentPopulation, 1),
                    latestOperatingDayChange: min(
                        max(state.latestDailyChange, 0),
                        max(state.currentPopulation, 1)
                    )
                )
            },
            economy: SavedEconomyLedger(
                completedOperatingDays: economyLedger.completedOperatingDays,
                operatingDayProgress: min(max(economyLedger.operatingDayProgress, 0), 0.999_999_999),
                lifetimeRevenuePence: max(economyLedger.lifetimeRevenuePence, 0),
                lifetimeOperatingCostPence: max(economyLedger.lifetimeOperatingCostPence, 0)
            ),
            financialState: SavedFinancialState(
                ledger: financeLedger,
                trackingStartedOnOperatingDay: financeLedger.trackingStartedOnOperatingDay
            ),
            publicBetaHistory: publicBetaHistory
        )
    }

    /// Restores durable gameplay state without partially changing this session if validation or
    /// rerouting fails. Geometry, distance and indicative cost always come from the current data.
    func restore(from snapshot: GameSaveSnapshot) async throws {
        cancelMapStationAddition()
        guard snapshot.schemaVersion == GameSaveSnapshot.currentSchemaVersion else {
            throw GameSessionRestoreError.unsupportedSchema(snapshot.schemaVersion)
        }

        let maximumLineCount = max(configuration.maximumLineCount, 0)
        let maximumStyleIndex = max(maximumLineCount - 1, 0)
        let savedLines = Array(snapshot.lines.prefix(maximumLineCount))
        let incompleteLineCount = savedLines.lazy.filter { savedLine in
            savedLine.constructionProgress.isFinite
                && min(max(savedLine.constructionProgress, 0), 1) < 1
        }.count
        guard incompleteLineCount <= 1 else {
            throw GameSessionRestoreError.invalidFleet
        }
        let stationLookup = Dictionary(
            stations.map { (StationEvolution.normalizedCRS($0.crs), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var restoredCorridors = [RailwayCorridor]()
        restoredCorridors.reserveCapacity(snapshot.corridors.count)
        var restoredCorridorsByID = [UUID: RailwayCorridor]()
        for savedCorridor in snapshot.corridors {
            guard restoredCorridorsByID[savedCorridor.id] == nil else {
                throw GameSessionRestoreError.duplicateIdentifier
            }
            let stationCRSs = savedCorridor.stationCRSs.map(
                StationEvolution.normalizedCRS
            )
            guard stationCRSs.count >= 2,
                  Set(stationCRSs).count == stationCRSs.count,
                  stationCRSs.allSatisfy({ stationLookup[$0] != nil }) else {
                let missingCRS = stationCRSs.first(where: { stationLookup[$0] == nil })
                    ?? stationCRSs.first ?? ""
                throw GameSessionRestoreError.stationUnavailable(missingCRS)
            }

            let route: ServiceRailwayRoute
            do {
                route = try await routingProvider.route(forStationCRSs: stationCRSs)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let originName = stationLookup[stationCRSs[0]]?.name ?? stationCRSs[0]
                let destinationName = stationLookup[stationCRSs[stationCRSs.count - 1]]?.name
                    ?? stationCRSs[stationCRSs.count - 1]
                throw GameSessionRestoreError.routeUnavailable(
                    originName,
                    destinationName,
                    underlyingDescription: (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                )
            }
            guard isUsableServiceRoute(route, expectedStationCount: stationCRSs.count) else {
                let originName = stationLookup[stationCRSs[0]]?.name ?? stationCRSs[0]
                let destinationName = stationLookup[stationCRSs[stationCRSs.count - 1]]?.name
                    ?? stationCRSs[stationCRSs.count - 1]
                throw GameSessionRestoreError.unusableRoute(originName, destinationName)
            }

            let corridor = RailwayCorridor(
                id: savedCorridor.id,
                stationCRSs: stationCRSs,
                route: route,
                distanceMetres: route.totalLength,
                indicativeCost: indicativeCost(forDistance: route.totalLength),
                railwayClass: RailwayClass(savedCorridor.railwayClass),
                trackCapacity: TrackCapacity(savedCorridor.trackCapacity),
                constructionProgress: min(max(savedCorridor.constructionProgress, 0), 1)
            )
            restoredCorridors.append(corridor)
            restoredCorridorsByID[corridor.id] = corridor
        }
        var restoredLines = [BuiltLine]()
        restoredLines.reserveCapacity(savedLines.count)
        var restoredLineIDs = Set<UUID>()
        var restoredTrainIDs = Set<UUID>()
        var restoredStationPairs = Set<String>()

        for savedLine in savedLines {
            guard restoredLineIDs.insert(savedLine.id).inserted else {
                throw GameSessionRestoreError.duplicateIdentifier
            }
            guard !savedLine.trains.isEmpty else {
                throw GameSessionRestoreError.invalidFleet
            }
            guard savedLine.constructionProgress.isFinite else {
                throw GameSessionRestoreError.invalidNumericValue
            }
            let referencedCorridors = savedLine.corridorIDs.compactMap {
                restoredCorridorsByID[$0]
            }
            guard !referencedCorridors.isEmpty,
                  referencedCorridors.count == savedLine.corridorIDs.count,
                  Set(savedLine.corridorIDs).count == savedLine.corridorIDs.count else {
                throw GameSessionRestoreError.invalidFleet
            }

            let originCRS = savedLine.originCRS
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            let destinationCRS = savedLine.destinationCRS
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            guard originCRS != destinationCRS else {
                throw GameSessionRestoreError.invalidEndpoints(originCRS, destinationCRS)
            }
            let stationPair = [originCRS, destinationCRS].sorted().joined(separator: "|")
            guard restoredStationPairs.insert(stationPair).inserted else {
                throw GameSessionRestoreError.duplicateConnection(originCRS, destinationCRS)
            }
            guard let origin = stationLookup[originCRS] else {
                throw GameSessionRestoreError.stationUnavailable(originCRS)
            }
            guard let destination = stationLookup[destinationCRS] else {
                throw GameSessionRestoreError.stationUnavailable(destinationCRS)
            }
            let orderedStationCRSs = savedLine.stationCRSs.map {
                StationEvolution.normalizedCRS($0)
            }
            guard orderedStationCRSs.first == originCRS,
                  orderedStationCRSs.last == destinationCRS,
                  Set(orderedStationCRSs).count == orderedStationCRSs.count,
                  orderedStationCRSs.allSatisfy({ stationLookup[$0] != nil }) else {
                let missingCRS = orderedStationCRSs.first(where: { stationLookup[$0] == nil })
                    ?? originCRS
                throw GameSessionRestoreError.stationUnavailable(missingCRS)
            }
            let assemblies = RailwayCorridorChainAssembler.assemblies(
                for: referencedCorridors
            )
            let assemblyMatches = assemblies.compactMap { assembly -> (
                assembly: RailwayCorridorChainAssembly,
                physicalCallIndices: [Int],
                isReversed: Bool
            )? in
                guard let match = serviceCallIndices(
                    orderedStationCRSs,
                    in: assembly.stationCRSs
                ) else { return nil }
                return (assembly, match.indices, match.isReversed)
            }
            guard let assemblyMatch = assemblyMatches.first else {
                throw GameSessionRestoreError.unusableRoute(origin.name, destination.name)
            }
            let assembly = assemblyMatch.assembly
            let route = serviceRoute(
                on: assembly.route,
                stationCoordinateIndices: assemblyMatch.physicalCallIndices.map {
                    assembly.route.stationCoordinateIndices[$0]
                },
                isReversed: assemblyMatch.isReversed
            )
            guard isUsableServiceRoute(
                route,
                expectedStationCount: orderedStationCRSs.count
            ) else {
                throw GameSessionRestoreError.unusableRoute(origin.name, destination.name)
            }

            let constructionProgress = assembly.constructionProgress
            let serviceFrequency = ServiceFrequency(savedLine.frequency)
            let railwayClass = assembly.railwayClass
            let formation = savedLine.formation
            let servicePattern = ServicePattern(savedLine.servicePattern)
            let trackCapacity = assembly.trackCapacity
            guard RailwayClass(savedLine.railwayClass) == railwayClass,
                  TrackCapacity(savedLine.trackCapacity) == trackCapacity,
                  abs(
                    min(max(savedLine.constructionProgress, 0), 1) - constructionProgress
                  ) < 0.000_000_001 else {
                throw GameSessionRestoreError.invalidFleet
            }
            if railwayClass == .highSpeed,
               (servicePattern != .express
                   || trackCapacity != .doubleTrack
                   || orderedStationCRSs.count != 2) {
                throw GameSessionRestoreError.invalidHighSpeedConfiguration
            }
            guard RollingStockFormation.supported(for: railwayClass).contains(formation) else {
                throw GameSessionRestoreError.invalidFleet
            }
            guard savedLine.ownedTrainCount >= serviceFrequency.visibleTrainCount,
                  savedLine.ownedTrainCount
                    <= GameSaveSnapshot.maximumOwnedTrainCountPerService else {
                throw GameSessionRestoreError.invalidFleet
            }
            var restoredTrains = [TrainState]()
            restoredTrains.reserveCapacity(serviceFrequency.visibleTrainCount)

            for savedTrain in savedLine.trains {
                guard restoredTrainIDs.insert(savedTrain.id).inserted else {
                    throw GameSessionRestoreError.duplicateIdentifier
                }
                guard savedTrain.normalizedRouteProgress.isFinite,
                      savedTrain.dwellRemaining.isFinite else {
                    throw GameSessionRestoreError.invalidNumericValue
                }
                guard restoredTrains.count < serviceFrequency.visibleTrainCount else {
                    continue
                }

                let normalizedRouteProgress = min(
                    max(savedTrain.normalizedRouteProgress, 0),
                    1
                )
                let distanceAlongRoute = route.totalLength * normalizedRouteProgress
                let direction = TrainTravelDirection(savedTrain.direction)
                guard let trainSample = route.sample(atDistance: distanceAlongRoute) else {
                    throw GameSessionRestoreError.unusableRoute(origin.name, destination.name)
                }
                restoredTrains.append(
                    TrainState(
                        id: savedTrain.id,
                        lineID: savedLine.id,
                        coordinate: trainSample.coordinate,
                        bearing: normalisedBearing(
                            trainSample.bearing + (direction == .reverse ? 180 : 0)
                        ),
                        distanceAlongRoute: distanceAlongRoute,
                        direction: direction,
                        dwellRemaining: max(savedTrain.dwellRemaining, 0)
                    )
                )
            }
            restoredTrains = completingFleet(
                restoredTrains,
                lineID: savedLine.id,
                route: route,
                frequency: serviceFrequency,
                fallbackCoordinate: origin.coordinate
            )
            let corridorDistanceMetres = assembly.distanceMetres
            let corridorIndicativeCost = assembly.indicativeCost
            let savedServicePlans = savedLine.trainServicePlans.map(\.trainServicePlan)
            let historicalDefaultPlans = TrainServicePlan.legacyDefaults(
                servicePattern: servicePattern,
                serviceStationCRSs: orderedStationCRSs
            )
            // Schema 12 did not record default-plan provenance. An exact preset match is the
            // unambiguous migration case: adopt bounded regional defaults without touching any
            // player-authored terminals or Express calls.
            let restoredServicePlans = savedServicePlans == historicalDefaultPlans
                ? defaultServicePlans(
                    servicePattern: servicePattern,
                    stationCRSs: orderedStationCRSs,
                    route: route,
                    railwayClass: railwayClass
                )
                : savedServicePlans
            var restoredLine = BuiltLine(
                    id: savedLine.id,
                    name: "\(origin.name) – \(destination.name)",
                    origin: origin,
                    destination: destination,
                    route: route,
                    distanceMetres: route.totalLength,
                    indicativeCost: corridorIndicativeCost,
                    styleIndex: min(max(savedLine.styleIndex, 0), maximumStyleIndex),
                    railwayClass: railwayClass,
                    formation: formation,
                    servicePattern: servicePattern,
                    trackCapacity: trackCapacity,
                    serviceFrequency: serviceFrequency,
                    ownedTrainCount: max(
                        savedLine.ownedTrainCount,
                        serviceFrequency.visibleTrainCount
                    ),
                    constructionProgress: constructionProgress,
                    trains: restoredTrains,
                    corridorIDs: savedLine.corridorIDs,
                    stationCRSs: orderedStationCRSs,
                    trainServicePlans: restoredServicePlans,
                    corridorStationCRSs: assembly.stationCRSs,
                    corridorRoute: assembly.route,
                    corridorDistanceMetres: corridorDistanceMetres,
                    corridorIndicativeCost: corridorIndicativeCost
                )
            guard restoredLine.trainServicePlans.allSatisfy({ plan in
                validatedServicePlan(plan, on: restoredLine) == plan
            }) else {
                throw GameSessionRestoreError.invalidFleet
            }
            restoredLine.trains = reconciledFleetWithServicePlans(for: restoredLine)
            restoredLines.append(restoredLine)
        }

        let restoredStationCRSs = Set(restoredCorridors.flatMap { corridor in
            corridor.stationCRSs.map(StationEvolution.normalizedCRS)
        })
        var savedProgressByCRS = [String: StationProgress]()
        for savedProgress in snapshot.stationProgress {
            let crs = StationEvolution.normalizedCRS(savedProgress.stationCRS)
            guard !crs.isEmpty,
                  restoredStationCRSs.contains(crs),
                  savedProgress.lifetimePassengerVisits >= 0,
                  savedProgressByCRS[crs] == nil else {
                throw GameSessionRestoreError.invalidStationProgress
            }
            savedProgressByCRS[crs] = StationProgress(
                level: StationLevel(savedProgress.level),
                lifetimePassengerVisits: savedProgress.lifetimePassengerVisits
            )
        }
        guard snapshot.economy.operatingDayProgress.isFinite,
              (0..<1).contains(snapshot.economy.operatingDayProgress),
              snapshot.economy.lifetimeRevenuePence >= 0,
              snapshot.economy.lifetimeOperatingCostPence >= 0 else {
            throw GameSessionRestoreError.invalidNumericValue
        }
        let restoredStationProgress = stationEvolution.reconcile(
            stationCRSs: Array(restoredStationCRSs),
            existingProgress: savedProgressByCRS
        )
        var savedPopulationStatesByCRS = [String: SettlementPopulationState]()
        for savedPopulation in snapshot.stationPopulations {
            let crs = StationEvolution.normalizedCRS(savedPopulation.stationCRS)
            let candidate = SettlementPopulationState(
                stationCRS: crs,
                baselinePopulation: settlementGrowth.baselinePopulation(
                    forStationCRS: crs
                ),
                currentPopulation: savedPopulation.currentPopulation,
                latestDailyChange: savedPopulation.latestOperatingDayChange
            )
            let sanitized = settlementGrowth.reconcile(
                connectedStationCRSs: [crs],
                existingStatesByCRS: [crs: candidate]
            )[crs]
            guard !crs.isEmpty,
                  restoredStationCRSs.contains(crs),
                  savedPopulation.stationCRS == crs,
                  savedPopulation.currentPopulation == candidate.currentPopulation,
                  savedPopulation.latestOperatingDayChange == candidate.latestDailyChange,
                  sanitized == candidate,
                  savedPopulationStatesByCRS.updateValue(candidate, forKey: crs) == nil else {
                throw GameSessionRestoreError.invalidNumericValue
            }
        }
        guard snapshot.stationPopulations.isEmpty
                || Set(savedPopulationStatesByCRS.keys) == restoredStationCRSs else {
            throw GameSessionRestoreError.invalidNumericValue
        }
        let restoredSettlementPopulation = settlementGrowth.reconcile(
            connectedStationCRSs: Array(restoredStationCRSs),
            existingStatesByCRS: savedPopulationStatesByCRS
        )
        let restoredEconomyLedger = EconomyLedger(
            completedOperatingDays: snapshot.economy.completedOperatingDays,
            operatingDayProgress: snapshot.economy.operatingDayProgress,
            lifetimeRevenuePence: snapshot.economy.lifetimeRevenuePence,
            lifetimeOperatingCostPence: snapshot.economy.lifetimeOperatingCostPence
        )
        guard restoredLines.contains(where: \.isConstructed)
                || restoredEconomyLedger.operatingDayProgress == 0 else {
            throw GameSessionRestoreError.invalidNumericValue
        }
        let restoredFinanceLedger = snapshot.financialState.financeLedger
        guard isValidFinanceLedger(
            restoredFinanceLedger,
            completedOperatingDays: restoredEconomyLedger.completedOperatingDays,
            savedAsPlaying: snapshot.isPlaying
        ) else {
            throw GameSessionRestoreError.invalidNumericValue
        }
        guard snapshot.publicBetaHistory.maximumRecordCount
                == PublicBetaDailyNetworkHistory.defaultMaximumRecordCount,
              snapshot.publicBetaHistory.records.count
                <= PublicBetaDailyNetworkHistory.defaultMaximumRecordCount,
              snapshot.publicBetaHistory.records.allSatisfy({ record in
                  record.operatingDay > 0
                      && record.operatingDay <= restoredEconomyLedger.completedOperatingDays
              }) else {
            throw GameSessionRestoreError.invalidNumericValue
        }

        // Commit only after every record has validated and rerouted successfully.
        finishEditingStops()
        cancelPendingRoute()
        clearBuildSelection()
        corridors = restoredCorridors
        lines = restoredLines
        selectedTrainID = nil
        selectedStationID = nil
        isFollowingSelectedTrain = false
        isPlaying = snapshot.isPlaying
        simulationSpeed = SimulationSpeed(snapshot.simulationSpeed)
        stationProgressByCRS = restoredStationProgress
        settlementPopulationByCRS = restoredSettlementPopulation
        economyLedger = restoredEconomyLedger
        publicBetaHistory = snapshot.publicBetaHistory
        financeLedger = restoredFinanceLedger
        stationUpgradeEvent = nil
        pendingStationUpgradeEvents.removeAll()
        latestPresentationEvent = nil
        presentationEventBuffer.removeAll()
        arrivalOrdinalsByTrainID.removeAll()
        trainArrivalPresentationEventsRemaining = 0
        errorMessage = nil
        errorRecoveryPhase = restoredLines.isEmpty ? .idle : .operating
        if restoredLines.contains(where: { !$0.isConstructed }) {
            phase = .constructing
        } else {
            phase = restoredLines.isEmpty ? .idle : .operating
        }
        recalculatePassengerSnapshot()
        markPersistenceChanged()
        synchronizeClockSuspension()
    }

    func selectTrain(_ id: UUID?) {
        guard let id else {
            finishEditingStops()
            selectedTrainID = nil
            isFollowingSelectedTrain = false
            return
        }
        guard let selectedTrain = trains.first(where: { $0.id == id }) else { return }

        if editingStopsLineID != nil, editingStopsLineID != selectedTrain.lineID {
            finishEditingStops()
        }

        if selectedTrainID != id {
            isFollowingSelectedTrain = false
        }
        selectedStationID = nil
        selectedTrainID = id
    }

    func selectStationForInspection(_ crs: String?) {
        guard let crs else {
            selectedStationID = nil
            return
        }
        let normalizedCRS = crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard stations.contains(where: { $0.crs == normalizedCRS }),
              happinessSnapshot.station(forCRS: normalizedCRS) != nil else { return }

        finishEditingStops()
        selectedTrainID = nil
        isFollowingSelectedTrain = false
        selectedStationID = normalizedCRS
    }

    func setServiceFrequency(_ frequency: ServiceFrequency, forLineID lineID: UUID) {
        guard let lineIndex = lines.firstIndex(where: { $0.id == lineID }) else { return }
        guard lines[lineIndex].serviceFrequency != frequency else { return }

        var line = lines[lineIndex]
        let additionalTrainCount = max(
            frequency.visibleTrainCount - line.ownedTrainCount,
            0
        )
        let rollingStockCost = capitalEconomy.rollingStockCost(
            forTrainCount: additionalTrainCount,
            formation: line.formation,
            railwayClass: line.railwayClass
        )
        var updatedFinanceLedger = financeLedger
        guard capitalEconomy.recordRollingStockPurchase(
            costPence: rollingStockCost,
            in: &updatedFinanceLedger
        ) else {
            let shortfall = capitalEconomy.fundingShortfall(
                for: rollingStockCost,
                ledger: financeLedger
            )
            presentError(
                "That frequency needs \(additionalTrainCount) more train"
                    + "\(additionalTrainCount == 1 ? "" : "s") and "
                    + "\(formattedPenceForMessage(shortfall)) more funding.",
                recoveringTo: .operating
            )
            return
        }

        line.serviceFrequency = frequency
        line.ownedTrainCount = max(line.ownedTrainCount, frequency.visibleTrainCount)
        line.trains = reconfiguredFleet(
            line.trains,
            lineID: line.id,
            route: line.route,
            frequency: frequency,
            fallbackCoordinate: line.origin.coordinate
        )
        line.trains = reconciledFleetWithServicePlans(for: line)
        if line.servicePattern == .balanced,
           line.trackCapacity.allowsOvertaking,
           !usesCustomServicePlans(line) {
            line.trains = stagedOvertakingFleet(for: line)
        }
        financeLedger = updatedFinanceLedger
        lines[lineIndex] = line

        if let selectedTrainID,
           !line.trains.contains(where: { $0.id == selectedTrainID }) {
            self.selectedTrainID = nil
            isFollowingSelectedTrain = false
        }

        recalculatePassengerSnapshot()
        markPersistenceChanged()
    }

    /// Adds two carriages to every trainset already owned by the line. The finance ledger and
    /// formation are committed together, so an unaffordable Career purchase cannot partially
    /// upgrade the fleet.
    @discardableResult
    func extendFormation(forLineID lineID: UUID) -> Bool {
        guard let lineIndex = lines.firstIndex(where: { $0.id == lineID }) else {
            return false
        }
        let currentLine = lines[lineIndex]
        guard currentLine.isConstructed, !financeLedger.isBankrupt else { return false }
        guard let quote = capitalEconomy.quoteForFormationExtension(
            ownedTrainCount: currentLine.ownedTrainCount,
            currentFormation: currentLine.formation,
            railwayClass: currentLine.railwayClass
        ) else {
            return false
        }

        var updatedFinanceLedger = financeLedger
        guard capitalEconomy.recordRollingStockPurchase(
            costPence: quote.totalCostPence,
            in: &updatedFinanceLedger
        ) else {
            let shortfall = capitalEconomy.fundingShortfall(
                for: quote.totalCostPence,
                ledger: financeLedger
            )
            presentError(
                "Longer trains need \(formattedPenceForMessage(shortfall)) more funding. "
                    + "Open Network finances to arrange a loan.",
                recoveringTo: .operating
            )
            return false
        }

        var upgradedLine = currentLine
        upgradedLine.formation = quote.upgradedFormation
        financeLedger = updatedFinanceLedger
        lines[lineIndex] = upgradedLine
        recalculatePassengerSnapshot()
        markPersistenceChanged()
        return true
    }

    func setServicePattern(_ pattern: ServicePattern, forLineID lineID: UUID) {
        guard let lineIndex = lines.firstIndex(where: { $0.id == lineID }),
              lines[lineIndex].railwayClass == .conventional else { return }

        var line = lines[lineIndex]
        let planning = automaticPlanningResult(
            servicePattern: pattern,
            stationCRSs: line.stationCRSs,
            route: line.route,
            railwayClass: line.railwayClass
        )
        if pattern == .local,
           let gap = planning.unbridgeableStationPairs.first,
           gap.count == 2 {
            let firstName = station(forNormalizedCRS: gap[0])?.name ?? gap[0]
            let secondName = station(forNormalizedCRS: gap[1])?.name ?? gap[1]
            presentError(
                "Local trains need another station between \(firstName) and \(secondName). "
                    + "Add an intermediate station or keep an Express service across this gap.",
                recoveringTo: .operating
            )
            return
        }
        let resetPlans = planning.representativePlans
        guard line.servicePattern != pattern || line.trainServicePlans != resetPlans else {
            return
        }
        line.servicePattern = pattern
        line.trainServicePlans = resetPlans
        if pattern == .balanced, line.trackCapacity.allowsOvertaking {
            line.trains = stagedOvertakingFleet(for: line)
        }
        line.trains = reconciledFleetWithServicePlans(for: line)
        lines[lineIndex] = line
        recalculatePassengerSnapshot()
        markPersistenceChanged()
    }

    /// Applies one train's strategic stopping plan over stations that are already built. The
    /// edit is free and atomic: invalid terminals or call order leave the live service untouched.
    @discardableResult
    func setTrainServicePlan(
        _ requestedPlan: TrainServicePlan,
        forTrainID trainID: UUID
    ) -> Bool {
        guard let lineIndex = lines.firstIndex(where: { line in
            line.trains.contains(where: { $0.id == trainID })
        }) else { return false }
        var line = lines[lineIndex]
        guard line.isConstructed,
              line.railwayClass == .conventional,
              let trainIndex = line.trains.firstIndex(where: { $0.id == trainID }),
              let planIndex = line.trainServicePlans.firstIndex(where: {
                  $0.slotIndex == trainIndex
              }),
              let plan = validatedServicePlan(
                  TrainServicePlan(
                      slotIndex: trainIndex,
                      role: requestedPlan.role,
                      stationCRSs: requestedPlan.stationCRSs
                  ),
                  on: line
              ) else { return false }
        guard line.trainServicePlans[planIndex] != plan else { return true }

        line.trainServicePlans[planIndex] = plan
        line.trains[trainIndex] = reconciledTrain(
            line.trains[trainIndex],
            with: plan,
            on: line
        )
        lines[lineIndex] = line
        recalculatePassengerSnapshot()
        markPersistenceChanged()
        return true
    }

    func servicePlanValidationMessage(
        _ requestedPlan: TrainServicePlan,
        forTrainID trainID: UUID
    ) -> String? {
        guard let line = lines.first(where: { line in
            line.trains.contains(where: { $0.id == trainID })
        }),
        let slotIndex = line.trains.firstIndex(where: { $0.id == trainID }) else {
            return "This train is no longer available."
        }
        let candidate = TrainServicePlan(
            slotIndex: slotIndex,
            role: requestedPlan.role,
            stationCRSs: requestedPlan.stationCRSs
        )
        guard validatedServicePlan(candidate, on: line) == nil else { return nil }
        if candidate.role == .local {
            return "This journey is too long for a Local train. Choose closer terminals or make it Express."
        }
        return "Choose two valid terminals and keep calling points in railway order."
    }

    func hasCustomServicePlans(forLineID lineID: UUID) -> Bool {
        guard let line = lines.first(where: { $0.id == lineID }) else { return false }
        return usesCustomServicePlans(line)
    }

    private func usesCustomServicePlans(_ line: BuiltLine) -> Bool {
        line.trainServicePlans != defaultServicePlans(
            servicePattern: line.servicePattern,
            stationCRSs: line.stationCRSs,
            route: line.route,
            railwayClass: line.railwayClass
        )
    }

    private func automaticPlanningResult(
        servicePattern: ServicePattern,
        stationCRSs: [String],
        route: ServiceRailwayRoute,
        railwayClass: RailwayClass
    ) -> AutomaticServicePlanningResult {
        let normalized = stationCRSs.map(StationEvolution.normalizedCRS)
        if railwayClass == .highSpeed {
            return AutomaticServicePlanningResult(
                representativePlans: TrainServicePlan.legacyDefaults(
                    servicePattern: .express,
                    serviceStationCRSs: normalized
                ),
                localZones: [],
                unbridgeableStationPairs: []
            )
        }
        return automaticServicePlanner.plan(
            servicePattern: servicePattern,
            stationCRSs: normalized,
            cumulativeDistancesMetres: cumulativeStationDistances(
                for: route,
                expectedStationCount: normalized.count
            )
        )
    }

    private func defaultServicePlans(
        servicePattern: ServicePattern,
        stationCRSs: [String],
        route: ServiceRailwayRoute,
        railwayClass: RailwayClass
    ) -> [TrainServicePlan] {
        automaticPlanningResult(
            servicePattern: servicePattern,
            stationCRSs: stationCRSs,
            route: route,
            railwayClass: railwayClass
        ).representativePlans
    }

    /// Expands untouched automatic Local slots into every bounded regional zone for the
    /// low-cadence passenger and station-capacity models. Map animation still uses the four
    /// representative trains, which prevents a national railway from creating hundreds of
    /// continuously updating SwiftUI annotations.
    private func logicalServiceRuns(for line: BuiltLine) -> [LogicalServiceRun] {
        let planning = automaticPlanningResult(
            servicePattern: line.servicePattern,
            stationCRSs: line.stationCRSs,
            route: line.route,
            railwayClass: line.railwayClass
        )
        let activePlans = line.trains.indices.compactMap { line.servicePlan(forSlot: $0) }
        return logicalServiceRuns(
            planning: planning,
            stationCRSs: line.stationCRSs,
            activePlans: activePlans
        )
    }

    /// Uses the same regional-service expansion for an unbuilt preview and a live railway.
    /// Keeping this independent of train sprites lets nationwide previews remain truthful
    /// without materialising every regional working as an animated train.
    private func logicalServiceRuns(
        planning: AutomaticServicePlanningResult,
        stationCRSs: [String],
        activePlans: [TrainServicePlan]
    ) -> [LogicalServiceRun] {
        let defaultPlansBySlot = Dictionary(
            uniqueKeysWithValues: planning.representativePlans.map { ($0.slotIndex, $0) }
        )
        var automaticLocalLaneCount = 0
        var automaticExpressLaneCount = 0
        var customRuns = [LogicalServiceRun]()

        for plan in activePlans.sorted(by: { $0.slotIndex < $1.slotIndex }) {
            if defaultPlansBySlot[plan.slotIndex] == plan {
                switch plan.role {
                case .local: automaticLocalLaneCount += 1
                case .express: automaticExpressLaneCount += 1
                }
            } else {
                customRuns.append(LogicalServiceRun(
                    identifier: plan.slotIndex,
                    stationCRSs: plan.stationCRSs,
                    scheduledDeparturesPerHour: 1
                ))
            }
        }

        var runs = customRuns
        if automaticLocalLaneCount > 0 {
            for (zoneIndex, zone) in planning.localZones.enumerated() where zone.count >= 2 {
                runs.append(LogicalServiceRun(
                    identifier: 10_000 + zoneIndex,
                    stationCRSs: zone,
                    scheduledDeparturesPerHour: Double(automaticLocalLaneCount)
                ))
            }
        }
        if automaticExpressLaneCount > 0,
           let first = stationCRSs.first,
           let last = stationCRSs.last,
           first != last {
            runs.append(LogicalServiceRun(
                identifier: 20_000,
                stationCRSs: [first, last],
                scheduledDeparturesPerHour: Double(automaticExpressLaneCount)
            ))
        }
        return runs.sorted { $0.identifier < $1.identifier }
    }

    @discardableResult
    func upgradeTrackCapacity(forLineID lineID: UUID) -> Bool {
        guard canUpgradeTrack(forLineID: lineID),
              let lineIndex = lines.firstIndex(where: { $0.id == lineID }) else {
            return false
        }
        let currentLine = lines[lineIndex]
        guard let corridorID = currentLine.corridorIDs.first,
              let corridorIndex = corridors.firstIndex(where: { $0.id == corridorID }) else {
            return false
        }
        let currentCorridor = corridors[corridorIndex]
        guard let nextCapacity = currentLine.trackCapacity.next,
              let cost = trainOperations.upgradeCostPence(
                from: currentLine.trackCapacity,
                constructionCostPounds: currentLine.corridorIndicativeCost
              ) else {
            return false
        }

        var updatedFinanceLedger = financeLedger
        let quote = CapitalPurchaseQuote(
            trackAndInfrastructurePence: cost,
            stationConstructionPence: 0,
            rollingStockPence: 0
        )
        guard capitalEconomy.recordPurchase(quote, in: &updatedFinanceLedger) else {
            let shortfall = capitalEconomy.fundingShortfall(
                for: cost,
                ledger: financeLedger
            )
            presentError(
                "This upgrade needs \(formattedPenceForMessage(shortfall)) more funding. "
                    + "Open Network finances to arrange a loan.",
                recoveringTo: .operating
            )
            return false
        }

        var upgradedLine = currentLine
        upgradedLine.trackCapacity = nextCapacity
        if upgradedLine.servicePattern == .balanced {
            upgradedLine.trains = stagedOvertakingFleet(for: upgradedLine)
        }
        var upgradedCorridor = currentCorridor
        upgradedCorridor.trackCapacity = nextCapacity
        financeLedger = updatedFinanceLedger
        corridors[corridorIndex] = upgradedCorridor
        lines[lineIndex] = upgradedLine
        recalculatePassengerSnapshot()
        emitPresentationEvent(
            .infrastructureUpgraded(lineID: lineID, capacity: nextCapacity)
        )
        markPersistenceChanged()
        return true
    }

    func setFollowingSelectedTrain(_ shouldFollow: Bool) {
        isFollowingSelectedTrain = shouldFollow && selectedTrain != nil
    }

    func dismissStationUpgradeEvent(id: UUID) {
        guard stationUpgradeEvent?.id == id else { return }
        stationUpgradeEvent = nil
        presentNextStationUpgradeEventIfNeeded()
    }

    /// Advances construction, trains and the low-cadence operating day by an exact elapsed-time
    /// delta. Slicing at construction and day boundaries keeps large test ticks equivalent to
    /// many display-link ticks.
    func tick(delta rawDelta: TimeInterval) {
        guard isPlaying,
              !financeLedger.isBankrupt,
              rawDelta.isFinite,
              rawDelta > 0 else { return }

        let multiplier = simulationSpeed.multiplier
        let maximumDelta = min(
            Self.maximumSimulatedSecondsPerTick,
            effectiveOperatingDayDuration
                * TimeInterval(Self.maximumOperatingDaySettlementsPerTick)
        )
        let elapsed = rawDelta >= maximumDelta / multiplier
            ? maximumDelta
            : rawDelta * multiplier
        guard elapsed.isFinite, elapsed > 0 else { return }

        trainArrivalPresentationEventsRemaining =
            Self.maximumTrainArrivalPresentationEventsPerTick
        defer { trainArrivalPresentationEventsRemaining = 0 }

        var remaining = elapsed
        var settledOperatingDays = 0
        while remaining > 0.000_000_001 {
            guard settledOperatingDays < Self.maximumOperatingDaySettlementsPerTick else {
                break
            }
            let timeToConstruction = timeUntilConstructionCompletes()
            let timeToOperatingDay = timeUntilOperatingDayCompletes()
            let slice = min(remaining, timeToConstruction, timeToOperatingDay)
            guard slice.isFinite, slice > 0 else {
                if timeToOperatingDay <= 0 {
                    if settleOperatingDay() { return }
                    settledOperatingDays += 1
                    continue
                }
                if timeToConstruction <= 0 {
                    finishConstructionIfNeeded()
                    continue
                }
                break
            }

            let hadOperatingLine = lines.contains(where: \.isConstructed)
            advanceLines(by: slice)
            if hadOperatingLine {
                let dayDuration = effectiveOperatingDayDuration
                operatingDayProgress = min(
                    operatingDayProgress + slice / dayDuration,
                    1
                )
            }
            remaining -= slice

            // A line that completes exactly on a settlement boundary starts contributing on the
            // following day rather than being credited for a day in which it did not operate.
            if operatingDayProgress >= 1 {
                if settleOperatingDay() { return }
                settledOperatingDays += 1
            }
            finishConstructionIfNeeded()
        }
    }

    private func advanceLines(by elapsed: TimeInterval) {
        guard elapsed > 0, !lines.isEmpty else { return }

        // Build the next frame off the observed properties and publish each collection once.
        // Mutating `lines[index]` directly used to notify SwiftUI once per service at 20 Hz,
        // making map cost grow sharply with a national network even when most trains were offscreen.
        var nextLines = lines
        let hasActiveConstruction = nextLines.contains { !$0.isConstructed }
        var nextCorridors = hasActiveConstruction ? corridors : []
        var corridorsChanged = false
        let corridorIndicesByID: [UUID: Int] = hasActiveConstruction
            ? Dictionary(
                uniqueKeysWithValues: nextCorridors.indices.map {
                    (nextCorridors[$0].id, $0)
                }
            )
            : [:]

        for index in nextLines.indices {
            var line = nextLines[index]

            if !line.isConstructed {
                let duration = configuration.constructionDuration
                if duration <= 0 {
                    line.constructionProgress = 1
                } else {
                    line.constructionProgress = min(
                        1,
                        line.constructionProgress + elapsed / duration
                    )
                }
            } else {
                let operations = operationsSnapshotsByLineID[line.id]
                    ?? operationsSnapshot(for: line)
                let movementTopology = trainMovementTopology(for: line)
                for trainIndex in line.trains.indices {
                    var train = line.trains[trainIndex]
                    let fallbackRole = trainOperations.role(
                        forTrainAt: trainIndex,
                        trainCount: line.trains.count,
                        pattern: line.servicePattern
                    )
                    let plan = line.servicePlan(forSlot: trainIndex)
                        ?? TrainServicePlan(
                            slotIndex: trainIndex,
                            role: fallbackRole,
                            stationCRSs: fallbackRole == .local
                                ? line.stationCRSs
                                : [line.stationCRSs.first, line.stationCRSs.last].compactMap { $0 }
                        )
                    let planTopology = trainMovementPlanTopology(
                        for: line,
                        trainIndex: trainIndex,
                        plan: plan,
                        movementTopology: movementTopology,
                        operations: operations
                    )
                    let arrivals = advanceTrain(
                        &train,
                        on: line.route,
                        planTopology: planTopology,
                        elapsed: elapsed,
                        operations: operations
                    )
                    line.trains[trainIndex] = train
                    recordTrainArrivals(
                        arrivals,
                        for: train,
                        on: line
                    )
                }
            }

            if hasActiveConstruction,
               line.corridorIDs.count == 1,
               let corridorID = line.corridorIDs.first,
               let corridorIndex = corridorIndicesByID[corridorID] {
                let previousProgress = nextCorridors[corridorIndex].constructionProgress
                if previousProgress != line.constructionProgress {
                    nextCorridors[corridorIndex].constructionProgress = line.constructionProgress
                    corridorsChanged = true
                }
            }

            nextLines[index] = line
        }
        lines = nextLines
        if corridorsChanged {
            corridors = nextCorridors
        }
    }

    private func trainMovementTopology(for line: BuiltLine) -> TrainMovementTopology {
        if let cached = trainMovementTopologyByLineID[line.id] {
            return cached
        }
        let topology = TrainMovementTopology(
            stationDistances: cumulativeStationDistances(
                for: line.route,
                expectedStationCount: line.stationCRSs.count
            ),
            stationIndicesByCRS: Dictionary(
                uniqueKeysWithValues: line.stationCRSs.enumerated().map {
                    (StationEvolution.normalizedCRS($0.element), $0.offset)
                }
            )
        )
        trainMovementTopologyByLineID[line.id] = topology
        return topology
    }

    private func trainMovementPlanTopology(
        for line: BuiltLine,
        trainIndex: Int,
        plan: TrainServicePlan,
        movementTopology: TrainMovementTopology,
        operations: LineOperationsSnapshot
    ) -> TrainMovementPlanTopology {
        if let cached = trainMovementPlanTopologiesByLineID[line.id]?[trainIndex] {
            return cached
        }

        let calls = plan.stationCRSs.compactMap { crs -> TrainMovementPlanTopology.Call? in
            guard let index = movementTopology.stationIndicesByCRS[
                StationEvolution.normalizedCRS(crs)
            ],
            movementTopology.stationDistances.indices.contains(index) else {
                return nil
            }
            return TrainMovementPlanTopology.Call(
                stationIndex: index,
                distance: movementTopology.stationDistances[index]
            )
        }

        let result: TrainMovementPlanTopology
        if calls.count >= 2,
           calls.count == plan.stationCRSs.count,
           let lowerCall = calls.min(by: { $0.distance < $1.distance }),
           let upperCall = calls.max(by: { $0.distance < $1.distance }) {
            let routeLength = line.route.totalLength
            let lowerBound = lowerCall.distance
            let upperBound = upperCall.distance
            let operatingDistance = upperBound - lowerBound
            let epsilon = max(routeLength * 0.000_000_001, 0.001)
            let selectedIntermediateStops = calls
                .filter {
                    $0.distance > lowerBound + epsilon
                        && $0.distance < upperBound - epsilon
                }
                .sorted { $0.distance < $1.distance }
                .map {
                    TrainMovementPlanTopology.Stop(
                        stationIndex: $0.stationIndex,
                        distance: $0.distance
                    )
                }
            let intermediateStops: [TrainMovementPlanTopology.Stop]
            if !selectedIntermediateStops.isEmpty {
                intermediateStops = selectedIntermediateStops
            } else if plan.role == .local,
                      operations.hasMixedServices,
                      operations.trackCapacity == .passingLoop {
                intermediateStops = [
                    TrainMovementPlanTopology.Stop(
                        stationIndex: nil,
                        distance: lowerBound + operatingDistance * 0.5
                    ),
                ]
            } else {
                intermediateStops = []
            }
            result = TrainMovementPlanTopology(
                role: plan.role,
                lowerCall: lowerCall,
                upperCall: upperCall,
                intermediateStops: intermediateStops
            )
        } else {
            result = TrainMovementPlanTopology(
                role: plan.role,
                lowerCall: nil,
                upperCall: nil,
                intermediateStops: []
            )
        }

        var lineTopologies = trainMovementPlanTopologiesByLineID[line.id] ?? [:]
        lineTopologies[trainIndex] = result
        trainMovementPlanTopologiesByLineID[line.id] = lineTopologies
        return result
    }

    private func finishConstructionIfNeeded() {
        if phase == .constructing, lines.allSatisfy(\.isConstructed) {
            finishConstruction()
        }
    }

    private func timeUntilConstructionCompletes() -> TimeInterval {
        let duration = configuration.constructionDuration
        guard duration.isFinite, duration > 0 else { return .infinity }
        return lines
            .filter { !$0.isConstructed }
            .map { max(1 - $0.constructionProgress, 0) * duration }
            .min() ?? .infinity
    }

    private var effectiveOperatingDayDuration: TimeInterval {
        let duration = configuration.operatingDayDuration
        guard duration.isFinite, duration > 0 else { return 30 }
        return max(duration, 1)
    }

    private func timeUntilOperatingDayCompletes() -> TimeInterval {
        guard lines.contains(where: \.isConstructed) else { return .infinity }
        return max(1 - operatingDayProgress, 0)
            * effectiveOperatingDayDuration
    }

    /// Returns true when this settlement newly bankrupts a Career company.
    private func settleOperatingDay() -> Bool {
        // Capture the projection being settled before station promotions recalculate the next
        // day's upkeep. History and presentation feedback must describe the cash flow just paid.
        let settledOperatingResultPence = economySnapshot.operatingResultPencePerDay
        var settledLedger = economyLedger
        settledLedger.operatingDayProgress = 0
        if settledLedger.completedOperatingDays < .max {
            settledLedger.completedOperatingDays += 1
        }
        settledLedger.lifetimeRevenuePence = saturatingAdd(
            settledLedger.lifetimeRevenuePence,
            max(economySnapshot.totalRevenuePencePerDay, 0)
        )
        settledLedger.lifetimeOperatingCostPence = saturatingAdd(
            settledLedger.lifetimeOperatingCostPence,
            max(economySnapshot.totalOperatingCostPencePerDay, 0)
        )
        economyLedger = settledLedger

        var updatedFinanceLedger = financeLedger
        let becameBankrupt = capitalEconomy.settleOperatingDay(
            operatingResultPence: settledOperatingResultPence,
            completedOperatingDay: economyLedger.completedOperatingDays,
            ledger: &updatedFinanceLedger
        )
        financeLedger = updatedFinanceLedger
        if becameBankrupt {
            isPlaying = false
            synchronizeClockSuspension()
        }

        let result = stationEvolution.applyOperatingDay(
            stationCRSs: networkStationCRSs,
            existingProgress: stationProgressByCRS,
            passengerSnapshot: passengerSnapshot
        )
        stationProgressByCRS = result.progressByStationCRS
        enqueueStationUpgradeEvents(for: result.promotedStationCRSs)
        let activeStationCRSs = activeNetworkStationCRSs
        let populationResult = settlementGrowth.applyOperatingDay(
            inputs: detailedSimulationStations.map { station in
                let localHappiness = happinessSnapshot(forStationCRS: station.crs)
                return SettlementGrowthInput(
                    stationCRS: station.crs,
                    isConnected: activeStationCRSs.contains(station.crs),
                    localHappinessScore: localHappiness?.happinessScore ?? 0,
                    reachableDestinationCount: localHappiness?.reachableDestinationCount ?? 0
                )
            },
            existingStatesByCRS: settlementPopulationByCRS
        )
        // An endpoint whose line is still under construction retains its baseline state for
        // persistence, but it cannot receive rail-led growth until the line opens.
        settlementPopulationByCRS = settlementGrowth.reconcile(
            connectedStationCRSs: networkStationCRSs,
            existingStatesByCRS: populationResult.statesByCRS
        )
        recalculatePassengerSnapshot()
        // Settlement changes both cash and station assets before the durable revision is bumped.
        // Clear the UI cache so the history record below captures the just-settled network.
        financeSnapshotCache = nil
        financeSnapshotCacheRevision = nil
        prestigeSnapshotCache = nil
        prestigeSnapshotCacheRevision = nil
        publicBetaHistory.record(
            PublicBetaDailyNetworkRecord(
                operatingDay: economyLedger.completedOperatingDays,
                facts: publicBetaFacts,
                operatingResultPence: settledOperatingResultPence,
                totalNetworkPopulation: networkPopulation,
                latestPopulationChange: latestNetworkPopulationChange
            )
        )
        emitPresentationEvent(
            .operatingDayCompleted(
                day: economyLedger.completedOperatingDays,
                operatingResultPence: settledOperatingResultPence
            )
        )
        markPersistenceChanged()
        return becameBankrupt
    }

    /// Lets deterministic tests wait for the currently active asynchronous route request.
    func waitForRouteCalculation() async {
        let task = routingTask
        await task?.value
    }

    /// Lets deterministic tests wait for the component-based station eligibility lookup.
    func waitForBuildStationEligibility() async {
        let task = buildStationEligibilityTask
        await task?.value
    }

    /// Lets deterministic tests await discovery or one paid station-addition transaction.
    func waitForLineStopUpdate() async {
        let task = lineStopsTask
        await task?.value
    }

    /// Lets deterministic tests and non-modal presentation wait for the current map proposal.
    func waitForMapStationAdditionProposal() async {
        let task = mapStationAdditionTask
        await task?.value
    }

    /// Returns the bounded presentation-event tail in emission order. The latest observable event
    /// wakes SwiftUI, while this buffer prevents synchronous bursts from being coalesced away.
    func presentationEvents(after sequence: UInt64) -> [GamePresentationEvent] {
        presentationEventBuffer.filter { $0.sequence > sequence }
    }

    private func beginRouteCalculation(from origin: Station, to destination: Station) {
        cancelPendingRoute()

        let requestID = UUID()
        routingRequestID = requestID
        preview = nil
        clearPreviewStationSelection()
        errorMessage = nil
        phase = .calculating

        let routingProvider = self.routingProvider
        let catalogStations = stations
        routingTask = Task { [weak self] in
            do {
                let route = try await routingProvider.route(
                    forStationCRSs: [origin.crs, destination.crs]
                )
                let intermediateMatches: [CorridorStationMatch]
                do {
                    intermediateMatches = try await routingProvider.discoverIntermediateStations(
                        on: route,
                        endpointCRSs: [origin.crs, destination.crs],
                        catalogStations: catalogStations
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // Station discovery enriches a valid route but must never make the established
                    // two-endpoint builder unavailable if optional catalogue matching fails.
                    intermediateMatches = []
                }
                guard !Task.isCancelled else { return }
                self?.completeRouteCalculation(
                    requestID: requestID,
                    origin: origin,
                    destination: destination,
                    route: route,
                    intermediateMatches: intermediateMatches
                )
            } catch is CancellationError {
                // Cancellation is an intentional transition; its caller owns the next phase.
            } catch {
                self?.failRouteCalculation(requestID: requestID, error: error)
            }
        }
    }

    private func completeRouteCalculation(
        requestID: UUID,
        origin: Station,
        destination: Station,
        route: ServiceRailwayRoute,
        intermediateMatches: [CorridorStationMatch]
    ) {
        guard routingRequestID == requestID else { return }

        routingTask = nil
        routingRequestID = nil

        guard isUsableServiceRoute(route, expectedStationCount: 2) else {
            presentError(
                "No usable railway route was found between those stations.",
                recoveringTo: .selectingDestination
            )
            return
        }

        let cost = indicativeCost(forDistance: route.totalLength)
        let initialEstimate = previewPassengerEstimate(
            origin: origin,
            destination: destination,
            route: route,
            stationCRSs: [origin.crs, destination.crs],
            railwayClass: .conventional,
            formation: .legacyBaseline
        )
        let recommendedFormation = recommendedFormation(
            for: initialEstimate,
            railwayClass: .conventional
        )
        let passengerEstimate = previewPassengerEstimate(
            origin: origin,
            destination: destination,
            route: route,
            stationCRSs: [origin.crs, destination.crs],
            railwayClass: .conventional,
            formation: recommendedFormation
        )
        preview = LinePreview(
            origin: origin,
            destination: destination,
            stationCRSs: [origin.crs, destination.crs],
            route: route,
            distanceMetres: route.totalLength,
            indicativeCost: cost,
            passengerEstimate: passengerEstimate,
            formation: recommendedFormation,
            recommendedFormation: recommendedFormation
        )
        previewIntermediateMatches = intermediateMatches
        previewIntermediateStations = intermediateMatches.map(\.station)
        previewSelectedStationCRSs = [origin.crs, destination.crs]
        isUpdatingPreviewRoute = false
        errorMessage = nil
        phase = .preview
    }

    private func beginPreviewRouteUpdate(
        for currentPreview: LinePreview,
        orderedStationCRSs: [String],
        targetRailwayClass: RailwayClass? = nil,
        targetFormation: RollingStockFormation? = nil
    ) {
        cancelPendingRoute()
        let requestID = UUID()
        routingRequestID = requestID
        isUpdatingPreviewRoute = true
        errorMessage = nil

        let routingProvider = self.routingProvider
        let resolvedRailwayClass = targetRailwayClass ?? currentPreview.railwayClass
        let resolvedFormation = targetFormation ?? currentPreview.formation
        routingTask = Task { [weak self] in
            do {
                let route = try await routingProvider.route(
                    forStationCRSs: orderedStationCRSs
                )
                guard !Task.isCancelled else { return }
                self?.completePreviewRouteUpdate(
                    requestID: requestID,
                    previewID: currentPreview.id,
                    orderedStationCRSs: orderedStationCRSs,
                    route: route,
                    railwayClass: resolvedRailwayClass,
                    formation: resolvedFormation
                )
            } catch is CancellationError {
                // A later station toggle owns the replacement request.
            } catch {
                self?.failPreviewRouteUpdate(requestID: requestID, error: error)
            }
        }
    }

    private func completePreviewRouteUpdate(
        requestID: UUID,
        previewID: UUID,
        orderedStationCRSs: [String],
        route: ServiceRailwayRoute,
        railwayClass: RailwayClass,
        formation: RollingStockFormation
    ) {
        guard routingRequestID == requestID,
              let currentPreview = preview,
              currentPreview.id == previewID else { return }
        routingTask = nil
        routingRequestID = nil
        isUpdatingPreviewRoute = false

        guard orderedStationCRSs.count <= maximumServiceCallCount,
              isUsableServiceRoute(
                  route,
                  expectedStationCount: orderedStationCRSs.count
              ),
              railwayClass != .highSpeed || orderedStationCRSs.count == 2 else {
            previewSelectedStationCRSs = currentPreview.stationCRSs
            presentError(
                "That station could not be added to a usable railway route.",
                recoveringTo: .preview
            )
            return
        }

        let passengerEstimate = previewPassengerEstimate(
            origin: currentPreview.origin,
            destination: currentPreview.destination,
            route: route,
            stationCRSs: orderedStationCRSs,
            railwayClass: railwayClass,
            formation: formation
        )
        preview = LinePreview(
            id: currentPreview.id,
            origin: currentPreview.origin,
            destination: currentPreview.destination,
            stationCRSs: orderedStationCRSs,
            route: route,
            distanceMetres: route.totalLength,
            indicativeCost: indicativeCost(forDistance: route.totalLength),
            passengerEstimate: passengerEstimate,
            railwayClass: railwayClass,
            formation: formation,
            recommendedFormation: recommendedFormation(
                for: passengerEstimate,
                railwayClass: railwayClass
            )
        )
        previewSelectedStationCRSs = orderedStationCRSs
        errorMessage = nil
    }

    private func failPreviewRouteUpdate(requestID: UUID, error: any Error) {
        guard routingRequestID == requestID else { return }
        routingTask = nil
        routingRequestID = nil
        isUpdatingPreviewRoute = false
        previewSelectedStationCRSs = preview?.stationCRSs ?? []
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        presentError(message, recoveringTo: .preview)
    }

    private func failRouteCalculation(requestID: UUID, error: any Error) {
        guard routingRequestID == requestID else { return }

        routingTask = nil
        routingRequestID = nil
        isUpdatingPreviewRoute = false
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        presentError(message, recoveringTo: .selectingDestination)
    }

    private func cancelPendingRoute() {
        routingRequestID = nil
        routingTask?.cancel()
        routingTask = nil
        isUpdatingPreviewRoute = false
        cancelBuildStationEligibility()
    }

    private func beginBuildStationEligibility(connectedTo origin: Station?) {
        cancelBuildStationEligibility()

        let requestID = UUID()
        buildStationEligibilityRequestID = requestID
        eligibleBuildStationCRSs = []
        isLoadingBuildStationEligibility = true
        hasResolvedBuildStationEligibility = false

        let routingProvider = self.routingProvider
        let candidateCRSs = Set(stations.map { StationEvolution.normalizedCRS($0.crs) })
        let originCRS = origin.map { StationEvolution.normalizedCRS($0.crs) }
        buildStationEligibilityTask = Task { [weak self] in
            do {
                let connected = try await routingProvider.directlyRoutableStationCRSs(
                    to: originCRS,
                    among: candidateCRSs
                )
                try Task.checkCancellation()
                self?.completeBuildStationEligibility(
                    requestID: requestID,
                    originCRS: originCRS,
                    connectedStationCRSs: connected,
                    candidateCRSs: candidateCRSs
                )
            } catch is CancellationError {
                // A later builder step owns the replacement eligibility request.
            } catch {
                self?.failBuildStationEligibility(
                    requestID: requestID,
                    originCRS: originCRS,
                    error: error
                )
            }
        }
    }

    private func completeBuildStationEligibility(
        requestID: UUID,
        originCRS: String?,
        connectedStationCRSs: Set<String>,
        candidateCRSs: Set<String>
    ) {
        guard buildStationEligibilityRequestID == requestID else { return }
        buildStationEligibilityTask = nil
        buildStationEligibilityRequestID = nil
        isLoadingBuildStationEligibility = false

        var eligible = Set(connectedStationCRSs.map(StationEvolution.normalizedCRS))
        eligible.formIntersection(candidateCRSs)
        if let originCRS {
            eligible.remove(originCRS)
            eligible = Set(eligible.filter { !hasLine(between: originCRS, and: $0) })
        }
        eligibleBuildStationCRSs = eligible
        hasResolvedBuildStationEligibility = true
    }

    private func failBuildStationEligibility(
        requestID: UUID,
        originCRS: String?,
        error: any Error
    ) {
        guard buildStationEligibilityRequestID == requestID else { return }
        buildStationEligibilityTask = nil
        buildStationEligibilityRequestID = nil
        eligibleBuildStationCRSs = []
        isLoadingBuildStationEligibility = false
        hasResolvedBuildStationEligibility = false
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        presentError(
            message,
            recoveringTo: originCRS == nil ? .selectingOrigin : .selectingDestination
        )
    }

    private func cancelBuildStationEligibility() {
        buildStationEligibilityRequestID = nil
        buildStationEligibilityTask?.cancel()
        buildStationEligibilityTask = nil
        eligibleBuildStationCRSs = []
        isLoadingBuildStationEligibility = false
        hasResolvedBuildStationEligibility = false
    }

    private func completeEditingStopsDiscovery(
        requestID: UUID,
        lineID: UUID,
        matches: [CorridorStationMatch]
    ) {
        guard lineStopsRequestID == requestID,
              editingStopsLineID == lineID,
              lines.contains(where: { $0.id == lineID }) else { return }
        lineStopsTask = nil
        lineStopsRequestID = nil
        editableIntermediateMatches = matches
        editableIntermediateStations = matches.map(\.station)
        isUpdatingLineStops = false
    }

    private func completeMapStationAdditionDiscovery(
        requestID: UUID,
        station: Station,
        results: [MapStationAdditionDiscoveryResult]
    ) {
        guard mapStationAdditionRequestID == requestID,
              phase == .operating,
              mapStationAdditionProposal?.station.crs == station.crs else { return }

        mapStationAdditionTask = nil
        mapStationAdditionRequestID = nil
        isLoadingMapStationAdditionProposal = false

        var options = [MapStationAdditionOption]()
        var pendingOptions = [UUID: PendingMapStationAdditionOption]()
        options.reserveCapacity(results.count)
        pendingOptions.reserveCapacity(results.count)

        for result in results {
            let sourceLine = result.input.line
            guard pendingOptions[sourceLine.id] == nil,
                  let currentLine = lines.first(where: { $0.id == sourceLine.id }),
                  lineIsCompatibleWithMapStationAdditionSnapshot(currentLine, sourceLine),
                  intermediateStationMatchIsValid(
                      result.match,
                      for: station,
                      on: currentLine
                  ),
                  let insertion = intermediateStationInsertionPlan(
                      for: station,
                      match: result.match,
                      line: currentLine
                  ),
                  let costPence = intermediateStationAdditionCostPence(
                      station,
                      toLineID: currentLine.id
                  ) else {
                continue
            }

            let resultingStationNames = insertion.serviceStationCRSs.map { crs in
                self.station(forNormalizedCRS: crs)?.name ?? crs
            }
            options.append(MapStationAdditionOption(
                lineID: currentLine.id,
                lineNumber: max(currentLine.styleIndex, 0) + 1,
                lineName: currentLine.name,
                resultingStationCRSs: insertion.serviceStationCRSs,
                resultingStationNames: resultingStationNames,
                costPence: costPence,
                isAffordable: canAffordIntermediateStation(
                    station,
                    toLineID: currentLine.id
                ),
                servicePattern: currentLine.servicePattern
            ))
            pendingOptions[currentLine.id] = PendingMapStationAdditionOption(
                sourceLine: sourceLine,
                match: result.match
            )
        }

        options.sort { lhs, rhs in
            if lhs.lineNumber != rhs.lineNumber { return lhs.lineNumber < rhs.lineNumber }
            return lhs.lineID.uuidString < rhs.lineID.uuidString
        }
        pendingMapStationAdditionOptions = pendingOptions
        mapStationAdditionProposal = MapStationAdditionProposal(
            station: station,
            options: options
        )
    }

    private func intermediateStationMatchIsValid(
        _ match: CorridorStationMatch,
        for station: Station,
        on line: BuiltLine
    ) -> Bool {
        let stationCRS = StationEvolution.normalizedCRS(station.crs)
        guard match.station == station,
              StationEvolution.normalizedCRS(match.station.crs) == stationCRS,
              !stationCRS.isEmpty,
              !line.stationCRSs.map(StationEvolution.normalizedCRS).contains(stationCRS),
              match.routeDistance.isFinite,
              match.routeProgress.isFinite,
              match.offsetFromRoute.isFinite,
              match.routeDistance > 0,
              match.routeDistance < line.corridorRoute.totalLength,
              (0...1).contains(match.routeProgress),
              match.offsetFromRoute >= 0,
              match.offsetFromRoute
                <= CorridorStationDiscoveryConfiguration.standard.maximumStationOffsetFromRoute,
              line.corridorRoute.coordinates.indices.contains(match.routeCoordinateIndex),
              line.corridorRoute.cumulativeDistances.count
                == line.corridorRoute.coordinates.count,
              line.corridorRoute.totalLength > 0 else {
            return false
        }

        let expectedProgress = match.routeDistance / line.corridorRoute.totalLength
        return abs(match.routeProgress - expectedProgress) <= 0.000_001
    }

    /// Train positions continue changing while a proposal is open, so they are intentionally not
    /// part of this comparison. All physical/service topology and timetable inputs that can make
    /// the retained match stale must remain exactly the same.
    private func lineIsCompatibleWithMapStationAdditionSnapshot(
        _ current: BuiltLine,
        _ snapshot: BuiltLine
    ) -> Bool {
        current.id == snapshot.id
            && current.corridorIDs == snapshot.corridorIDs
            && current.stationCRSs == snapshot.stationCRSs
            && current.corridorStationCRSs == snapshot.corridorStationCRSs
            && current.railwayClass == snapshot.railwayClass
            && current.isConstructed == snapshot.isConstructed
            && current.servicePattern == snapshot.servicePattern
            && current.serviceFrequency == snapshot.serviceFrequency
            && current.trainServicePlans == snapshot.trainServicePlans
            && routesAreExactlyEqual(current.route, snapshot.route)
            && routesAreExactlyEqual(current.corridorRoute, snapshot.corridorRoute)
    }

    private func routesAreExactlyEqual(
        _ lhs: ServiceRailwayRoute,
        _ rhs: ServiceRailwayRoute
    ) -> Bool {
        guard lhs.cumulativeDistances == rhs.cumulativeDistances,
              lhs.stationCoordinateIndices == rhs.stationCoordinateIndices,
              lhs.coordinates.count == rhs.coordinates.count else {
            return false
        }
        return zip(lhs.coordinates, rhs.coordinates).allSatisfy { lhs, rhs in
            lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
        }
    }

    private func intermediateStationAdditionQuote(
        _ station: Station,
        toLineID lineID: UUID
    ) -> CapitalPurchaseQuote? {
        guard let cost = intermediateStationAdditionCostPence(station, toLineID: lineID) else {
            return nil
        }
        return CapitalPurchaseQuote(
            trackAndInfrastructurePence: 0,
            stationConstructionPence: cost,
            rollingStockPence: 0
        )
    }

    private func intermediateStationInsertionPlan(
        for station: Station,
        match: CorridorStationMatch,
        line: BuiltLine
    ) -> IntermediateStationInsertionPlan? {
        guard line.isConstructed,
              line.railwayClass == .conventional,
              line.corridorIDs.count == 1,
              line.stationCRSs.count < maximumServiceCallCount,
              intermediateStationMatchIsValid(match, for: station, on: line) else {
            return nil
        }

        let stationCRS = StationEvolution.normalizedCRS(station.crs)
        guard let insertedCorridor = insertingCorridorStation(
            stationCRS,
            atRouteDistance: match.routeDistance,
            preferredCoordinateIndex: match.routeCoordinateIndex,
            into: line.corridorStationCRSs,
            route: line.corridorRoute
        ), isUsableServiceRoute(
            insertedCorridor.route,
            expectedStationCount: insertedCorridor.stationCRSs.count
        ), let orientedCorridor = corridorStationsOrientedForService(
            stationCRSs: insertedCorridor.stationCRSs,
            coordinateIndices: insertedCorridor.route.stationCoordinateIndices,
            originCRS: line.origin.crs,
            destinationCRS: line.destination.crs
        ) else {
            return nil
        }

        let selectedCallCRSs = Set(
            line.stationCRSs.map(StationEvolution.normalizedCRS) + [stationCRS]
        )
        let serviceCalls = orientedCorridor.stations.filter {
            selectedCallCRSs.contains($0.crs)
        }
        let serviceStationCRSs = serviceCalls.map(\.crs)
        let serviceStationCoordinateIndices = serviceCalls.map(\.coordinateIndex)
        guard serviceStationCRSs.count == selectedCallCRSs.count,
              serviceStationCRSs.count == line.stationCRSs.count + 1,
              serviceStationCRSs.first == StationEvolution.normalizedCRS(line.origin.crs),
              serviceStationCRSs.last == StationEvolution.normalizedCRS(line.destination.crs),
              serviceStationCRSs.count <= maximumServiceCallCount else {
            return nil
        }

        let updatedServiceRoute = serviceRoute(
            on: insertedCorridor.route,
            stationCoordinateIndices: serviceStationCoordinateIndices,
            isReversed: orientedCorridor.isReversed
        )
        guard isUsableServiceRoute(
            updatedServiceRoute,
            expectedStationCount: serviceStationCRSs.count
        ) else { return nil }

        return IntermediateStationInsertionPlan(
            corridorStationCRSs: insertedCorridor.stationCRSs,
            corridorRoute: insertedCorridor.route,
            serviceStationCRSs: serviceStationCRSs,
            serviceRoute: updatedServiceRoute
        )
    }

    private func insertingCorridorStation(
        _ stationCRS: String,
        atRouteDistance routeDistance: CLLocationDistance,
        preferredCoordinateIndex: Int,
        into stationCRSs: [String],
        route: ServiceRailwayRoute
    ) -> (stationCRSs: [String], route: ServiceRailwayRoute)? {
        let normalized = stationCRSs.map(StationEvolution.normalizedCRS)
        guard !stationCRS.isEmpty,
              normalized.count >= 2,
              isUsableServiceRoute(route, expectedStationCount: normalized.count) else {
            return nil
        }
        if normalized.contains(stationCRS) {
            return (normalized, route)
        }
        guard normalized.count < GameSaveSnapshot.maximumStationsPerCorridor,
              routeDistance.isFinite,
              routeDistance > 0,
              routeDistance < route.totalLength else {
            return nil
        }

        let tolerance: CLLocationDistance = 0.000_001
        let stationDistances = route.stationCoordinateIndices.map {
            route.cumulativeDistances[$0]
        }
        guard !stationDistances.contains(where: {
            abs($0 - routeDistance) <= tolerance
        }),
              let stationInsertionIndex = stationDistances.firstIndex(where: {
                  $0 > routeDistance
              }),
              stationInsertionIndex > 0,
              stationInsertionIndex < normalized.count else {
            return nil
        }

        var updatedCoordinates = route.coordinates
        var updatedCumulativeDistances = route.cumulativeDistances
        var updatedStationCoordinateIndices = route.stationCoordinateIndices
        let coordinateIndex: Int
        if route.cumulativeDistances.indices.contains(preferredCoordinateIndex),
           abs(route.cumulativeDistances[preferredCoordinateIndex] - routeDistance) <= tolerance {
            coordinateIndex = preferredCoordinateIndex
        } else if let matchingCoordinateIndex = route.cumulativeDistances.firstIndex(where: {
            abs($0 - routeDistance) <= tolerance
        }) {
            coordinateIndex = matchingCoordinateIndex
        } else {
            guard let upperCoordinateIndex = route.cumulativeDistances.firstIndex(where: {
                $0 > routeDistance
            }),
                  upperCoordinateIndex > 0,
                  let projectedCoordinate = route.sample(atDistance: routeDistance)?.coordinate else {
                return nil
            }
            updatedCoordinates.insert(projectedCoordinate, at: upperCoordinateIndex)
            updatedCumulativeDistances.insert(routeDistance, at: upperCoordinateIndex)
            updatedStationCoordinateIndices = updatedStationCoordinateIndices.map {
                $0 >= upperCoordinateIndex ? $0 + 1 : $0
            }
            coordinateIndex = upperCoordinateIndex
        }

        var updatedStationCRSs = normalized
        updatedStationCRSs.insert(stationCRS, at: stationInsertionIndex)
        updatedStationCoordinateIndices.insert(coordinateIndex, at: stationInsertionIndex)
        let updatedRoute = ServiceRailwayRoute(
            coordinates: updatedCoordinates,
            cumulativeDistances: updatedCumulativeDistances,
            stationCoordinateIndices: updatedStationCoordinateIndices
        )
        guard isUsableServiceRoute(
            updatedRoute,
            expectedStationCount: updatedStationCRSs.count
        ) else { return nil }
        return (updatedStationCRSs, updatedRoute)
    }

    private func corridorStationsOrientedForService(
        stationCRSs: [String],
        coordinateIndices: [Int],
        originCRS: String,
        destinationCRS: String
    ) -> (stations: [CorridorStationPosition], isReversed: Bool)? {
        guard stationCRSs.count == coordinateIndices.count else { return nil }
        let stations = zip(stationCRSs, coordinateIndices).map {
            CorridorStationPosition(
                crs: StationEvolution.normalizedCRS($0.0),
                coordinateIndex: $0.1
            )
        }
        let normalizedOrigin = StationEvolution.normalizedCRS(originCRS)
        let normalizedDestination = StationEvolution.normalizedCRS(destinationCRS)
        guard let originIndex = stations.firstIndex(where: { $0.crs == normalizedOrigin }),
              let destinationIndex = stations.firstIndex(where: {
                  $0.crs == normalizedDestination
              }),
              originIndex != destinationIndex else {
            return nil
        }
        if originIndex < destinationIndex {
            return (Array(stations[originIndex...destinationIndex]), false)
        }
        return (Array(stations[destinationIndex...originIndex].reversed()), true)
    }

    private func serviceCorridorDiscoverySpan(
        for line: BuiltLine
    ) -> (
        lowerDistance: CLLocationDistance,
        upperDistance: CLLocationDistance,
        isForward: Bool
    )? {
        guard isUsableServiceRoute(
            line.corridorRoute,
            expectedStationCount: line.corridorStationCRSs.count
        ), let orientedCorridor = corridorStationsOrientedForService(
            stationCRSs: line.corridorStationCRSs,
            coordinateIndices: line.corridorRoute.stationCoordinateIndices,
            originCRS: line.origin.crs,
            destinationCRS: line.destination.crs
        ), let originCoordinateIndex = orientedCorridor.stations.first?.coordinateIndex,
           let destinationCoordinateIndex = orientedCorridor.stations.last?.coordinateIndex,
           line.corridorRoute.cumulativeDistances.indices.contains(originCoordinateIndex),
           line.corridorRoute.cumulativeDistances.indices.contains(destinationCoordinateIndex)
        else { return nil }

        let originDistance = line.corridorRoute.cumulativeDistances[originCoordinateIndex]
        let destinationDistance = line.corridorRoute.cumulativeDistances[
            destinationCoordinateIndex
        ]
        guard originDistance.isFinite,
              destinationDistance.isFinite,
              originDistance != destinationDistance else { return nil }
        return (
            min(originDistance, destinationDistance),
            max(originDistance, destinationDistance),
            originDistance < destinationDistance
        )
    }

    private func serviceRoute(
        on corridorRoute: ServiceRailwayRoute,
        stationCoordinateIndices: [Int],
        isReversed: Bool
    ) -> ServiceRailwayRoute {
        guard let originCoordinateIndex = stationCoordinateIndices.first,
              let destinationCoordinateIndex = stationCoordinateIndices.last else {
            return ServiceRailwayRoute(
                coordinates: [],
                cumulativeDistances: [],
                stationCoordinateIndices: []
            )
        }
        if !isReversed {
            guard originCoordinateIndex >= 0,
                  destinationCoordinateIndex >= originCoordinateIndex,
                  corridorRoute.coordinates.indices.contains(originCoordinateIndex),
                  corridorRoute.coordinates.indices.contains(destinationCoordinateIndex),
                  corridorRoute.cumulativeDistances.indices.contains(originCoordinateIndex),
                  corridorRoute.cumulativeDistances.indices.contains(destinationCoordinateIndex)
            else {
                return ServiceRailwayRoute(
                    coordinates: [],
                    cumulativeDistances: [],
                    stationCoordinateIndices: []
                )
            }
            let originDistance = corridorRoute.cumulativeDistances[originCoordinateIndex]
            return ServiceRailwayRoute(
                coordinates: Array(
                    corridorRoute.coordinates[originCoordinateIndex...destinationCoordinateIndex]
                ),
                cumulativeDistances: corridorRoute.cumulativeDistances[
                    originCoordinateIndex...destinationCoordinateIndex
                ].map { $0 - originDistance },
                stationCoordinateIndices: stationCoordinateIndices.map {
                    $0 - originCoordinateIndex
                }
            )
        }

        guard destinationCoordinateIndex >= 0,
              originCoordinateIndex >= destinationCoordinateIndex,
              corridorRoute.coordinates.indices.contains(destinationCoordinateIndex),
              corridorRoute.coordinates.indices.contains(originCoordinateIndex),
              corridorRoute.cumulativeDistances.indices.contains(destinationCoordinateIndex),
              corridorRoute.cumulativeDistances.indices.contains(originCoordinateIndex) else {
            return ServiceRailwayRoute(
                coordinates: [],
                cumulativeDistances: [],
                stationCoordinateIndices: []
            )
        }
        let originDistance = corridorRoute.cumulativeDistances[originCoordinateIndex]
        return ServiceRailwayRoute(
            coordinates: Array(
                corridorRoute.coordinates[destinationCoordinateIndex...originCoordinateIndex].reversed()
            ),
            cumulativeDistances: corridorRoute.cumulativeDistances[
                destinationCoordinateIndex...originCoordinateIndex
            ].reversed().map {
                originDistance - $0
            },
            stationCoordinateIndices: stationCoordinateIndices.map {
                originCoordinateIndex - $0
            }
        )
    }

    private func routesHaveEquivalentGeometry(
        _ lhs: ServiceRailwayRoute,
        _ rhs: ServiceRailwayRoute
    ) -> Bool {
        let distanceTolerance: CLLocationDistance = 0.000_001
        let coordinateTolerance = 0.000_000_000_001
        guard abs(lhs.totalLength - rhs.totalLength) <= distanceTolerance else {
            return false
        }
        let sampleDistances = (lhs.cumulativeDistances + rhs.cumulativeDistances).filter {
            $0.isFinite && $0 >= 0 && $0 <= lhs.totalLength
        }
        for distance in sampleDistances {
            guard let lhsCoordinate = lhs.sample(atDistance: distance)?.coordinate,
                  let rhsCoordinate = rhs.sample(atDistance: distance)?.coordinate,
                  abs(lhsCoordinate.latitude - rhsCoordinate.latitude) <= coordinateTolerance,
                  abs(lhsCoordinate.longitude - rhsCoordinate.longitude) <= coordinateTolerance else {
                return false
            }
        }
        return true
    }

    /// Moves an existing fleet onto edited service geometry without moving trains between their
    /// retained station calls. This remains internal so focused integration tests can exercise
    /// legacy/custom geometry that the corridor-first restore path intentionally normalises.
    func remappingTrains(
        _ trains: [TrainState],
        from oldRoute: ServiceRailwayRoute,
        stationCRSs oldStationCRSs: [String],
        to newRoute: ServiceRailwayRoute,
        stationCRSs newStationCRSs: [String]
    ) -> [TrainState] {
        struct StationAnchor {
            let crs: String
            let oldDistance: CLLocationDistance
            let newDistance: CLLocationDistance
        }

        let normalizedOldCRSs = oldStationCRSs.map(StationEvolution.normalizedCRS)
        let normalizedNewCRSs = newStationCRSs.map(StationEvolution.normalizedCRS)
        let oldStationDistances = cumulativeStationDistances(
            for: oldRoute,
            expectedStationCount: normalizedOldCRSs.count
        )
        let newStationDistances = cumulativeStationDistances(
            for: newRoute,
            expectedStationCount: normalizedNewCRSs.count
        )
        var newDistanceByCRS = [String: CLLocationDistance]()
        if normalizedNewCRSs.count == newStationDistances.count,
           Set(normalizedNewCRSs).count == normalizedNewCRSs.count {
            for (crs, distance) in zip(normalizedNewCRSs, newStationDistances) {
                newDistanceByCRS[crs] = distance
            }
        }
        let anchors: [StationAnchor]
        if normalizedOldCRSs.count == oldStationDistances.count {
            anchors = zip(normalizedOldCRSs, oldStationDistances).compactMap { crs, distance in
                guard let newDistance = newDistanceByCRS[crs] else { return nil }
                return StationAnchor(
                    crs: crs,
                    oldDistance: distance,
                    newDistance: newDistance
                )
            }
        } else {
            anchors = []
        }
        let hasOrderedAnchors = anchors.count >= 2
            && zip(anchors, anchors.dropFirst()).allSatisfy {
                $0.oldDistance < $1.oldDistance && $0.newDistance < $1.newDistance
            }

        return trains.map { train in
            let oldDistance = train.distanceAlongRoute.isFinite
                ? min(max(train.distanceAlongRoute, 0), max(oldRoute.totalLength, 0))
                : 0
            let stationTolerance = max(oldRoute.totalLength * 0.000_000_001, 0.001)
            let dwellingAnchor = train.dwellRemaining > 0
                ? anchors.min(by: {
                    abs($0.oldDistance - oldDistance) < abs($1.oldDistance - oldDistance)
                })
                : nil
            let distance: CLLocationDistance
            if let dwellingAnchor,
               abs(dwellingAnchor.oldDistance - oldDistance) <= stationTolerance {
                // A dwelling train is physically at a call. Pin it to that same retained CRS,
                // rather than letting a percentage calculation place it between stations.
                distance = dwellingAnchor.newDistance
            } else if hasOrderedAnchors,
                      let upperIndex = anchors.firstIndex(where: {
                          $0.oldDistance >= oldDistance
                      }) {
                if upperIndex == 0 {
                    distance = anchors[0].newDistance
                } else {
                    let lower = anchors[upperIndex - 1]
                    let upper = anchors[upperIndex]
                    let legProgress = min(
                        max(
                            (oldDistance - lower.oldDistance)
                                / (upper.oldDistance - lower.oldDistance),
                            0
                        ),
                        1
                    )
                    distance = lower.newDistance
                        + (upper.newDistance - lower.newDistance) * legProgress
                }
            } else if hasOrderedAnchors, let lastAnchor = anchors.last {
                distance = lastAnchor.newDistance
            } else {
                let normalizedProgress = oldRoute.totalLength.isFinite
                    && oldRoute.totalLength > 0
                    ? min(max(oldDistance / oldRoute.totalLength, 0), 1)
                    : 0
                distance = newRoute.totalLength * normalizedProgress
            }
            let sample = newRoute.sample(atDistance: distance)
            let bearing = sample.map {
                normalisedBearing(
                    $0.bearing + (train.direction == .reverse ? 180 : 0)
                )
            } ?? train.bearing
            return TrainState(
                id: train.id,
                lineID: train.lineID,
                coordinate: sample?.coordinate ?? train.coordinate,
                bearing: bearing,
                distanceAlongRoute: distance,
                direction: train.direction,
                dwellRemaining: train.dwellRemaining
            )
        }
    }

    private func cancelLineStopsTask() {
        lineStopsRequestID = nil
        lineStopsTask?.cancel()
        lineStopsTask = nil
        isUpdatingLineStops = false
    }

    private func indicativeCost(forDistance distanceMetres: CLLocationDistance) -> Int64 {
        let rawCost = max(distanceMetres, 0) / 1_000
            * Double(max(configuration.indicativeCostPerKilometre, 0))
        guard rawCost.isFinite else { return Int64.max }
        let roundedCost = rawCost.rounded()
        guard roundedCost < Double(Int64.max) else { return .max }
        return Int64(roundedCost)
    }

    private func capitalQuote(for preview: LinePreview) -> CapitalPurchaseQuote {
        return capitalEconomy.quoteForNewLine(
            constructionCostPounds: preview.indicativeCost,
            originCRS: preview.origin.crs,
            destinationCRS: preview.destination.crs,
            stationCRSs: preview.stationCRSs,
            existingStationCRSs: Set(networkStationCRSs),
            initialTrainCount: ServiceFrequency.halfHourly.visibleTrainCount,
            initialFormation: preview.formation,
            railwayClass: preview.railwayClass,
            existingPremiumStationCRSs: premiumHighSpeedStationCRSs
        )
    }

    private func previewPassengerEstimate(
        origin: Station,
        destination: Station,
        route: ServiceRailwayRoute,
        stationCRSs: [String],
        railwayClass: RailwayClass,
        formation: RollingStockFormation
    ) -> PassengerDemandEstimate {
        let servicePattern: ServicePattern = railwayClass == .highSpeed ? .express : .balanced
        let planning = automaticPlanningResult(
            servicePattern: servicePattern,
            stationCRSs: stationCRSs,
            route: route,
            railwayClass: railwayClass
        )
        let initialTrainCount = ServiceFrequency.halfHourly.visibleTrainCount
        let activePlans = (0..<max(initialTrainCount, 0)).compactMap { slotIndex in
            planning.representativePlans.first { $0.slotIndex == slotIndex }
        }
        let operations = trainOperations.evaluate(
            LineOperationsInput(
                frequency: .halfHourly,
                servicePattern: servicePattern,
                trackCapacity: railwayClass == .highSpeed ? .doubleTrack : .singleTrack,
                railwayClass: railwayClass,
                serviceRoles: activePlans.map(\.role)
            )
        )
        let serviceRuns = passengerServiceRuns(
            stationCRSs: stationCRSs,
            route: route,
            logicalRuns: logicalServiceRuns(
                planning: planning,
                stationCRSs: stationCRSs,
                activePlans: activePlans
            )
        )
        let input = PassengerLineInput(
            id: UUID(),
            originCRS: origin.crs,
            destinationCRS: destination.crs,
            distanceKilometres: route.totalLength / 1_000,
            stationCRSs: stationCRSs,
            cumulativeStationDistancesKilometres: cumulativeStationDistances(
                for: route,
                expectedStationCount: stationCRSs.count
            ).map { $0 / 1_000 },
            frequency: .halfHourly,
            servicePattern: servicePattern,
            journeyTimeMultiplier: operations.journeyTimeMultiplier,
            reliability: operations.reliability,
            capacityPerTrain: formation.seatsPerTrain,
            serviceRuns: serviceRuns
        )
        guard let snapshot = passengerSimulation.evaluate(
            [input],
            stationPopulationMultipliers: stationPopulationDemandMultipliers
        ).line(for: input.id) else { return .zero }
        return PassengerDemandEstimate(
            potentialDailyJourneys: snapshot.potentialDailyJourneys,
            attractedDailyJourneys: snapshot.attractedDailyJourneys,
            passengersPerDay: snapshot.passengersPerDay,
            dailyCapacity: snapshot.dailyCapacity,
            journeyMinutes: snapshot.journeyMinutes,
            averageWaitMinutes: snapshot.averageWaitMinutes,
            demandServedRatio: snapshot.demandServedRatio,
            demandCapturedRatio: snapshot.demandCapturedRatio,
            peakOccupancyRatio: snapshot.peakOccupancyRatio,
            capacityPressure: snapshot.capacityPressure,
            feedback: snapshot.feedback
        )
    }

    private func recommendedFormation(
        for estimate: PassengerDemandEstimate,
        railwayClass: RailwayClass
    ) -> RollingStockFormation {
        let rawPeakShare = passengerSimulation.configuration.peakDemandShare
        let peakShare = rawPeakShare.isFinite
            ? min(max(rawPeakShare, 0), 1)
            : 0
        let rawPeakDemand = Double(max(estimate.attractedDailyJourneys, 0)) * peakShare
        let attractedPeakDemand: Int
        if !rawPeakDemand.isFinite || rawPeakDemand >= Double(Int.max) {
            attractedPeakDemand = .max
        } else {
            attractedPeakDemand = max(Int(rawPeakDemand.rounded()), 0)
        }

        let rawPeakHours = passengerSimulation.configuration.peakHoursPerDay
        let rawOperatingHours = passengerSimulation.configuration.operatingHoursPerDay
        let operatingHours = rawOperatingHours.isFinite ? max(rawOperatingHours, 0) : 0
        let peakHours = rawPeakHours.isFinite
            ? min(max(rawPeakHours, 0), operatingHours)
            : 0
        let rawDepartures = Double(ServiceFrequency.halfHourly.departuresPerHour * 2)
            * peakHours
        let departuresDuringPeak: Int
        if !rawDepartures.isFinite || rawDepartures >= Double(Int.max) {
            departuresDuringPeak = .max
        } else {
            departuresDuringPeak = max(Int(rawDepartures.rounded()), 0)
        }

        return RollingStockFormationPolicy().recommend(
            attractedPeakDemand: attractedPeakDemand,
            departuresDuringPeak: departuresDuringPeak,
            railwayClass: railwayClass
        )
    }

    private func formattedPenceForMessage(_ pence: Int64) -> String {
        (Double(pence) / 100).formatted(
            .currency(code: "GBP")
                .notation(.compactName)
                .precision(.fractionLength(0))
        )
    }

    private func advanceTrain(
        _ train: inout TrainState,
        on route: ServiceRailwayRoute,
        planTopology: TrainMovementPlanTopology,
        elapsed: TimeInterval,
        operations: LineOperationsSnapshot
    ) -> TrainArrivalBatch {
        var arrivals = TrainArrivalBatch()
        let routeLength = route.totalLength
        guard let lowerCall = planTopology.lowerCall,
              let upperCall = planTopology.upperCall else {
            updateTrainPosition(&train, on: route)
            return arrivals
        }
        let lowerBound = lowerCall.distance
        let upperBound = upperCall.distance
        let operatingDistance = upperBound - lowerBound
        let speed = effectiveTrainSpeed(for: operatingDistance) * trainOperations.speedMultiplier(
            for: planTopology.role,
            pattern: operations.servicePattern,
            trackCapacity: operations.trackCapacity,
            congestionRatio: operations.congestionRatio,
            railwayClass: operations.railwayClass
        )
        guard routeLength.isFinite, routeLength > 0,
              operatingDistance.isFinite, operatingDistance > 0,
              speed.isFinite, speed > 0 else {
            updateTrainPosition(&train, on: route)
            return arrivals
        }

        let dwellDuration = max(configuration.terminalDwellDuration, 0)
        let operationalDwellDuration = max(
            trainOperations.configuration.localIntermediateDwellDuration,
            0
        )
        let epsilon = max(routeLength * 0.000_000_001, 0.001)
        train.distanceAlongRoute = min(max(train.distanceAlongRoute, lowerBound), upperBound)
        if train.distanceAlongRoute <= lowerBound + epsilon, train.direction == .reverse {
            train.direction = .forward
        } else if train.distanceAlongRoute >= upperBound - epsilon,
                  train.direction == .forward {
            train.direction = .reverse
        }
        var remainingTime = elapsed

        while remainingTime > 0 {
            if train.dwellRemaining > 0 {
                let dwellElapsed = min(remainingTime, train.dwellRemaining)
                train.dwellRemaining -= dwellElapsed
                remainingTime -= dwellElapsed
                if remainingTime <= 0 { break }
            }

            let nextStop = nextOperationalStop(
                for: train,
                stops: planTopology.intermediateStops,
                routeLength: routeLength
            )
            let targetDistance: CLLocationDistance
            switch train.direction {
            case .forward:
                targetDistance = nextStop?.distance ?? upperBound
            case .reverse:
                targetDistance = nextStop?.distance ?? lowerBound
            }
            let remainingDistance = abs(targetDistance - train.distanceAlongRoute)
            let timeToTarget = remainingDistance / speed
            if remainingTime < timeToTarget {
                let travelled = remainingTime * speed
                train.distanceAlongRoute += train.direction == .forward ? travelled : -travelled
                remainingTime = 0
                continue
            }

            train.distanceAlongRoute = targetDistance
            remainingTime -= timeToTarget
            if let nextStop {
                if let stationIndex = nextStop.stationIndex {
                    arrivals.record(stationIndex: stationIndex)
                }
                train.dwellRemaining = operationalDwellDuration
                continue
            }

            arrivals.record(
                stationIndex: train.direction == .forward
                    ? upperCall.stationIndex
                    : lowerCall.stationIndex
            )
            switch train.direction {
            case .forward:
                train.direction = .reverse
            case .reverse:
                train.direction = .forward
            }
            train.dwellRemaining = dwellDuration
        }

        train.distanceAlongRoute = min(
            max(train.distanceAlongRoute, lowerBound),
            upperBound
        )
        updateTrainPosition(&train, on: route)
        return arrivals
    }

    private func recordTrainArrivals(
        _ arrivals: TrainArrivalBatch,
        for train: TrainState,
        on line: BuiltLine
    ) {
        guard arrivals.count > 0 else { return }

        var arrivalOrdinal = arrivalOrdinalsByTrainID[train.id] ?? 0
        let emittedCount = min(
            arrivals.stationIndices.count,
            max(trainArrivalPresentationEventsRemaining, 0)
        )
        let intermediateDeparturesPerHour: Int = switch line.servicePattern {
        case .local:
            line.serviceFrequency.departuresPerHour
        case .express:
            0
        case .balanced:
            (line.serviceFrequency.visibleTrainCount + 1) / 2
        }
        let dailyRevenue = economySnapshot(forLineID: line.id)?.revenuePencePerDay ?? 0
        let fareRevenuePence: Int64
        if hasCustomServicePlans(forLineID: line.id) {
            let activeCallsPerHour = line.trains.indices.reduce(0) { total, slotIndex in
                total + max(line.servicePlan(forSlot: slotIndex)?.stationCRSs.count ?? 0, 0)
            }
            let arrivalsPerDay = max(
                Int64(activeCallsPerHour)
                    * max(operatingEconomy.configuration.serviceHoursPerDay, 0)
                    * max(operatingEconomy.configuration.directionCount, 0),
                1
            )
            fareRevenuePence = max(dailyRevenue / arrivalsPerDay, 0)
        } else {
            fareRevenuePence = TrainJourneyPresentation
                .fareRevenuePencePerStationArrival(
                    dailyRevenuePence: dailyRevenue,
                    endpointDeparturesPerHour: line.serviceFrequency.departuresPerHour,
                    intermediateDeparturesPerHour: intermediateDeparturesPerHour,
                    intermediateStationCount: max(line.stationCRSs.count - 2, 0),
                    serviceHoursPerDay: operatingEconomy.configuration.serviceHoursPerDay,
                    directionCount: operatingEconomy.configuration.directionCount
                )
        }

        for arrivalIndex in 0..<emittedCount {
            arrivalOrdinal = saturatingAdd(arrivalOrdinal, 1)
            let stationIndex = arrivals.stationIndices[arrivalIndex]
            guard line.stationCRSs.indices.contains(stationIndex) else {
                continue
            }
            let stationCRS = line.stationCRSs[stationIndex]
            emitPresentationEvent(
                .trainArrived(
                    lineID: line.id,
                    trainID: train.id,
                    stationCRS: stationCRS,
                    fareRevenuePence: fareRevenuePence,
                    soundsHorn: TrainJourneyPresentation.shouldSoundHorn(
                        trainID: train.id,
                        arrivalOrdinal: arrivalOrdinal
                    )
                )
            )
        }
        trainArrivalPresentationEventsRemaining -= emittedCount

        let suppressedCount = arrivals.count - emittedCount
        if suppressedCount > 0 {
            arrivalOrdinal = saturatingAdd(arrivalOrdinal, UInt64(suppressedCount))
        }
        arrivalOrdinalsByTrainID[train.id] = arrivalOrdinal
    }

    private func stationIndex(
        atDistance distance: CLLocationDistance,
        in stationDistances: [CLLocationDistance],
        routeLength: CLLocationDistance
    ) -> Int? {
        let epsilon = max(routeLength * 0.000_000_001, 0.001)
        guard stationDistances.count > 2 else { return nil }
        return stationDistances.indices.dropFirst().dropLast().first {
            abs(stationDistances[$0] - distance) <= epsilon
        }
    }

    private func saturatingAdd(_ value: UInt64, _ increment: UInt64) -> UInt64 {
        let (result, overflow) = value.addingReportingOverflow(increment)
        return overflow ? .max : result
    }

    private func nextOperationalStop(
        for train: TrainState,
        stops: [TrainMovementPlanTopology.Stop],
        routeLength: CLLocationDistance
    ) -> TrainMovementPlanTopology.Stop? {
        guard !stops.isEmpty else { return nil }
        let epsilon = max(routeLength * 0.000_000_001, 0.001)
        switch train.direction {
        case .forward:
            let threshold = train.distanceAlongRoute + epsilon
            var lower = 0
            var upper = stops.count
            while lower < upper {
                let middle = (lower + upper) / 2
                if stops[middle].distance <= threshold {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }
            return stops.indices.contains(lower) ? stops[lower] : nil
        case .reverse:
            let threshold = train.distanceAlongRoute - epsilon
            var lower = 0
            var upper = stops.count
            while lower < upper {
                let middle = (lower + upper) / 2
                if stops[middle].distance < threshold {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }
            let index = lower - 1
            return stops.indices.contains(index) ? stops[index] : nil
        }
    }

    private func updateTrainPosition(
        _ train: inout TrainState,
        on route: ServiceRailwayRoute
    ) {
        guard let sample = route.sample(atDistance: train.distanceAlongRoute) else {
            return
        }

        train.coordinate = sample.coordinate
        train.bearing = normalisedBearing(
            sample.bearing + (train.direction == .reverse ? 180 : 0)
        )
    }

    private func hasLine(between firstCRS: String, and secondCRS: String) -> Bool {
        let first = firstCRS.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let second = secondCRS.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return lines.contains { line in
            (line.origin.crs == first && line.destination.crs == second)
                || (line.origin.crs == second && line.destination.crs == first)
        }
    }

    private func throughServiceMergePlan(
        primary: BuiltLine,
        candidate: BuiltLine
    ) -> ThroughServiceMergePlan? {
        guard primary.id != candidate.id,
              primary.isConstructed,
              candidate.isConstructed,
              primary.railwayClass == .conventional,
              candidate.railwayClass == .conventional,
              !primary.corridorIDs.isEmpty,
              !candidate.corridorIDs.isEmpty,
              Set(primary.corridorIDs).count == primary.corridorIDs.count,
              Set(candidate.corridorIDs).count == candidate.corridorIDs.count,
              Set(primary.corridorIDs).isDisjoint(with: Set(candidate.corridorIDs)) else {
            return nil
        }

        let corridorCountResult = primary.corridorIDs.count.addingReportingOverflow(
            candidate.corridorIDs.count
        )
        guard !corridorCountResult.overflow,
              corridorCountResult.partialValue <= GameSaveSnapshot.maximumCorridorCount else {
            return nil
        }

        let targetFormation = primary.formation.carriageCount >= candidate.formation.carriageCount
            ? primary.formation
            : candidate.formation
        let targetTrackCapacity = strongerTrackCapacity(
            primary.trackCapacity,
            candidate.trackCapacity
        )

        let normalizedPrimaryStations = primary.stationCRSs.map(StationEvolution.normalizedCRS)
        let normalizedCandidateStations = candidate.stationCRSs.map(StationEvolution.normalizedCRS)
        guard let primaryFirst = normalizedPrimaryStations.first,
              let primaryLast = normalizedPrimaryStations.last,
              let candidateFirst = normalizedCandidateStations.first,
              let candidateLast = normalizedCandidateStations.last else { return nil }
        let primaryEndpoints = [primaryFirst, primaryLast]
        let candidateEndpoints = [candidateFirst, candidateLast]
        let sharedEndpoints = Set(primaryEndpoints).intersection(candidateEndpoints)
        guard sharedEndpoints.count == 1,
              let junctionCRS = sharedEndpoints.first,
              Set(normalizedPrimaryStations).intersection(normalizedCandidateStations)
                == Set([junctionCRS]),
              let originCRS = primaryEndpoints.first(where: { $0 != junctionCRS }),
              let destinationCRS = candidateEndpoints.first(where: { $0 != junctionCRS }),
              originCRS != destinationCRS,
              let primaryCalls = orientedStationCRSs(
                  primary.stationCRSs,
                  from: originCRS,
                  to: junctionCRS
              ),
              let candidateCalls = orientedStationCRSs(
                  candidate.stationCRSs,
                  from: junctionCRS,
                  to: destinationCRS
              ) else { return nil }

        let stationCRSs = primaryCalls + candidateCalls.dropFirst()
        guard stationCRSs.count <= maximumServiceCallCount,
              stationCRSs.count <= GameSaveSnapshot.maximumStationsPerCorridor,
              Set(stationCRSs).count == stationCRSs.count else { return nil }

        let ownedTrainCountResult = primary.ownedTrainCount.addingReportingOverflow(
            candidate.ownedTrainCount
        )
        guard !ownedTrainCountResult.overflow,
              ownedTrainCountResult.partialValue >= primary.serviceFrequency.visibleTrainCount,
              ownedTrainCountResult.partialValue
                <= GameSaveSnapshot.maximumOwnedTrainCountPerService else { return nil }

        let duplicateOuterService = lines.contains { line in
            guard line.id != primary.id, line.id != candidate.id else { return false }
            let endpoints = Set([
                StationEvolution.normalizedCRS(line.origin.crs),
                StationEvolution.normalizedCRS(line.destination.crs),
            ])
            return endpoints == Set([originCRS, destinationCRS])
        }
        guard !duplicateOuterService else { return nil }

        // Assemble against the post-purchase infrastructure without mutating the player's live
        // assets. A source service's whole corridor group may need reversing before the groups are
        // concatenated; reversing only the first physical corridor is insufficient at an origin
        // extension. Confirmation repeats this calculation before committing anything.
        guard let primaryChain = orientedServiceCorridorChain(
            for: primary,
            from: originCRS,
            to: junctionCRS,
            targetTrackCapacity: targetTrackCapacity
        ), let candidateChain = orientedServiceCorridorChain(
            for: candidate,
            from: junctionCRS,
            to: destinationCRS,
            targetTrackCapacity: targetTrackCapacity
        ) else { return nil }
        let plannedCorridors = primaryChain.corridors + candidateChain.corridors
        let assemblies = RailwayCorridorChainAssembler.assemblies(
            for: plannedCorridors
        )
        guard let assembly = assemblies.first(where: {
            $0.stationCRSs.first == originCRS && $0.stationCRSs.last == destinationCRS
        }),
              assembly.corridorIDs.count == corridorCountResult.partialValue,
              let physicalCallIndices = orderedSubsequenceIndices(
                  stationCRSs,
                  in: assembly.stationCRSs
              ) else { return nil }
        let serviceCoordinateIndices = physicalCallIndices.map {
            assembly.route.stationCoordinateIndices[$0]
        }
        let serviceRoute = serviceRoute(
            on: assembly.route,
            stationCoordinateIndices: serviceCoordinateIndices,
            isReversed: false
        )
        guard isUsableServiceRoute(serviceRoute, expectedStationCount: stationCRSs.count),
              let origin = station(forNormalizedCRS: originCRS),
              let junction = station(forNormalizedCRS: junctionCRS),
              let destination = station(forNormalizedCRS: destinationCRS) else { return nil }
        let stationNames = stationCRSs.compactMap {
            station(forNormalizedCRS: $0)?.name
        }
        guard stationNames.count == stationCRSs.count else { return nil }

        let primaryFormationUpgradeCost = formationUpgradeCostPence(
            ownedTrainCount: primary.ownedTrainCount,
            from: primary.formation,
            to: targetFormation,
            railwayClass: primary.railwayClass
        )
        let candidateFormationUpgradeCost = formationUpgradeCostPence(
            ownedTrainCount: candidate.ownedTrainCount,
            from: candidate.formation,
            to: targetFormation,
            railwayClass: candidate.railwayClass
        )
        guard let primaryFormationUpgradeCost,
              let candidateFormationUpgradeCost else { return nil }

        let primaryLineNumber = max(primary.styleIndex, 0) + 1
        let candidateLineNumber = max(candidate.styleIndex, 0) + 1
        var automaticChanges = [ThroughServiceAutomaticChange]()
        if candidate.serviceFrequency != primary.serviceFrequency {
            automaticChanges.append(.serviceFrequency(
                lineID: candidate.id,
                lineNumber: candidateLineNumber,
                from: candidate.serviceFrequency,
                to: primary.serviceFrequency
            ))
        }
        if candidate.servicePattern != primary.servicePattern {
            automaticChanges.append(.servicePattern(
                lineID: candidate.id,
                lineNumber: candidateLineNumber,
                from: candidate.servicePattern,
                to: primary.servicePattern
            ))
        }
        if primary.formation != targetFormation {
            automaticChanges.append(.formation(
                lineID: primary.id,
                lineNumber: primaryLineNumber,
                ownedTrainCount: primary.ownedTrainCount,
                from: primary.formation,
                to: targetFormation,
                costPence: primaryFormationUpgradeCost
            ))
        }
        if candidate.formation != targetFormation {
            automaticChanges.append(.formation(
                lineID: candidate.id,
                lineNumber: candidateLineNumber,
                ownedTrainCount: candidate.ownedTrainCount,
                from: candidate.formation,
                to: targetFormation,
                costPence: candidateFormationUpgradeCost
            ))
        }
        var trackUpgradeCost: Int64 = 0
        for (line, lineNumber, chain) in [
            (primary, primaryLineNumber, primaryChain),
            (candidate, candidateLineNumber, candidateChain),
        ] {
            for plannedCorridor in chain.corridors {
                guard let corridor = corridors.first(where: { $0.id == plannedCorridor.id }),
                      let cost = trackUpgradeCostPence(
                          from: corridor.trackCapacity,
                          to: targetTrackCapacity,
                          constructionCostPounds: corridor.indicativeCost
                      ) else { return nil }
                trackUpgradeCost = EconomyArithmetic.add(trackUpgradeCost, cost)
                if corridor.trackCapacity != targetTrackCapacity {
                    automaticChanges.append(.trackCapacity(
                        lineID: line.id,
                        lineNumber: lineNumber,
                        corridorID: corridor.id,
                        segmentName: corridorSegmentName(corridor),
                        from: corridor.trackCapacity,
                        to: targetTrackCapacity,
                        costPence: cost
                    ))
                }
            }
        }
        let capitalQuote = CapitalPurchaseQuote(
            trackAndInfrastructurePence: trackUpgradeCost,
            stationConstructionPence: 0,
            rollingStockPence: EconomyArithmetic.add(
                primaryFormationUpgradeCost,
                candidateFormationUpgradeCost
            )
        )

        let option = ThroughServiceOption(
            primaryLineID: primary.id,
            candidateLineID: candidate.id,
            primaryLineNumber: primaryLineNumber,
            candidateLineNumber: candidateLineNumber,
            primaryCorridorCount: primary.corridorIDs.count,
            candidateCorridorCount: candidate.corridorIDs.count,
            resultingCorridorCount: assembly.corridorIDs.count,
            originCRS: originCRS,
            originName: origin.name,
            junctionCRS: junctionCRS,
            junctionName: junction.name,
            destinationCRS: destinationCRS,
            destinationName: destination.name,
            stationCRSs: stationCRSs,
            stationNames: stationNames,
            primaryOwnedTrainCount: primary.ownedTrainCount,
            candidateOwnedTrainCount: candidate.ownedTrainCount,
            resultingOwnedTrainCount: ownedTrainCountResult.partialValue,
            activeTrainCount: primary.trains.count,
            primaryFrequency: primary.serviceFrequency,
            candidateFrequency: candidate.serviceFrequency,
            primaryServicePattern: primary.servicePattern,
            candidateServicePattern: candidate.servicePattern,
            primaryFormation: primary.formation,
            candidateFormation: candidate.formation,
            primaryTrackCapacity: primary.trackCapacity,
            candidateTrackCapacity: candidate.trackCapacity,
            frequency: primary.serviceFrequency,
            servicePattern: primary.servicePattern,
            formation: targetFormation,
            trackCapacity: targetTrackCapacity,
            preservesPrimaryCustomServicePlans: usesCustomServicePlans(primary),
            automaticChanges: automaticChanges,
            capitalQuote: capitalQuote,
            canAfford: capitalEconomy.canAfford(capitalQuote, ledger: financeLedger),
            fundingShortfallPence: capitalEconomy.fundingShortfall(
                for: capitalQuote.totalPence,
                ledger: financeLedger
            )
        )
        let preservesPrimaryCustomServicePlans = usesCustomServicePlans(primary)
        let trainServicePlans = preservesPrimaryCustomServicePlans
            ? primary.trainServicePlans
            : defaultServicePlans(
                servicePattern: primary.servicePattern,
                stationCRSs: stationCRSs,
                route: serviceRoute,
                railwayClass: primary.railwayClass
            )
        return ThroughServiceMergePlan(
            option: option,
            assembly: assembly,
            serviceRoute: serviceRoute,
            primaryStationCRSs: primaryCalls,
            primaryIsReversed: normalizedPrimaryStations != primaryCalls,
            trainServicePlans: trainServicePlans
        )
    }

    /// Resolves one existing service as a whole physical corridor group in the requested
    /// direction. The stored corridor order is tried both forwards and backwards; within either
    /// order the chain assembler handles each corridor's own geometry orientation.
    private func orientedServiceCorridorChain(
        for line: BuiltLine,
        from originCRS: String,
        to destinationCRS: String,
        targetTrackCapacity: TrackCapacity
    ) -> OrientedServiceCorridorChain? {
        let storedCorridors = line.corridorIDs.compactMap { corridorID in
            corridors.first(where: { $0.id == corridorID })
        }
        guard !storedCorridors.isEmpty,
              storedCorridors.count == line.corridorIDs.count,
              Set(storedCorridors.map(\.id)).count == storedCorridors.count,
              storedCorridors.allSatisfy({
                  $0.isConstructed
                      && $0.railwayClass == .conventional
                      && $0.railwayClass == line.railwayClass
                      && $0.trackCapacity == line.trackCapacity
              }),
              let serviceCalls = orientedStationCRSs(
                  line.stationCRSs,
                  from: originCRS,
                  to: destinationCRS
              ) else { return nil }

        let orders = storedCorridors.count == 1
            ? [storedCorridors]
            : [storedCorridors, Array(storedCorridors.reversed())]
        for originalOrder in orders {
            let plannedOrder = originalOrder.map { corridor -> RailwayCorridor in
                var upgraded = corridor
                upgraded.trackCapacity = targetTrackCapacity
                return upgraded
            }
            if RailwayCorridorChainAssembler.assemblies(
                for: plannedOrder
            ).first(where: { assembly in
                assembly.stationCRSs.first == originCRS
                    && assembly.stationCRSs.last == destinationCRS
                    && orderedSubsequenceIndices(
                        serviceCalls,
                        in: assembly.stationCRSs
                    ) != nil
            }) != nil {
                return OrientedServiceCorridorChain(
                    corridors: plannedOrder
                )
            }
        }
        return nil
    }

    private func corridorSegmentName(_ corridor: RailwayCorridor) -> String {
        guard let firstCRS = corridor.stationCRSs.first,
              let lastCRS = corridor.stationCRSs.last else { return "Railway segment" }
        let firstName = station(forNormalizedCRS: StationEvolution.normalizedCRS(firstCRS))?.name
            ?? firstCRS
        let lastName = station(forNormalizedCRS: StationEvolution.normalizedCRS(lastCRS))?.name
            ?? lastCRS
        return "\(firstName) – \(lastName)"
    }

    private func strongerTrackCapacity(
        _ lhs: TrackCapacity,
        _ rhs: TrackCapacity
    ) -> TrackCapacity {
        trackCapacityRank(lhs) >= trackCapacityRank(rhs) ? lhs : rhs
    }

    private func trackCapacityRank(_ capacity: TrackCapacity) -> Int {
        switch capacity {
        case .singleTrack: 0
        case .passingLoop: 1
        case .doubleTrack: 2
        }
    }

    /// Uses the same two-car extension quotes as the standalone rolling-stock control, repeating
    /// them when a fleet must move through more than one supported formation step.
    private func formationUpgradeCostPence(
        ownedTrainCount: Int,
        from currentFormation: RollingStockFormation,
        to targetFormation: RollingStockFormation,
        railwayClass: RailwayClass
    ) -> Int64? {
        guard currentFormation.carriageCount <= targetFormation.carriageCount else { return nil }
        var formation = currentFormation
        var total: Int64 = 0
        while formation != targetFormation {
            guard let quote = capitalEconomy.quoteForFormationExtension(
                ownedTrainCount: ownedTrainCount,
                currentFormation: formation,
                railwayClass: railwayClass
            ),
            quote.upgradedFormation.carriageCount <= targetFormation.carriageCount else {
                return nil
            }
            total = EconomyArithmetic.add(total, quote.totalCostPence)
            formation = quote.upgradedFormation
        }
        return total
    }

    /// Sums every existing ladder step, so single track upgraded to double track costs exactly the
    /// same as buying a passing loop and then double track through the normal controls.
    private func trackUpgradeCostPence(
        from currentCapacity: TrackCapacity,
        to targetCapacity: TrackCapacity,
        constructionCostPounds: Int64
    ) -> Int64? {
        guard trackCapacityRank(currentCapacity) <= trackCapacityRank(targetCapacity) else {
            return nil
        }
        var capacity = currentCapacity
        var total: Int64 = 0
        while capacity != targetCapacity {
            guard let next = capacity.next,
                  let cost = trainOperations.upgradeCostPence(
                      from: capacity,
                      constructionCostPounds: constructionCostPounds
                  ),
                  trackCapacityRank(next) <= trackCapacityRank(targetCapacity) else {
                return nil
            }
            total = EconomyArithmetic.add(total, cost)
            capacity = next
        }
        return total
    }

    private func orientedStationCRSs(
        _ stationCRSs: [String],
        from originCRS: String,
        to destinationCRS: String
    ) -> [String]? {
        let normalized = stationCRSs.map(StationEvolution.normalizedCRS)
        guard normalized.count >= 2 else { return nil }
        if normalized.first == originCRS, normalized.last == destinationCRS {
            return normalized
        }
        if normalized.first == destinationCRS, normalized.last == originCRS {
            return Array(normalized.reversed())
        }
        return nil
    }

    private func orderedSubsequenceIndices(
        _ candidate: [String],
        in sequence: [String]
    ) -> [Int]? {
        var indices = [Int]()
        indices.reserveCapacity(candidate.count)
        var candidateIndex = candidate.startIndex
        for (index, value) in sequence.enumerated() where candidateIndex < candidate.endIndex {
            if value == candidate[candidateIndex] {
                indices.append(index)
                candidate.formIndex(after: &candidateIndex)
            }
        }
        return candidateIndex == candidate.endIndex ? indices : nil
    }

    /// Finds service calls along a physical chain while keeping the chain's stored orientation.
    /// Single-corridor saves historically preserve that physical orientation even when the
    /// passenger service runs in reverse, so reversal belongs to the service slice only.
    private func serviceCallIndices(
        _ calls: [String],
        in physicalStations: [String]
    ) -> (indices: [Int], isReversed: Bool)? {
        if let indices = orderedSubsequenceIndices(calls, in: physicalStations) {
            return (indices, false)
        }
        guard let ascendingIndices = orderedSubsequenceIndices(
            Array(calls.reversed()),
            in: physicalStations
        ) else { return nil }
        return (Array(ascendingIndices.reversed()), true)
    }

    private func station(forNormalizedCRS crs: String) -> Station? {
        stations.first {
            StationEvolution.normalizedCRS($0.crs) == crs
        }
    }

    private func reversingTrains(
        _ trains: [TrainState],
        on route: ServiceRailwayRoute
    ) -> [TrainState] {
        let routeLength = max(route.totalLength, 0)
        return trains.map { train in
            let oldDistance = train.distanceAlongRoute.isFinite
                ? min(max(train.distanceAlongRoute, 0), routeLength)
                : 0
            let newDistance = routeLength - oldDistance
            let direction: TrainTravelDirection = train.direction == .forward
                ? .reverse
                : .forward
            let reversedRoute = RailwayCorridorChainAssembler.reversedRoute(route)
            let sample = reversedRoute.sample(atDistance: newDistance)
            return TrainState(
                id: train.id,
                lineID: train.lineID,
                coordinate: sample?.coordinate ?? train.coordinate,
                bearing: sample.map {
                    normalisedBearing($0.bearing + (direction == .reverse ? 180 : 0))
                } ?? train.bearing,
                distanceAlongRoute: newDistance,
                direction: direction,
                dwellRemaining: train.dwellRemaining
            )
        }
    }

    private func nextAvailableStyleIndex() -> Int {
        let used = Set(lines.map(\.styleIndex))
        let maximum = max(configuration.maximumLineCount, 0)
        return (0..<maximum).first(where: { !used.contains($0) })
            ?? min(max(lines.count, 0), max(maximum - 1, 0))
    }

    private func makeFleet(
        lineID: UUID,
        route: ServiceRailwayRoute,
        frequency: ServiceFrequency,
        fallbackCoordinate: CLLocationCoordinate2D
    ) -> [TrainState] {
        completingFleet(
            [],
            lineID: lineID,
            route: route,
            frequency: frequency,
            fallbackCoordinate: fallbackCoordinate
        )
    }

    /// Adds any trains omitted by an older save while preserving every restored train exactly.
    private func completingFleet(
        _ existing: [TrainState],
        lineID: UUID,
        route: ServiceRailwayRoute,
        frequency: ServiceFrequency,
        fallbackCoordinate: CLLocationCoordinate2D
    ) -> [TrainState] {
        let desiredCount = max(frequency.visibleTrainCount, 1)
        var fleet = Array(existing.prefix(desiredCount))
        let baseTime = fleet.first.map { cycleTime(for: $0, on: route) } ?? 0
        let cycleDuration = trainCycleDuration(for: route)

        while fleet.count < desiredCount {
            let index = fleet.count
            fleet.append(
                phasedTrain(
                    lineID: lineID,
                    route: route,
                    cycleTime: baseTime
                        + cycleDuration * Double(index) / Double(desiredCount),
                    fallbackCoordinate: fallbackCoordinate
                )
            )
        }
        return fleet
    }

    /// Rephases the visible fleet around the full out-and-back cycle. The selected/lead train is
    /// preserved exactly, including terminal dwell, while the remaining trains are spaced by
    /// equal travel time rather than by a one-way geographic fraction.
    private func reconfiguredFleet(
        _ existing: [TrainState],
        lineID: UUID,
        route: ServiceRailwayRoute,
        frequency: ServiceFrequency,
        fallbackCoordinate: CLLocationCoordinate2D
    ) -> [TrainState] {
        let desiredCount = max(frequency.visibleTrainCount, 1)
        guard let first = existing.first else {
            return makeFleet(
                lineID: lineID,
                route: route,
                frequency: frequency,
                fallbackCoordinate: fallbackCoordinate
            )
        }
        let baseTime = cycleTime(for: first, on: route)
        let cycleDuration = trainCycleDuration(for: route)

        return (0..<desiredCount).map { index in
            if index == 0 {
                return TrainState(
                    id: first.id,
                    lineID: lineID,
                    coordinate: first.coordinate,
                    bearing: first.bearing,
                    distanceAlongRoute: first.distanceAlongRoute,
                    direction: first.direction,
                    dwellRemaining: first.dwellRemaining
                )
            }

            return phasedTrain(
                id: existing.indices.contains(index) ? existing[index].id : UUID(),
                lineID: lineID,
                route: route,
                cycleTime: baseTime
                    + cycleDuration * Double(index) / Double(desiredCount),
                fallbackCoordinate: fallbackCoordinate
            )
        }
    }

    /// Places a mixed fleet into a short, deterministic demonstration encounter after the player
    /// creates overtaking capacity. IDs are retained so selection and persistence remain stable.
    private func stagedOvertakingFleet(for line: BuiltLine) -> [TrainState] {
        guard line.trains.count >= 2,
              line.route.totalLength.isFinite,
              line.route.totalLength > 0 else {
            return line.trains
        }

        let routeLength = line.route.totalLength
        return line.trains.enumerated().map { index, train in
            let role = trainOperations.role(
                forTrainAt: index,
                trainCount: line.trains.count,
                pattern: line.servicePattern
            )
            let travelsForward = (index / 2).isMultiple(of: 2)
            let direction: TrainTravelDirection = travelsForward ? .forward : .reverse
            let progress: Double
            let dwellRemaining: TimeInterval
            switch (role, direction) {
            case (.local, _):
                progress = 0.5
                dwellRemaining = line.trackCapacity == .passingLoop
                    ? max(trainOperations.configuration.localIntermediateDwellDuration, 0)
                    : 0
            case (.express, .forward):
                progress = 0.42
                dwellRemaining = 0
            case (.express, .reverse):
                progress = 0.58
                dwellRemaining = 0
            }

            let distance = routeLength * progress
            let sample = line.route.sample(atDistance: distance)
            return TrainState(
                id: train.id,
                lineID: line.id,
                coordinate: sample?.coordinate ?? line.origin.coordinate,
                bearing: normalisedBearing(
                    (sample?.bearing ?? 0) + (direction == .reverse ? 180 : 0)
                ),
                distanceAlongRoute: distance,
                direction: direction,
                dwellRemaining: dwellRemaining
            )
        }
    }

    private func operationsSnapshot(for line: BuiltLine) -> LineOperationsSnapshot {
        let activeRoles = line.trains.indices.map { index in
            line.servicePlan(forSlot: index)?.role
                ?? trainOperations.role(
                    forTrainAt: index,
                    trainCount: line.trains.count,
                    pattern: line.servicePattern
                )
        }
        return trainOperations.evaluate(
            LineOperationsInput(
                frequency: line.serviceFrequency,
                servicePattern: line.servicePattern,
                trackCapacity: line.trackCapacity,
                railwayClass: line.railwayClass,
                serviceRoles: activeRoles
            )
        )
    }

    private func validatedServicePlan(
        _ plan: TrainServicePlan,
        on line: BuiltLine
    ) -> TrainServicePlan? {
        let available = line.stationCRSs.map(StationEvolution.normalizedCRS)
        let requested = plan.stationCRSs.map(StationEvolution.normalizedCRS)
        guard requested.count >= 2,
              requested.count <= maximumServiceCallCount,
              Set(requested).count == requested.count,
              !requested.contains(where: \.isEmpty) else { return nil }

        let indices = requested.compactMap { available.firstIndex(of: $0) }
        guard indices.count == requested.count else { return nil }
        let increasing = zip(indices, indices.dropFirst()).allSatisfy { $0 < $1 }
        let decreasing = zip(indices, indices.dropFirst()).allSatisfy { $0 > $1 }
        guard increasing || decreasing,
              let first = indices.first,
              let last = indices.last,
              first != last else { return nil }

        if plan.role == .local {
            let lower = min(first, last)
            let upper = max(first, last)
            let expected = first < last
                ? Array(available[lower...upper])
                : Array(available[lower...upper].reversed())
            guard requested == expected else { return nil }
            let cumulativeDistances = cumulativeStationDistances(
                for: line.route,
                expectedStationCount: available.count
            )
            guard cumulativeDistances.count == available.count else { return nil }
            let localDistance = abs(cumulativeDistances[last] - cumulativeDistances[first])
            guard automaticServicePlanner.isValidLocalZone(
                distanceMetres: localDistance,
                callCount: requested.count
            ) else { return nil }
        }
        return TrainServicePlan(
            slotIndex: plan.slotIndex,
            role: plan.role,
            stationCRSs: requested
        )
    }

    private func reconciledFleetWithServicePlans(for line: BuiltLine) -> [TrainState] {
        line.trains.enumerated().map { index, train in
            guard let plan = line.servicePlan(forSlot: index) else { return train }
            return reconciledTrain(train, with: plan, on: line)
        }
    }

    private func servicePlans(
        _ plans: [TrainServicePlan],
        afterAddingStationsTo availableStationCRSs: [String],
        replacing previousAutomaticPlans: [TrainServicePlan],
        with updatedAutomaticPlans: [TrainServicePlan]
    ) -> [TrainServicePlan]? {
        let available = availableStationCRSs.map(StationEvolution.normalizedCRS)
        let previousAutomaticBySlot = Dictionary(
            previousAutomaticPlans.map { ($0.slotIndex, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let updatedAutomaticBySlot = Dictionary(
            updatedAutomaticPlans.map { ($0.slotIndex, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        guard previousAutomaticBySlot.count == previousAutomaticPlans.count,
              updatedAutomaticBySlot.count == updatedAutomaticPlans.count,
              Set(previousAutomaticBySlot.keys) == Set(updatedAutomaticBySlot.keys),
              Set(plans.map(\.slotIndex)).count == plans.count,
              Set(plans.map(\.slotIndex)) == Set(updatedAutomaticBySlot.keys) else {
            return nil
        }

        return plans.compactMap { plan in
            guard let updatedAutomaticPlan = updatedAutomaticBySlot[plan.slotIndex] else {
                return nil
            }
            if previousAutomaticBySlot[plan.slotIndex] == plan {
                return updatedAutomaticPlan
            }
            guard plan.role == .local,
                  let firstCRS = plan.stationCRSs.first.map(
                      StationEvolution.normalizedCRS
                  ),
                  let lastCRS = plan.stationCRSs.last.map(
                      StationEvolution.normalizedCRS
                  ),
                  let first = available.firstIndex(of: firstCRS),
                  let last = available.firstIndex(of: lastCRS),
                  first != last else { return plan }
            let lower = min(first, last)
            let upper = max(first, last)
            return TrainServicePlan(
                slotIndex: plan.slotIndex,
                role: .local,
                stationCRSs: first < last
                    ? Array(available[lower...upper])
                    : Array(available[lower...upper].reversed())
            )
        }
    }

    /// Keeps player-authored plans that remain legal after a station insertion. A custom Local
    /// whose expanded all-stop span now exceeds the regional bounds is replaced only in that
    /// timetable slot by the new automatic plan; unrelated custom Express plans remain intact.
    private func servicePlans(
        preservingValidPlansFrom plans: [TrainServicePlan],
        fallingBackTo automaticPlans: [TrainServicePlan],
        on line: BuiltLine
    ) -> [TrainServicePlan]? {
        let automaticBySlot = Dictionary(
            automaticPlans.map { ($0.slotIndex, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        guard automaticBySlot.count == automaticPlans.count,
              Set(plans.map(\.slotIndex)).count == plans.count,
              Set(plans.map(\.slotIndex)) == Set(automaticBySlot.keys) else {
            return nil
        }

        var result = [TrainServicePlan]()
        result.reserveCapacity(plans.count)
        for plan in plans {
            if validatedServicePlan(plan, on: line) == plan {
                result.append(plan)
                continue
            }
            guard let automaticPlan = automaticBySlot[plan.slotIndex],
                  validatedServicePlan(automaticPlan, on: line) == automaticPlan else {
                return nil
            }
            result.append(automaticPlan)
        }
        return result
    }

    private func reconciledTrain(
        _ original: TrainState,
        with plan: TrainServicePlan,
        on line: BuiltLine
    ) -> TrainState {
        let stationDistances = cumulativeStationDistances(
            for: line.route,
            expectedStationCount: line.stationCRSs.count
        )
        guard stationDistances.count == line.stationCRSs.count else { return original }
        let available = line.stationCRSs.map(StationEvolution.normalizedCRS)
        let callDistances = plan.stationCRSs.compactMap { crs -> CLLocationDistance? in
            guard let index = available.firstIndex(
                of: StationEvolution.normalizedCRS(crs)
            ) else { return nil }
            return stationDistances[index]
        }
        guard callDistances.count == plan.stationCRSs.count,
              let minimum = callDistances.min(),
              let maximum = callDistances.max(),
              maximum > minimum else { return original }

        var train = original
        let priorDistance = train.distanceAlongRoute.isFinite
            ? train.distanceAlongRoute
            : minimum
        train.distanceAlongRoute = min(max(priorDistance, minimum), maximum)
        let epsilon = max(line.route.totalLength * 0.000_000_001, 0.001)
        if train.distanceAlongRoute <= minimum + epsilon {
            train.distanceAlongRoute = minimum
            train.direction = .forward
        } else if train.distanceAlongRoute >= maximum - epsilon {
            train.distanceAlongRoute = maximum
            train.direction = .reverse
        }
        let isAtCall = callDistances.contains {
            abs($0 - train.distanceAlongRoute) <= epsilon
        }
        if !isAtCall {
            train.dwellRemaining = 0
        }
        guard train.distanceAlongRoute != original.distanceAlongRoute
                || train.direction != original.direction
                || train.dwellRemaining != original.dwellRemaining else {
            // The station list may have gained a call without changing this train's safe span.
            // Retain its exact sampled coordinate and bearing rather than introducing tiny
            // geometry-resampling drift into an otherwise station-only transaction.
            return original
        }
        updateTrainPosition(&train, on: line.route)
        return train
    }

    private func effectiveTrainSpeed(for routeLength: CLLocationDistance) -> CLLocationSpeed {
        let baseSpeed = configuration.trainSpeedMetresPerSecond
        let demonstrationSpeed: CLLocationSpeed
        if let maximumJourneyDuration = configuration.maximumOneWayJourneyDuration,
           maximumJourneyDuration.isFinite,
           maximumJourneyDuration > 0 {
            demonstrationSpeed = routeLength / maximumJourneyDuration
        } else {
            demonstrationSpeed = 0
        }
        // Long real-world routes need to remain watchable in a short POC session.
        // Explicit test configurations can omit the cap and use physical speed only.
        return max(baseSpeed, demonstrationSpeed)
    }

    private func trainCycleDuration(for route: ServiceRailwayRoute) -> TimeInterval {
        let routeLength = max(route.totalLength, 0)
        let speed = effectiveTrainSpeed(for: routeLength)
        guard routeLength.isFinite, routeLength > 0, speed.isFinite, speed > 0 else {
            return 0
        }
        return 2 * (routeLength / speed + max(configuration.terminalDwellDuration, 0))
    }

    private func cycleTime(for train: TrainState, on route: ServiceRailwayRoute) -> TimeInterval {
        let routeLength = max(route.totalLength, 0)
        let speed = effectiveTrainSpeed(for: routeLength)
        guard routeLength.isFinite, routeLength > 0, speed.isFinite, speed > 0 else {
            return 0
        }

        let travelTime = routeLength / speed
        let dwellDuration = max(configuration.terminalDwellDuration, 0)
        let distance = min(max(train.distanceAlongRoute, 0), routeLength)
        let remainingDwell = min(max(train.dwellRemaining, 0), dwellDuration)

        switch train.direction {
        case .forward:
            if distance <= 0, remainingDwell > 0 {
                return 2 * travelTime + dwellDuration
                    + (dwellDuration - remainingDwell)
            }
            return distance / speed

        case .reverse:
            if distance >= routeLength, remainingDwell > 0 {
                return travelTime + (dwellDuration - remainingDwell)
            }
            return travelTime + dwellDuration + (routeLength - distance) / speed
        }
    }

    private func phasedTrain(
        id: UUID = UUID(),
        lineID: UUID,
        route: ServiceRailwayRoute,
        cycleTime rawCycleTime: TimeInterval,
        fallbackCoordinate: CLLocationCoordinate2D
    ) -> TrainState {
        let routeLength = max(route.totalLength, 0)
        let speed = effectiveTrainSpeed(for: routeLength)
        let dwellDuration = max(configuration.terminalDwellDuration, 0)
        let travelTime = speed > 0 ? routeLength / speed : 0
        let cycleDuration = 2 * (travelTime + dwellDuration)

        guard routeLength.isFinite, routeLength > 0,
              speed.isFinite, speed > 0,
              cycleDuration.isFinite, cycleDuration > 0 else {
            return TrainState(
                id: id,
                lineID: lineID,
                coordinate: fallbackCoordinate,
                bearing: 0
            )
        }

        let remainder = rawCycleTime.truncatingRemainder(dividingBy: cycleDuration)
        let cycleTime = remainder >= 0 ? remainder : remainder + cycleDuration
        let distance: CLLocationDistance
        let direction: TrainTravelDirection
        let dwellRemaining: TimeInterval

        if cycleTime < travelTime {
            distance = cycleTime * speed
            direction = .forward
            dwellRemaining = 0
        } else if cycleTime < travelTime + dwellDuration {
            distance = routeLength
            direction = .reverse
            dwellRemaining = travelTime + dwellDuration - cycleTime
        } else if cycleTime < 2 * travelTime + dwellDuration {
            distance = routeLength - (cycleTime - travelTime - dwellDuration) * speed
            direction = .reverse
            dwellRemaining = 0
        } else {
            distance = 0
            direction = .forward
            dwellRemaining = cycleDuration - cycleTime
        }

        let clampedDistance = min(max(distance, 0), routeLength)
        let sample = route.sample(atDistance: clampedDistance)
        return TrainState(
            id: id,
            lineID: lineID,
            coordinate: sample?.coordinate ?? fallbackCoordinate,
            bearing: normalisedBearing(
                (sample?.bearing ?? 0) + (direction == .reverse ? 180 : 0)
            ),
            distanceAlongRoute: clampedDistance,
            direction: direction,
            dwellRemaining: max(dwellRemaining, 0)
        )
    }

    private func activeStationCapacityRuns(
        for line: BuiltLine
    ) -> [StationCapacityServiceRunInput] {
        logicalServiceRuns(for: line).map { run in
            return StationCapacityServiceRunInput(
                slotIndex: run.identifier,
                stationCRSs: run.stationCRSs,
                scheduledDeparturesPerHour: run.scheduledDeparturesPerHour
            )
        }
    }

    private func activePassengerServiceRuns(
        for line: BuiltLine,
        capacitySnapshot: StationCapacityLineSnapshot?
    ) -> [PassengerServiceRunInput] {
        passengerServiceRuns(
            stationCRSs: line.stationCRSs,
            route: line.route,
            logicalRuns: logicalServiceRuns(for: line),
            effectiveDeparturesPerHour: { run in
                capacitySnapshot?.effectiveDeparturesPerHour(forSlot: run.identifier)
            }
        )
    }

    private func passengerServiceRuns(
        stationCRSs: [String],
        route: ServiceRailwayRoute,
        logicalRuns: [LogicalServiceRun],
        effectiveDeparturesPerHour: (LogicalServiceRun) -> Double? = { _ in nil }
    ) -> [PassengerServiceRunInput] {
        let distances = cumulativeStationDistances(
            for: route,
            expectedStationCount: stationCRSs.count
        )
        guard distances.count == stationCRSs.count else { return [] }
        let normalizedAvailable = stationCRSs.map(StationEvolution.normalizedCRS)

        return logicalRuns.compactMap { run in
            let calls = run.stationCRSs.compactMap { crs -> PassengerStationCallInput? in
                guard let index = normalizedAvailable.firstIndex(
                    of: StationEvolution.normalizedCRS(crs)
                ) else { return nil }
                return PassengerStationCallInput(
                    stationCRS: normalizedAvailable[index],
                    distanceKilometresFromOrigin: distances[index] / 1_000
                )
            }
            .sorted { $0.distanceKilometresFromOrigin < $1.distanceKilometresFromOrigin }
            guard calls.count == run.stationCRSs.count, calls.count >= 2 else { return nil }
            return PassengerServiceRunInput(
                slotIndex: run.identifier,
                stationCalls: calls,
                scheduledDeparturesPerHour: run.scheduledDeparturesPerHour,
                effectiveDeparturesPerHour: effectiveDeparturesPerHour(run)
            )
        }
    }

    private func recalculatePassengerSnapshot() {
        reconcileStationProgress()
        reconcileSettlementPopulation()
        activeNetworkStationCRSCache = calculateActiveNetworkStationCRSs()
        let simulationStations = detailedSimulationStations
        let populationMultipliers = stationPopulationDemandMultipliers
        let newOperationsSnapshots = Dictionary(
            uniqueKeysWithValues: lines.map { line in
                (line.id, operationsSnapshot(for: line))
            }
        )
        let newStationCapacitySnapshot = stationCapacitySimulation.evaluate(
            lines: lines.map { line in
                StationCapacityLineInput(
                    id: line.id,
                    originCRS: line.origin.crs,
                    destinationCRS: line.destination.crs,
                    frequency: line.serviceFrequency,
                    stationCRSs: line.stationCRSs,
                    servicePattern: line.servicePattern,
                    serviceRuns: activeStationCapacityRuns(for: line),
                    isOperating: line.isConstructed
                )
            },
            platformCountsByStationCRS: stationProgressByCRS.mapValues {
                $0.level.platformCount
            }
        )
        let newPassengerSnapshot = passengerSimulation.evaluate(
            lines.map { line in
                PassengerLineInput(
                    id: line.id,
                    originCRS: line.origin.crs,
                    destinationCRS: line.destination.crs,
                    distanceKilometres: line.distanceKilometres,
                    stationCRSs: line.stationCRSs,
                    cumulativeStationDistancesKilometres: cumulativeStationDistances(
                        for: line.route,
                        expectedStationCount: line.stationCRSs.count
                    ).map { $0 / 1_000 },
                    frequency: line.serviceFrequency,
                    servicePattern: line.servicePattern,
                    journeyTimeMultiplier: newOperationsSnapshots[line.id]?
                        .journeyTimeMultiplier ?? 1,
                    reliability: newOperationsSnapshots[line.id]?.reliability ?? 1,
                    capacityPerTrain: line.formation.seatsPerTrain,
                    effectiveDeparturesPerHour: newStationCapacitySnapshot
                        .line(for: line.id)?.effectiveDeparturesPerHour,
                    effectiveIntermediateDeparturesPerHour: newStationCapacitySnapshot
                        .line(for: line.id)?.effectiveIntermediateDeparturesPerHour,
                    serviceRuns: activePassengerServiceRuns(
                        for: line,
                        capacitySnapshot: newStationCapacitySnapshot.line(for: line.id)
                    ),
                    isOperating: line.isConstructed
                )
            },
            stationPopulationMultipliers: populationMultipliers
        )

        let dynamicStationImportanceWeights = Dictionary(
            uniqueKeysWithValues: simulationStations.map { station in
                let baseline = passengerSimulation.configuration.stationDemandWeights[
                    station.crs
                ] ?? passengerSimulation.configuration.fallbackStationDemandWeight
                return (station.crs, baseline * populationMultipliers[station.crs, default: 1])
            }
        )

        let newHappinessSnapshot = accessibilityHappiness.evaluate(
            stationCRSs: simulationStations.map(\.crs),
            passengerSnapshot: newPassengerSnapshot,
            stationImportanceWeights: dynamicStationImportanceWeights,
            reliabilityByLineID: Dictionary(uniqueKeysWithValues: lines.compactMap { line in
                line.isConstructed
                    ? (line.id, newOperationsSnapshots[line.id]?.reliability ?? 1)
                    : nil
            })
        )

        let stationLevels = stationProgressByCRS.mapValues(\.level)
        let newEconomySnapshot = operatingEconomy.evaluate(
            lines: lines.map { line in
                EconomyLineInput(
                    id: line.id,
                    originCRS: line.origin.crs,
                    destinationCRS: line.destination.crs,
                    stationCRSs: line.stationCRSs,
                    distanceMetres: wholeMetres(line.distanceMetres),
                    frequency: line.serviceFrequency,
                    trackCapacity: line.trackCapacity,
                    passengerJourneysPerDay: newPassengerSnapshot.line(for: line.id)?
                        .passengersPerDay ?? 0,
                    passengerMetresPerDay: newPassengerSnapshot.line(for: line.id).map {
                        wholeMetres($0.passengerKilometresPerDay * 1_000)
                    },
                    isOperating: line.isConstructed,
                    railwayClass: line.railwayClass,
                    formation: line.formation
                )
            },
            stationLevelsByCRS: stationLevels
        )

        operationsSnapshotsByLineID = newOperationsSnapshots
        stationCapacitySnapshot = newStationCapacitySnapshot
        passengerSnapshot = newPassengerSnapshot
        happinessSnapshot = newHappinessSnapshot
        economySnapshot = newEconomySnapshot
    }

    private var networkStationCRSs: [String] {
        Set(corridors.flatMap { corridor in
            corridor.stationCRSs.map(StationEvolution.normalizedCRS)
        })
        .filter { !$0.isEmpty }
        .sorted()
    }

    /// The station catalogue is reference data, not an instruction to simulate every unbuilt
    /// place. Preserve full-catalogue behavior for compact fixtures and scope national gameplay
    /// to the network the player has actually constructed.
    private var detailedSimulationStations: [Station] {
        let globalLimit = max(
            configuration.maximumGloballySimulatedCatalogueStationCount,
            0
        )
        guard stations.count > globalLimit else { return stations }
        let networkCRSs = Set(networkStationCRSs)
        return stations.filter { networkCRSs.contains($0.crs) }
    }

    private var activeNetworkStationCRSs: Set<String> {
        activeNetworkStationCRSCache
    }

    private func calculateActiveNetworkStationCRSs() -> Set<String> {
        Set(lines.filter(\.isConstructed).flatMap { line in
            let activeCalls = logicalServiceRuns(for: line).flatMap(\.stationCRSs)
            return (activeCalls.isEmpty ? line.stationCRSs : activeCalls)
                .map(StationEvolution.normalizedCRS)
        })
        .filter { !$0.isEmpty }
    }

    private var stationPopulationDemandMultipliers: [String: Double] {
        Dictionary(uniqueKeysWithValues: settlementPopulationByCRS.keys.sorted().compactMap {
            crs in
            guard let state = settlementPopulationByCRS[crs] else { return nil }
            return (crs, settlementGrowth.passengerDemandMultiplier(for: state))
        })
    }

    private var highSpeedPrestigeInputs: [HighSpeedPrestigeLineInput] {
        lines.map { line in
            HighSpeedPrestigeLineInput(
                id: line.id,
                railwayClass: line.railwayClass,
                originCRS: line.origin.crs,
                destinationCRS: line.destination.crs,
                isCompleted: line.isConstructed
            )
        }
    }

    private func reconcileStationProgress() {
        stationProgressByCRS = stationEvolution.reconcile(
            stationCRSs: networkStationCRSs,
            existingProgress: stationProgressByCRS
        )
    }

    private func reconcileSettlementPopulation() {
        settlementPopulationByCRS = settlementGrowth.reconcile(
            connectedStationCRSs: networkStationCRSs,
            existingStatesByCRS: settlementPopulationByCRS
        )
    }

    private func enqueueStationUpgradeEvents(for stationCRSs: [String]) {
        let stationsByCRS = Dictionary(
            stations.map { ($0.crs, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for crs in stationCRSs.sorted() {
            guard let progress = stationProgressByCRS[crs] else { continue }
            pendingStationUpgradeEvents.append(
                StationUpgradeEvent(
                    stationCRS: crs,
                    stationName: stationsByCRS[crs]?.name ?? crs,
                    level: progress.level
                )
            )
            emitPresentationEvent(.stationUpgraded(stationCRS: crs, level: progress.level))
        }
        presentNextStationUpgradeEventIfNeeded()
    }

    private func presentNextStationUpgradeEventIfNeeded() {
        guard stationUpgradeEvent == nil,
              !pendingStationUpgradeEvents.isEmpty else { return }
        stationUpgradeEvent = pendingStationUpgradeEvents.removeFirst()
    }

    private func cumulativeStationDistances(
        for route: ServiceRailwayRoute,
        expectedStationCount: Int
    ) -> [CLLocationDistance] {
        let fallback = [0, max(route.totalLength, 0)]
        guard expectedStationCount >= 2,
              route.stationCoordinateIndices.count == expectedStationCount else {
            return fallback
        }

        var previousDistance = -CLLocationDistance.infinity
        var distances = [CLLocationDistance]()
        distances.reserveCapacity(expectedStationCount)
        for coordinateIndex in route.stationCoordinateIndices {
            guard route.cumulativeDistances.indices.contains(coordinateIndex) else {
                return fallback
            }
            let distance = route.cumulativeDistances[coordinateIndex]
            guard distance.isFinite,
                  distance >= 0,
                  distance > previousDistance || distances.isEmpty else {
                return fallback
            }
            distances.append(distance)
            previousDistance = distance
        }
        guard distances.count == expectedStationCount,
              abs((distances.first ?? 0)) < 0.001,
              abs((distances.last ?? 0) - route.totalLength) < 0.001 else {
            return fallback
        }
        return distances
    }

    private func previewIsPurchasable(_ preview: LinePreview) -> Bool {
        let stationCRSs = preview.stationCRSs.map(StationEvolution.normalizedCRS)
        let originCRS = StationEvolution.normalizedCRS(preview.origin.crs)
        let destinationCRS = StationEvolution.normalizedCRS(preview.destination.crs)
        guard stationCRSs.count >= 2,
              stationCRSs.count <= maximumServiceCallCount,
              stationCRSs.first == originCRS,
              stationCRSs.last == destinationCRS,
              Set(stationCRSs).count == stationCRSs.count,
              preview.railwayClass != .highSpeed || stationCRSs.count == 2 else {
            return false
        }
        return isUsableServiceRoute(
            preview.route,
            expectedStationCount: stationCRSs.count
        )
    }

    /// Validates the station positions that make a routed service safe to purchase and simulate.
    /// Duplicate route vertices are allowed elsewhere in the polyline, but two passenger calls
    /// must never resolve to the same or a backwards position along it.
    private func isUsableServiceRoute(
        _ route: ServiceRailwayRoute,
        expectedStationCount: Int
    ) -> Bool {
        guard expectedStationCount >= 2,
              route.coordinates.count >= 2,
              route.cumulativeDistances.count == route.coordinates.count,
              route.coordinates.allSatisfy({
                  $0.latitude.isFinite && $0.longitude.isFinite
              }),
              route.cumulativeDistances.allSatisfy({ $0.isFinite && $0 >= 0 }),
              route.totalLength.isFinite,
              route.totalLength > 0,
              route.stationCoordinateIndices.count == expectedStationCount else {
            return false
        }

        var seenIndices = Set<Int>()
        var stationDistances = [CLLocationDistance]()
        stationDistances.reserveCapacity(expectedStationCount)
        for coordinateIndex in route.stationCoordinateIndices {
            guard route.coordinates.indices.contains(coordinateIndex),
                  route.cumulativeDistances.indices.contains(coordinateIndex),
                  seenIndices.insert(coordinateIndex).inserted else {
                return false
            }
            let distance = route.cumulativeDistances[coordinateIndex]
            guard stationDistances.last.map({ distance > $0 }) ?? true else {
                return false
            }
            stationDistances.append(distance)
        }

        return abs((stationDistances.first ?? .infinity)) < 0.001
            && abs((stationDistances.last ?? -.infinity) - route.totalLength) < 0.001
    }

    private func wholeMetres(_ distance: CLLocationDistance) -> Int64 {
        guard distance.isFinite, distance > 0 else { return 0 }
        let roundedDistance = distance.rounded()
        guard roundedDistance < Double(Int64.max) else { return .max }
        return Int64(roundedDistance)
    }

    private func isValidFinanceLedger(
        _ ledger: FinanceLedger,
        completedOperatingDays: UInt64,
        savedAsPlaying: Bool
    ) -> Bool {
        guard ledger.lifetimeConstructionSpendPence >= 0,
              ledger.lifetimeRollingStockSpendPence >= 0,
              ledger.lifetimeLoanProceedsPence >= 0,
              ledger.lifetimePrincipalRepaidPence >= 0,
              ledger.lifetimeInterestPaidPence >= 0,
              ledger.lifetimePrincipalRepaidPence
                <= ledger.lifetimeLoanProceedsPence,
              ledger.trackingStartedOnOperatingDay <= completedOperatingDays,
              ledger.consecutiveNegativeCashDays >= 0,
              !ledger.hasIncompleteCapitalHistory || ledger.mode == .zen,
              ledger.loans.count <= GameSaveSnapshot.maximumActiveLoanCount else {
            return false
        }

        var loanIDs = Set<UUID>()
        for loan in ledger.loans {
            guard loanIDs.insert(loan.id).inserted,
                  loan.originalPrincipalPence > 0,
                  loan.outstandingPrincipalPence > 0,
                  loan.outstandingPrincipalPence <= loan.originalPrincipalPence,
                  (0...10_000).contains(loan.annualInterestBasisPoints),
                  loan.termOperatingDays > 0,
                  loan.remainingOperatingDays > 0,
                  loan.remainingOperatingDays <= loan.termOperatingDays,
                  loan.originatedOnOperatingDay
                    >= ledger.trackingStartedOnOperatingDay,
                  loan.originatedOnOperatingDay <= completedOperatingDays else {
                return false
            }
        }
        let outstandingPrincipal = ledger.loans.reduce(Int64(0)) { result, loan in
            EconomyArithmetic.add(result, loan.outstandingPrincipalPence)
        }
        let activeOriginalPrincipal = ledger.loans.reduce(Int64(0)) { result, loan in
            EconomyArithmetic.add(result, loan.originalPrincipalPence)
        }
        guard activeOriginalPrincipal <= ledger.lifetimeLoanProceedsPence else {
            return false
        }
        guard EconomyArithmetic.add(
            outstandingPrincipal,
            ledger.lifetimePrincipalRepaidPence
        ) == ledger.lifetimeLoanProceedsPence else {
            return false
        }

        switch ledger.mode {
        case .zen:
            return ledger.cashBalancePence == 0
                && ledger.loans.isEmpty
                && ledger.lifetimeLoanProceedsPence == 0
                && ledger.lifetimePrincipalRepaidPence == 0
                && ledger.lifetimeInterestPaidPence == 0
                && ledger.consecutiveNegativeCashDays == 0
                && ledger.bankruptcyOperatingDay == nil
        case .career:
            if ledger.cashBalancePence < 0 {
                guard ledger.consecutiveNegativeCashDays > 0 else { return false }
            } else {
                guard ledger.consecutiveNegativeCashDays == 0 else { return false }
            }
            if let bankruptcyDay = ledger.bankruptcyOperatingDay {
                return bankruptcyDay >= ledger.trackingStartedOnOperatingDay
                    && bankruptcyDay <= completedOperatingDays
                    && ledger.cashBalancePence < 0
                    && ledger.consecutiveNegativeCashDays > 0
                    && !savedAsPlaying
            }
            return true
        }
    }

    private func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? .max : result.partialValue
    }

    private func finishConstruction() {
        let openedLine = lines.last
        restartOperatingDayForNetworkChange()
        selectedOrigin = nil
        selectedDestination = nil
        preview = nil
        clearPreviewStationSelection()
        phase = lines.isEmpty ? .idle : .operating
        recalculatePassengerSnapshot()
        if let openedLine {
            emitPresentationEvent(
                .lineOpened(
                    lineID: openedLine.id,
                    railwayClass: openedLine.railwayClass
                )
            )
        }
        markPersistenceChanged()
    }

    /// A newly opened line starts a fresh synthetic operating day. Frequency-only changes preserve
    /// progress so a company cannot avoid an imminent loss by repeatedly resetting the day.
    private func restartOperatingDayForNetworkChange() {
        var restartedLedger = economyLedger
        restartedLedger.operatingDayProgress = 0
        economyLedger = restartedLedger
    }

    private func clearBuildSelection() {
        selectedOrigin = nil
        selectedDestination = nil
        preview = nil
        clearPreviewStationSelection()
    }

    private func clearPreviewStationSelection() {
        previewIntermediateMatches = []
        previewIntermediateStations = []
        previewSelectedStationCRSs = []
        isUpdatingPreviewRoute = false
    }

    private func presentError(_ message: String, recoveringTo phase: GamePhase) {
        cancelMapStationAddition()
        errorMessage = message
        errorRecoveryPhase = phase
        self.phase = .error
    }

    private func normalisedBearing(_ bearing: CLLocationDirection) -> CLLocationDirection {
        guard bearing.isFinite else { return 0 }
        let remainder = bearing.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }

    private func markPersistenceChanged() {
        // Durable edits may replace route geometry or station order. Animation-only ticks do not
        // call this method, so topology allocations stay out of the 20 Hz train movement path.
        trainMovementTopologyByLineID.removeAll(keepingCapacity: true)
        trainMovementPlanTopologiesByLineID.removeAll(keepingCapacity: true)
        financeSnapshotCache = nil
        financeSnapshotCacheRevision = nil
        prestigeSnapshotCache = nil
        prestigeSnapshotCacheRevision = nil
        if networkLineCount != lines.count {
            networkLineCount = lines.count
        }
        if persistenceRevision < .max {
            persistenceRevision += 1
        }
    }

    private func synchronizeClockSuspension() {
        clock.setSuspended(!isSceneActive || !isPlaying || financeLedger.isBankrupt)
    }

    private func emitPresentationEvent(_ kind: GamePresentationEvent.Kind) {
        if presentationEventSequence < .max {
            presentationEventSequence += 1
        }
        let event = GamePresentationEvent(
            sequence: presentationEventSequence,
            kind: kind
        )
        presentationEventBuffer.append(event)
        if presentationEventBuffer.count > Self.maximumBufferedPresentationEvents {
            presentationEventBuffer.removeFirst(
                presentationEventBuffer.count - Self.maximumBufferedPresentationEvents
            )
        }
        latestPresentationEvent = event
    }
}
