import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("M16 service-plan persistence", .serialized)
struct M16ServicePlanPersistenceTests {
    @Test("Legacy presets create four stable Local and Express timetable slots")
    func legacyPresetPlans() {
        let calls = ["PUR", "ECR", "GTW", "HOR"]

        let local = TrainServicePlan.legacyDefaults(
            servicePattern: .local,
            serviceStationCRSs: calls
        )
        #expect(local.map(\.slotIndex) == [0, 1, 2, 3])
        #expect(local.allSatisfy { $0.role == .local && $0.stationCRSs == calls })

        let express = TrainServicePlan.legacyDefaults(
            servicePattern: .express,
            serviceStationCRSs: calls
        )
        #expect(express.map(\.role) == [.express, .express, .express, .express])
        #expect(express.allSatisfy { $0.stationCRSs == ["PUR", "HOR"] })

        let balanced = TrainServicePlan.legacyDefaults(
            servicePattern: .balanced,
            serviceStationCRSs: calls
        )
        #expect(balanced.map(\.role) == [.local, .express, .local, .express])
        #expect(balanced.map(\.stationCRSs) == [
            calls,
            ["PUR", "HOR"],
            calls,
            ["PUR", "HOR"],
        ])
    }

    @Test("Schema 12 round-trips four custom plans with independent interior terminals")
    func schemaTwelveCustomPlanRoundTrip() async throws {
        let plans = [
            plan(0, .local, ["ECR", "RDC", "GTW", "HOR"]),
            plan(1, .express, ["PUR", "RDC", "HOR"]),
            plan(2, .local, ["GTW", "RDC"]),
            plan(3, .express, ["HOR", "ECR"]),
        ]
        let source = makeSnapshot(plans: plans)
        let location = temporarySaveURL()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        let store = GameSaveStore(fileURL: location)

        try await store.save(source)
        let restored = try #require(try await store.load())

        #expect(restored == source)
        #expect(restored.schemaVersion == 12)
        #expect(restored.lines[0].trainServicePlans == plans)
        #expect(restored.lines[0].trains.map(\.id) == source.lines[0].trains.map(\.id))

        let root = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: location)) as? [String: Any]
        )
        let lines = try #require(root["lines"] as? [[String: Any]])
        let encodedPlans = try #require(lines[0]["trainServicePlans"] as? [[String: Any]])
        #expect(encodedPlans.count == GameSaveSnapshot.maximumTrainsPerLine)
        #expect(encodedPlans.map { $0["slotIndex"] as? Int } == [0, 1, 2, 3])
    }

    @Test("Schema 11 materialises balanced plans without changing prior state")
    func schemaElevenMigration() async throws {
        let source = makeSnapshot()
        var root = try encodedJSONObject(source)
        root["schemaVersion"] = 11
        var lines = try #require(root["lines"] as? [[String: Any]])
        lines[0].removeValue(forKey: "trainServicePlans")
        root["lines"] = lines
        let location = temporarySaveURL()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        try write(try JSONSerialization.data(withJSONObject: root), to: location)

        let migrated = try #require(try await GameSaveStore(fileURL: location).load())

        #expect(migrated.schemaVersion == GameSaveSnapshot.currentSchemaVersion)
        #expect(migrated.savedAt == source.savedAt)
        #expect(migrated.corridors == source.corridors)
        #expect(migrated.lines[0].id == source.lines[0].id)
        #expect(migrated.lines[0].corridorIDs == source.lines[0].corridorIDs)
        #expect(migrated.lines[0].stationCRSs == source.lines[0].stationCRSs)
        #expect(migrated.lines[0].trains == source.lines[0].trains)
        #expect(migrated.economy == source.economy)
        #expect(migrated.financialState == source.financialState)
        #expect(migrated.lines[0].trainServicePlans.map(\.slotIndex) == [0, 1, 2, 3])
        #expect(migrated.lines[0].trainServicePlans.map(\.role) == [
            .local, .express, .local, .express,
        ])
        #expect(migrated.lines[0].trainServicePlans.map(\.stationCRSs) == [
            ["PUR", "ECR", "RDC", "GTW", "HOR"],
            ["PUR", "HOR"],
            ["PUR", "ECR", "RDC", "GTW", "HOR"],
            ["PUR", "HOR"],
        ])
    }

    @Test("Native schema 12 requires the complete plan collection")
    func strictNativePlanDecode() async throws {
        var root = try encodedJSONObject(makeSnapshot())
        var lines = try #require(root["lines"] as? [[String: Any]])
        lines[0].removeValue(forKey: "trainServicePlans")
        root["lines"] = lines
        let location = temporarySaveURL()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        try write(try JSONSerialization.data(withJSONObject: root), to: location)

        do {
            _ = try await GameSaveStore(fileURL: location).load()
            Issue.record("Expected a missing native plan collection to be corrupt")
        } catch let error as GameSaveStoreError {
            #expect(error == .corruptSave(fileURL: location))
        }
    }

    @Test("Plan slots, built stations, role semantics, and service order are validated")
    func invalidPlansAreRejected() async throws {
        let valid = makeSnapshot().lines[0].trainServicePlans
        let invalidCollections: [[SavedTrainServicePlan]] = [
            Array(valid.dropLast()),
            [valid[0], valid[0], valid[2], valid[3]],
            [valid[0], valid[1], valid[2], plan(4, .express, ["PUR", "HOR"])],
            replacing(valid, slot: 0, with: plan(0, .local, ["PUR"])),
            replacing(valid, slot: 0, with: plan(0, .local, ["PUR", "ECR", "ECR", "HOR"])),
            replacing(valid, slot: 0, with: plan(0, .local, ["pur", "HOR"])),
            replacing(valid, slot: 0, with: plan(0, .local, ["PUR", "ZZZ", "HOR"])),
            replacing(valid, slot: 0, with: plan(0, .local, ["PUR", "CWD", "HOR"])),
            replacing(valid, slot: 0, with: plan(0, .local, ["PUR", "RDC", "HOR"])),
            replacing(valid, slot: 0, with: plan(0, .local, ["PUR", "GTW", "ECR", "HOR"])),
        ]

        for plans in invalidCollections {
            await expectInvalidSave(makeSnapshot(plans: plans))
        }
    }

    @Test("Saved and live plan roles convert without changing stable slot data")
    func savedLiveConversion() {
        let saved = plan(2, .express, ["ECR", "RDC", "HOR"])
        let live = saved.trainServicePlan

        #expect(live.slotIndex == 2)
        #expect(live.role == .express)
        #expect(live.stationCRSs == ["ECR", "RDC", "HOR"])
        #expect(SavedTrainServicePlan(live) == saved)
    }

    private func makeSnapshot(
        plans: [SavedTrainServicePlan]? = nil
    ) -> GameSaveSnapshot {
        let firstCorridorID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAA1")!
        let secondCorridorID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAA2")!
        let serviceCalls = ["PUR", "ECR", "RDC", "GTW", "HOR"]
        let line = SavedLineRecord(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            originCRS: "PUR",
            destinationCRS: "HOR",
            styleIndex: 1,
            constructionProgress: 1,
            frequency: .halfHourly,
            formation: .eightCar,
            servicePattern: .balanced,
            trackCapacity: .doubleTrack,
            ownedTrainCount: 3,
            trains: [
                train("CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCC1", progress: 0.25),
                train("CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCC2", progress: 0.75),
            ],
            corridorIDs: [firstCorridorID, secondCorridorID],
            stationCRSs: serviceCalls,
            trainServicePlans: plans
        )
        let corridors = [
            SavedRailwayCorridorRecord(
                id: firstCorridorID,
                stationCRSs: ["PUR", "ECR", "CWD", "RDC"],
                constructionProgress: 1,
                trackCapacity: .doubleTrack
            ),
            SavedRailwayCorridorRecord(
                id: secondCorridorID,
                stationCRSs: ["RDC", "GTW", "HOR"],
                constructionProgress: 1,
                trackCapacity: .doubleTrack
            ),
        ]
        let stations = corridors.flatMap(\.stationCRSs).reduce(into: [String]()) { result, crs in
            if !result.contains(crs) { result.append(crs) }
        }
        return GameSaveSnapshot(
            savedAt: Date(timeIntervalSince1970: 1_800_000_000),
            isPlaying: false,
            simulationSpeed: .threeX,
            lines: [line],
            corridors: corridors,
            stationProgress: stations.map {
                SavedStationProgressRecord(
                    stationCRS: $0,
                    level: .halt,
                    lifetimePassengerVisits: 0
                )
            },
            stationPopulations: stations.map {
                SavedStationPopulationRecord(
                    stationCRS: $0,
                    currentPopulation: 100_000,
                    latestOperatingDayChange: 0
                )
            }
        )
    }

    private func plan(
        _ slotIndex: Int,
        _ role: SavedTrainServiceRole,
        _ stationCRSs: [String]
    ) -> SavedTrainServicePlan {
        SavedTrainServicePlan(
            slotIndex: slotIndex,
            role: role,
            stationCRSs: stationCRSs
        )
    }

    private func train(
        _ id: String,
        progress: Double
    ) -> SavedTrainRecord {
        SavedTrainRecord(
            id: UUID(uuidString: id)!,
            normalizedRouteProgress: progress,
            direction: .forward,
            dwellRemaining: 0
        )
    }

    private func replacing(
        _ plans: [SavedTrainServicePlan],
        slot: Int,
        with replacement: SavedTrainServicePlan
    ) -> [SavedTrainServicePlan] {
        plans.map { $0.slotIndex == slot ? replacement : $0 }
    }

    private func expectInvalidSave(_ snapshot: GameSaveSnapshot) async {
        let location = temporarySaveURL()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        do {
            try await GameSaveStore(fileURL: location).save(snapshot)
            Issue.record("Expected invalid service plans to be rejected")
        } catch let error as GameSaveStoreError {
            guard case .invalidSnapshot = error else {
                Issue.record("Expected invalidSnapshot, received \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func encodedJSONObject(_ snapshot: GameSaveSnapshot) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try #require(
            JSONSerialization.jsonObject(with: encoder.encode(snapshot)) as? [String: Any]
        )
    }

    private func temporarySaveURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TrainTrackTycoon-M16-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("save.json", isDirectory: false)
    }

    private func write(_ data: Data, to location: URL) throws {
        try FileManager.default.createDirectory(
            at: location.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: location, options: .atomic)
    }
}
