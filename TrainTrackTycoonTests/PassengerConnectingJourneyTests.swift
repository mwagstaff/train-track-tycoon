import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Passenger connecting journeys")
struct PassengerConnectingJourneyTests {
    private let firstID = UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!
    private let secondID = UUID(uuidString: "B2000000-0000-0000-0000-000000000002")!

    @Test("Two constructed legs create one canonical outer market")
    func connectedVNetworkCreatesOneMarket() throws {
        let network = PassengerSimulation().evaluate([
            line(firstID, "AAA", "BBB", distance: 20),
            line(secondID, "BBB", "CCC", distance: 30),
        ])
        let connection = try #require(network.connectingJourneySnapshots.first)

        #expect(network.connectingJourneySnapshots.count == 1)
        #expect(connection.originCRS == "AAA")
        #expect(connection.destinationCRS == "CCC")
        #expect(connection.interchangeCRS == "BBB")
        #expect(connection.potentialDailyJourneys > 0)
        #expect(connection.attractedDailyJourneys > 0)
        #expect(connection.passengersPerDay > 0)
        #expect(connection.interchangePenaltyMinutes == 12)
        #expect(connection.combinedReliability == 1)
        #expect(network.connectingJourneysPerDay == connection.passengersPerDay)
        #expect(try #require(network.line(for: firstID)).connectingPassengersPerDay
            == connection.passengersPerDay)
        #expect(try #require(network.line(for: secondID)).connectingPassengersPerDay
            == connection.passengersPerDay)
    }

    @Test("Disjoint, duplicate, invalid and nonoperating lines create no transfer market")
    func topologyMustBeAConstructedV() {
        let simulation = PassengerSimulation()
        let first = line(firstID, "AAA", "BBB", distance: 20)
        let cases: [[PassengerLineInput]] = [
            [first, line(secondID, "CCC", "DDD", distance: 20)],
            [first, line(secondID, "BBB", "AAA", distance: 20)],
            [first, line(secondID, "BBB", "CCC", distance: 20, isOperating: false)],
            [first, line(secondID, "BBB", "BBB", distance: 20)],
            [first, line(secondID, "BBB", "CCC", distance: .infinity)],
        ]

        for lines in cases {
            let network = simulation.evaluate(lines)
            #expect(network.connectingJourneysPerDay == 0)
            #expect(network.connectingJourneySnapshots.isEmpty)
            #expect(network.lineSnapshots.allSatisfy {
                $0.connectingPassengersPerDay == 0
                    && $0.directPassengersPerDay == $0.passengersPerDay
            })
            #expect(network.stationSnapshots.allSatisfy { $0.transferJourneysPerDay == 0 })
        }
    }

    @Test("Connection attraction includes both journey legs, both waits and interchange")
    func generalizedJourneyTimeDrivesAttraction() throws {
        let simulation = PassengerSimulation()
        let network = simulation.evaluate([
            line(
                firstID,
                "AAA",
                "BBB",
                distance: 40,
                frequency: .hourly,
                journeyTimeMultiplier: 1.5
            ),
            line(
                secondID,
                "BBB",
                "CCC",
                distance: 60,
                frequency: .quarterHourly,
                journeyTimeMultiplier: 0.75
            ),
        ])
        let connection = try #require(network.connectingJourneySnapshots.first)
        let firstLeg = try #require(network.line(for: firstID))
        let secondLeg = try #require(network.line(for: secondID))
        let expectedInVehicle = firstLeg.journeyMinutes + secondLeg.journeyMinutes
        let expectedWait = firstLeg.averageWaitMinutes + secondLeg.averageWaitMinutes
        let generalizedMinutes = expectedInVehicle + expectedWait + 12
        let attraction = min(
            max(
                simulation.configuration.serviceAttractionBaseline
                    - generalizedMinutes
                        / simulation.configuration.servicePenaltyWindowMinutes,
                simulation.configuration.minimumAttractionRatio
            ),
            1
        )
        let expectedAttracted = Int(
            (Double(connection.potentialDailyJourneys) * attraction).rounded()
        )

        #expect(abs(connection.inVehicleJourneyMinutes - expectedInVehicle)
            < 0.000_000_001)
        #expect(abs(connection.averageWaitMinutes - expectedWait) < 0.000_000_001)
        #expect(abs(connection.generalizedJourneyMinutes - generalizedMinutes)
            < 0.000_000_001)
        #expect(connection.attractedDailyJourneys == expectedAttracted)
    }

    @Test("Both leg reliabilities penalize only connecting attraction")
    func reliabilityUsesBothLegs() throws {
        let simulation = PassengerSimulation()
        let reliableLines = [
            line(firstID, "AAA", "BBB", distance: 20),
            line(secondID, "BBB", "CCC", distance: 20),
        ]
        let lessReliableLines = [
            line(firstID, "AAA", "BBB", distance: 20, reliability: 0.8),
            line(secondID, "BBB", "CCC", distance: 20, reliability: 0.5),
        ]
        let reliable = try #require(
            simulation.evaluate(reliableLines).connectingJourneySnapshots.first
        )
        let lessReliable = try #require(
            simulation.evaluate(lessReliableLines).connectingJourneySnapshots.first
        )

        #expect(abs(lessReliable.combinedReliability - 0.4) < 0.000_000_001)
        #expect(lessReliable.potentialDailyJourneys == reliable.potentialDailyJourneys)
        #expect(lessReliable.attractedDailyJourneys < reliable.attractedDailyJourneys)
        #expect(lessReliable.passengersPerDay <= reliable.passengersPerDay)

        let directReliable = simulation.evaluate([reliableLines[0]])
        let directUnreliable = simulation.evaluate([
            line(firstID, "AAA", "BBB", distance: 20, reliability: 0)
        ])
        #expect(directReliable == directUnreliable)
    }

    @Test("Reliability normalization is deterministic and bounded")
    func invalidReliabilityIsSafe() throws {
        let simulation = PassengerSimulation()
        func connection(_ firstReliability: Double, _ secondReliability: Double) throws
            -> PassengerConnectingJourneySnapshot {
            try #require(simulation.evaluate([
                line(
                    firstID,
                    "AAA",
                    "BBB",
                    distance: 20,
                    reliability: firstReliability
                ),
                line(
                    secondID,
                    "BBB",
                    "CCC",
                    distance: 20,
                    reliability: secondReliability
                ),
            ]).connectingJourneySnapshots.first)
        }

        let baseline = try connection(1, 1)
        let nonfinite = try connection(.nan, .infinity)
        let aboveRange = try connection(2, 3)
        #expect(nonfinite == baseline)
        #expect(aboveRange == baseline)
        let zero = try connection(-1, 1)
        #expect(zero.combinedReliability == 0)
        #expect(zero.attractedDailyJourneys == 0)
        #expect(zero.passengersPerDay == 0)
    }

    @Test("Evaluation is independent of input order and the transfer market is canonical")
    func orderingIsDeterministic() {
        let simulation = PassengerSimulation()
        let first = line(firstID, "BBB", "AAA", distance: 20, reliability: 0.9)
        let second = line(secondID, "CCC", "BBB", distance: 30, reliability: 0.8)
        let canonicalFirst = line(
            firstID,
            "AAA",
            "BBB",
            distance: 20,
            reliability: 0.9
        )
        let canonicalSecond = line(
            secondID,
            "BBB",
            "CCC",
            distance: 30,
            reliability: 0.8
        )

        let reversedDirections = simulation.evaluate([first, second])
        let canonicalDirections = simulation.evaluate([canonicalSecond, canonicalFirst])
        #expect(reversedDirections == simulation.evaluate([second, first]))
        #expect(reversedDirections.connectingJourneySnapshots
            == canonicalDirections.connectingJourneySnapshots)
        #expect(reversedDirections.potentialDailyJourneys
            == canonicalDirections.potentialDailyJourneys)
        #expect(reversedDirections.passengersPerDay == canonicalDirections.passengersPerDay)
    }

    @Test("Either leg can bottleneck and no line exceeds its daily capacity")
    func residualCapacityOnBothLegsBottlenecks() throws {
        let simulation = PassengerSimulation()
        func network(_ firstFrequency: ServiceFrequency, _ secondFrequency: ServiceFrequency)
            -> NetworkPassengerSnapshot {
            simulation.evaluate([
                line(
                    firstID,
                    "VIC",
                    "CLJ",
                    distance: 20,
                    frequency: firstFrequency
                ),
                line(
                    secondID,
                    "CLJ",
                    "BTN",
                    distance: 20,
                    frequency: secondFrequency
                ),
            ])
        }

        let firstTight = network(.hourly, .quarterHourly)
        let secondTight = network(.quarterHourly, .hourly)
        let roomy = network(.quarterHourly, .quarterHourly)
        let firstTightJourneys = try #require(
            firstTight.connectingJourneySnapshots.first
        ).passengersPerDay
        let secondTightJourneys = try #require(
            secondTight.connectingJourneySnapshots.first
        ).passengersPerDay
        let roomyJourneys = try #require(
            roomy.connectingJourneySnapshots.first
        ).passengersPerDay

        #expect(firstTightJourneys <= roomyJourneys)
        #expect(secondTightJourneys <= roomyJourneys)
        for result in [firstTight, secondTight, roomy] {
            let connecting = try #require(result.connectingJourneySnapshots.first)
            let firstLine = try #require(result.line(for: firstID))
            let secondLine = try #require(result.line(for: secondID))
            #expect(connecting.passengersPerDay
                == firstLine.connectingPassengersPerDay)
            #expect(connecting.passengersPerDay
                == secondLine.connectingPassengersPerDay)
            #expect(result.lineSnapshots.allSatisfy {
                $0.passengersPerDay <= $0.dailyCapacity
                    && $0.peakOccupancyRatio >= 0
                    && $0.peakOccupancyRatio <= 1
                    && $0.capacityPressure >= 0
            })
        }
    }

    @Test("Network, line and station totals reconcile without redefining direct destinations")
    func snapshotsReconcile() throws {
        let network = PassengerSimulation().evaluate([
            line(firstID, "AAA", "BBB", distance: 20),
            line(secondID, "BBB", "CCC", distance: 30),
        ])
        let connection = try #require(network.connectingJourneySnapshots.first)
        let firstLine = try #require(network.line(for: firstID))
        let secondLine = try #require(network.line(for: secondID))
        let alpha = try #require(network.station(forCRS: "AAA"))
        let interchange = try #require(network.station(forCRS: "BBB"))
        let charlie = try #require(network.station(forCRS: "CCC"))

        #expect(firstLine.passengersPerDay
            == firstLine.directPassengersPerDay + firstLine.connectingPassengersPerDay)
        #expect(secondLine.passengersPerDay
            == secondLine.directPassengersPerDay + secondLine.connectingPassengersPerDay)
        #expect(network.passengersPerDay
            == network.lineSnapshots.reduce(0) { $0 + $1.passengersPerDay })
        #expect(network.potentialDailyJourneys
            == network.lineSnapshots.reduce(0) { $0 + $1.potentialDailyJourneys })
        #expect(network.unservedDailyJourneys
            == network.potentialDailyJourneys - network.passengersPerDay)
        #expect(alpha.servedDailyJourneys == firstLine.passengersPerDay)
        #expect(charlie.servedDailyJourneys == secondLine.passengersPerDay)
        #expect(interchange.servedDailyJourneys
            == firstLine.passengersPerDay + secondLine.passengersPerDay)
        #expect(alpha.transferJourneysPerDay == 0)
        #expect(charlie.transferJourneysPerDay == 0)
        #expect(interchange.transferJourneysPerDay == connection.passengersPerDay)
        #expect(alpha.connectedDestinationCount == 1)
        #expect(interchange.connectedDestinationCount == 2)
        #expect(charlie.connectedDestinationCount == 1)
        #expect(alpha.busiestDirectDestinationCRS == "BBB")
        #expect(charlie.busiestDirectDestinationCRS == "BBB")
    }

    @Test("Population multipliers apply to the outer market, not the interchange")
    func populationGrowthUsesOuterEndpoints() throws {
        let simulation = PassengerSimulation()
        let lines = [
            line(firstID, "AAA", "BBB", distance: 20),
            line(secondID, "BBB", "CCC", distance: 30),
        ]
        func connection(_ multipliers: [String: Double]) throws
            -> PassengerConnectingJourneySnapshot {
            try #require(simulation.evaluate(
                lines,
                stationPopulationMultipliers: multipliers
            ).connectingJourneySnapshots.first)
        }

        let baseline = try connection([:])
        let interchangeGrowth = try connection(["BBB": 1.5])
        let outerGrowth = try connection(["AAA": 1.5, "CCC": 1.5])

        #expect(interchangeGrowth.potentialDailyJourneys == baseline.potentialDailyJourneys)
        #expect(outerGrowth.potentialDailyJourneys > baseline.potentialDailyJourneys)
    }

    @Test("Invalid and extreme inputs remain finite and capacity bounded")
    func extremeInputsAreBounded() throws {
        let simulation = PassengerSimulation()
        let invalid = simulation.evaluate([
            line(firstID, "AAA", "BBB", distance: 20),
            line(secondID, "BBB", "CCC", distance: .nan),
        ])
        #expect(invalid.connectingJourneySnapshots.isEmpty)

        let extreme = simulation.evaluate(
            [
                line(firstID, "AAA", "BBB", distance: Double.greatestFiniteMagnitude),
                line(secondID, "BBB", "CCC", distance: Double.greatestFiniteMagnitude),
            ],
            stationPopulationMultipliers: ["AAA": 1e300, "CCC": 1e300]
        )
        let connection = try #require(extreme.connectingJourneySnapshots.first)

        #expect(connection.potentialDailyJourneys == Int.max)
        #expect(connection.generalizedJourneyMinutes.isFinite)
        #expect(connection.demandServedRatio.isFinite)
        #expect(connection.demandCapturedRatio.isFinite)
        #expect(extreme.potentialDailyJourneys >= extreme.passengersPerDay)
        #expect(extreme.lineSnapshots.allSatisfy {
            $0.passengersPerDay >= 0
                && $0.passengersPerDay <= $0.dailyCapacity
                && $0.peakOccupancyRatio.isFinite
                && $0.capacityPressure.isFinite
        })
    }

    @Test("Direct-only golden outputs are unchanged")
    func directGoldenIsUnchanged() throws {
        let simulation = PassengerSimulation()
        let input = PassengerLineInput(
            id: firstID,
            originCRS: "VIC",
            destinationCRS: "BTN",
            distanceKilometres: 80,
            frequency: .halfHourly
        )
        let network = simulation.evaluate([input])
        let line = try #require(network.line(for: firstID))

        #expect(line.potentialDailyJourneys == 7_360)
        #expect(line.attractedDailyJourneys == 5_152)
        #expect(line.directPassengersPerDay == 5_152)
        #expect(line.connectingPassengersPerDay == 0)
        #expect(line.passengersPerDay == 5_152)
        #expect(line.dailyCapacity == 17_280)
        #expect(line.journeyMinutes == 48)
        #expect(line.averageWaitMinutes == 15)
        #expect(abs(line.peakOccupancyRatio - 0.603_75) < 0.000_000_001)
        #expect(line.feedback == .goodService)
        #expect(network.potentialDailyJourneys == 7_360)
        #expect(network.passengersPerDay == 5_152)
        #expect(network.unservedDailyJourneys == 2_208)
        #expect(network.connectingJourneysPerDay == 0)
        #expect(network.connectingJourneySnapshots.isEmpty)
        #expect(network.stationSnapshots.allSatisfy { $0.transferJourneysPerDay == 0 })
    }

    @Test("A longer chain creates every one-change market but never a two-change market")
    func arbitraryChainIsBoundedToOneChange() throws {
        let thirdID = UUID(uuidString: "C3000000-0000-0000-0000-000000000003")!
        let network = PassengerSimulation().evaluate([
            line(firstID, "AAA", "BBB", distance: 20),
            line(secondID, "BBB", "CCC", distance: 20),
            line(thirdID, "CCC", "DDD", distance: 20),
        ])

        #expect(network.connectingJourneySnapshots.map(\.id) == [
            "AAA-BBB-CCC",
            "BBB-CCC-DDD",
        ])
        #expect(!network.connectingJourneySnapshots.contains {
            $0.originCRS == "AAA" && $0.destinationCRS == "DDD"
        })

        let firstConnection = try #require(network.connectingJourneySnapshots.first)
        let secondConnection = try #require(network.connectingJourneySnapshots.last)
        #expect(try #require(network.line(for: firstID)).connectingPassengersPerDay
            == firstConnection.passengersPerDay)
        #expect(try #require(network.line(for: thirdID)).connectingPassengersPerDay
            == secondConnection.passengersPerDay)
        #expect(try #require(network.line(for: secondID)).connectingPassengersPerDay
            == firstConnection.passengersPerDay + secondConnection.passengersPerDay)
    }

    @Test("An unrelated third service cannot disable an existing connecting market")
    func disjointThirdServicePreservesConnection() throws {
        let disjointID = UUID(uuidString: "C3000000-0000-0000-0000-000000000003")!
        let connectedLines = [
            line(firstID, "AAA", "BBB", distance: 20),
            line(secondID, "BBB", "CCC", distance: 30),
        ]
        let simulation = PassengerSimulation()
        let baseline = simulation.evaluate(connectedLines)
        let expanded = simulation.evaluate(connectedLines + [
            line(disjointID, "DDD", "EEE", distance: 25),
        ])
        let baselineConnection = try #require(
            baseline.connectingJourneySnapshots.first { $0.id == "AAA-BBB-CCC" }
        )
        let expandedConnection = try #require(
            expanded.connectingJourneySnapshots.first { $0.id == "AAA-BBB-CCC" }
        )

        #expect(expandedConnection == baselineConnection)
        #expect(expanded.connectingJourneySnapshots.count == 1)
        #expect(try #require(expanded.line(for: firstID)).connectingPassengersPerDay
            == baselineConnection.passengersPerDay)
        #expect(try #require(expanded.line(for: secondID)).connectingPassengersPerDay
            == baselineConnection.passengersPerDay)
        #expect(try #require(expanded.line(for: disjointID)).connectingPassengersPerDay == 0)
    }

    @Test("A direct service suppresses a competing transfer market")
    func directServiceOwnsItsMarket() {
        let thirdID = UUID(uuidString: "C3000000-0000-0000-0000-000000000003")!
        let network = PassengerSimulation().evaluate([
            line(firstID, "AAA", "BBB", distance: 20),
            line(secondID, "BBB", "CCC", distance: 20),
            line(thirdID, "AAA", "CCC", distance: 40),
        ])

        #expect(network.connectingJourneySnapshots.isEmpty)
        #expect(network.connectingJourneysPerDay == 0)
        #expect(network.lineSnapshots.allSatisfy { $0.connectingPassengersPerDay == 0 })
    }

    @Test("Alternative interchanges choose the lowest generalized-time path")
    func bestInterchangeIsDeterministic() throws {
        let thirdID = UUID(uuidString: "C3000000-0000-0000-0000-000000000003")!
        let fourthID = UUID(uuidString: "D4000000-0000-0000-0000-000000000004")!
        let lines = [
            line(firstID, "AAA", "XXX", distance: 40),
            line(secondID, "XXX", "DDD", distance: 40),
            line(thirdID, "AAA", "YYY", distance: 10),
            line(fourthID, "YYY", "DDD", distance: 10),
        ]
        let forward = PassengerSimulation().evaluate(lines)
        let reversed = PassengerSimulation().evaluate(Array(lines.reversed()))
        let alphaDelta = try #require(forward.connectingJourneySnapshots.first {
            $0.originCRS == "AAA" && $0.destinationCRS == "DDD"
        })
        let slowFirstLeg = try #require(forward.line(for: firstID))
        let slowSecondLeg = try #require(forward.line(for: secondID))

        #expect(forward == reversed)
        #expect(alphaDelta.interchangeCRS == "YYY")
        #expect(alphaDelta.inVehicleJourneyMinutes
            < slowFirstLeg.journeyMinutes + slowSecondLeg.journeyMinutes)
    }

    @Test("Twelve services share all one-change markets fairly and deterministically")
    func twelveServiceHubIsDeterministicAndCapacityBounded() throws {
        let lines = (0..<12).map { index in
            line(
                UUID(uuidString: String(
                    format: "D0000000-0000-0000-0000-%012d",
                    index + 1
                ))!,
                String(format: "S%02d", index),
                "HUB",
                distance: 20,
                frequency: .hourly
            )
        }
        let simulation = PassengerSimulation()
        let forward = simulation.evaluate(lines)
        let reversed = simulation.evaluate(Array(lines.reversed()))

        #expect(forward == reversed)
        #expect(forward.lineSnapshots.count == 12)
        #expect(forward.connectingJourneySnapshots.count == 66)
        #expect(forward.connectingJourneySnapshots.allSatisfy {
            $0.interchangeCRS == "HUB" && $0.passengersPerDay >= 0
        })
        #expect(forward.lineSnapshots.allSatisfy {
            $0.passengersPerDay <= $0.dailyCapacity
                && $0.connectingPassengersPerDay >= 0
        })
        #expect(forward.passengersPerDay
            == forward.lineSnapshots.reduce(0) { $0 + $1.passengersPerDay })
        #expect(forward.potentialDailyJourneys
            == forward.lineSnapshots.reduce(0) { $0 + $1.potentialDailyJourneys })
        #expect(try #require(forward.station(forCRS: "HUB")).transferJourneysPerDay
            == forward.connectingJourneysPerDay)

        let connectingLoads = forward.lineSnapshots.map(\.connectingPassengersPerDay)
        // Integer reconciliation may award one extra passenger on each of a line's eleven
        // incident outer markets, but can introduce no larger structural skew.
        #expect((connectingLoads.max() ?? 0) - (connectingLoads.min() ?? 0) <= 11)
    }

    @Test("A nationwide chain indexes transfer candidates by interchange")
    func nationwideChainTransferIndexIsDeterministic() {
        let serviceCount = 512
        let lines = (0..<serviceCount).map { index in
            line(
                UUID(uuidString: String(
                    format: "E0000000-0000-0000-0000-%012d",
                    index + 1
                ))!,
                String(format: "S%04d", index),
                String(format: "S%04d", index + 1),
                distance: 8,
                frequency: .hourly
            )
        }
        let simulation = PassengerSimulation()
        let forward = simulation.evaluate(lines)
        let reversed = simulation.evaluate(Array(lines.reversed()))

        #expect(forward == reversed)
        #expect(forward.lineSnapshots.count == serviceCount)
        #expect(forward.connectingJourneySnapshots.count == serviceCount - 1)
        #expect(forward.connectingJourneySnapshots.allSatisfy {
            $0.passengersPerDay >= 0
        })
    }

    @Test("A 512-spoke hub keeps only the best bounded transfer detail")
    func nationwideHubTransferDetailIsBoundedAndDeterministic() {
        let serviceCount = 512
        let slowestSpoke = String(format: "S%04d", serviceCount - 1)
        let lines = (0..<serviceCount).map { index in
            line(
                UUID(uuidString: String(
                    format: "F0000000-0000-0000-0000-%012d",
                    index + 1
                ))!,
                String(format: "S%04d", index),
                "HUB",
                distance: index == serviceCount - 1 ? 500 : 8,
                frequency: .hourly
            )
        }
        let simulation = PassengerSimulation()
        let forward = simulation.evaluate(lines)
        let reversed = simulation.evaluate(Array(lines.reversed()))

        #expect(forward == reversed)
        #expect(forward.lineSnapshots.count == serviceCount)
        #expect(
            forward.connectingJourneySnapshots.count
                == PassengerSimulation.maximumConnectingJourneyCandidatesPerInterchange
        )
        #expect(forward.connectingJourneySnapshots.allSatisfy {
            $0.interchangeCRS == "HUB"
                && $0.originCRS != slowestSpoke
                && $0.destinationCRS != slowestSpoke
        })
    }

    private func line(
        _ id: UUID,
        _ origin: String,
        _ destination: String,
        distance: Double,
        frequency: ServiceFrequency = .halfHourly,
        journeyTimeMultiplier: Double = 1,
        reliability: Double = 1,
        isOperating: Bool = true
    ) -> PassengerLineInput {
        PassengerLineInput(
            id: id,
            originCRS: origin,
            destinationCRS: destination,
            distanceKilometres: distance,
            frequency: frequency,
            journeyTimeMultiplier: journeyTimeMultiplier,
            reliability: reliability,
            isOperating: isOperating
        )
    }
}
