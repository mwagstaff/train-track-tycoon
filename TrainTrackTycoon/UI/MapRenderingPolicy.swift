import CoreLocation
import Foundation
import MapKit

/// Coarse presentation tiers for keeping a country-scale railway map responsive.
///
/// These tiers affect only map geometry and the number of rendered station markers. They never
/// remove stations from the game catalogue or change simulation fidelity.
nonisolated enum RailwayMapRenderingDetailLevel: Int, CaseIterable, Hashable, Sendable {
    case country
    case regional
    case local

    init(cameraDistanceMetres: CLLocationDistance) {
        let distance = cameraDistanceMetres.isFinite ? max(cameraDistanceMetres, 0) : .infinity
        if distance <= 85_000 {
            self = .local
        } else if distance <= 360_000 {
            self = .regional
        } else {
            self = .country
        }
    }

    var candidateStationLimit: Int {
        switch self {
        case .country: 40
        case .regional: 80
        case .local: 160
        }
    }

    var builtStationLimit: Int {
        switch self {
        case .country: 72
        case .regional: 144
        case .local: 260
        }
    }

    var maximumRoutePointCount: Int {
        switch self {
        case .country: 128
        case .regional: 512
        case .local: 2_048
        }
    }

    /// A strict global overlay budget. Without this cap a dense national save can ask MapKit to
    /// maintain hundreds of multi-point polylines even though most are visually indistinguishable
    /// at the current scale.
    var maximumVisibleLineCount: Int {
        switch self {
        case .country: 96
        case .regional: 160
        case .local: 240
        }
    }

    var maximumVisibleTrainCount: Int {
        switch self {
        case .country: 24
        case .regional: 48
        case .local: 72
        }
    }

    var showsCandidateStationNames: Bool {
        self == .local
    }
}

