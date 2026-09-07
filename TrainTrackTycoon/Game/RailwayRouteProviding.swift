import Foundation

nonisolated protocol RailwayRouteProviding: Sendable {
    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute

    /// Returns catalogue stations that share a connected railway graph component with `originCRS`.
    /// Passing `nil` returns stations that can act as an origin because their component contains
    /// at least one other catalogue station. Implementations should answer from graph connectivity
    /// metadata rather than calculating a route to every candidate.
    func connectedStationCRSs(
        to originCRS: String?,
        among candidateCRSs: Set<String>
    ) async throws -> Set<String>

    /// Returns catalogue stations that can be reached from `originCRS` over a reasonably direct
    /// physical railway corridor. Unlike connected-component membership, this excludes nearby
    /// stations whose only graph path makes a large diversion. Implementations should answer with
    /// one graph traversal (or equivalent precomputed metadata), rather than one route search per
    /// candidate.
    func directlyRoutableStationCRSs(
        to originCRS: String?,
        among candidateCRSs: Set<String>
    ) async throws -> Set<String>

    /// Finds real catalogue stations that can be added between a routed corridor's endpoints.
    /// Results exclude the supplied endpoints and are ordered from route origin to destination.
    func discoverIntermediateStations(
        on route: ServiceRailwayRoute,
        endpointCRSs: [String],
        catalogStations: [Station]
    ) async throws -> [CorridorStationMatch]
}

extension RailwayRouteProviding {
    /// Fixture and lightweight providers already promise that their supplied geometry can connect
    /// any requested station pair. Keep that useful behavior without requiring every test provider
    /// to model the production OSM graph's connected components.
    func connectedStationCRSs(
        to originCRS: String?,
        among candidateCRSs: Set<String>
    ) async throws -> Set<String> {
        try Task.checkCancellation()
        let normalizedCandidates = Set(candidateCRSs.compactMap { rawCRS -> String? in
            let crs = rawCRS.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return crs.isEmpty ? nil : crs
        })
        guard let originCRS else { return normalizedCandidates }
        let normalizedOrigin = originCRS
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return normalizedCandidates.subtracting([normalizedOrigin])
    }

    /// Lightweight providers generally model only explicitly valid fixture connections, so their
    /// connectivity answer is also their direct-route answer. The production OSM router refines
    /// this with route-directness analysis.
    func directlyRoutableStationCRSs(
        to originCRS: String?,
        among candidateCRSs: Set<String>
    ) async throws -> Set<String> {
        try await connectedStationCRSs(to: originCRS, among: candidateCRSs)
    }

    /// Geometry-only fallback for fixture providers and routing implementations without graph
    /// anchors. The production OSM router supplies an anchor-aware implementation below.
    func discoverIntermediateStations(
        on route: ServiceRailwayRoute,
        endpointCRSs: [String],
        catalogStations: [Station]
    ) async throws -> [CorridorStationMatch] {
        try Task.checkCancellation()
        let matches = CorridorStationDiscovery.discover(
            on: route,
            endpointCRSs: endpointCRSs,
            catalogStations: catalogStations
        )
        try Task.checkCancellation()
        return matches
    }
}

extension RailwayRoutingService: RailwayRouteProviding {}
