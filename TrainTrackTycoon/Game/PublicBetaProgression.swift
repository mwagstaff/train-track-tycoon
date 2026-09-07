import Foundation

/// A compact, persistence-friendly view of the network facts used by public-beta progression.
///
/// Values are normalized at the boundary so achievements, scenarios and history remain pure and
/// deterministic even when a partially migrated save or provisional simulation produces bad data.
nonisolated struct PublicBetaNetworkFacts: Codable, Equatable, Sendable {
    let completedLineCount: Int
    let stationCount: Int
    let expressLineCount: Int
    let passengersPerDay: Int64
    /// The 0...100 happiness score represented as 0...10,000 basis points.
    let globalHappinessBasisPoints: Int
    let completedHighSpeedCorridorCount: Int
    /// The bounded 0...100 high-speed prestige score.
    let prestigeScore: Int
    let interchangeOrHigherStationCount: Int
    let lifetimeProfitableOperatingDays: Int
    let networkValuePence: Int64

    init(
        completedLineCount: Int = 0,
        stationCount: Int = 0,
        expressLineCount: Int = 0,
        passengersPerDay: Int64 = 0,
        globalHappinessBasisPoints: Int = 0,
        completedHighSpeedCorridorCount: Int = 0,
        prestigeScore: Int = 0,
        interchangeOrHigherStationCount: Int = 0,
        lifetimeProfitableOperatingDays: Int = 0,
        networkValuePence: Int64 = 0
    ) {
        self.completedLineCount = max(completedLineCount, 0)
        self.stationCount = max(stationCount, 0)
        self.expressLineCount = max(expressLineCount, 0)
        self.passengersPerDay = max(passengersPerDay, 0)
        self.globalHappinessBasisPoints = min(max(globalHappinessBasisPoints, 0), 10_000)
        self.completedHighSpeedCorridorCount = max(completedHighSpeedCorridorCount, 0)
        self.prestigeScore = min(max(prestigeScore, 0), 100)
        self.interchangeOrHigherStationCount = max(interchangeOrHigherStationCount, 0)
        self.lifetimeProfitableOperatingDays = max(lifetimeProfitableOperatingDays, 0)
        self.networkValuePence = max(networkValuePence, 0)
    }

    static let zero = Self()

    func value(for metric: PublicBetaProgressMetric) -> Int64 {
        switch metric {
        case .completedLines:
            Int64(completedLineCount)
        case .stations:
            Int64(stationCount)
        case .expressLines:
            Int64(expressLineCount)
        case .passengersPerDay:
            passengersPerDay
        case .globalHappinessBasisPoints:
            Int64(globalHappinessBasisPoints)
        case .completedHighSpeedCorridors:
            Int64(completedHighSpeedCorridorCount)
        case .prestigeScore:
            Int64(prestigeScore)
        case .interchangeOrHigherStations:
            Int64(interchangeOrHigherStationCount)
        case .lifetimeProfitableOperatingDays:
            Int64(lifetimeProfitableOperatingDays)
        case .networkValuePence:
            networkValuePence
        }
    }

    private enum CodingKeys: String, CodingKey {
        case completedLineCount
        case stationCount
        case expressLineCount
        case passengersPerDay
        case globalHappinessBasisPoints
        case completedHighSpeedCorridorCount
        case prestigeScore
        case interchangeOrHigherStationCount
        case lifetimeProfitableOperatingDays
        case networkValuePence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            completedLineCount: try container.decodeIfPresent(
                Int.self,
                forKey: .completedLineCount
            ) ?? 0,
            stationCount: try container.decodeIfPresent(Int.self, forKey: .stationCount) ?? 0,
            expressLineCount: try container.decodeIfPresent(
                Int.self,
                forKey: .expressLineCount
            ) ?? 0,
            passengersPerDay: try container.decodeIfPresent(
                Int64.self,
                forKey: .passengersPerDay
            ) ?? 0,
            globalHappinessBasisPoints: try container.decodeIfPresent(
                Int.self,
                forKey: .globalHappinessBasisPoints
            ) ?? 0,
            completedHighSpeedCorridorCount: try container.decodeIfPresent(
                Int.self,
                forKey: .completedHighSpeedCorridorCount
            ) ?? 0,
            prestigeScore: try container.decodeIfPresent(Int.self, forKey: .prestigeScore) ?? 0,
            interchangeOrHigherStationCount: try container.decodeIfPresent(
                Int.self,
                forKey: .interchangeOrHigherStationCount
            ) ?? 0,
            lifetimeProfitableOperatingDays: try container.decodeIfPresent(
                Int.self,
                forKey: .lifetimeProfitableOperatingDays
            ) ?? 0,
            networkValuePence: try container.decodeIfPresent(
                Int64.self,
                forKey: .networkValuePence
            ) ?? 0
        )
    }
}

