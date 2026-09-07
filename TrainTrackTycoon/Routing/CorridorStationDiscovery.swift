import CoreLocation
import Foundation

/// A real station from the bundled catalogue that can form an intermediate call on a corridor.
/// Endpoints are deliberately not returned; callers can place them around these ordered matches.
nonisolated struct CorridorStationMatch: Identifiable, Hashable, Sendable {
    let station: Station
    let routeDistance: CLLocationDistance
    let routeProgress: Double
    let routeCoordinateIndex: Int
    let offsetFromRoute: CLLocationDistance

    var id: String { station.crs }
}

/// Tuned conservatively to favour stations on the selected railway over nearby parallel routes.
nonisolated struct CorridorStationDiscoveryConfiguration: Equatable, Sendable {
    let maximumStationOffsetFromRoute: CLLocationDistance
    let maximumAnchorOffsetFromRoute: CLLocationDistance
    let maximumFallbackOffsetFromRoute: CLLocationDistance
    let endpointClearance: CLLocationDistance
    let maximumIntermediateStationCount: Int

    static let standard = CorridorStationDiscoveryConfiguration(
        maximumStationOffsetFromRoute: 400,
        maximumAnchorOffsetFromRoute: 40,
        maximumFallbackOffsetFromRoute: 180,
        endpointClearance: 100,
        maximumIntermediateStationCount: 254
    )
}

/// A graph station anchor mapped to its railway-node coordinate.
/// The routing service supplies these from the bundled OSM routing asset when available.
nonisolated struct CorridorStationAnchor: Hashable, Sendable {
    let coordinate: CLLocationCoordinate2D
    let stationOffset: CLLocationDistance
    let stableIndex: Int

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.stationOffset == rhs.stationOffset
            && lhs.stableIndex == rhs.stableIndex
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
        hasher.combine(stationOffset)
        hasher.combine(stableIndex)
    }
}

