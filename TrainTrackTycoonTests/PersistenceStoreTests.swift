import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Game save store", .serialized)
struct PersistenceStoreTests {
    @Test("Schema 11 round-trips formation, population, history, and all prior state")
    func schemaElevenRoundTrip() async throws {
        let location = temporarySaveURL()
        defer { removeTestDirectory(for: location) }
        let store = GameSaveStore(fileURL: location)
        let stations = [
            SavedStationProgressRecord(
                stationCRS: "BTN",
                level: .interchange,
                lifetimePassengerVisits: 12_345
            ),
            SavedStationProgressRecord(
                stationCRS: "VIC",
                level: .terminus,
                lifetimePassengerVisits: 0
            ),
        ]
        let economy = SavedEconomyLedger(
            completedOperatingDays: 42,
            operatingDayProgress: 0.625,
            lifetimeRevenuePence: 987_654,
            lifetimeOperatingCostPence: 456_789
        )
        let stationPopulations = [
            SavedStationPopulationRecord(
                stationCRS: "BTN",
                currentPopulation: 123_456,
                latestOperatingDayChange: 345
            ),
            SavedStationPopulationRecord(
                stationCRS: "VIC",
                currentPopulation: 8_750_000,
                latestOperatingDayChange: 1_250
            ),
        ]
        let loan = SavedLoanAccount(
            id: Self.firstLoanID,
            originalPrincipalPence: 4_000_000_000,
            outstandingPrincipalPence: 3_000_000_000,
            annualInterestBasisPoints: 800,
            termOperatingDays: 1_000,
            remainingOperatingDays: 750,
            originatedOnOperatingDay: 10
        )
        let financialState = SavedFinancialState(
            mode: .career,
            cashBalancePence: 7_500_000_000,
            loans: [loan],
            lifetimeConstructionSpendPence: 2_000_000_000,
            lifetimeRollingStockSpendPence: 1_200_000_000,
            lifetimeLoanProceedsPence: 4_000_000_000,
            lifetimePrincipalRepaidPence: 1_000_000_000,
            lifetimeInterestPaidPence: 125_000_000,
            consecutiveNegativeCashDays: 0,
            bankruptcyOperatingDay: nil,
            trackingStartedOnOperatingDay: 10
        )
        let snapshot = makeSnapshot(
            frequency: .quarterHourly,
            servicePattern: .express,
            trackCapacity: .doubleTrack,
            railwayClass: .highSpeed,
            trains: (0..<GameSaveSnapshot.maximumTrainsPerLine).map { makeTrain(index: $0) },
            stationProgress: stations,
            stationPopulations: stationPopulations,
            economy: economy,
            financialState: financialState,
            publicBetaHistory: PublicBetaDailyNetworkHistory(records: [
                PublicBetaDailyNetworkRecord(
                    operatingDay: 42,
                    facts: PublicBetaNetworkFacts(
                        completedLineCount: 1,
                        stationCount: 2,
                        passengersPerDay: 12_345,
                        globalHappinessBasisPoints: 6_750,
                        completedHighSpeedCorridorCount: 1,
                        prestigeScore: 25,
                        networkValuePence: 4_200_000_000
                    ),
                    operatingResultPence: 531_000,
                    totalNetworkPopulation: 8_873_456,
                    latestPopulationChange: 1_595
                ),
            ])
        )

        try await store.save(snapshot)
        let loaded = try await store.load()

        #expect(loaded == snapshot)
        #expect(loaded?.schemaVersion == GameSaveSnapshot.currentSchemaVersion)
        #expect(loaded?.stationProgress == stations)
        #expect(loaded?.stationPopulations == stationPopulations)
        #expect(loaded?.economy == economy)
        #expect(loaded?.financialState == financialState)
        #expect(loaded?.financialState.financeLedger.trackingStartedOnOperatingDay == 10)
        #expect(loaded?.lines[0].trains.count == 4)
        #expect(loaded?.lines[0].ownedTrainCount == 4)
        #expect(loaded?.lines[0].servicePattern == .express)
        #expect(loaded?.lines[0].trackCapacity == .doubleTrack)
        #expect(loaded?.lines[0].railwayClass == .highSpeed)
        #expect(loaded?.lines[0].formation == .legacyBaseline)
        #expect(loaded?.publicBetaHistory.records.count == 1)
        #expect(loaded?.publicBetaHistory.latestRecord?.operatingDay == 42)
        #expect(loaded?.publicBetaHistory.latestRecord?.totalNetworkPopulation == 8_873_456)
        #expect(loaded?.publicBetaHistory.latestRecord?.latestPopulationChange == 1_595)

        let root = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: location)) as? [String: Any]
        )
        #expect(root["schemaVersion"] as? Int == GameSaveSnapshot.currentSchemaVersion)
        #expect(root["stationProgress"] != nil)
        #expect(root["stationPopulations"] != nil)
        #expect(root["economy"] != nil)
        #expect(root["financialState"] != nil)
        #expect(root["publicBetaHistory"] != nil)
        let lines = try #require(root["lines"] as? [[String: Any]])
        let encodedLine = try #require(lines.first)
        #expect(encodedLine["frequency"] as? String == "quarterHourly")
        #expect(encodedLine["servicePattern"] as? String == "express")
        #expect(encodedLine["trackCapacity"] as? String == "doubleTrack")
        #expect(encodedLine["railwayClass"] as? String == "highSpeed")
        #expect(encodedLine["formation"] as? Int == 6)
        #expect(encodedLine["ownedTrainCount"] as? Int == 4)
        #expect((encodedLine["trains"] as? [[String: Any]])?.count == 4)
        #expect(encodedLine["train"] == nil)
    }

    @Test("Every station level has a stable persisted spelling")
    func stationLevelCoding() throws {
        let data = try JSONEncoder().encode(SavedStationLevel.allCases)
        let decoded = try JSONDecoder().decode([SavedStationLevel].self, from: data)

        #expect(decoded == SavedStationLevel.allCases)
        #expect(decoded.map(\.rawValue) == [
            "halt",
            "localStation",
            "townStation",
            "majorStation",
            "interchange",
            "terminus",
        ])
    }

    @Test("Line choices have stable persisted spellings and live-model conversions")
    func lineChoiceCoding() throws {
        let patterns = SavedServicePattern.allCases
        let capacities = SavedTrackCapacity.allCases
        let railwayClasses = SavedRailwayClass.allCases

        #expect(try JSONDecoder().decode(
            [SavedServicePattern].self,
            from: JSONEncoder().encode(patterns)
        ) == patterns)
        #expect(patterns.map(\.rawValue) == ["local", "balanced", "express"])
        #expect(patterns.map { SavedServicePattern(ServicePattern($0)) } == patterns)

        #expect(try JSONDecoder().decode(
            [SavedTrackCapacity].self,
            from: JSONEncoder().encode(capacities)
        ) == capacities)
        #expect(capacities.map(\.rawValue) == [
            "singleTrack",
            "passingLoop",
            "doubleTrack",
        ])
        #expect(capacities.map { SavedTrackCapacity(TrackCapacity($0)) } == capacities)

        #expect(try JSONDecoder().decode(
            [SavedRailwayClass].self,
            from: JSONEncoder().encode(railwayClasses)
        ) == railwayClasses)
        #expect(railwayClasses.map(\.rawValue) == ["conventional", "highSpeed"])
        #expect(railwayClasses.map { SavedRailwayClass(RailwayClass($0)) } == railwayClasses)
    }

    @Test("A real schema 2 document migrates its full fleet to current defaults")
    func schemaTwoMigration() async throws {
        let location = temporarySaveURL()
        defer { removeTestDirectory(for: location) }
        try write(Data(Self.legacyV2JSON.utf8), to: location)
        let store = GameSaveStore(fileURL: location)

        let migrated = try #require(try await store.load())

        #expect(migrated.schemaVersion == GameSaveSnapshot.currentSchemaVersion)
        #expect(migrated.savedAt == Self.fixedDate)
        #expect(migrated.isPlaying)
        #expect(migrated.simulationSpeed == .oneX)
        #expect(migrated.lines.count == 1)
        #expect(migrated.lines[0].frequency == .quarterHourly)
        #expect(migrated.lines[0].trains.count == 4)
        #expect(migrated.lines[0].ownedTrainCount == 4)
        #expect(migrated.lines[0].servicePattern == .balanced)
        #expect(migrated.lines[0].trackCapacity == .singleTrack)
        #expect(migrated.lines[0].railwayClass == .conventional)
        #expect(migrated.lines[0].formation == .legacyBaseline)
        #expect(migrated.lines[0].trains.map(\.id) == Self.legacyV2TrainIDs)
        #expect(migrated.stationProgress.map(\.stationCRS) == ["BTN", "VIC"])
        #expect(migrated.stationProgress.allSatisfy {
            $0.level == .halt && $0.lifetimePassengerVisits == 0
        })
        #expect(migrated.economy == .zero)
        #expect(migrated.financialState == .migratedZen(
            trackingStartedOnOperatingDay: 0,
            hasIncompleteCapitalHistory: true
        ))
        #expect(migrated.stationPopulations.isEmpty)
    }

    @Test("A real schema 1 document migrates its canonical fleet to current defaults")
    func schemaOneMigration() async throws {
        let location = temporarySaveURL()
        defer { removeTestDirectory(for: location) }
        try write(Data(Self.legacyV1JSON.utf8), to: location)
        let store = GameSaveStore(fileURL: location)

        let migrated = try #require(try await store.load())

        #expect(migrated.schemaVersion == GameSaveSnapshot.currentSchemaVersion)
        #expect(migrated.savedAt == Self.fixedDate)
        #expect(!migrated.isPlaying)
        #expect(migrated.simulationSpeed == .threeX)
        #expect(migrated.lines.count == 1)
        #expect(migrated.lines[0].frequency == .halfHourly)
        #expect(migrated.lines[0].trains.count == 1)
        #expect(migrated.lines[0].ownedTrainCount == 2)
        #expect(migrated.lines[0].servicePattern == .balanced)
        #expect(migrated.lines[0].trackCapacity == .singleTrack)
        #expect(migrated.lines[0].railwayClass == .conventional)
        #expect(migrated.lines[0].formation == .legacyBaseline)
        #expect(migrated.lines[0].train.id == Self.firstTrainID)
        #expect(migrated.lines[0].train.direction == .reverse)
        #expect(migrated.stationProgress.map(\.stationCRS) == ["BTN", "VIC"])
        #expect(migrated.stationProgress.allSatisfy {
            $0.level == .halt && $0.lifetimePassengerVisits == 0
        })
        #expect(migrated.economy == .zero)
        #expect(migrated.financialState == .migratedZen(
            trackingStartedOnOperatingDay: 0,
            hasIncompleteCapitalHistory: true
        ))
        #expect(migrated.stationPopulations.isEmpty)
    }

    @Test("A real schema 3 document preserves station and economy history")
    func schemaThreeMigration() async throws {
        let location = temporarySaveURL()
        defer { removeTestDirectory(for: location) }
        let economy = SavedEconomyLedger(
            completedOperatingDays: 42,
            operatingDayProgress: 0.625,
            lifetimeRevenuePence: 987_654,
            lifetimeOperatingCostPence: 456_789
        )
        let stations = [
            SavedStationProgressRecord(
                stationCRS: "BTN",
                level: .interchange,
                lifetimePassengerVisits: 12_345
            ),
            SavedStationProgressRecord(
                stationCRS: "VIC",
                level: .terminus,
                lifetimePassengerVisits: 67_890
            ),
        ]
        var legacyRoot = try encodedJSONObject(
            makeSnapshot(stationProgress: stations, economy: economy)
        )
        legacyRoot["schemaVersion"] = 3
        legacyRoot.removeValue(forKey: "financialState")
        var lines = try #require(legacyRoot["lines"] as? [[String: Any]])
        for index in lines.indices {
            lines[index].removeValue(forKey: "ownedTrainCount")
            lines[index].removeValue(forKey: "servicePattern")
            lines[index].removeValue(forKey: "trackCapacity")
            lines[index].removeValue(forKey: "railwayClass")
            lines[index].removeValue(forKey: "formation")
        }
        legacyRoot["lines"] = lines
        try write(try JSONSerialization.data(withJSONObject: legacyRoot), to: location)

        let migrated = try #require(try await GameSaveStore(fileURL: location).load())

        #expect(migrated.schemaVersion == GameSaveSnapshot.currentSchemaVersion)
        #expect(migrated.stationProgress == stations)
        #expect(migrated.economy == economy)
        #expect(migrated.lines[0].ownedTrainCount == migrated.lines[0].trains.count)
        #expect(migrated.lines[0].servicePattern == .balanced)
        #expect(migrated.lines[0].trackCapacity == .singleTrack)
        #expect(migrated.lines[0].railwayClass == .conventional)
        #expect(migrated.lines[0].formation == .legacyBaseline)
        #expect(migrated.financialState == .migratedZen(
            trackingStartedOnOperatingDay: economy.completedOperatingDays,
            hasIncompleteCapitalHistory: true
        ))
        #expect(migrated.stationPopulations.isEmpty)
    }

    @Test("A zero-day schema 3 network still records incomplete legacy capital history")
    func zeroDaySchemaThreeMigration() async throws {
        let location = temporarySaveURL()
        defer { removeTestDirectory(for: location) }
        var legacyRoot = try encodedJSONObject(makeSnapshot(economy: .zero))
        legacyRoot["schemaVersion"] = 3
        legacyRoot.removeValue(forKey: "financialState")
        var lines = try #require(legacyRoot["lines"] as? [[String: Any]])
        for index in lines.indices {
            lines[index].removeValue(forKey: "ownedTrainCount")
            lines[index].removeValue(forKey: "servicePattern")
            lines[index].removeValue(forKey: "trackCapacity")
            lines[index].removeValue(forKey: "railwayClass")
            lines[index].removeValue(forKey: "formation")
        }
        legacyRoot["lines"] = lines
        try write(try JSONSerialization.data(withJSONObject: legacyRoot), to: location)

        let migrated = try #require(try await GameSaveStore(fileURL: location).load())

        #expect(migrated.schemaVersion == GameSaveSnapshot.currentSchemaVersion)
        #expect(migrated.economy.completedOperatingDays == 0)
        #expect(migrated.lines[0].servicePattern == .balanced)
        #expect(migrated.lines[0].trackCapacity == .singleTrack)
        #expect(migrated.lines[0].railwayClass == .conventional)
        #expect(migrated.lines[0].formation == .legacyBaseline)
        #expect(migrated.financialState.trackingStartedOnOperatingDay == 0)
        #expect(migrated.financialState.hasIncompleteCapitalHistory)
        #expect(migrated.stationPopulations.isEmpty)
    }

    @Test("Schema 4 conservatively preserves incomplete history after later Zen spending")
    func schemaFourMigration() async throws {
        let location = temporarySaveURL()
        defer { removeTestDirectory(for: location) }
        var legacyRoot = try encodedJSONObject(makeSnapshot())
        legacyRoot["schemaVersion"] = 4
        var lines = try #require(legacyRoot["lines"] as? [[String: Any]])
        for index in lines.indices {
            lines[index].removeValue(forKey: "servicePattern")
            lines[index].removeValue(forKey: "trackCapacity")
            lines[index].removeValue(forKey: "railwayClass")
            lines[index].removeValue(forKey: "formation")
        }
        legacyRoot["lines"] = lines
        var financialState = try #require(legacyRoot["financialState"] as? [String: Any])
        financialState.removeValue(forKey: "hasIncompleteCapitalHistory")
        financialState["lifetimeConstructionSpendPence"] = 250_000_000
        financialState["lifetimeRollingStockSpendPence"] = 400_000_000
        legacyRoot["financialState"] = financialState
        try write(try JSONSerialization.data(withJSONObject: legacyRoot), to: location)

        let migrated = try #require(try await GameSaveStore(fileURL: location).load())

        #expect(migrated.schemaVersion == GameSaveSnapshot.currentSchemaVersion)
        #expect(migrated.financialState.mode == .zen)
        #expect(migrated.financialState.lifetimeConstructionSpendPence == 250_000_000)
        #expect(migrated.financialState.lifetimeRollingStockSpendPence == 400_000_000)
        #expect(migrated.financialState.hasIncompleteCapitalHistory)
        #expect(migrated.lines[0].servicePattern == .balanced)
        #expect(migrated.lines[0].trackCapacity == .singleTrack)
        #expect(migrated.lines[0].railwayClass == .conventional)
        #expect(migrated.lines[0].formation == .legacyBaseline)
        #expect(migrated.stationPopulations.isEmpty)
    }

    @Test("Schema 5 preserves every financial field and defaults line choices")
    func schemaFiveMigration() async throws {
        let location = temporarySaveURL()
        defer { removeTestDirectory(for: location) }
        let economy = SavedEconomyLedger(
            completedOperatingDays: 10,
            operatingDayProgress: 0.4,
            lifetimeRevenuePence: 900_000,
            lifetimeOperatingCostPence: 700_000
        )
        let loan = makeLoan()
        let financialState = makeFinancialState(
            cashBalancePence: 123_456_789,
            loans: [loan],
            lifetimeConstructionSpendPence: 2_300_000_000,
            lifetimeRollingStockSpendPence: 800_000_000,
            lifetimeLoanProceedsPence: 100,
            lifetimePrincipalRepaidPence: 25,
            lifetimeInterestPaidPence: 12_345,
            trackingStartedOnOperatingDay: 0
        )
        let source = makeSnapshot(
            servicePattern: .local,
            trackCapacity: .doubleTrack,
            economy: economy,
            financialState: financialState
        )
        var legacyRoot = try encodedJSONObject(source)
        legacyRoot["schemaVersion"] = 5
        var lines = try #require(legacyRoot["lines"] as? [[String: Any]])
        for index in lines.indices {
            lines[index].removeValue(forKey: "servicePattern")
            lines[index].removeValue(forKey: "trackCapacity")
            lines[index].removeValue(forKey: "railwayClass")
            lines[index].removeValue(forKey: "formation")
        }
        legacyRoot["lines"] = lines
        try write(try JSONSerialization.data(withJSONObject: legacyRoot), to: location)

        let migrated = try #require(try await GameSaveStore(fileURL: location).load())

        #expect(migrated.schemaVersion == GameSaveSnapshot.currentSchemaVersion)
        #expect(migrated.economy == economy)
        #expect(migrated.financialState == financialState)
        #expect(migrated.lines[0].frequency == source.lines[0].frequency)
        #expect(migrated.lines[0].ownedTrainCount == source.lines[0].ownedTrainCount)
        #expect(migrated.lines[0].trains == source.lines[0].trains)
        #expect(migrated.lines[0].servicePattern == .balanced)
        #expect(migrated.lines[0].trackCapacity == .singleTrack)
        #expect(migrated.lines[0].railwayClass == .conventional)
        #expect(migrated.lines[0].formation == .legacyBaseline)
        #expect(migrated.stationPopulations.isEmpty)
    }

    @Test("Schema 5 remains strict about its complete finance and fleet fields")
    func strictSchemaFiveDecode() async throws {
        let source = makeSnapshot()

        for missingKey in ["ownedTrainCount", "hasIncompleteCapitalHistory"] {
            let location = temporarySaveURL()
            defer { removeTestDirectory(for: location) }
            var legacyRoot = try encodedJSONObject(source)
            legacyRoot["schemaVersion"] = 5
            var lines = try #require(legacyRoot["lines"] as? [[String: Any]])
            for index in lines.indices {
                lines[index].removeValue(forKey: "servicePattern")
                lines[index].removeValue(forKey: "trackCapacity")
                lines[index].removeValue(forKey: "railwayClass")
            }
            if missingKey == "ownedTrainCount" {
                lines[0].removeValue(forKey: missingKey)
            } else {
                var financialState = try #require(
                    legacyRoot["financialState"] as? [String: Any]
                )
                financialState.removeValue(forKey: missingKey)
                legacyRoot["financialState"] = financialState
            }
            legacyRoot["lines"] = lines
            try write(try JSONSerialization.data(withJSONObject: legacyRoot), to: location)

            try await expectCorrupt(at: location)
        }
    }

    @Test("Schema 6 preserves every existing field and defaults railway class")
    func schemaSixMigration() async throws {
        let source = makeSnapshot(
            frequency: .quarterHourly,
            servicePattern: .local,
            trackCapacity: .passingLoop,
            railwayClass: .highSpeed,
            trains: (0..<GameSaveSnapshot.maximumTrainsPerLine).map { makeTrain(index: $0) },
            economy: SavedEconomyLedger(
                completedOperatingDays: 17,
                operatingDayProgress: 0.375,
                lifetimeRevenuePence: 9_876_543,
                lifetimeOperatingCostPence: 7_654_321
            ),
            financialState: makeFinancialState(
                cashBalancePence: 123_456_789,
                lifetimeConstructionSpendPence: 2_300_000_000,
                lifetimeRollingStockSpendPence: 800_000_000,
                trackingStartedOnOperatingDay: 5
            ),
            isPlaying: true
        )
        var legacyRoot = try encodedJSONObject(source)
        legacyRoot["schemaVersion"] = 6
        var legacyLines = try #require(legacyRoot["lines"] as? [[String: Any]])
        for index in legacyLines.indices {
            legacyLines[index].removeValue(forKey: "railwayClass")
            legacyLines[index].removeValue(forKey: "formation")
        }
        legacyRoot["lines"] = legacyLines

        let location = temporarySaveURL()
        defer { removeTestDirectory(for: location) }
        try write(try JSONSerialization.data(withJSONObject: legacyRoot), to: location)

        let migrated = try #require(try await GameSaveStore(fileURL: location).load())
        let sourceLine = try #require(source.lines.first)
        let expectedLine = SavedLineRecord(
            id: sourceLine.id,
            originCRS: sourceLine.originCRS,
            destinationCRS: sourceLine.destinationCRS,
            styleIndex: sourceLine.styleIndex,
            constructionProgress: sourceLine.constructionProgress,
            frequency: sourceLine.frequency,
            railwayClass: .conventional,
            servicePattern: sourceLine.servicePattern,
            trackCapacity: sourceLine.trackCapacity,
            ownedTrainCount: sourceLine.ownedTrainCount,
            trains: sourceLine.trains
        )
        let expected = GameSaveSnapshot(
            schemaVersion: GameSaveSnapshot.currentSchemaVersion,
            savedAt: source.savedAt,
            isPlaying: source.isPlaying,
            simulationSpeed: source.simulationSpeed,
            lines: [expectedLine],
            stationProgress: source.stationProgress,
            economy: source.economy,
            financialState: source.financialState
        )

        #expect(migrated == expected)
        #expect(migrated.lines.first?.formation == .legacyBaseline)
        #expect(migrated.stationPopulations.isEmpty)
    }

    @Test("Schema 6 remains strict about all fields it originally required")
    func strictSchemaSixDecode() async throws {
        for missingLineKey in ["servicePattern", "trackCapacity", "ownedTrainCount"] {
            let location = temporarySaveURL()
            defer { removeTestDirectory(for: location) }
            var legacyRoot = try encodedJSONObject(makeSnapshot())
            legacyRoot["schemaVersion"] = 6
            var lines = try #require(legacyRoot["lines"] as? [[String: Any]])
            lines[0].removeValue(forKey: "railwayClass")
            lines[0].removeValue(forKey: missingLineKey)
            legacyRoot["lines"] = lines
            try write(try JSONSerialization.data(withJSONObject: legacyRoot), to: location)

            try await expectCorrupt(at: location)
        }
    }

    @Test("Schema 7 preserves its full railway and starts an empty beta history")
    func schemaSevenMigration() async throws {
        let source = makeSnapshot(
            economy: SavedEconomyLedger(
                completedOperatingDays: 9,
                operatingDayProgress: 0.25,
                lifetimeRevenuePence: 900_000,
                lifetimeOperatingCostPence: 700_000
            )
        )
        var legacyRoot = try encodedJSONObject(source)
        legacyRoot["schemaVersion"] = 7
        legacyRoot.removeValue(forKey: "publicBetaHistory")
        var legacyLines = try #require(legacyRoot["lines"] as? [[String: Any]])
        for index in legacyLines.indices {
            legacyLines[index].removeValue(forKey: "formation")
        }
        legacyRoot["lines"] = legacyLines

        let location = temporarySaveURL()
        defer { removeTestDirectory(for: location) }
        try write(try JSONSerialization.data(withJSONObject: legacyRoot), to: location)

        let migrated = try #require(try await GameSaveStore(fileURL: location).load())
        #expect(migrated.schemaVersion == GameSaveSnapshot.currentSchemaVersion)
        #expect(migrated.lines == source.lines)
        #expect(migrated.lines.allSatisfy { $0.formation == .legacyBaseline })
        #expect(migrated.stationProgress == source.stationProgress)
        #expect(migrated.economy == source.economy)
        #expect(migrated.financialState == source.financialState)
        #expect(migrated.publicBetaHistory.records.isEmpty)
        #expect(migrated.stationPopulations.isEmpty)
    }

    @Test("Schema 8 preserves railway and history while population starts unreconciled")
    func schemaEightMigration() async throws {
        let history = PublicBetaDailyNetworkHistory(records: [
            PublicBetaDailyNetworkRecord(
                operatingDay: 9,
                facts: PublicBetaNetworkFacts(
                    completedLineCount: 1,
                    stationCount: 2,
                    passengersPerDay: 12_345,
                    globalHappinessBasisPoints: 6_750,
                    prestigeScore: 25,
                    networkValuePence: 4_200_000_000
                ),
                operatingResultPence: 531_000,
                totalNetworkPopulation: 999_999,
                latestPopulationChange: 999
            ),
        ])
        let source = makeSnapshot(
            servicePattern: .express,
            trackCapacity: .doubleTrack,
            railwayClass: .highSpeed,
            economy: SavedEconomyLedger(
                completedOperatingDays: 9,
                operatingDayProgress: 0.25,
                lifetimeRevenuePence: 900_000,
                lifetimeOperatingCostPence: 700_000
            ),
            publicBetaHistory: history
        )
        var legacyRoot = try encodedJSONObject(source)
        legacyRoot["schemaVersion"] = 8
        legacyRoot.removeValue(forKey: "stationPopulations")
        var legacyLines = try #require(legacyRoot["lines"] as? [[String: Any]])
        for index in legacyLines.indices {
            legacyLines[index].removeValue(forKey: "formation")
        }
        legacyRoot["lines"] = legacyLines
        var legacyHistory = try #require(legacyRoot["publicBetaHistory"] as? [String: Any])
        var legacyRecords = try #require(legacyHistory["records"] as? [[String: Any]])
        legacyRecords[0].removeValue(forKey: "totalNetworkPopulation")
        legacyRecords[0].removeValue(forKey: "latestPopulationChange")
        legacyHistory["records"] = legacyRecords
        legacyRoot["publicBetaHistory"] = legacyHistory

        let location = temporarySaveURL()
        defer { removeTestDirectory(for: location) }
        try write(try JSONSerialization.data(withJSONObject: legacyRoot), to: location)

        let migrated = try #require(try await GameSaveStore(fileURL: location).load())
        let migratedRecord = try #require(migrated.publicBetaHistory.latestRecord)
        #expect(migrated.schemaVersion == GameSaveSnapshot.currentSchemaVersion)
        #expect(migrated.lines == source.lines)
        #expect(migrated.lines.allSatisfy { $0.formation == .legacyBaseline })
        #expect(migrated.stationProgress == source.stationProgress)
        #expect(migrated.economy == source.economy)
        #expect(migrated.financialState == source.financialState)
        #expect(migrated.stationPopulations.isEmpty)
        #expect(migratedRecord.operatingDay == 9)
        #expect(migratedRecord.facts == history.latestRecord?.facts)
        #expect(migratedRecord.operatingResultPence == 531_000)
        #expect(migratedRecord.totalNetworkPopulation == 0)
        #expect(migratedRecord.latestPopulationChange == 0)
    }

    @Test("Only schema 1 migration permits an incomplete fleet")
    func legacyFleetAllowanceIsSchemaOneOnly() async throws {
        let location = temporarySaveURL()
        defer { removeTestDirectory(for: location) }
        var root = try #require(
            JSONSerialization.jsonObject(with: Data(Self.legacyV2JSON.utf8)) as? [String: Any]
        )
        var lines = try #require(root["lines"] as? [[String: Any]])
        var line = try #require(lines.first)
        let trains = try #require(line["trains"] as? [[String: Any]])
        line["trains"] = [try #require(trains.first)]
        lines[0] = line
        root["lines"] = lines
        try write(try JSONSerialization.data(withJSONObject: root), to: location)

        try await expectCorrupt(at: location)
    }

    @Test("Native schema 11 requires formation, population, history, and all prior fields")
    func strictSchemaElevenDecode() async throws {
        let validRoot = try encodedJSONObject(makeSnapshot())

        for requiredKey in [
            "stationProgress",
            "stationPopulations",
            "economy",
            "financialState",
            "publicBetaHistory",
        ] {
            let location = temporarySaveURL()
            defer { removeTestDirectory(for: location) }
            var malformedRoot = validRoot
            malformedRoot.removeValue(forKey: requiredKey)
            try write(try JSONSerialization.data(withJSONObject: malformedRoot), to: location)

            try await expectCorrupt(at: location)
        }

        let missingHistoryLocation = temporarySaveURL()
        defer { removeTestDirectory(for: missingHistoryLocation) }
        var missingHistoryRoot = validRoot
        var missingHistoryFinance = try #require(
            missingHistoryRoot["financialState"] as? [String: Any]
        )
        missingHistoryFinance.removeValue(forKey: "hasIncompleteCapitalHistory")
        missingHistoryRoot["financialState"] = missingHistoryFinance
        try write(
            try JSONSerialization.data(withJSONObject: missingHistoryRoot),
            to: missingHistoryLocation
        )
        try await expectCorrupt(at: missingHistoryLocation)

        let location = temporarySaveURL()
        defer { removeTestDirectory(for: location) }
        var malformedRoot = validRoot
        var lines = try #require(malformedRoot["lines"] as? [[String: Any]])
        var line = try #require(lines.first)
        line.removeValue(forKey: "ownedTrainCount")
        lines[0] = line
        malformedRoot["lines"] = lines
        try write(try JSONSerialization.data(withJSONObject: malformedRoot), to: location)

        try await expectCorrupt(at: location)

        for requiredLineKey in [
            "servicePattern",
            "trackCapacity",
            "railwayClass",
            "formation",
        ] {
            let operationsLocation = temporarySaveURL()
            defer { removeTestDirectory(for: operationsLocation) }
            var missingOperationsRoot = validRoot
            var operationLines = try #require(
                missingOperationsRoot["lines"] as? [[String: Any]]
            )
            operationLines[0].removeValue(forKey: requiredLineKey)
            missingOperationsRoot["lines"] = operationLines
            try write(
                try JSONSerialization.data(withJSONObject: missingOperationsRoot),
                to: operationsLocation
            )
            try await expectCorrupt(at: operationsLocation)
        }

        let historyLocation = temporarySaveURL()
        defer { removeTestDirectory(for: historyLocation) }
        let sourceWithHistory = makeSnapshot(
            economy: SavedEconomyLedger(
                completedOperatingDays: 1,
                operatingDayProgress: 0,
                lifetimeRevenuePence: 0,
                lifetimeOperatingCostPence: 0
            ),
            publicBetaHistory: PublicBetaDailyNetworkHistory(records: [
                PublicBetaDailyNetworkRecord(
                    operatingDay: 1,
                    facts: .zero,
                    operatingResultPence: 0,
                    totalNetworkPopulation: 200_000,
                    latestPopulationChange: 0
                ),
            ])
        )
        let validHistoryRoot = try encodedJSONObject(sourceWithHistory)
        for requiredHistoryKey in ["totalNetworkPopulation", "latestPopulationChange"] {
            var missingHistoryFieldRoot = validHistoryRoot
            var history = try #require(
                missingHistoryFieldRoot["publicBetaHistory"] as? [String: Any]
            )
            var records = try #require(history["records"] as? [[String: Any]])
            records[0].removeValue(forKey: requiredHistoryKey)
            history["records"] = records
            missingHistoryFieldRoot["publicBetaHistory"] = history
            try write(
                try JSONSerialization.data(withJSONObject: missingHistoryFieldRoot),
                to: historyLocation
            )
            try await expectCorrupt(at: historyLocation)
        }
    }

    @Test("Native schema 11 rejects unknown line-choice values")
    func unknownLineChoiceEnumValues() async throws {
        for (key, unknownValue) in [
            ("servicePattern", "limitedStop"),
            ("trackCapacity", "quadrupleTrack"),
            ("railwayClass", "maglev"),
        ] {
            let location = temporarySaveURL()
            defer { removeTestDirectory(for: location) }
            var root = try encodedJSONObject(makeSnapshot())
            var lines = try #require(root["lines"] as? [[String: Any]])
            lines[0][key] = unknownValue
            root["lines"] = lines
            try write(try JSONSerialization.data(withJSONObject: root), to: location)

            try await expectCorrupt(at: location)
        }
    }

    @Test("Schema 2 still requires its frequency and trains fields")
    func strictSchemaTwoDecode() async throws {
        let location = temporarySaveURL()
        defer { removeTestDirectory(for: location) }
        let malformedV2 = Self.legacyV1JSON.replacingOccurrences(
            of: #""schemaVersion": 1"#,
            with: #""schemaVersion": 2"#
        )
        try write(Data(malformedV2.utf8), to: location)

        try await expectCorrupt(at: location)
    }

    @Test("Malformed JSON reports a localized corrupt-save error")
    func malformedJSON() async throws {
        let location = temporarySaveURL()
        defer { removeTestDirectory(for: location) }
        try write(Data("{ definitely-not-json".utf8), to: location)

        let error = try await corruptError(at: location)
        #expect(error == .corruptSave(fileURL: location))
        #expect(error.localizedDescription.contains("damaged or incomplete"))
    }

    @Test("Out-of-range persisted data is corrupt")
    func outOfRangePersistedData() async throws {
        let invalidSnapshots = [
            makeSnapshot(
                trains: [
                    SavedTrainRecord(
                        id: Self.firstTrainID,
                        normalizedRouteProgress: 1.01,
                        direction: .forward,
                        dwellRemaining: 0
                    ),
                    makeTrain(index: 1),
                ]
            ),
            makeSnapshot(
                economy: SavedEconomyLedger(
                    completedOperatingDays: 1,
                    operatingDayProgress: 1,
                    lifetimeRevenuePence: 10,
                    lifetimeOperatingCostPence: 5
                )
            ),
        ]

        for snapshot in invalidSnapshots {
            let location = temporarySaveURL()
            defer { removeTestDirectory(for: location) }
            try write(try encode(snapshot), to: location)

            try await expectCorrupt(at: location)
        }
    }

    @Test("Station progress must be normalized, unique, complete, and nonnegative")
    func stationProgressValidation() async throws {
        let invalidStationCollections = [
            [makeStation("VIC")],
            [makeStation("BTN"), makeStation("VIC"), makeStation("GTW")],
            [makeStation("BTN"), makeStation(" vic ")],
            [makeStation("BTN"), makeStation("VIC"), makeStation("VIC")],
            [
                makeStation("BTN"),
                SavedStationProgressRecord(
                    stationCRS: "VIC",
                    level: .localStation,
                    lifetimePassengerVisits: -1
                ),
            ],
        ]

        for stations in invalidStationCollections {
            try await expectInvalidSave(makeSnapshot(stationProgress: stations))
        }
    }

    @Test("Station populations must be normalized, unique, complete, and sane")
    func stationPopulationValidation() async throws {
        let validBTN = makePopulation("BTN", population: 100_000, change: 25)
        let validVIC = makePopulation("VIC", population: 8_000_000, change: 250)
        let invalidPopulationCollections = [
            [validBTN],
            [validBTN, validVIC, makePopulation("GTW")],
            [validBTN, makePopulation(" vic ")],
            [validBTN, validVIC, validVIC],
            [validBTN, makePopulation("VIC", population: 0)],
            [validBTN, makePopulation("VIC", population: -1)],
            [validBTN, makePopulation("VIC", population: 100, change: -1)],
            [validBTN, makePopulation("VIC", population: 100, change: 101)],
        ]

        for stationPopulations in invalidPopulationCollections {
            try await expectInvalidSave(
                makeSnapshot(stationPopulations: stationPopulations)
            )
        }

        try await expectInvalidSave(
            makeSnapshot(
                lines: [],
                stationPopulations: [makePopulation("VIC")]
            )
        )

        let corruptLocation = temporarySaveURL()
        defer { removeTestDirectory(for: corruptLocation) }
        let corruptSnapshot = makeSnapshot(stationPopulations: [
            validBTN,
            makePopulation("VIC", population: 100, change: 101),
        ])
        try write(try encode(corruptSnapshot), to: corruptLocation)
        try await expectCorrupt(at: corruptLocation)
    }

    @Test("Economy progress and lifetime totals are validated before saving")
    func economyValidation() async throws {
        let invalidEconomies = [
            SavedEconomyLedger(
                completedOperatingDays: 0,
                operatingDayProgress: -0.01,
                lifetimeRevenuePence: 0,
                lifetimeOperatingCostPence: 0
            ),
            SavedEconomyLedger(
                completedOperatingDays: 0,
                operatingDayProgress: 1,
                lifetimeRevenuePence: 0,
                lifetimeOperatingCostPence: 0
            ),
            SavedEconomyLedger(
                completedOperatingDays: 0,
                operatingDayProgress: .infinity,
                lifetimeRevenuePence: 0,
                lifetimeOperatingCostPence: 0
            ),
            SavedEconomyLedger(
                completedOperatingDays: 0,
                operatingDayProgress: 0,
                lifetimeRevenuePence: -1,
                lifetimeOperatingCostPence: 0
            ),
            SavedEconomyLedger(
                completedOperatingDays: 0,
                operatingDayProgress: 0,
                lifetimeRevenuePence: 0,
                lifetimeOperatingCostPence: -1
            ),
        ]

        for economy in invalidEconomies {
            try await expectInvalidSave(makeSnapshot(economy: economy))
        }

        let constructingLine = makeLine(
            constructionProgress: 0.5,
            trains: [makeTrain(index: 0), makeTrain(index: 1)]
        )
        try await expectInvalidSave(
            makeSnapshot(
                lines: [constructingLine],
                economy: SavedEconomyLedger(
                    completedOperatingDays: 0,
                    operatingDayProgress: 0.25,
                    lifetimeRevenuePence: 0,
                    lifetimeOperatingCostPence: 0
                )
            )
        )
    }

    @Test("Public-beta history is bounded and cannot extend beyond the saved operating day")
    func publicBetaHistoryValidation() async throws {
        let economy = SavedEconomyLedger(
            completedOperatingDays: 2,
            operatingDayProgress: 0,
            lifetimeRevenuePence: 0,
            lifetimeOperatingCostPence: 0
        )
        let futureHistory = PublicBetaDailyNetworkHistory(records: [
            PublicBetaDailyNetworkRecord(
                operatingDay: 3,
                facts: .zero,
                operatingResultPence: 0
            ),
        ])
        try await expectInvalidSave(
            makeSnapshot(economy: economy, publicBetaHistory: futureHistory)
        )

        try await expectInvalidSave(
            makeSnapshot(
                economy: economy,
                publicBetaHistory: PublicBetaDailyNetworkHistory(maximumRecordCount: 121)
            )
        )

        for (totalPopulation, latestChange) in [
            (Int64(-1), Int64(0)),
            (Int64(100), Int64(-1)),
            (Int64(100), Int64(101)),
        ] {
            try await expectInvalidSave(
                makeSnapshot(
                    economy: economy,
                    publicBetaHistory: PublicBetaDailyNetworkHistory(records: [
                        PublicBetaDailyNetworkRecord(
                            operatingDay: 2,
                            facts: .zero,
                            operatingResultPence: 0,
                            totalNetworkPopulation: totalPopulation,
                            latestPopulationChange: latestChange
                        ),
                    ])
                )
            )
        }
    }

    @Test("Owned rolling stock must cover the active service and remain within the fleet cap")
    func ownedTrainCountValidation() async throws {
        for ownedTrainCount in [
            0,
            1,
            GameSaveSnapshot.maximumOwnedTrainCountPerService + 1,
        ] {
            try await expectInvalidSave(
                makeSnapshot(ownedTrainCount: ownedTrainCount)
            )
        }

        let surplusFleet = makeSnapshot(ownedTrainCount: 8)
        let location = temporarySaveURL()
        defer { removeTestDirectory(for: location) }
        let store = GameSaveStore(fileURL: location)
        try await store.save(surplusFleet)
        #expect(try await store.load()?.lines[0].ownedTrainCount == 8)
    }

    @Test("Financial state rejects impossible mode, balance, history and bankruptcy combinations")
    func financialStateValidation() async throws {
        let economy = SavedEconomyLedger(
            completedOperatingDays: 10,
            operatingDayProgress: 0,
            lifetimeRevenuePence: 1_000,
            lifetimeOperatingCostPence: 500
        )
        let invalidStates = [
            makeFinancialState(mode: .zen, cashBalancePence: 1),
            makeFinancialState(lifetimeConstructionSpendPence: -1),
            makeFinancialState(
                lifetimeLoanProceedsPence: 10,
                lifetimePrincipalRepaidPence: 11
            ),
            makeFinancialState(consecutiveNegativeCashDays: -1),
            makeFinancialState(trackingStartedOnOperatingDay: 11),
            makeFinancialState(
                cashBalancePence: -1,
                consecutiveNegativeCashDays: 0
            ),
            makeFinancialState(
                cashBalancePence: 1,
                consecutiveNegativeCashDays: 1
            ),
            makeFinancialState(
                cashBalancePence: -1,
                consecutiveNegativeCashDays: 3,
                bankruptcyOperatingDay: 11
            ),
        ]

        for financialState in invalidStates {
            try await expectInvalidSave(
                makeSnapshot(economy: economy, financialState: financialState)
            )
        }

        let playingBankruptState = makeFinancialState(
            cashBalancePence: -1,
            consecutiveNegativeCashDays: 3,
            bankruptcyOperatingDay: 10
        )
        try await expectInvalidSave(
            makeSnapshot(
                economy: economy,
                financialState: playingBankruptState,
                isPlaying: true
            )
        )
    }

    @Test("Active loans require unique identifiers and internally consistent terms")
    func loanValidation() async throws {
        let economy = SavedEconomyLedger(
            completedOperatingDays: 10,
            operatingDayProgress: 0,
            lifetimeRevenuePence: 0,
            lifetimeOperatingCostPence: 0
        )
        let validLoan = makeLoan()
        let invalidLoanCollections = [
            [validLoan, validLoan],
            [makeLoan(originalPrincipalPence: 0, outstandingPrincipalPence: 0)],
            [makeLoan(originalPrincipalPence: 100, outstandingPrincipalPence: 101)],
            [makeLoan(annualInterestBasisPoints: -1)],
            [makeLoan(annualInterestBasisPoints: 10_001)],
            [makeLoan(termOperatingDays: 0, remainingOperatingDays: 0)],
            [makeLoan(remainingOperatingDays: 0)],
            [makeLoan(termOperatingDays: 10, remainingOperatingDays: 11)],
            [makeLoan(originatedOnOperatingDay: 11)],
            (0...GameSaveSnapshot.maximumActiveLoanCount).map { index in
                makeLoan(
                    id: UUID(
                        uuidString: String(
                            format: "55555555-5555-5555-5555-%012d",
                            index + 1
                        )
                    )!
                )
            },
        ]

        for loans in invalidLoanCollections {
            let proceeds = loans.reduce(Int64(0)) { partialResult, loan in
                partialResult + max(loan.originalPrincipalPence, 0)
            }
            try await expectInvalidSave(
                makeSnapshot(
                    economy: economy,
                    financialState: makeFinancialState(
                        loans: loans,
                        lifetimeLoanProceedsPence: proceeds
                    )
                )
            )
        }
    }

    @Test("Active debt and repayments reconcile exactly with lifetime loan proceeds")
    func loanHistoryReconciliation() async throws {
        let economy = SavedEconomyLedger(
            completedOperatingDays: 10,
            operatingDayProgress: 0,
            lifetimeRevenuePence: 0,
            lifetimeOperatingCostPence: 0
        )
        let loan = makeLoan(
            originalPrincipalPence: 100,
            outstandingPrincipalPence: 75
        )

        try await expectInvalidSave(
            makeSnapshot(
                economy: economy,
                financialState: makeFinancialState(
                    lifetimeLoanProceedsPence: 100
                )
            )
        )
        try await expectInvalidSave(
            makeSnapshot(
                economy: economy,
                financialState: makeFinancialState(
                    loans: [loan],
                    lifetimeLoanProceedsPence: 50
                )
            )
        )
        try await expectInvalidSave(
            makeSnapshot(
                economy: economy,
                financialState: makeFinancialState(
                    loans: [makeLoan(
                        originalPrincipalPence: 1_000,
                        outstandingPrincipalPence: 50
                    )],
                    lifetimeLoanProceedsPence: 100,
                    lifetimePrincipalRepaidPence: 50
                )
            )
        )

        let location = temporarySaveURL()
        defer { removeTestDirectory(for: location) }
        let validState = makeFinancialState(
            loans: [loan],
            lifetimeLoanProceedsPence: 100,
            lifetimePrincipalRepaidPence: 25
        )
        let store = GameSaveStore(fileURL: location)
        try await store.save(makeSnapshot(economy: economy, financialState: validState))
        #expect(try await store.load()?.financialState == validState)
    }

    @Test("Train count and identifiers are validated before saving")
    func trainCollectionValidation() async throws {
        try await expectInvalidSave(makeSnapshot(trains: []))
        try await expectInvalidSave(
            makeSnapshot(
                trains: (0...GameSaveSnapshot.maximumTrainsPerLine).map { makeTrain(index: $0) }
            )
        )

        let duplicateTrainID = Self.firstTrainID
        let lines = [
            makeLine(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                originCRS: "VIC",
                destinationCRS: "GTW",
                styleIndex: 0,
                trains: [makeTrain(id: duplicateTrainID), makeTrain(index: 1)]
            ),
            makeLine(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                originCRS: "GTW",
                destinationCRS: "BTN",
                styleIndex: 1,
                trains: [makeTrain(id: duplicateTrainID), makeTrain(index: 2)]
            ),
        ]
        try await expectInvalidSave(makeSnapshot(lines: lines))
    }

    @Test("Native schemas require an exact fleet and unique station pairs")
    func strictFleetAndConnectionValidation() async throws {
        let invalidSnapshots = [
            makeSnapshot(
                frequency: .hourly,
                trains: [makeTrain(index: 0), makeTrain(index: 1)]
            ),
            makeSnapshot(
                frequency: .quarterHourly,
                trains: [makeTrain(index: 0)]
            ),
            makeSnapshot(
                lines: [
                    makeLine(
                        originCRS: " vic ",
                        destinationCRS: "BTN",
                        styleIndex: 0,
                        trains: [makeTrain(index: 0), makeTrain(index: 1)]
                    ),
                    makeLine(
                        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                        originCRS: "btn",
                        destinationCRS: "VIC",
                        styleIndex: 1,
                        trains: [makeTrain(index: 2), makeTrain(index: 3)]
                    ),
                ]
            ),
        ]

        for snapshot in invalidSnapshots {
            try await expectInvalidSave(snapshot)
        }
    }

    @Test("A save cannot contain two lines under construction")
    func concurrentConstructionValidation() async throws {
        let lines = [
            makeLine(
                originCRS: "VIC",
                destinationCRS: "GTW",
                styleIndex: 0,
                constructionProgress: 0.25,
                trains: [makeTrain(index: 0), makeTrain(index: 1)]
            ),
            makeLine(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                originCRS: "GTW",
                destinationCRS: "BTN",
                styleIndex: 1,
                constructionProgress: 0.75,
                trains: [makeTrain(index: 2), makeTrain(index: 3)]
            ),
        ]

        try await expectInvalidSave(makeSnapshot(lines: lines))
    }

    @Test("Future and invalid schema numbers are unsupported")
    func unsupportedSchemaVersions() async throws {
        for version in [0, GameSaveSnapshot.currentSchemaVersion + 1] {
            let location = temporarySaveURL()
            defer { removeTestDirectory(for: location) }
            let snapshot = makeSnapshot(schemaVersion: version)
            try write(try encode(snapshot), to: location)
            let store = GameSaveStore(fileURL: location)

            do {
                _ = try await store.load()
                Issue.record("Expected schema \(version) to be unsupported")
            } catch let error as GameSaveStoreError {
                #expect(error == .unsupportedSchemaVersion(
                    found: version,
                    supported: GameSaveSnapshot.currentSchemaVersion
                ))
            }
        }
    }

    @Test("A missing save loads as nil and can be deleted")
    func missingFile() async throws {
        let location = temporarySaveURL()
        defer { removeTestDirectory(for: location) }
        let store = GameSaveStore(fileURL: location)

        #expect(try await store.load() == nil)
        try await store.delete()
    }

    private func expectInvalidSave(_ snapshot: GameSaveSnapshot) async throws {
        let location = temporarySaveURL()
        defer { removeTestDirectory(for: location) }
        let store = GameSaveStore(fileURL: location)
        do {
            try await store.save(snapshot)
            Issue.record("Expected invalid current-schema snapshot to be rejected")
        } catch let error as GameSaveStoreError {
            guard case .invalidSnapshot = error else {
                Issue.record("Unexpected save-store error: \(error)")
                return
            }
        }
    }

    private func expectCorrupt(at location: URL) async throws {
        let error = try await corruptError(at: location)
        #expect(error == .corruptSave(fileURL: location))
    }

    private func corruptError(at location: URL) async throws -> GameSaveStoreError {
        let store = GameSaveStore(fileURL: location)
        do {
            _ = try await store.load()
            Issue.record("Expected a corrupt-save error")
            return .corruptSave(fileURL: location)
        } catch let error as GameSaveStoreError {
            return error
        }
    }

    private func temporarySaveURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TrainTrackTycoonPersistenceTests-\(UUID().uuidString)")
            .appendingPathComponent("saved-game.json")
    }

    private func write(_ data: Data, to location: URL) throws {
        try FileManager.default.createDirectory(
            at: location.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: location, options: .atomic)
    }

    private func removeTestDirectory(for location: URL) {
        try? FileManager.default.removeItem(at: location.deletingLastPathComponent())
    }

    private func encode(_ snapshot: GameSaveSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(snapshot)
    }

    private func encodedJSONObject(_ snapshot: GameSaveSnapshot) throws -> [String: Any] {
        try #require(
            JSONSerialization.jsonObject(with: encode(snapshot)) as? [String: Any]
        )
    }

    private func makeSnapshot(
        schemaVersion: Int = GameSaveSnapshot.currentSchemaVersion,
        frequency: SavedServiceFrequency = .halfHourly,
        servicePattern: SavedServicePattern = .balanced,
        trackCapacity: SavedTrackCapacity = .singleTrack,
        railwayClass: SavedRailwayClass = .conventional,
        trains: [SavedTrainRecord]? = nil,
        stationProgress: [SavedStationProgressRecord]? = nil,
        stationPopulations: [SavedStationPopulationRecord]? = nil,
        economy: SavedEconomyLedger = .zero,
        financialState: SavedFinancialState = .zero,
        publicBetaHistory: PublicBetaDailyNetworkHistory = PublicBetaDailyNetworkHistory(),
        isPlaying: Bool = false,
        ownedTrainCount: Int? = nil
    ) -> GameSaveSnapshot {
        let fleet = trains ?? (0..<frequency.visibleTrainCount).map { index in
            index == 0
                ? makeTrain(id: Self.firstTrainID)
                : makeTrain(index: index)
        }
        let lines = [
            makeLine(
                frequency: frequency,
                servicePattern: servicePattern,
                trackCapacity: trackCapacity,
                railwayClass: railwayClass,
                ownedTrainCount: ownedTrainCount,
                trains: fleet
            ),
        ]
        return makeSnapshot(
            schemaVersion: schemaVersion,
            lines: lines,
            stationProgress: stationProgress,
            stationPopulations: stationPopulations,
            economy: economy,
            financialState: financialState,
            publicBetaHistory: publicBetaHistory,
            isPlaying: isPlaying
        )
    }

    private func makeSnapshot(
        schemaVersion: Int = GameSaveSnapshot.currentSchemaVersion,
        lines: [SavedLineRecord],
        stationProgress: [SavedStationProgressRecord]? = nil,
        stationPopulations: [SavedStationPopulationRecord]? = nil,
        economy: SavedEconomyLedger = .zero,
        financialState: SavedFinancialState = .zero,
        publicBetaHistory: PublicBetaDailyNetworkHistory = PublicBetaDailyNetworkHistory(),
        isPlaying: Bool = false
    ) -> GameSaveSnapshot {
        GameSaveSnapshot(
            schemaVersion: schemaVersion,
            savedAt: Self.fixedDate,
            isPlaying: isPlaying,
            simulationSpeed: .threeX,
            lines: lines,
            stationProgress: stationProgress ?? stationRecords(for: lines),
            stationPopulations: stationPopulations ?? populationRecords(for: lines),
            economy: economy,
            financialState: financialState,
            publicBetaHistory: publicBetaHistory
        )
    }

    private func stationRecords(for lines: [SavedLineRecord]) -> [SavedStationProgressRecord] {
        Set(lines.flatMap { [$0.originCRS, $0.destinationCRS] }.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        })
        .sorted()
        .map { makeStation($0) }
    }

    private func populationRecords(
        for lines: [SavedLineRecord]
    ) -> [SavedStationPopulationRecord] {
        Set(lines.flatMap { [$0.originCRS, $0.destinationCRS] }.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        })
        .sorted()
        .map { stationCRS in
            SavedStationPopulationRecord(
                stationCRS: stationCRS,
                currentPopulation: 100_000,
                latestOperatingDayChange: 0
            )
        }
    }

    private func makeStation(_ crs: String) -> SavedStationProgressRecord {
        SavedStationProgressRecord(
            stationCRS: crs,
            level: .halt,
            lifetimePassengerVisits: 0
        )
    }

    private func makePopulation(
        _ crs: String,
        population: Int64 = 100_000,
        change: Int64 = 0
    ) -> SavedStationPopulationRecord {
        SavedStationPopulationRecord(
            stationCRS: crs,
            currentPopulation: population,
            latestOperatingDayChange: change
        )
    }

    private func makeFinancialState(
        mode: GameMode = .career,
        cashBalancePence: Int64 = 0,
        loans: [SavedLoanAccount] = [],
        lifetimeConstructionSpendPence: Int64 = 0,
        lifetimeRollingStockSpendPence: Int64 = 0,
        lifetimeLoanProceedsPence: Int64 = 0,
        lifetimePrincipalRepaidPence: Int64 = 0,
        lifetimeInterestPaidPence: Int64 = 0,
        consecutiveNegativeCashDays: Int = 0,
        bankruptcyOperatingDay: UInt64? = nil,
        trackingStartedOnOperatingDay: UInt64 = 0
    ) -> SavedFinancialState {
        SavedFinancialState(
            mode: mode,
            cashBalancePence: cashBalancePence,
            loans: loans,
            lifetimeConstructionSpendPence: lifetimeConstructionSpendPence,
            lifetimeRollingStockSpendPence: lifetimeRollingStockSpendPence,
            lifetimeLoanProceedsPence: lifetimeLoanProceedsPence,
            lifetimePrincipalRepaidPence: lifetimePrincipalRepaidPence,
            lifetimeInterestPaidPence: lifetimeInterestPaidPence,
            consecutiveNegativeCashDays: consecutiveNegativeCashDays,
            bankruptcyOperatingDay: bankruptcyOperatingDay,
            trackingStartedOnOperatingDay: trackingStartedOnOperatingDay
        )
    }

    private func makeLoan(
        id: UUID = Self.firstLoanID,
        originalPrincipalPence: Int64 = 100,
        outstandingPrincipalPence: Int64 = 75,
        annualInterestBasisPoints: Int = 800,
        termOperatingDays: Int = 10,
        remainingOperatingDays: Int = 5,
        originatedOnOperatingDay: UInt64 = 1
    ) -> SavedLoanAccount {
        SavedLoanAccount(
            id: id,
            originalPrincipalPence: originalPrincipalPence,
            outstandingPrincipalPence: outstandingPrincipalPence,
            annualInterestBasisPoints: annualInterestBasisPoints,
            termOperatingDays: termOperatingDays,
            remainingOperatingDays: remainingOperatingDays,
            originatedOnOperatingDay: originatedOnOperatingDay
        )
    }

    private func makeLine(
        id: UUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        originCRS: String = "VIC",
        destinationCRS: String = "BTN",
        styleIndex: Int = 1,
        frequency: SavedServiceFrequency = .halfHourly,
        servicePattern: SavedServicePattern = .balanced,
        trackCapacity: SavedTrackCapacity = .singleTrack,
        railwayClass: SavedRailwayClass = .conventional,
        constructionProgress: Double = 1,
        ownedTrainCount: Int? = nil,
        trains: [SavedTrainRecord]
    ) -> SavedLineRecord {
        SavedLineRecord(
            id: id,
            originCRS: originCRS,
            destinationCRS: destinationCRS,
            styleIndex: styleIndex,
            constructionProgress: constructionProgress,
            frequency: frequency,
            railwayClass: railwayClass,
            servicePattern: servicePattern,
            trackCapacity: trackCapacity,
            ownedTrainCount: ownedTrainCount,
            trains: trains
        )
    }

    private func makeTrain(index: Int) -> SavedTrainRecord {
        makeTrain(
            id: UUID(uuidString: String(format: "22222222-2222-2222-2222-%012d", index + 1))!,
            progress: Double(index) / Double(GameSaveSnapshot.maximumTrainsPerLine)
        )
    }

    private func makeTrain(
        id: UUID = Self.firstTrainID,
        progress: Double = 0.375
    ) -> SavedTrainRecord {
        SavedTrainRecord(
            id: id,
            normalizedRouteProgress: progress,
            direction: .reverse,
            dwellRemaining: 1.25
        )
    }

    private static let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)
    private static let firstTrainID = UUID(
        uuidString: "22222222-2222-2222-2222-222222222222"
    )!
    private static let firstLoanID = UUID(
        uuidString: "55555555-5555-5555-5555-555555555555"
    )!
    private static let legacyV2TrainIDs = (1...4).map { index in
        UUID(uuidString: String(format: "44444444-4444-4444-4444-%012d", index))!
    }

    private static let legacyV1JSON = #"""
    {
      "schemaVersion": 1,
      "savedAt": 1800000000000,
      "isPlaying": false,
      "simulationSpeed": "threeX",
      "lines": [
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "originCRS": "VIC",
          "destinationCRS": "BTN",
          "styleIndex": 1,
          "constructionProgress": 0.625,
          "train": {
            "id": "22222222-2222-2222-2222-222222222222",
            "normalizedRouteProgress": 0.375,
            "direction": "reverse",
            "dwellRemaining": 1.25
          }
        }
      ]
    }
    """#

    private static let legacyV2JSON = #"""
    {
      "schemaVersion": 2,
      "savedAt": 1800000000000,
      "isPlaying": true,
      "simulationSpeed": "oneX",
      "lines": [
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "originCRS": "VIC",
          "destinationCRS": "BTN",
          "styleIndex": 1,
          "constructionProgress": 0.625,
          "frequency": "quarterHourly",
          "trains": [
            {
              "id": "44444444-4444-4444-4444-000000000001",
              "normalizedRouteProgress": 0.1,
              "direction": "forward",
              "dwellRemaining": 0
            },
            {
              "id": "44444444-4444-4444-4444-000000000002",
              "normalizedRouteProgress": 0.3,
              "direction": "reverse",
              "dwellRemaining": 1
            },
            {
              "id": "44444444-4444-4444-4444-000000000003",
              "normalizedRouteProgress": 0.6,
              "direction": "forward",
              "dwellRemaining": 2
            },
            {
              "id": "44444444-4444-4444-4444-000000000004",
              "normalizedRouteProgress": 0.9,
              "direction": "reverse",
              "dwellRemaining": 3
            }
          ]
        }
      ]
    }
    """#
}
