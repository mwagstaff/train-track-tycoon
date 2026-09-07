import Foundation

/// Durable population state for one rail-connected settlement.
///
/// Population values are deliberately synthetic gameplay figures. They describe the catchment
/// represented by a station, not an official demographic estimate for the place in its name.
nonisolated struct SettlementPopulationState: Codable, Equatable, Hashable, Identifiable,
    Sendable {
    let stationCRS: String
    let baselinePopulation: Int64
    let currentPopulation: Int64
    let latestDailyChange: Int64

    var id: String { stationCRS }
    var totalGrowth: Int64 { max(currentPopulation - baselinePopulation, 0) }

    init(
        stationCRS: String,
        baselinePopulation: Int64,
        currentPopulation: Int64,
        latestDailyChange: Int64 = 0
    ) {
        self.stationCRS = Self.normalizedCRS(stationCRS)
        self.baselinePopulation = max(baselinePopulation, 1)
        self.currentPopulation = max(currentPopulation, self.baselinePopulation)
        self.latestDailyChange = max(latestDailyChange, 0)
    }

    private static func normalizedCRS(_ crs: String) -> String {
        crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

/// The network facts that can create rail-led population growth during one operating day.
nonisolated struct SettlementGrowthInput: Equatable, Sendable {
    let stationCRS: String
    let isConnected: Bool
    /// The local accessibility/happiness result on the user-facing 0...100 scale.
    let localHappinessScore: Double
    let reachableDestinationCount: Int

    init(
        stationCRS: String,
        isConnected: Bool,
        localHappinessScore: Double,
        reachableDestinationCount: Int
    ) {
        self.stationCRS = stationCRS
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        self.isConnected = isConnected
        self.localHappinessScore = localHappinessScore.isFinite
            ? min(max(localHappinessScore, 0), 100)
            : 0
        self.reachableDestinationCount = max(reachableDestinationCount, 0)
    }
}

/// Stable feedback categories let the UI explain growth without interpreting numeric thresholds.
nonisolated enum SettlementGrowthFeedback: String, CaseIterable, Codable, Equatable, Sendable {
    case noRailAccess
    case needsBetterAccessibility
    case steadyGrowth
    case strongGrowth
    case maximumReached

    var title: String {
        switch self {
        case .noRailAccess: "No rail-led growth"
        case .needsBetterAccessibility: "Growth needs better access"
        case .steadyGrowth: "Population growing"
        case .strongGrowth: "Strong population growth"
        case .maximumReached: "Growth potential reached"
        }
    }

    var message: String {
        switch self {
        case .noRailAccess:
            "Connect this settlement to begin rail-led population growth."
        case .needsBetterAccessibility:
            "Reach more destinations and improve local happiness to support population growth."
        case .steadyGrowth:
            "Better rail access is supporting steady population growth."
        case .strongGrowth:
            "Excellent accessibility is driving strong population growth."
        case .maximumReached:
            "This settlement has reached the population supported by the current growth model."
        }
    }
}

/// A presentation-ready, derived view of one settlement's growth state.
nonisolated struct SettlementGrowthStatus: Identifiable, Equatable, Sendable {
    let stationCRS: String
    let isConnected: Bool
    let baselinePopulation: Int64
    let currentPopulation: Int64
    let latestDailyChange: Int64
    /// Normalized growth potential from current happiness and accessibility, in `0...1`.
    let growthPotential: Double
    /// The bounded multiplier to apply to this station's synthetic passenger-demand weight.
    let passengerDemandMultiplier: Double
    let feedback: SettlementGrowthFeedback

    var id: String { stationCRS }
    var totalGrowth: Int64 { max(currentPopulation - baselinePopulation, 0) }
    var growthFromBaselineRatio: Double {
        guard baselinePopulation > 0 else { return 0 }
        return max(Double(totalGrowth) / Double(baselinePopulation), 0)
    }
}

/// The result of advancing every supplied settlement by one completed operating day.
nonisolated struct SettlementGrowthResult: Equatable, Sendable {
    /// Only currently connected settlements have durable rail-led population state.
    let statesByCRS: [String: SettlementPopulationState]
    /// Includes disconnected inputs so station UI can explain why they are not growing.
    let statusesByCRS: [String: SettlementGrowthStatus]
    let totalConnectedPopulation: Int64
    let latestDailyPopulationChange: Int64
    let passengerDemandMultipliersByCRS: [String: Double]

    var states: [SettlementPopulationState] {
        statesByCRS.values.sorted { $0.stationCRS < $1.stationCRS }
    }

    var statuses: [SettlementGrowthStatus] {
        statusesByCRS.values.sorted { $0.stationCRS < $1.stationCRS }
    }

    func state(forStationCRS crs: String) -> SettlementPopulationState? {
        statesByCRS[Self.normalizedCRS(crs)]
    }

    func status(forStationCRS crs: String) -> SettlementGrowthStatus? {
        statusesByCRS[Self.normalizedCRS(crs)]
    }

    private static func normalizedCRS(_ crs: String) -> String {
        crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

nonisolated struct SettlementGrowthConfiguration: Equatable, Sendable {
    let baselinePopulationByCRS: [String: Int64]
    let fallbackBaselinePopulation: Int64
    let minimumHappinessScoreForGrowth: Double
    let happinessScoreForFullGrowth: Double
    let reachableDestinationsForFullGrowth: Int
    let happinessWeight: Double
    /// Strict proportional cap applied to the population at the start of each operating day.
    let maximumDailyGrowthRate: Double
    /// Strict absolute cap applied after the proportional cap.
    let maximumDailyPopulationIncrease: Int64
    /// Strict lifetime population ceiling relative to the settlement's initial baseline.
    let maximumPopulationMultiplier: Double
    /// Population can increase demand, but this prevents a runaway simulation feedback loop.
    let maximumPassengerDemandMultiplier: Double
    let strongGrowthPotentialThreshold: Double

    init(
        baselinePopulationByCRS: [String: Int64],
        fallbackBaselinePopulation: Int64 = 100_000,
        minimumHappinessScoreForGrowth: Double = 25,
        happinessScoreForFullGrowth: Double = 80,
        reachableDestinationsForFullGrowth: Int = 4,
        happinessWeight: Double = 0.75,
        maximumDailyGrowthRate: Double = 0.002,
        maximumDailyPopulationIncrease: Int64 = 500,
        maximumPopulationMultiplier: Double = 1.5,
        maximumPassengerDemandMultiplier: Double = 1.25,
        strongGrowthPotentialThreshold: Double = 0.72
    ) {
        var normalizedBaselines = [String: Int64]()
        for (rawCRS, rawPopulation) in baselinePopulationByCRS.sorted(by: {
            $0.key < $1.key
        }) {
            let crs = Self.normalizedCRS(rawCRS)
            guard !crs.isEmpty else { continue }
            normalizedBaselines[crs] = max(
                normalizedBaselines[crs] ?? 1,
                max(rawPopulation, 1)
            )
        }
        self.baselinePopulationByCRS = normalizedBaselines
        self.fallbackBaselinePopulation = max(fallbackBaselinePopulation, 1)

        let minimumHappiness = Self.finite(
            minimumHappinessScoreForGrowth,
            fallback: 25
        )
        self.minimumHappinessScoreForGrowth = min(max(minimumHappiness, 0), 100)
        let fullHappiness = Self.finite(happinessScoreForFullGrowth, fallback: 80)
        self.happinessScoreForFullGrowth = min(
            max(fullHappiness, self.minimumHappinessScoreForGrowth),
            100
        )
        self.reachableDestinationsForFullGrowth = max(
            reachableDestinationsForFullGrowth,
            1
        )
        self.happinessWeight = Self.clamp(
            Self.finite(happinessWeight, fallback: 0.75),
            lower: 0,
            upper: 1
        )
        self.maximumDailyGrowthRate = Self.clamp(
            Self.finite(maximumDailyGrowthRate, fallback: 0),
            lower: 0,
            upper: 1
        )
        self.maximumDailyPopulationIncrease = max(maximumDailyPopulationIncrease, 0)
        self.maximumPopulationMultiplier = max(
            Self.finite(maximumPopulationMultiplier, fallback: 1),
            1
        )
        self.maximumPassengerDemandMultiplier = max(
            Self.finite(maximumPassengerDemandMultiplier, fallback: 1),
            1
        )
        self.strongGrowthPotentialThreshold = Self.clamp(
            Self.finite(strongGrowthPotentialThreshold, fallback: 0.72),
            lower: 0,
            upper: 1
        )
    }

    /// Synthetic catchment populations for the current South East POC catalogue.
    ///
    /// These intentionally preserve the relative importance of the existing passenger tuning;
    /// they are not asserted to be real populations for station names or local authorities.
    static let poc = SettlementGrowthConfiguration(
        baselinePopulationByCRS: [
            "VIC": 160_000,
            "LBG": 160_000,
            "GTW": 145_000,
            "BFR": 140_000,
            "CLJ": 140_000,
            "BTN": 135_000,
            "ECR": 115_000,
            "TBD": 100_000,
            "HHE": 95_000,
            "HOR": 80_000,
            "PUR": 80_000,
            "SRS": 65_000,
        ]
    )

    private static func normalizedCRS(_ crs: String) -> String {
        crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func finite(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? value : fallback
    }

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}

/// Pure, deterministic settlement progression evaluated only at operating-day boundaries.
nonisolated struct SettlementGrowth: Sendable {
    let configuration: SettlementGrowthConfiguration

    init(configuration: SettlementGrowthConfiguration = .poc) {
        self.configuration = configuration
    }

    func baselinePopulation(forStationCRS crs: String) -> Int64 {
        configuration.baselinePopulationByCRS[normalizedCRS(crs)]
            ?? configuration.fallbackBaselinePopulation
    }

    func initialState(forStationCRS crs: String) -> SettlementPopulationState {
        let normalizedCRS = normalizedCRS(crs)
        let baseline = baselinePopulation(forStationCRS: normalizedCRS)
        return SettlementPopulationState(
            stationCRS: normalizedCRS,
            baselinePopulation: baseline,
            currentPopulation: baseline
        )
    }

    /// Keeps exactly one sanitized state for every connected CRS and drops disconnected state.
    func reconcile(
        connectedStationCRSs: [String],
        existingStatesByCRS: [String: SettlementPopulationState]
    ) -> [String: SettlementPopulationState] {
        let connectedCRSs = Set(
            connectedStationCRSs.map(normalizedCRS).filter { !$0.isEmpty }
        )
        let existing = canonicalizedStates(existingStatesByCRS)
        return Dictionary(uniqueKeysWithValues: connectedCRSs.sorted().map { crs in
            let state = existing[crs].map { sanitizedState($0, stationCRS: crs) }
                ?? initialState(forStationCRS: crs)
            return (crs, state)
        })
    }

    /// Advances every connected settlement exactly once and returns next-day demand multipliers.
    func applyOperatingDay(
        inputs: [SettlementGrowthInput],
        existingStatesByCRS: [String: SettlementPopulationState]
    ) -> SettlementGrowthResult {
        let inputsByCRS = canonicalizedInputs(inputs)
        let connectedCRSs = inputsByCRS.values
            .filter(\.isConnected)
            .map(\.stationCRS)
        var statesByCRS = reconcile(
            connectedStationCRSs: connectedCRSs,
            existingStatesByCRS: existingStatesByCRS
        )

        var statusesByCRS = [String: SettlementGrowthStatus]()
        for crs in inputsByCRS.keys.sorted() {
            guard let input = inputsByCRS[crs] else { continue }
            if input.isConnected, let existingState = statesByCRS[crs] {
                let quality = growthPotential(for: input)
                let increase = dailyIncrease(for: existingState, growthPotential: quality)
                let nextPopulation = saturatingAdd(existingState.currentPopulation, increase)
                let nextState = sanitizedState(
                    SettlementPopulationState(
                        stationCRS: crs,
                        baselinePopulation: existingState.baselinePopulation,
                        currentPopulation: nextPopulation,
                        latestDailyChange: increase
                    ),
                    stationCRS: crs
                )
                statesByCRS[crs] = nextState
                statusesByCRS[crs] = status(for: input, state: nextState)
            } else {
                statusesByCRS[crs] = status(for: input, state: nil)
            }
        }

        var totalPopulation: Int64 = 0
        var totalDailyChange: Int64 = 0
        var multipliersByCRS = [String: Double]()
        for crs in statesByCRS.keys.sorted() {
            guard let state = statesByCRS[crs] else { continue }
            totalPopulation = saturatingAdd(totalPopulation, state.currentPopulation)
            totalDailyChange = saturatingAdd(totalDailyChange, state.latestDailyChange)
            multipliersByCRS[crs] = passengerDemandMultiplier(for: state)
        }

        return SettlementGrowthResult(
            statesByCRS: statesByCRS,
            statusesByCRS: statusesByCRS,
            totalConnectedPopulation: totalPopulation,
            latestDailyPopulationChange: totalDailyChange,
            passengerDemandMultipliersByCRS: multipliersByCRS
        )
    }

    func status(
        for input: SettlementGrowthInput,
        state rawState: SettlementPopulationState?
    ) -> SettlementGrowthStatus {
        let crs = normalizedCRS(input.stationCRS)
        let state = rawState.map { sanitizedState($0, stationCRS: crs) }
            ?? initialState(forStationCRS: crs)
        let potential = growthPotential(for: input)
        let maximumPopulation = maximumPopulation(forBaseline: state.baselinePopulation)
        let feedback: SettlementGrowthFeedback
        if !input.isConnected {
            feedback = .noRailAccess
        } else if state.currentPopulation >= maximumPopulation {
            feedback = .maximumReached
        } else if potential <= 0 {
            feedback = .needsBetterAccessibility
        } else if potential >= configuration.strongGrowthPotentialThreshold {
            feedback = .strongGrowth
        } else {
            feedback = .steadyGrowth
        }

        return SettlementGrowthStatus(
            stationCRS: crs,
            isConnected: input.isConnected,
            baselinePopulation: state.baselinePopulation,
            currentPopulation: state.currentPopulation,
            latestDailyChange: input.isConnected ? state.latestDailyChange : 0,
            growthPotential: input.isConnected ? potential : 0,
            passengerDemandMultiplier: input.isConnected
                ? passengerDemandMultiplier(for: state)
                : 1,
            feedback: feedback
        )
    }

    func passengerDemandMultiplier(for rawState: SettlementPopulationState) -> Double {
        let state = sanitizedState(rawState, stationCRS: normalizedCRS(rawState.stationCRS))
        guard state.baselinePopulation > 0 else { return 1 }
        return clamp(
            Double(state.currentPopulation) / Double(state.baselinePopulation),
            lower: 1,
            upper: configuration.maximumPassengerDemandMultiplier
        )
    }

    private func growthPotential(for input: SettlementGrowthInput) -> Double {
        guard input.isConnected, input.reachableDestinationCount > 0 else { return 0 }
        let lowerHappiness = configuration.minimumHappinessScoreForGrowth
        let upperHappiness = configuration.happinessScoreForFullGrowth
        let happinessSpan = upperHappiness - lowerHappiness
        let happinessFactor: Double
        if happinessSpan > 0 {
            happinessFactor = clamp(
                (input.localHappinessScore - lowerHappiness) / happinessSpan,
                lower: 0,
                upper: 1
            )
        } else {
            happinessFactor = input.localHappinessScore >= upperHappiness ? 1 : 0
        }
        let accessibilityFactor = clamp(
            Double(input.reachableDestinationCount)
                / Double(configuration.reachableDestinationsForFullGrowth),
            lower: 0,
            upper: 1
        )
        // Happiness must clear the configured threshold. Once it does, wider accessibility adds
        // an additional benefit without letting destination count alone create growth.
        return clamp(
            happinessFactor * (
                configuration.happinessWeight
                    + (1 - configuration.happinessWeight) * accessibilityFactor
            ),
            lower: 0,
            upper: 1
        )
    }

    private func dailyIncrease(
        for state: SettlementPopulationState,
        growthPotential: Double
    ) -> Int64 {
        guard growthPotential > 0,
              configuration.maximumDailyGrowthRate > 0,
              configuration.maximumDailyPopulationIncrease > 0 else {
            return 0
        }
        let maximumPopulation = maximumPopulation(forBaseline: state.baselinePopulation)
        let remainingGrowth = max(maximumPopulation - state.currentPopulation, 0)
        guard remainingGrowth > 0 else { return 0 }

        let proportionalCap = min(
            Double(state.currentPopulation) * configuration.maximumDailyGrowthRate,
            Double(Int64.max)
        )
        let strictDailyCap = min(
            proportionalCap,
            Double(configuration.maximumDailyPopulationIncrease),
            Double(remainingGrowth)
        )
        let proposedIncrease = floor(max(strictDailyCap, 0) * growthPotential)
        guard proposedIncrease.isFinite, proposedIncrease >= 1 else { return 0 }
        if proposedIncrease >= Double(Int64.max) {
            return remainingGrowth
        }
        return min(Int64(proposedIncrease), remainingGrowth)
    }

    private func maximumPopulation(forBaseline baseline: Int64) -> Int64 {
        let candidate = Double(max(baseline, 1)) * configuration.maximumPopulationMultiplier
        guard candidate.isFinite, candidate < Double(Int64.max) else { return .max }
        return max(Int64(candidate.rounded(.down)), max(baseline, 1))
    }

    private func sanitizedState(
        _ state: SettlementPopulationState,
        stationCRS: String
    ) -> SettlementPopulationState {
        let baseline = max(state.baselinePopulation, 1)
        let maximumPopulation = maximumPopulation(forBaseline: baseline)
        let currentPopulation = min(max(state.currentPopulation, baseline), maximumPopulation)
        let latestChange = min(
            max(state.latestDailyChange, 0),
            configuration.maximumDailyPopulationIncrease,
            max(currentPopulation - baseline, 0)
        )
        return SettlementPopulationState(
            stationCRS: stationCRS,
            baselinePopulation: baseline,
            currentPopulation: currentPopulation,
            latestDailyChange: latestChange
        )
    }

    private func canonicalizedInputs(
        _ inputs: [SettlementGrowthInput]
    ) -> [String: SettlementGrowthInput] {
        var result = [String: SettlementGrowthInput]()
        for input in inputs {
            let crs = normalizedCRS(input.stationCRS)
            guard !crs.isEmpty else { continue }
            if let existing = result[crs] {
                result[crs] = SettlementGrowthInput(
                    stationCRS: crs,
                    isConnected: existing.isConnected || input.isConnected,
                    localHappinessScore: max(
                        existing.localHappinessScore,
                        input.localHappinessScore
                    ),
                    reachableDestinationCount: max(
                        existing.reachableDestinationCount,
                        input.reachableDestinationCount
                    )
                )
            } else {
                result[crs] = input
            }
        }
        return result
    }

    private func canonicalizedStates(
        _ states: [String: SettlementPopulationState]
    ) -> [String: SettlementPopulationState] {
        var result = [String: SettlementPopulationState]()
        for (rawCRS, state) in states.sorted(by: { $0.key < $1.key }) {
            let crs = normalizedCRS(rawCRS)
            guard !crs.isEmpty else { continue }
            let candidate = sanitizedState(state, stationCRS: crs)
            guard let existing = result[crs] else {
                result[crs] = candidate
                continue
            }
            if candidate.currentPopulation > existing.currentPopulation
                || (candidate.currentPopulation == existing.currentPopulation
                    && candidate.latestDailyChange > existing.latestDailyChange) {
                result[crs] = candidate
            }
        }
        return result
    }

    private func normalizedCRS(_ crs: String) -> String {
        crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    private func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? .max : result.partialValue
    }
}