nonisolated enum PublicBetaProgressMetric: String, CaseIterable, Codable, Equatable, Sendable {
    case completedLines
    case stations
    case expressLines
    case passengersPerDay
    case globalHappinessBasisPoints
    case completedHighSpeedCorridors
    case prestigeScore
    case interchangeOrHigherStations
    case lifetimeProfitableOperatingDays
    case networkValuePence
}

nonisolated struct PublicBetaProgressGoal: Codable, Equatable, Sendable {
    let metric: PublicBetaProgressMetric
    let targetValue: Int64

    init(metric: PublicBetaProgressMetric, targetValue: Int64) {
        self.metric = metric
        self.targetValue = max(targetValue, 1)
    }

    func evaluate(facts: PublicBetaNetworkFacts) -> PublicBetaGoalProgress {
        let currentValue = max(facts.value(for: metric), 0)
        let boundedCurrent = min(currentValue, targetValue)
        return PublicBetaGoalProgress(
            metric: metric,
            currentValue: currentValue,
            targetValue: targetValue,
            remainingValue: targetValue - boundedCurrent,
            fractionComplete: min(Double(currentValue) / Double(targetValue), 1),
            isComplete: currentValue >= targetValue
        )
    }

    private enum CodingKeys: String, CodingKey {
        case metric
        case targetValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            metric: try container.decode(PublicBetaProgressMetric.self, forKey: .metric),
            targetValue: try container.decode(Int64.self, forKey: .targetValue)
        )
    }
}

nonisolated struct PublicBetaGoalProgress: Equatable, Sendable {
    let metric: PublicBetaProgressMetric
    let currentValue: Int64
    let targetValue: Int64
    let remainingValue: Int64
    let fractionComplete: Double
    let isComplete: Bool
}

// MARK: - Achievements

nonisolated enum PublicBetaAchievementID: String, CaseIterable, Codable, Equatable, Hashable,
    Sendable {
    case firstLine
    case networkBuilder
    case firstExpressService
    case passengerMagnet
    case highSpeedPioneer
    case majorInterchange
    case profitableWeek
}

nonisolated struct PublicBetaAchievementDefinition: Identifiable, Codable, Equatable, Sendable {
    let id: PublicBetaAchievementID
    let title: String
    let summary: String
    let goal: PublicBetaProgressGoal
}

nonisolated struct PublicBetaAchievementStatus: Equatable, Sendable {
    let definition: PublicBetaAchievementDefinition
    let progress: PublicBetaGoalProgress
    let isUnlocked: Bool
    let wasPreviouslyUnlocked: Bool
}

nonisolated struct PublicBetaAchievementEvaluation: Equatable, Sendable {
    let statuses: [PublicBetaAchievementStatus]
    /// Newly completed IDs in stable catalogue order.
    let newlyUnlockedIDs: [PublicBetaAchievementID]

    var unlockedIDs: Set<PublicBetaAchievementID> {
        Set(statuses.lazy.filter(\.isUnlocked).map { $0.definition.id })
    }
}

