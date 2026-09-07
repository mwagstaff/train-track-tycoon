import Foundation

/// A purchasable train length shared by capacity, economy and map presentation.
///
/// The proof of concept deliberately offers only even formations. Keeping the supported values
/// finite makes save migration and purchase controls deterministic, while the six-car default
/// preserves the passenger model's original 240-seat trains.
nonisolated enum RollingStockFormation: Int, CaseIterable, Codable, Equatable, Hashable,
    Sendable, Identifiable {
    case twoCar = 2
    case fourCar = 4
    case sixCar = 6
    case eightCar = 8
    case tenCar = 10
    case twelveCar = 12

    static let seatsPerCarriage = 40
    static let legacyBaseline = RollingStockFormation.sixCar

    var id: Int { rawValue }
    var carriageCount: Int { rawValue }
    var seatsPerTrain: Int { carriageCount * Self.seatsPerCarriage }

    static func supported(for railwayClass: RailwayClass) -> [Self] {
        switch railwayClass {
        case .conventional:
            allCases
        case .highSpeed:
            allCases.filter { $0.carriageCount >= 6 }
        }
    }

    /// Returns the nearest supported formation. Equal-distance ties prefer the smaller train.
    func clamped(for railwayClass: RailwayClass) -> Self {
        Self.supported(for: railwayClass).min { lhs, rhs in
            let lhsDistance = abs(lhs.carriageCount - carriageCount)
            let rhsDistance = abs(rhs.carriageCount - carriageCount)
            if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
            return lhs.carriageCount < rhs.carriageCount
        } ?? .legacyBaseline
    }

    func next(for railwayClass: RailwayClass) -> Self? {
        Self.supported(for: railwayClass).first { $0.carriageCount > carriageCount }
    }
}

/// Pure formation selection rules. Recommendations size the peak timetable to an 80% target load
/// and never influence an already purchased formation.
nonisolated struct RollingStockFormationPolicy: Equatable, Sendable {
    static let targetPeakLoadPercent = 80

    func supportedFormations(for railwayClass: RailwayClass) -> [RollingStockFormation] {
        RollingStockFormation.supported(for: railwayClass)
    }

    func clamp(
        _ formation: RollingStockFormation,
        for railwayClass: RailwayClass
    ) -> RollingStockFormation {
        formation.clamped(for: railwayClass)
    }

    func next(
        after formation: RollingStockFormation,
        for railwayClass: RailwayClass
    ) -> RollingStockFormation? {
        formation.next(for: railwayClass)
    }

    /// Selects the smallest formation whose scheduled peak trains can carry the attracted peak
    /// demand at no more than the target load. A positive demand without a valid departure count
    /// safely recommends the largest train; demand beyond twelve-car capacity is likewise capped.
    func recommend(
        attractedPeakDemand: Int,
        departuresDuringPeak: Int,
        railwayClass: RailwayClass
    ) -> RollingStockFormation {
        let supported = supportedFormations(for: railwayClass)
        guard let minimum = supported.first, let maximum = supported.last else {
            return .legacyBaseline
        }

        let demand = max(attractedPeakDemand, 0)
        guard demand > 0 else { return minimum }
        let departures = max(departuresDuringPeak, 0)
        guard departures > 0 else { return maximum }

        for formation in supported {
            let targetPassengersPerTrain = formation.seatsPerTrain
                * Self.targetPeakLoadPercent / 100
            let targetCapacity = saturatedProduct(targetPassengersPerTrain, departures)
            if targetCapacity >= demand { return formation }
        }
        return maximum
    }

    /// Spelling-friendly alias for call sites that model the result as a value rather than action.
    func recommendedFormation(
        attractedPeakDemand: Int,
        departuresDuringPeak: Int,
        railwayClass: RailwayClass
    ) -> RollingStockFormation {
        recommend(
            attractedPeakDemand: attractedPeakDemand,
            departuresDuringPeak: departuresDuringPeak,
            railwayClass: railwayClass
        )
    }

    private func saturatedProduct(_ lhs: Int, _ rhs: Int) -> Int {
        let product = lhs.multipliedReportingOverflow(by: rhs)
        return product.overflow ? .max : max(product.partialValue, 0)
    }
}

/// The amount of train detail that should be drawn at the current map scale.
nonisolated enum TrainMapDetailLevel: Equatable, Sendable {
    case compact
    case formation
}

/// Stable, presentation-facing facts for one visible train formation.
nonisolated struct TrainFormationSnapshot: Equatable, Sendable {
    let carriageCount: Int
    let estimatedPeakPassengers: Int
    let peakOccupancyRatio: Double
}

