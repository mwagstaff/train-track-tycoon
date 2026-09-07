import CoreLocation
import Foundation

nonisolated enum RailwayRoutingError: LocalizedError, Equatable, Sendable {
    case resourceMissing
    case invalidResource
    case insufficientCallingPoints
    case stationOutsideCoverage(String)
    case routeUnavailable(String, String)

    var errorDescription: String? {
        switch self {
        case .resourceMissing:
            return "The railway map data is unavailable."
        case .invalidResource:
            return "The railway map data couldn't be loaded."
        case .insufficientCallingPoints:
            return "At least two stations are needed to build a railway line."
        case .stationOutsideCoverage(let crs):
            return "Station \(crs) is outside the selected railway map coverage."
        case .routeUnavailable(let start, let end):
            return "No mainline route could be found between \(start) and \(end)."
        }
    }
}

actor RailwayRoutingService {
    static let shared = RailwayRoutingService()

    private let bundle: Bundle
    private var graph: RailwayGraph?
    private var graphLoadTask: Task<RailwayGraph, Error>?
    private var pathCache: [PathKey: GraphPath] = [:]
    private var pathCacheOrder: [PathKey] = []
    private var cachedPathTraversalCount = 0
    private var unreachablePaths: Set<PathKey> = []
    private var unreachablePathOrder: [PathKey] = []
    private var directStationCache: [String: Set<String>] = [:]
    private var directStationCacheOrder: [String] = []
    private let maximumCachedDirectedPaths = 2_048
    /// Bound cache memory by stored graph work as well as entry count. This retains the many
    /// short adjacent-station paths reused while editing a national route without allowing a few
    /// country-length paths to make memory usage unbounded.
    private let maximumCachedPathTraversals = 200_000
    private let maximumCachedUnreachablePaths = 512
    private let maximumCachedDirectStationOrigins = 24
    private let adjacentBacktrackFactor = 4.0
    /// Farther anchors are useful as route-choice fallbacks at unusually large stations, but can
    /// accidentally snap a station onto a neighbouring station's tracks. Keep normal platform
    /// choices local, with a nearest-anchor fallback for the one catalogue outlier in the asset.
    private let maximumTrustedAnchorDistance: CLLocationDistance = 250
    private let maximumTrustedAnchorSpread: CLLocationDistance = 25
    /// A direct corridor may curve around terrain, coastlines or city-centre junctions. Allow a
    /// proportionate curve or two kilometres of junction approach, while rejecting a large loop
    /// merely to connect two stations that are a short walk apart.
    private let maximumDirectRouteAdditionalDistance: CLLocationDistance = 2_000
    private let maximumDirectRouteDetourRatio = 4.0

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func prepare() async throws {
        try Task.checkCancellation()
        _ = try await loadGraph()
        try Task.checkCancellation()
    }

    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        let normalizedCRSs = stationCRSs.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        guard normalizedCRSs.count >= 2 else {
            throw RailwayRoutingError.insufficientCallingPoints
        }
        try Task.checkCancellation()

        let graph = try await loadGraph()
        try Task.checkCancellation()
        let candidates = try normalizedCRSs.map { crs -> [RailwayAnchor] in
            guard let anchors = graph.stationAnchors[crs], !anchors.isEmpty else {
                throw RailwayRoutingError.stationOutsideCoverage(crs)
            }
            return trustedAnchors(from: anchors)
        }

        var layers = [[RouteChoice?]]()
        layers.append(candidates[0].map {
            RouteChoice(score: $0.distance * 2, previousCandidate: nil, incomingPath: nil)
        })

        for stationIndex in 1..<candidates.count {
            try Task.checkCancellation()
            var nextLayer = Array<RouteChoice?>(
                repeating: nil,
                count: candidates[stationIndex].count
            )
            for (nextCandidateIndex, nextCandidate) in candidates[stationIndex].enumerated() {
                var bestChoice: RouteChoice?
                for (previousCandidateIndex, previousCandidate) in
                    candidates[stationIndex - 1].enumerated() {
                    guard let previousChoice = layers[stationIndex - 1][previousCandidateIndex] else {
                        continue
                    }
                    guard let path = try shortestPath(
                        in: graph,
                        from: previousCandidate.node,
                        to: nextCandidate.node
                    ) else {
                        continue
                    }

                    let backtrackLength = sharedPathLength(
                        previousChoice.incomingPath,
                        path,
                        graph: graph
                    )
                    let score = previousChoice.score
                        + path.cost
                        + (nextCandidate.distance * 2)
                        + (backtrackLength * adjacentBacktrackFactor)
                    if bestChoice == nil || score < bestChoice!.score {
                        bestChoice = RouteChoice(
                            score: score,
                            previousCandidate: previousCandidateIndex,
                            incomingPath: path
                        )
                    }
                }
                nextLayer[nextCandidateIndex] = bestChoice
            }

            guard nextLayer.contains(where: { $0 != nil }) else {
                throw RailwayRoutingError.routeUnavailable(
                    normalizedCRSs[stationIndex - 1],
                    normalizedCRSs[stationIndex]
                )
            }
            layers.append(nextLayer)
        }

        guard let finalCandidate = layers.last?.enumerated().compactMap({ index, choice in
            choice.map { (index, $0.score) }
        }).min(by: { $0.1 < $1.1 })?.0 else {
            throw RailwayRoutingError.invalidResource
        }

        var segmentPaths = Array<GraphPath?>(
            repeating: nil,
            count: normalizedCRSs.count - 1
        )
        var candidateIndex = finalCandidate
        for stationIndex in stride(from: normalizedCRSs.count - 1, through: 1, by: -1) {
            guard let choice = layers[stationIndex][candidateIndex],
                  let previousCandidate = choice.previousCandidate,
                  let incomingPath = choice.incomingPath else {
                throw RailwayRoutingError.invalidResource
            }
            segmentPaths[stationIndex - 1] = incomingPath
            candidateIndex = previousCandidate
        }

        return try merge(segmentPaths.compactMap { $0 }, graph: graph)
    }

    /// Connected-component lookup makes the entire catalogue eligibility check O(stations) for an
    /// origin and O(eligible stations) for a destination. It deliberately avoids 2,606 shortest-
    /// path searches whenever the player enters the line builder.
    func connectedStationCRSs(
        to originCRS: String?,
        among candidateCRSs: Set<String>
    ) async throws -> Set<String> {
        try Task.checkCancellation()
        let graph = try await loadGraph()
        try Task.checkCancellation()

        let normalizedCandidates = Set(candidateCRSs.compactMap { rawCRS -> String? in
            let crs = rawCRS.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return crs.isEmpty ? nil : crs
        })
        guard let originCRS else {
            if graph.routableStationCRSs.isSubset(of: normalizedCandidates) {
                return graph.routableStationCRSs
            }
            return graph.stationCRSsByComponent.values.reduce(into: Set<String>()) {
                result, stationCRSs in
                let candidateStations = stationCRSs.intersection(normalizedCandidates)
                guard candidateStations.count >= 2 else { return }
                result.formUnion(candidateStations)
            }
        }

        let normalizedOrigin = originCRS
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard let originComponents = graph.stationComponentsByCRS[normalizedOrigin] else {
            return []
        }

        var connected = Set<String>()
        for component in originComponents {
            guard let stationCRSs = graph.stationCRSsByComponent[component] else { continue }
            connected.formUnion(stationCRSs)
        }
        connected.formIntersection(normalizedCandidates)
        connected.remove(normalizedOrigin)
        return connected
    }

    /// Finds direct destination corridors with one shortest-path-tree traversal from the origin.
    /// This is O(graph + stations), rather than doing an A* search for every catalogue station.
    /// The result is cached per origin because the national graph and catalogue are immutable.
    func directlyRoutableStationCRSs(
        to originCRS: String?,
        among candidateCRSs: Set<String>
    ) async throws -> Set<String> {
        try Task.checkCancellation()
        let normalizedCandidates = Set(candidateCRSs.compactMap { rawCRS -> String? in
            let crs = rawCRS.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return crs.isEmpty ? nil : crs
        })
        guard let originCRS else {
            // Origin discovery must stay instant. Nearly every anchored station has a nearby
            // direct neighbour; destination discovery performs the precise corridor check.
            return try await connectedStationCRSs(to: nil, among: normalizedCandidates)
        }

        let normalizedOrigin = originCRS
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !normalizedOrigin.isEmpty else { return [] }
        if let cached = directStationCache[normalizedOrigin] {
            touchDirectStationCache(normalizedOrigin)
            return cached.intersection(normalizedCandidates)
        }

        let graph = try await loadGraph()
        try Task.checkCancellation()
        let direct = try directStationCRSs(in: graph, from: normalizedOrigin)
        rememberDirectStationCRSs(direct, for: normalizedOrigin)
        return direct.intersection(normalizedCandidates)
    }

    func discoverIntermediateStations(
        on route: ServiceRailwayRoute,
        endpointCRSs: [String],
        catalogStations: [Station]
    ) async throws -> [CorridorStationMatch] {
        try Task.checkCancellation()
        let graph = try await loadGraph()
        try Task.checkCancellation()

        var anchorsByCRS = [String: [CorridorStationAnchor]]()
        anchorsByCRS.reserveCapacity(catalogStations.count)
        for (stationIndex, station) in catalogStations.enumerated() {
            if stationIndex.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            let crs = station.crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard anchorsByCRS[crs] == nil,
                  let anchors = graph.stationAnchors[crs],
                  !anchors.isEmpty else {
                continue
            }
            anchorsByCRS[crs] = anchors.enumerated().compactMap { index, anchor in
                guard graph.nodes.indices.contains(anchor.node) else { return nil }
                return CorridorStationAnchor(
                    coordinate: graph.nodes[anchor.node],
                    stationOffset: anchor.distance,
                    stableIndex: index
                )
            }
        }

        let matches = CorridorStationDiscovery.discover(
            on: route,
            endpointCRSs: endpointCRSs,
            catalogStations: catalogStations,
            anchorsByCRS: anchorsByCRS
        )
        try Task.checkCancellation()
        return matches
    }

    private func sharedPathLength(
        _ first: GraphPath?,
        _ second: GraphPath,
        graph: RailwayGraph
    ) -> CLLocationDistance {
        guard let first else { return 0 }
        let firstEdges = Set(first.traversals.map(\.edge))
        let secondEdges = Set(second.traversals.map(\.edge))
        return firstEdges.intersection(secondEdges).reduce(0) { result, edge in
            result + graph.edges[edge].length
        }
    }

    private func trustedAnchors(from anchors: [RailwayAnchor]) -> [RailwayAnchor] {
        guard let nearest = anchors.min(by: { $0.distance < $1.distance }) else { return [] }
        let distanceLimit = min(
            maximumTrustedAnchorDistance,
            nearest.distance + maximumTrustedAnchorSpread
        )
        let nearby = anchors.filter { $0.distance <= distanceLimit }
        return nearby.isEmpty ? [nearest] : nearby
    }

    private func directStationCRSs(
        in graph: RailwayGraph,
        from originCRS: String
    ) throws -> Set<String> {
        guard let rawOriginAnchors = graph.stationAnchors[originCRS],
              !rawOriginAnchors.isEmpty else {
            return []
        }
        let originAnchors = trustedAnchors(from: rawOriginAnchors)
        guard let representativeOrigin = originAnchors.min(by: { $0.distance < $1.distance }),
              graph.nodes.indices.contains(representativeOrigin.node) else {
            return []
        }

        var routingCosts = Array(repeating: Double.infinity, count: graph.nodes.count)
        var routeLengths = Array(repeating: Double.infinity, count: graph.nodes.count)
        var queue = RailwayMinHeap()
        for anchor in originAnchors where graph.nodes.indices.contains(anchor.node) {
            let initialCost = anchor.distance * 2
            guard initialCost < routingCosts[anchor.node] else { continue }
            routingCosts[anchor.node] = initialCost
            routeLengths[anchor.node] = anchor.distance
            queue.push(RailwayHeapItem(
                node: anchor.node,
                cost: initialCost,
                priority: initialCost
            ))
        }

        var visitedCount = 0
        while let item = queue.pop() {
            visitedCount += 1
            if visitedCount.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            let node = item.node
            if item.cost > routingCosts[node] + 0.001 { continue }
            for adjacency in graph.adjacency[node] {
                let edge = graph.edges[adjacency.edge]
                let candidateCost = routingCosts[node] + edge.cost
                let candidateLength = routeLengths[node] + edge.length
                let existingCost = routingCosts[adjacency.neighbour]
                guard candidateCost < existingCost - 0.001
                        || (abs(candidateCost - existingCost) <= 0.001
                            && candidateLength < routeLengths[adjacency.neighbour]) else {
                    continue
                }
                routingCosts[adjacency.neighbour] = candidateCost
                routeLengths[adjacency.neighbour] = candidateLength
                queue.push(RailwayHeapItem(
                    node: adjacency.neighbour,
                    cost: candidateCost,
                    priority: candidateCost
                ))
            }
        }

        let originCoordinate = graph.nodes[representativeOrigin.node]
        var result = Set<String>()
        result.reserveCapacity(graph.stationAnchors.count)
        for (stationIndex, entry) in graph.stationAnchors.enumerated() {
            if stationIndex.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            let rawCRS = entry.key
            let crs = rawCRS.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard crs != originCRS else { continue }
            let anchors = trustedAnchors(from: entry.value)
            guard let representativeDestination = anchors.min(by: { $0.distance < $1.distance }),
                  graph.nodes.indices.contains(representativeDestination.node) else {
                continue
            }

            var bestScore = Double.infinity
            var bestRouteLength = Double.infinity
            for anchor in anchors where graph.nodes.indices.contains(anchor.node) {
                let score = routingCosts[anchor.node] + (anchor.distance * 2)
                let length = routeLengths[anchor.node] + anchor.distance
                if score < bestScore {
                    bestScore = score
                    bestRouteLength = length
                }
            }
            guard bestScore.isFinite, bestRouteLength.isFinite else { continue }

            let directDistance = straightLineDistance(
                originCoordinate,
                graph.nodes[representativeDestination.node]
            )
            let maximumLength = max(
                directDistance * maximumDirectRouteDetourRatio,
                directDistance + maximumDirectRouteAdditionalDistance
            )
            if bestRouteLength <= maximumLength {
                result.insert(crs)
            }
        }
        return result
    }

    private func touchDirectStationCache(_ originCRS: String) {
        directStationCacheOrder.removeAll { $0 == originCRS }
        directStationCacheOrder.append(originCRS)
    }

    private func rememberDirectStationCRSs(_ stationCRSs: Set<String>, for originCRS: String) {
        directStationCache[originCRS] = stationCRSs
        touchDirectStationCache(originCRS)
        while directStationCacheOrder.count > maximumCachedDirectStationOrigins {
            let evicted = directStationCacheOrder.removeFirst()
            directStationCache.removeValue(forKey: evicted)
        }
    }

    private func loadGraph() async throws -> RailwayGraph {
        if let graph { return graph }
        if let graphLoadTask {
            let loaded = try await graphLoadTask.value
            graph = loaded
            self.graphLoadTask = nil
            return loaded
        }

        guard let resourceURL = RailwayGraphLoader.resourceURL(in: bundle) else {
            throw RailwayRoutingError.resourceMissing
        }
        // Route requests are replaceable while the large graph is loading. Detached reusable
        // work lets the replacement await the same load instead of starting a second decode.
        let loadTask = Task.detached(priority: .userInitiated) {
            try RailwayGraphLoader.load(from: resourceURL)
        }
        graphLoadTask = loadTask
        do {
            let loaded = try await loadTask.value
            graph = loaded
            graphLoadTask = nil
            return loaded
        } catch {
            graphLoadTask = nil
            throw error
        }
    }

    private func shortestPath(
        in graph: RailwayGraph,
        from start: Int,
        to end: Int
    ) throws -> GraphPath? {
        if start == end {
            return GraphPath(length: 0, cost: 0, traversals: [])
        }
        let key = PathKey(start: start, end: end)
        if let cached = pathCache[key] {
            touchCachedPath(key)
            return cached
        }
        if unreachablePaths.contains(key) { return nil }

        guard graph.components[start] == graph.components[end] else {
            rememberUnreachablePath(key)
            rememberUnreachablePath(PathKey(start: end, end: start))
            return nil
        }

        let heuristicPath = try search(
            in: graph,
            from: start,
            to: end,
            usesHeuristic: true
        )
        let path = try heuristicPath ?? search(
            in: graph,
            from: start,
            to: end,
            usesHeuristic: false
        )
        guard let path else {
            rememberUnreachablePath(key)
            rememberUnreachablePath(PathKey(start: end, end: start))
            return nil
        }

        remember(path, for: key)
        let reverseKey = PathKey(start: end, end: start)
        remember(GraphPath(
            length: path.length,
            cost: path.cost,
            traversals: path.traversals.reversed().map {
                RailwayTraversal(edge: $0.edge, from: $0.to, to: $0.from)
            }
        ), for: reverseKey)
        return path
    }

    private func touchCachedPath(_ key: PathKey) {
        pathCacheOrder.removeAll { $0 == key }
        pathCacheOrder.append(key)
    }

    private func remember(_ path: GraphPath, for key: PathKey) {
        if let previous = pathCache[key] {
            cachedPathTraversalCount = max(
                cachedPathTraversalCount - previous.traversals.count,
                0
            )
        }
        pathCache[key] = path
        cachedPathTraversalCount += path.traversals.count
        touchCachedPath(key)
        while pathCacheOrder.count > maximumCachedDirectedPaths
            || cachedPathTraversalCount > maximumCachedPathTraversals {
            let evicted = pathCacheOrder.removeFirst()
            if let removed = pathCache.removeValue(forKey: evicted) {
                cachedPathTraversalCount = max(
                    cachedPathTraversalCount - removed.traversals.count,
                    0
                )
            }
        }
    }

    private func rememberUnreachablePath(_ key: PathKey) {
        guard unreachablePaths.insert(key).inserted else { return }
        unreachablePathOrder.append(key)
        while unreachablePathOrder.count > maximumCachedUnreachablePaths {
            let evicted = unreachablePathOrder.removeFirst()
            unreachablePaths.remove(evicted)
        }
    }

    private func search(
        in graph: RailwayGraph,
        from start: Int,
        to end: Int,
        usesHeuristic: Bool
    ) throws -> GraphPath? {
        func heuristic(for node: Int) -> CLLocationDistance {
            usesHeuristic ? straightLineDistance(graph.nodes[node], graph.nodes[end]) : 0
        }

        var distances = Array(repeating: Double.infinity, count: graph.nodes.count)
        var previousNodes = Array(repeating: -1, count: graph.nodes.count)
        var previousEdges = Array(repeating: -1, count: graph.nodes.count)
        var queue = RailwayMinHeap()
        distances[start] = 0
        queue.push(RailwayHeapItem(
            node: start,
            cost: 0,
            priority: heuristic(for: start)
        ))

        var visitedCount = 0
        while let item = queue.pop() {
            visitedCount += 1
            if visitedCount.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            let current = item.node
            if current == end { break }
            if item.cost > distances[current] + 0.001 { continue }

            for adjacency in graph.adjacency[current] {
                let edge = graph.edges[adjacency.edge]
                let candidateDistance = distances[current] + edge.cost
                if candidateDistance < distances[adjacency.neighbour] {
                    distances[adjacency.neighbour] = candidateDistance
                    previousNodes[adjacency.neighbour] = current
                    previousEdges[adjacency.neighbour] = adjacency.edge
                    queue.push(RailwayHeapItem(
                        node: adjacency.neighbour,
                        cost: candidateDistance,
                        priority: candidateDistance + heuristic(for: adjacency.neighbour)
                    ))
                }
            }
        }

        guard distances[end].isFinite else { return nil }

        var traversals = [RailwayTraversal]()
        var current = end
        while current != start {
            let previous = previousNodes[current]
            let edge = previousEdges[current]
            guard previous >= 0, edge >= 0 else { return nil }
            traversals.append(RailwayTraversal(edge: edge, from: previous, to: current))
            current = previous
        }
        traversals.reverse()
        let length = traversals.reduce(0.0) { partialResult, traversal in
            partialResult + graph.edges[traversal.edge].length
        }
        return GraphPath(length: length, cost: distances[end], traversals: traversals)
    }

    private func merge(_ paths: [GraphPath], graph: RailwayGraph) throws -> ServiceRailwayRoute {
        guard !paths.isEmpty else {
            throw RailwayRoutingError.insufficientCallingPoints
        }
        var coordinates = [CLLocationCoordinate2D]()
        var stationCoordinateIndices = [0]

        for path in paths {
            for traversal in path.traversals {
                let edge = graph.edges[traversal.edge]
                let edgeCoordinates: [CLLocationCoordinate2D]
                if traversal.from == edge.start && traversal.to == edge.end {
                    edgeCoordinates = edge.coordinates
                } else if traversal.from == edge.end && traversal.to == edge.start {
                    edgeCoordinates = Array(edge.coordinates.reversed())
                } else {
                    throw RailwayRoutingError.invalidResource
                }

                if coordinates.isEmpty {
                    coordinates.append(contentsOf: edgeCoordinates)
                } else {
                    guard let existingEnd = coordinates.last,
                          let incomingStart = edgeCoordinates.first,
                          straightLineDistance(existingEnd, incomingStart) < 0.5 else {
                        throw RailwayRoutingError.invalidResource
                    }
                    coordinates.append(contentsOf: edgeCoordinates.dropFirst())
                }
            }
            stationCoordinateIndices.append(max(0, coordinates.count - 1))
        }

        guard coordinates.count >= 2,
              stationCoordinateIndices.count == paths.count + 1 else {
            throw RailwayRoutingError.invalidResource
        }
        var cumulativeDistances = Array(repeating: 0.0, count: coordinates.count)
        for index in 1..<coordinates.count {
            cumulativeDistances[index] = cumulativeDistances[index - 1]
                + straightLineDistance(coordinates[index - 1], coordinates[index])
        }
        return ServiceRailwayRoute(
            coordinates: coordinates,
            cumulativeDistances: cumulativeDistances,
            stationCoordinateIndices: stationCoordinateIndices
        )
    }
}