/// A data-driven achievement catalogue with deterministic, sticky unlock evaluation.
nonisolated struct PublicBetaAchievementCatalogue: Equatable, Sendable {
    let definitions: [PublicBetaAchievementDefinition]

    init(definitions: [PublicBetaAchievementDefinition]) {
        var seen = Set<PublicBetaAchievementID>()
        self.definitions = definitions.filter { seen.insert($0.id).inserted }
    }

    func definition(for id: PublicBetaAchievementID) -> PublicBetaAchievementDefinition? {
        definitions.first { $0.id == id }
    }

    func evaluate(
        facts: PublicBetaNetworkFacts,
        previouslyUnlocked: Set<PublicBetaAchievementID> = []
    ) -> PublicBetaAchievementEvaluation {
        var newlyUnlockedIDs = [PublicBetaAchievementID]()
        let statuses = definitions.map { definition in
            let progress = definition.goal.evaluate(facts: facts)
            let wasPreviouslyUnlocked = previouslyUnlocked.contains(definition.id)
            if progress.isComplete, !wasPreviouslyUnlocked {
                newlyUnlockedIDs.append(definition.id)
            }
            return PublicBetaAchievementStatus(
                definition: definition,
                progress: progress,
                isUnlocked: wasPreviouslyUnlocked || progress.isComplete,
                wasPreviouslyUnlocked: wasPreviouslyUnlocked
            )
        }
        return PublicBetaAchievementEvaluation(
            statuses: statuses,
            newlyUnlockedIDs: newlyUnlockedIDs
        )
    }

    static let publicBeta = Self(definitions: [
        PublicBetaAchievementDefinition(
            id: .firstLine,
            title: "First Departure",
            summary: "Complete the first railway line.",
            goal: PublicBetaProgressGoal(metric: .completedLines, targetValue: 1)
        ),
        PublicBetaAchievementDefinition(
            id: .networkBuilder,
            title: "Network Builder",
            summary: "Serve three stations.",
            goal: PublicBetaProgressGoal(metric: .stations, targetValue: 3)
        ),
        PublicBetaAchievementDefinition(
            id: .firstExpressService,
            title: "First Express",
            summary: "Operate an express service.",
            goal: PublicBetaProgressGoal(metric: .expressLines, targetValue: 1)
        ),
        PublicBetaAchievementDefinition(
            id: .passengerMagnet,
            title: "Passenger Magnet",
            summary: "Carry 20,000 passengers in one operating day.",
            goal: PublicBetaProgressGoal(metric: .passengersPerDay, targetValue: 20_000)
        ),
        PublicBetaAchievementDefinition(
            id: .highSpeedPioneer,
            title: "High-Speed Pioneer",
            summary: "Complete a dedicated high-speed corridor.",
            goal: PublicBetaProgressGoal(
                metric: .completedHighSpeedCorridors,
                targetValue: 1
            )
        ),
        PublicBetaAchievementDefinition(
            id: .majorInterchange,
            title: "Connections Matter",
            summary: "Grow a station into an interchange or terminus.",
            goal: PublicBetaProgressGoal(
                metric: .interchangeOrHigherStations,
                targetValue: 1
            )
        ),
        PublicBetaAchievementDefinition(
            id: .profitableWeek,
            title: "Seven Good Days",
            summary: "Record seven profitable days in the saved 120-day history.",
            goal: PublicBetaProgressGoal(
                metric: .lifetimeProfitableOperatingDays,
                targetValue: 7
            )
        ),
    ])
}

// MARK: - Scenarios

nonisolated enum PublicBetaScenarioID: String, CaseIterable, Codable, Equatable, Hashable,
    Sendable {
    case southernStarter
    case highSpeedFuture
}

nonisolated struct PublicBetaScenarioObjectiveDefinition: Identifiable, Codable, Equatable,
    Sendable {
    let id: String
    let title: String
    let goal: PublicBetaProgressGoal
}

