import Foundation

/// The infrastructure family used by a railway line.
///
/// High-speed rail remains separate from service patterns: an express service can use a
/// conventional line, while a high-speed line represents dedicated infrastructure.
nonisolated enum RailwayClass: String, CaseIterable, Codable, Equatable, Sendable, Identifiable {
    case conventional
    case highSpeed

    var id: Self { self }

    var name: String {
        switch self {
        case .conventional: "Conventional"
        case .highSpeed: "High speed"
        }
    }

    var compactSymbol: String {
        switch self {
        case .conventional: "R"
        case .highSpeed: "H"
        }
    }

    var isHighSpeed: Bool { self == .highSpeed }
}

/// Data-driven tuning for the first playable high-speed rail slice.
nonisolated struct HighSpeedRailConfiguration: Equatable, Sendable {
    /// Applied to the conventional route-construction quote. 30,000 means 3x.
    let trackCostMultiplierBasisPoints: Int64
    let premiumStationUpgradeCostPence: Int64
    /// Purchase price of one high-speed six-car trainset.
    let highSpeedTrainUnitCostPence: Int64
    let advertisedSpeedMilesPerHour: Int
    let movementBaselineMetresPerSecond: Double
    let journeyTimeMultiplier: Double
    let prestigePointsPerCompletedCorridor: Int64
    let prestigePointsPerPremiumEndpoint: Int64

    init(
        trackCostMultiplierBasisPoints: Int64,
        premiumStationUpgradeCostPence: Int64,
        highSpeedTrainUnitCostPence: Int64,
        advertisedSpeedMilesPerHour: Int,
        movementBaselineMetresPerSecond: Double,
        journeyTimeMultiplier: Double,
        prestigePointsPerCompletedCorridor: Int64,
        prestigePointsPerPremiumEndpoint: Int64
    ) {
        self.trackCostMultiplierBasisPoints = trackCostMultiplierBasisPoints
        self.premiumStationUpgradeCostPence = premiumStationUpgradeCostPence
        self.highSpeedTrainUnitCostPence = highSpeedTrainUnitCostPence
        self.advertisedSpeedMilesPerHour = advertisedSpeedMilesPerHour
        self.movementBaselineMetresPerSecond = movementBaselineMetresPerSecond
        self.journeyTimeMultiplier = journeyTimeMultiplier
        self.prestigePointsPerCompletedCorridor = prestigePointsPerCompletedCorridor
        self.prestigePointsPerPremiumEndpoint = prestigePointsPerPremiumEndpoint
    }

    static let poc = Self(
        trackCostMultiplierBasisPoints: 30_000,
        premiumStationUpgradeCostPence: 2_000_000_000,
        highSpeedTrainUnitCostPence: 2_000_000_000,
        advertisedSpeedMilesPerHour: 215,
        movementBaselineMetresPerSecond: 45,
        journeyTimeMultiplier: 0.55,
        prestigePointsPerCompletedCorridor: 15,
        prestigePointsPerPremiumEndpoint: 5
    )
}

/// A high-speed investment split into the same broad categories as the capital economy.
nonisolated struct HighSpeedInvestmentQuote: Equatable, Sendable {
    /// The unmodified conventional construction quote, retained for comparison in the UI.
    let conventionalTrackReferencePence: Int64
    let trackAndInfrastructurePence: Int64
    let premiumStationUpgradesPence: Int64
    let rollingStockPence: Int64
    let newPremiumEndpointCount: Int
    let initialTrainCount: Int

    var constructionPence: Int64 {
        EconomyArithmetic.add(
            max(trackAndInfrastructurePence, 0),
            max(premiumStationUpgradesPence, 0)
        )
    }

    var totalPence: Int64 {
        EconomyArithmetic.add(constructionPence, max(rollingStockPence, 0))
    }
}

