import CoreLocation
import Foundation
import SwiftUI
import Testing
@testable import TrainTrackTycoon

@Suite("Persistence hardening", .serialized)
struct PersistenceHardeningTests {
    @Test("A failed atomic replacement preserves the last readable save")
    func failedAtomicReplacementPreservesLastSave() async throws {
        let location = temporarySaveURL()
        let directory = location.deletingLastPathComponent()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
            try? FileManager.default.removeItem(at: directory)
        }

        let store = GameSaveStore(fileURL: location)
        let original = makeSnapshot(isPlaying: false, speed: .oneX)
        let replacement = makeSnapshot(isPlaying: true, speed: .threeX)
        try await store.save(original)
        let originalBytes = try Data(contentsOf: location)

        // Prevent Foundation from creating the sibling temporary file used by `.atomic`.
        // This exercises a real filesystem failure after a valid slot already exists.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: directory.path
        )

        do {
            try await store.save(replacement)
            Issue.record("Expected the read-only directory to reject the replacement")
        } catch let error as GameSaveStoreError {
            guard case let .writeFailed(fileURL, _) = error else {
                Issue.record("Unexpected save-store error: \(error)")
                return
            }
            #expect(fileURL == location)
        }

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )

        #expect(try Data(contentsOf: location) == originalBytes)
        #expect(try await store.load() == original)
    }

    @Test("A rejected snapshot cannot overwrite the last readable save")
    func rejectedSnapshotPreservesLastSave() async throws {
        let location = temporarySaveURL()
        defer { removeTestDirectory(for: location) }
        let store = GameSaveStore(fileURL: location)
        let original = makeSnapshot(isPlaying: false, speed: .oneX)
        try await store.save(original)
        let originalBytes = try Data(contentsOf: location)

        let invalid = GameSaveSnapshot(
            savedAt: Self.fixedDate,
            isPlaying: true,
            simulationSpeed: .threeX,
            lines: [],
            economy: SavedEconomyLedger(
                completedOperatingDays: 0,
                operatingDayProgress: 0.5,
                lifetimeRevenuePence: 0,
                lifetimeOperatingCostPence: 0
            )
        )

        do {
            try await store.save(invalid)
            Issue.record("Expected the invalid replacement to be rejected")
        } catch let error as GameSaveStoreError {
            guard case .invalidSnapshot = error else {
                Issue.record("Unexpected save-store error: \(error)")
                return
            }
        }

        #expect(try Data(contentsOf: location) == originalBytes)
        #expect(try await store.load() == original)
    }

    @Test("Loading a corrupt slot is non-destructive and a later save recovers it")
    func corruptSlotCanBeRecoveredBySaving() async throws {
        let location = temporarySaveURL()
        defer { removeTestDirectory(for: location) }
        try FileManager.default.createDirectory(
            at: location.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let corruptBytes = Data(#"{"schemaVersion":8,"lines":["#.utf8)
        try corruptBytes.write(to: location, options: .atomic)
        let store = GameSaveStore(fileURL: location)

        do {
            _ = try await store.load()
            Issue.record("Expected a corrupt-save error")
        } catch let error as GameSaveStoreError {
            #expect(error == .corruptSave(fileURL: location))
        }
        #expect(try Data(contentsOf: location) == corruptBytes)

        let recovered = makeSnapshot(isPlaying: true, speed: .threeX)
        try await store.save(recovered)

        #expect(try await store.load() == recovered)
    }

    @Test("Unknown patch fields remain compatible with the current schema")
    func unknownPatchFieldsAreIgnored() async throws {
        let location = temporarySaveURL()
        defer { removeTestDirectory(for: location) }
        var root = try encodedJSONObject(makeSnapshot(isPlaying: true, speed: .threeX))
        root["futurePatchMetadata"] = ["build": 99, "channel": "public-beta"]
        var finance = try #require(root["financialState"] as? [String: Any])
        finance["futureAccountingField"] = 123_456
        root["financialState"] = finance
        var history = try #require(root["publicBetaHistory"] as? [String: Any])
        history["futureStatistic"] = "reserved"
        root["publicBetaHistory"] = history
        try FileManager.default.createDirectory(
            at: location.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONSerialization.data(withJSONObject: root).write(
            to: location,
            options: .atomic
        )

        let loaded = try #require(try await GameSaveStore(fileURL: location).load())

        #expect(loaded == makeSnapshot(isPlaying: true, speed: .threeX))
    }

    private func temporarySaveURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TrainTrackTycoonHardeningTests-\(UUID())", isDirectory: true)
            .appendingPathComponent("saved-game.json", isDirectory: false)
    }

    private func removeTestDirectory(for location: URL) {
        try? FileManager.default.removeItem(at: location.deletingLastPathComponent())
    }

    private func makeSnapshot(
        isPlaying: Bool,
        speed: SavedSimulationSpeed
    ) -> GameSaveSnapshot {
        GameSaveSnapshot(
            savedAt: Self.fixedDate,
            isPlaying: isPlaying,
            simulationSpeed: speed,
            lines: []
        )
    }

    private func encodedJSONObject(_ snapshot: GameSaveSnapshot) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try #require(
            JSONSerialization.jsonObject(with: encoder.encode(snapshot)) as? [String: Any]
        )
    }

    private static let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)
}

