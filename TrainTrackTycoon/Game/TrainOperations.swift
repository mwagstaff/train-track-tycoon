import Foundation

/// The passenger-facing stopping pattern for a line.
nonisolated enum ServicePattern: String, CaseIterable, Codable, Equatable, Sendable, Identifiable {
    case local
    case balanced
    case express

    var id: Self { self }

    var name: String {
        switch self {
        case .local: "Local"
        case .balanced: "Balanced"
        case .express: "Express"
        }
    }

    var compactSymbol: String {
        switch self {
        case .local: "L"
        case .balanced: "B"
        case .express: "X"
        }
    }

    var summary: String {
        switch self {
        case .local:
            "All trains make the intermediate call. Slower journeys serve more places."
        case .balanced:
            "Local and express trains share the line. Extra track capacity unlocks overtaking."
        case .express:
            "All trains run fast between the main destinations and skip the intermediate call."
        }
    }
}

/// A deliberately small infrastructure ladder for the operations proof of concept.
nonisolated enum TrackCapacity: String, CaseIterable, Codable, Equatable, Sendable, Identifiable {
    case singleTrack
    case passingLoop
    case doubleTrack

    var id: Self { self }

    var name: String {
        switch self {
        case .singleTrack: "Single track"
        case .passingLoop: "Passing loop"
        case .doubleTrack: "Double track"
        }
    }

    var next: Self? {
        switch self {
        case .singleTrack: .passingLoop
        case .passingLoop: .doubleTrack
        case .doubleTrack: nil
        }
    }

    var allowsOvertaking: Bool { self != .singleTrack }

    var maintenanceMultiplierBasisPoints: Int64 {
        switch self {
        case .singleTrack: 10_000
        case .passingLoop: 10_750
        case .doubleTrack: 18_500
        }
    }

    var summary: String {
        switch self {
        case .singleTrack:
            "Trains share one constrained railway. Mixed services can queue behind each other."
        case .passingLoop:
            "A local can wait at the midpoint while an express passes."
        case .doubleTrack:
            "Trains have room to pass throughout the route, improving flow and reliability."
        }
    }
}

nonisolated enum TrainServiceRole: String, Codable, Equatable, Sendable {
    case local
    case express

    var badge: String { self == .local ? "L" : "X" }

    var name: String { self == .local ? "Local" : "Express" }
}

nonisolated enum CongestionBand: String, Equatable, Sendable {
    case flowing
    case busy
    case congested

    var name: String {
        switch self {
        case .flowing: "Flowing"
        case .busy: "Busy"
        case .congested: "Congested"
        }
    }
}

nonisolated struct LineOperationsInput: Equatable, Sendable {
    let frequency: ServiceFrequency
    let servicePattern: ServicePattern
    let trackCapacity: TrackCapacity
    let railwayClass: RailwayClass
    /// Optional roles for the active timetable slots. Older callers omit this and retain the
    /// established Local/Balanced/Express preset behaviour.
    let serviceRoles: [TrainServiceRole]?

    init(
        frequency: ServiceFrequency,
        servicePattern: ServicePattern,
        trackCapacity: TrackCapacity,
        railwayClass: RailwayClass = .conventional,
        serviceRoles: [TrainServiceRole]? = nil
    ) {
        self.frequency = frequency
        self.servicePattern = servicePattern
        self.trackCapacity = trackCapacity
        self.railwayClass = railwayClass
        self.serviceRoles = serviceRoles
    }
}

nonisolated struct LineOperationsSnapshot: Equatable, Sendable {
    let railwayClass: RailwayClass
    let servicePattern: ServicePattern
    let trackCapacity: TrackCapacity
    /// A normalized measure of infrastructure pressure, from zero through one.
    let congestionRatio: Double
    let congestionBand: CongestionBand
    /// The expected on-time proportion, from zero through one.
    let reliability: Double
    /// Multiplier applied to the passenger model's unconstrained journey time.
    let journeyTimeMultiplier: Double
    let localTrainCount: Int
    let expressTrainCount: Int
    let advertisedMaximumSpeedMilesPerHour: Int

    var hasMixedServices: Bool { localTrainCount > 0 && expressTrainCount > 0 }

    /// In the POC one visible train represents one departure per hour. This is therefore the
    /// advertised frequency at a real intermediate station; endpoints retain the full timetable.
    var intermediateDeparturesPerHour: Double { Double(max(localTrainCount, 0)) }

    var statusMessage: String {
        if railwayClass == .highSpeed {
            return "Dedicated high-speed tracks are clear for "
                + "\(advertisedMaximumSpeedMilesPerHour) mph running."
        }
        if hasMixedServices, !trackCapacity.allowsOvertaking {
            return "Expresses are being held behind local trains. A passing loop is recommended."
        }
        switch congestionBand {
        case .flowing:
            return trackCapacity.allowsOvertaking
                ? "Services are flowing and overtaking is available."
                : "Services are flowing within the current track capacity."
        case .busy:
            return "The timetable is using most of the available track capacity."
        case .congested:
            return "Trains are losing time to congestion. More track capacity is recommended."
        }
    }
}

