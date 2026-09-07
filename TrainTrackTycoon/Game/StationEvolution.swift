import Foundation

/// The canonical visual and operational tiers used by station evolution.
nonisolated enum StationLevel: String, CaseIterable, Codable, Comparable, Equatable, Hashable, Sendable {
    case halt
    case localStation
    case townStation
    case majorStation
    case interchange
    case terminus

    static func < (lhs: Self, rhs: Self) -> Bool {
        guard let lhsIndex = allCases.firstIndex(of: lhs),
              let rhsIndex = allCases.firstIndex(of: rhs) else {
            return lhs.rawValue < rhs.rawValue
        }
        return lhsIndex < rhsIndex
    }

    var displayName: String {
        switch self {
        case .halt: "Halt"
        case .localStation: "Local Station"
        case .townStation: "Town Station"
        case .majorStation: "Major Station"
        case .interchange: "Interchange"
        case .terminus: "Terminus"
        }
    }

    var nextLevel: Self? {
        guard let index = Self.allCases.firstIndex(of: self),
              Self.allCases.indices.contains(index + 1) else {
            return nil
        }
        return Self.allCases[index + 1]
    }

    var platformCount: Int {
        switch self {
        case .halt: 1
        case .localStation: 2
        case .townStation: 3
        case .majorStation: 4
        case .interchange: 6
        case .terminus: 8
        }
    }

    var requiresMultipleConnectedDestinations: Bool {
        self == .interchange || self == .terminus
    }
}