nonisolated struct PublicBetaScenarioDefinition: Identifiable, Codable, Equatable, Sendable {
    let id: PublicBetaScenarioID
    let title: String
    let summary: String
    let recommendedMode: GameMode
    let objectives: [PublicBetaScenarioObjectiveDefinition]

    init(
        id: PublicBetaScenarioID,
        title: String,
        summary: String,
        recommendedMode: GameMode,
        objectives: [PublicBetaScenarioObjectiveDefinition]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.recommendedMode = recommendedMode
        var seen = Set<String>()
        self.objectives = objectives.filter { seen.insert($0.id).inserted }
    }
}

nonisolated struct PublicBetaScenarioObjectiveProgress: Equatable, Sendable {
    let definition: PublicBetaScenarioObjectiveDefinition
    let progress: PublicBetaGoalProgress
}

nonisolated struct PublicBetaScenarioEvaluation: Equatable, Sendable {
    let scenario: PublicBetaScenarioDefinition
    let objectives: [PublicBetaScenarioObjectiveProgress]
    let completedObjectiveCount: Int
    let isComplete: Bool
}

/// Two small fixtures exercise the generic objective model without committing the game to a
/// large content library before public-beta playtesting.
nonisolated struct PublicBetaScenarioCatalogue: Equatable, Sendable {
    let scenarios: [PublicBetaScenarioDefinition]

    init(scenarios: [PublicBetaScenarioDefinition]) {
        var seen = Set<PublicBetaScenarioID>()
        self.scenarios = scenarios.filter { seen.insert($0.id).inserted }
    }

    func definition(for id: PublicBetaScenarioID) -> PublicBetaScenarioDefinition? {
        scenarios.first { $0.id == id }
    }

    func evaluate(
        scenarioID: PublicBetaScenarioID,
        facts: PublicBetaNetworkFacts
    ) -> PublicBetaScenarioEvaluation? {
        guard let scenario = definition(for: scenarioID) else { return nil }
        let objectives = scenario.objectives.map { objective in
            PublicBetaScenarioObjectiveProgress(
                definition: objective,
                progress: objective.goal.evaluate(facts: facts)
            )
        }
        let completedObjectiveCount = objectives.lazy.filter(\.progress.isComplete).count
        return PublicBetaScenarioEvaluation(
            scenario: scenario,
            objectives: objectives,
            completedObjectiveCount: completedObjectiveCount,
            isComplete: !objectives.isEmpty && completedObjectiveCount == objectives.count
        )
    }

    static let publicBeta = Self(scenarios: [
        PublicBetaScenarioDefinition(
            id: .southernStarter,
            title: "Southern Starter",
            summary: "Create a useful first network south of London.",
            recommendedMode: .career,
            objectives: [
                PublicBetaScenarioObjectiveDefinition(
                    id: "complete-two-lines",
                    title: "Complete two railway lines",
                    goal: PublicBetaProgressGoal(metric: .completedLines, targetValue: 2)
                ),
                PublicBetaScenarioObjectiveDefinition(
                    id: "serve-three-stations",
                    title: "Serve three stations",
                    goal: PublicBetaProgressGoal(metric: .stations, targetValue: 3)
                ),
                PublicBetaScenarioObjectiveDefinition(
                    id: "carry-20k-passengers",
                    title: "Carry 20,000 passengers per day",
                    goal: PublicBetaProgressGoal(metric: .passengersPerDay, targetValue: 20_000)
                ),
                PublicBetaScenarioObjectiveDefinition(
                    id: "reach-55-happiness",
                    title: "Reach 55% network happiness",
                    goal: PublicBetaProgressGoal(
                        metric: .globalHappinessBasisPoints,
                        targetValue: 5_500
                    )
                ),
            ]
        ),
        PublicBetaScenarioDefinition(
            id: .highSpeedFuture,
            title: "High-Speed Future",
            summary: "Build a transformational high-speed network.",
            recommendedMode: .zen,
            objectives: [
                PublicBetaScenarioObjectiveDefinition(
                    id: "complete-two-high-speed-corridors",
                    title: "Complete two high-speed corridors",
                    goal: PublicBetaProgressGoal(
                        metric: .completedHighSpeedCorridors,
                        targetValue: 2
                    )
                ),
                PublicBetaScenarioObjectiveDefinition(
                    id: "reach-45-prestige",
                    title: "Reach 45 prestige",
                    goal: PublicBetaProgressGoal(metric: .prestigeScore, targetValue: 45)
                ),
                PublicBetaScenarioObjectiveDefinition(
                    id: "carry-20k-passengers",
                    title: "Carry 20,000 passengers per day",
                    goal: PublicBetaProgressGoal(metric: .passengersPerDay, targetValue: 20_000)
                ),
            ]
        ),
    ])
}