/// The minimum facts needed to derive high-speed prestige from completed infrastructure.
nonisolated struct HighSpeedPrestigeLineInput: Identifiable, Equatable, Sendable {
    let id: UUID
    let railwayClass: RailwayClass
    let originCRS: String
    let destinationCRS: String
    let isCompleted: Bool

    init(
        id: UUID,
        railwayClass: RailwayClass,
        originCRS: String,
        destinationCRS: String,
        isCompleted: Bool
    ) {
        self.id = id
        self.railwayClass = railwayClass
        self.originCRS = originCRS
        self.destinationCRS = destinationCRS
        self.isCompleted = isCompleted
    }
}

nonisolated enum HighSpeedPrestigeTier: String, CaseIterable, Codable, Equatable, Sendable {
    case none
    case pioneer
    case national
    case worldClass
    case iconic

    var name: String {
        switch self {
        case .none: "No high-speed prestige"
        case .pioneer: "High-speed pioneer"
        case .national: "National high-speed network"
        case .worldClass: "World-class high-speed network"
        case .iconic: "Iconic high-speed network"
        }
    }

    var summary: String {
        switch self {
        case .none:
            "Complete a dedicated high-speed corridor to begin earning prestige."
        case .pioneer:
            "A landmark high-speed project is reshaping the network."
        case .national:
            "High-speed rail now connects a meaningful national network."
        case .worldClass:
            "The high-speed network is one of the country's defining transport assets."
        case .iconic:
            "The completed high-speed network has reached iconic status."
        }
    }
}

nonisolated struct HighSpeedPrestigeSnapshot: Equatable, Sendable {
    /// A bounded score from zero through 100.
    let score: Int
    let completedCorridorCount: Int
    let premiumEndpointCount: Int
    let tier: HighSpeedPrestigeTier

    var summary: String {
        guard completedCorridorCount > 0 else { return tier.summary }
        let corridorNoun = completedCorridorCount == 1 ? "corridor" : "corridors"
        let stationNoun = premiumEndpointCount == 1 ? "station" : "stations"
        let servingVerb = completedCorridorCount == 1 ? "serves" : "serve"
        if score == 0 {
            return "\(completedCorridorCount) completed \(corridorNoun) serve "
                + "\(premiumEndpointCount) premium \(stationNoun), but current tuning awards "
                + "no high-speed prestige."
        }
        return "\(tier.summary) \(completedCorridorCount) completed \(corridorNoun) \(servingVerb) "
            + "\(premiumEndpointCount) premium \(stationNoun)."
    }
}