private nonisolated enum RailwayGraphLoader {
    static func resourceURL(in bundle: Bundle) -> URL? {
        bundle.url(
            forResource: "railway-routing-great-britain-osm",
            withExtension: "json",
            subdirectory: "Resources"
        ) ?? bundle.url(
            forResource: "railway-routing-great-britain-osm",
            withExtension: "json"
        )
    }

    static func load(from resourceURL: URL) throws -> RailwayGraph {
        try Task.checkCancellation()
        let data = try Data(contentsOf: resourceURL, options: .mappedIfSafe)
        try Task.checkCancellation()
        let asset: RailwayRoutingAsset
        do {
            asset = try JSONDecoder().decode(RailwayRoutingAsset.self, from: data)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RailwayRoutingError.invalidResource
        }
        try Task.checkCancellation()
        guard asset.metadata.schemaVersion == 1,
              !asset.nodes.isEmpty,
              !asset.edges.isEmpty else {
            throw RailwayRoutingError.invalidResource
        }

        let nodes = asset.nodes
        let edges = asset.edges
        var adjacency = Array(repeating: [RailwayAdjacency](), count: nodes.count)
        for (edgeIndex, edge) in edges.enumerated() {
            if edgeIndex.isMultiple(of: 2_048) {
                try Task.checkCancellation()
            }
            guard nodes.indices.contains(edge.start),
                  nodes.indices.contains(edge.end),
                  edge.length > 0,
                  edge.length.isFinite,
                  edge.cost > 0,
                  edge.cost.isFinite,
                  edge.coordinates.count >= 2 else {
                throw RailwayRoutingError.invalidResource
            }
            adjacency[edge.start].append(RailwayAdjacency(
                neighbour: edge.end,
                edge: edgeIndex
            ))
            adjacency[edge.end].append(RailwayAdjacency(
                neighbour: edge.start,
                edge: edgeIndex
            ))
        }
        try Task.checkCancellation()

        let anchors: [String: [RailwayAnchor]] = asset.stationAnchors.mapValues { values in
            values.compactMap { anchor in
                guard nodes.indices.contains(anchor.node),
                      anchor.distance >= 0,
                      anchor.distance.isFinite else {
                    return nil
                }
                return RailwayAnchor(node: anchor.node, distance: anchor.distance)
            }
        }
        let components = railwayConnectedComponents(adjacency: adjacency)
        let stationConnectivity = railwayStationConnectivity(
            stationAnchors: anchors,
            components: components
        )
        return RailwayGraph(
            nodes: nodes,
            edges: edges,
            adjacency: adjacency,
            stationAnchors: anchors,
            components: components,
            stationComponentsByCRS: stationConnectivity.componentsByCRS,
            stationCRSsByComponent: stationConnectivity.stationCRSsByComponent,
            routableStationCRSs: stationConnectivity.routableStationCRSs
        )
    }
}

