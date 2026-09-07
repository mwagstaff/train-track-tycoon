import Foundation

/// The operating inputs for one line during a single Zen-mode economy evaluation.
///
/// Distances are stored as whole metres and monetary outputs as whole pence so the
/// simulation remains deterministic across devices and launches.
nonisolated struct EconomyLineInput: Identifiable, Equatable, Sendable {
    let id: UUID
    let originCRS: String
    let destinationCRS: String
    let stationCRSs: [String]
    let distanceMetres: Int64
    let frequency: ServiceFrequency
    let trackCapacity: TrackCapacity
    let passengerJourneysPerDay: Int
    /// Aggregate passenger-distance for real intermediate journeys. Nil preserves the historical
    /// assumption that every rider travels the complete line.
    let passengerMetresPerDay: Int64?
    let isOperating: Bool
    let railwayClass: RailwayClass
    let formation: RollingStockFormation

    init(
        id: UUID,
        originCRS: String,
        destinationCRS: String,
        stationCRSs: [String]? = nil,
        distanceMetres: Int64,
        frequency: ServiceFrequency = .halfHourly,
        trackCapacity: TrackCapacity = .singleTrack,
        passengerJourneysPerDay: Int,
        passengerMetresPerDay: Int64? = nil,
        isOperating: Bool = true,
        railwayClass: RailwayClass = .conventional,
        formation: RollingStockFormation = .legacyBaseline
    ) {
        self.id = id
        self.originCRS = Self.normalizedCRS(originCRS)
        self.destinationCRS = Self.normalizedCRS(destinationCRS)
        let normalizedStations = stationCRSs?.map(Self.normalizedCRS) ?? []
        self.stationCRSs = normalizedStations.count >= 2
            && normalizedStations.first == self.originCRS
            && normalizedStations.last == self.destinationCRS
            ? normalizedStations
            : [self.originCRS, self.destinationCRS]
        self.distanceMetres = distanceMetres
        self.frequency = frequency
        self.trackCapacity = trackCapacity
        self.passengerJourneysPerDay = passengerJourneysPerDay
        self.passengerMetresPerDay = passengerMetresPerDay
        self.isOperating = isOperating
        self.railwayClass = railwayClass
        self.formation = formation
    }

    private static func normalizedCRS(_ crs: String) -> String {
        crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

nonisolated struct LineOperatingEconomySnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let revenuePencePerDay: Int64
    /// The portion of revenue earned above the conventional fare.
    let highSpeedFarePremiumPencePerDay: Int64
    let energyCostPencePerDay: Int64
    let rollingStockMaintenanceCostPencePerDay: Int64
    /// Compatibility aggregate for UI that has not yet adopted the category split.
    let trainOperatingCostPencePerDay: Int64
    let trackUpkeepPencePerDay: Int64
    let totalOperatingCostPencePerDay: Int64
    let operatingResultPencePerDay: Int64

    static func zero(id: UUID) -> Self {
        Self(
            id: id,
            revenuePencePerDay: 0,
            highSpeedFarePremiumPencePerDay: 0,
            energyCostPencePerDay: 0,
            rollingStockMaintenanceCostPencePerDay: 0,
            trainOperatingCostPencePerDay: 0,
            trackUpkeepPencePerDay: 0,
            totalOperatingCostPencePerDay: 0,
            operatingResultPencePerDay: 0
        )
    }

    var premiumFareRevenuePencePerDay: Int64 {
        highSpeedFarePremiumPencePerDay
    }
}

nonisolated struct NetworkOperatingEconomySnapshot: Equatable, Sendable {
    let lineSnapshotsByID: [UUID: LineOperatingEconomySnapshot]
    /// Base station upkeep plus the premium-station surcharge.
    let stationUpkeepPencePerDay: Int64
    let premiumStationUpkeepPencePerDay: Int64
    let totalRevenuePencePerDay: Int64
    let totalHighSpeedFarePremiumPencePerDay: Int64
    let totalEnergyCostPencePerDay: Int64
    let totalRollingStockMaintenanceCostPencePerDay: Int64
    /// Compatibility aggregate equal to energy plus rolling-stock maintenance.
    let totalTrainOperatingCostPencePerDay: Int64
    let totalTrackUpkeepPencePerDay: Int64
    let totalOperatingCostPencePerDay: Int64
    let operatingResultPencePerDay: Int64

    init(
        lineSnapshotsByID: [UUID: LineOperatingEconomySnapshot],
        stationUpkeepPencePerDay: Int64,
        premiumStationUpkeepPencePerDay: Int64 = 0,
        totalRevenuePencePerDay: Int64,
        totalHighSpeedFarePremiumPencePerDay: Int64 = 0,
        totalEnergyCostPencePerDay: Int64,
        totalRollingStockMaintenanceCostPencePerDay: Int64,
        totalTrainOperatingCostPencePerDay: Int64,
        totalTrackUpkeepPencePerDay: Int64,
        totalOperatingCostPencePerDay: Int64,
        operatingResultPencePerDay: Int64
    ) {
        self.lineSnapshotsByID = lineSnapshotsByID
        self.stationUpkeepPencePerDay = stationUpkeepPencePerDay
        self.premiumStationUpkeepPencePerDay = premiumStationUpkeepPencePerDay
        self.totalRevenuePencePerDay = totalRevenuePencePerDay
        self.totalHighSpeedFarePremiumPencePerDay =
            totalHighSpeedFarePremiumPencePerDay
        self.totalEnergyCostPencePerDay = totalEnergyCostPencePerDay
        self.totalRollingStockMaintenanceCostPencePerDay =
            totalRollingStockMaintenanceCostPencePerDay
        self.totalTrainOperatingCostPencePerDay = totalTrainOperatingCostPencePerDay
        self.totalTrackUpkeepPencePerDay = totalTrackUpkeepPencePerDay
        self.totalOperatingCostPencePerDay = totalOperatingCostPencePerDay
        self.operatingResultPencePerDay = operatingResultPencePerDay
    }

    static let zero = Self(
        lineSnapshotsByID: [:],
        stationUpkeepPencePerDay: 0,
        premiumStationUpkeepPencePerDay: 0,
        totalRevenuePencePerDay: 0,
        totalHighSpeedFarePremiumPencePerDay: 0,
        totalEnergyCostPencePerDay: 0,
        totalRollingStockMaintenanceCostPencePerDay: 0,
        totalTrainOperatingCostPencePerDay: 0,
        totalTrackUpkeepPencePerDay: 0,
        totalOperatingCostPencePerDay: 0,
        operatingResultPencePerDay: 0
    )

    func lineSnapshot(for id: UUID) -> LineOperatingEconomySnapshot? {
        lineSnapshotsByID[id]
    }

    var totalPremiumFareRevenuePencePerDay: Int64 {
        totalHighSpeedFarePremiumPencePerDay
    }
}

/// Lifetime values settled by the game session when an operating day completes.
///
/// `OperatingEconomy` only produces a daily snapshot; it intentionally does not mutate
/// this ledger so the session remains the single owner of elapsed-time settlement.
nonisolated struct EconomyLedger: Equatable, Sendable {
    var completedOperatingDays: UInt64
    var operatingDayProgress: Double
    var lifetimeRevenuePence: Int64
    var lifetimeOperatingCostPence: Int64

    init(
        completedOperatingDays: UInt64 = 0,
        operatingDayProgress: Double = 0,
        lifetimeRevenuePence: Int64 = 0,
        lifetimeOperatingCostPence: Int64 = 0
    ) {
        self.completedOperatingDays = completedOperatingDays
        self.operatingDayProgress = operatingDayProgress
        self.lifetimeRevenuePence = lifetimeRevenuePence
        self.lifetimeOperatingCostPence = lifetimeOperatingCostPence
    }

    static let zero = Self()

    var lifetimeOperatingResultPence: Int64 {
        SaturatingEconomyArithmetic.subtract(
            lifetimeRevenuePence,
            lifetimeOperatingCostPence
        )
    }
}

nonisolated struct OperatingEconomyConfiguration: Equatable, Sendable {
    let baseFarePencePerJourney: Int64
    let farePencePerPassengerKilometre: Int64
    let serviceHoursPerDay: Int64
    let directionCount: Int64
    /// Six-car reference rate; purchased formations scale this by `carriages / 6`.
    let energyCostPencePerTrainKilometre: Int64
    /// Six-car reference rate; purchased formations scale this by `carriages / 6`.
    let variableRollingStockMaintenancePencePerTrainKilometre: Int64
    /// Per trainset rather than per carriage, so spare and active units retain an overhead.
    let fixedRollingStockMaintenancePencePerAssignedTrainPerDay: Int64
    let trackUpkeepPencePerKilometrePerDay: Int64
    let stationUpkeepPencePerDayByLevel: [StationLevel: Int64]
    let highSpeedFareMultiplierBasisPoints: Int64
    let highSpeedEnergyCostMultiplierBasisPoints: Int64
    let highSpeedRollingStockMaintenanceMultiplierBasisPoints: Int64
    let highSpeedTrackUpkeepMultiplierBasisPoints: Int64
    let premiumStationUpkeepPencePerDay: Int64

    init(
        baseFarePencePerJourney: Int64,
        farePencePerPassengerKilometre: Int64,
        serviceHoursPerDay: Int64,
        directionCount: Int64,
        energyCostPencePerTrainKilometre: Int64,
        variableRollingStockMaintenancePencePerTrainKilometre: Int64,
        fixedRollingStockMaintenancePencePerAssignedTrainPerDay: Int64,
        trackUpkeepPencePerKilometrePerDay: Int64,
        stationUpkeepPencePerDayByLevel: [StationLevel: Int64],
        highSpeedFareMultiplierBasisPoints: Int64 = 13_500,
        highSpeedEnergyCostMultiplierBasisPoints: Int64 = 20_000,
        highSpeedRollingStockMaintenanceMultiplierBasisPoints: Int64 = 17_500,
        highSpeedTrackUpkeepMultiplierBasisPoints: Int64 = 20_000,
        premiumStationUpkeepPencePerDay: Int64 = 500_000
    ) {
        self.baseFarePencePerJourney = baseFarePencePerJourney
        self.farePencePerPassengerKilometre = farePencePerPassengerKilometre
        self.serviceHoursPerDay = serviceHoursPerDay
        self.directionCount = directionCount
        self.energyCostPencePerTrainKilometre = energyCostPencePerTrainKilometre
        self.variableRollingStockMaintenancePencePerTrainKilometre =
            variableRollingStockMaintenancePencePerTrainKilometre
        self.fixedRollingStockMaintenancePencePerAssignedTrainPerDay =
            fixedRollingStockMaintenancePencePerAssignedTrainPerDay
        self.trackUpkeepPencePerKilometrePerDay = trackUpkeepPencePerKilometrePerDay
        self.stationUpkeepPencePerDayByLevel = stationUpkeepPencePerDayByLevel
        self.highSpeedFareMultiplierBasisPoints = highSpeedFareMultiplierBasisPoints
        self.highSpeedEnergyCostMultiplierBasisPoints =
            highSpeedEnergyCostMultiplierBasisPoints
        self.highSpeedRollingStockMaintenanceMultiplierBasisPoints =
            highSpeedRollingStockMaintenanceMultiplierBasisPoints
        self.highSpeedTrackUpkeepMultiplierBasisPoints =
            highSpeedTrackUpkeepMultiplierBasisPoints
        self.premiumStationUpkeepPencePerDay = premiumStationUpkeepPencePerDay
    }

    static let poc = Self(
        baseFarePencePerJourney: 200,
        farePencePerPassengerKilometre: 12,
        serviceHoursPerDay: 18,
        directionCount: 2,
        energyCostPencePerTrainKilometre: 300,
        variableRollingStockMaintenancePencePerTrainKilometre: 200,
        fixedRollingStockMaintenancePencePerAssignedTrainPerDay: 75_000,
        trackUpkeepPencePerKilometrePerDay: 12_000,
        stationUpkeepPencePerDayByLevel: [
            .halt: 25_000,
            .localStation: 50_000,
            .townStation: 100_000,
            .majorStation: 200_000,
            .interchange: 400_000,
            .terminus: 700_000,
        ]
    )

    func stationUpkeepPencePerDay(for level: StationLevel) -> Int64 {
        max(stationUpkeepPencePerDayByLevel[level] ?? 0, 0)
    }
}

nonisolated struct OperatingEconomy: Sendable {
    let configuration: OperatingEconomyConfiguration

    init(configuration: OperatingEconomyConfiguration = .poc) {
        self.configuration = configuration
    }

    func stationUpkeepPencePerDay(for level: StationLevel) -> Int64 {
        configuration.stationUpkeepPencePerDay(for: level)
    }

    func evaluate(
        lines: [EconomyLineInput],
        stationLevelsByCRS: [String: StationLevel]
    ) -> NetworkOperatingEconomySnapshot {
        guard !lines.isEmpty else { return .zero }

        let canonicalLines = canonicalInputs(lines)
        let normalizedStationLevels = normalizedLevels(stationLevelsByCRS)
        var lineSnapshotsByID: [UUID: LineOperatingEconomySnapshot] = [:]
        var operatingStationCRS = Set<String>()
        var premiumOperatingStationCRS = Set<String>()
        var totalRevenuePencePerDay: Int64 = 0
        var totalHighSpeedFarePremiumPencePerDay: Int64 = 0
        var totalEnergyCostPencePerDay: Int64 = 0
        var totalRollingStockMaintenanceCostPencePerDay: Int64 = 0
        var totalTrainOperatingCostPencePerDay: Int64 = 0
        var totalTrackUpkeepPencePerDay: Int64 = 0

        for line in canonicalLines {
            let snapshot = evaluate(line: line)
            lineSnapshotsByID[line.id] = snapshot
            totalRevenuePencePerDay = SaturatingEconomyArithmetic.add(
                totalRevenuePencePerDay,
                snapshot.revenuePencePerDay
            )
            totalHighSpeedFarePremiumPencePerDay = SaturatingEconomyArithmetic.add(
                totalHighSpeedFarePremiumPencePerDay,
                snapshot.highSpeedFarePremiumPencePerDay
            )
            totalEnergyCostPencePerDay = SaturatingEconomyArithmetic.add(
                totalEnergyCostPencePerDay,
                snapshot.energyCostPencePerDay
            )
            totalRollingStockMaintenanceCostPencePerDay =
                SaturatingEconomyArithmetic.add(
                    totalRollingStockMaintenanceCostPencePerDay,
                    snapshot.rollingStockMaintenanceCostPencePerDay
                )
            totalTrainOperatingCostPencePerDay = SaturatingEconomyArithmetic.add(
                totalTrainOperatingCostPencePerDay,
                snapshot.trainOperatingCostPencePerDay
            )
            totalTrackUpkeepPencePerDay = SaturatingEconomyArithmetic.add(
                totalTrackUpkeepPencePerDay,
                snapshot.trackUpkeepPencePerDay
            )

            guard line.isOperating else { continue }
            operatingStationCRS.formUnion(line.stationCRSs.filter { !$0.isEmpty })
            if line.railwayClass == .highSpeed {
                if !line.originCRS.isEmpty {
                    premiumOperatingStationCRS.insert(line.originCRS)
                }
                if !line.destinationCRS.isEmpty {
                    premiumOperatingStationCRS.insert(line.destinationCRS)
                }
            }
        }

        let baseStationUpkeepPencePerDay = operatingStationCRS.sorted().reduce(Int64(0)) {
            partialResult,
            crs in
            let level = normalizedStationLevels[crs] ?? .halt
            return SaturatingEconomyArithmetic.add(
                partialResult,
                configuration.stationUpkeepPencePerDay(for: level)
            )
        }
        let premiumStationUpkeepPencePerDay = SaturatingEconomyArithmetic.multiply(
            Int64(clamping: premiumOperatingStationCRS.count),
            max(configuration.premiumStationUpkeepPencePerDay, 0)
        )
        let stationUpkeepPencePerDay = SaturatingEconomyArithmetic.add(
            baseStationUpkeepPencePerDay,
            premiumStationUpkeepPencePerDay
        )
        let lineOperatingCostPencePerDay = SaturatingEconomyArithmetic.add(
            totalTrainOperatingCostPencePerDay,
            totalTrackUpkeepPencePerDay
        )
        let totalOperatingCostPencePerDay = SaturatingEconomyArithmetic.add(
            lineOperatingCostPencePerDay,
            stationUpkeepPencePerDay
        )

        return NetworkOperatingEconomySnapshot(
            lineSnapshotsByID: lineSnapshotsByID,
            stationUpkeepPencePerDay: stationUpkeepPencePerDay,
            premiumStationUpkeepPencePerDay: premiumStationUpkeepPencePerDay,
            totalRevenuePencePerDay: totalRevenuePencePerDay,
            totalHighSpeedFarePremiumPencePerDay:
                totalHighSpeedFarePremiumPencePerDay,
            totalEnergyCostPencePerDay: totalEnergyCostPencePerDay,
            totalRollingStockMaintenanceCostPencePerDay:
                totalRollingStockMaintenanceCostPencePerDay,
            totalTrainOperatingCostPencePerDay: totalTrainOperatingCostPencePerDay,
            totalTrackUpkeepPencePerDay: totalTrackUpkeepPencePerDay,
            totalOperatingCostPencePerDay: totalOperatingCostPencePerDay,
            operatingResultPencePerDay: SaturatingEconomyArithmetic.subtract(
                totalRevenuePencePerDay,
                totalOperatingCostPencePerDay
            )
        )
    }

    private func evaluate(line: EconomyLineInput) -> LineOperatingEconomySnapshot {
        guard line.isOperating else { return .zero(id: line.id) }

        let distanceMetres = max(line.distanceMetres, 0)
        let passengerJourneysPerDay = Int64(
            clamping: max(line.passengerJourneysPerDay, 0)
        )
        let baseFareRevenuePencePerDay = SaturatingEconomyArithmetic.multiply(
            max(configuration.baseFarePencePerJourney, 0),
            passengerJourneysPerDay
        )
        let passengerMetresPerDay = line.passengerMetresPerDay.map { max($0, 0) }
            ?? SaturatingEconomyArithmetic.multiply(distanceMetres, passengerJourneysPerDay)
        let distanceFareRevenuePencePerDay = SaturatingEconomyArithmetic.pence(
            forMetres: passengerMetresPerDay,
            ratePerKilometre: max(configuration.farePencePerPassengerKilometre, 0)
        )
        let conventionalRevenuePencePerDay = SaturatingEconomyArithmetic.add(
            baseFareRevenuePencePerDay,
            distanceFareRevenuePencePerDay
        )
        let highSpeedFarePremiumPencePerDay: Int64
        if line.railwayClass == .highSpeed {
            let fareMultiplier = max(
                configuration.highSpeedFareMultiplierBasisPoints,
                10_000
            )
            highSpeedFarePremiumPencePerDay = SaturatingEconomyArithmetic.scaled(
                conventionalRevenuePencePerDay,
                multiplier: fareMultiplier - 10_000,
                divisor: 10_000
            )
        } else {
            highSpeedFarePremiumPencePerDay = 0
        }
        let revenuePencePerDay = SaturatingEconomyArithmetic.add(
            conventionalRevenuePencePerDay,
            highSpeedFarePremiumPencePerDay
        )

        let oneWayTripsPerDay = SaturatingEconomyArithmetic.multiply(
            SaturatingEconomyArithmetic.multiply(
                Int64(line.frequency.departuresPerHour),
                max(configuration.serviceHoursPerDay, 0)
            ),
            max(configuration.directionCount, 0)
        )
        let normalizedFormation = line.formation.clamped(for: line.railwayClass)
        let energyCostPencePerTrip = SaturatingEconomyArithmetic.pence(
            forMetres: distanceMetres,
            ratePerKilometre: max(
                configuration.energyCostPencePerTrainKilometre,
                0
            )
        )
        let sixCarEnergyCostPencePerDay = SaturatingEconomyArithmetic.multiply(
            energyCostPencePerTrip,
            oneWayTripsPerDay
        )
        let formationEnergyCostPencePerDay = formationScaled(
            sixCarEnergyCostPencePerDay,
            formation: normalizedFormation
        )
        let energyCostPencePerDay = classScaled(
            formationEnergyCostPencePerDay,
            for: line.railwayClass,
            highSpeedMultiplierBasisPoints:
                configuration.highSpeedEnergyCostMultiplierBasisPoints
        )
        let variableMaintenancePencePerTrip = SaturatingEconomyArithmetic.pence(
            forMetres: distanceMetres,
            ratePerKilometre: max(
                configuration.variableRollingStockMaintenancePencePerTrainKilometre,
                0
            )
        )
        let sixCarVariableMaintenancePencePerDay = SaturatingEconomyArithmetic.multiply(
            variableMaintenancePencePerTrip,
            oneWayTripsPerDay
        )
        let variableMaintenancePencePerDay = formationScaled(
            sixCarVariableMaintenancePencePerDay,
            formation: normalizedFormation
        )
        let fixedMaintenancePencePerDay = SaturatingEconomyArithmetic.multiply(
            Int64(line.frequency.visibleTrainCount),
            max(
                configuration.fixedRollingStockMaintenancePencePerAssignedTrainPerDay,
                0
            )
        )
        let conventionalRollingStockMaintenancePencePerDay =
            SaturatingEconomyArithmetic.add(
            variableMaintenancePencePerDay,
            fixedMaintenancePencePerDay
        )
        let rollingStockMaintenanceCostPencePerDay = classScaled(
            conventionalRollingStockMaintenancePencePerDay,
            for: line.railwayClass,
            highSpeedMultiplierBasisPoints:
                configuration.highSpeedRollingStockMaintenanceMultiplierBasisPoints
        )
        let trainOperatingCostPencePerDay = SaturatingEconomyArithmetic.add(
            energyCostPencePerDay,
            rollingStockMaintenanceCostPencePerDay
        )
        let baseTrackUpkeepPencePerDay = SaturatingEconomyArithmetic.pence(
            forMetres: distanceMetres,
            ratePerKilometre: max(
                configuration.trackUpkeepPencePerKilometrePerDay,
                0
            )
        )
        let trackUpkeepPencePerDay: Int64
        if line.railwayClass == .highSpeed {
            // The high-speed multiplier already represents its mandatory dedicated double
            // track, so the conventional capacity multiplier must not be charged again.
            trackUpkeepPencePerDay = SaturatingEconomyArithmetic.scaled(
                baseTrackUpkeepPencePerDay,
                multiplier: max(
                    configuration.highSpeedTrackUpkeepMultiplierBasisPoints,
                    0
                ),
                divisor: 10_000
            )
        } else {
            trackUpkeepPencePerDay = SaturatingEconomyArithmetic.scaled(
                baseTrackUpkeepPencePerDay,
                multiplier: max(
                    line.trackCapacity.maintenanceMultiplierBasisPoints,
                    0
                ),
                divisor: 10_000
            )
        }
        let totalOperatingCostPencePerDay = SaturatingEconomyArithmetic.add(
            trainOperatingCostPencePerDay,
            trackUpkeepPencePerDay
        )

        return LineOperatingEconomySnapshot(
            id: line.id,
            revenuePencePerDay: revenuePencePerDay,
            highSpeedFarePremiumPencePerDay: highSpeedFarePremiumPencePerDay,
            energyCostPencePerDay: energyCostPencePerDay,
            rollingStockMaintenanceCostPencePerDay:
                rollingStockMaintenanceCostPencePerDay,
            trainOperatingCostPencePerDay: trainOperatingCostPencePerDay,
            trackUpkeepPencePerDay: trackUpkeepPencePerDay,
            totalOperatingCostPencePerDay: totalOperatingCostPencePerDay,
            operatingResultPencePerDay: SaturatingEconomyArithmetic.subtract(
                revenuePencePerDay,
                totalOperatingCostPencePerDay
            )
        )
    }

    /// Duplicate IDs are invalid upstream, but selecting a canonical representation keeps this
    /// pure engine deterministic and non-crashing if malformed inputs reach it.
    private func canonicalInputs(_ lines: [EconomyLineInput]) -> [EconomyLineInput] {
        var linesByID: [UUID: EconomyLineInput] = [:]
        for line in lines {
            guard let current = linesByID[line.id] else {
                linesByID[line.id] = line
                continue
            }
            if canonicalPrecedes(line, current) {
                linesByID[line.id] = line
            }
        }
        return linesByID.values.sorted(by: canonicalPrecedes)
    }

    private func canonicalPrecedes(
        _ lhs: EconomyLineInput,
        _ rhs: EconomyLineInput
    ) -> Bool {
        if lhs.id != rhs.id { return lhs.id.uuidString < rhs.id.uuidString }
        if lhs.originCRS != rhs.originCRS { return lhs.originCRS < rhs.originCRS }
        if lhs.destinationCRS != rhs.destinationCRS {
            return lhs.destinationCRS < rhs.destinationCRS
        }
        if lhs.stationCRSs != rhs.stationCRSs {
            return lhs.stationCRSs.lexicographicallyPrecedes(rhs.stationCRSs)
        }
        if lhs.distanceMetres != rhs.distanceMetres {
            return lhs.distanceMetres < rhs.distanceMetres
        }
        if lhs.frequency != rhs.frequency {
            return lhs.frequency.rawValue < rhs.frequency.rawValue
        }
        if lhs.trackCapacity != rhs.trackCapacity {
            return lhs.trackCapacity.rawValue < rhs.trackCapacity.rawValue
        }
        if lhs.railwayClass != rhs.railwayClass {
            return lhs.railwayClass.rawValue < rhs.railwayClass.rawValue
        }
        if lhs.formation != rhs.formation {
            return lhs.formation.carriageCount < rhs.formation.carriageCount
        }
        if lhs.passengerJourneysPerDay != rhs.passengerJourneysPerDay {
            return lhs.passengerJourneysPerDay < rhs.passengerJourneysPerDay
        }
        if lhs.passengerMetresPerDay != rhs.passengerMetresPerDay {
            return (lhs.passengerMetresPerDay ?? .max)
                < (rhs.passengerMetresPerDay ?? .max)
        }
        if lhs.isOperating != rhs.isOperating { return !lhs.isOperating }
        return false
    }

    private func classScaled(
        _ value: Int64,
        for railwayClass: RailwayClass,
        highSpeedMultiplierBasisPoints: Int64
    ) -> Int64 {
        guard railwayClass == .highSpeed else { return value }
        return SaturatingEconomyArithmetic.scaled(
            value,
            multiplier: max(highSpeedMultiplierBasisPoints, 0),
            divisor: 10_000
        )
    }

    private func formationScaled(
        _ sixCarValue: Int64,
        formation: RollingStockFormation
    ) -> Int64 {
        SaturatingEconomyArithmetic.scaled(
            sixCarValue,
            multiplier: Int64(formation.carriageCount),
            divisor: Int64(RollingStockFormation.legacyBaseline.carriageCount)
        )
    }

    private func normalizedLevels(
        _ levelsByCRS: [String: StationLevel]
    ) -> [String: StationLevel] {
        var normalized: [String: StationLevel] = [:]
        for (rawCRS, level) in levelsByCRS.sorted(by: { $0.key < $1.key }) {
            let crs = rawCRS
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            guard !crs.isEmpty else { continue }
            if let existing = normalized[crs] {
                normalized[crs] = max(existing, level)
            } else {
                normalized[crs] = level
            }
        }
        return normalized
    }
}

private nonisolated enum SaturatingEconomyArithmetic {
    private static let metresPerKilometre: Int64 = 1_000

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

    /// Applies a positive fixed-point multiplier without overflowing the intermediate product.
    /// Fractional pence are truncated consistently with the existing per-kilometre arithmetic.
    static func scaled(_ value: Int64, multiplier: Int64, divisor: Int64) -> Int64 {
        guard value > 0, multiplier > 0, divisor > 0 else { return 0 }

        let unsignedDivisor = UInt64(divisor)
        let product = UInt64(value).multipliedFullWidth(by: UInt64(multiplier))
        guard product.high < unsignedDivisor else { return .max }
        let quotient = unsignedDivisor.dividingFullWidth(product).quotient
        guard quotient <= UInt64(Int64.max) else { return .max }
        return Int64(quotient)
    }

    /// Calculates whole pence for a metre quantity at a pence-per-kilometre rate without
    /// overflowing the intermediate metre-rate product. Fractional pence are truncated.
    static func pence(forMetres metres: Int64, ratePerKilometre: Int64) -> Int64 {
        guard metres > 0, ratePerKilometre > 0 else { return 0 }

        let wholeKilometres = metres / metresPerKilometre
        let remainingMetres = metres % metresPerKilometre
        let wholePence = multiply(wholeKilometres, ratePerKilometre)
        guard wholePence != .max else { return .max }

        let wholePencePerMetre = ratePerKilometre / metresPerKilometre
        let remainingRate = ratePerKilometre % metresPerKilometre
        let partialPence = add(
            multiply(remainingMetres, wholePencePerMetre),
            multiply(remainingMetres, remainingRate) / metresPerKilometre
        )
        return add(wholePence, partialPence)
    }
}
