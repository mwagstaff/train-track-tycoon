import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Station capacity simulation")
struct StationCapacityTests {
    private let firstID = UUID(uuidString: "CA000000-0000-0000-0000-000000000001")!
    private let secondID = UUID(uuidString: "CA000000-0000-0000-0000-000000000002")!

    @Test("Every station level maps to four train calls per platform")
    func levelCapacityMapping() throws {
        let counts = Dictionary(uniqueKeysWithValues: StationLevel.allCases.map {
            ($0.rawValue, $0.platformCount)
        })
        let snapshot = StationCapacitySimulation().evaluate(
            lines: [],
            platformCountsByStationCRS: counts
        )

        #expect(try StationLevel.allCases.map { level in
            try #require(snapshot.station(forCRS: level.rawValue)).trainCallCapacityPerHour
        } == [4, 8, 12, 16, 24, 32])
    }

    @Test("A Halt preserves half-hourly service and constrains quarter-hourly service")
    func haltBaselineAndConstraint() throws {
        let simulation = StationCapacitySimulation()
        let halfHourly = simulation.evaluate(
            lines: [line(firstID, "AAA", "BBB", .halfHourly)],
            platformCountsByStationCRS: ["AAA": 1, "BBB": 1]
        )
        let halfHourlyLine = try #require(halfHourly.line(for: firstID))
        #expect(halfHourlyLine.scheduledDeparturesPerHour == 2)
        #expect(halfHourlyLine.effectiveDeparturesPerHour == 2)
        #expect(!halfHourlyLine.isPlatformConstrained)
        #expect(try #require(halfHourly.station(forCRS: "AAA")).utilization == 1)

        let quarterHourly = simulation.evaluate(
            lines: [line(firstID, "AAA", "BBB", .quarterHourly)],
            platformCountsByStationCRS: ["AAA": 1, "BBB": 1]
        )
        let constrained = try #require(quarterHourly.line(for: firstID))
        #expect(constrained.effectiveDeparturesPerHour == 2)
        #expect(constrained.throughputRatio == 0.5)
        #expect(constrained.limitingStationCRSs == ["AAA", "BBB"])
        #expect(constrained.isPlatformConstrained)
        #expect(try #require(quarterHourly.station(forCRS: "AAA")).capacityPressure == 2)
        #expect(try #require(quarterHourly.station(forCRS: "AAA"))
            .effectiveTrainCallsPerHour == 4)
    }

    @Test("A shared Halt treats both services proportionally and Local restores them")
    func sharedHubCapacity() throws {
        let lines = [
            line(firstID, "AAA", "HUB", .halfHourly),
            line(secondID, "HUB", "CCC", .halfHourly),
        ]
        let simulation = StationCapacitySimulation()
        let halt = simulation.evaluate(
            lines: lines,
            platformCountsByStationCRS: ["AAA": 1, "HUB": 1, "CCC": 1]
        )

        #expect(try #require(halt.line(for: firstID)).effectiveDeparturesPerHour == 1)
        #expect(try #require(halt.line(for: secondID)).effectiveDeparturesPerHour == 1)
        let haltHub = try #require(halt.station(forCRS: "HUB"))
        #expect(haltHub.scheduledTrainCallsPerHour == 8)
        #expect(haltHub.effectiveTrainCallsPerHour == 4)
        #expect(haltHub.blockedTrainCallsPerHour == 4)
        #expect(haltHub.isPlatformConstrained)

        let local = simulation.evaluate(
            lines: lines,
            platformCountsByStationCRS: ["AAA": 1, "HUB": 2, "CCC": 1]
        )
        #expect(try #require(local.line(for: firstID)).effectiveDeparturesPerHour == 2)
        #expect(try #require(local.line(for: secondID)).effectiveDeparturesPerHour == 2)
        #expect(!(try #require(local.station(forCRS: "HUB"))).isPlatformConstrained)
    }

    @Test("The more constrained endpoint determines a line's delivered service")
    func endpointMinimum() throws {
        let snapshot = StationCapacitySimulation().evaluate(
            lines: [line(firstID, "AAA", "BBB", .quarterHourly)],
            platformCountsByStationCRS: ["AAA": 1, "BBB": 2]
        )
        let result = try #require(snapshot.line(for: firstID))

        #expect(result.effectiveDeparturesPerHour == 2)
        #expect(result.limitingStationCRSs == ["AAA"])
        #expect((try #require(snapshot.station(forCRS: "AAA"))).isPlatformConstrained)
        #expect(!(try #require(snapshot.station(forCRS: "BBB"))).isPlatformConstrained)
        #expect(try #require(snapshot.station(forCRS: "BBB"))
            .effectiveTrainCallsPerHour == 4)
    }

    @Test("More platforms are monotonic and every station stays within call capacity")
    func platformGrowthIsMonotonicAndBounded() throws {
        let lines = [
            line(firstID, "AAA", "HUB", .quarterHourly),
            line(secondID, "HUB", "CCC", .halfHourly),
        ]
        let simulation = StationCapacitySimulation()
        var previousFirst = 0.0
        var previousSecond = 0.0

        for platformCount in StationLevel.allCases.map(\.platformCount) {
            let snapshot = simulation.evaluate(
                lines: lines,
                platformCountsByStationCRS: [
                    "AAA": 8,
                    "HUB": platformCount,
                    "CCC": 8,
                ]
            )
            let first = try #require(snapshot.line(for: firstID))
            let second = try #require(snapshot.line(for: secondID))
            #expect(first.effectiveDeparturesPerHour >= previousFirst)
            #expect(second.effectiveDeparturesPerHour >= previousSecond)
            previousFirst = first.effectiveDeparturesPerHour
            previousSecond = second.effectiveDeparturesPerHour

            for station in snapshot.stationSnapshots {
                if let capacity = station.trainCallCapacityPerHour {
                    #expect(station.effectiveTrainCallsPerHour <= capacity)
                }
            }
        }
    }

    @Test("A disjoint service cannot change an existing corridor")
    func disjointLineIsolation() throws {
        let simulation = StationCapacitySimulation()
        let first = line(firstID, "AAA", "BBB", .quarterHourly)
        let baseline = simulation.evaluate(
            lines: [first],
            platformCountsByStationCRS: ["AAA": 1, "BBB": 1]
        )
        let withDisjoint = simulation.evaluate(
            lines: [first, line(secondID, "CCC", "DDD", .quarterHourly)],
            platformCountsByStationCRS: ["AAA": 1, "BBB": 1, "CCC": 1, "DDD": 1]
        )

        #expect(withDisjoint.line(for: firstID) == baseline.line(for: firstID))
        #expect(withDisjoint.station(forCRS: "AAA") == baseline.station(forCRS: "AAA"))
        #expect(withDisjoint.station(forCRS: "BBB") == baseline.station(forCRS: "BBB"))
    }

    @Test("Evaluation is independent of line order, endpoint direction and aliases")
    func deterministicOrderingAndNormalization() {
        let simulation = StationCapacitySimulation()
        let forward = simulation.evaluate(
            lines: [
                line(firstID, " aaa ", "hub", .halfHourly),
                line(secondID, "HUB", "ccc", .halfHourly),
            ],
            platformCountsByStationCRS: [" AAA ": 1, "hub": 1, " HUB ": 2, "ccc": 1]
        )
        let reversed = simulation.evaluate(
            lines: [
                line(secondID, "CCC", "HUB", .halfHourly),
                line(firstID, "HUB", "AAA", .halfHourly),
            ],
            platformCountsByStationCRS: ["ccc": 1, " HUB ": 2, "hub": 1, "AAA": 1]
        )

        #expect(forward == reversed)
        #expect(forward.station(forCRS: "hub")?.platformCount == 2)
    }

    @Test("Absent records are unbounded while zero platforms block only operating service")
    func missingZeroAndNonOperating() throws {
        let simulation = StationCapacitySimulation()
        let legacy = simulation.evaluate(
            lines: [line(firstID, "AAA", "BBB", .quarterHourly)],
            platformCountsByStationCRS: [:]
        )
        #expect(try #require(legacy.line(for: firstID)).effectiveDeparturesPerHour == 4)
        #expect(try #require(legacy.station(forCRS: "AAA")).platformCount == nil)
        #expect(!(try #require(legacy.station(forCRS: "AAA"))).isPlatformConstrained)

        let blocked = simulation.evaluate(
            lines: [
                line(firstID, "AAA", "BBB", .halfHourly),
                line(secondID, "AAA", "CCC", .quarterHourly, isOperating: false),
            ],
            platformCountsByStationCRS: ["AAA": 0, "BBB": 1, "CCC": 0]
        )
        #expect(try #require(blocked.line(for: firstID)).effectiveDeparturesPerHour == 0)
        #expect(try #require(blocked.line(for: secondID)).effectiveDeparturesPerHour == 0)
        #expect(!(try #require(blocked.line(for: secondID))).isPlatformConstrained)
        #expect(try #require(blocked.station(forCRS: "AAA"))
            .scheduledTrainCallsPerHour == 4)
        #expect(try #require(blocked.station(forCRS: "CCC"))
            .scheduledTrainCallsPerHour == 0)
    }

    @Test("Adversarial counts and configuration remain finite and bounded")
    func extremeValues() throws {
        let fallbackConfiguration = StationCapacityConfiguration(
            trainCallsPerPlatformPerHour: .nan
        )
        #expect(fallbackConfiguration.trainCallsPerPlatformPerHour == 4)

        let snapshot = StationCapacitySimulation().evaluate(
            lines: [
                StationCapacityLineInput(
                    id: firstID,
                    originCRS: "AAA",
                    destinationCRS: "BBB",
                    scheduledDeparturesPerHour: .greatestFiniteMagnitude
                ),
            ],
            platformCountsByStationCRS: ["AAA": Int.max, "BBB": -1]
        )
        let lineSnapshot = try #require(snapshot.line(for: firstID))
        let alpha = try #require(snapshot.station(forCRS: "AAA"))
        let bravo = try #require(snapshot.station(forCRS: "BBB"))

        #expect(lineSnapshot.effectiveDeparturesPerHour.isFinite)
        #expect(lineSnapshot.effectiveDeparturesPerHour >= 0)
        #expect(lineSnapshot.effectiveDeparturesPerHour
            <= lineSnapshot.scheduledDeparturesPerHour)
        #expect(alpha.trainCallCapacityPerHour?.isFinite == true)
        #expect(alpha.effectiveTrainCallsPerHour <= (alpha.trainCallCapacityPerHour ?? 0))
        #expect(bravo.capacityPressure.isFinite)
        #expect(bravo.effectiveTrainCallsPerHour == 0)

        let tinyCapacity = StationCapacitySimulation(
            configuration: StationCapacityConfiguration(
                trainCallsPerPlatformPerHour: .leastNonzeroMagnitude
            )
        ).evaluate(
            lines: [line(firstID, "AAA", "BBB", .quarterHourly)],
            platformCountsByStationCRS: ["AAA": 1, "BBB": 1]
        )
        #expect(try #require(tinyCapacity.station(forCRS: "AAA")).capacityPressure.isFinite)
    }

    @Test("Unused hub capacity is redistributed after another endpoint constrains a service")
    func progressiveFillingRedistributesCapacity() throws {
        let lines = [
            line(firstID, "AAA", "HUB", .quarterHourly),
            line(secondID, "HUB", "BBB", .halfHourly),
        ]
        let simulation = StationCapacitySimulation()
        let forward = simulation.evaluate(
            lines: lines,
            platformCountsByStationCRS: ["AAA": 1, "HUB": 2, "BBB": 1]
        )
        let reversed = simulation.evaluate(
            lines: Array(lines.reversed()),
            platformCountsByStationCRS: ["BBB": 1, "HUB": 2, "AAA": 1]
        )

        #expect(forward == reversed)
        #expect(try #require(forward.line(for: firstID)).effectiveDeparturesPerHour == 2)
        #expect(try #require(forward.line(for: secondID)).effectiveDeparturesPerHour == 2)
        #expect(try #require(forward.line(for: firstID)).limitingStationCRSs == ["AAA"])
        #expect(try #require(forward.line(for: secondID)).limitingStationCRSs.isEmpty)
        #expect(try #require(forward.station(forCRS: "HUB"))
            .effectiveTrainCallsPerHour == 8)
        #expect(try #require(forward.station(forCRS: "HUB")).utilization == 1)
    }

    @Test("Twelve incident services receive an equal throughput ratio in any order")
    func twelveServiceHubIsFairAndOrderIndependent() throws {
        let lines = (0..<12).map { index in
            StationCapacityLineInput(
                id: UUID(uuidString: String(
                    format: "CE000000-0000-0000-0000-%012d",
                    index + 1
                ))!,
                originCRS: String(format: "S%02d", index),
                destinationCRS: "HUB",
                frequency: .halfHourly
            )
        }
        let platforms = Dictionary(uniqueKeysWithValues:
            lines.map { ($0.originCRS, 1) } + [("HUB", 3)]
        )
        let simulation = StationCapacitySimulation()
        let forward = simulation.evaluate(
            lines: lines,
            platformCountsByStationCRS: platforms
        )
        let reversed = simulation.evaluate(
            lines: Array(lines.reversed()),
            platformCountsByStationCRS: platforms
        )

        #expect(forward == reversed)
        #expect(forward.lineSnapshots.count == 12)
        let delivered = forward.lineSnapshots.map(\.effectiveDeparturesPerHour)
        #expect(delivered.allSatisfy { abs($0 - 0.5) < 0.000_000_001 })
        #expect(try #require(forward.station(forCRS: "HUB"))
            .effectiveTrainCallsPerHour == 12)
        #expect(forward.stationSnapshots.allSatisfy { station in
            guard let capacity = station.trainCallCapacityPerHour else { return true }
            return station.effectiveTrainCallsPerHour <= capacity
        })
    }

    @Test("An intermediate closure blocks only the local half of a Balanced service")
    func intermediateClosurePreservesExpressFlow() throws {
        let snapshot = StationCapacitySimulation().evaluate(
            lines: [StationCapacityLineInput(
                id: firstID,
                originCRS: "AAA",
                destinationCRS: "CCC",
                stationCRSs: ["AAA", "BBB", "CCC"],
                scheduledDeparturesPerHour: 4,
                scheduledIntermediateDeparturesPerHour: 2
            )],
            platformCountsByStationCRS: ["AAA": 2, "BBB": 0, "CCC": 2]
        )

        let line = try #require(snapshot.line(for: firstID))
        #expect(line.effectiveDeparturesPerHour == 2)
        #expect(line.effectiveIntermediateDeparturesPerHour == 0)
        #expect(line.limitingStationCRSs == ["BBB"])
        #expect(line.isPlatformConstrained)

        let origin = try #require(snapshot.station(forCRS: "AAA"))
        let intermediate = try #require(snapshot.station(forCRS: "BBB"))
        let destination = try #require(snapshot.station(forCRS: "CCC"))
        #expect(origin.scheduledTrainCallsPerHour == 8)
        #expect(origin.effectiveTrainCallsPerHour == 4)
        #expect(intermediate.scheduledTrainCallsPerHour == 4)
        #expect(intermediate.effectiveTrainCallsPerHour == 0)
        #expect(destination.scheduledTrainCallsPerHour == 8)
        #expect(destination.effectiveTrainCallsPerHour == 4)
    }

    @Test("Pure Local and Express services retain their established calling constraints")
    func pureServicePatternsRemainUnchanged() throws {
        let simulation = StationCapacitySimulation()
        let local = simulation.evaluate(
            lines: [StationCapacityLineInput(
                id: firstID,
                originCRS: "AAA",
                destinationCRS: "CCC",
                frequency: .quarterHourly,
                stationCRSs: ["AAA", "BBB", "CCC"],
                servicePattern: .local
            )],
            platformCountsByStationCRS: ["AAA": 2, "BBB": 0, "CCC": 2]
        )
        let express = simulation.evaluate(
            lines: [StationCapacityLineInput(
                id: secondID,
                originCRS: "AAA",
                destinationCRS: "CCC",
                frequency: .quarterHourly,
                stationCRSs: ["AAA", "BBB", "CCC"],
                servicePattern: .express
            )],
            platformCountsByStationCRS: ["AAA": 2, "BBB": 0, "CCC": 2]
        )

        let localLine = try #require(local.line(for: firstID))
        #expect(localLine.effectiveDeparturesPerHour == 0)
        #expect(localLine.effectiveIntermediateDeparturesPerHour == 0)
        #expect(localLine.limitingStationCRSs == ["BBB"])

        let expressLine = try #require(express.line(for: secondID))
        #expect(expressLine.effectiveDeparturesPerHour == 4)
        #expect(expressLine.effectiveIntermediateDeparturesPerHour == 0)
        #expect(expressLine.limitingStationCRSs.isEmpty)
        #expect(try #require(express.station(forCRS: "BBB"))
            .scheduledTrainCallsPerHour == 0)
    }

    @Test("Balanced local flows share an intermediate fairly while express flows continue")
    func balancedFlowAllocationIsFairAndOrderIndependent() throws {
        let lines = [
            StationCapacityLineInput(
                id: firstID,
                originCRS: "AAA",
                destinationCRS: "BBB",
                stationCRSs: ["AAA", "HUB", "BBB"],
                scheduledDeparturesPerHour: 4,
                scheduledIntermediateDeparturesPerHour: 2
            ),
            StationCapacityLineInput(
                id: secondID,
                originCRS: "CCC",
                destinationCRS: "DDD",
                stationCRSs: ["CCC", "HUB", "DDD"],
                scheduledDeparturesPerHour: 4,
                scheduledIntermediateDeparturesPerHour: 2
            ),
        ]
        let platforms = ["AAA": 2, "BBB": 2, "CCC": 2, "DDD": 2, "HUB": 1]
        let simulation = StationCapacitySimulation()
        let forward = simulation.evaluate(
            lines: lines,
            platformCountsByStationCRS: platforms
        )
        let reversed = simulation.evaluate(
            lines: Array(lines.reversed()),
            platformCountsByStationCRS: platforms
        )

        #expect(forward == reversed)
        for lineID in [firstID, secondID] {
            let line = try #require(forward.line(for: lineID))
            #expect(line.effectiveDeparturesPerHour == 3)
            #expect(line.effectiveIntermediateDeparturesPerHour == 1)
            #expect(line.limitingStationCRSs == ["HUB"])
        }
        #expect(try #require(forward.station(forCRS: "HUB"))
            .effectiveTrainCallsPerHour == 4)
    }

    private func line(
        _ id: UUID,
        _ origin: String,
        _ destination: String,
        _ frequency: ServiceFrequency,
        isOperating: Bool = true
    ) -> StationCapacityLineInput {
        StationCapacityLineInput(
            id: id,
            originCRS: origin,
            destinationCRS: destination,
            frequency: frequency,
            isOperating: isOperating
        )
    }
}

