import CoreLocation
import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Milestone 17 automatic regional service planning")
struct AutomaticServicePlannerTests {
    private let planner = AutomaticServicePlanner(configuration: .init(
        planningSpeedKilometresPerHour: 60,
        intermediateCallDuration: 0,
        preferredOneWayDuration: 30 * 60,
        maximumOneWayDuration: 60 * 60,
        maximumDistanceMetres: 40_000,
        maximumCallsPerLocalZone: 4
    ))

    @Test("Short routes preserve Local, Balanced, and Express presets")
    func shortRoutePresets() {
        let stationCRSs = ["AAA", "BBB", "CCC"]
        let distances: [CLLocationDistance] = [0, 10_000, 20_000]

        let local = planner.plan(
            servicePattern: .local,
            stationCRSs: stationCRSs,
            cumulativeDistancesMetres: distances
        )
        #expect(local.localZones == [stationCRSs])
        #expect(local.representativePlans.count == 4)
        #expect(local.representativePlans.allSatisfy {
            $0.role == .local && $0.stationCRSs == stationCRSs
        })

        let balanced = planner.plan(
            servicePattern: .balanced,
            stationCRSs: stationCRSs,
            cumulativeDistancesMetres: distances
        )
        #expect(balanced.localZones == [stationCRSs])
        #expect(balanced.representativePlans.map(\.role)
            == [.local, .express, .local, .express])
        #expect(balanced.representativePlans[0].stationCRSs == stationCRSs)
        #expect(balanced.representativePlans[1].stationCRSs == ["AAA", "CCC"])

        let express = planner.plan(
            servicePattern: .express,
            stationCRSs: stationCRSs,
            cumulativeDistancesMetres: distances
        )
        #expect(express.localZones.isEmpty)
        #expect(express.unbridgeableStationPairs.isEmpty)
        #expect(express.representativePlans.allSatisfy {
            $0.role == .express && $0.stationCRSs == ["AAA", "CCC"]
        })
    }

    @Test("A long railway is fully covered by bounded overlapping Local zones")
    func longRouteCoverageAndBounds() throws {
        let stationCRSs = (0...8).map { String(format: "S%02d", $0) }
        let distances = stationCRSs.indices.map { Double($0) * 10_000 }
        let distanceByCRS = Dictionary(uniqueKeysWithValues: zip(stationCRSs, distances))

        let result = planner.plan(
            servicePattern: .local,
            stationCRSs: stationCRSs,
            cumulativeDistancesMetres: distances
        )

        #expect(result.localZones.count > 1)
        #expect(Set(result.localZones.flatMap { $0 }) == Set(stationCRSs))
        #expect(result.unbridgeableStationPairs.isEmpty)
        for zone in result.localZones {
            let first = try #require(zone.first.flatMap { distanceByCRS[$0] })
            let last = try #require(zone.last.flatMap { distanceByCRS[$0] })
            let distance = last - first
            #expect(zone.count >= 2)
            #expect(zone.count <= 4)
            #expect(distance <= 40_000)
            #expect(planner.isValidLocalZone(
                distanceMetres: distance,
                callCount: zone.count
            ))
        }
        for pair in zip(result.localZones, result.localZones.dropFirst()) {
            #expect(pair.0.last == pair.1.first)
            #expect(Set(pair.0).intersection(pair.1).count == 1)
        }
        #expect(result.representativePlans.allSatisfy { plan in
            plan.role == .local && result.localZones.contains(plan.stationCRSs)
        })

        let isolatedPair = planner.plan(
            servicePattern: .local,
            stationCRSs: ["AAA", "BBB"],
            cumulativeDistancesMetres: [0, 60_000]
        )
        #expect(isolatedPair.localZones.isEmpty)
        #expect(isolatedPair.unbridgeableStationPairs == [["AAA", "BBB"]])
        #expect(isolatedPair.representativePlans.allSatisfy {
            $0.role == .express && $0.stationCRSs == ["AAA", "BBB"]
        })
    }

    @Test("Reversing a railway reverses the same deterministic zone boundaries")
    func reverseDeterminism() {
        let stationCRSs = (0...10).map { String(format: "S%02d", $0) }
        let distances = stationCRSs.indices.map { Double($0) * 10_000 }
        let forward = planner.plan(
            servicePattern: .balanced,
            stationCRSs: stationCRSs,
            cumulativeDistancesMetres: distances
        )
        let reversed = planner.plan(
            servicePattern: .balanced,
            stationCRSs: Array(stationCRSs.reversed()),
            cumulativeDistancesMetres: distances
        )

        let expectedZones = forward.localZones.reversed().map { Array($0.reversed()) }
        #expect(reversed.localZones == expectedZones)
        #expect(reversed.unbridgeableStationPairs
            == forward.unbridgeableStationPairs.reversed().map { Array($0.reversed()) })
        #expect(reversed.representativePlans.map(\.role)
            == forward.representativePlans.map(\.role))
        let forwardLocalRepresentatives = Set(forward.representativePlans
            .filter { $0.role == .local }
            .map { Array($0.stationCRSs.reversed()) })
        let reversedLocalRepresentatives = Set(reversed.representativePlans
            .filter { $0.role == .local }
            .map(\.stationCRSs))
        #expect(reversedLocalRepresentatives == forwardLocalRepresentatives)
        #expect(reversed.representativePlans.filter { $0.role == .express }.allSatisfy {
            $0.stationCRSs == [stationCRSs.last!, stationCRSs.first!]
        })
    }

    @Test("An impossible adjacent leg is reported and never labelled Local")
    func unbridgeableAdjacentLeg() {
        let result = planner.plan(
            servicePattern: .local,
            stationCRSs: ["AAA", "BBB", "CCC", "DDD"],
            cumulativeDistancesMetres: [0, 20_000, 80_000, 100_000]
        )

        #expect(result.localZones == [["AAA", "BBB"], ["CCC", "DDD"]])
        #expect(result.unbridgeableStationPairs == [["BBB", "CCC"]])
        #expect(result.representativePlans.allSatisfy { plan in
            plan.role == .local && result.localZones.contains(plan.stationCRSs)
        })
    }

    @Test("Express trains remain unrestricted over a country-length railway")
    func expressRemainsUnrestricted() {
        let stationCRSs = (0...40).map { String(format: "S%02d", $0) }
        let distances = stationCRSs.indices.map { Double($0) * 25_000 }

        let result = planner.plan(
            servicePattern: .express,
            stationCRSs: stationCRSs,
            cumulativeDistancesMetres: distances
        )

        #expect(distances.last == 1_000_000)
        #expect(result.localZones.isEmpty)
        #expect(result.representativePlans.allSatisfy {
            $0.role == .express
                && $0.stationCRSs == [stationCRSs.first!, stationCRSs.last!]
        })
    }
}

