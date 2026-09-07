import CoreLocation
import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Map station addition proposals", .serialized)
@MainActor
struct MapStationAdditionTests {
    @Test("A bounded one-station proposal commits through the established atomic transaction")
    func proposalCommitsStationAndExactCostOnce() async throws {
        let provider = MapStationAdditionRoutingProvider()
        let session = makeSession(provider: provider, mode: .career)
        await buildLine(from: alpha, to: charlie, in: session)
        let line = try #require(session.lines.first)
        let originalFinance = session.financeLedger
        let originalRouteCoordinates = line.route.coordinates
        await provider.resetDiscoveryRequests()

        session.beginMapStationAddition(
            bravo,
            candidateLineIDs: [line.id, UUID()]
        )
        #expect(session.mapStationAdditionProposal?.station == bravo)
        await session.waitForMapStationAdditionProposal()

        let requests = await provider.discoveryRequests
        #expect(requests == [
            MapStationAdditionDiscoveryRequest(
                endpointCRSs: ["AAA", "CCC"],
                catalogStationCRSs: ["BBB"]
            ),
        ])
        let option = try #require(session.mapStationAdditionProposal?.options.first)
        #expect(session.mapStationAdditionProposal?.options.count == 1)
        #expect(option.lineID == line.id)
        #expect(option.lineNumber == 1)
        #expect(option.lineName == "Alpha – Charlie")
        #expect(option.resultingStationCRSs == ["AAA", "BBB", "CCC"])
        #expect(option.resultingStationNames == ["Alpha", "Bravo", "Charlie"])
        #expect(option.costPence == 200_000_000)
        #expect(option.isAffordable)
        #expect(option.servicePattern == .balanced)

        #expect(session.confirmMapStationAddition(onLineID: line.id))
        let updatedLine = try #require(session.lines.first)
        #expect(updatedLine.id == line.id)
        #expect(updatedLine.stationCRSs == ["AAA", "BBB", "CCC"])
        #expect(updatedLine.corridorStationCRSs == ["AAA", "BBB", "CCC"])
        #expect(coordinatesEqual(updatedLine.route.coordinates, originalRouteCoordinates))
        #expect(session.corridors.first?.stationCRSs == ["AAA", "BBB", "CCC"])
        #expect(
            session.financeLedger.cashBalancePence
                == originalFinance.cashBalancePence - 200_000_000
        )
        #expect(
            session.financeLedger.lifetimeConstructionSpendPence
                == originalFinance.lifetimeConstructionSpendPence + 200_000_000
        )
        #expect(session.mapStationAdditionProposal == nil)

        let financeAfterConfirmation = session.financeLedger
        #expect(!session.confirmMapStationAddition(onLineID: line.id))
        #expect(session.financeLedger == financeAfterConfirmation)
        #expect(session.lines.first?.stationCRSs == ["AAA", "BBB", "CCC"])
    }

    @Test("Options are deterministic and only caller-supplied lines are inspected")
    func deterministicOptionsRespectCandidateBound() async throws {
        let provider = MapStationAdditionRoutingProvider()
        let session = makeSession(provider: provider, mode: .zen)
        await buildLine(from: alpha, to: charlie, in: session)
        await buildLine(from: delta, to: foxtrot, in: session)
        let firstLine = try #require(session.lines.first)
        let secondLine = try #require(session.lines.last)

        await provider.resetDiscoveryRequests()
        session.beginMapStationAddition(bravo, candidateLineIDs: [secondLine.id])
        await session.waitForMapStationAdditionProposal()
        #expect(session.mapStationAdditionProposal?.options.map(\.lineID) == [secondLine.id])
        #expect(await provider.discoveryRequests == [
            MapStationAdditionDiscoveryRequest(
                endpointCRSs: ["DDD", "FFF"],
                catalogStationCRSs: ["BBB"]
            ),
        ])

        session.beginMapStationAddition(
            bravo,
            candidateLineIDs: [secondLine.id, firstLine.id]
        )
        await session.waitForMapStationAdditionProposal()
        let options = try #require(session.mapStationAdditionProposal?.options)
        #expect(options.map(\.lineID) == [firstLine.id, secondLine.id])
        #expect(options.map(\.lineNumber) == [1, 2])
        #expect(options[0].resultingStationNames == ["Alpha", "Bravo", "Charlie"])
        #expect(options[1].resultingStationNames == ["Delta", "Bravo", "Foxtrot"])

        #expect(session.confirmMapStationAddition(onLineID: secondLine.id))
        #expect(session.lines.first(where: { $0.id == firstLine.id })?.stationCRSs == ["AAA", "CCC"])
        #expect(
            session.lines.first(where: { $0.id == secondLine.id })?.stationCRSs
                == ["DDD", "BBB", "FFF"]
        )
    }

    @Test("Malformed exact matches and non-corridor stations cannot become options")
    func invalidMatchesAreRejected() async throws {
        let provider = MapStationAdditionRoutingProvider()
        let session = makeSession(provider: provider, mode: .zen)
        await buildLine(from: alpha, to: charlie, in: session)
        let lineID = try #require(session.lines.first?.id)

        await provider.setReturnsMalformedProgress(true)
        session.beginMapStationAddition(bravo, candidateLineIDs: [lineID])
        await session.waitForMapStationAdditionProposal()
        #expect(session.mapStationAdditionProposal?.options.isEmpty == true)
        #expect(!session.confirmMapStationAddition(onLineID: lineID))
        #expect(session.lines.first?.stationCRSs == ["AAA", "CCC"])

        await provider.setReturnsMalformedProgress(false)
        session.beginMapStationAddition(echo, candidateLineIDs: [lineID])
        await session.waitForMapStationAdditionProposal()
        #expect(session.mapStationAdditionProposal?.station == echo)
        #expect(session.mapStationAdditionProposal?.options.isEmpty == true)
        #expect(session.lines.first?.stationCRSs == ["AAA", "CCC"])
    }

    @Test("Cancellation and stale line changes invalidate retained matches")
    func cancellationAndStaleProposalAreSafe() async throws {
        let provider = MapStationAdditionRoutingProvider()
        let session = makeSession(provider: provider, mode: .zen)
        await buildLine(from: alpha, to: charlie, in: session)
        let lineID = try #require(session.lines.first?.id)

        await provider.setDiscoveryDelayNanoseconds(500_000_000)
        session.beginMapStationAddition(bravo, candidateLineIDs: [lineID])
        session.cancelMapStationAddition()
        await session.waitForMapStationAdditionProposal()
        #expect(session.mapStationAdditionProposal == nil)
        #expect(!session.isLoadingMapStationAdditionProposal)

        await provider.setDiscoveryDelayNanoseconds(0)
        session.beginMapStationAddition(bravo, candidateLineIDs: [lineID])
        await session.waitForMapStationAdditionProposal()
        #expect(session.mapStationAdditionProposal?.options.count == 1)

        session.setServicePattern(.local, forLineID: lineID)
        let financeBeforeConfirmation = session.financeLedger
        #expect(!session.confirmMapStationAddition(onLineID: lineID))
        #expect(session.financeLedger == financeBeforeConfirmation)
        #expect(session.lines.first?.stationCRSs == ["AAA", "CCC"])
        #expect(session.mapStationAdditionProposal == nil)
    }

    private func makeSession(
        provider: MapStationAdditionRoutingProvider,
        mode: GameMode
    ) -> GameSession {
        GameSession(
            stations: [alpha, bravo, charlie, delta, echo, foxtrot],
            routingProvider: provider,
            gameMode: mode,
            clock: MapStationAdditionClock(),
            configuration: GameConfiguration(
                maximumLineCount: 8,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 40,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 0,
                maximumServiceCallCount: 16
            )
        )
    }

    private func buildLine(
        from origin: Station,
        to destination: Station,
        in session: GameSession
    ) async {
        session.startBuilding()
        await session.waitForBuildStationEligibility()
        session.selectStation(origin)
        await session.waitForBuildStationEligibility()
        session.selectStation(destination)
        await session.waitForRouteCalculation()
        session.confirmPreview()
        #expect(session.phase == .operating)
    }

    private var alpha: Station {
        Station(crs: "AAA", name: "Alpha", latitude: 51, longitude: 0)
    }

    private var bravo: Station {
        Station(crs: "BBB", name: "Bravo", latitude: 51, longitude: 0.01)
    }

    private var charlie: Station {
        Station(crs: "CCC", name: "Charlie", latitude: 51, longitude: 0.02)
    }

    private var delta: Station {
        Station(crs: "DDD", name: "Delta", latitude: 51, longitude: -0.01)
    }

    private var echo: Station {
        Station(crs: "EEE", name: "Echo", latitude: 51.01, longitude: 0.01)
    }

    private var foxtrot: Station {
        Station(crs: "FFF", name: "Foxtrot", latitude: 51, longitude: 0.03)
    }

    private func coordinatesEqual(
        _ lhs: [CLLocationCoordinate2D],
        _ rhs: [CLLocationCoordinate2D]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy {
            $0.latitude == $1.latitude && $0.longitude == $1.longitude
        }
    }
}