private nonisolated struct RailwayRoutingAsset: Decodable, Sendable {
    let metadata: RailwayRoutingMetadata
    let nodes: [CLLocationCoordinate2D]
    let edges: [RailwayGraphEdge]
    let stationAnchors: [String: [RailwayAnchor]]

    private enum CodingKeys: String, CodingKey {
        case metadata
        case nodes
        case edges
        case stationAnchors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metadata = try container.decode(RailwayRoutingMetadata.self, forKey: .metadata)
        // Decode coordinate pairs straight into their runtime representation. Retaining the
        // JSON's hundreds of thousands of tiny [Double] arrays causes a large cold-load spike.
        nodes = try container.decode([RailwayCoordinate].self, forKey: .nodes).map(\.value)
        edges = try container.decode([RailwayGraphEdge].self, forKey: .edges)
        stationAnchors = try container.decode(
            [String: [RailwayAnchor]].self,
            forKey: .stationAnchors
        )
    }
}

private nonisolated struct RailwayRoutingMetadata: Decodable, Sendable {
    let schemaVersion: Int
}

private nonisolated struct RailwayCoordinate: Decodable, Sendable {
    let value: CLLocationCoordinate2D

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let longitude = try container.decode(Double.self)
        let latitude = try container.decode(Double.self)
        guard container.isAtEnd,
              longitude.isFinite,
              latitude.isFinite,
              (-180...180).contains(longitude),
              (-90...90).contains(latitude) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a valid longitude/latitude pair."
            )
        }
        value = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private nonisolated struct RailwayGraph: Sendable {
    let nodes: [CLLocationCoordinate2D]
    let edges: [RailwayGraphEdge]
    let adjacency: [[RailwayAdjacency]]
    let stationAnchors: [String: [RailwayAnchor]]
    let components: [Int]
    let stationComponentsByCRS: [String: Set<Int>]
    let stationCRSsByComponent: [Int: Set<String>]
    let routableStationCRSs: Set<String>
}