/// Pure rules for presenting a train's formation on the map.
///
/// A purchased formation is authoritative and always renders its exact carriage count. The
/// demand-and-distance heuristic remains only as a source-compatible fallback for legacy callers
/// that do not yet supply owned rolling stock.
nonisolated struct TrainFormationPolicy: Equatable, Sendable {
    static let formationEnterCameraDistanceMetres = 9_000.0
    static let formationExitCameraDistanceMetres = 12_000.0

    private static let passengerWeight = 0.65
    private static let distanceWeight = 0.35

    func evaluate(
        serviceRole: TrainServiceRole,
        railwayClass: RailwayClass,
        routeDistanceKilometres rawRouteDistanceKilometres: Double,
        peakOccupancyRatio rawPeakOccupancyRatio: Double,
        nominalTrainCapacity rawNominalTrainCapacity: Int,
        purchasedFormation: RollingStockFormation? = nil
    ) -> TrainFormationSnapshot {
        let occupancy = normalizedRatio(rawPeakOccupancyRatio)
        let routeDistanceKilometres = normalizedNonnegative(rawRouteDistanceKilometres)
        let nominalTrainCapacity = purchasedFormation?.seatsPerTrain
            ?? max(rawNominalTrainCapacity, 0)

        if let purchasedFormation {
            return TrainFormationSnapshot(
                carriageCount: purchasedFormation.carriageCount,
                estimatedPeakPassengers: estimatedPassengerCount(
                    occupancy: occupancy,
                    nominalCapacity: nominalTrainCapacity
                ),
                peakOccupancyRatio: occupancy
            )
        }

        let range = formationRange(
            serviceRole: serviceRole,
            railwayClass: railwayClass
        )
        let distanceRatio = min(routeDistanceKilometres / range.distanceReferenceKilometres, 1)
        let formationScore = Self.passengerWeight * occupancy
            + Self.distanceWeight * distanceRatio
        let availableSteps = (range.maximumCarriages - range.minimumCarriages) / 2
        let selectedStep = min(
            max(Int((formationScore * Double(availableSteps)).rounded()), 0),
            availableSteps
        )
        let carriageCount = range.minimumCarriages + selectedStep * 2

        return TrainFormationSnapshot(
            carriageCount: carriageCount,
            estimatedPeakPassengers: estimatedPassengerCount(
                occupancy: occupancy,
                nominalCapacity: nominalTrainCapacity
            ),
            peakOccupancyRatio: occupancy
        )
    }

    /// Applies two thresholds so a train does not repeatedly change representation while the
    /// player pinches around one camera distance.
    func detailLevel(
        after currentLevel: TrainMapDetailLevel,
        cameraDistanceMetres: Double
    ) -> TrainMapDetailLevel {
        guard cameraDistanceMetres.isFinite, cameraDistanceMetres >= 0 else {
            return currentLevel
        }

        switch currentLevel {
        case .compact:
            return cameraDistanceMetres <= Self.formationEnterCameraDistanceMetres
                ? .formation
                : .compact
        case .formation:
            return cameraDistanceMetres >= Self.formationExitCameraDistanceMetres
                ? .compact
                : .formation
        }
    }

    private func formationRange(
        serviceRole: TrainServiceRole,
        railwayClass: RailwayClass
    ) -> FormationRange {
        if railwayClass == .highSpeed {
            return FormationRange(
                minimumCarriages: 6,
                maximumCarriages: 12,
                distanceReferenceKilometres: 450
            )
        }

        switch serviceRole {
        case .local:
            return FormationRange(
                minimumCarriages: 2,
                maximumCarriages: 6,
                distanceReferenceKilometres: 80
            )
        case .express:
            return FormationRange(
                minimumCarriages: 4,
                maximumCarriages: 12,
                distanceReferenceKilometres: 250
            )
        }
    }

    private func normalizedRatio(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private func normalizedNonnegative(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return max(value, 0)
    }

    private func estimatedPassengerCount(
        occupancy: Double,
        nominalCapacity: Int
    ) -> Int {
        guard occupancy > 0, nominalCapacity > 0 else { return 0 }
        let estimate = occupancy * Double(nominalCapacity)
        guard estimate.isFinite, estimate < Double(Int.max) else { return .max }
        return max(Int(estimate.rounded()), 0)
    }
}

private nonisolated struct FormationRange: Equatable, Sendable {
    let minimumCarriages: Int
    let maximumCarriages: Int
    let distanceReferenceKilometres: Double
}