/// Durable station state. The containing dictionary owns the normalized CRS key.
nonisolated struct StationProgress: Codable, Equatable, Hashable, Sendable {
    var level: StationLevel
    var lifetimePassengerVisits: Int64

    init(level: StationLevel = .halt, lifetimePassengerVisits: Int64 = 0) {
        self.level = level
        self.lifetimePassengerVisits = max(lifetimePassengerVisits, 0)
    }

    private enum CodingKeys: String, CodingKey {
        case level
        case lifetimePassengerVisits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        level = try container.decode(StationLevel.self, forKey: .level)
        lifetimePassengerVisits = max(
            try container.decode(Int64.self, forKey: .lifetimePassengerVisits),
            0
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(level, forKey: .level)
        try container.encode(max(lifetimePassengerVisits, 0), forKey: .lifetimePassengerVisits)
    }
}

nonisolated struct StationEvolutionConfiguration: Equatable, Sendable {
    let localStationThreshold: Int64
    let townStationThreshold: Int64
    let majorStationThreshold: Int64
    let interchangeThreshold: Int64
    let terminusThreshold: Int64
    let minimumConnectedDestinationsForAdvancedLevels: Int

    init(
        localStationThreshold: Int64,
        townStationThreshold: Int64,
        majorStationThreshold: Int64,
        interchangeThreshold: Int64,
        terminusThreshold: Int64,
        minimumConnectedDestinationsForAdvancedLevels: Int = 2
    ) {
        let localStationThreshold = max(localStationThreshold, 0)
        let townStationThreshold = max(townStationThreshold, localStationThreshold)
        let majorStationThreshold = max(majorStationThreshold, townStationThreshold)
        let interchangeThreshold = max(interchangeThreshold, majorStationThreshold)
        let terminusThreshold = max(terminusThreshold, interchangeThreshold)

        self.localStationThreshold = localStationThreshold
        self.townStationThreshold = townStationThreshold
        self.majorStationThreshold = majorStationThreshold
        self.interchangeThreshold = interchangeThreshold
        self.terminusThreshold = terminusThreshold
        self.minimumConnectedDestinationsForAdvancedLevels = max(
            minimumConnectedDestinationsForAdvancedLevels,
            2
        )
    }

    func lifetimePassengerVisitThreshold(toReach level: StationLevel) -> Int64 {
        switch level {
        case .halt: 0
        case .localStation: localStationThreshold
        case .townStation: townStationThreshold
        case .majorStation: majorStationThreshold
        case .interchange: interchangeThreshold
        case .terminus: terminusThreshold
        }
    }

    static let poc = StationEvolutionConfiguration(
        localStationThreshold: 10_000,
        townStationThreshold: 50_000,
        majorStationThreshold: 200_000,
        interchangeThreshold: 600_000,
        terminusThreshold: 1_500_000,
        minimumConnectedDestinationsForAdvancedLevels: 2
    )
}

nonisolated enum StationPromotionEligibility: Equatable, Sendable {
    case eligible(nextLevel: StationLevel)
    case needsPassengerVisits(nextLevel: StationLevel, remaining: Int64)
    case needsConnectedDestinations(nextLevel: StationLevel, current: Int, required: Int)
    case needsPassengerVisitsAndDestinations(
        nextLevel: StationLevel,
        remainingVisits: Int64,
        currentDestinations: Int,
        requiredDestinations: Int
    )
    case maximumLevel

    var isEligible: Bool {
        if case .eligible = self { return true }
        return false
    }

    var explanation: String {
        switch self {
        case .eligible(let nextLevel):
            "Ready to upgrade to \(nextLevel.displayName)."
        case let .needsPassengerVisits(nextLevel, remaining):
            "Needs \(remaining) more lifetime passenger visits to reach \(nextLevel.displayName)."
        case let .needsConnectedDestinations(nextLevel, current, required):
            "Needs \(max(required - current, 0)) more direct destinations to reach \(nextLevel.displayName)."
        case let .needsPassengerVisitsAndDestinations(
            nextLevel,
            remainingVisits,
            currentDestinations,
            requiredDestinations
        ):
            "Needs \(remainingVisits) more lifetime passenger visits and "
                + "\(max(requiredDestinations - currentDestinations, 0)) more direct destinations "
                + "to reach \(nextLevel.displayName)."
        case .maximumLevel:
            "Terminus is the highest station level."
        }
    }
}

nonisolated struct StationEvolutionStatus: Equatable, Sendable {
    let level: StationLevel
    let lifetimePassengerVisits: Int64
    let platformCount: Int
    let nextLevel: StationLevel?
    let progressToNextLevel: Double
    let remainingPassengerVisits: Int64
    let promotionEligibility: StationPromotionEligibility

    var eligibilityExplanation: String { promotionEligibility.explanation }
    var isEligibleForPromotion: Bool { promotionEligibility.isEligible }
}

nonisolated struct StationEvolutionDayResult: Equatable, Sendable {
    let progressByStationCRS: [String: StationProgress]
    /// Normalized CRS codes in stable lexical order.
    let promotedStationCRSs: [String]
}

/// Deterministic station progression driven by one cached passenger-network day at a time.
nonisolated struct StationEvolution: Sendable {
    let configuration: StationEvolutionConfiguration

    init(configuration: StationEvolutionConfiguration = .poc) {
        self.configuration = configuration
    }

    static func normalizedCRS(_ crs: String) -> String {
        crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Adds new catalogue stations at Halt, canonicalizes keys, merges aliases without losing
    /// progress, and removes records no longer present in the supplied station set.
    func reconcile(
        stationCRSs: [String],
        existingProgress: [String: StationProgress]
    ) -> [String: StationProgress] {
        let desiredCRSs = Set(
            stationCRSs
                .map(Self.normalizedCRS)
                .filter { !$0.isEmpty }
        )
        var result = [String: StationProgress](minimumCapacity: desiredCRSs.count)

        for rawCRS in existingProgress.keys.sorted() {
            let crs = Self.normalizedCRS(rawCRS)
            guard desiredCRSs.contains(crs), let candidate = existingProgress[rawCRS] else {
                continue
            }

            let sanitized = StationProgress(
                level: candidate.level,
                lifetimePassengerVisits: candidate.lifetimePassengerVisits
            )
            if let current = result[crs] {
                result[crs] = StationProgress(
                    level: max(current.level, sanitized.level),
                    lifetimePassengerVisits: max(
                        current.lifetimePassengerVisits,
                        sanitized.lifetimePassengerVisits
                    )
                )
            } else {
                result[crs] = sanitized
            }
        }

        for crs in desiredCRSs.sorted() where result[crs] == nil {
            result[crs] = StationProgress()
        }
        return result
    }

    func status(
        for progress: StationProgress,
        connectedDestinationCount: Int
    ) -> StationEvolutionStatus {
        let sanitizedProgress = StationProgress(
            level: progress.level,
            lifetimePassengerVisits: progress.lifetimePassengerVisits
        )
        guard let nextLevel = sanitizedProgress.level.nextLevel else {
            return StationEvolutionStatus(
                level: sanitizedProgress.level,
                lifetimePassengerVisits: sanitizedProgress.lifetimePassengerVisits,
                platformCount: sanitizedProgress.level.platformCount,
                nextLevel: nil,
                progressToNextLevel: 1,
                remainingPassengerVisits: 0,
                promotionEligibility: .maximumLevel
            )
        }

        let currentThreshold = configuration.lifetimePassengerVisitThreshold(
            toReach: sanitizedProgress.level
        )
        let nextThreshold = configuration.lifetimePassengerVisitThreshold(toReach: nextLevel)
        let remainingVisits = sanitizedProgress.lifetimePassengerVisits >= nextThreshold
            ? 0
            : nextThreshold - sanitizedProgress.lifetimePassengerVisits
        let thresholdSpan = nextThreshold - currentThreshold
        let visitsWithinLevel = max(
            sanitizedProgress.lifetimePassengerVisits - currentThreshold,
            0
        )
        let progressToNext: Double
        if thresholdSpan > 0 {
            progressToNext = min(max(
                Double(visitsWithinLevel) / Double(thresholdSpan),
                0
            ), 1)
        } else {
            progressToNext = remainingVisits == 0 ? 1 : 0
        }

        let currentDestinations = max(connectedDestinationCount, 0)
        let requiredDestinations = nextLevel.requiresMultipleConnectedDestinations
            ? configuration.minimumConnectedDestinationsForAdvancedLevels
            : 0
        let needsVisits = remainingVisits > 0
        let needsDestinations = currentDestinations < requiredDestinations
        let eligibility: StationPromotionEligibility
        switch (needsVisits, needsDestinations) {
        case (false, false):
            eligibility = .eligible(nextLevel: nextLevel)
        case (true, false):
            eligibility = .needsPassengerVisits(
                nextLevel: nextLevel,
                remaining: remainingVisits
            )
        case (false, true):
            eligibility = .needsConnectedDestinations(
                nextLevel: nextLevel,
                current: currentDestinations,
                required: requiredDestinations
            )
        case (true, true):
            eligibility = .needsPassengerVisitsAndDestinations(
                nextLevel: nextLevel,
                remainingVisits: remainingVisits,
                currentDestinations: currentDestinations,
                requiredDestinations: requiredDestinations
            )
        }

        return StationEvolutionStatus(
            level: sanitizedProgress.level,
            lifetimePassengerVisits: sanitizedProgress.lifetimePassengerVisits,
            platformCount: sanitizedProgress.level.platformCount,
            nextLevel: nextLevel,
            progressToNextLevel: progressToNext,
            remainingPassengerVisits: remainingVisits,
            promotionEligibility: eligibility
        )
    }

    /// Applies exactly one operating day. Even a very large day can advance a station by at most
    /// one tier; excess lifetime visits remain available for later days.
    func applyOperatingDay(
        stationCRSs: [String],
        existingProgress: [String: StationProgress],
        passengerSnapshot: NetworkPassengerSnapshot
    ) -> StationEvolutionDayResult {
        var result = reconcile(
            stationCRSs: stationCRSs,
            existingProgress: existingProgress
        )
        var servedByCRS = [String: Int64]()
        var destinationsByCRS = [String: Int]()

        for rawCRS in passengerSnapshot.stationsByCRS.keys.sorted() {
            guard let station = passengerSnapshot.stationsByCRS[rawCRS] else { continue }
            let crs = Self.normalizedCRS(rawCRS)
            guard !crs.isEmpty else { continue }

            servedByCRS[crs] = saturatingAdd(
                servedByCRS[crs, default: 0],
                Int64(max(station.servedDailyJourneys, 0))
            )
            destinationsByCRS[crs] = max(
                destinationsByCRS[crs, default: 0],
                max(station.connectedDestinationCount, 0)
            )
        }

        var promotedStationCRSs = [String]()
        for crs in result.keys.sorted() {
            guard var progress = result[crs] else { continue }
            progress.lifetimePassengerVisits = saturatingAdd(
                max(progress.lifetimePassengerVisits, 0),
                servedByCRS[crs, default: 0]
            )

            let stationStatus = status(
                for: progress,
                connectedDestinationCount: destinationsByCRS[crs, default: 0]
            )
            if stationStatus.isEligibleForPromotion, let nextLevel = stationStatus.nextLevel {
                progress.level = nextLevel
                promotedStationCRSs.append(crs)
            }
            result[crs] = progress
        }

        return StationEvolutionDayResult(
            progressByStationCRS: result,
            promotedStationCRSs: promotedStationCRSs
        )
    }

    private func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let lhs = max(lhs, 0)
        let rhs = max(rhs, 0)
        let sum = lhs.addingReportingOverflow(rhs)
        return sum.overflow ? .max : sum.partialValue
    }
}