@Suite("Milestone 17 regional services in a game session", .serialized)
@MainActor
struct M17RegionalServiceIntegrationTests {
    @Test("A long build preview matches the regional timetable that is purchased")
    func longPreviewMatchesConfirmedRegionalService() async throws {
        let stations = M17RoutingProvider.makeStations(count: 14)
        let session = GameSession(
            stations: stations,
            routingProvider: M17RoutingProvider(stations: stations),
            stationCapacitySimulation: StationCapacitySimulation(
                configuration: StationCapacityConfiguration(
                    trainCallsPerPlatformPerHour: 1_000_000
                )
            ),
            gameMode: .zen,
            clock: M17ManualSimulationClock(),
            configuration: GameConfiguration(
                maximumLineCount: 12,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 100,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000,
                maximumServiceCallCount: 20
            )
        )

        session.startBuilding()
        session.selectStation(stations[0])
        session.selectStation(stations[stations.count - 1])
        await session.waitForRouteCalculation()
        for station in stations.dropFirst().dropLast() {
            session.togglePreviewIntermediateStation(station)
            await session.waitForRouteCalculation()
        }

        var preview = try #require(session.preview)
        let planning = AutomaticServicePlanner().plan(
            servicePattern: .balanced,
            stationCRSs: preview.stationCRSs,
            cumulativeDistancesMetres: preview.route.cumulativeDistances
        )
        #expect(planning.localZones.count >= 3)

        // Use the recommendation so its rolling-stock cost is also the exact purchase quote.
        session.setPreviewFormation(preview.recommendedFormation)
        preview = try #require(session.preview)
        let previewQuote = try #require(session.previewCapitalQuote)

        // This is the legacy whole-route projection used before M17 preview parity. A national
        // regional timetable must expose more than this single outer-station market.
        let legacyInput = PassengerLineInput(
            id: UUID(),
            originCRS: preview.origin.crs,
            destinationCRS: preview.destination.crs,
            distanceKilometres: preview.distanceKilometres,
            stationCRSs: preview.stationCRSs,
            cumulativeStationDistancesKilometres: preview.route.cumulativeDistances.map {
                $0 / 1_000
            },
            frequency: .halfHourly,
            servicePattern: .balanced,
            capacityPerTrain: preview.formation.seatsPerTrain
        )
        let legacySnapshot = try #require(
            PassengerSimulation().evaluate([legacyInput]).line(for: legacyInput.id)
        )
        #expect(
            preview.passengerEstimate.potentialDailyJourneys
                > legacySnapshot.potentialDailyJourneys
        )
        #expect(preview.passengerEstimate.dailyCapacity > legacySnapshot.dailyCapacity)

        session.confirmPreview()

        let line = try #require(session.lines.first)
        let confirmed = try #require(session.passengerSnapshot(forLineID: line.id))
        #expect(line.formation == preview.recommendedFormation)
        #expect(preview.passengerEstimate.potentialDailyJourneys == confirmed.potentialDailyJourneys)
        #expect(preview.passengerEstimate.attractedDailyJourneys == confirmed.attractedDailyJourneys)
        #expect(preview.passengerEstimate.passengersPerDay == confirmed.passengersPerDay)
        #expect(preview.passengerEstimate.dailyCapacity == confirmed.dailyCapacity)
        #expect(preview.passengerEstimate.journeyMinutes == confirmed.journeyMinutes)
        #expect(preview.passengerEstimate.averageWaitMinutes == confirmed.averageWaitMinutes)
        #expect(preview.passengerEstimate.demandServedRatio == confirmed.demandServedRatio)
        #expect(preview.passengerEstimate.demandCapturedRatio == confirmed.demandCapturedRatio)
        #expect(preview.passengerEstimate.peakOccupancyRatio == confirmed.peakOccupancyRatio)
        #expect(preview.passengerEstimate.capacityPressure == confirmed.capacityPressure)
        #expect(preview.passengerEstimate.feedback == confirmed.feedback)
        #expect(session.financeLedger.lifetimeConstructionSpendPence == previewQuote.constructionPence)
        #expect(session.financeLedger.lifetimeRollingStockSpendPence == previewQuote.rollingStockPence)
        #expect(session.financeLedger.lifetimeCapitalSpendPence == previewQuote.totalPence)
    }

    @Test("Automatic Local zones serve every station while custom Express remains end to end")
    func regionalDefaultsAndCountryLengthExpress() async throws {
        let stations = M17RoutingProvider.makeStations(count: 8)
        let session = GameSession(
            stations: stations,
            routingProvider: M17RoutingProvider(stations: stations),
            stationCapacitySimulation: StationCapacitySimulation(
                configuration: StationCapacityConfiguration(
                    trainCallsPerPlatformPerHour: 1_000_000
                )
            ),
            gameMode: .zen,
            clock: M17ManualSimulationClock(),
            configuration: GameConfiguration(
                maximumLineCount: 12,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 100,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000,
                maximumServiceCallCount: 16
            )
        )
        await buildLongLine(in: session, stations: stations)
        let lineID = try #require(session.lines.first?.id)

        let balanced = try #require(session.lines.first)
        #expect(balanced.stationCRSs == stations.map(\.crs))
        #expect(balanced.trainServicePlans[0].role == .local)
        #expect(balanced.trainServicePlans[0].stationCRSs.count < stations.count)
        #expect(balanced.trainServicePlans[1] == TrainServicePlan(
            slotIndex: 1,
            role: .express,
            stationCRSs: [stations.first!.crs, stations.last!.crs]
        ))
        #expect(marketFrequency(
            from: stations.first!.crs,
            to: stations.last!.crs,
            in: session
        ) == 1)

        session.setServicePattern(.local, forLineID: lineID)
        let local = try #require(session.lines.first)
        #expect(local.trains.indices.allSatisfy { slot in
            guard let plan = local.servicePlan(forSlot: slot) else { return false }
            return plan.role == .local && plan.stationCRSs.count < stations.count
        })
        #expect(marketFrequency(
            from: stations.first!.crs,
            to: stations.last!.crs,
            in: session
        ) == nil)
        for pair in zip(stations, stations.dropFirst()) {
            #expect(marketFrequency(from: pair.0.crs, to: pair.1.crs, in: session) == 2)
        }
        #expect(stations.allSatisfy {
            session.passengerSnapshot.station(forCRS: $0.crs)?.servedDailyJourneys ?? 0 > 0
        })

        let customTrain = try #require(local.trains.first)
        #expect(!session.setTrainServicePlan(
            TrainServicePlan(
                slotIndex: customTrain.id.hashValue,
                role: .local,
                stationCRSs: [stations.first!.crs, stations.last!.crs]
            ),
            forTrainID: customTrain.id
        ))
        #expect(session.setTrainServicePlan(
            TrainServicePlan(
                slotIndex: customTrain.id.hashValue,
                role: .express,
                stationCRSs: [stations.first!.crs, stations.last!.crs]
            ),
            forTrainID: customTrain.id
        ))
        #expect(session.trainServicePlan(for: customTrain.id) == TrainServicePlan(
            slotIndex: 0,
            role: .express,
            stationCRSs: [stations.first!.crs, stations.last!.crs]
        ))
        #expect(session.hasCustomServicePlans(forLineID: lineID))
        #expect(marketFrequency(
            from: stations.first!.crs,
            to: stations.last!.crs,
            in: session
        ) == 1)
        for pair in zip(stations, stations.dropFirst()) {
            #expect(marketFrequency(from: pair.0.crs, to: pair.1.crs, in: session) == 1)
        }

        session.setServicePattern(.express, forLineID: lineID)
        let express = try #require(session.lines.first)
        #expect(express.trainServicePlans.allSatisfy {
            $0.role == .express
                && $0.stationCRSs == [stations.first!.crs, stations.last!.crs]
        })
        #expect(session.passengerSnapshot.serviceMarketSnapshots.filter {
            $0.serviceID == lineID
        }.count == 1)
        #expect(marketFrequency(
            from: stations.first!.crs,
            to: stations.last!.crs,
            in: session
        ) == 2)
    }

    @Test("A sparse national route explains why an all-Local timetable is unavailable")
    func sparseNationalLocalPatternIsBlocked() async throws {
        let stations = M17RoutingProvider.makeStations(count: 8)
        let session = GameSession(
            stations: stations,
            routingProvider: M17RoutingProvider(stations: stations),
            gameMode: .zen,
            clock: M17ManualSimulationClock(),
            configuration: GameConfiguration(
                maximumLineCount: 12,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 100,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 0,
                maximumServiceCallCount: 16
            )
        )
        session.startBuilding()
        session.selectStation(stations.first!)
        session.selectStation(stations.last!)
        await session.waitForRouteCalculation()
        session.confirmPreview()
        let lineID = try #require(session.lines.first?.id)

        session.setServicePattern(.local, forLineID: lineID)

        #expect(session.lines.first?.servicePattern == .balanced)
        #expect(session.errorMessage?.contains("Local trains need another station") == true)
        #expect(session.errorMessage?.contains("intermediate station") == true)
    }

    private func buildLongLine(in session: GameSession, stations: [Station]) async {
        session.startBuilding()
        session.selectStation(stations[0])
        session.selectStation(stations[stations.count - 1])
        await session.waitForRouteCalculation()
        #expect(session.phase == .preview)

        for station in stations.dropFirst().dropLast() {
            session.togglePreviewIntermediateStation(station)
            await session.waitForRouteCalculation()
        }
        #expect(session.preview?.stationCRSs == stations.map(\.crs))
        session.setPreviewFormation(.legacyBaseline)
        session.confirmPreview()
        #expect(session.phase == .operating)
    }

    private func marketFrequency(
        from originCRS: String,
        to destinationCRS: String,
        in session: GameSession
    ) -> Double? {
        session.passengerSnapshot.serviceMarketSnapshots.first { market in
            market.originCRS == originCRS && market.destinationCRS == destinationCRS
        }?.departuresPerHour
    }
}