/// Pure, deterministic high-speed construction, movement and prestige rules.
nonisolated struct HighSpeedRail: Sendable {
    private static let metresPerSecondPerMilePerHour = 0.44704

    let configuration: HighSpeedRailConfiguration

    init(configuration: HighSpeedRailConfiguration = .poc) {
        self.configuration = configuration
    }

    var advertisedSpeedMilesPerHour: Int {
        max(configuration.advertisedSpeedMilesPerHour, 0)
    }

    /// Converts the advertised capability into the multiplier used by the existing 45 m/s
    /// movement baseline. The POC value is equivalent to 215 mph.
    var movementSpeedMultiplier: Double {
        let baseline = configuration.movementBaselineMetresPerSecond
        guard baseline.isFinite, baseline > 0 else { return 0 }
        let advertisedMetresPerSecond = Double(advertisedSpeedMilesPerHour)
            * Self.metresPerSecondPerMilePerHour
        let multiplier = advertisedMetresPerSecond / baseline
        guard multiplier.isFinite else { return 0 }
        return max(multiplier, 0)
    }

    /// The passenger-simulation journey-time multiplier for a completed high-speed corridor.
    var journeyTimeMultiplier: Double {
        let multiplier = configuration.journeyTimeMultiplier
        guard multiplier.isFinite, multiplier > 0 else { return 1 }
        return min(multiplier, 1)
    }

    func investmentQuote(
        constructionCostPounds: Int64,
        originCRS: String,
        destinationCRS: String,
        existingPremiumStationCRSs: Set<String>,
        trainCount: Int,
        formation: RollingStockFormation = .legacyBaseline
    ) -> HighSpeedInvestmentQuote {
        let conventionalTrackPence = EconomyArithmetic.multiply(
            max(constructionCostPounds, 0),
            100
        )
        let highSpeedTrackPence = EconomyArithmetic.scaled(
            conventionalTrackPence,
            multiplier: max(configuration.trackCostMultiplierBasisPoints, 0),
            divisor: 10_000
        )

        let normalizedExistingStations = Set(
            existingPremiumStationCRSs.map(Self.normalizedCRS)
        ).filter { !$0.isEmpty }
        let endpoints = Set([
            Self.normalizedCRS(originCRS),
            Self.normalizedCRS(destinationCRS),
        ]).filter { !$0.isEmpty }
        let newPremiumEndpointCount = endpoints
            .subtracting(normalizedExistingStations)
            .count
        let normalizedTrainCount = max(trainCount, 0)
        let normalizedFormation = formation.clamped(for: .highSpeed)
        let formationUnitCostPence = EconomyArithmetic.scaled(
            max(configuration.highSpeedTrainUnitCostPence, 0),
            multiplier: Int64(normalizedFormation.carriageCount),
            divisor: Int64(RollingStockFormation.legacyBaseline.carriageCount)
        )

        return HighSpeedInvestmentQuote(
            conventionalTrackReferencePence: conventionalTrackPence,
            trackAndInfrastructurePence: highSpeedTrackPence,
            premiumStationUpgradesPence: EconomyArithmetic.multiply(
                Int64(newPremiumEndpointCount),
                max(configuration.premiumStationUpgradeCostPence, 0)
            ),
            rollingStockPence: EconomyArithmetic.multiply(
                Int64(clamping: normalizedTrainCount),
                formationUnitCostPence
            ),
            newPremiumEndpointCount: newPremiumEndpointCount,
            initialTrainCount: normalizedTrainCount
        )
    }

    func prestigeSnapshot(
        lines: [HighSpeedPrestigeLineInput]
    ) -> HighSpeedPrestigeSnapshot {
        var completedCorridorIDs = Set<UUID>()
        var premiumEndpointCRSs = Set<String>()

        for line in lines where line.railwayClass == .highSpeed && line.isCompleted {
            completedCorridorIDs.insert(line.id)
            let origin = Self.normalizedCRS(line.originCRS)
            let destination = Self.normalizedCRS(line.destinationCRS)
            if !origin.isEmpty { premiumEndpointCRSs.insert(origin) }
            if !destination.isEmpty { premiumEndpointCRSs.insert(destination) }
        }

        let corridorPoints = EconomyArithmetic.multiply(
            Int64(clamping: completedCorridorIDs.count),
            max(configuration.prestigePointsPerCompletedCorridor, 0)
        )
        let endpointPoints = EconomyArithmetic.multiply(
            Int64(clamping: premiumEndpointCRSs.count),
            max(configuration.prestigePointsPerPremiumEndpoint, 0)
        )
        let unboundedScore = EconomyArithmetic.add(corridorPoints, endpointPoints)
        let score = Int(min(max(unboundedScore, 0), 100))

        return HighSpeedPrestigeSnapshot(
            score: score,
            completedCorridorCount: completedCorridorIDs.count,
            premiumEndpointCount: premiumEndpointCRSs.count,
            tier: Self.prestigeTier(for: score)
        )
    }

    func projectedPrestigeGain(
        for proposedLine: HighSpeedPrestigeLineInput,
        existingLines: [HighSpeedPrestigeLineInput]
    ) -> Int {
        let currentScore = prestigeSnapshot(lines: existingLines).score
        let projectedScore = prestigeSnapshot(lines: existingLines + [proposedLine]).score
        return max(projectedScore - currentScore, 0)
    }

    private static func prestigeTier(for score: Int) -> HighSpeedPrestigeTier {
        switch score {
        case ...0: .none
        case 1..<40: .pioneer
        case 40..<70: .national
        case 70..<100: .worldClass
        default: .iconic
        }
    }

    private static func normalizedCRS(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