@Suite("Persistence recovery", .serialized)
@MainActor
struct PersistenceRecoveryTests {
    @Test("Start Fresh recovers from a corrupt save without reloading station data")
    func startFreshAfterCorruptSave() async throws {
        let store = CorruptThenEmptySaveStore()
        let stations = Self.stations
        let route = ServiceRailwayRoute(
            coordinates: stations.map(\.coordinate),
            cumulativeDistances: [0, 10_000],
            stationCoordinateIndices: [0, 1]
        )
        let stationLoadCounter = StationLoadCounter()
        let coordinator = GamePersistenceCoordinator(
            saveStore: store,
            stationLoader: {
                await stationLoadCounter.increment()
                return stations
            },
            sessionFactory: { stations in
                GameSession(
                    stations: stations,
                    routingProvider: PersistenceRecoveryRoutingProvider(route: route),
                    clock: PersistenceRecoveryIdleClock()
                )
            }
        )

        await coordinator.launchIfNeeded()

        #expect(coordinator.session == nil)
        #expect(coordinator.canStartFresh)
        #expect(coordinator.launchErrorMessage?.contains("damaged or incomplete") == true)
        #expect(await stationLoadCounter.value == 1)

        await coordinator.startFresh()

        #expect(coordinator.session != nil)
        #expect(coordinator.launchErrorMessage == nil)
        #expect(!coordinator.canStartFresh)
        #expect(await store.wasDeleted)
        #expect(await stationLoadCounter.value == 1)
    }

    private static let stations = [
        Station(
            crs: "VIC",
            name: "London Victoria",
            latitude: 51.4952,
            longitude: -0.1441
        ),
        Station(
            crs: "ECR",
            name: "East Croydon",
            latitude: 51.3752,
            longitude: -0.0923
        ),
    ]
}

private actor CorruptThenEmptySaveStore: GameSaveStoring {
    private(set) var wasDeleted = false

    func load() throws -> GameSaveSnapshot? {
        throw GameSaveStoreError.corruptSave(
            fileURL: URL(fileURLWithPath: "/tmp/saved-game.json")
        )
    }

    func save(_ snapshot: GameSaveSnapshot) {}

    func delete() {
        wasDeleted = true
    }
}

private actor StationLoadCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private nonisolated struct PersistenceRecoveryRoutingProvider: RailwayRouteProviding {
    let route: ServiceRailwayRoute

    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        route
    }
}

@MainActor
private final class PersistenceRecoveryIdleClock: SimulationClock {
    func start(tick: @escaping @MainActor (TimeInterval) -> Void) {}
    func stop() {}
}