private nonisolated struct RailwayStationConnectivity: Sendable {
    let componentsByCRS: [String: Set<Int>]
    let stationCRSsByComponent: [Int: Set<String>]
    let routableStationCRSs: Set<String>
}

private nonisolated struct RailwayGraphEdge: Decodable, Sendable {
    let start: Int
    let end: Int
    let length: Double
    let cost: Double
    let coordinates: [CLLocationCoordinate2D]

    private enum CodingKeys: String, CodingKey {
        case start = "s"
        case end = "e"
        case length = "l"
        case cost = "c"
        case coordinates = "p"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decode(Int.self, forKey: .start)
        end = try container.decode(Int.self, forKey: .end)
        length = try container.decode(Double.self, forKey: .length)
        cost = try container.decodeIfPresent(Double.self, forKey: .cost) ?? length
        coordinates = try container.decode(
            [RailwayCoordinate].self,
            forKey: .coordinates
        ).map(\.value)
    }
}

private nonisolated struct RailwayAdjacency: Sendable {
    let neighbour: Int
    let edge: Int
}

private nonisolated struct RailwayAnchor: Decodable, Sendable {
    let node: Int
    let distance: Double

    private enum CodingKeys: String, CodingKey {
        case node = "n"
        case distance = "d"
    }
}