private nonisolated struct MapStationAdditionDiscoveryRequest: Equatable, Sendable {
    let endpointCRSs: [String]
    let catalogStationCRSs: [String]
}

private actor MapStationAdditionRoutingProvider: RailwayRouteProviding {
    private(set) var discoveryRequests = [MapStationAdditionDiscoveryRequest]()
    private var returnsMalformedProgress = false
    private var discoveryDelayNanoseconds: UInt64 = 0

    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        switch stationCRSs {
        case ["AAA", "CCC"]:
            return ServiceRailwayRoute(
                coordinates: [coordinate(0), coordinate(1), coordinate(2)],
                cumulativeDistances: [0, 1_000, 2_000],
                stationCoordinateIndices: [0, 2]
            )
        case ["DDD", "FFF"]:
            return ServiceRailwayRoute(
                coordinates: [
                    coordinate(-1), coordinate(0), coordinate(1), coordinate(2), coordinate(3),
                ],
                cumulativeDistances: [0, 1_000, 2_000, 3_000, 4_000],
                stationCoordinateIndices: [0, 4]
            )
        default:
            throw MapStationAdditionRoutingError.unavailable
        }
    }

    func discoverIntermediateStations(
        on route: ServiceRailwayRoute,
        endpointCRSs: [String],
        catalogStations: [Station]
    ) async throws -> [CorridorStationMatch] {
        discoveryRequests.append(MapStationAdditionDiscoveryRequest(
            endpointCRSs: endpointCRSs,
            catalogStationCRSs: catalogStations.map(\.crs)
        ))
        if discoveryDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: discoveryDelayNanoseconds)
        }
        guard let station = catalogStations.first(where: { $0.crs == "BBB" }) else {
            return []
        }
        let routeDistance: CLLocationDistance
        let coordinateIndex: Int
        switch endpointCRSs {
        case ["AAA", "CCC"]:
            routeDistance = 1_000
            coordinateIndex = 1
        case ["DDD", "FFF"]:
            routeDistance = 2_000
            coordinateIndex = 2
        default:
            return []
        }
        return [CorridorStationMatch(
            station: station,
            routeDistance: routeDistance,
            routeProgress: returnsMalformedProgress ? 0.25 : 0.5,
            routeCoordinateIndex: coordinateIndex,
            offsetFromRoute: 0
        )]
    }

    func resetDiscoveryRequests() {
        discoveryRequests = []
    }

    func setReturnsMalformedProgress(_ value: Bool) {
        returnsMalformedProgress = value
    }

    func setDiscoveryDelayNanoseconds(_ value: UInt64) {
        discoveryDelayNanoseconds = value
    }

    private func coordinate(_ index: Int) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 51, longitude: Double(index) * 0.01)
    }
}

private nonisolated enum MapStationAdditionRoutingError: Error {
    case unavailable
}

@MainActor
private final class MapStationAdditionClock: SimulationClock {
    func start(tick: @escaping @MainActor (TimeInterval) -> Void) {}
    func stop() {}
    func setSuspended(_ isSuspended: Bool) {}
}