/// Pure, deterministic map filtering and simplification rules.
nonisolated enum RailwayMapRenderingPolicy {
    /// A cheap screen-local preflight for the map's "add station" affordance. Exact OSM-anchor
    /// validation still happens after a tap; this pass only prevents us from running graph-backed
    /// discovery for every catalogue marker and every national-network service continuously.
    static func potentialIntermediateLineIDs(
        for stations: [Station],
        among lines: [BuiltLine],
        maximumServiceCallCount: Int,
        maximumStationOffsetMetres: CLLocationDistance = 400,
        endpointClearanceMetres: CLLocationDistance = 100
    ) -> [String: [UUID]] {
        let maximumServiceCallCount = max(maximumServiceCallCount, 2)
        let maximumOffset = max(maximumStationOffsetMetres, 0)
        let endpointClearance = max(endpointClearanceMetres, 0)
        let eligibleLines = lines.filter { line in
            line.isConstructed
                && line.railwayClass == .conventional
                && line.corridorIDs.count == 1
                && line.stationCRSs.count < maximumServiceCallCount
                && line.corridorRoute.totalLength > endpointClearance * 2
        }.sorted { lhs, rhs in
            if lhs.styleIndex != rhs.styleIndex { return lhs.styleIndex < rhs.styleIndex }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        guard !eligibleLines.isEmpty, !stations.isEmpty else { return [:] }

        // A station that is already part of the network keeps its normal inspection action. It
        // can still be added to another service through that service's Edit Stops workflow; the
        // map shortcut is deliberately reserved for unbuilt markers so one tap has one meaning.
        let networkStationCRSs = Set(lines.flatMap { $0.stationCRSs.map(normalizedCRS) })

        let lineCandidates = eligibleLines.map { line in
            let routeRect = mapRect(containing: line.corridorRoute.coordinates)
            let centreLatitude = line.corridorRoute.coordinates.isEmpty
                ? 51.5
                : line.corridorRoute.coordinates[
                    line.corridorRoute.coordinates.count / 2
                ].latitude
            let padding = maximumOffset * MKMapPointsPerMeterAtLatitude(centreLatitude)
            let paddedRect = MKMapRect(
                x: routeRect.minX - padding,
                y: routeRect.minY - padding,
                width: routeRect.width + padding * 2,
                height: routeRect.height + padding * 2
            )
            return (
                line: line,
                existingCalls: Set(line.stationCRSs.map(normalizedCRS)),
                paddedRect: paddedRect
            )
        }

        var result = [String: [UUID]]()
        result.reserveCapacity(stations.count)
        for station in stations {
            guard !Task.isCancelled else { return [:] }
            let crs = normalizedCRS(station.crs)
            guard !crs.isEmpty, !networkStationCRSs.contains(crs) else { continue }
            let point = MKMapPoint(station.coordinate)
            for candidate in lineCandidates {
                guard !Task.isCancelled else { return [:] }
                guard !candidate.existingCalls.contains(crs),
                      isUsable(candidate.paddedRect),
                      candidate.paddedRect.contains(point),
                      let projection = candidate.line.corridorRoute.projection(
                          closestTo: station.coordinate
                      ),
                      projection.offsetFromRoute <= maximumOffset,
                      projection.routeDistance > endpointClearance,
                      projection.routeDistance
                        < candidate.line.corridorRoute.totalLength - endpointClearance else {
                    continue
                }
                result[crs, default: []].append(candidate.line.id)
            }
        }
        return result
    }

    static func paddedMapRect(_ rect: MKMapRect, horizontal: Double = 0.24, vertical: Double = 0.28) -> MKMapRect {
        guard isUsable(rect) else { return rect }
        let horizontalPadding = rect.width * max(horizontal, 0)
        let verticalPadding = rect.height * max(vertical, 0)
        return MKMapRect(
            x: rect.minX - horizontalPadding,
            y: rect.minY - verticalPadding,
            width: rect.width + horizontalPadding * 2,
            height: rect.height + verticalPadding * 2
        )
    }

    /// Camera following can emit a settled camera update on every simulation tick. The rendered
    /// station set already includes a padded fringe, so it only needs rebuilding after a material
    /// pan or zoom rather than for tiny movements within that fringe.
    static func viewportRequiresStationRefresh(
        previous: MKMapRect?,
        current: MKMapRect
    ) -> Bool {
        guard let previous, isUsable(previous), isUsable(current) else { return true }
        let widthRatio = current.width / previous.width
        let heightRatio = current.height / previous.height
        guard (0.78...1.28).contains(widthRatio),
              (0.78...1.28).contains(heightRatio) else {
            return true
        }
        return abs(current.midX - previous.midX) > previous.width * 0.14
            || abs(current.midY - previous.midY) > previous.height * 0.16
    }

    /// Returns nearby unbuilt and built stations under separate strict tier budgets, followed by
    /// the handful of actively selected stations even when they are offscreen. Built stations are
    /// preferred over catalogue candidates and draw above them without allowing a completed
    /// national network to recreate thousands of simultaneous annotations.
    static func renderedStations(
        from stations: [Station],
        builtStationCRSs: Set<String>,
        selectedStationCRSs: Set<String>,
        visibleMapRect: MKMapRect,
        detailLevel: RailwayMapRenderingDetailLevel
    ) -> [Station] {
        let normalizedBuiltCRSs = Set(builtStationCRSs.map(normalizedCRS))
        let normalizedSelectedCRSs = Set(selectedStationCRSs.map(normalizedCRS))
        let candidateRect = paddedMapRect(visibleMapRect)
        let centre = MKMapPoint(x: visibleMapRect.midX, y: visibleMapRect.midY)

        var selectedStations = [Station]()
        var builtStations = [(station: Station, distanceSquared: Double)]()
        var candidates = [(station: Station, distanceSquared: Double)]()
        selectedStations.reserveCapacity(min(normalizedSelectedCRSs.count, stations.count))
        builtStations.reserveCapacity(min(detailLevel.builtStationLimit * 2, stations.count))
        candidates.reserveCapacity(min(detailLevel.candidateStationLimit * 2, stations.count))

        for station in stations {
            let normalizedStationCRS = normalizedCRS(station.crs)
            if normalizedSelectedCRSs.contains(normalizedStationCRS) {
                selectedStations.append(station)
                continue
            }
            let point = MKMapPoint(station.coordinate)
            guard candidateRect.contains(point) else { continue }
            let deltaX = point.x - centre.x
            let deltaY = point.y - centre.y
            let distanceSquared = (deltaX * deltaX) + (deltaY * deltaY)
            if normalizedBuiltCRSs.contains(normalizedStationCRS) {
                builtStations.append((station, distanceSquared))
            } else {
                candidates.append((station, distanceSquared))
            }
        }

        func orderedByDistance(
            _ lhs: (station: Station, distanceSquared: Double),
            _ rhs: (station: Station, distanceSquared: Double)
        ) -> Bool {
            if lhs.distanceSquared != rhs.distanceSquared {
                return lhs.distanceSquared < rhs.distanceSquared
            }
            return normalizedCRS(lhs.station.crs) < normalizedCRS(rhs.station.crs)
        }
        candidates.sort(by: orderedByDistance)
        builtStations.sort(by: orderedByDistance)
        selectedStations.sort { normalizedCRS($0.crs) < normalizedCRS($1.crs) }

        return candidates.prefix(detailLevel.candidateStationLimit).map(\.station)
            + builtStations.prefix(detailLevel.builtStationLimit).map(\.station)
            + selectedStations
    }

    /// Uniform source-index sampling is cheap, deterministic and has a hard output bound. Both
    /// endpoints are always preserved so construction frontiers and terminals stay exact.
    static func simplifiedCoordinates(
        _ coordinates: [CLLocationCoordinate2D],
        maximumPointCount rawMaximumPointCount: Int
    ) -> [CLLocationCoordinate2D] {
        let maximumPointCount = max(rawMaximumPointCount, 2)
        guard coordinates.count > maximumPointCount else { return coordinates }

        let lastSourceIndex = coordinates.count - 1
        let lastDestinationIndex = maximumPointCount - 1
        return (0..<maximumPointCount).map { destinationIndex in
            let sourceIndex = Int(
                (Double(destinationIndex) * Double(lastSourceIndex) / Double(lastDestinationIndex))
                    .rounded()
            )
            return coordinates[min(max(sourceIndex, 0), lastSourceIndex)]
        }
    }

    static func mapRect(containing coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        coordinates.reduce(MKMapRect.null) { result, coordinate in
            let point = MKMapPoint(coordinate)
            return result.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }
    }

    static func polyline(
        _ coordinates: [CLLocationCoordinate2D],
        intersects visibleMapRect: MKMapRect
    ) -> Bool {
        guard isUsable(visibleMapRect), !coordinates.isEmpty else { return false }
        if coordinates.contains(where: { visibleMapRect.contains(MKMapPoint($0)) }) {
            return true
        }
        guard coordinates.count > 1 else { return false }

        for index in coordinates.indices.dropLast() {
            let start = MKMapPoint(coordinates[index])
            let end = MKMapPoint(coordinates[index + 1])
            let segmentBounds = MKMapRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: max(abs(end.x - start.x), 1),
                height: max(abs(end.y - start.y), 1)
            )
            if segmentBounds.intersects(visibleMapRect) {
                return true
            }
        }
        return false
    }

    static func renderedTrains(
        from trains: [TrainState],
        selectedTrainID: UUID?,
        visibleMapRect: MKMapRect,
        maximumCount: Int
    ) -> [TrainState] {
        let renderRect = paddedMapRect(visibleMapRect, horizontal: 0.12, vertical: 0.16)
        let centre = MKMapPoint(x: visibleMapRect.midX, y: visibleMapRect.midY)
        var selected: TrainState?
        var candidates = [(train: TrainState, distanceSquared: Double)]()

        for train in trains {
            if train.id == selectedTrainID {
                selected = train
                continue
            }
            let point = MKMapPoint(train.coordinate)
            guard renderRect.contains(point) else { continue }
            let deltaX = point.x - centre.x
            let deltaY = point.y - centre.y
            candidates.append((train, (deltaX * deltaX) + (deltaY * deltaY)))
        }
        candidates.sort { lhs, rhs in
            if lhs.distanceSquared != rhs.distanceSquared {
                return lhs.distanceSquared < rhs.distanceSquared
            }
            return lhs.train.id.uuidString < rhs.train.id.uuidString
        }

        var result = candidates.prefix(max(maximumCount, 0)).map(\.train)
        if let selected {
            result.append(selected)
        }
        return result
    }

    /// Selects the routes that are closest to the visible viewport under a strict overlay budget.
    /// The actively focused route is retained inside that budget, even while a camera animation is
    /// moving towards it, and deterministic UUID ordering prevents visual churn at equal distance.
    static func renderedLineIDs(
        from candidates: [RailwayMapLineCandidate],
        focusedLineID: UUID?,
        visibleMapRect: MKMapRect,
        maximumCount: Int
    ) -> [UUID] {
        let maximumCount = max(maximumCount, 0)
        guard maximumCount > 0, isUsable(visibleMapRect) else { return [] }

        let renderRect = paddedMapRect(visibleMapRect, horizontal: 0.18, vertical: 0.22)
        let centre = MKMapPoint(x: visibleMapRect.midX, y: visibleMapRect.midY)
        var focused: RailwayMapLineCandidate?
        var visible = [(candidate: RailwayMapLineCandidate, distanceSquared: Double)]()
        visible.reserveCapacity(min(candidates.count, maximumCount * 2))

        for candidate in candidates {
            if candidate.id == focusedLineID {
                focused = candidate
                continue
            }
            guard isUsable(candidate.mapRect), candidate.mapRect.intersects(renderRect) else {
                continue
            }
            visible.append((candidate, squaredDistance(from: centre, to: candidate.mapRect)))
        }

        visible.sort { lhs, rhs in
            if lhs.distanceSquared != rhs.distanceSquared {
                return lhs.distanceSquared < rhs.distanceSquared
            }
            return lhs.candidate.id.uuidString < rhs.candidate.id.uuidString
        }

        let visibleBudget = maximumCount - (focused == nil ? 0 : 1)
        var result = visible.prefix(max(visibleBudget, 0)).map(\.candidate.id)
        if let focused {
            result.append(focused.id)
        }
        return result
    }

    static func isUsable(_ rect: MKMapRect) -> Bool {
        !rect.isNull
            && !rect.isEmpty
            && rect.origin.x.isFinite
            && rect.origin.y.isFinite
            && rect.width.isFinite
            && rect.height.isFinite
            && rect.width > 0
            && rect.height > 0
    }

    private static func normalizedCRS(_ crs: String) -> String {
        crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func squaredDistance(from point: MKMapPoint, to rect: MKMapRect) -> Double {
        let nearestX = min(max(point.x, rect.minX), rect.maxX)
        let nearestY = min(max(point.y, rect.minY), rect.maxY)
        let deltaX = point.x - nearestX
        let deltaY = point.y - nearestY
        return deltaX * deltaX + deltaY * deltaY
    }
}

nonisolated struct RailwayMapLineCandidate: Sendable {
    let id: UUID
    let mapRect: MKMapRect
}

/// Memoizes the expensive geometry projections independently from SwiftUI observation updates.
/// Train movement can therefore redraw at its existing cadence without re-sampling every route.
@MainActor
final class RailwayMapRenderingCache {
    private struct GeometryFingerprint: Equatable {
        let coordinateCount: Int
        let totalLengthBitPattern: UInt64
        let firstLatitude: UInt64
        let firstLongitude: UInt64
        let quarterLatitude: UInt64
        let quarterLongitude: UInt64
        let middleLatitude: UInt64
        let middleLongitude: UInt64
        let threeQuarterLatitude: UInt64
        let threeQuarterLongitude: UInt64
        let lastLatitude: UInt64
        let lastLongitude: UInt64

        init(route: ServiceRailwayRoute) {
            coordinateCount = route.coordinates.count
            totalLengthBitPattern = route.totalLength.bitPattern
            let fallback = CLLocationCoordinate2D(latitude: 0, longitude: 0)
            let first = route.coordinates.first ?? fallback
            let quarter = route.coordinates.isEmpty
                ? fallback
                : route.coordinates[route.coordinates.count / 4]
            let middle = route.coordinates.isEmpty
                ? fallback
                : route.coordinates[route.coordinates.count / 2]
            let threeQuarter = route.coordinates.isEmpty
                ? fallback
                : route.coordinates[(route.coordinates.count * 3) / 4]
            let last = route.coordinates.last ?? fallback
            firstLatitude = first.latitude.bitPattern
            firstLongitude = first.longitude.bitPattern
            quarterLatitude = quarter.latitude.bitPattern
            quarterLongitude = quarter.longitude.bitPattern
            middleLatitude = middle.latitude.bitPattern
            middleLongitude = middle.longitude.bitPattern
            threeQuarterLatitude = threeQuarter.latitude.bitPattern
            threeQuarterLongitude = threeQuarter.longitude.bitPattern
            lastLatitude = last.latitude.bitPattern
            lastLongitude = last.longitude.bitPattern
        }
    }

    private struct CachedGeometry {
        let fingerprint: GeometryFingerprint
        let route: ServiceRailwayRoute
        var fullCoordinatesByLevel: [RailwayMapRenderingDetailLevel: [CLLocationCoordinate2D]] = [:]
        var partialCoordinatesByKey: [PartialKey: [CLLocationCoordinate2D]] = [:]
        var framingMapRect: MKMapRect?
    }

    private struct PartialKey: Hashable {
        let detailLevel: RailwayMapRenderingDetailLevel
        let progressBucket: Int
    }

    private var lineGeometries: [UUID: CachedGeometry] = [:]
    private var previewGeometry: CachedGeometry?

    func coordinates(
        for line: BuiltLine,
        detailLevel: RailwayMapRenderingDetailLevel
    ) -> [CLLocationCoordinate2D] {
        var geometry = cachedGeometry(for: line.route, existing: lineGeometries[line.id])
        let result: [CLLocationCoordinate2D]
        if line.isConstructed {
            result = fullCoordinates(in: &geometry, detailLevel: detailLevel)
        } else {
            let clampedProgress = min(max(line.constructionProgress, 0), 1)
            let progressBucket = Int((clampedProgress * 240).rounded(.down))
            let key = PartialKey(detailLevel: detailLevel, progressBucket: progressBucket)
            if let cached = geometry.partialCoordinatesByKey[key] {
                result = cached
            } else {
                let bucketProgress = min(Double(progressBucket + 1) / 240, clampedProgress)
                let rawCoordinates = line.route.coordinates(
                    upToDistance: line.route.totalLength * bucketProgress
                )
                let simplified = RailwayMapRenderingPolicy.simplifiedCoordinates(
                    rawCoordinates,
                    maximumPointCount: detailLevel.maximumRoutePointCount
                )
                geometry.partialCoordinatesByKey[key] = simplified
                if geometry.partialCoordinatesByKey.count > 8 {
                    geometry.partialCoordinatesByKey = [key: simplified]
                }
                result = simplified
            }
        }
        lineGeometries[line.id] = geometry
        return result
    }

    func previewCoordinates(
        for route: ServiceRailwayRoute,
        detailLevel: RailwayMapRenderingDetailLevel
    ) -> [CLLocationCoordinate2D] {
        var geometry = cachedGeometry(for: route, existing: previewGeometry)
        let result = fullCoordinates(in: &geometry, detailLevel: detailLevel)
        previewGeometry = geometry
        return result
    }

    /// A bounded per-line rectangle for framing restored networks.
    ///
    /// Country-level coordinates already retain both endpoints and at most 128 uniformly sampled
    /// points. Reusing that cached representation avoids flattening every raw route coordinate
    /// into one potentially enormous temporary array when a national save first opens.
    func framingMapRect(for line: BuiltLine) -> MKMapRect {
        var geometry = cachedGeometry(for: line.route, existing: lineGeometries[line.id])
        if let cached = geometry.framingMapRect {
            lineGeometries[line.id] = geometry
            return cached
        }
        let coordinates = fullCoordinates(in: &geometry, detailLevel: .country)
        let result = RailwayMapRenderingPolicy.mapRect(containing: coordinates)
        geometry.framingMapRect = result
        lineGeometries[line.id] = geometry
        return result
    }

    func removeLines(except validLineIDs: Set<UUID>) {
        lineGeometries = lineGeometries.filter { validLineIDs.contains($0.key) }
    }

    private func cachedGeometry(
        for route: ServiceRailwayRoute,
        existing: CachedGeometry?
    ) -> CachedGeometry {
        let fingerprint = GeometryFingerprint(route: route)
        if let existing, existing.fingerprint == fingerprint {
            return existing
        }
        return CachedGeometry(fingerprint: fingerprint, route: route)
    }

    private func fullCoordinates(
        in geometry: inout CachedGeometry,
        detailLevel: RailwayMapRenderingDetailLevel
    ) -> [CLLocationCoordinate2D] {
        if let cached = geometry.fullCoordinatesByLevel[detailLevel] {
            return cached
        }
        let coordinates = RailwayMapRenderingPolicy.simplifiedCoordinates(
            geometry.route.coordinates,
            maximumPointCount: detailLevel.maximumRoutePointCount
        )
        geometry.fullCoordinatesByLevel[detailLevel] = coordinates
        return coordinates
    }
}
