import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Milestone 16 service-flow simulation")
struct M16ServiceFlowSimulationTests {
    private let lineID = UUID(uuidString: "16000000-0000-0000-0000-000000000001")!
    private let secondLineID = UUID(uuidString: "16000000-0000-0000-0000-000000000002")!

    @Test("Omitting service runs preserves the established multi-stop result exactly")
    func omittedRunsPreserveLegacyResult() {
        let legacy = legacyLocalLine()
        let explicitNil = PassengerLineInput(
            id: lineID,
            originCRS: "AAA",
            destinationCRS: "CCC",
            distanceKilometres: 40,
            stationCRSs: ["AAA", "BBB", "CCC"],
            cumulativeStationDistancesKilometres: [0, 10, 40],
            frequency: .halfHourly,
            servicePattern: .local,
            serviceRuns: nil
        )

        #expect(PassengerSimulation().evaluate([legacy])
            == PassengerSimulation().evaluate([explicitNil]))
        #expect(StationCapacitySimulation().evaluate(
            lines: [legacyCapacityLine()],
            platformCountsByStationCRS: ["AAA": 2, "BBB": 1, "CCC": 2]
        ) == StationCapacitySimulation().evaluate(
            lines: [StationCapacityLineInput(
                id: lineID,
                originCRS: "AAA",
                destinationCRS: "CCC",
                frequency: .halfHourly,
                stationCRSs: ["AAA", "BBB", "CCC"],
                servicePattern: .local,
                serviceRuns: nil
            )],
            platformCountsByStationCRS: ["AAA": 2, "BBB": 1, "CCC": 2]
        ))
    }

    @Test("Explicit default slots preserve every legacy service-pattern result")
    func explicitDefaultSlotsPreserveLegacyPatterns() {
        let simulation = PassengerSimulation()
        let capacitySimulation = StationCapacitySimulation()
        for pattern in ServicePattern.allCases {
            let legacy = PassengerLineInput(
                id: lineID,
                originCRS: "AAA",
                destinationCRS: "CCC",
                distanceKilometres: 40,
                stationCRSs: ["AAA", "BBB", "CCC"],
                cumulativeStationDistancesKilometres: [0, 10, 40],
                frequency: .halfHourly,
                servicePattern: pattern
            )
            let local = run(0, [("AAA", 0), ("BBB", 10), ("CCC", 40)])
            let express = run(1, [("AAA", 0), ("CCC", 40)])
            let explicitRuns: [PassengerServiceRunInput] = switch pattern {
            case .local: [local, run(1, [("AAA", 0), ("BBB", 10), ("CCC", 40)])]
            case .balanced: [local, express]
            case .express: [run(0, [("AAA", 0), ("CCC", 40)]), express]
            }
            let explicit = PassengerLineInput(
                id: lineID,
                originCRS: "AAA",
                destinationCRS: "CCC",
                distanceKilometres: 40,
                stationCRSs: ["AAA", "BBB", "CCC"],
                cumulativeStationDistancesKilometres: [0, 10, 40],
                frequency: .halfHourly,
                servicePattern: pattern,
                serviceRuns: explicitRuns
            )
            #expect(simulation.evaluate([explicit]) == simulation.evaluate([legacy]))

            let legacyCapacity = StationCapacityLineInput(
                id: lineID,
                originCRS: "AAA",
                destinationCRS: "CCC",
                frequency: .halfHourly,
                stationCRSs: ["AAA", "BBB", "CCC"],
                servicePattern: pattern
            )
            let explicitCapacityRuns = explicitRuns.map {
                StationCapacityServiceRunInput(
                    slotIndex: $0.slotIndex,
                    stationCRSs: $0.stationCalls.map(\.stationCRS)
                )
            }
            let explicitCapacity = StationCapacityLineInput(
                id: lineID,
                originCRS: "AAA",
                destinationCRS: "CCC",
                frequency: .halfHourly,
                stationCRSs: ["AAA", "BBB", "CCC"],
                servicePattern: pattern,
                serviceRuns: explicitCapacityRuns
            )
            let platforms = ["AAA": 1, "BBB": 1, "CCC": 1]
            let legacySnapshot = capacitySimulation.evaluate(
                lines: [legacyCapacity],
                platformCountsByStationCRS: platforms
            )
            let explicitSnapshot = capacitySimulation.evaluate(
                lines: [explicitCapacity],
                platformCountsByStationCRS: platforms
            )
            #expect(explicitSnapshot.line(for: lineID)?.scheduledDeparturesPerHour
                == legacySnapshot.line(for: lineID)?.scheduledDeparturesPerHour)
            #expect(explicitSnapshot.line(for: lineID)?.effectiveDeparturesPerHour
                == legacySnapshot.line(for: lineID)?.effectiveDeparturesPerHour)
            #expect(explicitSnapshot.line(for: lineID)?.scheduledIntermediateDeparturesPerHour
                == legacySnapshot.line(for: lineID)?.scheduledIntermediateDeparturesPerHour)
            #expect(explicitSnapshot.line(for: lineID)?.effectiveIntermediateDeparturesPerHour
                == legacySnapshot.line(for: lineID)?.effectiveIntermediateDeparturesPerHour)
            #expect(explicitSnapshot.stationsByCRS == legacySnapshot.stationsByCRS)
        }
    }

    @Test("Explicit default slots preserve the legacy construction forecast")
    func explicitDefaultSlotsPreserveNonOperatingForecast() {
        let simulation = PassengerSimulation()
        let legacy = PassengerLineInput(
            id: lineID,
            originCRS: "AAA",
            destinationCRS: "CCC",
            distanceKilometres: 40,
            stationCRSs: ["AAA", "BBB", "CCC"],
            cumulativeStationDistancesKilometres: [0, 10, 40],
            frequency: .halfHourly,
            servicePattern: .local,
            isOperating: false
        )
        let explicit = PassengerLineInput(
            id: lineID,
            originCRS: "AAA",
            destinationCRS: "CCC",
            distanceKilometres: 40,
            stationCRSs: ["AAA", "BBB", "CCC"],
            cumulativeStationDistancesKilometres: [0, 10, 40],
            frequency: .halfHourly,
            servicePattern: .local,
            serviceRuns: [
                run(0, [("AAA", 0), ("BBB", 10), ("CCC", 40)]),
                run(1, [("AAA", 0), ("BBB", 10), ("CCC", 40)]),
            ],
            isOperating: false
        )

        #expect(simulation.evaluate([explicit]) == simulation.evaluate([legacy]))
    }

    @Test("Custom runs cannot leave or reorder their retained infrastructure")
    func invalidCustomRunsAreRejected() throws {
        let passenger = customLine(runs: [
            run(0, [("AAA", 0), ("ZZZ", 20)]),
            run(1, [("AAA", 0), ("BBB", 11)]),
            run(2, [("AAA", 0), ("CCC", 40), ("BBB", 10)]),
            run(3, [("AAA", 0), ("CCC", 40)]),
        ])
        #expect(passenger.serviceRuns?.map(\.slotIndex) == [3])
        #expect(passenger.serviceRuns?.first?.stationCalls.map(\.stationCRS)
            == ["AAA", "CCC"])
        #expect(PassengerSimulation().evaluate([passenger])
            .serviceMarketSnapshots.map { pair($0.originCRS, $0.destinationCRS) }
            == ["AAA|CCC"])

        let capacity = StationCapacitySimulation().evaluate(
            lines: [StationCapacityLineInput(
                id: lineID,
                originCRS: "AAA",
                destinationCRS: "CCC",
                frequency: .halfHourly,
                stationCRSs: ["AAA", "BBB", "CCC"],
                serviceRuns: [
                    .init(slotIndex: 0, stationCRSs: ["AAA", "ZZZ"]),
                    .init(slotIndex: 1, stationCRSs: ["AAA", "CCC", "BBB"]),
                    .init(slotIndex: 2, stationCRSs: ["BBB", "CCC"]),
                ]
            )],
            platformCountsByStationCRS: ["AAA": 1, "BBB": 1, "CCC": 1, "ZZZ": 0]
        )
        let capacityLine = try #require(capacity.line(for: lineID))
        #expect(capacityLine.scheduledDeparturesPerHour == 1)
        #expect(capacityLine.effectiveDeparturesBySlot == [2: 1])
        #expect(capacity.station(forCRS: "AAA")?.scheduledTrainCallsPerHour == 0)
        #expect(capacity.station(forCRS: "BBB")?.scheduledTrainCallsPerHour == 2)
        #expect(capacity.station(forCRS: "CCC")?.scheduledTrainCallsPerHour == 2)
    }

    @Test("Two-call short turns count calls at a parent intermediate station")
    func shortTurnsContributeIntermediateDepartures() throws {
        let passenger = customLine(runs: [
            run(0, [("AAA", 0), ("BBB", 10)], effective: 0.5),
        ])
        #expect(passenger.scheduledIntermediateDeparturesPerHour == 1)
        #expect(passenger.passengerIntermediateDeparturesPerHour == 0.5)
        #expect(PassengerSimulation().evaluate([passenger])
            .serviceMarketSnapshots.first?.departuresPerHour == 0.5)

        let capacity = StationCapacitySimulation().evaluate(
            lines: [StationCapacityLineInput(
                id: lineID,
                originCRS: "AAA",
                destinationCRS: "CCC",
                frequency: .hourly,
                stationCRSs: ["AAA", "BBB", "CCC"],
                serviceRuns: [
                    .init(slotIndex: 0, stationCRSs: ["AAA", "BBB"]),
                ]
            )],
            platformCountsByStationCRS: ["AAA": 1, "BBB": 1, "CCC": 1]
        )
        let capacityLine = try #require(capacity.line(for: lineID))
        #expect(capacityLine.scheduledIntermediateDeparturesPerHour == 1)
        #expect(capacityLine.effectiveIntermediateDeparturesPerHour == 1)
        #expect(capacityLine.effectiveDeparturesPerHour(forSlot: 0) == 1)
        #expect(capacity.station(forCRS: "BBB")?.scheduledTrainCallsPerHour == 2)
    }

    @Test("Exact run calls aggregate duplicate markets without inventing skipped markets")
    func exactCallsAndDuplicateAggregation() throws {
        let input = customLine(runs: [
            run(0, [("AAA", 0), ("BBB", 10), ("CCC", 40)]),
            run(1, [("AAA", 0), ("CCC", 40)]),
        ])
        let snapshot = PassengerSimulation().evaluate([input])
        let markets = Dictionary(uniqueKeysWithValues: snapshot.serviceMarketSnapshots.map {
            (pair($0.originCRS, $0.destinationCRS), $0)
        })

        #expect(markets.count == 3)
        #expect(markets["AAA|CCC"]?.departuresPerHour == 2)
        #expect(markets["AAA|BBB"]?.departuresPerHour == 1)
        #expect(markets["BBB|CCC"]?.departuresPerHour == 1)
        #expect(snapshot.connectingJourneySnapshots.isEmpty)
        #expect(try #require(snapshot.line(for: lineID)).directPassengersPerDay
            == markets.values.reduce(0) { $0 + $1.directPassengersPerDay })
    }

    @Test("Different run terminals expose only markets served by one train")
    func runTerminalsMayDiffer() {
        let input = customLine(
            destination: "DDD",
            distance: 60,
            envelope: [("AAA", 0), ("BBB", 10), ("CCC", 40), ("DDD", 60)],
            runs: [
                run(0, [("AAA", 0), ("BBB", 10), ("CCC", 40)]),
                run(1, [("BBB", 10), ("DDD", 60)]),
            ]
        )
        let markets = PassengerSimulation().evaluate([input]).serviceMarketSnapshots
        let pairs = Set(markets.map { pair($0.originCRS, $0.destinationCRS) })

        #expect(pairs == ["AAA|BBB", "AAA|CCC", "BBB|CCC", "BBB|DDD"])
        #expect(!pairs.contains("AAA|DDD"))
        #expect(!pairs.contains("CCC|DDD"))
    }

    @Test("Each run reserves its own seats across overlapping markets")
    func runSegmentSeatsAreNotDoubleSold() throws {
        let input = customLine(
            runs: [
                run(0, [("AAA", 0), ("BBB", 10), ("CCC", 40)]),
                run(1, [("AAA", 0), ("BBB", 10), ("CCC", 40)]),
            ],
            capacityPerTrain: RollingStockFormation.twoCar.seatsPerTrain
        )
        let snapshot = PassengerSimulation().evaluate([input])
        let line = try #require(snapshot.line(for: lineID))
        let passengers = Dictionary(uniqueKeysWithValues: snapshot.serviceMarketSnapshots.map {
            (pair($0.originCRS, $0.destinationCRS), $0.directPassengersPerDay)
        })

        #expect(passengers["AAA|BBB", default: 0] + passengers["AAA|CCC", default: 0]
            <= line.dailyCapacity)
        #expect(passengers["BBB|CCC", default: 0] + passengers["AAA|CCC", default: 0]
            <= line.dailyCapacity)
        #expect(line.dailyCapacity == 5_760)
    }

    @Test("Station bottlenecks constrain only slots that call there")
    func capacityIsReportedBySlot() throws {
        let input = StationCapacityLineInput(
            id: lineID,
            originCRS: "AAA",
            destinationCRS: "CCC",
            frequency: .halfHourly,
            stationCRSs: ["AAA", "BBB", "CCC"],
            servicePattern: .balanced,
            serviceRuns: [
                StationCapacityServiceRunInput(
                    slotIndex: 0,
                    stationCRSs: ["AAA", "BBB", "CCC"]
                ),
                StationCapacityServiceRunInput(
                    slotIndex: 1,
                    stationCRSs: ["AAA", "CCC"]
                ),
            ]
        )
        let snapshot = StationCapacitySimulation().evaluate(
            lines: [input],
            platformCountsByStationCRS: ["AAA": 2, "BBB": 0, "CCC": 2]
        )
        let line = try #require(snapshot.line(for: lineID))

        #expect(line.scheduledDeparturesPerHour == 2)
        #expect(line.effectiveDeparturesPerHour(forSlot: 0) == 0)
        #expect(line.effectiveDeparturesPerHour(forSlot: 1) == 1)
        #expect(line.effectiveDeparturesPerHour == 1)
        #expect(line.effectiveIntermediateDeparturesPerHour == 0)
        #expect(line.limitingStationCRSs == ["BBB"])
        #expect(try #require(snapshot.station(forCRS: "BBB"))
            .scheduledTrainCallsPerHour == 2)
        #expect(try #require(snapshot.station(forCRS: "AAA"))
            .effectiveTrainCallsPerHour == 2)
    }

    @Test("Capacity flows may turn back at different terminals")
    func capacityRunTerminalsMayDiffer() throws {
        let snapshot = StationCapacitySimulation().evaluate(
            lines: [StationCapacityLineInput(
                id: lineID,
                originCRS: "AAA",
                destinationCRS: "DDD",
                frequency: .halfHourly,
                stationCRSs: ["AAA", "BBB", "CCC", "DDD"],
                serviceRuns: [
                    .init(slotIndex: 0, stationCRSs: ["AAA", "CCC"]),
                    .init(slotIndex: 1, stationCRSs: ["BBB", "DDD"]),
                ]
            )],
            platformCountsByStationCRS: ["AAA": 0, "BBB": 1, "CCC": 1, "DDD": 1]
        )
        let line = try #require(snapshot.line(for: lineID))

        #expect(line.effectiveDeparturesPerHour(forSlot: 0) == 0)
        #expect(line.effectiveDeparturesPerHour(forSlot: 1) == 1)
        #expect(snapshot.station(forCRS: "AAA")?.scheduledTrainCallsPerHour == 2)
        #expect(snapshot.station(forCRS: "BBB")?.scheduledTrainCallsPerHour == 2)
        #expect(snapshot.station(forCRS: "BBB")?.effectiveTrainCallsPerHour == 2)
        #expect(line.limitingStationCRSs == ["AAA"])
    }

    @Test("Capacity delivery feeds the matching passenger slots")
    func deliveredSlotFrequencyFeedsPassengerDemand() throws {
        let capacity = StationCapacitySimulation().evaluate(
            lines: [StationCapacityLineInput(
                id: lineID,
                originCRS: "AAA",
                destinationCRS: "CCC",
                frequency: .halfHourly,
                stationCRSs: ["AAA", "BBB", "CCC"],
                serviceRuns: [
                    .init(slotIndex: 0, stationCRSs: ["AAA", "BBB", "CCC"]),
                    .init(slotIndex: 1, stationCRSs: ["AAA", "CCC"]),
                ]
            )],
            platformCountsByStationCRS: ["AAA": 2, "BBB": 0, "CCC": 2]
        )
        let delivered = try #require(capacity.line(for: lineID))
        let passengers = PassengerSimulation().evaluate([customLine(runs: [
            run(0, [("AAA", 0), ("BBB", 10), ("CCC", 40)],
                effective: delivered.effectiveDeparturesPerHour(forSlot: 0)),
            run(1, [("AAA", 0), ("CCC", 40)],
                effective: delivered.effectiveDeparturesPerHour(forSlot: 1)),
        ])])
        let markets = Dictionary(uniqueKeysWithValues: passengers.serviceMarketSnapshots.map {
            (pair($0.originCRS, $0.destinationCRS), $0)
        })

        #expect(markets["AAA|CCC"]?.departuresPerHour == 1)
        #expect(markets["AAA|CCC"]?.directPassengersPerDay ?? 0 > 0)
        #expect(markets["AAA|BBB"]?.departuresPerHour == 0)
        #expect(markets["BBB|CCC"]?.departuresPerHour == 0)
        #expect(passengers.station(forCRS: "BBB")?.connectedLineCount == 0)
    }

    @Test("Custom-run markets retain deterministic one-change journeys")
    func connectingJourneysRemainAvailable() {
        let first = customLine(
            destination: "BBB",
            distance: 20,
            envelope: [("AAA", 0), ("BBB", 20)],
            runs: [run(0, [("AAA", 0), ("BBB", 20)])]
        )
        let second = PassengerLineInput(
            id: secondLineID,
            originCRS: "BBB",
            destinationCRS: "CCC",
            distanceKilometres: 20,
            frequency: .hourly
        )
        let snapshot = PassengerSimulation().evaluate([first, second])

        #expect(snapshot.connectingJourneySnapshots.count == 1)
        #expect(snapshot.connectingJourneySnapshots.first?.originCRS == "AAA")
        #expect(snapshot.connectingJourneySnapshots.first?.interchangeCRS == "BBB")
        #expect(snapshot.connectingJourneySnapshots.first?.destinationCRS == "CCC")
        #expect(snapshot.connectingJourneySnapshots.first?.passengersPerDay ?? 0 > 0)
        #expect(snapshot.line(for: lineID)?.connectingPassengersPerDay ?? 0 > 0)
        #expect(snapshot.line(for: secondLineID)?.connectingPassengersPerDay ?? 0 > 0)
    }

    @Test("Run and line input order cannot change either simulation")
    func customFlowsAreOrderIndependent() {
        let runs = [
            run(0, [("AAA", 0), ("BBB", 10), ("CCC", 40)]),
            run(1, [("AAA", 0), ("CCC", 40)]),
        ]
        let first = customLine(runs: runs)
        let second = PassengerLineInput(
            id: secondLineID,
            originCRS: "CCC",
            destinationCRS: "DDD",
            distanceKilometres: 20,
            serviceRuns: [run(0, [("CCC", 0), ("DDD", 20)])]
        )

        #expect(PassengerSimulation().evaluate([first, second])
            == PassengerSimulation().evaluate([
                second,
                customLine(runs: runs.reversed()),
            ]))

        let capacityRuns = [
            StationCapacityServiceRunInput(
                slotIndex: 0,
                stationCRSs: ["AAA", "BBB", "CCC"]
            ),
            StationCapacityServiceRunInput(
                slotIndex: 1,
                stationCRSs: ["AAA", "CCC"]
            ),
        ]
        let forward = StationCapacitySimulation().evaluate(
            lines: [StationCapacityLineInput(
                id: lineID,
                originCRS: "AAA",
                destinationCRS: "CCC",
                frequency: .halfHourly,
                stationCRSs: ["AAA", "BBB", "CCC"],
                serviceRuns: capacityRuns
            )],
            platformCountsByStationCRS: ["AAA": 2, "BBB": 1, "CCC": 2]
        )
        let reversed = StationCapacitySimulation().evaluate(
            lines: [StationCapacityLineInput(
                id: lineID,
                originCRS: "AAA",
                destinationCRS: "CCC",
                frequency: .halfHourly,
                stationCRSs: ["AAA", "BBB", "CCC"],
                serviceRuns: Array(capacityRuns.reversed())
            )],
            platformCountsByStationCRS: ["CCC": 2, "BBB": 1, "AAA": 2]
        )
        #expect(forward == reversed)
    }

    @Test("A reversed train path has the same undirected passenger markets")
    func reversedRunOrientationIsCanonical() {
        let forward = customLine(runs: [
            run(0, [("AAA", 0), ("BBB", 10), ("CCC", 40)]),
        ])
        let reversed = customLine(runs: [
            run(0, [("CCC", 40), ("BBB", 10), ("AAA", 0)]),
        ])

        #expect(PassengerSimulation().evaluate([forward])
            == PassengerSimulation().evaluate([reversed]))
    }

    private func legacyLocalLine() -> PassengerLineInput {
        PassengerLineInput(
            id: lineID,
            originCRS: "AAA",
            destinationCRS: "CCC",
            distanceKilometres: 40,
            stationCRSs: ["AAA", "BBB", "CCC"],
            cumulativeStationDistancesKilometres: [0, 10, 40],
            frequency: .halfHourly,
            servicePattern: .local
        )
    }

    private func legacyCapacityLine() -> StationCapacityLineInput {
        StationCapacityLineInput(
            id: lineID,
            originCRS: "AAA",
            destinationCRS: "CCC",
            frequency: .halfHourly,
            stationCRSs: ["AAA", "BBB", "CCC"],
            servicePattern: .local
        )
    }

    private func customLine(
        destination: String = "CCC",
        distance: Double = 40,
        envelope: [(String, Double)] = [("AAA", 0), ("BBB", 10), ("CCC", 40)],
        runs: some Sequence<PassengerServiceRunInput>,
        capacityPerTrain: Int = RollingStockFormation.legacyBaseline.seatsPerTrain
    ) -> PassengerLineInput {
        PassengerLineInput(
            id: lineID,
            originCRS: "AAA",
            destinationCRS: destination,
            distanceKilometres: distance,
            stationCRSs: envelope.map(\.0),
            cumulativeStationDistancesKilometres: envelope.map(\.1),
            frequency: .halfHourly,
            servicePattern: .balanced,
            capacityPerTrain: capacityPerTrain,
            serviceRuns: Array(runs)
        )
    }

    private func run(
        _ slotIndex: Int,
        _ calls: [(String, Double)],
        effective: Double? = nil
    ) -> PassengerServiceRunInput {
        PassengerServiceRunInput(
            slotIndex: slotIndex,
            stationCalls: calls.map {
                PassengerStationCallInput(
                    stationCRS: $0.0,
                    distanceKilometresFromOrigin: $0.1
                )
            },
            effectiveDeparturesPerHour: effective
        )
    }

    private func pair(_ first: String, _ second: String) -> String {
        [first, second].sorted().joined(separator: "|")
    }
}