private nonisolated struct M17RoutingProvider: RailwayRouteProviding {
    private let stations: [Station]
    private let indexByCRS: [String: Int]

    init(stations: [Station]) {
        self.stations = stations
        indexByCRS = Dictionary(uniqueKeysWithValues: stations.enumerated().map {
            ($0.element.crs, $0.offset)
        })
    }

    static func makeStations(count: Int) -> [Station] {
        (0..<count).map { index in
            Station(
                crs: String(format: "S%02d", index),
                name: "Station \(index)",
                latitude: 50.0 + Double(index) * 0.05,
                longitude: -1
            )
        }
    }

    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        let indices = try stationCRSs.map { crs in
            guard let index = indexByCRS[crs] else { throw M17RoutingError.unavailable }
            return index
        }
        guard indices.count >= 2 else { throw M17RoutingError.unavailable }
        let increasing = zip(indices, indices.dropFirst()).allSatisfy(<)
        let decreasing = zip(indices, indices.dropFirst()).allSatisfy(>)
        guard increasing || decreasing else { throw M17RoutingError.unavailable }
        let start = indices[0]
        return ServiceRailwayRoute(
            coordinates: indices.map { stations[$0].coordinate },
            cumulativeDistances: indices.map { Double(abs($0 - start)) * 20_000 },
            stationCoordinateIndices: Array(indices.indices)
        )
    }

    func discoverIntermediateStations(
        on route: ServiceRailwayRoute,
        endpointCRSs: [String],
        catalogStations: [Station]
    ) async throws -> [CorridorStationMatch] {
        guard endpointCRSs.count == 2,
              let first = indexByCRS[endpointCRSs[0]],
              let last = indexByCRS[endpointCRSs[1]],
              first != last else { throw M17RoutingError.unavailable }
        let direction = first < last ? 1 : -1
        let intermediateIndices = stride(from: first + direction, to: last, by: direction)
        let totalDistance = Double(abs(last - first)) * 20_000
        return intermediateIndices.enumerated().map { offset, index in
            let distance = Double(offset + 1) * 20_000
            return CorridorStationMatch(
                station: stations[index],
                routeDistance: distance,
                routeProgress: distance / totalDistance,
                routeCoordinateIndex: 0,
                offsetFromRoute: 0
            )
        }
    }
}

private nonisolated enum M17RoutingError: Error {
    case unavailable
}

@MainActor
private final class M17ManualSimulationClock: SimulationClock {
    func start(tick: @escaping @MainActor (TimeInterval) -> Void) {}
    func stop() {}
    func setSuspended(_ isSuspended: Bool) {}
}
