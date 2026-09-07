import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Accessibility and happiness")
struct AccessibilityHappinessTests {
    @Test("Documented weights produce a stable known score")
    func documentedWeightsAndKnownScore() throws {
        let snapshot = AccessibilityHappiness().evaluate(
            settlements: [settlement("AAA"), settlement("BBB")],
            services: [
                service(
                    id: firstID,
                    from: "AAA",
                    to: "BBB",
                    journeyMinutes: 60,
                    departuresPerHour: 1,
                    reliability: 0.8,
                    occupancy: 0.5
                ),
            ]
        )
        let local = try #require(snapshot.station(forCRS: " aaa "))

        #expect(HappinessComponentWeights.documented == HappinessComponentWeights(
            reachableDestinations: 0.30,
            destinationImportance: 0.20,
            journeyTime: 0.20,
            frequency: 0.15,
            reliability: 0.10,
            crowding: 0.05
        ))
        #expect(local.componentScores.reachableDestinations == 1)
        #expect(local.componentScores.destinationImportance == 1)
        #expect(local.componentScores.journeyTime == 0.5)
        #expect(local.componentScores.frequency == 0.5)
        #expect(local.componentScores.reliability == 0.8)
        #expect(local.componentScores.crowding == 1)
        #expect(abs(local.happinessScore - 80.5) < tolerance)
        #expect(local.band == .excellent)
        #expect(abs(snapshot.globalHappinessScore - 80.5) < tolerance)
        #expect(snapshot.statistics == NetworkAccessibilityStatistics(
            settlementCount: 2,
            connectedSettlementCount: 2,
            isolatedSettlementCount: 0,
            operatingServiceCount: 1,
            overcrowdedServiceCount: 0,
            reachableSettlementPairCount: 1,
            possibleSettlementPairCount: 1,
            coverageRatio: 1,
            averageReachableDestinations: 1,
            averageJourneyMinutes: 60,
            averageInterchanges: 0,
            maximumEvaluatedDestinationsPerSettlement: 1
        ))
    }

    @Test("Frequency has deterministic diminishing returns")
    func frequencyHasDiminishingReturns() throws {
        let hourly = try localSnapshot(departuresPerHour: 1)
        let halfHourly = try localSnapshot(departuresPerHour: 2)
        let quarterHourly = try localSnapshot(departuresPerHour: 4)

        #expect(abs(hourly.componentScores.frequency - 0.5) < tolerance)
        #expect(abs(halfHourly.componentScores.frequency - (2.0 / 3.0)) < tolerance)
        #expect(abs(quarterHourly.componentScores.frequency - 0.8) < tolerance)
        #expect(hourly.happinessScore < halfHourly.happinessScore)
        #expect(halfHourly.happinessScore < quarterHourly.happinessScore)
        #expect(
            halfHourly.happinessScore - hourly.happinessScore
                > quarterHourly.happinessScore - halfHourly.happinessScore
        )
    }

    @Test("Local routes, importance, global weighting, and network statistics agree")
    func localAndGlobalAggregation() throws {
        let settlements = [
            settlement("AAA", importance: 1, happinessWeight: 1),
            settlement("BBB", importance: 2, happinessWeight: 2),
            settlement("CCC", importance: 4, happinessWeight: 4),
            settlement("DDD", importance: 3, happinessWeight: 3),
        ]
        let services = [
            service(id: firstID, from: "AAA", to: "BBB", journeyMinutes: 20),
            service(id: secondID, from: "BBB", to: "CCC", journeyMinutes: 30),
        ]

        let snapshot = AccessibilityHappiness().evaluate(
            settlements: settlements,
            services: services
        )
        let alpha = try #require(snapshot.station(forCRS: "AAA"))
        let bravo = try #require(snapshot.station(forCRS: "BBB"))
        let charlie = try #require(snapshot.station(forCRS: "CCC"))
        let isolated = try #require(snapshot.station(forCRS: " ddd "))

        #expect(alpha.reachableDestinationCRSs == ["BBB", "CCC"])
        #expect(alpha.featuredImportantDestinationCRS == "CCC")
        #expect(abs(alpha.averageJourneyMinutes - 40) < tolerance)
        #expect(abs(alpha.averageInterchanges - (2.0 / 3.0)) < tolerance)
        #expect(isolated.happinessScore == 0)
        #expect(isolated.feedback.map(\.kind) == [.noRailAccess])
        #expect(snapshot.statistics.settlementCount == 4)
        #expect(snapshot.statistics.connectedSettlementCount == 3)
        #expect(snapshot.statistics.isolatedSettlementCount == 1)
        #expect(snapshot.statistics.reachableSettlementPairCount == 3)
        #expect(snapshot.statistics.possibleSettlementPairCount == 6)
        #expect(snapshot.statistics.coverageRatio == 0.5)
        #expect(snapshot.statistics.averageReachableDestinations == 1.5)
        #expect(abs(snapshot.statistics.averageJourneyMinutes - (100.0 / 3.0)) < tolerance)
        #expect(abs(snapshot.statistics.averageInterchanges - (1.0 / 3.0)) < tolerance)

        let expectedGlobal = (
            alpha.happinessScore * 1
                + bravo.happinessScore * 2
                + charlie.happinessScore * 4
                + isolated.happinessScore * 3
        ) / 10
        #expect(abs(snapshot.globalHappinessScore - expectedGlobal) < tolerance)
    }

    @Test("National snapshots retain a bounded destination sample without changing totals")
    func reachableDestinationStorageIsBounded() throws {
        let snapshot = AccessibilityHappiness(
            configuration: AccessibilityHappinessConfiguration(
                maximumRetainedReachableDestinationCRSs: 2
            )
        ).evaluate(
            settlements: [
                settlement("AAA"),
                settlement("BBB"),
                settlement("CCC"),
                settlement("DDD"),
            ],
            services: [
                service(id: firstID, from: "AAA", to: "BBB", journeyMinutes: 10),
                service(id: secondID, from: "BBB", to: "CCC", journeyMinutes: 10),
                service(
                    id: UUID(uuidString: "C3000000-0000-0000-0000-000000000003")!,
                    from: "CCC",
                    to: "DDD",
                    journeyMinutes: 10
                ),
            ]
        )

        let alpha = try #require(snapshot.station(forCRS: "AAA"))
        #expect(alpha.reachableDestinationCount == 3)
        #expect(alpha.reachableDestinationCRSs == ["BBB", "CCC"])
        #expect(snapshot.statistics.reachableSettlementPairCount == 6)
        #expect(snapshot.statistics.coverageRatio == 1)
    }

    @Test("A 2,606-station connected network has bounded deterministic route work")
    func nationalRouteEvaluationIsBounded() throws {
        let stationCount = 2_606
        let detailedBudget = 16
        let settlements = (0..<stationCount).map { index in
            settlement(String(format: "S%04d", index))
        }
        var services = [AccessibilityServiceInput]()
        services.reserveCapacity(stationCount * 4)
        var serviceOrdinal = 1
        // Four forward neighbours create a connected, bidirectional graph with up to eight
        // incident services per station: substantially denser than a simple benchmark chain.
        for originIndex in 0..<stationCount {
            for offset in 1...4 {
                let destinationIndex = originIndex + offset
                guard destinationIndex < stationCount else { continue }
                let id = UUID(uuidString: String(
                    format: "A1700000-0000-0000-0000-%012d",
                    serviceOrdinal
                ))!
                services.append(service(
                    id: id,
                    from: String(format: "S%04d", originIndex),
                    to: String(format: "S%04d", destinationIndex),
                    journeyMinutes: Double(offset * 4)
                ))
                serviceOrdinal += 1
            }
        }

        let evaluator = AccessibilityHappiness(
            configuration: AccessibilityHappinessConfiguration(
                maximumRetainedReachableDestinationCRSs: detailedBudget,
                maximumEvaluatedDestinationsPerSettlement: detailedBudget
            )
        )
        let snapshot = evaluator.evaluate(settlements: settlements, services: services)
        let reversed = evaluator.evaluate(
            settlements: Array(settlements.reversed()),
            services: Array(services.reversed())
        )

        let first = try #require(snapshot.station(forCRS: "S0000"))
        #expect(snapshot == reversed)
        #expect(snapshot.stationsByCRS.count == stationCount)
        #expect(first.reachableDestinationCount == stationCount - 1)
        #expect(first.reachableDestinationCRSs.count == detailedBudget)
        #expect(snapshot.statistics.reachableSettlementPairCount
            == stationCount * (stationCount - 1) / 2)
        #expect(snapshot.statistics.maximumEvaluatedDestinationsPerSettlement
            == detailedBudget)
        #expect(snapshot.globalHappinessScore.isFinite)
        #expect((0...100).contains(snapshot.globalHappinessScore))
    }

    @Test("Catalogue convenience API retains unconnected settlements")
    func passengerSnapshotConvenienceIncludesCatalogue() throws {
        let passengerSnapshot = PassengerSimulation().evaluate([
            PassengerLineInput(
                id: firstID,
                originCRS: "VIC",
                destinationCRS: "BTN",
                distanceKilometres: 80,
                frequency: .halfHourly
            ),
        ])

        let snapshot = AccessibilityHappiness().evaluate(
            stationCRSs: [" vic ", "BTN", "zzz", "VIC"],
            passengerSnapshot: passengerSnapshot,
            stationImportanceWeights: ["VIC": 3, "btn": 2, "ZZZ": 1],
            reliabilityByLineID: [firstID: 1]
        )

        #expect(snapshot.sortedStationSnapshots.map(\.stationCRS) == ["BTN", "VIC", "ZZZ"])
        #expect(try #require(snapshot.station(forCRS: " vic ")).happinessScore > 0)
        let unconnected = try #require(snapshot.station(forCRS: " zzz "))
        #expect(unconnected.happinessScore == 0)
        #expect(unconnected.reachableDestinationCount == 0)
        #expect(unconnected.feedback.map(\.kind) == [.noRailAccess])
    }

    @Test("A line that is not operating provides no accessibility")
    func nonOperatingServiceIsExcluded() throws {
        let passengerSnapshot = PassengerSimulation().evaluate([
            PassengerLineInput(
                id: firstID,
                originCRS: "AAA",
                destinationCRS: "BBB",
                distanceKilometres: 20,
                isOperating: false
            ),
        ])

        let snapshot = AccessibilityHappiness().evaluate(
            stationCRSs: ["AAA", "BBB"],
            passengerSnapshot: passengerSnapshot
        )

        #expect(snapshot.statistics.operatingServiceCount == 0)
        #expect(snapshot.statistics.connectedSettlementCount == 0)
        #expect(snapshot.globalHappinessScore == 0)
        #expect(try #require(snapshot.station(forCRS: "AAA")).feedback.map(\.kind)
            == [.noRailAccess])
    }

    @Test("Evaluation and feedback are independent of input ordering")
    func deterministicOrderingAndFeedback() throws {
        let settlements = [settlement("AAA"), settlement("BBB"), settlement("CCC")]
        let services = [
            service(
                id: firstID,
                from: "AAA",
                to: "BBB",
                journeyMinutes: 600,
                departuresPerHour: 0.1,
                reliability: 0.2,
                occupancy: 1
            ),
            service(
                id: secondID,
                from: "BBB",
                to: "CCC",
                journeyMinutes: 15,
                departuresPerHour: 4,
                reliability: 1,
                occupancy: 0.5
            ),
        ]
        let evaluator = AccessibilityHappiness()

        let forward = evaluator.evaluate(settlements: settlements, services: services)
        let reversed = evaluator.evaluate(
            settlements: Array(settlements.reversed()),
            services: Array(services.reversed())
        )

        #expect(forward == reversed)
        let isolatedPairOnly = evaluator.evaluate(
            settlements: Array(settlements.prefix(2)),
            services: [services[0]]
        )
        let alpha = try #require(isolatedPairOnly.station(forCRS: "AAA"))
        #expect(alpha.feedback.map(\.kind) == [
            .slowJourneys,
            .infrequentService,
            .unreliableService,
        ])
    }

    @Test("Strong service feedback identifies the important destination")
    func stablePositiveFeedback() throws {
        let snapshot = AccessibilityHappiness().evaluate(
            settlements: [
                settlement("AAA", importance: 1),
                settlement("BBB", importance: 4),
            ],
            services: [
                service(
                    id: firstID,
                    from: "AAA",
                    to: "BBB",
                    journeyMinutes: 10,
                    departuresPerHour: 4,
                    reliability: 1,
                    occupancy: 0.5
                ),
            ]
        )
        let alpha = try #require(snapshot.station(forCRS: "AAA"))

        #expect(alpha.feedback.map(\.kind) == [
            .excellentDestinationAccess,
            .strongAccessibility,
        ])
        #expect(alpha.feedback.first?.relatedStationCRS == "BBB")
    }

    @Test("Invalid configuration values have deterministic bounded fallbacks")
    func invalidConfigurationFallbacks() {
        let invalidWeights = HappinessComponentWeights(
            reachableDestinations: .greatestFiniteMagnitude,
            destinationImportance: .greatestFiniteMagnitude,
            journeyTime: .greatestFiniteMagnitude,
            frequency: .greatestFiniteMagnitude,
            reliability: .greatestFiniteMagnitude,
            crowding: .greatestFiniteMagnitude
        )
        let components = HappinessComponentScores(
            reachableDestinations: 2,
            destinationImportance: -1,
            journeyTime: .nan,
            frequency: 1,
            reliability: 1,
            crowding: 1
        )

        #expect(abs(components.happinessScore(using: invalidWeights) - 60) < tolerance)
        #expect(AccessibilityHappiness().evaluate(settlements: [], services: []) == .empty)
    }

    private func localSnapshot(departuresPerHour: Double) throws
        -> SettlementHappinessSnapshot {
        let snapshot = AccessibilityHappiness().evaluate(
            settlements: [settlement("AAA"), settlement("BBB")],
            services: [
                service(
                    id: firstID,
                    from: "AAA",
                    to: "BBB",
                    journeyMinutes: 30,
                    departuresPerHour: departuresPerHour,
                    reliability: 1,
                    occupancy: 0.5
                ),
            ]
        )
        return try #require(snapshot.station(forCRS: "AAA"))
    }

    private func settlement(
        _ crs: String,
        importance: Double = 1,
        happinessWeight: Double? = nil
    ) -> SettlementAccessibilityInput {
        SettlementAccessibilityInput(
            stationCRS: crs,
            destinationImportance: importance,
            happinessWeight: happinessWeight
        )
    }

    private func service(
        id: UUID,
        from originCRS: String,
        to destinationCRS: String,
        journeyMinutes: Double,
        departuresPerHour: Double = 2,
        reliability: Double? = 1,
        occupancy: Double = 0.5
    ) -> AccessibilityServiceInput {
        AccessibilityServiceInput(
            id: id,
            originCRS: originCRS,
            destinationCRS: destinationCRS,
            journeyMinutes: journeyMinutes,
            departuresPerHour: departuresPerHour,
            reliability: reliability,
            peakOccupancyRatio: occupancy
        )
    }

    private var firstID: UUID {
        UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    }

    private var secondID: UUID {
        UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    }

    private var tolerance: Double { 0.000_000_001 }
}
