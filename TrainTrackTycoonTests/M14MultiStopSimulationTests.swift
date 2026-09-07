import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Milestone 14 multi-stop simulation")
struct M14MultiStopSimulationTests {
    private let lineID = UUID(uuidString: "14000000-0000-0000-0000-000000000001")!

    @Test("An explicit two-stop sequence preserves the endpoint golden path")
    func explicitTwoStopSequenceIsBackwardCompatible() {
        let legacy = PassengerLineInput(
            id: lineID,
            originCRS: "AAA",
            destinationCRS: "CCC",
            distanceKilometres: 40,
            frequency: .halfHourly,
            servicePattern: .local
        )
        let explicit = PassengerLineInput(
            id: lineID,
            originCRS: "AAA",
            destinationCRS: "CCC",
            distanceKilometres: 40,
            stationCRSs: ["AAA", "CCC"],
            cumulativeStationDistancesKilometres: [0, 40],
            frequency: .halfHourly,
            servicePattern: .local
        )

        #expect(PassengerSimulation().evaluate([legacy])
            == PassengerSimulation().evaluate([explicit]))
    }

    @Test("A local service offers adjacent and through markets without an invented transfer")
    func localServiceCreatesDirectMarkets() throws {
        let snapshot = PassengerSimulation().evaluate([multiStopLine(pattern: .local)])
        let line = try #require(snapshot.line(for: lineID))
        let markets = snapshot.serviceMarketSnapshots

        #expect(markets.count == 3)
        #expect(Set(markets.map { "\($0.originCRS)-\($0.destinationCRS)" })
            == ["AAA-BBB", "AAA-CCC", "BBB-CCC"])
        #expect(markets.allSatisfy { $0.departuresPerHour == 2 })
        #expect(snapshot.connectingJourneySnapshots.isEmpty)
        #expect(line.directPassengersPerDay == markets.reduce(0) {
            $0 + $1.directPassengersPerDay
        })
        #expect(line.connectingPassengersPerDay == 0)
        #expect(line.stationCRSs == ["AAA", "BBB", "CCC"])

        let intermediate = try #require(snapshot.station(forCRS: "BBB"))
        #expect(intermediate.connectedLineCount == 1)
        #expect(intermediate.connectedDestinationCount == 2)
        #expect(intermediate.servedDailyJourneys > 0)
    }

    @Test("Overlapping markets share physical seats on every corridor segment")
    func overlappingMarketsCannotOversubscribeSegments() throws {
        let input = PassengerLineInput(
            id: lineID,
            originCRS: "AAA",
            destinationCRS: "CCC",
            distanceKilometres: 40,
            stationCRSs: ["AAA", "BBB", "CCC"],
            cumulativeStationDistancesKilometres: [0, 10, 40],
            frequency: .halfHourly,
            servicePattern: .local,
            capacityPerTrain: RollingStockFormation.twoCar.seatsPerTrain
        )
        let snapshot = PassengerSimulation().evaluate([input])
        let line = try #require(snapshot.line(for: lineID))
        let marketsByPair = Dictionary(uniqueKeysWithValues:
            snapshot.serviceMarketSnapshots.map {
                ("\($0.originCRS)-\($0.destinationCRS)", $0.directPassengersPerDay)
            }
        )

        let firstSegmentLoad = marketsByPair["AAA-BBB", default: 0]
            + marketsByPair["AAA-CCC", default: 0]
        let secondSegmentLoad = marketsByPair["BBB-CCC", default: 0]
            + marketsByPair["AAA-CCC", default: 0]

        #expect(firstSegmentLoad <= line.dailyCapacity)
        #expect(secondSegmentLoad <= line.dailyCapacity)
        #expect(line.dailyCapacity == 5_760)
    }

    @Test("Segment allocation is independent of service input ordering")
    func segmentAllocationIsOrderIndependent() {
        let first = multiStopLine(pattern: .local)
        let second = PassengerLineInput(
            id: UUID(uuidString: "14000000-0000-0000-0000-000000000002")!,
            originCRS: "DDD",
            destinationCRS: "FFF",
            distanceKilometres: 30,
            stationCRSs: ["DDD", "EEE", "FFF"],
            cumulativeStationDistancesKilometres: [0, 15, 30],
            frequency: .hourly,
            servicePattern: .local,
            capacityPerTrain: RollingStockFormation.twoCar.seatsPerTrain
        )

        #expect(PassengerSimulation().evaluate([first, second])
            == PassengerSimulation().evaluate([second, first]))
    }

    @Test("The sixteen-call gameplay bound evaluates all direct markets")
    func maximumGameplayCallingPatternRemainsBounded() throws {
        let stationCRSs = (0..<16).map { String(format: "S%02d", $0) }
        let input = PassengerLineInput(
            id: lineID,
            originCRS: stationCRSs[0],
            destinationCRS: stationCRSs[15],
            distanceKilometres: 150,
            stationCRSs: stationCRSs,
            cumulativeStationDistancesKilometres: (0..<16).map { Double($0) * 10 },
            frequency: .halfHourly,
            servicePattern: .local,
            capacityPerTrain: RollingStockFormation.twoCar.seatsPerTrain
        )

        let snapshot = PassengerSimulation().evaluate([input])
        let line = try #require(snapshot.line(for: lineID))

        #expect(snapshot.serviceMarketSnapshots.count == 120)
        #expect(snapshot.connectingJourneySnapshots.isEmpty)
        #expect(line.stationCRSs == stationCRSs)
        #expect(line.passengersPerDay > 0)
    }

    @Test("Balanced calls use only local frequency and Express skips intermediate stations")
    func patternControlsIntermediateAvailability() {
        let simulation = PassengerSimulation()
        let local = simulation.evaluate([multiStopLine(pattern: .local)])
        let balanced = simulation.evaluate([multiStopLine(pattern: .balanced)])
        let express = simulation.evaluate([multiStopLine(pattern: .express)])

        #expect(local.serviceMarketSnapshots.count == 3)
        #expect(local.serviceMarketSnapshots.allSatisfy { $0.departuresPerHour == 2 })

        let balancedByPair = Dictionary(uniqueKeysWithValues:
            balanced.serviceMarketSnapshots.map {
                ("\($0.originCRS)-\($0.destinationCRS)", $0.departuresPerHour)
            }
        )
        #expect(balancedByPair["AAA-CCC"] == 2)
        #expect(balancedByPair["AAA-BBB"] == 1)
        #expect(balancedByPair["BBB-CCC"] == 1)

        #expect(express.serviceMarketSnapshots.count == 1)
        #expect(express.serviceMarketSnapshots.first?.originCRS == "AAA")
        #expect(express.serviceMarketSnapshots.first?.destinationCRS == "CCC")
        #expect(express.station(forCRS: "BBB") == nil)
    }

    @Test("A blocked local portion leaves Balanced express passengers running end to end")
    func blockedLocalCallsPreserveExpressPassengers() throws {
        let input = PassengerLineInput(
            id: lineID,
            originCRS: "AAA",
            destinationCRS: "CCC",
            distanceKilometres: 40,
            stationCRSs: ["AAA", "BBB", "CCC"],
            cumulativeStationDistancesKilometres: [0, 10, 40],
            frequency: .halfHourly,
            servicePattern: .balanced,
            effectiveDeparturesPerHour: 1,
            effectiveIntermediateDeparturesPerHour: 0
        )
        let snapshot = PassengerSimulation().evaluate([input])
        let markets = Dictionary(uniqueKeysWithValues:
            snapshot.serviceMarketSnapshots.map {
                ("\($0.originCRS)-\($0.destinationCRS)", $0)
            }
        )

        #expect(markets["AAA-CCC"]?.departuresPerHour == 1)
        #expect(markets["AAA-CCC"]?.directPassengersPerDay ?? 0 > 0)
        #expect(markets["AAA-BBB"]?.departuresPerHour == 0)
        #expect(markets["BBB-CCC"]?.departuresPerHour == 0)
        #expect(try #require(snapshot.station(forCRS: "BBB")).connectedLineCount == 0)
    }

    @Test("An intermediate platform constrains Local calls but not a Balanced timetable it can fit")
    func intermediateStationCapacityUsesCallingFrequency() throws {
        let simulation = StationCapacitySimulation()
        let local = simulation.evaluate(
            lines: [StationCapacityLineInput(
                id: lineID,
                originCRS: "AAA",
                destinationCRS: "CCC",
                frequency: .quarterHourly,
                stationCRSs: ["AAA", "BBB", "CCC"],
                servicePattern: .local
            )],
            platformCountsByStationCRS: ["AAA": 2, "BBB": 1, "CCC": 2]
        )
        let localLine = try #require(local.line(for: lineID))
        #expect(localLine.effectiveDeparturesPerHour == 2)
        #expect(localLine.effectiveIntermediateDeparturesPerHour == 2)
        #expect(localLine.limitingStationCRSs == ["BBB"])
        #expect(try #require(local.station(forCRS: "BBB"))
            .scheduledTrainCallsPerHour == 8)

        let balanced = simulation.evaluate(
            lines: [StationCapacityLineInput(
                id: lineID,
                originCRS: "AAA",
                destinationCRS: "CCC",
                frequency: .quarterHourly,
                stationCRSs: ["AAA", "BBB", "CCC"],
                servicePattern: .balanced
            )],
            platformCountsByStationCRS: ["AAA": 2, "BBB": 1, "CCC": 2]
        )
        let balancedLine = try #require(balanced.line(for: lineID))
        #expect(balancedLine.effectiveDeparturesPerHour == 4)
        #expect(balancedLine.effectiveIntermediateDeparturesPerHour == 2)
        #expect(!balancedLine.isPlatformConstrained)
    }

    @Test("Accessibility sees a through train as direct at every selected station")
    func accessibilityUsesDirectServiceMarkets() throws {
        let passenger = PassengerSimulation().evaluate([multiStopLine(pattern: .local)])
        let happiness = AccessibilityHappiness().evaluate(
            stationCRSs: ["AAA", "BBB", "CCC"],
            passengerSnapshot: passenger,
            reliabilityByLineID: [lineID: 1]
        )

        #expect(happiness.statistics.operatingServiceCount == 1)
        #expect(happiness.statistics.reachableSettlementPairCount == 3)
        #expect(happiness.statistics.averageInterchanges == 0)
        let middle = try #require(happiness.station(forCRS: "BBB"))
        #expect(middle.reachableDestinationCRSs == ["AAA", "CCC"])
        #expect(middle.averageInterchanges == 0)
    }

    @Test("Economy charges real passenger distance and includes intermediate station upkeep")
    func economyUsesIntermediateJourneyDistance() throws {
        let economy = OperatingEconomy()
        let snapshot = economy.evaluate(
            lines: [EconomyLineInput(
                id: lineID,
                originCRS: "AAA",
                destinationCRS: "CCC",
                stationCRSs: ["AAA", "BBB", "CCC"],
                distanceMetres: 40_000,
                passengerJourneysPerDay: 100,
                passengerMetresPerDay: 1_000_000
            )],
            stationLevelsByCRS: [
                "AAA": .halt,
                "BBB": .halt,
                "CCC": .halt,
            ]
        )

        #expect(try #require(snapshot.lineSnapshot(for: lineID)).revenuePencePerDay
            == 32_000)
        #expect(snapshot.stationUpkeepPencePerDay == 75_000)
    }

    @Test("Train stopping distances preserve every real call for Local trains")
    func realStationStoppingDistances() {
        let operations = TrainOperations()
        #expect(operations.intermediateStopDistances(
            routeLength: 40_000,
            orderedStationDistances: [0, 5_000, 15_000, 40_000],
            role: .local
        ) == [5_000, 15_000])
        #expect(operations.intermediateStopDistances(
            routeLength: 40_000,
            orderedStationDistances: [0, 5_000, 15_000, 40_000],
            role: .express
        ).isEmpty)
    }

    private func multiStopLine(pattern: ServicePattern) -> PassengerLineInput {
        PassengerLineInput(
            id: lineID,
            originCRS: "AAA",
            destinationCRS: "CCC",
            distanceKilometres: 40,
            stationCRSs: ["AAA", "BBB", "CCC"],
            cumulativeStationDistancesKilometres: [0, 10, 40],
            frequency: .halfHourly,
            servicePattern: pattern
        )
    }
}