// MARK: - Bounded daily statistics

nonisolated struct PublicBetaDailyNetworkRecord: Codable, Equatable, Sendable {
    let operatingDay: UInt64
    let facts: PublicBetaNetworkFacts
    let operatingResultPence: Int64
    let totalNetworkPopulation: Int64
    let latestPopulationChange: Int64

    init(
        operatingDay: UInt64,
        facts: PublicBetaNetworkFacts,
        operatingResultPence: Int64,
        totalNetworkPopulation: Int64 = 0,
        latestPopulationChange: Int64 = 0
    ) {
        self.operatingDay = operatingDay
        self.facts = facts
        self.operatingResultPence = operatingResultPence
        self.totalNetworkPopulation = totalNetworkPopulation
        self.latestPopulationChange = latestPopulationChange
    }
}

nonisolated struct PublicBetaNetworkHistoryStatistics: Equatable, Sendable {
    let recordedDayCount: Int
    let firstOperatingDay: UInt64?
    let lastOperatingDay: UInt64?
    let totalRecordedPassengers: Int64
    let averagePassengersPerDay: Int64
    let peakPassengersPerDay: Int64
    let averageHappinessBasisPoints: Int
    let cumulativeOperatingResultPence: Int64
    let profitableDayCount: Int
    let latestOperatingResultPence: Int64
    let passengerChangeFromPreviousDay: Int64
    let completedLineChangeFromFirstDay: Int
    let stationChangeFromFirstDay: Int
    let latestNetworkValuePence: Int64
    let latestPrestigeScore: Int

    static let empty = Self(
        recordedDayCount: 0,
        firstOperatingDay: nil,
        lastOperatingDay: nil,
        totalRecordedPassengers: 0,
        averagePassengersPerDay: 0,
        peakPassengersPerDay: 0,
        averageHappinessBasisPoints: 0,
        cumulativeOperatingResultPence: 0,
        profitableDayCount: 0,
        latestOperatingResultPence: 0,
        passengerChangeFromPreviousDay: 0,
        completedLineChangeFromFirstDay: 0,
        stationChangeFromFirstDay: 0,
        latestNetworkValuePence: 0,
        latestPrestigeScore: 0
    )
}

