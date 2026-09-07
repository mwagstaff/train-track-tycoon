import CoreLocation
import Foundation

/// Gameplay limits for automatically generated regional stopping services.
///
/// These are deliberately service-planning values rather than animation values. A long route can
/// still be animated quickly, while its default Local trains remain credible regional workings.
nonisolated struct AutomaticServicePlanningConfiguration: Equatable, Sendable {
    let planningSpeedKilometresPerHour: Double
    let intermediateCallDuration: TimeInterval
    let preferredOneWayDuration: TimeInterval
    let maximumOneWayDuration: TimeInterval
    let maximumDistanceMetres: CLLocationDistance
    let maximumCallsPerLocalZone: Int

    static let standard = Self(
        planningSpeedKilometresPerHour: 75,
        intermediateCallDuration: 75,
        preferredOneWayDuration: 60 * 60,
        maximumOneWayDuration: 75 * 60,
        maximumDistanceMetres: 90_000,
        maximumCallsPerLocalZone: 12
    )
}

/// One complete automatic service plan over an ordered physical railway.
///
/// `representativePlans` remains compatible with the four visible M16 timetable slots. The full
/// `localZones` collection is consumed by passenger and station-capacity simulation, so every
/// feasible station can receive the advertised regional service without creating a map sprite for
/// every physical train that would be required in the real world.
nonisolated struct AutomaticServicePlanningResult: Equatable, Sendable {
    let representativePlans: [TrainServicePlan]
    let localZones: [[String]]
    let unbridgeableStationPairs: [[String]]
}