nonisolated enum CorridorStationDiscovery {
    static func discover(
        on route: ServiceRailwayRoute,
        endpointCRSs: [String],
        catalogStations: [Station],
        anchorsByCRS: [String: [CorridorStationAnchor]] = [:],
        configuration: CorridorStationDiscoveryConfiguration = .standard
    ) -> [CorridorStationMatch] {
        guard route.coordinates.count >= 2,
              route.cumulativeDistances.count == route.coordinates.count,
              route.coordinates.allSatisfy({
                  $0.latitude.isFinite && $0.longitude.isFinite
              }),
              route.cumulativeDistances.allSatisfy(\.isFinite),
              route.totalLength.isFinite,
              configuration.maximumStationOffsetFromRoute.isFinite,
              configuration.maximumAnchorOffsetFromRoute.isFinite,
              configuration.maximumFallbackOffsetFromRoute.isFinite,
              configuration.endpointClearance.isFinite,
              configuration.maximumStationOffsetFromRoute >= 0,
              configuration.maximumAnchorOffsetFromRoute >= 0,
              configuration.maximumFallbackOffsetFromRoute >= 0,
              configuration.endpointClearance >= 0,
              route.totalLength > configuration.endpointClearance * 2,
              configuration.maximumIntermediateStationCount > 0 else {
            return []
        }

        let endpoints = Set(endpointCRSs.map(normalizedCRS))
        let bounds = geographicBounds(for: route.coordinates)
        let latitudePadding = configuration.maximumStationOffsetFromRoute / 110_574
        let centerLatitude = (bounds.minimumLatitude + bounds.maximumLatitude) / 2
        let longitudeMetres = max(1, 111_320 * cos(centerLatitude * .pi / 180))
        let longitudePadding = configuration.maximumStationOffsetFromRoute / longitudeMetres

        // Catalogue order is not part of gameplay. Normalizing and sorting first makes duplicate
        // handling and equal-distance ties stable across resource regeneration.
        var uniqueStations = [String: Station]()
        for station in catalogStations {
            let crs = normalizedCRS(station.crs)
            guard !crs.isEmpty else { continue }
            if let existing = uniqueStations[crs] {
                if stationIsPreferred(station, over: existing) {
                    uniqueStations[crs] = station
                }
            } else {
                uniqueStations[crs] = station
            }
        }

        var matches = [CorridorStationMatch]()
        for crs in uniqueStations.keys.sorted() {
            guard !endpoints.contains(crs),
                  let station = uniqueStations[crs],
                  station.latitude.isFinite,
                  station.longitude.isFinite,
                  station.latitude >= bounds.minimumLatitude - latitudePadding,
                  station.latitude <= bounds.maximumLatitude + latitudePadding,
                  station.longitude >= bounds.minimumLongitude - longitudePadding,
                  station.longitude <= bounds.maximumLongitude + longitudePadding,
                  let stationProjection = route.projection(closestTo: station.coordinate),
                  stationProjection.offsetFromRoute
                    <= configuration.maximumStationOffsetFromRoute else {
                continue
            }

            let normalizedAnchors = anchorsByCRS[crs, default: []]
                .filter {
                    $0.stationOffset.isFinite
                        && $0.stationOffset >= 0
                        && $0.stationOffset <= configuration.maximumStationOffsetFromRoute
                }

            let selectedProjection: RailwayRouteProjection?
            if normalizedAnchors.isEmpty {
                selectedProjection = stationProjection.offsetFromRoute
                    <= configuration.maximumFallbackOffsetFromRoute
                    ? stationProjection
                    : nil
            } else {
                selectedProjection = normalizedAnchors.compactMap { anchor in
                    route.projection(closestTo: anchor.coordinate).map { projection in
                        (anchor: anchor, projection: projection)
                    }
                }
                .filter {
                    $0.projection.offsetFromRoute
                        <= configuration.maximumAnchorOffsetFromRoute
                }
                .min(by: anchorCandidateIsPreferred)?.projection
            }

            guard let selectedProjection,
                  selectedProjection.routeDistance > configuration.endpointClearance,
                  selectedProjection.routeDistance
                    < route.totalLength - configuration.endpointClearance else {
                continue
            }
            matches.append(CorridorStationMatch(
                station: station,
                routeDistance: selectedProjection.routeDistance,
                routeProgress: selectedProjection.routeProgress,
                routeCoordinateIndex: selectedProjection.routeCoordinateIndex,
                offsetFromRoute: stationProjection.offsetFromRoute
            ))
        }

        matches.sort {
            if abs($0.routeDistance - $1.routeDistance) > 0.001 {
                return $0.routeDistance < $1.routeDistance
            }
            return $0.station.crs < $1.station.crs
        }
        return Array(matches.prefix(configuration.maximumIntermediateStationCount))
    }

    private static func normalizedCRS(_ crs: String) -> String {
        crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func anchorCandidateIsPreferred(
        _ lhs: (anchor: CorridorStationAnchor, projection: RailwayRouteProjection),
        _ rhs: (anchor: CorridorStationAnchor, projection: RailwayRouteProjection)
    ) -> Bool {
        if abs(lhs.projection.offsetFromRoute - rhs.projection.offsetFromRoute) > 0.001 {
            return lhs.projection.offsetFromRoute < rhs.projection.offsetFromRoute
        }
        if abs(lhs.anchor.stationOffset - rhs.anchor.stationOffset) > 0.001 {
            return lhs.anchor.stationOffset < rhs.anchor.stationOffset
        }
        if abs(lhs.projection.routeDistance - rhs.projection.routeDistance) > 0.001 {
            return lhs.projection.routeDistance < rhs.projection.routeDistance
        }
        return lhs.anchor.stableIndex < rhs.anchor.stableIndex
    }

    private static func stationIsPreferred(_ lhs: Station, over rhs: Station) -> Bool {
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        if lhs.latitude != rhs.latitude { return lhs.latitude < rhs.latitude }
        return lhs.longitude < rhs.longitude
    }

    private static func geographicBounds(
        for coordinates: [CLLocationCoordinate2D]
    ) -> (
        minimumLatitude: Double,
        maximumLatitude: Double,
        minimumLongitude: Double,
        maximumLongitude: Double
    ) {
        var minimumLatitude = Double.infinity
        var maximumLatitude = -Double.infinity
        var minimumLongitude = Double.infinity
        var maximumLongitude = -Double.infinity
        for coordinate in coordinates {
            minimumLatitude = min(minimumLatitude, coordinate.latitude)
            maximumLatitude = max(maximumLatitude, coordinate.latitude)
            minimumLongitude = min(minimumLongitude, coordinate.longitude)
            maximumLongitude = max(maximumLongitude, coordinate.longitude)
        }
        return (
            minimumLatitude,
            maximumLatitude,
            minimumLongitude,
            maximumLongitude
        )
    }
}
