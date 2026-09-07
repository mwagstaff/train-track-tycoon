import CoreLocation
import Foundation

/// A compatible adjacent service that can be merged into one through service.
///
/// The option is deliberately a presentation-safe value rather than a mutation token. The game
/// session revalidates the live network when the player confirms, so stale UI cannot join services
/// after one of their operating settings has changed.
nonisolated struct ThroughServiceOption: Identifiable, Equatable, Sendable {
    var id: UUID { candidateLineID }

    let primaryLineID: UUID
    let candidateLineID: UUID
    let primaryLineNumber: Int
    let candidateLineNumber: Int
    let primaryCorridorCount: Int
    let candidateCorridorCount: Int
    let resultingCorridorCount: Int
    let originCRS: String
    let originName: String
    let junctionCRS: String
    let junctionName: String
    let destinationCRS: String
    let destinationName: String
    let stationCRSs: [String]
    let stationNames: [String]
    let primaryOwnedTrainCount: Int
    let candidateOwnedTrainCount: Int
    let resultingOwnedTrainCount: Int
    let activeTrainCount: Int
    let primaryFrequency: ServiceFrequency
    let candidateFrequency: ServiceFrequency
    let primaryServicePattern: ServicePattern
    let candidateServicePattern: ServicePattern
    let primaryFormation: RollingStockFormation
    let candidateFormation: RollingStockFormation
    let primaryTrackCapacity: TrackCapacity
    let candidateTrackCapacity: TrackCapacity
    /// The primary service's timetable is retained when the services are joined.
    let frequency: ServiceFrequency
    /// The primary service's stopping pattern is retained when the services are joined.
    let servicePattern: ServicePattern
    /// The longer of the two purchased formations. Shorter stock is extended, never downgraded.
    let formation: RollingStockFormation
    /// The stronger of the two physical corridors. Weaker infrastructure is upgraded.
    let trackCapacity: TrackCapacity
    /// True when Line `primaryLineNumber` keeps its four exact per-train stopping plans.
    /// Untouched fleet presets instead expand across the enlarged through route.
    let preservesPrimaryCustomServicePlans: Bool
    let automaticChanges: [ThroughServiceAutomaticChange]
    let capitalQuote: CapitalPurchaseQuote
    var canAfford: Bool
    var fundingShortfallPence: Int64
}

/// One explicit, presentation-safe change included in a through-service reconciliation quote.
/// Operating-setting changes are free; asset changes carry their incremental purchase price.
nonisolated enum ThroughServiceAutomaticChange: Equatable, Sendable {
    case serviceFrequency(
        lineID: UUID,
        lineNumber: Int,
        from: ServiceFrequency,
        to: ServiceFrequency
    )
    case servicePattern(
        lineID: UUID,
        lineNumber: Int,
        from: ServicePattern,
        to: ServicePattern
    )
    case formation(
        lineID: UUID,
        lineNumber: Int,
        ownedTrainCount: Int,
        from: RollingStockFormation,
        to: RollingStockFormation,
        costPence: Int64
    )
    case trackCapacity(
        lineID: UUID,
        lineNumber: Int,
        corridorID: UUID,
        segmentName: String,
        from: TrackCapacity,
        to: TrackCapacity,
        costPence: Int64
    )
}

/// A stable, presentation-safe explanation of why an adjacent service cannot currently be joined.
nonisolated enum ThroughServiceIncompatibilityReason: String, Equatable, Sendable {
    case incompleteConstruction
    case conventionalServicesOnly
    case alreadyJoinedService
    case frequencyMismatch
    case servicePatternMismatch
    case formationMismatch
    case trackCapacityMismatch
    case overlappingOrBranchedRoute
    case serviceLimitExceeded
    case unavailable
}

nonisolated struct ThroughServiceIncompatibility: Identifiable, Equatable, Sendable {
    var id: UUID { candidateLineID }

    let primaryLineID: UUID
    let candidateLineID: UUID
    let primaryLineNumber: Int
    let candidateLineNumber: Int
    let junctionCRS: String
    let junctionName: String
    let reasons: [ThroughServiceIncompatibilityReason]
}

