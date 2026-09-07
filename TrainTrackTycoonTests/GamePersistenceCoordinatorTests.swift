import CoreLocation
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import TrainTrackTycoon

@Suite("Game persistence coordinator", .serialized)
@MainActor
struct GamePersistenceCoordinatorTests {
    @Test("A newer snapshot is saved after an in-flight write fails")
    func pendingSnapshotSurvivesWriteFailure() async throws {
        let store = CoordinatorSaveStore(
            blockedSaveIndices: [0],
            failingSaveIndices: [0]
        )
        let coordinator = makeCoordinator(saveStore: store)
        await coordinator.launchIfNeeded()

        let session = try #require(coordinator.session)
        session.togglePlayPause()
        coordinator.retrySave()
        await store.waitForSaveCount(1)

        session.togglePlayPause()
        coordinator.retrySave()
        await store.resumeSave(at: 0)
        await store.waitForSaveCount(2)

        let attempts = await store.savedSnapshots()
        #expect(attempts.count == 2)
        #expect(attempts[0].isPlaying == false)
        #expect(attempts[1].isPlaying == true)
        #expect(coordinator.saveErrorMessage == nil)
    }

    @Test("A migrated fleet is rewritten and keeps synthesized IDs across relaunch")
    func migrationRewriteMakesFleetIDsStable() async throws {
        let saveURL = try makeLegacySaveFile(contents: Self.legacyV1JSON)
        defer { try? FileManager.default.removeItem(at: saveURL.deletingLastPathComponent()) }
        let store = GameSaveStore(fileURL: saveURL)

        let firstLaunch = makeCoordinator(saveStore: store)
        await firstLaunch.launchIfNeeded()

        let canonicalSnapshot = try readCurrentSnapshot(from: saveURL)
        let firstFleetIDs = try #require(canonicalSnapshot.lines.first).trains.map(\.id)
        #expect(canonicalSnapshot.schemaVersion == GameSaveSnapshot.currentSchemaVersion)
        #expect(firstFleetIDs.count == SavedServiceFrequency.halfHourly.visibleTrainCount)
        #expect(firstFleetIDs.first == Self.legacyV1TrainID)
        #expect(canonicalSnapshot.lines.first?.railwayClass == .conventional)

        let secondLaunch = makeCoordinator(saveStore: store)
        await secondLaunch.launchIfNeeded()

        let relaunchedSnapshot = try readCurrentSnapshot(from: saveURL)
        let relaunchedFleetIDs = try #require(relaunchedSnapshot.lines.first).trains.map(\.id)
        #expect(relaunchedFleetIDs == firstFleetIDs)
    }

    @Test("A complete legacy fleet is also rewritten as the current schema")
    func completeLegacyFleetIsRewritten() async throws {
        let saveURL = try makeLegacySaveFile(contents: Self.legacyV2JSON)
        defer { try? FileManager.default.removeItem(at: saveURL.deletingLastPathComponent()) }
        let store = GameSaveStore(fileURL: saveURL)
        let coordinator = makeCoordinator(saveStore: store)

        await coordinator.launchIfNeeded()

        let rewritten = try readCurrentSnapshot(from: saveURL)
        #expect(rewritten.schemaVersion == GameSaveSnapshot.currentSchemaVersion)
        #expect(rewritten.lines.first?.trains.map(\.id) == Self.legacyV2TrainIDs)
        #expect(rewritten.lines.first?.railwayClass == .conventional)
    }

    @Test("An expired lifecycle task permits a later lifecycle save")
    func expirationClearsLifecycleRegistration() async throws {
        let store = CoordinatorSaveStore(blockedSaveIndices: [0])
        let backgroundTasks = CoordinatorBackgroundTaskManager()
        let coordinator = makeCoordinator(
            saveStore: store,
            backgroundTaskManager: backgroundTasks
        )
        await coordinator.launchIfNeeded()

        coordinator.scenePhaseDidChange(to: .inactive)
        await store.waitForSaveCount(1)
        #expect(backgroundTasks.beginCount == 1)

        backgroundTasks.expire(at: 0)
        coordinator.scenePhaseDidChange(to: .background)
        #expect(backgroundTasks.beginCount == 2)

        await store.resumeSave(at: 0)
        await store.waitForSaveCount(2)
        #expect((await store.savedSnapshots()).count == 2)
    }

