import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Rolling-stock persistence", .serialized)
struct RollingStockPersistenceTests {
    @Test("Schema 11 round-trips purchased formations explicitly")
    func schemaElevenRoundTrip() async throws {
        let location = temporarySaveURL()
        defer { removeTestDirectory(for: location) }
        let store = GameSaveStore(fileURL: location)
        let source = snapshot(
            formation: .twelveCar,
            railwayClass: .highSpeed
        )

        try await store.save(source)
        let loaded = try #require(try await store.load())

        #expect(loaded == source)
        #expect(loaded.schemaVersion == GameSaveSnapshot.currentSchemaVersion)
        #expect(loaded.lines.first?.formation == .twelveCar)
        let root = try encodedJSONObject(at: location)
        let lines = try #require(root["lines"] as? [[String: Any]])
        #expect(lines.first?["formation"] as? Int == 12)
    }

    @Test("Schema 9 migrates to six cars without retroactive rolling-stock spend")
    func schemaNineMigration() async throws {
        let location = temporarySaveURL()
        defer { removeTestDirectory(for: location) }
        let financialState = SavedFinancialState(
            mode: .zen,
            cashBalancePence: 0,
            loans: [],
            lifetimeConstructionSpendPence: 987_654_321,
            lifetimeRollingStockSpendPence: 123_456_789,
            lifetimeLoanProceedsPence: 0,
            lifetimePrincipalRepaidPence: 0,
            lifetimeInterestPaidPence: 0,
            consecutiveNegativeCashDays: 0,
            bankruptcyOperatingDay: nil,
            trackingStartedOnOperatingDay: 0
        )
        var root = try encodedJSONObject(
            snapshot(
                formation: .twelveCar,
                railwayClass: .highSpeed,
                financialState: financialState
            )
        )
        root["schemaVersion"] = 9
        var lines = try #require(root["lines"] as? [[String: Any]])
        lines[0].removeValue(forKey: "formation")
        root["lines"] = lines
        try write(root, to: location)

        let migrated = try #require(try await GameSaveStore(fileURL: location).load())

        #expect(migrated.schemaVersion == GameSaveSnapshot.currentSchemaVersion)
        #expect(migrated.lines.first?.formation == .legacyBaseline)
        #expect(migrated.lines.first?.railwayClass == .highSpeed)
        #expect(migrated.financialState == financialState)
        #expect(migrated.financialState.lifetimeRollingStockSpendPence == 123_456_789)
    }

    @Test("Native schema 11 requires a formation field")
    func strictNativeFormationDecode() async throws {
        let location = temporarySaveURL()
        defer { removeTestDirectory(for: location) }
        var root = try encodedJSONObject(snapshot())
        var lines = try #require(root["lines"] as? [[String: Any]])
        lines[0].removeValue(forKey: "formation")
        root["lines"] = lines
        try write(root, to: location)

        await expectCorrupt(at: location)
    }

    @Test("Native schema 11 rejects odd, out-of-range and too-short high-speed formations")
    func nativeFormationValidation() async throws {
        for invalidCarriageCount in [1, 3, 14] {
            let location = temporarySaveURL()
            defer { removeTestDirectory(for: location) }
            var root = try encodedJSONObject(snapshot())
            var lines = try #require(root["lines"] as? [[String: Any]])
            lines[0]["formation"] = invalidCarriageCount
            root["lines"] = lines
            try write(root, to: location)

            await expectCorrupt(at: location)
        }

        let shortHighSpeedLocation = temporarySaveURL()
        defer { removeTestDirectory(for: shortHighSpeedLocation) }
        var shortHighSpeedRoot = try encodedJSONObject(snapshot(
            formation: .fourCar,
            railwayClass: .highSpeed
        ))
        // The model initializer can represent this deliberately malformed native document so
        // the store's class-specific validation is exercised on load.
        shortHighSpeedRoot["schemaVersion"] = 10
        try write(shortHighSpeedRoot, to: shortHighSpeedLocation)

        await expectCorrupt(at: shortHighSpeedLocation)
    }

    @Test("Every supported conventional and high-speed formation saves successfully")
    func supportedNativeFormations() async throws {
        for railwayClass in RailwayClass.allCases {
            for formation in RollingStockFormation.supported(for: railwayClass) {
                let location = temporarySaveURL()
                defer { removeTestDirectory(for: location) }
                let store = GameSaveStore(fileURL: location)
                let source = snapshot(
                    formation: formation,
                    railwayClass: SavedRailwayClass(railwayClass)
                )

                try await store.save(source)
                #expect(try await store.load() == source)
            }
        }
    }

    private func snapshot(
        formation: RollingStockFormation = .legacyBaseline,
        railwayClass: SavedRailwayClass = .conventional,
        financialState: SavedFinancialState = .zero
    ) -> GameSaveSnapshot {
        let line = SavedLineRecord(
            id: Self.lineID,
            originCRS: "VIC",
            destinationCRS: "BTN",
            styleIndex: 0,
            constructionProgress: 1,
            frequency: .hourly,
            railwayClass: railwayClass,
            formation: formation,
            servicePattern: .balanced,
            trackCapacity: railwayClass == .highSpeed ? .doubleTrack : .singleTrack,
            ownedTrainCount: 1,
            trains: [
                SavedTrainRecord(
                    id: Self.trainID,
                    normalizedRouteProgress: 0.25,
                    direction: .forward,
                    dwellRemaining: 0
                ),
            ]
        )
        return GameSaveSnapshot(
            savedAt: Self.fixedDate,
            isPlaying: false,
            simulationSpeed: .oneX,
            lines: [line],
            stationProgress: ["BTN", "VIC"].map {
                SavedStationProgressRecord(
                    stationCRS: $0,
                    level: .halt,
                    lifetimePassengerVisits: 0
                )
            },
            stationPopulations: ["BTN", "VIC"].map {
                SavedStationPopulationRecord(
                    stationCRS: $0,
                    currentPopulation: 100_000,
                    latestOperatingDayChange: 0
                )
            },
            financialState: financialState
        )
    }

    private func encodedJSONObject(
        _ snapshot: GameSaveSnapshot
    ) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try #require(
            JSONSerialization.jsonObject(with: encoder.encode(snapshot)) as? [String: Any]
        )
    }

    private func encodedJSONObject(at location: URL) throws -> [String: Any] {
        try #require(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: location)
            ) as? [String: Any]
        )
    }

    private func write(_ object: [String: Any], to location: URL) throws {
        try FileManager.default.createDirectory(
            at: location.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONSerialization.data(withJSONObject: object).write(
            to: location,
            options: .atomic
        )
    }

    private func expectCorrupt(at location: URL) async {
        do {
            _ = try await GameSaveStore(fileURL: location).load()
            Issue.record("Expected the save to be rejected as corrupt")
        } catch let error as GameSaveStoreError {
            #expect(error == .corruptSave(fileURL: location))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func temporarySaveURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TrainTrackTycoonFormationTests-\(UUID())", isDirectory: true)
            .appendingPathComponent("saved-game.json", isDirectory: false)
    }

    private func removeTestDirectory(for location: URL) {
        try? FileManager.default.removeItem(at: location.deletingLastPathComponent())
    }

    private static let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)
    private static let lineID = UUID(
        uuidString: "A1200000-0000-0000-0000-000000000001"
    )!
    private static let trainID = UUID(
        uuidString: "A1200000-0000-0000-0000-000000000002"
    )!
}
