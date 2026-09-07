import CoreLocation
import Foundation

nonisolated enum RouteTravelDirection: Sendable {
    case forward
    case reverse
}

nonisolated struct RouteSample: Sendable {
    let coordinate: CLLocationCoordinate2D
    /// Degrees clockwise from true north, suitable for rotating a map annotation.
    let bearing: CLLocationDirection
}

/// The closest point on a routed railway polyline to a geographic coordinate.
///
/// `routeCoordinateIndex` identifies the nearest existing route vertex while `routeDistance`
/// and `routeProgress` retain the more precise position within the adjoining segment. This lets
/// callers order station calls without altering the proven route geometry.
nonisolated struct RailwayRouteProjection: Sendable {
    let coordinate: CLLocationCoordinate2D
    let routeDistance: CLLocationDistance
    let routeProgress: Double
    let routeCoordinateIndex: Int
    let offsetFromRoute: CLLocationDistance
}

nonisolated struct ServiceRailwayRoute: Sendable {
    let coordinates: [CLLocationCoordinate2D]
    let cumulativeDistances: [CLLocationDistance]
    let stationCoordinateIndices: [Int]

    var totalLength: CLLocationDistance {
        cumulativeDistances.last ?? 0
    }

    var stationCount: Int {
        stationCoordinateIndices.count
    }

    init(
        coordinates: [CLLocationCoordinate2D],
        cumulativeDistances: [CLLocationDistance],
        stationCoordinateIndices: [Int]
    ) {
        self.coordinates = coordinates
        self.cumulativeDistances = cumulativeDistances
        self.stationCoordinateIndices = stationCoordinateIndices
    }

    /// Convenience initializer for fixtures and route geometry created outside the OSM graph.
    init(
        coordinates: [CLLocationCoordinate2D],
        stationCoordinateIndices: [Int]? = nil
    ) {
        self.coordinates = coordinates
        self.cumulativeDistances = Self.distances(for: coordinates)
        if let stationCoordinateIndices {
            self.stationCoordinateIndices = stationCoordinateIndices
        } else if coordinates.isEmpty {
            self.stationCoordinateIndices = []
        } else if coordinates.count == 1 {
            self.stationCoordinateIndices = [0]
        } else {
            self.stationCoordinateIndices = [0, coordinates.count - 1]
        }
    }

    func coordinate(atStation index: Int) -> CLLocationCoordinate2D? {
        guard stationCoordinateIndices.indices.contains(index) else { return nil }
        let coordinateIndex = stationCoordinateIndices[index]
        guard coordinates.indices.contains(coordinateIndex) else { return nil }
        return coordinates[coordinateIndex]
    }

    func coordinate(atFloatingStationIndex index: Double) -> CLLocationCoordinate2D? {
        guard stationCount > 0, index.isFinite else { return nil }
        let clamped = min(max(index, 0), Double(stationCount - 1))
        let lowerStation = Int(floor(clamped))
        let upperStation = Int(ceil(clamped))
        if lowerStation == upperStation {
            return coordinate(atStation: lowerStation)
        }

        guard stationCoordinateIndices.indices.contains(lowerStation),
              stationCoordinateIndices.indices.contains(upperStation),
              cumulativeDistances.indices.contains(stationCoordinateIndices[lowerStation]),
              cumulativeDistances.indices.contains(stationCoordinateIndices[upperStation]) else {
            return nil
        }
        let lowerDistance = cumulativeDistances[stationCoordinateIndices[lowerStation]]
        let upperDistance = cumulativeDistances[stationCoordinateIndices[upperStation]]
        let progress = clamped - Double(lowerStation)
        return coordinate(
            atAbsoluteDistance: lowerDistance + ((upperDistance - lowerDistance) * progress)
        )
    }

    func coordinate(
        fromStation start: Int,
        toStation end: Int,
        progress: Double
    ) -> CLLocationCoordinate2D? {
        guard progress.isFinite,
              stationCoordinateIndices.indices.contains(start),
              stationCoordinateIndices.indices.contains(end),
              cumulativeDistances.indices.contains(stationCoordinateIndices[start]),
              cumulativeDistances.indices.contains(stationCoordinateIndices[end]) else {
            return nil
        }
        let clampedProgress = min(max(progress, 0), 1)
        let startDistance = cumulativeDistances[stationCoordinateIndices[start]]
        let endDistance = cumulativeDistances[stationCoordinateIndices[end]]
        return coordinate(
            atAbsoluteDistance: startDistance + ((endDistance - startDistance) * clampedProgress)
        )
    }

    /// Samples metres travelled from the selected direction's origin.
    ///
    /// Forward distance zero is the first route coordinate. Reverse distance zero is the last.
    /// Out-of-range finite values are clamped so animation overshoot remains safe.
    func sample(
        atDistance distance: CLLocationDistance,
        direction: RouteTravelDirection = .forward
    ) -> RouteSample? {
        guard distance.isFinite,
              !coordinates.isEmpty,
              cumulativeDistances.count == coordinates.count else {
            return nil
        }

        let clampedTravelDistance = min(max(distance, 0), totalLength)
        let absoluteDistance = direction == .forward
            ? clampedTravelDistance
            : totalLength - clampedTravelDistance
        guard let coordinate = coordinate(atAbsoluteDistance: absoluteDistance) else {
            return nil
        }

        let bearing: CLLocationDirection
        if let segment = bearingSegment(
            atAbsoluteDistance: absoluteDistance,
            direction: direction
        ) {
            switch direction {
            case .forward:
                bearing = Self.bearing(from: coordinates[segment], to: coordinates[segment + 1])
            case .reverse:
                bearing = Self.bearing(from: coordinates[segment + 1], to: coordinates[segment])
            }
        } else {
            bearing = 0
        }

        return RouteSample(coordinate: coordinate, bearing: bearing)
    }

    /// Returns a continuous construction-reveal polyline, including an interpolated endpoint.
    func coordinates(
        upToDistance distance: CLLocationDistance,
        direction: RouteTravelDirection = .forward
    ) -> [CLLocationCoordinate2D] {
        guard distance.isFinite,
              !coordinates.isEmpty,
              cumulativeDistances.count == coordinates.count else {
            return []
        }

        let clampedTravelDistance = min(max(distance, 0), totalLength)
        guard let sample = sample(atDistance: clampedTravelDistance, direction: direction) else {
            return []
        }
        let absoluteDistance = direction == .forward
            ? clampedTravelDistance
            : totalLength - clampedTravelDistance

        var result = [CLLocationCoordinate2D]()
        switch direction {
        case .forward:
            for index in coordinates.indices where cumulativeDistances[index] <= absoluteDistance {
                result.append(coordinates[index])
            }
        case .reverse:
            for index in coordinates.indices.reversed()
                where cumulativeDistances[index] >= absoluteDistance {
                result.append(coordinates[index])
            }
        }

        if let last = result.last {
            if !Self.coordinatesAreEqual(last, sample.coordinate) {
                result.append(sample.coordinate)
            }
        } else {
            result.append(sample.coordinate)
        }
        return result
    }

    /// Returns a continuous forward polyline between two absolute route distances, including
    /// interpolated endpoints. This is used for short infrastructure highlights such as loops.
    func coordinates(
        fromDistance rawStart: CLLocationDistance,
        toDistance rawEnd: CLLocationDistance
    ) -> [CLLocationCoordinate2D] {
        guard rawStart.isFinite,
              rawEnd.isFinite,
              !coordinates.isEmpty,
              cumulativeDistances.count == coordinates.count else {
            return []
        }
        let start = min(max(min(rawStart, rawEnd), 0), totalLength)
        let end = min(max(max(rawStart, rawEnd), 0), totalLength)
        guard let startCoordinate = coordinate(atAbsoluteDistance: start),
              let endCoordinate = coordinate(atAbsoluteDistance: end) else {
            return []
        }

        var result = [startCoordinate]
        for index in coordinates.indices
            where cumulativeDistances[index] > start && cumulativeDistances[index] < end {
            result.append(coordinates[index])
        }
        if !Self.coordinatesAreEqual(result.last ?? startCoordinate, endCoordinate) {
            result.append(endCoordinate)
        }
        return result
    }

    func floatingStationIndex(closestTo coordinate: CLLocationCoordinate2D) -> Double? {
        guard coordinates.count >= 2,
              cumulativeDistances.count == coordinates.count,
              stationCount >= 2,
              let projectedDistance = projection(closestTo: coordinate)?.routeDistance else {
            return stationCount == 1 ? 0 : nil
        }

        for upperStation in 1..<stationCount {
            let lowerCoordinateIndex = stationCoordinateIndices[upperStation - 1]
            let upperCoordinateIndex = stationCoordinateIndices[upperStation]
            guard cumulativeDistances.indices.contains(lowerCoordinateIndex),
                  cumulativeDistances.indices.contains(upperCoordinateIndex) else {
                return nil
            }
            let lowerDistance = cumulativeDistances[lowerCoordinateIndex]
            let upperDistance = cumulativeDistances[upperCoordinateIndex]
            guard projectedDistance <= upperDistance else { continue }
            let segmentLength = upperDistance - lowerDistance
            guard segmentLength > 0 else { return Double(upperStation) }
            let fraction = min(max(
                (projectedDistance - lowerDistance) / segmentLength,
                0
            ), 1)
            return Double(upperStation - 1) + fraction
        }
        return Double(stationCount - 1)
    }

    /// Projects a coordinate onto the route and reports its ordered position and lateral offset.
    /// Degenerate and malformed routes fail safely instead of producing non-finite progress.
    func projection(closestTo coordinate: CLLocationCoordinate2D) -> RailwayRouteProjection? {
        guard coordinate.latitude.isFinite,
              coordinate.longitude.isFinite,
              (-90...90).contains(coordinate.latitude),
              (-180...180).contains(coordinate.longitude),
              cumulativeDistances.count == coordinates.count,
              let first = coordinates.first else {
            return nil
        }

        if coordinates.count == 1 {
            return RailwayRouteProjection(
                coordinate: first,
                routeDistance: 0,
                routeProgress: 0,
                routeCoordinateIndex: 0,
                offsetFromRoute: straightLineDistance(first, coordinate)
            )
        }

        let metresPerDegreeLatitude = 111_132.0
        let metresPerDegreeLongitude = 111_320.0 * cos(coordinate.latitude * .pi / 180)
        func localPoint(_ routeCoordinate: CLLocationCoordinate2D) -> (x: Double, y: Double) {
            (
                x: (routeCoordinate.longitude - coordinate.longitude) * metresPerDegreeLongitude,
                y: (routeCoordinate.latitude - coordinate.latitude) * metresPerDegreeLatitude
            )
        }

        var closestOffset = CLLocationDistance.infinity
        var closestRouteDistance: CLLocationDistance?
        var closestCoordinate: CLLocationCoordinate2D?
        var closestCoordinateIndex = 0
        for index in coordinates.indices.dropLast() {
            let start = localPoint(coordinates[index])
            let end = localPoint(coordinates[index + 1])
            let deltaX = end.x - start.x
            let deltaY = end.y - start.y
            let squaredLength = (deltaX * deltaX) + (deltaY * deltaY)
            let fraction = squaredLength > 0
                ? min(max(-((start.x * deltaX) + (start.y * deltaY)) / squaredLength, 0), 1)
                : 0
            let offset = hypot(
                start.x + (deltaX * fraction),
                start.y + (deltaY * fraction)
            )
            guard offset < closestOffset else { continue }

            let segmentLength = cumulativeDistances[index + 1] - cumulativeDistances[index]
            guard segmentLength >= 0, segmentLength.isFinite else { return nil }
            closestOffset = offset
            closestRouteDistance = cumulativeDistances[index] + (segmentLength * fraction)
            closestCoordinate = CLLocationCoordinate2D(
                latitude: coordinates[index].latitude
                    + ((coordinates[index + 1].latitude - coordinates[index].latitude) * fraction),
                longitude: coordinates[index].longitude
                    + ((coordinates[index + 1].longitude - coordinates[index].longitude) * fraction)
            )
            closestCoordinateIndex = fraction <= 0.5 ? index : index + 1
        }

        guard let closestRouteDistance,
              let closestCoordinate,
              closestOffset.isFinite else {
            return nil
        }
        let progress = totalLength > 0
            ? min(max(closestRouteDistance / totalLength, 0), 1)
            : 0
        return RailwayRouteProjection(
            coordinate: closestCoordinate,
            routeDistance: closestRouteDistance,
            routeProgress: progress,
            routeCoordinateIndex: closestCoordinateIndex,
            offsetFromRoute: closestOffset
        )
    }

    func coordinates(fromStation start: Int, throughStation end: Int) -> [CLLocationCoordinate2D] {
        guard stationCount > 0 else { return [] }
        let lowerStation = min(max(min(start, end), 0), stationCount - 1)
        let upperStation = min(max(max(start, end), 0), stationCount - 1)
        let lowerCoordinate = stationCoordinateIndices[lowerStation]
        let upperCoordinate = stationCoordinateIndices[upperStation]
        guard coordinates.indices.contains(lowerCoordinate),
              coordinates.indices.contains(upperCoordinate),
              lowerCoordinate <= upperCoordinate else {
            return []
        }
        return Array(coordinates[lowerCoordinate...upperCoordinate])
    }

    func reversed() -> ServiceRailwayRoute {
        let lastIndex = max(0, coordinates.count - 1)
        return ServiceRailwayRoute(
            coordinates: Array(coordinates.reversed()),
            stationCoordinateIndices: stationCoordinateIndices.reversed().map { lastIndex - $0 }
        )
    }

    private func coordinate(
        atAbsoluteDistance distance: CLLocationDistance
    ) -> CLLocationCoordinate2D? {
        guard let first = coordinates.first,
              let last = coordinates.last,
              cumulativeDistances.count == coordinates.count,
              distance.isFinite else {
            return nil
        }
        if distance <= 0 { return first }
        if distance >= totalLength { return last }

        let upperIndex = lowerBound(for: distance)
        let lowerIndex = max(0, upperIndex - 1)
        let segmentStart = cumulativeDistances[lowerIndex]
        let segmentEnd = cumulativeDistances[upperIndex]
        let segmentLength = segmentEnd - segmentStart
        guard segmentLength > 0 else { return coordinates[upperIndex] }
        let progress = (distance - segmentStart) / segmentLength
        let start = coordinates[lowerIndex]
        let end = coordinates[upperIndex]
        return CLLocationCoordinate2D(
            latitude: start.latitude + ((end.latitude - start.latitude) * progress),
            longitude: start.longitude + ((end.longitude - start.longitude) * progress)
        )
    }

    private func lowerBound(for distance: CLLocationDistance) -> Int {
        var lower = 0
        var upper = cumulativeDistances.count - 1
        while lower < upper {
            let middle = (lower + upper) / 2
            if cumulativeDistances[middle] < distance {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func bearingSegment(
        atAbsoluteDistance distance: CLLocationDistance,
        direction: RouteTravelDirection
    ) -> Int? {
        guard coordinates.count >= 2 else { return nil }
        let upperIndex = lowerBound(for: distance)
        let startsAtVertex = cumulativeDistances[upperIndex] == distance

        let preferred: Int
        switch direction {
        case .forward:
            preferred = startsAtVertex && upperIndex < coordinates.count - 1
                ? upperIndex
                : max(0, upperIndex - 1)
        case .reverse:
            preferred = max(0, upperIndex - 1)
        }

        if segmentHasLength(preferred) { return preferred }

        switch direction {
        case .forward:
            if preferred + 1 < coordinates.count - 1 {
                for index in (preferred + 1)..<(coordinates.count - 1)
                    where segmentHasLength(index) {
                    return index
                }
            }
            if preferred > 0 {
                for index in stride(from: preferred - 1, through: 0, by: -1)
                    where segmentHasLength(index) {
                    return index
                }
            }
        case .reverse:
            if preferred > 0 {
                for index in stride(from: preferred - 1, through: 0, by: -1)
                    where segmentHasLength(index) {
                    return index
                }
            }
            if preferred + 1 < coordinates.count - 1 {
                for index in (preferred + 1)..<(coordinates.count - 1)
                    where segmentHasLength(index) {
                    return index
                }
            }
        }
        return nil
    }

    private func segmentHasLength(_ index: Int) -> Bool {
        guard index >= 0,
              index + 1 < cumulativeDistances.count else {
            return false
        }
        return cumulativeDistances[index + 1] > cumulativeDistances[index]
    }

    private static func distances(
        for coordinates: [CLLocationCoordinate2D]
    ) -> [CLLocationDistance] {
        guard !coordinates.isEmpty else { return [] }
        var result = Array(repeating: 0.0, count: coordinates.count)
        if coordinates.count > 1 {
            for index in 1..<coordinates.count {
                result[index] = result[index - 1]
                    + straightLineDistance(coordinates[index - 1], coordinates[index])
            }
        }
        return result
    }

    private static func bearing(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> CLLocationDirection {
        let startLatitude = start.latitude * .pi / 180
        let endLatitude = end.latitude * .pi / 180
        let longitudeDelta = (end.longitude - start.longitude) * .pi / 180
        let y = sin(longitudeDelta) * cos(endLatitude)
        let x = (cos(startLatitude) * sin(endLatitude))
            - (sin(startLatitude) * cos(endLatitude) * cos(longitudeDelta))
        guard x != 0 || y != 0 else { return 0 }
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func coordinatesAreEqual(
        _ first: CLLocationCoordinate2D,
        _ second: CLLocationCoordinate2D
    ) -> Bool {
        abs(first.latitude - second.latitude) < 0.000_000_001
            && abs(first.longitude - second.longitude) < 0.000_000_001
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