@Suite("Station capacity passenger integration")
struct StationCapacityPassengerTests {
    private let firstID = UUID(uuidString: "CB000000-0000-0000-0000-000000000001")!
    private let secondID = UUID(uuidString: "CB000000-0000-0000-0000-000000000002")!

    @Test("Absent and full-throughput overrides preserve the passenger golden exactly")
    func legacyCompatibility() {
        let simulation = PassengerSimulation()
        let legacy = simulation.estimate(for: passengerLine(
            firstID,
            "VIC",
            "BTN",
            distance: 80,
            frequency: .halfHourly
        ))
        let explicit = simulation.estimate(for: passengerLine(
            firstID,
            "VIC",
            "BTN",
            distance: 80,
            frequency: .halfHourly,
            effectiveDepartures: 2
        ))
        let invalid = simulation.estimate(for: passengerLine(
            firstID,
            "VIC",
            "BTN",
            distance: 80,
            frequency: .halfHourly,
            effectiveDepartures: .nan
        ))

        #expect(legacy == explicit)
        #expect(legacy == invalid)
        #expect(legacy.passengersPerDay == 5_152)
        #expect(legacy.dailyCapacity == 17_280)
        #expect(legacy.effectiveDeparturesPerHour == 2)
    }

    @Test("A platform-limited quarter-hourly line behaves like half-hourly service")
    func directServiceUsesEffectiveFrequency() throws {
        let simulation = PassengerSimulation()
        let constrained = simulation.estimate(for: passengerLine(
            firstID,
            "VIC",
            "BTN",
            distance: 80,
            frequency: .quarterHourly,
            effectiveDepartures: 2
        ))
        let baseline = simulation.estimate(for: passengerLine(
            firstID,
            "VIC",
            "BTN",
            distance: 80,
            frequency: .halfHourly
        ))

        #expect(constrained.effectiveDeparturesPerHour == 2)
        #expect(constrained.potentialDailyJourneys == baseline.potentialDailyJourneys)
        #expect(constrained.attractedDailyJourneys == baseline.attractedDailyJourneys)
        #expect(constrained.passengersPerDay == baseline.passengersPerDay)
        #expect(constrained.dailyCapacity == baseline.dailyCapacity)
        #expect(constrained.averageWaitMinutes == baseline.averageWaitMinutes)
        #expect(constrained.feedback == .stationCapacityConstrained)

        let network = simulation.evaluate([passengerLine(
            firstID,
            "VIC",
            "BTN",
            distance: 80,
            frequency: .quarterHourly,
            effectiveDepartures: 2
        )])
        #expect(try #require(network.line(for: firstID)).feedback
            == .stationCapacityConstrained)
    }

    @Test("Zero effective frequency retains latent demand without carrying passengers")
    func zeroFrequencyRetainsPotential() {
        let snapshot = PassengerSimulation().estimate(for: passengerLine(
            firstID,
            "VIC",
            "BTN",
            distance: 80,
            frequency: .quarterHourly,
            effectiveDepartures: 0
        ))

        #expect(snapshot.potentialDailyJourneys == 7_360)
        #expect(snapshot.attractedDailyJourneys == 0)
        #expect(snapshot.passengersPerDay == 0)
        #expect(snapshot.dailyCapacity == 0)
        #expect(snapshot.effectiveDeparturesPerHour == 0)
        #expect(snapshot.feedback == .stationCapacityConstrained)
    }

    @Test("Effective frequency is safely clamped to the selected timetable")
    func effectiveFrequencySanitization() {
        let simulation = PassengerSimulation()
        let baseline = simulation.estimate(for: passengerLine(
            firstID,
            "AAA",
            "BBB",
            distance: 20,
            frequency: .halfHourly
        ))
        let excessive = simulation.estimate(for: passengerLine(
            firstID,
            "AAA",
            "BBB",
            distance: 20,
            frequency: .halfHourly,
            effectiveDepartures: 20
        ))
        let negative = simulation.estimate(for: passengerLine(
            firstID,
            "AAA",
            "BBB",
            distance: 20,
            frequency: .halfHourly,
            effectiveDepartures: -4
        ))

        #expect(excessive == baseline)
        #expect(negative.effectiveDeparturesPerHour == 0)
        #expect(negative.potentialDailyJourneys == baseline.potentialDailyJourneys)
        #expect(negative.passengersPerDay == 0)
    }

    @Test("Fractional duplicate services share one market proportionally and deterministically")
    func duplicateServiceAllocation() throws {
        let first = passengerLine(
            firstID,
            "AAA",
            "BBB",
            distance: 20,
            frequency: .quarterHourly,
            effectiveDepartures: 1.6
        )
        let second = passengerLine(
            secondID,
            "BBB",
            "AAA",
            distance: 20,
            frequency: .hourly,
            effectiveDepartures: 0.4
        )
        let simulation = PassengerSimulation()
        let forward = simulation.evaluate([first, second])
        let reversed = simulation.evaluate([second, first])
        let firstResult = try #require(forward.line(for: firstID))
        let secondResult = try #require(forward.line(for: secondID))

        #expect(forward == reversed)
        #expect(firstResult.passengersPerDay + secondResult.passengersPerDay
            == forward.passengersPerDay)
        #expect(firstResult.dailyCapacity + secondResult.dailyCapacity == 17_280)
        #expect(firstResult.passengersPerDay > secondResult.passengersPerDay)
        #expect(firstResult.passengersPerDay <= firstResult.dailyCapacity)
        #expect(secondResult.passengersPerDay <= secondResult.dailyCapacity)
    }

    @Test("A constrained interchange respects both legs and every effective seat limit")
    func connectingJourneyUsesEffectiveCapacity() throws {
        let simulation = PassengerSimulation()
        let unconstrainedLines = [
            passengerLine(firstID, "VIC", "CLJ", distance: 20, frequency: .halfHourly),
            passengerLine(secondID, "CLJ", "BTN", distance: 20, frequency: .halfHourly),
        ]
        let constrainedLines = [
            passengerLine(
                firstID,
                "VIC",
                "CLJ",
                distance: 20,
                frequency: .halfHourly,
                effectiveDepartures: 1
            ),
            passengerLine(
                secondID,
                "CLJ",
                "BTN",
                distance: 20,
                frequency: .halfHourly,
                effectiveDepartures: 1
            ),
        ]
        let unconstrained = simulation.evaluate(unconstrainedLines)
        let constrained = simulation.evaluate(constrainedLines)
        let unconstrainedConnection = try #require(
            unconstrained.connectingJourneySnapshots.first
        )
        let constrainedConnection = try #require(
            constrained.connectingJourneySnapshots.first
        )

        #expect(constrainedConnection.potentialDailyJourneys
            == unconstrainedConnection.potentialDailyJourneys)
        #expect(constrainedConnection.attractedDailyJourneys
            < unconstrainedConnection.attractedDailyJourneys)
        #expect(constrainedConnection.passengersPerDay
            <= unconstrainedConnection.passengersPerDay)
        for line in constrained.lineSnapshots {
            #expect(line.passengersPerDay <= line.dailyCapacity)
            #expect(line.feedback == .stationCapacityConstrained)
        }
        #expect(try #require(constrained.station(forCRS: "CLJ")).transferJourneysPerDay
            == constrainedConnection.passengersPerDay)
    }

    @Test("Happiness uses delivered rather than scheduled frequency")
    func happinessUsesEffectiveFrequency() throws {
        let simulation = PassengerSimulation()
        let fullPassenger = simulation.evaluate([passengerLine(
            firstID,
            "AAA",
            "BBB",
            distance: 20,
            frequency: .quarterHourly
        )])
        let constrainedPassenger = simulation.evaluate([passengerLine(
            firstID,
            "AAA",
            "BBB",
            distance: 20,
            frequency: .quarterHourly,
            effectiveDepartures: 1
        )])
        let evaluator = AccessibilityHappiness()
        let full = evaluator.evaluate(
            stationCRSs: ["AAA", "BBB"],
            passengerSnapshot: fullPassenger
        )
        let constrained = evaluator.evaluate(
            stationCRSs: ["AAA", "BBB"],
            passengerSnapshot: constrainedPassenger
        )
        let fullLocal = try #require(full.station(forCRS: "AAA"))
        let constrainedLocal = try #require(constrained.station(forCRS: "AAA"))

        #expect(fullLocal.componentScores.frequency == 0.8)
        #expect(constrainedLocal.componentScores.frequency == 0.5)
        #expect(constrainedLocal.happinessScore < fullLocal.happinessScore)
    }

    private func passengerLine(
        _ id: UUID,
        _ origin: String,
        _ destination: String,
        distance: Double,
        frequency: ServiceFrequency,
        effectiveDepartures: Double? = nil
    ) -> PassengerLineInput {
        PassengerLineInput(
            id: id,
            originCRS: origin,
            destinationCRS: destination,
            distanceKilometres: distance,
            frequency: frequency,
            effectiveDeparturesPerHour: effectiveDepartures
        )
    }
}