/// A value-type daily history. Days are unique and sorted; recording an existing day replaces it.
/// The oldest days are discarded once the configured bound is exceeded.
nonisolated struct PublicBetaDailyNetworkHistory: Codable, Equatable, Sendable {
    static let defaultMaximumRecordCount = 120
    static let absoluteMaximumRecordCount = 3_650

    private(set) var maximumRecordCount: Int
    private(set) var records: [PublicBetaDailyNetworkRecord]

    init(
        maximumRecordCount: Int = Self.defaultMaximumRecordCount,
        records: [PublicBetaDailyNetworkRecord] = []
    ) {
        self.maximumRecordCount = min(
            max(maximumRecordCount, 1),
            Self.absoluteMaximumRecordCount
        )
        self.records = []
        for record in records {
            self.record(record)
        }
    }

    var latestRecord: PublicBetaDailyNetworkRecord? { records.last }

    var statistics: PublicBetaNetworkHistoryStatistics {
        guard let first = records.first, let latest = records.last else { return .empty }

        var totalPassengers: Int64 = 0
        var totalHappinessBasisPoints: Int64 = 0
        var cumulativeOperatingResultPence: Int64 = 0
        var peakPassengersPerDay: Int64 = 0
        var profitableDayCount = 0

        for record in records {
            totalPassengers = PublicBetaProgressionArithmetic.saturatingAdd(
                totalPassengers,
                record.facts.passengersPerDay
            )
            totalHappinessBasisPoints = PublicBetaProgressionArithmetic.saturatingAdd(
                totalHappinessBasisPoints,
                Int64(record.facts.globalHappinessBasisPoints)
            )
            cumulativeOperatingResultPence = PublicBetaProgressionArithmetic.saturatingAddSigned(
                cumulativeOperatingResultPence,
                record.operatingResultPence
            )
            peakPassengersPerDay = max(
                peakPassengersPerDay,
                record.facts.passengersPerDay
            )
            if record.operatingResultPence > 0 {
                profitableDayCount += 1
            }
        }

        let previous = records.count > 1 ? records[records.index(before: records.endIndex - 1)] : nil
        return PublicBetaNetworkHistoryStatistics(
            recordedDayCount: records.count,
            firstOperatingDay: first.operatingDay,
            lastOperatingDay: latest.operatingDay,
            totalRecordedPassengers: totalPassengers,
            averagePassengersPerDay: totalPassengers / Int64(records.count),
            peakPassengersPerDay: peakPassengersPerDay,
            averageHappinessBasisPoints: Int(
                totalHappinessBasisPoints / Int64(records.count)
            ),
            cumulativeOperatingResultPence: cumulativeOperatingResultPence,
            profitableDayCount: profitableDayCount,
            latestOperatingResultPence: latest.operatingResultPence,
            passengerChangeFromPreviousDay: previous.map {
                latest.facts.passengersPerDay - $0.facts.passengersPerDay
            } ?? 0,
            completedLineChangeFromFirstDay: latest.facts.completedLineCount
                - first.facts.completedLineCount,
            stationChangeFromFirstDay: latest.facts.stationCount - first.facts.stationCount,
            latestNetworkValuePence: latest.facts.networkValuePence,
            latestPrestigeScore: latest.facts.prestigeScore
        )
    }

    mutating func record(_ newRecord: PublicBetaDailyNetworkRecord) {
        if let existingIndex = records.firstIndex(where: {
            $0.operatingDay == newRecord.operatingDay
        }) {
            records[existingIndex] = newRecord
        } else {
            records.append(newRecord)
        }
        records.sort { $0.operatingDay < $1.operatingDay }
        if records.count > maximumRecordCount {
            records.removeFirst(records.count - maximumRecordCount)
        }
    }

    func recording(_ newRecord: PublicBetaDailyNetworkRecord) -> Self {
        var copy = self
        copy.record(newRecord)
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case maximumRecordCount
        case records
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            maximumRecordCount: try container.decodeIfPresent(
                Int.self,
                forKey: .maximumRecordCount
            ) ?? Self.defaultMaximumRecordCount,
            records: try container.decodeIfPresent(
                [PublicBetaDailyNetworkRecord].self,
                forKey: .records
            ) ?? []
        )
    }
}

private nonisolated enum PublicBetaProgressionArithmetic {
    static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let result = max(lhs, 0).addingReportingOverflow(max(rhs, 0))
        return result.overflow ? .max : result.partialValue
    }

    static func saturatingAddSigned(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let result = lhs.addingReportingOverflow(rhs)
        guard result.overflow else { return result.partialValue }
        return rhs >= 0 ? .max : .min
    }
}
