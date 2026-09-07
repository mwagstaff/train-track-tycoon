import CoreLocation
import XCTest
@testable import TrainTrackTycoon

/// Repeatable performance baselines for simulation hot paths.
///
/// XCTest records clock and CPU measurements for comparison in Xcode. There are no
/// hard-coded duration limits: functional assertions guard correctness, while performance
/// regression policy remains a baseline decision for the target device or CI environment.
@MainActor
final class SimulationPerformanceBenchmarks: XCTestCase {
    func testMaximumNetworkDailySettlementPerformance() async throws {
        let session = try await makeMaximumNetwork()

        // Fill the retained-history window before measurement. Each measured iteration therefore
        // has the same bounded replace-and-trim workload instead of measuring initial growth.
        session.tick(delta: .greatestFiniteMagnitude)
        XCTAssertEqual(session.economyLedger.completedOperatingDays, 120)
        XCTAssertEqual(session.publicBetaHistory.records.count, 120)
        XCTAssertGreaterThan(session.passengerSnapshot.connectingJourneysPerDay, 0)

        let options = XCTMeasureOptions.default
        options.iterationCount = 5
        var measuredBlockCount = 0
        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric()],
            options: options
        ) {
            measuredBlockCount += 1
            // One block represents four simulated months at the maximum beta network size. It
            // exercises train movement, daily finance, demand, happiness, station growth,
            // progression history, and bounded presentation-event retention.
            for _ in 0..<120 {
                session.tick(delta: 30)
            }
        }

        XCTAssertEqual(session.lines.count, 12)
        XCTAssertEqual(session.trains.count, 48)
        XCTAssertGreaterThanOrEqual(measuredBlockCount, options.iterationCount)
        XCTAssertEqual(
            session.economyLedger.completedOperatingDays,
            120 + (UInt64(measuredBlockCount) * 120)
        )
        XCTAssertEqual(session.passengerSnapshot.connectingJourneySnapshots.count, 66)
        XCTAssertGreaterThan(session.passengerSnapshot.connectingJourneysPerDay, 0)
        XCTAssertEqual(session.publicBetaHistory.records.count, 120)
        XCTAssertLessThanOrEqual(session.presentationEvents(after: 0).count, 32)
        XCTAssertTrue(session.lines.allSatisfy(\.isConstructed))
        XCTAssertTrue(session.trains.allSatisfy { train in
            train.distanceAlongRoute.isFinite
                && train.dwellRemaining.isFinite
                && train.bearing.isFinite
        })
    }

    func testRepresentativeRouteSamplingPerformance() {
        let route = makeRepresentativeRoute(pointCount: 4_096, metresPerSegment: 25)
        var samplingChecksum = 0.0

        let options = XCTMeasureOptions.default
        options.iterationCount = 5
        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric()],
            options: options
        ) {
            var iterationChecksum = 0.0
            for sampleIndex in 0..<50_000 {
                let distance = Double((sampleIndex * 7_919) % 102_375)
                let direction: RouteTravelDirection = sampleIndex.isMultiple(of: 2)
                    ? .forward
                    : .reverse
                if let sample = route.sample(atDistance: distance, direction: direction) {
                    iterationChecksum += sample.coordinate.latitude
                        + sample.coordinate.longitude
                        + sample.bearing
                }
            }
            samplingChecksum = iterationChecksum
        }

        XCTAssertTrue(samplingChecksum.isFinite)
        XCTAssertGreaterThan(samplingChecksum, 0)
        XCTAssertEqual(route.coordinates.count, 4_096)
        XCTAssertEqual(route.totalLength, 102_375)
    }

    private func makeMaximumNetwork() async throws -> GameSession {
        let stations = benchmarkStations
        let session = GameSession(
            stations: stations,
            routingProvider: BenchmarkRoutingProvider(route: benchmarkRoute),
            gameMode: .zen,
            clock: BenchmarkClock(),
            configuration: GameConfiguration(
                maximumLineCount: 12,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 20,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000,
                operatingDayDuration: 30
            )
        )

        let hub = try XCTUnwrap(stations.first)
        for (index, destination) in stations.dropFirst().enumerated() {
            let railwayClass: RailwayClass = index.isMultiple(of: 4)
                ? .highSpeed
                : .conventional
            try await addLine(
                from: hub,
                to: destination,
                railwayClass: railwayClass,
                in: session
            )
            let lineID = try XCTUnwrap(session.lines.last?.id)
            session.setServiceFrequency(.quarterHourly, forLineID: lineID)
            if railwayClass == .conventional {
                session.setServicePattern(.balanced, forLineID: lineID)
                XCTAssertTrue(session.upgradeTrackCapacity(forLineID: lineID))
            }
        }

        XCTAssertEqual(session.lines.count, 12)
        XCTAssertEqual(session.trains.count, 48)
        XCTAssertEqual(session.passengerSnapshot.connectingJourneySnapshots.count, 66)
        return session
    }

    private func addLine(
        from origin: Station,
        to destination: Station,
        railwayClass: RailwayClass,
        in session: GameSession
    ) async throws {
        session.startBuilding()
        session.selectStation(origin)
        session.selectStation(destination)
        await session.waitForRouteCalculation()
        XCTAssertEqual(session.phase, .preview)
        session.setPreviewRailwayClass(railwayClass)
        session.confirmPreview()
        XCTAssertEqual(session.phase, .operating)
    }

    private func makeRepresentativeRoute(
        pointCount: Int,
        metresPerSegment: CLLocationDistance
    ) -> ServiceRailwayRoute {
        let coordinates = (0..<pointCount).map { index in
            let progress = Double(index) / Double(max(pointCount - 1, 1))
            return CLLocationCoordinate2D(
                latitude: 51.50 - progress * 0.67 + sin(progress * 24) * 0.002,
                longitude: -0.14 + sin(progress * 10) * 0.035
            )
        }
        let cumulativeDistances = coordinates.indices.map {
            Double($0) * metresPerSegment
        }
        return ServiceRailwayRoute(
            coordinates: coordinates,
            cumulativeDistances: cumulativeDistances,
            stationCoordinateIndices: [0, max(pointCount - 1, 0)]
        )
    }

    private var benchmarkStations: [Station] {
        [
            Station(crs: "HUB", name: "Benchmark Hub", latitude: 51.40, longitude: -0.10),
        ] + (0..<12).map { index in
            Station(
                crs: String(format: "B%02d", index),
                name: "Benchmark Branch \(index + 1)",
                latitude: 50.90 + Double(index) * 0.035,
                longitude: -0.28 + Double(index) * 0.03
            )
        }
    }

    private var benchmarkRoute: ServiceRailwayRoute {
        ServiceRailwayRoute(
            coordinates: [
                CLLocationCoordinate2D(latitude: 51.5, longitude: -0.14),
                CLLocationCoordinate2D(latitude: 51.25, longitude: -0.12),
                CLLocationCoordinate2D(latitude: 50.83, longitude: -0.14),
            ],
            cumulativeDistances: [0, 600, 1_200],
            stationCoordinateIndices: [0, 2]
        )
    }
}

private nonisolated struct BenchmarkRoutingProvider: RailwayRouteProviding {
    let route: ServiceRailwayRoute

    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        route
    }
}

@MainActor
private final class BenchmarkClock: SimulationClock {
    func start(tick: @escaping @MainActor (TimeInterval) -> Void) {}
    func stop() {}
}
