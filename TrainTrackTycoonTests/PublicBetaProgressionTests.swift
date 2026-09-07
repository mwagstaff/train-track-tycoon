import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Public-beta progression")
struct PublicBetaProgressionTests {
    @Test("Network facts normalize unsafe inputs and preserve valid values through Codable")
    func normalizedFacts() throws {
        let facts = PublicBetaNetworkFacts(
            completedLineCount: -1,
            stationCount: 12,
            expressLineCount: -3,
            passengersPerDay: -4,
            globalHappinessBasisPoints: 50_000,
            completedHighSpeedCorridorCount: -2,
            prestigeScore: 999,
            interchangeOrHigherStationCount: -1,
            lifetimeProfitableOperatingDays: -5,
            networkValuePence: -100
        )

        #expect(facts.completedLineCount == 0)
        #expect(facts.stationCount == 12)
        #expect(facts.expressLineCount == 0)
        #expect(facts.passengersPerDay == 0)
        #expect(facts.globalHappinessBasisPoints == 10_000)
        #expect(facts.completedHighSpeedCorridorCount == 0)
        #expect(facts.prestigeScore == 100)
        #expect(facts.interchangeOrHigherStationCount == 0)
        #expect(facts.lifetimeProfitableOperatingDays == 0)
        #expect(facts.networkValuePence == 0)

        let decoded = try JSONDecoder().decode(
            PublicBetaNetworkFacts.self,
            from: JSONEncoder().encode(facts)
        )
        #expect(decoded == facts)

        let sparse = try JSONDecoder().decode(
            PublicBetaNetworkFacts.self,
            from: Data("{}".utf8)
        )
        #expect(sparse == .zero)
    }

    @Test("Generic goals expose bounded, exact progress")
    func genericGoalProgress() throws {
        let goal = PublicBetaProgressGoal(metric: .passengersPerDay, targetValue: 50_000)
        let partial = goal.evaluate(facts: PublicBetaNetworkFacts(passengersPerDay: 12_500))
        let complete = goal.evaluate(facts: PublicBetaNetworkFacts(passengersPerDay: 60_000))

        #expect(partial.currentValue == 12_500)
        #expect(partial.targetValue == 50_000)
        #expect(partial.remainingValue == 37_500)
        #expect(abs(partial.fractionComplete - 0.25) < 0.000_001)
        #expect(!partial.isComplete)
        #expect(complete.currentValue == 60_000)
        #expect(complete.remainingValue == 0)
        #expect(complete.fractionComplete == 1)
        #expect(complete.isComplete)

        let invalidTarget = PublicBetaProgressGoal(metric: .stations, targetValue: -10)
        #expect(invalidTarget.targetValue == 1)
        let roundTrip = try JSONDecoder().decode(
            PublicBetaProgressGoal.self,
            from: JSONEncoder().encode(invalidTarget)
        )
        #expect(roundTrip == invalidTarget)
    }

    @Test("The public-beta achievement catalogue is ordered, unique and data driven")
    func achievementCatalogue() throws {
        let catalogue = PublicBetaAchievementCatalogue.publicBeta
        #expect(catalogue.definitions.map(\.id) == PublicBetaAchievementID.allCases)
        #expect(catalogue.definition(for: .passengerMagnet)?.goal.targetValue == 20_000)
        #expect(
            catalogue.definition(for: .highSpeedPioneer)?.goal.metric
                == .completedHighSpeedCorridors
        )

