import Foundation

/// The six canonical weights documented in Volume 2B of the game plan.
///
/// Every component is represented as a quality score from zero through one, including journey
/// time and crowding (where a higher value means faster and more comfortable respectively).
nonisolated struct HappinessComponentWeights: Equatable, Sendable {
    let reachableDestinations: Double
    let destinationImportance: Double
    let journeyTime: Double
    let frequency: Double
    let reliability: Double
    let crowding: Double

    static let documented = Self(
        reachableDestinations: 0.30,
        destinationImportance: 0.20,
        journeyTime: 0.20,
        frequency: 0.15,
        reliability: 0.10,
        crowding: 0.05
    )
}

/// Normalized quality values. A larger value is always better, and every field is in `0...1`.
nonisolated struct HappinessComponentScores: Equatable, Sendable {
    let reachableDestinations: Double
    let destinationImportance: Double
    let journeyTime: Double
    let frequency: Double
    let reliability: Double
    let crowding: Double

    static let zero = Self(
        reachableDestinations: 0,
        destinationImportance: 0,
        journeyTime: 0,
        frequency: 0,
        reliability: 0,
        crowding: 0
    )

    /// Returns the configured weighted score on the user-facing 0–100 scale.
    func happinessScore(using weights: HappinessComponentWeights = .documented) -> Double {
        let normalizedWeights = NormalizedHappinessWeights(weights)
        let reachableDestinations = Self.normalizedScore(reachableDestinations)
        let destinationImportance = Self.normalizedScore(destinationImportance)
        let journeyTime = Self.normalizedScore(journeyTime)
        let frequency = Self.normalizedScore(frequency)
        let reliability = Self.normalizedScore(reliability)
        let crowding = Self.normalizedScore(crowding)
        return 100 * (
            reachableDestinations * normalizedWeights.reachableDestinations
                + destinationImportance * normalizedWeights.destinationImportance
                + journeyTime * normalizedWeights.journeyTime
                + frequency * normalizedWeights.frequency
                + reliability * normalizedWeights.reliability
                + crowding * normalizedWeights.crowding
        )
    }

    private static func normalizedScore(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

/// One settlement included in local and global happiness.
nonisolated struct SettlementAccessibilityInput: Equatable, Sendable {
    let stationCRS: String
    let destinationImportance: Double
    let happinessWeight: Double

    /// When real population/employment/tourism data arrives it should supply two independent
    /// weights. For the POC, omitting `happinessWeight` deliberately reuses the synthetic demand
    /// weight for both destination importance and global-score weighting.
    init(
        stationCRS: String,
        destinationImportance: Double = 1,
        happinessWeight: Double? = nil
    ) {
        self.stationCRS = Self.normalizedCRS(stationCRS)
        self.destinationImportance = destinationImportance
        self.happinessWeight = happinessWeight ?? destinationImportance
    }

    private static func normalizedCRS(_ crs: String) -> String {
        crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

/// A passenger-facing service edge used to find the best path between settlements.
nonisolated struct AccessibilityServiceInput: Identifiable, Equatable, Sendable {
    let id: UUID
    let originCRS: String
    let destinationCRS: String
    let journeyMinutes: Double
    let departuresPerHour: Double
    let averageWaitMinutes: Double?
    /// Nil uses the configured synthetic reliability until the operations model supplies it.
    let reliability: Double?
    let peakOccupancyRatio: Double
    let isOperating: Bool

    init(
        id: UUID,
        originCRS: String,
        destinationCRS: String,
        journeyMinutes: Double,
        departuresPerHour: Double,
        averageWaitMinutes: Double? = nil,
        reliability: Double? = nil,
        peakOccupancyRatio: Double,
        isOperating: Bool = true
    ) {
        self.id = id
        self.originCRS = Self.normalizedCRS(originCRS)
        self.destinationCRS = Self.normalizedCRS(destinationCRS)
        self.journeyMinutes = journeyMinutes
        self.departuresPerHour = departuresPerHour
        self.averageWaitMinutes = averageWaitMinutes
        self.reliability = reliability
        self.peakOccupancyRatio = peakOccupancyRatio
        self.isOperating = isOperating
    }

    init(snapshot: PassengerLineSnapshot, reliability: Double? = nil) {
        self.init(
            id: snapshot.id,
            originCRS: snapshot.originCRS,
            destinationCRS: snapshot.destinationCRS,
            journeyMinutes: snapshot.journeyMinutes,
            departuresPerHour: snapshot.effectiveDeparturesPerHour,
            averageWaitMinutes: snapshot.averageWaitMinutes,
            reliability: reliability,
            peakOccupancyRatio: snapshot.peakOccupancyRatio,
            isOperating: snapshot.feedback != .notOperating
        )
    }

    init(snapshot: PassengerServiceMarketSnapshot, reliability: Double? = nil) {
        self.init(
            id: snapshot.serviceID,
            originCRS: snapshot.originCRS,
            destinationCRS: snapshot.destinationCRS,
            journeyMinutes: snapshot.journeyMinutes,
            departuresPerHour: snapshot.departuresPerHour,
            averageWaitMinutes: snapshot.averageWaitMinutes,
            reliability: reliability,
            peakOccupancyRatio: snapshot.peakOccupancyRatio,
            isOperating: snapshot.isOperating
        )
    }

    private static func normalizedCRS(_ crs: String) -> String {
        crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

nonisolated enum HappinessBand: String, CaseIterable, Codable, Comparable, Equatable, Sendable {
    case veryPoor
    case poor
    case average
    case good
    case excellent

    static func < (lhs: Self, rhs: Self) -> Bool {
        guard let lhsIndex = allCases.firstIndex(of: lhs),
              let rhsIndex = allCases.firstIndex(of: rhs) else {
            return lhs.rawValue < rhs.rawValue
        }
        return lhsIndex < rhsIndex
    }

    var label: String {
        switch self {
        case .veryPoor: "Very Poor"
        case .poor: "Poor"
        case .average: "Average"
        case .good: "Good"
        case .excellent: "Excellent"
        }
    }
}

nonisolated enum HappinessFeedbackSentiment: String, Codable, Equatable, Sendable {
    case positive
    case caution
}

/// Stable categories let UI and tests react to feedback without parsing presentation text.
nonisolated enum HappinessFeedbackKind: Int, CaseIterable, Codable, Equatable, Sendable {
    case noRailAccess
    case poorConnectivity
    case weakDestinationAccess
    case slowJourneys
    case infrequentService
    case unreliableService
    case overcrowdedTrains
    case excellentDestinationAccess
    case strongAccessibility
    case balancedNetwork
}

nonisolated struct HappinessFeedbackItem: Equatable, Sendable {
    let kind: HappinessFeedbackKind
    let sentiment: HappinessFeedbackSentiment
    let relatedStationCRS: String?

    var title: String {
        switch kind {
        case .noRailAccess: "No rail access"
        case .poorConnectivity: "Poor regional connectivity"
        case .weakDestinationAccess: "Important places are out of reach"
        case .slowJourneys: "Journeys are slow"
        case .infrequentService: "Services are infrequent"
        case .unreliableService: "Reliability needs attention"
        case .overcrowdedTrains: "Peak trains are overcrowded"
        case .excellentDestinationAccess: "Excellent destination access"
        case .strongAccessibility: "Excellent accessibility"
        case .balancedNetwork: "Network performs consistently"
        }
    }

    var message: String {
        switch kind {
        case .noRailAccess:
            "Build a connection to make useful destinations reachable."
        case .poorConnectivity:
            "A branch or interchange would put more settlements within reach."
        case .weakDestinationAccess:
            "Connect this area to more important destinations."
        case .slowJourneys:
            "Faster or more direct services would improve accessibility."
        case .infrequentService:
            "More frequent departures would reduce waiting time."
        case .unreliableService:
            "Improve service reliability to make journeys dependable."
        case .overcrowdedTrains:
            "Add capacity or frequency to relieve peak crowding."
        case .excellentDestinationAccess:
            if let relatedStationCRS {
                "\(relatedStationCRS) is an important destination within easy reach."
            } else {
                "Important destinations are within easy reach."
            }
        case .strongAccessibility:
            "Most useful destinations are reached with a strong service."
        case .balancedNetwork:
            "No single service-quality factor is holding accessibility back."
        }
    }
}

nonisolated struct SettlementHappinessSnapshot: Identifiable, Equatable, Sendable {
    let stationCRS: String
    let happinessScore: Double
    let band: HappinessBand
    let componentScores: HappinessComponentScores
    let reachableDestinationCount: Int
    /// Normalized CRS values in stable lexical order.
    let reachableDestinationCRSs: [String]
    let featuredImportantDestinationCRS: String?
    let averageJourneyMinutes: Double
    let averageInterchanges: Double
    let feedback: [HappinessFeedbackItem]

    var id: String { stationCRS }
    var accessibilityScore: Double { happinessScore }
}

nonisolated struct NetworkAccessibilityStatistics: Equatable, Sendable {
    let settlementCount: Int
    let connectedSettlementCount: Int
    let isolatedSettlementCount: Int
    let operatingServiceCount: Int
    let overcrowdedServiceCount: Int
    /// Unordered settlement pairs for which a path exists.
    let reachableSettlementPairCount: Int
    let possibleSettlementPairCount: Int
    let coverageRatio: Double
    let averageReachableDestinations: Double
    let averageJourneyMinutes: Double
    let averageInterchanges: Double
    /// Largest number of route destinations whose detailed quality was evaluated from one
    /// settlement. This makes the national computation budget observable in regression tests.
    let maximumEvaluatedDestinationsPerSettlement: Int

    static let empty = Self(
        settlementCount: 0,
        connectedSettlementCount: 0,
        isolatedSettlementCount: 0,
        operatingServiceCount: 0,
        overcrowdedServiceCount: 0,
        reachableSettlementPairCount: 0,
        possibleSettlementPairCount: 0,
        coverageRatio: 0,
        averageReachableDestinations: 0,
        averageJourneyMinutes: 0,
        averageInterchanges: 0,
        maximumEvaluatedDestinationsPerSettlement: 0
    )
}

nonisolated struct NetworkHappinessSnapshot: Equatable, Sendable {
    let globalHappinessScore: Double
    let componentScores: HappinessComponentScores
    let feedback: [HappinessFeedbackItem]
    let statistics: NetworkAccessibilityStatistics
    let stationsByCRS: [String: SettlementHappinessSnapshot]

    static let empty = Self(
        globalHappinessScore: 0,
        componentScores: .zero,
        feedback: [],
        statistics: .empty,
        stationsByCRS: [:]
    )

    var accessibilityScore: Double { globalHappinessScore }

    var sortedStationSnapshots: [SettlementHappinessSnapshot] {
        stationsByCRS.values.sorted { $0.stationCRS < $1.stationCRS }
    }

    var stationSnapshots: [SettlementHappinessSnapshot] { sortedStationSnapshots }

    func station(forCRS crs: String) -> SettlementHappinessSnapshot? {
        stationsByCRS[crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()]
    }
}

nonisolated struct AccessibilityHappinessConfiguration: Equatable, Sendable {
    let weights: HappinessComponentWeights
    let reachableDestinationsForFullScore: Int
    let journeyTimeHalfScoreMinutes: Double
    let frequencyHalfScoreDeparturesPerHour: Double
    let interchangePenaltyMinutes: Double
    let maximumReliabilityPenaltyMinutes: Double
    /// Used only when a caller has no operations signal; the current delay-free session supplies 1.
    let defaultReliability: Double
    let comfortablePeakOccupancyRatio: Double
    let weakComponentThreshold: Double
    let excellentComponentThreshold: Double
    let maximumFeedbackItems: Int
    let fallbackStationImportance: Double
    let fallbackHappinessWeight: Double
    /// Full reachability counts and scores remain exact, but retaining every CRS in every station
    /// snapshot would require millions of strings for a connected national network. The sorted
    /// prefix is ample for presentation and diagnostics while keeping snapshot memory bounded.
    let maximumRetainedReachableDestinationCRSs: Int
    /// Detailed route-quality samples per settlement. Reachability and destination-importance
    /// coverage remain exact through connected-component summaries, while journey/frequency/
    /// reliability/crowding use this deterministic nearest-route sample at national scale.
    let maximumEvaluatedDestinationsPerSettlement: Int

    init(
        weights: HappinessComponentWeights = .documented,
        reachableDestinationsForFullScore: Int = 4,
        journeyTimeHalfScoreMinutes: Double = 60,
        frequencyHalfScoreDeparturesPerHour: Double = 1,
        interchangePenaltyMinutes: Double = 12,
        maximumReliabilityPenaltyMinutes: Double = 30,
        defaultReliability: Double = 0.92,
        comfortablePeakOccupancyRatio: Double = 0.75,
        weakComponentThreshold: Double = 0.55,
        excellentComponentThreshold: Double = 0.75,
        maximumFeedbackItems: Int = 3,
        fallbackStationImportance: Double = 1,
        fallbackHappinessWeight: Double = 1,
        maximumRetainedReachableDestinationCRSs: Int = 256,
        maximumEvaluatedDestinationsPerSettlement: Int = 128
    ) {
        self.weights = weights
        self.reachableDestinationsForFullScore = reachableDestinationsForFullScore
        self.journeyTimeHalfScoreMinutes = journeyTimeHalfScoreMinutes
        self.frequencyHalfScoreDeparturesPerHour = frequencyHalfScoreDeparturesPerHour
        self.interchangePenaltyMinutes = interchangePenaltyMinutes
        self.maximumReliabilityPenaltyMinutes = maximumReliabilityPenaltyMinutes
        self.defaultReliability = defaultReliability
        self.comfortablePeakOccupancyRatio = comfortablePeakOccupancyRatio
        self.weakComponentThreshold = weakComponentThreshold
        self.excellentComponentThreshold = excellentComponentThreshold
        self.maximumFeedbackItems = maximumFeedbackItems
        self.fallbackStationImportance = fallbackStationImportance
        self.fallbackHappinessWeight = fallbackHappinessWeight
        self.maximumRetainedReachableDestinationCRSs =
            maximumRetainedReachableDestinationCRSs
        self.maximumEvaluatedDestinationsPerSettlement =
            maximumEvaluatedDestinationsPerSettlement
    }

    /// Synthetic POC normalization only. The plans define the six weights but intentionally do
    /// not yet provide real settlement importance, timetable reliability, or benchmark curves.
    static let poc = Self()
}

/// Pure deterministic accessibility and happiness evaluation.
///
/// The graph uses the lowest generalized-time path. Generalized time is onboard time plus waits,
/// interchange penalties, and a small synthetic reliability penalty. Component scoring remains
/// separate so a poor frequency or reliability is still visible in player feedback.
nonisolated struct AccessibilityHappiness: Sendable {
    let configuration: AccessibilityHappinessConfiguration

    init(configuration: AccessibilityHappinessConfiguration = .poc) {
        self.configuration = configuration
    }

    /// Convenience entry point for `GameSession`. Every supplied catalogue CRS participates in
    /// global happiness, including settlements without any operating rail connection (score zero).
    func evaluate(
        stationCRSs: [String],
        passengerSnapshot: NetworkPassengerSnapshot,
        stationImportanceWeights: [String: Double] = [:],
        reliabilityByLineID: [UUID: Double] = [:]
    ) -> NetworkHappinessSnapshot {
        let importanceByCRS = normalizedImportanceWeights(stationImportanceWeights)
        var allStationCRSs = Set(
            stationCRSs.map(normalizedCRS).filter { !$0.isEmpty }
        )
        for line in passengerSnapshot.lineSnapshots {
            if !line.originCRS.isEmpty { allStationCRSs.insert(normalizedCRS(line.originCRS)) }
            if !line.destinationCRS.isEmpty {
                allStationCRSs.insert(normalizedCRS(line.destinationCRS))
            }
        }

        let settlements = allStationCRSs.sorted().map { crs in
            let importance = importanceByCRS[crs]
                ?? positiveFinite(
                    configuration.fallbackStationImportance,
                    fallback: 1
                )
            return SettlementAccessibilityInput(
                stationCRS: crs,
                destinationImportance: importance,
                // POC: synthetic demand importance stands in for population weighting.
                happinessWeight: importance
            )
        }
        let services: [AccessibilityServiceInput]
        if passengerSnapshot.serviceMarketSnapshots.isEmpty {
            services = passengerSnapshot.lineSnapshots.map { line in
                AccessibilityServiceInput(
                    snapshot: line,
                    reliability: reliabilityByLineID[line.id]
                )
            }
        } else {
            services = passengerSnapshot.serviceMarketSnapshots.map { market in
                AccessibilityServiceInput(
                    snapshot: market,
                    reliability: reliabilityByLineID[market.serviceID]
                )
            }
        }
        return evaluate(settlements: settlements, services: services)
    }

    func evaluate(
        settlements: [SettlementAccessibilityInput],
        services: [AccessibilityServiceInput]
    ) -> NetworkHappinessSnapshot {
        let canonicalSettlements = canonicalizedSettlements(settlements, services: services)
        guard !canonicalSettlements.isEmpty else { return .empty }

        let canonicalServices = canonicalizedServices(services, stations: canonicalSettlements)
        let adjacency = adjacencyList(
            services: canonicalServices,
            stationCRSs: Set(canonicalSettlements.keys)
        )
        let stationCRSs = canonicalSettlements.keys.sorted()
        let reachability = reachabilityIndex(
            stationCRSs: stationCRSs,
            settlementsByCRS: canonicalSettlements,
            adjacency: adjacency
        )
        let detailedDestinationLimit = max(
            configuration.maximumEvaluatedDestinationsPerSettlement,
            1
        )
        let usesExactAllPairs = reachability.components.allSatisfy {
            max($0.stationCRSs.count - 1, 0) <= detailedDestinationLimit
        }
        var snapshotsByCRS = [String: SettlementHappinessSnapshot]()
        snapshotsByCRS.reserveCapacity(stationCRSs.count)
        var routeCount = 0
        var totalJourneyMinutes = 0.0
        var totalInterchanges = 0.0
        var maximumEvaluatedDestinationCount = 0
        for crs in stationCRSs {
            guard let component = reachability.component(containing: crs) else { continue }
            // Process and release one bounded shortest-path tree at a time. Compact networks stay
            // exact; a national network retains exact component reachability while detailed
            // service-quality work has a deterministic per-origin ceiling.
            let routes = bestRoutes(
                from: crs,
                adjacency: adjacency,
                maximumDestinationCount: min(
                    detailedDestinationLimit,
                    max(component.stationCRSs.count - 1, 0)
                ),
                boundsEdgeRelaxations: component.stationCRSs.count - 1
                    > detailedDestinationLimit
            )
            maximumEvaluatedDestinationCount = max(
                maximumEvaluatedDestinationCount,
                routes.count
            )
            snapshotsByCRS[crs] = settlementSnapshot(
                stationCRS: crs,
                settlementsByCRS: canonicalSettlements,
                routes: routes,
                component: component
            )
            for destination in routes.keys.sorted()
            where !usesExactAllPairs || crs < destination {
                guard let route = routes[destination] else { continue }
                routeCount += 1
                totalJourneyMinutes += route.journeyMinutes
                totalInterchanges += Double(max(route.legCount - 1, 0))
            }
        }

        let globalComponents = weightedGlobalComponents(
            snapshotsByCRS: snapshotsByCRS,
            settlementsByCRS: canonicalSettlements
        )
        let globalScore = globalComponents.happinessScore(using: configuration.weights)
        let statistics = networkStatistics(
            stationCRSs: stationCRSs,
            snapshotsByCRS: snapshotsByCRS,
            routeCount: routeCount,
            totalJourneyMinutes: totalJourneyMinutes,
            totalInterchanges: totalInterchanges,
            maximumEvaluatedDestinationCount: maximumEvaluatedDestinationCount,
            services: canonicalServices
        )
        return NetworkHappinessSnapshot(
            globalHappinessScore: globalScore,
            componentScores: globalComponents,
            feedback: feedback(
                components: globalComponents,
                happinessScore: globalScore,
                reachableDestinationCount: statistics.reachableSettlementPairCount,
                featuredDestinationCRS: nil
            ),
            statistics: statistics,
            stationsByCRS: snapshotsByCRS
        )
    }

    private func settlementSnapshot(
        stationCRS: String,
        settlementsByCRS: [String: CanonicalSettlement],
        routes: [String: BestRoute],
        component: ReachabilityComponent
    ) -> SettlementHappinessSnapshot {
        let reachableDestinationCount = max(component.stationCRSs.count - 1, 0)
        guard reachableDestinationCount > 0 else {
            return SettlementHappinessSnapshot(
                stationCRS: stationCRS,
                happinessScore: 0,
                band: .veryPoor,
                componentScores: .zero,
                reachableDestinationCount: 0,
                reachableDestinationCRSs: [],
                featuredImportantDestinationCRS: nil,
                averageJourneyMinutes: 0,
                averageInterchanges: 0,
                feedback: [
                    HappinessFeedbackItem(
                        kind: .noRailAccess,
                        sentiment: .caution,
                        relatedStationCRS: nil
                    ),
                ]
            )
        }

        let evaluatedCRSs = routes.keys.filter { $0 != stationCRS }.sorted()
        let possibleDestinationCount = max(settlementsByCRS.count - 1, 0)
        let reachabilityTarget = min(
            max(configuration.reachableDestinationsForFullScore, 1),
            max(possibleDestinationCount, 1)
        )
        let reachableScore = clamp(
            Double(reachableDestinationCount) / Double(reachabilityTarget),
            lower: 0,
            upper: 1
        )
        let originImportance = settlementsByCRS[stationCRS]?.destinationImportance ?? 0
        let totalPossibleImportance = max(
            component.totalNetworkImportance - originImportance,
            0
        )
        let exactReachableImportance = max(component.totalImportance - originImportance, 0)

        var evaluatedImportance = 0.0
        var journeyScoreTotal = 0.0
        var frequencyScoreTotal = 0.0
        var reliabilityScoreTotal = 0.0
        var crowdingScoreTotal = 0.0
        var journeyMinutesTotal = 0.0
        var interchangeTotal = 0.0
        let featuredDestinationCRS = component.featuredStationCRSs.first {
            $0 != stationCRS
        }

        for destinationCRS in evaluatedCRSs {
            guard let route = routes[destinationCRS],
                  let destination = settlementsByCRS[destinationCRS] else { continue }
            let importance = destination.destinationImportance
            evaluatedImportance += importance
            journeyScoreTotal += journeyTimeScore(route.journeyMinutes) * importance
            frequencyScoreTotal += frequencyScore(route.departuresPerHour) * importance
            reliabilityScoreTotal += route.reliability * importance
            crowdingScoreTotal += crowdingScore(route.peakOccupancyRatio) * importance
            journeyMinutesTotal += route.journeyMinutes * importance
            interchangeTotal += Double(max(route.legCount - 1, 0)) * importance

        }

        let componentScores = HappinessComponentScores(
            reachableDestinations: reachableScore,
            destinationImportance: ratio(exactReachableImportance, over: totalPossibleImportance),
            journeyTime: ratio(journeyScoreTotal, over: evaluatedImportance),
            frequency: ratio(frequencyScoreTotal, over: evaluatedImportance),
            reliability: ratio(reliabilityScoreTotal, over: evaluatedImportance),
            crowding: ratio(crowdingScoreTotal, over: evaluatedImportance)
        )
        let happinessScore = componentScores.happinessScore(using: configuration.weights)
        return SettlementHappinessSnapshot(
            stationCRS: stationCRS,
            happinessScore: happinessScore,
            band: band(for: happinessScore),
            componentScores: componentScores,
            reachableDestinationCount: reachableDestinationCount,
            reachableDestinationCRSs: component.retainedDestinationCRSs(
                excluding: stationCRS,
                maximumCount: max(
                    configuration.maximumRetainedReachableDestinationCRSs,
                    0
                )
            ),
            featuredImportantDestinationCRS: featuredDestinationCRS,
            averageJourneyMinutes: average(journeyMinutesTotal, over: evaluatedImportance),
            averageInterchanges: average(interchangeTotal, over: evaluatedImportance),
            feedback: feedback(
                components: componentScores,
                happinessScore: happinessScore,
                reachableDestinationCount: reachableDestinationCount,
                featuredDestinationCRS: featuredDestinationCRS
            )
        )
    }

    private func weightedGlobalComponents(
        snapshotsByCRS: [String: SettlementHappinessSnapshot],
        settlementsByCRS: [String: CanonicalSettlement]
    ) -> HappinessComponentScores {
        var totalWeight = 0.0
        var reachable = 0.0
        var importance = 0.0
        var journey = 0.0
        var frequency = 0.0
        var reliability = 0.0
        var crowding = 0.0

        for crs in snapshotsByCRS.keys.sorted() {
            guard let snapshot = snapshotsByCRS[crs],
                  let settlement = settlementsByCRS[crs] else { continue }
            let weight = settlement.happinessWeight
            totalWeight += weight
            reachable += snapshot.componentScores.reachableDestinations * weight
            importance += snapshot.componentScores.destinationImportance * weight
            journey += snapshot.componentScores.journeyTime * weight
            frequency += snapshot.componentScores.frequency * weight
            reliability += snapshot.componentScores.reliability * weight
            crowding += snapshot.componentScores.crowding * weight
        }

        guard totalWeight > 0 else { return .zero }
        return HappinessComponentScores(
            reachableDestinations: reachable / totalWeight,
            destinationImportance: importance / totalWeight,
            journeyTime: journey / totalWeight,
            frequency: frequency / totalWeight,
            reliability: reliability / totalWeight,
            crowding: crowding / totalWeight
        )
    }

    private func networkStatistics(
        stationCRSs: [String],
        snapshotsByCRS: [String: SettlementHappinessSnapshot],
        routeCount: Int,
        totalJourneyMinutes: Double,
        totalInterchanges: Double,
        maximumEvaluatedDestinationCount: Int,
        services: [CanonicalService]
    ) -> NetworkAccessibilityStatistics {
        let settlementCount = stationCRSs.count
        let connectedCount = snapshotsByCRS.values.filter {
            $0.reachableDestinationCount > 0
        }.count
        let directedReachableCount = snapshotsByCRS.values.reduce(0) {
            saturatingAdd($0, $1.reachableDestinationCount)
        }
        let reachablePairCount = directedReachableCount / 2
        let possiblePairCount = unorderedPairCount(settlementCount)
        return NetworkAccessibilityStatistics(
            settlementCount: settlementCount,
            connectedSettlementCount: connectedCount,
            isolatedSettlementCount: max(settlementCount - connectedCount, 0),
            operatingServiceCount: Set(services.map(\.id)).count,
            overcrowdedServiceCount: Set(services.compactMap {
                $0.peakOccupancyRatio > comfortablePeakOccupancyRatio ? $0.id : nil
            }).count,
            reachableSettlementPairCount: reachablePairCount,
            possibleSettlementPairCount: possiblePairCount,
            coverageRatio: ratio(Double(reachablePairCount), over: Double(possiblePairCount)),
            averageReachableDestinations: average(
                Double(directedReachableCount),
                over: Double(settlementCount)
            ),
            averageJourneyMinutes: average(totalJourneyMinutes, over: Double(routeCount)),
            averageInterchanges: average(totalInterchanges, over: Double(routeCount)),
            maximumEvaluatedDestinationsPerSettlement: max(
                maximumEvaluatedDestinationCount,
                0
            )
        )
    }

    private func feedback(
        components: HappinessComponentScores,
        happinessScore: Double,
        reachableDestinationCount: Int,
        featuredDestinationCRS: String?
    ) -> [HappinessFeedbackItem] {
        guard reachableDestinationCount > 0 else {
            return [
                HappinessFeedbackItem(
                    kind: .noRailAccess,
                    sentiment: .caution,
                    relatedStationCRS: nil
                ),
            ]
        }

        let weakThreshold = clamp(
            finite(configuration.weakComponentThreshold, fallback: 0.55),
            lower: 0,
            upper: 1
        )
        let componentWeights = NormalizedHappinessWeights(configuration.weights)
        let candidates: [(kind: HappinessFeedbackKind, score: Double)] = [
            (
                .poorConnectivity,
                componentWeights.reachableDestinations
                    * max(weakThreshold - components.reachableDestinations, 0)
            ),
            (
                .weakDestinationAccess,
                componentWeights.destinationImportance
                    * max(weakThreshold - components.destinationImportance, 0)
            ),
            (
                .slowJourneys,
                componentWeights.journeyTime * max(weakThreshold - components.journeyTime, 0)
            ),
            (
                .infrequentService,
                componentWeights.frequency * max(weakThreshold - components.frequency, 0)
            ),
            (
                .unreliableService,
                componentWeights.reliability
                    * max(weakThreshold - components.reliability, 0)
            ),
            (
                .overcrowdedTrains,
                componentWeights.crowding * max(weakThreshold - components.crowding, 0)
            ),
        ]
        let maximumItems = max(configuration.maximumFeedbackItems, 1)
        var result = candidates
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
            .prefix(maximumItems)
            .map {
                HappinessFeedbackItem(
                    kind: $0.kind,
                    sentiment: .caution,
                    relatedStationCRS: nil
                )
            }

        let excellentThreshold = clamp(
            finite(configuration.excellentComponentThreshold, fallback: 0.75),
            lower: 0,
            upper: 1
        )
        if result.count < maximumItems,
           components.destinationImportance >= excellentThreshold,
           featuredDestinationCRS != nil {
            result.append(
                HappinessFeedbackItem(
                    kind: .excellentDestinationAccess,
                    sentiment: .positive,
                    relatedStationCRS: featuredDestinationCRS
                )
            )
        }
        if result.count < maximumItems, happinessScore >= 80 {
            result.append(
                HappinessFeedbackItem(
                    kind: .strongAccessibility,
                    sentiment: .positive,
                    relatedStationCRS: nil
                )
            )
        }
        if result.isEmpty {
            result.append(
                HappinessFeedbackItem(
                    kind: .balancedNetwork,
                    sentiment: .positive,
                    relatedStationCRS: nil
                )
            )
        }
        return result
    }

    private func reachabilityIndex(
        stationCRSs: [String],
        settlementsByCRS: [String: CanonicalSettlement],
        adjacency: [String: [GraphEdge]]
    ) -> ReachabilityIndex {
        let totalNetworkImportance = settlementsByCRS.values.reduce(0.0) {
            $0 + $1.destinationImportance
        }
        var visited = Set<String>()
        var components = [ReachabilityComponent]()
        var componentIndexByStationCRS = [String: Int]()
        componentIndexByStationCRS.reserveCapacity(stationCRSs.count)

        for start in stationCRSs where visited.insert(start).inserted {
            var pending = [start]
            var members = [String]()
            while let stationCRS = pending.popLast() {
                members.append(stationCRS)
                for edge in adjacency[stationCRS] ?? []
                where visited.insert(edge.destinationCRS).inserted {
                    pending.append(edge.destinationCRS)
                }
            }
            members.sort()
            let rankedByImportance = members.sorted { lhs, rhs in
                let lhsImportance = settlementsByCRS[lhs]?.destinationImportance ?? 0
                let rhsImportance = settlementsByCRS[rhs]?.destinationImportance ?? 0
                if lhsImportance != rhsImportance {
                    return lhsImportance > rhsImportance
                }
                return lhs < rhs
            }
            let component = ReachabilityComponent(
                stationCRSs: members,
                totalImportance: members.reduce(0.0) {
                    $0 + (settlementsByCRS[$1]?.destinationImportance ?? 0)
                },
                totalNetworkImportance: totalNetworkImportance,
                featuredStationCRSs: Array(rankedByImportance.prefix(2))
            )
            let componentIndex = components.count
            components.append(component)
            for stationCRS in members {
                componentIndexByStationCRS[stationCRS] = componentIndex
            }
        }
        return ReachabilityIndex(
            components: components,
            componentIndexByStationCRS: componentIndexByStationCRS
        )
    }

    private func bestRoutes(
        from origin: String,
        adjacency: [String: [GraphEdge]],
        maximumDestinationCount: Int,
        boundsEdgeRelaxations: Bool
    ) -> [String: BestRoute] {
        guard maximumDestinationCount > 0 else { return [:] }
        let relaxationProduct = maximumDestinationCount.multipliedReportingOverflow(by: 64)
        let boundedMaximumEdgeRelaxations = relaxationProduct.overflow
            ? Int.max
            : max(relaxationProduct.partialValue, 4_096)
        let maximumEdgeRelaxations = boundsEdgeRelaxations
            ? boundedMaximumEdgeRelaxations
            : Int.max
        var edgeRelaxationCount = 0
        let originSignature = RouteSignature(component: origin, previous: nil)
        var bestByStation = [
            origin: BestRoute(
                generalizedMinutes: 0,
                journeyMinutes: 0,
                departuresPerHour: .infinity,
                reliability: 1,
                peakOccupancyRatio: 0,
                legCount: 0,
                signature: originSignature
            ),
        ]
        var settledStations = Set<String>()
        var settledDestinations = [String: BestRoute]()
        settledDestinations.reserveCapacity(maximumDestinationCount)
        var frontier = RouteHeap()
        frontier.insert(RouteFrontierItem(stationCRS: origin, route: bestByStation[origin]!))

        while let current = frontier.removeMinimum() {
            guard let known = bestByStation[current.stationCRS], known == current.route else {
                continue
            }
            guard settledStations.insert(current.stationCRS).inserted else { continue }
            if current.stationCRS != origin {
                settledDestinations[current.stationCRS] = current.route
                if settledDestinations.count >= maximumDestinationCount {
                    break
                }
            }
            for edge in adjacency[current.stationCRS] ?? [] {
                guard edgeRelaxationCount < maximumEdgeRelaxations else { break }
                edgeRelaxationCount += 1
                guard !settledStations.contains(edge.destinationCRS) else { continue }
                let transferPenalty = current.route.legCount > 0
                    ? sanitizedNonnegative(configuration.interchangePenaltyMinutes, fallback: 12)
                    : 0
                let reliabilityPenalty = (1 - edge.reliability)
                    * sanitizedNonnegative(
                        configuration.maximumReliabilityPenaltyMinutes,
                        fallback: 30
                    )
                let route = BestRoute(
                    generalizedMinutes: current.route.generalizedMinutes
                        + edge.journeyMinutes
                        + edge.averageWaitMinutes
                        + transferPenalty
                        + reliabilityPenalty,
                    journeyMinutes: current.route.journeyMinutes + edge.journeyMinutes,
                    departuresPerHour: min(
                        current.route.departuresPerHour,
                        edge.departuresPerHour
                    ),
                    reliability: clamp(
                        current.route.reliability * edge.reliability,
                        lower: 0,
                        upper: 1
                    ),
                    peakOccupancyRatio: max(
                        current.route.peakOccupancyRatio,
                        edge.peakOccupancyRatio
                    ),
                    legCount: current.route.legCount + 1,
                    signature: RouteSignature(
                        component: "\(edge.destinationCRS)|\(edge.serviceID.uuidString)",
                        previous: current.route.signature
                    )
                )
                if let existing = bestByStation[edge.destinationCRS],
                   !route.precedes(existing) {
                    continue
                }
                bestByStation[edge.destinationCRS] = route
                frontier.insert(
                    RouteFrontierItem(stationCRS: edge.destinationCRS, route: route)
                )
            }
        }
        return settledDestinations
    }

    private func canonicalizedSettlements(
        _ settlements: [SettlementAccessibilityInput],
        services: [AccessibilityServiceInput]
    ) -> [String: CanonicalSettlement] {
        var result = [String: CanonicalSettlement]()
        for input in settlements.sorted(by: { $0.stationCRS < $1.stationCRS }) {
            let crs = normalizedCRS(input.stationCRS)
            guard !crs.isEmpty else { continue }
            let candidate = CanonicalSettlement(
                destinationImportance: positiveFinite(
                    input.destinationImportance,
                    fallback: positiveFinite(configuration.fallbackStationImportance, fallback: 1)
                ),
                happinessWeight: positiveFinite(
                    input.happinessWeight,
                    fallback: positiveFinite(configuration.fallbackHappinessWeight, fallback: 1)
                )
            )
            if let existing = result[crs] {
                result[crs] = CanonicalSettlement(
                    destinationImportance: max(
                        existing.destinationImportance,
                        candidate.destinationImportance
                    ),
                    happinessWeight: max(existing.happinessWeight, candidate.happinessWeight)
                )
            } else {
                result[crs] = candidate
            }
        }

        // A service endpoint omitted by a caller still participates rather than disappearing.
        for service in services.sorted(by: canonicalServiceInputPrecedes) {
            for crs in [normalizedCRS(service.originCRS), normalizedCRS(service.destinationCRS)]
                where !crs.isEmpty && result[crs] == nil {
                result[crs] = CanonicalSettlement(
                    destinationImportance: positiveFinite(
                        configuration.fallbackStationImportance,
                        fallback: 1
                    ),
                    happinessWeight: positiveFinite(
                        configuration.fallbackHappinessWeight,
                        fallback: 1
                    )
                )
            }
        }
        return result
    }

    private func canonicalizedServices(
        _ services: [AccessibilityServiceInput],
        stations: [String: CanonicalSettlement]
    ) -> [CanonicalService] {
        var byKey = [AccessibilityServiceKey: CanonicalService]()
        for input in services.sorted(by: canonicalServiceInputPrecedes) {
            let originCRS = normalizedCRS(input.originCRS)
            let destinationCRS = normalizedCRS(input.destinationCRS)
            guard input.isOperating,
                  !originCRS.isEmpty,
                  !destinationCRS.isEmpty,
                  originCRS != destinationCRS,
                  stations[originCRS] != nil,
                  stations[destinationCRS] != nil,
                  input.journeyMinutes.isFinite,
                  input.journeyMinutes > 0,
                  input.departuresPerHour.isFinite,
                  input.departuresPerHour > 0 else { continue }

            let wait = input.averageWaitMinutes.flatMap { value in
                value.isFinite && value >= 0 ? value : nil
            } ?? 30 / input.departuresPerHour
            let reliability = clamp(
                input.reliability.flatMap { $0.isFinite ? $0 : nil }
                    ?? finite(configuration.defaultReliability, fallback: 0.92),
                lower: 0,
                upper: 1
            )
            let occupancy = clamp(
                finite(input.peakOccupancyRatio, fallback: 0),
                lower: 0,
                upper: 1
            )
            let candidate = CanonicalService(
                id: input.id,
                originCRS: originCRS,
                destinationCRS: destinationCRS,
                journeyMinutes: input.journeyMinutes,
                departuresPerHour: input.departuresPerHour,
                averageWaitMinutes: wait,
                reliability: reliability,
                peakOccupancyRatio: occupancy
            )
            let key = AccessibilityServiceKey(
                serviceID: input.id,
                originCRS: min(originCRS, destinationCRS),
                destinationCRS: max(originCRS, destinationCRS)
            )
            if let existing = byKey[key], !candidate.precedes(existing) {
                continue
            }
            byKey[key] = candidate
        }
        return byKey.values.sorted(by: { $0.precedes($1) })
    }

    private func adjacencyList(
        services: [CanonicalService],
        stationCRSs: Set<String>
    ) -> [String: [GraphEdge]] {
        var result = Dictionary(uniqueKeysWithValues: stationCRSs.map { ($0, [GraphEdge]()) })
        for service in services {
            result[service.originCRS, default: []].append(
                GraphEdge(service: service, destinationCRS: service.destinationCRS)
            )
            result[service.destinationCRS, default: []].append(
                GraphEdge(service: service, destinationCRS: service.originCRS)
            )
        }
        for crs in result.keys.sorted() {
            result[crs]?.sort(by: GraphEdge.precedes)
        }
        return result
    }

    private func journeyTimeScore(_ minutes: Double) -> Double {
        let halfScore = positiveFinite(configuration.journeyTimeHalfScoreMinutes, fallback: 60)
        return clamp(halfScore / (halfScore + max(minutes, 0)), lower: 0, upper: 1)
    }

    private func frequencyScore(_ departuresPerHour: Double) -> Double {
        let halfScore = positiveFinite(
            configuration.frequencyHalfScoreDeparturesPerHour,
            fallback: 1
        )
        let departures = max(departuresPerHour, 0)
        // Saturating Michaelis–Menten curve: every extra departure helps less than the previous.
        return clamp(departures / (departures + halfScore), lower: 0, upper: 1)
    }

    private var comfortablePeakOccupancyRatio: Double {
        clamp(
            finite(configuration.comfortablePeakOccupancyRatio, fallback: 0.75),
            lower: 0,
            upper: 0.999_999
        )
    }

    private func crowdingScore(_ occupancy: Double) -> Double {
        let comfortable = comfortablePeakOccupancyRatio
        guard occupancy > comfortable else { return 1 }
        return clamp(
            1 - (occupancy - comfortable) / (1 - comfortable),
            lower: 0,
            upper: 1
        )
    }

    private func band(for score: Double) -> HappinessBand {
        switch clamp(score, lower: 0, upper: 100) {
        case 80...: .excellent
        case 60..<80: .good
        case 40..<60: .average
        case 20..<40: .poor
        default: .veryPoor
        }
    }

    private func normalizedImportanceWeights(_ weights: [String: Double]) -> [String: Double] {
        var result = [String: Double]()
        for rawCRS in weights.keys.sorted() {
            let crs = normalizedCRS(rawCRS)
            guard !crs.isEmpty, let value = weights[rawCRS], value.isFinite, value > 0 else {
                continue
            }
            result[crs] = max(result[crs] ?? 0, value)
        }
        return result
    }

    private func canonicalServiceInputPrecedes(
        _ lhs: AccessibilityServiceInput,
        _ rhs: AccessibilityServiceInput
    ) -> Bool {
        if lhs.id != rhs.id { return lhs.id.uuidString < rhs.id.uuidString }
        if lhs.originCRS != rhs.originCRS { return lhs.originCRS < rhs.originCRS }
        if lhs.destinationCRS != rhs.destinationCRS {
            return lhs.destinationCRS < rhs.destinationCRS
        }
        if lhs.journeyMinutes != rhs.journeyMinutes {
            return canonicalDouble(lhs.journeyMinutes) < canonicalDouble(rhs.journeyMinutes)
        }
        if lhs.departuresPerHour != rhs.departuresPerHour {
            return canonicalDouble(lhs.departuresPerHour) < canonicalDouble(rhs.departuresPerHour)
        }
        return false
    }

    private func normalizedCRS(_ crs: String) -> String {
        crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func canonicalDouble(_ value: Double) -> Double {
        value.isNaN ? .infinity : value
    }

    private func finite(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? value : fallback
    }

    private func positiveFinite(_ value: Double, fallback: Double) -> Double {
        value.isFinite && value > 0 ? value : fallback
    }

    private func sanitizedNonnegative(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? max(value, 0) : fallback
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    private func ratio(_ numerator: Double, over denominator: Double) -> Double {
        guard numerator.isFinite, denominator.isFinite, denominator > 0 else { return 0 }
        return clamp(numerator / denominator, lower: 0, upper: 1)
    }

    private func average(_ total: Double, over denominator: Double) -> Double {
        guard total.isFinite, denominator.isFinite, denominator > 0 else { return 0 }
        return max(total / denominator, 0)
    }

    private func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? .max : result.partialValue
    }

    private func unorderedPairCount(_ count: Int) -> Int {
        guard count > 1 else { return 0 }
        let first: Int
        let second: Int
        if count.isMultiple(of: 2) {
            first = count / 2
            second = count - 1
        } else {
            first = count
            second = (count - 1) / 2
        }
        let result = first.multipliedReportingOverflow(by: second)
        return result.overflow ? .max : result.partialValue
    }
}

private nonisolated struct NormalizedHappinessWeights {
    let reachableDestinations: Double
    let destinationImportance: Double
    let journeyTime: Double
    let frequency: Double
    let reliability: Double
    let crowding: Double

    init(_ weights: HappinessComponentWeights) {
        let values = [
            Self.nonnegative(weights.reachableDestinations),
            Self.nonnegative(weights.destinationImportance),
            Self.nonnegative(weights.journeyTime),
            Self.nonnegative(weights.frequency),
            Self.nonnegative(weights.reliability),
            Self.nonnegative(weights.crowding),
        ]
        let total = values.reduce(0, +)
        let normalized = total.isFinite && total > 0
            ? values.map { $0 / total }
            : [0.30, 0.20, 0.20, 0.15, 0.10, 0.05]
        reachableDestinations = normalized[0]
        destinationImportance = normalized[1]
        journeyTime = normalized[2]
        frequency = normalized[3]
        reliability = normalized[4]
        crowding = normalized[5]
    }

    private static func nonnegative(_ value: Double) -> Double {
        value.isFinite ? max(value, 0) : 0
    }
}

private nonisolated struct CanonicalSettlement: Equatable {
    let destinationImportance: Double
    let happinessWeight: Double
}

private nonisolated struct ReachabilityComponent {
    let stationCRSs: [String]
    let totalImportance: Double
    let totalNetworkImportance: Double
    /// The two highest-importance stations are sufficient to choose a featured destination when
    /// the highest-ranked member is the origin itself.
    let featuredStationCRSs: [String]

    func retainedDestinationCRSs(excluding origin: String, maximumCount: Int) -> [String] {
        guard maximumCount > 0 else { return [] }
        var result = [String]()
        result.reserveCapacity(min(maximumCount, max(stationCRSs.count - 1, 0)))
        for stationCRS in stationCRSs where stationCRS != origin {
            result.append(stationCRS)
            if result.count == maximumCount { break }
        }
        return result
    }
}

private nonisolated struct ReachabilityIndex {
    let components: [ReachabilityComponent]
    let componentIndexByStationCRS: [String: Int]

    func component(containing stationCRS: String) -> ReachabilityComponent? {
        guard let index = componentIndexByStationCRS[stationCRS],
              components.indices.contains(index) else { return nil }
        return components[index]
    }
}

private nonisolated struct AccessibilityServiceKey: Hashable {
    let serviceID: UUID
    let originCRS: String
    let destinationCRS: String
}

private nonisolated struct CanonicalService: Equatable {
    let id: UUID
    let originCRS: String
    let destinationCRS: String
    let journeyMinutes: Double
    let departuresPerHour: Double
    let averageWaitMinutes: Double
    let reliability: Double
    let peakOccupancyRatio: Double

    func precedes(_ other: Self) -> Bool {
        if id != other.id { return id.uuidString < other.id.uuidString }
        if originCRS != other.originCRS { return originCRS < other.originCRS }
        if destinationCRS != other.destinationCRS { return destinationCRS < other.destinationCRS }
        if journeyMinutes != other.journeyMinutes { return journeyMinutes < other.journeyMinutes }
        if departuresPerHour != other.departuresPerHour {
            return departuresPerHour > other.departuresPerHour
        }
        if averageWaitMinutes != other.averageWaitMinutes {
            return averageWaitMinutes < other.averageWaitMinutes
        }
        if reliability != other.reliability { return reliability > other.reliability }
        return peakOccupancyRatio < other.peakOccupancyRatio
    }
}

private nonisolated struct GraphEdge: Equatable {
    let serviceID: UUID
    let destinationCRS: String
    let journeyMinutes: Double
    let departuresPerHour: Double
    let averageWaitMinutes: Double
    let reliability: Double
    let peakOccupancyRatio: Double

    init(service: CanonicalService, destinationCRS: String) {
        serviceID = service.id
        self.destinationCRS = destinationCRS
        journeyMinutes = service.journeyMinutes
        departuresPerHour = service.departuresPerHour
        averageWaitMinutes = service.averageWaitMinutes
        reliability = service.reliability
        peakOccupancyRatio = service.peakOccupancyRatio
    }

    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.destinationCRS != rhs.destinationCRS {
            return lhs.destinationCRS < rhs.destinationCRS
        }
        if lhs.journeyMinutes != rhs.journeyMinutes {
            return lhs.journeyMinutes < rhs.journeyMinutes
        }
        return lhs.serviceID.uuidString < rhs.serviceID.uuidString
    }
}

private nonisolated final class RouteSignature: @unchecked Sendable {
    let component: String
    let previous: RouteSignature?

    init(component: String, previous: RouteSignature?) {
        self.component = component
        self.previous = previous
    }

    func lexicallyPrecedes(_ other: RouteSignature) -> Bool {
        components.lexicographicallyPrecedes(other.components)
    }

    private var components: [String] {
        var reversed = [String]()
        var cursor: RouteSignature? = self
        while let node = cursor {
            reversed.append(node.component)
            cursor = node.previous
        }
        return Array(reversed.reversed())
    }
}

private nonisolated struct BestRoute: Equatable {
    let generalizedMinutes: Double
    let journeyMinutes: Double
    let departuresPerHour: Double
    let reliability: Double
    let peakOccupancyRatio: Double
    let legCount: Int
    let signature: RouteSignature

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.generalizedMinutes == rhs.generalizedMinutes
            && lhs.journeyMinutes == rhs.journeyMinutes
            && lhs.departuresPerHour == rhs.departuresPerHour
            && lhs.reliability == rhs.reliability
            && lhs.peakOccupancyRatio == rhs.peakOccupancyRatio
            && lhs.legCount == rhs.legCount
            && lhs.signature === rhs.signature
    }

    func precedes(_ other: Self) -> Bool {
        if generalizedMinutes != other.generalizedMinutes {
            return generalizedMinutes < other.generalizedMinutes
        }
        return signature.lexicallyPrecedes(other.signature)
    }
}

private nonisolated struct RouteFrontierItem: Equatable {
    let stationCRS: String
    let route: BestRoute

    func precedes(_ other: Self) -> Bool {
        if route.generalizedMinutes != other.route.generalizedMinutes {
            return route.generalizedMinutes < other.route.generalizedMinutes
        }
        if route.signature !== other.route.signature {
            return route.signature.lexicallyPrecedes(other.route.signature)
        }
        return stationCRS < other.stationCRS
    }
}

private nonisolated struct RouteHeap {
    private var storage = [RouteFrontierItem]()

    mutating func insert(_ item: RouteFrontierItem) {
        storage.append(item)
        var child = storage.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard storage[child].precedes(storage[parent]) else { break }
            storage.swapAt(child, parent)
            child = parent
        }
    }

    mutating func removeMinimum() -> RouteFrontierItem? {
        guard !storage.isEmpty else { return nil }
        if storage.count == 1 { return storage.removeLast() }
        let minimum = storage[0]
        storage[0] = storage.removeLast()
        var parent = 0
        while true {
            let left = 2 * parent + 1
            guard left < storage.count else { break }
            let right = left + 1
            let child = right < storage.count && storage[right].precedes(storage[left])
                ? right
                : left
            guard storage[child].precedes(storage[parent]) else { break }
            storage.swapAt(parent, child)
            parent = child
        }
        return minimum
    }
}