nonisolated struct ThroughServiceAvailability: Equatable, Sendable {
    let options: [ThroughServiceOption]
    let incompatibilities: [ThroughServiceIncompatibility]

    static let empty = ThroughServiceAvailability(options: [], incompatibilities: [])
}

/// A route-independent orientation of retained physical corridors into one connected chain.
/// GameSession selects passenger calls from this physical result rather than asking the OSM router
/// for a new end-to-end shortest path that could silently leave the player's purchased track.
nonisolated struct RailwayCorridorChainAssembly: Sendable {
    let corridorIDs: [UUID]
    let stationCRSs: [String]
    let route: ServiceRailwayRoute
    let distanceMetres: CLLocationDistance
    let indicativeCost: Int64
    let railwayClass: RailwayClass
    let trackCapacity: TrackCapacity
    let constructionProgress: Double
}

nonisolated enum RailwayCorridorChainAssembler {
    /// Returns the at-most-two physical orientations of an ordered corridor collection.
    static func assemblies(for corridors: [RailwayCorridor]) -> [RailwayCorridorChainAssembly] {
        guard let first = corridors.first,
              corridors.allSatisfy({ corridorIsUsable($0) }),
              Set(corridors.map(\.id)).count == corridors.count,
              corridors.allSatisfy({ $0.railwayClass == first.railwayClass }),
              corridors.allSatisfy({ $0.trackCapacity == first.trackCapacity }) else {
            return []
        }

        return [false, true].compactMap { firstIsReversed in
            var oriented = [orientedCorridor(first, isReversed: firstIsReversed)]
            for corridor in corridors.dropFirst() {
                guard let joiningCRS = oriented.last?.stationCRSs.last else { return nil }
                let normalized = corridor.stationCRSs.map(normalizedCRS)
                let isReversed: Bool
                if normalized.first == joiningCRS {
                    isReversed = false
                } else if normalized.last == joiningCRS {
                    isReversed = true
                } else {
                    return nil
                }
                oriented.append(orientedCorridor(corridor, isReversed: isReversed))
            }

            guard let chain = concatenate(oriented) else { return nil }
            return RailwayCorridorChainAssembly(
                corridorIDs: corridors.map(\.id),
                stationCRSs: chain.stationCRSs,
                route: chain.route,
                distanceMetres: chain.route.totalLength,
                indicativeCost: corridors.reduce(0) {
                    saturatingAdd($0, max($1.indicativeCost, 0))
                },
                railwayClass: first.railwayClass,
                trackCapacity: first.trackCapacity,
                constructionProgress: corridors.reduce(1) {
                    min($0, min(max($1.constructionProgress, 0), 1))
                }
            )
        }
    }

    static func reversedRoute(_ route: ServiceRailwayRoute) -> ServiceRailwayRoute {
        guard !route.coordinates.isEmpty else { return route }
        let finalIndex = route.coordinates.count - 1
        let totalLength = route.totalLength
        return ServiceRailwayRoute(
            coordinates: Array(route.coordinates.reversed()),
            cumulativeDistances: route.cumulativeDistances.reversed().map {
                totalLength - $0
            },
            stationCoordinateIndices: route.stationCoordinateIndices.reversed().map {
                finalIndex - $0
            }
        )
    }

    private struct OrientedCorridor {
        let stationCRSs: [String]
        let route: ServiceRailwayRoute
    }

    private static func orientedCorridor(
        _ corridor: RailwayCorridor,
        isReversed: Bool
    ) -> OrientedCorridor {
        let stations = corridor.stationCRSs.map(normalizedCRS)
        if isReversed {
            return OrientedCorridor(
                stationCRSs: Array(stations.reversed()),
                route: reversedRoute(corridor.route)
            )
        }
        return OrientedCorridor(stationCRSs: stations, route: corridor.route)
    }

    private static func concatenate(
        _ corridors: [OrientedCorridor]
    ) -> (stationCRSs: [String], route: ServiceRailwayRoute)? {
        guard let first = corridors.first else { return nil }
        var stationCRSs = first.stationCRSs
        var coordinates = first.route.coordinates
        var cumulativeDistances = first.route.cumulativeDistances
        var stationCoordinateIndices = first.route.stationCoordinateIndices

        for corridor in corridors.dropFirst() {
            guard stationCRSs.last == corridor.stationCRSs.first,
                  let previousCoordinate = coordinates.last,
                  let joiningCoordinate = corridor.route.coordinates.first else {
                return nil
            }
            let removesDuplicateCoordinate = coordinatesAreEqual(
                previousCoordinate,
                joiningCoordinate
            )
            let coordinateOffset = coordinates.count - (removesDuplicateCoordinate ? 1 : 0)
            let distanceOffset = cumulativeDistances.last ?? 0
            if removesDuplicateCoordinate {
                coordinates.append(contentsOf: corridor.route.coordinates.dropFirst())
                cumulativeDistances.append(contentsOf:
                    corridor.route.cumulativeDistances.dropFirst().map {
                        distanceOffset + $0
                    }
                )
            } else {
                // Different station anchors at a complex junction are retained and connected by
                // a short deterministic seam. This is still the union of the two purchased route
                // geometries and avoids rerouting either corridor.
                coordinates.append(contentsOf: corridor.route.coordinates)
                let seamDistance = CLLocation(
                    latitude: previousCoordinate.latitude,
                    longitude: previousCoordinate.longitude
                ).distance(from: CLLocation(
                    latitude: joiningCoordinate.latitude,
                    longitude: joiningCoordinate.longitude
                ))
                cumulativeDistances.append(contentsOf:
                    corridor.route.cumulativeDistances.map {
                        distanceOffset + seamDistance + $0
                    }
                )
            }
            stationCRSs.append(contentsOf: corridor.stationCRSs.dropFirst())
            stationCoordinateIndices.append(contentsOf:
                corridor.route.stationCoordinateIndices.dropFirst().map {
                    coordinateOffset + $0
                }
            )
        }

        guard stationCRSs.count == stationCoordinateIndices.count,
              Set(stationCRSs).count == stationCRSs.count else { return nil }
        let route = ServiceRailwayRoute(
            coordinates: coordinates,
            cumulativeDistances: cumulativeDistances,
            stationCoordinateIndices: stationCoordinateIndices
        )
        guard route.stationCount == stationCRSs.count,
              route.totalLength.isFinite,
              route.totalLength > 0 else { return nil }
        return (stationCRSs, route)
    }

    private static func corridorIsUsable(_ corridor: RailwayCorridor) -> Bool {
        let stations = corridor.stationCRSs.map(normalizedCRS)
        guard stations.count >= 2,
              !stations.contains(where: \.isEmpty),
              Set(stations).count == stations.count,
              corridor.route.coordinates.count >= 2,
              corridor.route.stationCoordinateIndices.count == stations.count,
              corridor.route.cumulativeDistances.count == corridor.route.coordinates.count,
              corridor.route.totalLength.isFinite,
              corridor.route.totalLength > 0 else { return false }

        var previousIndex = -1
        for index in corridor.route.stationCoordinateIndices {
            guard corridor.route.coordinates.indices.contains(index), index > previousIndex else {
                return false
            }
            previousIndex = index
        }
        return true
    }

    private static func normalizedCRS(_ crs: String) -> String {
        crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func coordinatesAreEqual(
        _ lhs: CLLocationCoordinate2D,
        _ rhs: CLLocationCoordinate2D
    ) -> Bool {
        abs(lhs.latitude - rhs.latitude) <= 0.000_000_000_001
            && abs(lhs.longitude - rhs.longitude) <= 0.000_000_000_001
    }

    private static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? .max : result.partialValue
    }
}