private nonisolated struct RailwayTraversal: Sendable {
    let edge: Int
    let from: Int
    let to: Int
}

private nonisolated struct GraphPath: Sendable {
    let length: Double
    let cost: Double
    let traversals: [RailwayTraversal]
}

private nonisolated struct RouteChoice: Sendable {
    let score: Double
    let previousCandidate: Int?
    let incomingPath: GraphPath?
}

private nonisolated struct PathKey: Hashable, Sendable {
    let start: Int
    let end: Int
}

private nonisolated struct RailwayHeapItem: Sendable {
    let node: Int
    let cost: Double
    let priority: Double
}

private nonisolated struct RailwayMinHeap: Sendable {
    private var items = [RailwayHeapItem]()

    mutating func push(_ item: RailwayHeapItem) {
        items.append(item)
        var index = items.count - 1
        while index > 0 {
            let parent = (index - 1) / 2
            guard items[index].priority < items[parent].priority else { break }
            items.swapAt(index, parent)
            index = parent
        }
    }

    mutating func pop() -> RailwayHeapItem? {
        guard !items.isEmpty else { return nil }
        if items.count == 1 { return items.removeLast() }
        let result = items[0]
        items[0] = items.removeLast()
        var index = 0
        while true {
            let left = (index * 2) + 1
            let right = left + 1
            var smallest = index
            if left < items.count && items[left].priority < items[smallest].priority {
                smallest = left
            }
            if right < items.count && items[right].priority < items[smallest].priority {
                smallest = right
            }
            guard smallest != index else { break }
            items.swapAt(index, smallest)
            index = smallest
        }
        return result
    }
}