        let first = try #require(catalogue.definitions.first)
        let deduplicated = PublicBetaAchievementCatalogue(definitions: [first, first])
        #expect(deduplicated.definitions == [first])
    }

    @Test("Achievement unlocks are sticky and newly unlocked IDs follow catalogue order")
    func achievementEvaluation() throws {
        let catalogue = PublicBetaAchievementCatalogue.publicBeta
        let facts = PublicBetaNetworkFacts(
            completedLineCount: 1,
            stationCount: 2,
            expressLineCount: 1,
            passengersPerDay: 20_000,
            globalHappinessBasisPoints: 7_000,
            completedHighSpeedCorridorCount: 1,
            prestigeScore: 25,
            interchangeOrHigherStationCount: 0,
            lifetimeProfitableOperatingDays: 3,
            networkValuePence: 10_000
        )
        let evaluation = catalogue.evaluate(facts: facts)

        #expect(evaluation.newlyUnlockedIDs == [
            .firstLine,
            .firstExpressService,
            .passengerMagnet,
            .highSpeedPioneer,
        ])
        #expect(evaluation.unlockedIDs == [
            .firstLine,
            .firstExpressService,
            .passengerMagnet,
            .highSpeedPioneer,
        ])
        let networkBuilder = try #require(
            evaluation.statuses.first { $0.definition.id == .networkBuilder }
        )
        #expect(!networkBuilder.isUnlocked)
        #expect(networkBuilder.progress.remainingValue == 1)

        let sticky = catalogue.evaluate(
            facts: .zero,
            previouslyUnlocked: [.highSpeedPioneer]
        )
        let highSpeed = try #require(
            sticky.statuses.first { $0.definition.id == .highSpeedPioneer }
        )
        #expect(highSpeed.isUnlocked)
        #expect(highSpeed.wasPreviouslyUnlocked)
        #expect(!highSpeed.progress.isComplete)
        #expect(sticky.newlyUnlockedIDs.isEmpty)
        #expect(sticky.unlockedIDs == [.highSpeedPioneer])
    }

    @Test("The scenario catalogue exposes exactly two playable fixtures")
    func scenarioFixtures() throws {
        let catalogue = PublicBetaScenarioCatalogue.publicBeta
        #expect(catalogue.scenarios.map(\.id) == [.southernStarter, .highSpeedFuture])
        #expect(catalogue.definition(for: .southernStarter)?.recommendedMode == .career)
        #expect(catalogue.definition(for: .highSpeedFuture)?.recommendedMode == .zen)

        let partialFacts = PublicBetaNetworkFacts(
            completedLineCount: 2,
            stationCount: 3,
            passengersPerDay: 20_000,
            globalHappinessBasisPoints: 5_400
        )
        let partial = try #require(
            catalogue.evaluate(scenarioID: .southernStarter, facts: partialFacts)
        )
        #expect(partial.objectives.count == 4)
        #expect(partial.completedObjectiveCount == 3)
        #expect(!partial.isComplete)
        let happiness = try #require(
            partial.objectives.first { $0.definition.id == "reach-55-happiness" }
        )
        #expect(happiness.progress.remainingValue == 100)

        let completed = try #require(catalogue.evaluate(
            scenarioID: .southernStarter,
            facts: PublicBetaNetworkFacts(
                completedLineCount: 2,
                stationCount: 3,
                passengersPerDay: 20_000,
                globalHappinessBasisPoints: 5_500
            )
        ))
        #expect(completed.completedObjectiveCount == 4)
        #expect(completed.isComplete)

        let highSpeed = try #require(catalogue.evaluate(
            scenarioID: .highSpeedFuture,
            facts: PublicBetaNetworkFacts(
                passengersPerDay: 20_000,
                completedHighSpeedCorridorCount: 2,
                prestigeScore: 45
            )
        ))
        #expect(highSpeed.isComplete)
    }

    @Test("Every count-based public-beta goal fits the current two-line POC ceiling")
    func progressionGoalsFitCurrentPOC() {
        let maximumLines = 2
        let maximumUniqueEndpointStations = maximumLines * 2

        for achievement in PublicBetaAchievementCatalogue.publicBeta.definitions {
            switch achievement.goal.metric {
            case .completedLines, .expressLines, .completedHighSpeedCorridors:
                #expect(achievement.goal.targetValue <= Int64(maximumLines))
            case .stations, .interchangeOrHigherStations:
                #expect(achievement.goal.targetValue <= Int64(maximumUniqueEndpointStations))
            default:
                break
            }
        }

        for scenario in PublicBetaScenarioCatalogue.publicBeta.scenarios {
            for objective in scenario.objectives {
                switch objective.goal.metric {
                case .completedLines, .expressLines, .completedHighSpeedCorridors:
                    #expect(objective.goal.targetValue <= Int64(maximumLines))
                case .stations, .interchangeOrHigherStations:
                    #expect(objective.goal.targetValue <= Int64(maximumUniqueEndpointStations))
                default:
                    break
                }
            }
        }
    }

    @Test("Scenario and objective duplicates preserve the first stable definition")
    func scenarioDeduplication() throws {
        let original = try #require(
            PublicBetaScenarioCatalogue.publicBeta.definition(for: .southernStarter)
        )
        let duplicateObjective = try #require(original.objectives.first)
        let normalizedScenario = PublicBetaScenarioDefinition(
            id: .southernStarter,
            title: "Fixture",
            summary: "Fixture",
            recommendedMode: .zen,
            objectives: [duplicateObjective, duplicateObjective]
        )
        #expect(normalizedScenario.objectives == [duplicateObjective])

        let catalogue = PublicBetaScenarioCatalogue(
            scenarios: [normalizedScenario, original]
        )
        #expect(catalogue.scenarios == [normalizedScenario])
        let evaluation = try #require(
            catalogue.evaluate(scenarioID: .southernStarter, facts: .zero)
        )
        #expect(!evaluation.isComplete)
        #expect(evaluation.objectives.count == 1)
    }

    @Test("Daily history sorts, replaces and discards the oldest records at its bound")
    func boundedHistory() {
        var history = PublicBetaDailyNetworkHistory(maximumRecordCount: 3)
        history.record(record(day: 3, passengers: 300, result: 30))
        history.record(record(day: 1, passengers: 100, result: 10))
        history.record(record(day: 2, passengers: 200, result: 20))
        #expect(history.records.map(\.operatingDay) == [1, 2, 3])

        history.record(record(day: 4, passengers: 400, result: 40))
        #expect(history.records.map(\.operatingDay) == [2, 3, 4])

        history.record(record(day: 3, passengers: 333, result: -3))
        #expect(history.records.map(\.operatingDay) == [2, 3, 4])
        #expect(history.records[1].facts.passengersPerDay == 333)
        #expect(history.records[1].operatingResultPence == -3)

        let copy = history.recording(record(day: 5, passengers: 500, result: 50))
        #expect(history.records.map(\.operatingDay) == [2, 3, 4])
        #expect(copy.records.map(\.operatingDay) == [3, 4, 5])
    }

    @Test("Daily statistics are exact and deterministic")
    func historyStatistics() {
        let history = PublicBetaDailyNetworkHistory(
            maximumRecordCount: 10,
            records: [
                record(
                    day: 3,
                    passengers: 400,
                    happiness: 8_000,
                    result: 80,
                    lines: 4,
                    stations: 5,
                    value: 300,
                    prestige: 45
                ),
                record(
                    day: 1,
                    passengers: 100,
                    happiness: 5_000,
                    result: -20,
                    lines: 1,
                    stations: 2,
                    value: 100,
                    prestige: 0
                ),
                record(
                    day: 2,
                    passengers: 200,
                    happiness: 7_000,
                    result: 50,
                    lines: 2,
                    stations: 3,
                    value: 200,
                    prestige: 25
                ),
            ]
        )
        let statistics = history.statistics

        #expect(statistics.recordedDayCount == 3)
        #expect(statistics.firstOperatingDay == 1)
        #expect(statistics.lastOperatingDay == 3)
        #expect(statistics.totalRecordedPassengers == 700)
        #expect(statistics.averagePassengersPerDay == 233)
        #expect(statistics.peakPassengersPerDay == 400)
        #expect(statistics.averageHappinessBasisPoints == 6_666)
        #expect(statistics.cumulativeOperatingResultPence == 110)
        #expect(statistics.profitableDayCount == 2)
        #expect(statistics.latestOperatingResultPence == 80)
        #expect(statistics.passengerChangeFromPreviousDay == 200)
        #expect(statistics.completedLineChangeFromFirstDay == 3)
        #expect(statistics.stationChangeFromFirstDay == 3)
        #expect(statistics.latestNetworkValuePence == 300)
        #expect(statistics.latestPrestigeScore == 45)
        #expect(history.latestRecord?.operatingDay == 3)
    }

    @Test("Empty and one-day histories expose stable zero deltas")
    func shortHistoryStatistics() {
        #expect(PublicBetaDailyNetworkHistory().statistics == .empty)

        let history = PublicBetaDailyNetworkHistory(records: [
            record(day: 9, passengers: 10, result: 0, lines: 2, stations: 4),
        ])
        #expect(history.statistics.passengerChangeFromPreviousDay == 0)
        #expect(history.statistics.completedLineChangeFromFirstDay == 0)
        #expect(history.statistics.stationChangeFromFirstDay == 0)
        #expect(history.statistics.profitableDayCount == 0)
    }

    @Test("History Codable restoration reapplies ordering, deduplication and bounds")
    func historyCodableInvariants() throws {
        let history = PublicBetaDailyNetworkHistory(
            maximumRecordCount: 2,
            records: [
                record(day: 3, passengers: 30, result: 3),
                record(day: 1, passengers: 10, result: 1),
                record(day: 2, passengers: 20, result: 2),
            ]
        )
        let decoded = try JSONDecoder().decode(
            PublicBetaDailyNetworkHistory.self,
            from: JSONEncoder().encode(history)
        )
        #expect(decoded == history)
        #expect(decoded.records.map(\.operatingDay) == [2, 3])

        let malformed = Data(
            #"{"maximumRecordCount":0,"records":[{"operatingDay":1,"facts":{},"operatingResultPence":1,"totalNetworkPopulation":10,"latestPopulationChange":1},{"operatingDay":1,"facts":{"passengersPerDay":9},"operatingResultPence":2,"totalNetworkPopulation":12,"latestPopulationChange":2}]}"#.utf8
        )
        let normalized = try JSONDecoder().decode(
            PublicBetaDailyNetworkHistory.self,
            from: malformed
        )
        #expect(normalized.maximumRecordCount == 1)
        #expect(normalized.records.count == 1)
        #expect(normalized.records[0].facts.passengersPerDay == 9)
        #expect(normalized.records[0].operatingResultPence == 2)
        #expect(normalized.records[0].totalNetworkPopulation == 12)
        #expect(normalized.records[0].latestPopulationChange == 2)
    }

    @Test("History totals saturate instead of overflowing")
    func historyOverflowSafety() {
        let positive = PublicBetaDailyNetworkHistory(records: [
            record(day: 1, passengers: .max, result: .max),
            record(day: 2, passengers: 1, result: 1),
        ]).statistics
        #expect(positive.totalRecordedPassengers == .max)
        #expect(positive.cumulativeOperatingResultPence == .max)

        let negative = PublicBetaDailyNetworkHistory(records: [
            record(day: 1, passengers: 0, result: .min),
            record(day: 2, passengers: 0, result: -1),
        ]).statistics
        #expect(negative.cumulativeOperatingResultPence == .min)
    }

    @Test("History capacity is always finite and positive")
    func historyCapacitySafety() {
        #expect(PublicBetaDailyNetworkHistory(maximumRecordCount: 0).maximumRecordCount == 1)
        #expect(
            PublicBetaDailyNetworkHistory(maximumRecordCount: .max).maximumRecordCount
                == PublicBetaDailyNetworkHistory.absoluteMaximumRecordCount
        )
    }

    private func record(
        day: UInt64,
        passengers: Int64,
        happiness: Int = 0,
        result: Int64,
        lines: Int = 0,
        stations: Int = 0,
        value: Int64 = 0,
        prestige: Int = 0
    ) -> PublicBetaDailyNetworkRecord {
        PublicBetaDailyNetworkRecord(
            operatingDay: day,
            facts: PublicBetaNetworkFacts(
                completedLineCount: lines,
                stationCount: stations,
                passengersPerDay: passengers,
                globalHappinessBasisPoints: happiness,
                prestigeScore: prestige,
                networkValuePence: value
            ),
            operatingResultPence: result
        )
    }
}