    private var stations: [Station] {
        [
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

    private func makeCoordinator(
        saveStore: any GameSaveStoring,
        backgroundTaskManager: (any GameBackgroundTaskManaging)? = nil
    ) -> GamePersistenceCoordinator {
        let stations = stations
        let route = ServiceRailwayRoute(
            coordinates: [stations[0].coordinate, stations[1].coordinate],
            cumulativeDistances: [0, 10_000],
            stationCoordinateIndices: [0, 1]
        )

        return GamePersistenceCoordinator(
            saveStore: saveStore,
            stationLoader: { stations },
            sessionFactory: { stations in
                GameSession(
                    stations: stations,
                    routingProvider: CoordinatorRoutingProvider(route: route),
                    clock: CoordinatorIdleClock()
                )
            },
            backgroundTaskManager: backgroundTaskManager
        )
    }

    private func makeLegacySaveFile(contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrainTrackTycoonCoordinatorTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let saveURL = directory.appendingPathComponent("saved-game.json", isDirectory: false)
        try Data(contents.utf8).write(to: saveURL, options: .atomic)
        return saveURL
    }

    private func readCurrentSnapshot(from saveURL: URL) throws -> GameSaveSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(
            GameSaveSnapshot.self,
            from: Data(contentsOf: saveURL)
        )
    }

    private static let legacyV1TrainID = UUID(
        uuidString: "22222222-2222-2222-2222-222222222222"
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
          "destinationCRS": "ECR",
          "styleIndex": 0,
          "constructionProgress": 1,
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
          "destinationCRS": "ECR",
          "styleIndex": 0,
          "constructionProgress": 1,
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

private nonisolated struct CoordinatorRoutingProvider: RailwayRouteProviding {
    let route: ServiceRailwayRoute

    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        route
    }
}

@MainActor
private final class CoordinatorIdleClock: SimulationClock {
    func start(tick: @escaping @MainActor (TimeInterval) -> Void) {}
    func stop() {}
}

@MainActor
private final class CoordinatorBackgroundTaskManager: GameBackgroundTaskManaging {
    private var expirationHandlers: [@MainActor @Sendable () -> Void] = []

    var beginCount: Int { expirationHandlers.count }

    func begin(
        name: String,
        expirationHandler: @escaping @MainActor @Sendable () -> Void
    ) -> UIBackgroundTaskIdentifier {
        expirationHandlers.append(expirationHandler)
        return .invalid
    }

    func end(_ identifier: UIBackgroundTaskIdentifier) {}

    func expire(at index: Int) {
        guard expirationHandlers.indices.contains(index) else { return }
        expirationHandlers[index]()
    }
}

private nonisolated struct CoordinatorWriteError: Error, LocalizedError, Sendable {
    var errorDescription: String? { "Deliberate coordinator test write failure." }
}

private actor CoordinatorSaveStore: GameSaveStoring {
    private struct SaveCountWaiter {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var loadedSnapshot: GameSaveSnapshot?
    private var saveAttempts: [GameSaveSnapshot] = []
    private var blockedSaveIndices: Set<Int>
    private let failingSaveIndices: Set<Int>
    private var blockedSaveContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var saveCountWaiters: [SaveCountWaiter] = []

    init(
        loadedSnapshot: GameSaveSnapshot? = nil,
        blockedSaveIndices: Set<Int> = [],
        failingSaveIndices: Set<Int> = []
    ) {
        self.loadedSnapshot = loadedSnapshot
        self.blockedSaveIndices = blockedSaveIndices
        self.failingSaveIndices = failingSaveIndices
    }

    func load() async throws -> GameSaveSnapshot? {
        loadedSnapshot
    }

    func save(_ snapshot: GameSaveSnapshot) async throws {
        let saveIndex = saveAttempts.count
        saveAttempts.append(snapshot)
        resumeSatisfiedSaveCountWaiters()

        if blockedSaveIndices.remove(saveIndex) != nil {
            await withCheckedContinuation { continuation in
                blockedSaveContinuations[saveIndex] = continuation
            }
        }

        if failingSaveIndices.contains(saveIndex) {
            throw CoordinatorWriteError()
        }
        loadedSnapshot = snapshot
    }

    func delete() async throws {
        loadedSnapshot = nil
    }

    func savedSnapshots() -> [GameSaveSnapshot] {
        saveAttempts
    }

    func waitForSaveCount(_ count: Int) async {
        guard saveAttempts.count < count else { return }
        await withCheckedContinuation { continuation in
            saveCountWaiters.append(
                SaveCountWaiter(count: count, continuation: continuation)
            )
        }
    }

    func resumeSave(at index: Int) {
        blockedSaveContinuations.removeValue(forKey: index)?.resume()
    }

    private func resumeSatisfiedSaveCountWaiters() {
        var remainingWaiters: [SaveCountWaiter] = []
        for waiter in saveCountWaiters {
            if saveAttempts.count >= waiter.count {
                waiter.continuation.resume()
            } else {
                remainingWaiters.append(waiter)
            }
        }
        saveCountWaiters = remainingWaiters
    }
}