private nonisolated func straightLineDistance(
    _ first: CLLocationCoordinate2D,
    _ second: CLLocationCoordinate2D
) -> CLLocationDistance {
    CLLocation(latitude: first.latitude, longitude: first.longitude).distance(
        from: CLLocation(latitude: second.latitude, longitude: second.longitude)
    )
}

private nonisolated func railwayConnectedComponents(
    adjacency: [[RailwayAdjacency]]
) -> [Int] {
    var components = Array(repeating: -1, count: adjacency.count)
    var component = 0
    for start in adjacency.indices where components[start] == -1 {
        var pending = [start]
        components[start] = component
        while let node = pending.popLast() {
            for edge in adjacency[node] where components[edge.neighbour] == -1 {
                components[edge.neighbour] = component
                pending.append(edge.neighbour)
            }
        }
        component += 1
    }
    return components
}

private nonisolated func railwayStationConnectivity(
    stationAnchors: [String: [RailwayAnchor]],
    components: [Int]
) -> RailwayStationConnectivity {
    var componentsByCRS = [String: Set<Int>]()
    componentsByCRS.reserveCapacity(stationAnchors.count)
    var stationCRSsByComponent = [Int: Set<String>]()

    for (rawCRS, anchors) in stationAnchors {
        let crs = rawCRS.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !crs.isEmpty else { continue }
        let stationComponents = Set(anchors.compactMap { anchor -> Int? in
            guard components.indices.contains(anchor.node) else { return nil }
            return components[anchor.node]
        })
        guard !stationComponents.isEmpty else { continue }
        componentsByCRS[crs] = stationComponents
        for component in stationComponents {
            stationCRSsByComponent[component, default: []].insert(crs)
        }
    }

    let routableStationCRSs = stationCRSsByComponent.values.reduce(into: Set<String>()) {
        result, stationCRSs in
        guard stationCRSs.count >= 2 else { return }
        result.formUnion(stationCRSs)
    }
    return RailwayStationConnectivity(
        componentsByCRS: componentsByCRS,
        stationCRSsByComponent: stationCRSsByComponent,
        routableStationCRSs: routableStationCRSs
    )
}
