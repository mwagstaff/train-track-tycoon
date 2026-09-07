import CoreLocation
import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Build station eligibility", .serialized)
@MainActor
struct BuildStationEligibilityTests {
    @Test("Builder exposes only stations connected to the selected origin")
    func builderPublishesConnectedComponentEligibility() async throws {
        let stations = Self.stations
        let session = GameSession(
            stations: stations,
            routingProvider: ComponentEligibilityRoutingProvider(),
            clock: EligibilityClock(),
            configuration: .poc
        )

        session.startBuilding()
        #expect(session.phase == .selectingOrigin)
        #expect(session.isLoadingBuildStationEligibility)
        #expect(!session.hasResolvedBuildStationEligibility)
        #expect(session.eligibleBuildStationCRSs.isEmpty)

        await session.waitForBuildStationEligibility()
        #expect(session.hasResolvedBuildStationEligibility)
        #expect(session.eligibleBuildStationCRSs == Set(stations.map(\.crs)))

        session.selectOrigin(stations[0])
        #expect(session.phase == .selectingDestination)
        await session.waitForBuildStationEligibility()

        #expect(session.eligibleBuildStationCRSs == ["BBB", "CCC"])
        #expect(session.isStationEligibleForCurrentBuild(stations[1]))
        #expect(!session.isStationEligibleForCurrentBuild(stations[0]))
        #expect(!session.isStationEligibleForCurrentBuild(stations[3]))
    }

    @Test("An ineligible destination is rejected before pathfinding")
    func disconnectedDestinationCannotEnterRouteCalculation() async throws {
        let provider = ComponentEligibilityRoutingProvider()
        let session = GameSession(
            stations: Self.stations,
            routingProvider: provider,
            clock: EligibilityClock(),
            configuration: .poc
        )

        session.startBuilding()
        await session.waitForBuildStationEligibility()
        session.selectOrigin(Self.stations[0])
        await session.waitForBuildStationEligibility()
        session.selectDestination(Self.stations[3])

        #expect(session.phase == .error)
        #expect(session.errorMessage?.contains("No reasonably direct railway path") == true)
        #expect(await provider.routeRequestCount == 0)

        session.dismissError()
        #expect(session.phase == .selectingDestination)
        session.selectDestination(Self.stations[1])
        await session.waitForRouteCalculation()
        #expect(session.phase == .preview)
        #expect(await provider.routeRequestCount == 1)
    }

    @Test("Cancelling the builder clears eligibility and prevents stale publication")
    func cancellationClearsEligibility() async {
        let provider = SuspendedEligibilityRoutingProvider()
        let session = GameSession(
            stations: Self.stations,
            routingProvider: provider,
            clock: EligibilityClock(),
            configuration: .poc
        )

        session.startBuilding()
        #expect(await waitForEligibilityRequests(1, in: provider))
        session.cancelBuild()
        #expect(session.phase == .idle)
        #expect(!session.isLoadingBuildStationEligibility)
        #expect(!session.hasResolvedBuildStationEligibility)
        #expect(session.eligibleBuildStationCRSs.isEmpty)

        await provider.completeOldest(with: Set(Self.stations.map(\.crs)))
        await Task.yield()
        #expect(session.eligibleBuildStationCRSs.isEmpty)
        #expect(!session.hasResolvedBuildStationEligibility)
    }

    private static let stations = [
        Station(crs: "AAA", name: "Mainland A", latitude: 51.0, longitude: -0.3),
        Station(crs: "BBB", name: "Mainland B", latitude: 51.1, longitude: -0.2),
        Station(crs: "CCC", name: "Mainland C", latitude: 51.2, longitude: -0.1),
        Station(crs: "III", name: "Island I", latitude: 50.6, longitude: -1.2),
        Station(crs: "JJJ", name: "Island J", latitude: 50.7, longitude: -1.1),
    ]

    private func waitForEligibilityRequests(
        _ count: Int,
        in provider: SuspendedEligibilityRoutingProvider
    ) async -> Bool {
        for _ in 0..<100 {
            if await provider.eligibilityRequestCount == count { return true }
            await Task.yield()
        }
        return false
    }
}

private actor ComponentEligibilityRoutingProvider: RailwayRouteProviding {
    private(set) var routeRequestCount = 0

    func connectedStationCRSs(
        to originCRS: String?,
        among candidateCRSs: Set<String>
    ) async throws -> Set<String> {
        let components: [Set<String>] = [
            ["AAA", "BBB", "CCC"],
            ["III", "JJJ"],
        ]
        guard let originCRS else {
            return components.reduce(into: Set<String>()) { $0.formUnion($1) }
                .intersection(candidateCRSs)
        }
        return (components.first(where: { $0.contains(originCRS) }) ?? [])
            .subtracting([originCRS])
            .intersection(candidateCRSs)
    }

    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        routeRequestCount += 1
        let coordinates = stationCRSs.indices.map { index in
            CLLocationCoordinate2D(latitude: 51, longitude: Double(index) * 0.01)
        }
        return ServiceRailwayRoute(
            coordinates: coordinates,
            cumulativeDistances: stationCRSs.indices.map { Double($0) * 1_000 },
            stationCoordinateIndices: Array(stationCRSs.indices)
        )
    }
}

private actor SuspendedEligibilityRoutingProvider: RailwayRouteProviding {
    private var pending = [CheckedContinuation<Set<String>, any Error>]()
    private(set) var eligibilityRequestCount = 0

    func connectedStationCRSs(
        to originCRS: String?,
        among candidateCRSs: Set<String>
    ) async throws -> Set<String> {
        eligibilityRequestCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending.append(continuation)
        }
    }

    func completeOldest(with result: Set<String>) {
        pending.removeFirst().resume(returning: result)
    }

    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        ServiceRailwayRoute(
            coordinates: [
                CLLocationCoordinate2D(latitude: 51, longitude: 0),
                CLLocationCoordinate2D(latitude: 51, longitude: 0.01),
            ],
            cumulativeDistances: [0, 1_000],
            stationCoordinateIndices: [0, 1]
        )
    }
}

@MainActor
private final class EligibilityClock: SimulationClock {
    func start(tick: @escaping @MainActor (TimeInterval) -> Void) {}
    func stop() {}
}