/// Deterministically partitions long all-stop routes into bounded, overlapping regional zones.
///
/// The dynamic programme considers at most `maximumCallsPerLocalZone` next stations from each
/// boundary, keeping work linear for national routes. Adjacent zones share exactly one terminal so
/// passengers can change there. Express plans intentionally have no distance limit.
nonisolated struct AutomaticServicePlanner: Sendable {
    let configuration: AutomaticServicePlanningConfiguration

    init(configuration: AutomaticServicePlanningConfiguration = .standard) {
        self.configuration = configuration
    }

    func plan(
        servicePattern: ServicePattern,
        stationCRSs rawStationCRSs: [String],
        cumulativeDistancesMetres rawDistances: [CLLocationDistance],
        slotCount: Int = 4
    ) -> AutomaticServicePlanningResult {
        let stationCRSs = rawStationCRSs.map(normalizedCRS)
        let fallback = TrainServicePlan.legacyDefaults(
            servicePattern: servicePattern,
            serviceStationCRSs: stationCRSs,
            slotCount: slotCount
        )
        guard stationCRSs.count >= 2,
              stationCRSs.allSatisfy({ !$0.isEmpty }),
              Set(stationCRSs).count == stationCRSs.count,
              rawDistances.count == stationCRSs.count,
              validDistances(rawDistances) else {
            return AutomaticServicePlanningResult(
                representativePlans: fallback,
                localZones: servicePattern == .express ? [] : [stationCRSs],
                unbridgeableStationPairs: []
            )
        }

        // An Express-only timetable is intentionally unrestricted and has no regional Local
        // workings to plan. Besides keeping the result semantically consistent with the invalid
        // input fallback and high-speed path, this avoids even bounded partition work when a
        // player switches a long national service to Express.
        if servicePattern == .express {
            return AutomaticServicePlanningResult(
                representativePlans: fallback,
                localZones: [],
                unbridgeableStationPairs: []
            )
        }

        // Canonical orientation ensures that reversing the same physical railway produces the
        // exact reverse of its established boundaries instead of a different partition.
        let usesForwardCanonicalOrder = (stationCRSs.first ?? "") <= (stationCRSs.last ?? "")
        let canonicalCRSs: [String]
        let canonicalDistances: [CLLocationDistance]
        if usesForwardCanonicalOrder {
            canonicalCRSs = stationCRSs
            canonicalDistances = rawDistances
        } else {
            let total = rawDistances.last ?? 0
            canonicalCRSs = Array(stationCRSs.reversed())
            canonicalDistances = rawDistances.reversed().map { total - $0 }
        }

        let partition = partitionIntoLocalZones(
            stationCRSs: canonicalCRSs,
            cumulativeDistancesMetres: canonicalDistances
        )
        let localZones = usesForwardCanonicalOrder
            ? partition.zones
            : partition.zones.reversed().map { Array($0.reversed()) }
        let unbridgeablePairs = usesForwardCanonicalOrder
            ? partition.unbridgeablePairs
            : partition.unbridgeablePairs.reversed().map { Array($0.reversed()) }
        let terminalCRSs = [stationCRSs.first, stationCRSs.last].compactMap { $0 }

        let legacyRoles = fallback.map(\.role)
        let localSlotIndices = legacyRoles.indices.filter { legacyRoles[$0] == .local }
        var representativePlans = fallback
        for (ordinal, slotIndex) in localSlotIndices.enumerated() {
            guard !localZones.isEmpty else {
                // A sparse route with no feasible regional section must never masquerade as a
                // Local train. It remains a valid unrestricted Express until stations are added.
                representativePlans[slotIndex] = TrainServicePlan(
                    slotIndex: slotIndex,
                    role: .express,
                    stationCRSs: terminalCRSs
                )
                continue
            }
            let zoneIndex = representativeZoneIndex(
                ordinal: ordinal,
                representativeCount: localSlotIndices.count,
                zoneCount: localZones.count
            )
            representativePlans[slotIndex] = TrainServicePlan(
                slotIndex: slotIndex,
                role: .local,
                stationCRSs: localZones[zoneIndex]
            )
        }
        for index in representativePlans.indices where representativePlans[index].role == .express {
            representativePlans[index].stationCRSs = terminalCRSs
        }

        return AutomaticServicePlanningResult(
            representativePlans: representativePlans,
            localZones: localZones,
            unbridgeableStationPairs: unbridgeablePairs
        )
    }

    func estimatedLocalJourneyDuration(
        distanceMetres: CLLocationDistance,
        callCount: Int
    ) -> TimeInterval {
        guard distanceMetres.isFinite, distanceMetres >= 0 else { return .infinity }
        let speed = configuration.planningSpeedKilometresPerHour
        guard speed.isFinite, speed > 0 else { return .infinity }
        let runningSeconds = distanceMetres * 3.6 / speed
        let dwellSeconds = Double(max(callCount - 2, 0))
            * max(configuration.intermediateCallDuration, 0)
        let result = ceil(runningSeconds) + dwellSeconds
        return result.isFinite ? result : .infinity
    }

    func isValidLocalZone(
        distanceMetres: CLLocationDistance,
        callCount: Int
    ) -> Bool {
        guard callCount >= 2,
              callCount <= max(configuration.maximumCallsPerLocalZone, 2),
              distanceMetres.isFinite,
              distanceMetres >= 0,
              distanceMetres <= max(configuration.maximumDistanceMetres, 0) else {
            return false
        }
        return estimatedLocalJourneyDuration(
            distanceMetres: distanceMetres,
            callCount: callCount
        ) <= max(configuration.maximumOneWayDuration, 0)
    }

    private func partitionIntoLocalZones(
        stationCRSs: [String],
        cumulativeDistancesMetres: [CLLocationDistance]
    ) -> (zones: [[String]], unbridgeablePairs: [[String]]) {
        var componentStart = 0
        var zones = [[String]]()
        var unbridgeablePairs = [[String]]()

        for upperIndex in 1..<stationCRSs.count {
            let adjacentDistance = cumulativeDistancesMetres[upperIndex]
                - cumulativeDistancesMetres[upperIndex - 1]
            guard !isValidLocalZone(distanceMetres: adjacentDistance, callCount: 2) else {
                continue
            }
            zones.append(contentsOf: optimalZones(
                stationCRSs: stationCRSs,
                cumulativeDistancesMetres: cumulativeDistancesMetres,
                lowerBound: componentStart,
                upperBound: upperIndex - 1
            ))
            unbridgeablePairs.append([
                stationCRSs[upperIndex - 1],
                stationCRSs[upperIndex],
            ])
            componentStart = upperIndex
        }
        zones.append(contentsOf: optimalZones(
            stationCRSs: stationCRSs,
            cumulativeDistancesMetres: cumulativeDistancesMetres,
            lowerBound: componentStart,
            upperBound: stationCRSs.count - 1
        ))
        return (zones, unbridgeablePairs)
    }

    private func optimalZones(
        stationCRSs: [String],
        cumulativeDistancesMetres: [CLLocationDistance],
        lowerBound: Int,
        upperBound: Int
    ) -> [[String]] {
        guard lowerBound >= 0,
              upperBound < stationCRSs.count,
              lowerBound < upperBound else { return [] }

        var best = [Int: PlannerCandidate]()
        best[lowerBound] = PlannerCandidate(cost: 0, zoneCount: 0, previousIndex: -1)
        let maximumCalls = max(configuration.maximumCallsPerLocalZone, 2)

        for start in lowerBound..<upperBound {
            guard let prefix = best[start] else { continue }
            let latestEnd = min(upperBound, start + maximumCalls - 1)
            guard latestEnd > start else { continue }
            for end in (start + 1)...latestEnd {
                let distance = cumulativeDistancesMetres[end]
                    - cumulativeDistancesMetres[start]
                let callCount = end - start + 1
                guard isValidLocalZone(distanceMetres: distance, callCount: callCount) else {
                    // Distance, duration and calls only grow as the candidate endpoint advances.
                    break
                }
                let duration = estimatedLocalJourneyDuration(
                    distanceMetres: distance,
                    callCount: callCount
                )
                let target = max(configuration.preferredOneWayDuration, 1)
                let normalizedDeviation = (duration - target) / target
                let candidate = PlannerCandidate(
                    cost: prefix.cost + 1 + normalizedDeviation * normalizedDeviation,
                    zoneCount: prefix.zoneCount + 1,
                    previousIndex: start
                )
                if candidateIsPreferred(candidate, over: best[end]) {
                    best[end] = candidate
                }
            }
        }

        guard best[upperBound] != nil else { return [] }
        var boundaries = [upperBound]
        var cursor = upperBound
        while cursor > lowerBound, let candidate = best[cursor] {
            cursor = candidate.previousIndex
            guard cursor >= lowerBound else { return [] }
            boundaries.append(cursor)
        }
        guard cursor == lowerBound else { return [] }
        boundaries.reverse()

        return zip(boundaries, boundaries.dropFirst()).map { start, end in
            Array(stationCRSs[start...end])
        }
    }

    private func candidateIsPreferred(
        _ candidate: PlannerCandidate,
        over existing: PlannerCandidate?
    ) -> Bool {
        guard let existing else { return true }
        let epsilon = 0.000_000_001
        if abs(candidate.cost - existing.cost) > epsilon {
            return candidate.cost < existing.cost
        }
        if candidate.zoneCount != existing.zoneCount {
            return candidate.zoneCount < existing.zoneCount
        }
        // Prefer the longer final zone as the last deterministic tie-break. Because planning is
        // canonicalised first, reversing a line cannot change this choice.
        return candidate.previousIndex < existing.previousIndex
    }

    private func representativeZoneIndex(
        ordinal: Int,
        representativeCount: Int,
        zoneCount: Int
    ) -> Int {
        guard zoneCount > 1, representativeCount > 1 else {
            return zoneCount <= 1 ? 0 : zoneCount / 2
        }
        let progress = Double(ordinal) / Double(representativeCount - 1)
        return min(max(Int((progress * Double(zoneCount - 1)).rounded()), 0), zoneCount - 1)
    }

    private func validDistances(_ distances: [CLLocationDistance]) -> Bool {
        guard let first = distances.first,
              first.isFinite,
              abs(first) <= 0.001 else { return false }
        var previous = first
        for distance in distances.dropFirst() {
            guard distance.isFinite, distance > previous else { return false }
            previous = distance
        }
        return true
    }

    private func normalizedCRS(_ crs: String) -> String {
        crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

// File-scope comparison storage avoids exposing the planner's internal dynamic-programming type.
private nonisolated struct PlannerCandidate: Sendable {
    let cost: Double
    let zoneCount: Int
    let previousIndex: Int
}