nonisolated struct TrainOperationsConfiguration: Equatable, Sendable {
    let localSpeedMultiplier: Double
    let expressSpeedMultiplier: Double
    let constrainedMixedExpressSpeedMultiplier: Double
    let localIntermediateDwellDuration: TimeInterval
    let passingLoopBaseCostPence: Int64
    let doubleTrackConstructionCostBasisPoints: Int64

    static let poc = Self(
        localSpeedMultiplier: 0.82,
        expressSpeedMultiplier: 1.24,
        constrainedMixedExpressSpeedMultiplier: 0.86,
        localIntermediateDwellDuration: 3,
        passingLoopBaseCostPence: 800_000_000,
        doubleTrackConstructionCostBasisPoints: 4_500
    )
}

/// Pure, deterministic operations rules. Animation state remains owned by `GameSession`.
nonisolated struct TrainOperations: Sendable {
    let configuration: TrainOperationsConfiguration
    let highSpeedRail: HighSpeedRail

    init(
        configuration: TrainOperationsConfiguration = .poc,
        highSpeedRail: HighSpeedRail = HighSpeedRail()
    ) {
        self.configuration = configuration
        self.highSpeedRail = highSpeedRail
    }

    func evaluate(_ input: LineOperationsInput) -> LineOperationsSnapshot {
        if input.railwayClass == .highSpeed {
            return evaluateHighSpeed(input)
        }
        let departures = Double(max(input.frequency.departuresPerHour, 0))
        let referenceCapacity: Double
        let mixedServicePenalty: Double
        switch input.trackCapacity {
        case .singleTrack:
            referenceCapacity = 2
            mixedServicePenalty = 0.15
        case .passingLoop:
            referenceCapacity = 3.5
            mixedServicePenalty = 0.06
        case .doubleTrack:
            referenceCapacity = 6
            mixedServicePenalty = 0
        }

        let trainCount = max(input.frequency.visibleTrainCount, 1)
        let roles = activeRoles(for: input, trainCount: trainCount)
        let roleCounts = (
            local: roles.reduce(0) { $0 + ($1 == .local ? 1 : 0) },
            express: roles.reduce(0) { $0 + ($1 == .express ? 1 : 0) }
        )
        let operationalPattern: ServicePattern
        if input.serviceRoles == nil {
            // Preserve the established preset forecast exactly for older callers. An explicit
            // role list means the player has composed individual M16 train plans, in which case
            // the forecast follows the trains that are actually active.
            operationalPattern = input.servicePattern
        } else if roleCounts.express == 0 {
            operationalPattern = .local
        } else if roleCounts.local == 0 {
            operationalPattern = .express
        } else {
            operationalPattern = .balanced
        }

        let utilization = departures / referenceCapacity
        let baseCongestion = max((utilization - 0.25) * 0.70, 0)
        let patternPenalty = operationalPattern == .balanced ? mixedServicePenalty : 0
        let congestion = clamp(baseCongestion + patternPenalty)
        let band: CongestionBand
        if congestion < 0.30 {
            band = .flowing
        } else if congestion < 0.65 {
            band = .busy
        } else {
            band = .congested
        }

        let unconstrainedJourneyMultiplier: Double
        switch operationalPattern {
        case .local:
            unconstrainedJourneyMultiplier = 1.18
        case .balanced:
            if input.serviceRoles == nil {
                unconstrainedJourneyMultiplier = 0.98
            } else {
                let localShare = Double(roleCounts.local) / Double(max(roles.count, 1))
                // Keep the familiar 50/50 Balanced forecast as the centre point while still
                // allowing deliberately local- or express-heavy custom mixes to affect it.
                unconstrainedJourneyMultiplier = 0.80 + 0.36 * localShare
            }
        case .express:
            unconstrainedJourneyMultiplier = 0.82
        }

        return LineOperationsSnapshot(
            railwayClass: .conventional,
            servicePattern: operationalPattern,
            trackCapacity: input.trackCapacity,
            congestionRatio: congestion,
            congestionBand: band,
            reliability: clamp(1 - congestion * 0.28),
            journeyTimeMultiplier: unconstrainedJourneyMultiplier + congestion * 0.45,
            localTrainCount: roleCounts.local,
            expressTrainCount: roleCounts.express,
            advertisedMaximumSpeedMilesPerHour: 100
        )
    }

    private func activeRoles(
        for input: LineOperationsInput,
        trainCount: Int
    ) -> [TrainServiceRole] {
        if let configuredRoles = input.serviceRoles,
           configuredRoles.count >= trainCount {
            return Array(configuredRoles.prefix(trainCount))
        }
        return (0..<trainCount).map {
            role(forTrainAt: $0, trainCount: trainCount, pattern: input.servicePattern)
        }
    }

    func role(
        forTrainAt index: Int,
        trainCount: Int,
        pattern: ServicePattern
    ) -> TrainServiceRole {
        switch pattern {
        case .local:
            return .local
        case .express:
            return .express
        case .balanced:
            guard trainCount > 1 else { return .local }
            return index.isMultiple(of: 2) ? .local : .express
        }
    }

    func speedMultiplier(
        for role: TrainServiceRole,
        pattern: ServicePattern,
        trackCapacity: TrackCapacity,
        congestionRatio: Double,
        railwayClass: RailwayClass = .conventional
    ) -> Double {
        if railwayClass == .highSpeed {
            return max(
                highSpeedRail.movementSpeedMultiplier
                    * (1 - clamp(congestionRatio) * 0.08),
                0.1
            )
        }
        // The legacy POC ran a half-hourly balanced service at the configured demonstration
        // speed. Keep that baseline stable on unmodified track; the operational contrast begins
        // when the player chooses a dedicated pattern or creates overtaking capacity.
        if pattern == .balanced, trackCapacity == .singleTrack {
            return 1
        }

        let base: Double
        switch role {
        case .local:
            base = configuration.localSpeedMultiplier
        case .express:
            if pattern == .balanced, trackCapacity == .singleTrack {
                base = configuration.constrainedMixedExpressSpeedMultiplier
            } else {
                base = configuration.expressSpeedMultiplier
            }
        }
        return max(base * (1 - clamp(congestionRatio) * 0.22), 0.1)
    }

    private func evaluateHighSpeed(_ input: LineOperationsInput) -> LineOperationsSnapshot {
        let departures = Double(max(input.frequency.departuresPerHour, 0))
        let utilization = departures / 8
        let congestion = clamp(max((utilization - 0.25) * 0.40, 0))
        let band: CongestionBand
        if congestion < 0.30 {
            band = .flowing
        } else if congestion < 0.65 {
            band = .busy
        } else {
            band = .congested
        }

        return LineOperationsSnapshot(
            railwayClass: .highSpeed,
            servicePattern: .express,
            trackCapacity: .doubleTrack,
            congestionRatio: congestion,
            congestionBand: band,
            reliability: clamp(0.99 - congestion * 0.10),
            journeyTimeMultiplier: highSpeedRail.journeyTimeMultiplier
                + congestion * 0.10,
            localTrainCount: 0,
            expressTrainCount: max(input.frequency.visibleTrainCount, 1),
            advertisedMaximumSpeedMilesPerHour: highSpeedRail.advertisedSpeedMilesPerHour
        )
    }

    func intermediateStopDistances(
        routeLength: Double,
        role: TrainServiceRole
    ) -> [Double] {
        guard role == .local, routeLength.isFinite, routeLength > 0 else { return [] }
        return [routeLength * 0.5]
    }

    /// Returns every real intermediate calling point for a local train, in route order.
    /// Express trains deliberately skip the same selected stations. Invalid, duplicate and
    /// terminal distances are discarded so animation can consume the result without extra guards.
    func intermediateStopDistances(
        routeLength: Double,
        orderedStationDistances: [Double],
        role: TrainServiceRole
    ) -> [Double] {
        guard role == .local, routeLength.isFinite, routeLength > 0 else { return [] }
        let epsilon = max(routeLength * 0.000_000_001, 0.001)
        var previous = -Double.infinity
        return orderedStationDistances.compactMap { rawDistance in
            guard rawDistance.isFinite else { return nil }
            let distance = min(max(rawDistance, 0), routeLength)
            guard distance > epsilon,
                  distance < routeLength - epsilon,
                  distance > previous + epsilon else { return nil }
            previous = distance
            return distance
        }
    }

    func upgradeCostPence(
        from current: TrackCapacity,
        constructionCostPounds: Int64
    ) -> Int64? {
        switch current {
        case .singleTrack:
            return max(configuration.passingLoopBaseCostPence, 0)
        case .passingLoop:
            let constructionPence = EconomyArithmetic.multiply(
                max(constructionCostPounds, 0),
                100
            )
            return EconomyArithmetic.scaled(
                constructionPence,
                multiplier: max(configuration.doubleTrackConstructionCostBasisPoints, 0),
                divisor: 10_000
            )
        case .doubleTrack:
            return nil
        }
    }

    func infrastructureInvestmentPence(
        for capacity: TrackCapacity,
        constructionCostPounds: Int64
    ) -> Int64 {
        switch capacity {
        case .singleTrack:
            return 0
        case .passingLoop:
            return upgradeCostPence(
                from: .singleTrack,
                constructionCostPounds: constructionCostPounds
            ) ?? 0
        case .doubleTrack:
            return EconomyArithmetic.add(
                upgradeCostPence(
                    from: .singleTrack,
                    constructionCostPounds: constructionCostPounds
                ) ?? 0,
                upgradeCostPence(
                    from: .passingLoop,
                    constructionCostPounds: constructionCostPounds
                ) ?? 0
            )
        }
    }

    private func roleCounts(
        for pattern: ServicePattern,
        trainCount: Int
    ) -> (local: Int, express: Int) {
        var local = 0
        var express = 0
        for index in 0..<max(trainCount, 0) {
            switch role(forTrainAt: index, trainCount: trainCount, pattern: pattern) {
            case .local: local += 1
            case .express: express += 1
            }
        }
        return (local, express)
    }

    private func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
