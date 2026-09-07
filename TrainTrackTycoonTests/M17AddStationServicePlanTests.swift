import CoreLocation
import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Milestone 17 station additions preserve restorable timetables", .serialized)
@MainActor
struct M17AddStationServicePlanTests {
    @Test("A thirteenth call replans only invalid and untouched Local slots")
    func addingAStationReconcilesPartialCustomTimetableBeforeSaving() async throws {
        let stations = makeStations()
        let provider = M17AddStationRoutingProvider(stations: stations)
        let session = makeSession(stations: stations, provider: provider)

        await buildEndpointLine(in: session, stations: stations)
        let lineID = try #require(session.lines.first?.id)
        session.beginEditingStops(forLineID: lineID)
        await session.waitForLineStopUpdate()
        for station in stations[1...10] {
            #expect(session.editableIntermediateStations.contains { $0.crs == station.crs })
            session.addIntermediateStation(station, toLineID: lineID)
            await session.waitForLineStopUpdate()
        }

        session.setServiceFrequency(.quarterHourly, forLineID: lineID)
        session.setServicePattern(.local, forLineID: lineID)
        let twelveCallLine = try #require(session.lines.first)
        #expect(twelveCallLine.stationCRSs == stations[0...10].map(\.crs) + [stations[12].crs])
        #expect(twelveCallLine.trains.count == 4)

        let invalidAfterInsertion = TrainServicePlan(
            slotIndex: 0,
            role: .local,
            stationCRSs: Array(twelveCallLine.stationCRSs.reversed())
        )
        let customExpress = TrainServicePlan(
            slotIndex: 1,
            role: .express,
            stationCRSs: [stations[0].crs, stations[6].crs, stations[12].crs]
        )
        let validCustomLocal = TrainServicePlan(
            slotIndex: 2,
            role: .local,
            stationCRSs: stations[0...5].map(\.crs)
        )
        #expect(session.setTrainServicePlan(
            invalidAfterInsertion,
            forTrainID: twelveCallLine.trains[0].id
        ))
        #expect(session.setTrainServicePlan(
            customExpress,
            forTrainID: twelveCallLine.trains[1].id
        ))
        #expect(session.setTrainServicePlan(
            validCustomLocal,
            forTrainID: twelveCallLine.trains[2].id
        ))

        let partiallyCustomized = try #require(session.lines.first)
        let untouchedSlotThree = try #require(partiallyCustomized.servicePlan(forSlot: 3))
        #expect(untouchedSlotThree.stationCRSs.count == 12)

        session.addIntermediateStation(stations[11], toLineID: lineID)
        await session.waitForLineStopUpdate()

        let updatedLine = try #require(session.lines.first)
        #expect(updatedLine.stationCRSs == stations.map(\.crs))
        let automaticPlans = AutomaticServicePlanner().plan(
            servicePattern: .local,
            stationCRSs: stations.map(\.crs),
            cumulativeDistancesMetres: stations.indices.map { Double($0) * 2_000 }
        ).representativePlans
        #expect(updatedLine.servicePlan(forSlot: 0) == automaticPlans[0])
        #expect(updatedLine.servicePlan(forSlot: 1) == customExpress)
        #expect(updatedLine.servicePlan(forSlot: 2) == validCustomLocal)
        #expect(updatedLine.servicePlan(forSlot: 3) == automaticPlans[3])
        #expect(updatedLine.trainServicePlans.allSatisfy { plan in
            plan.role == .express || plan.stationCRSs.count <= 12
        })

        let snapshot = session.makeSaveSnapshot()
        let restored = makeSession(
            stations: stations,
            provider: M17AddStationRoutingProvider(stations: stations)
        )
        try await restored.restore(from: snapshot)
        #expect(restored.lines.first?.stationCRSs == stations.map(\.crs))
        #expect(restored.lines.first?.trainServicePlans == updatedLine.trainServicePlans)
    }

    private func makeStations() -> [Station] {
        (0...12).map { index in
            Station(
                crs: String(format: "S%02d", index),
                name: "Station \(index)",
                latitude: 51.5 - Double(index) * 0.01,
                longitude: -0.1
            )
        }
    }

    private func makeSession(
        stations: [Station],
        provider: M17AddStationRoutingProvider
    ) -> GameSession {
        GameSession(
            stations: stations,
            routingProvider: provider,
            gameMode: .zen,
            clock: M17AddStationClock(),
            configuration: GameConfiguration(
                maximumLineCount: 64,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 100,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 0,
                operatingDayDuration: 30,
                maximumServiceCallCount: 64
            )
        )
    }

    private func buildEndpointLine(
        in session: GameSession,
        stations: [Station]
    ) async {
        session.startBuilding()
        session.selectStation(stations[0])
        session.selectStation(stations[12])
        await session.waitForRouteCalculation()
        #expect(session.phase == .preview)
        session.confirmPreview()
        #expect(session.phase == .operating)
    }
}

private actor M17AddStationRoutingProvider: RailwayRouteProviding {
    private let stationsByCRS: [String: Station]
    private let orderedCRSs: [String]

    init(stations: [Station]) {
        stationsByCRS = Dictionary(uniqueKeysWithValues: stations.map { ($0.crs, $0) })
        orderedCRSs = stations.map(\.crs)
    }

    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        let indices = try stationCRSs.map { crs in
            guard let index = orderedCRSs.firstIndex(of: crs) else {
                throw M17AddStationRoutingError.unavailable
            }
            return index
        }
        guard indices.count >= 2,
              let first = indices.first,
              let last = indices.last,
              first != last else {
            throw M17AddStationRoutingError.unavailable
        }
        let isForward = first < last
        guard zip(indices, indices.dropFirst()).allSatisfy({ pair in
            isForward ? pair.0 < pair.1 : pair.0 > pair.1
        }) else {
            throw M17AddStationRoutingError.unavailable
        }

        let routeIndices = isForward
            ? Array(first...last)
            : Array((last...first).reversed())
        return ServiceRailwayRoute(
            coordinates: routeIndices.map(coordinate(at:)),
            cumulativeDistances: routeIndices.indices.map { Double($0) * 2_000 },
            stationCoordinateIndices: indices.map { abs($0 - first) }
        )
    }

    func discoverIntermediateStations(
        on route: ServiceRailwayRoute,
        endpointCRSs: [String],
        catalogStations: [Station]
    ) async throws -> [CorridorStationMatch] {
        guard endpointCRSs.count == 2,
              let first = orderedCRSs.firstIndex(of: endpointCRSs[0]),
              let last = orderedCRSs.firstIndex(of: endpointCRSs[1]),
              first < last else {
            throw M17AddStationRoutingError.unavailable
        }
        return ((first + 1)..<last).compactMap { index in
            guard let station = stationsByCRS[orderedCRSs[index]] else { return nil }
            let distance = Double(index - first) * 2_000
            return CorridorStationMatch(
                station: station,
                routeDistance: distance,
                routeProgress: distance / route.totalLength,
                routeCoordinateIndex: index - first,
                offsetFromRoute: 0
            )
        }
    }

    private func coordinate(at index: Int) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: 51.5 - Double(index) * 0.01,
            longitude: -0.1
        )
    }
}

private nonisolated enum M17AddStationRoutingError: Error {
    case unavailable
}

@MainActor
private final class M17AddStationClock: SimulationClock {
    func start(tick: @escaping @MainActor (TimeInterval) -> Void) {}
    func stop() {}
    func setSuspended(_ isSuspended: Bool) {}
}
