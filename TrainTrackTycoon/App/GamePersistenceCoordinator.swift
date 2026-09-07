import Foundation
import Observation
import SwiftUI
import UIKit

/// The coordinator depends on behavior rather than the concrete actor so its
/// serialization guarantees can be exercised without touching the file system.
protocol GameSaveStoring: Sendable {
    func load() async throws -> GameSaveSnapshot?
    func save(_ snapshot: GameSaveSnapshot) async throws
    func delete() async throws
}

extension GameSaveStore: GameSaveStoring {}

@MainActor
protocol GameBackgroundTaskManaging: AnyObject {
    func begin(
        name: String,
        expirationHandler: @escaping @MainActor @Sendable () -> Void
    ) -> UIBackgroundTaskIdentifier

    func end(_ identifier: UIBackgroundTaskIdentifier)
}

@MainActor
private final class ApplicationBackgroundTaskManager: GameBackgroundTaskManaging {
    func begin(
        name: String,
        expirationHandler: @escaping @MainActor @Sendable () -> Void
    ) -> UIBackgroundTaskIdentifier {
        UIApplication.shared.beginBackgroundTask(
            withName: name
        ) {
            Task { @MainActor in
                expirationHandler()
            }
        }
    }

    func end(_ identifier: UIBackgroundTaskIdentifier) {
        UIApplication.shared.endBackgroundTask(identifier)
    }
}

/// Owns launch and persistence orchestration so the SwiftUI bootstrap view only
/// renders state and forwards lifecycle events.
@MainActor
@Observable
final class GamePersistenceCoordinator {
    private(set) var session: GameSession?
    private(set) var isLoading = false
    private(set) var launchErrorMessage: String?
    private(set) var canStartFresh = false
    private(set) var saveErrorMessage: String?

    @ObservationIgnored private let saveStore: any GameSaveStoring
    @ObservationIgnored private let stationLoader: @Sendable () async throws -> [Station]
    @ObservationIgnored private let sessionFactory: @MainActor ([Station]) -> GameSession
    @ObservationIgnored private let backgroundTaskManager: any GameBackgroundTaskManaging
    @ObservationIgnored private var loadedStations: [Station]?
    @ObservationIgnored private var persistenceMonitoringIsActive = false
    @ObservationIgnored private var lastObservedPersistenceRevision: UInt64?
    @ObservationIgnored private var currentScenePhase: ScenePhase = .inactive

    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var periodicAutosaveTask: Task<Void, Never>?
    @ObservationIgnored private var saveWorkerTask: Task<Void, Never>?
    @ObservationIgnored private var lifecycleSaveTask: Task<Void, Never>?
    @ObservationIgnored private var lifecycleSaveGeneration: UInt64 = 0
    @ObservationIgnored private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private var hasPendingSave = false

    private static let durableChangeDebounce: Duration = .milliseconds(700)
    private static let trainProgressSaveInterval: Duration = .seconds(12)

    init(
        saveStore: any GameSaveStoring = GameSaveStore(),
        stationLoader: @escaping @Sendable () async throws -> [Station] = {
            try await GamePersistenceCoordinator.loadStations()
        },
        sessionFactory: @escaping @MainActor ([Station]) -> GameSession = {
            GameSession(stations: $0, gameMode: .career)
        },
        backgroundTaskManager: (any GameBackgroundTaskManaging)? = nil
    ) {
        self.saveStore = saveStore
        self.stationLoader = stationLoader
        self.sessionFactory = sessionFactory
        self.backgroundTaskManager = backgroundTaskManager ?? ApplicationBackgroundTaskManager()
    }

    func launchIfNeeded() async {
        guard session == nil, !isLoading else { return }
        await launch()
    }

    func retryLaunch() async {
        guard !isLoading else { return }
        await launch()
    }

    func startFresh() async {
        guard !isLoading else { return }

        isLoading = true
        launchErrorMessage = nil
        canStartFresh = false
        defer { isLoading = false }

        do {
            let stations: [Station]
            if let loadedStations {
                stations = loadedStations
            } else {
                stations = try await stationLoader()
                loadedStations = stations
            }

            try await saveStore.delete()
            finishLaunch(with: sessionFactory(stations))
        } catch {
            presentLaunchFailure(
                error,
                canStartFresh: loadedStations != nil
            )
        }
    }

    func sessionPersistenceDidChange(to revision: UInt64) {
        guard persistenceMonitoringIsActive else { return }
        guard lastObservedPersistenceRevision != revision else { return }

        lastObservedPersistenceRevision = revision
        scheduleDebouncedSave()
    }

    func scenePhaseDidChange(to scenePhase: ScenePhase) {
        currentScenePhase = scenePhase
        session?.setSceneActive(scenePhase == .active)

        switch scenePhase {
        case .active:
            startPeriodicAutosaveIfNeeded()
        case .inactive, .background:
            periodicAutosaveTask?.cancel()
            periodicAutosaveTask = nil
            beginLifecycleSave()
        @unknown default:
            break
        }
    }

    func retrySave() {
        saveErrorMessage = nil
        enqueueImmediateSave()
    }

    func dismissSaveError() {
        saveErrorMessage = nil
    }

    private func launch() async {
        isLoading = true
        launchErrorMessage = nil
        canStartFresh = false
        persistenceMonitoringIsActive = false
        defer { isLoading = false }

        async let stationsTask: [Station] = stationLoader()
        async let savedGameTask: GameSaveSnapshot? = saveStore.load()

        let stations: [Station]
        do {
            stations = try await stationsTask
            loadedStations = stations
        } catch {
            loadedStations = nil
            presentLaunchFailure(error, canStartFresh: false)
            return
        }

        let savedGame: GameSaveSnapshot?
        do {
            savedGame = try await savedGameTask
        } catch {
            presentLaunchFailure(error, canStartFresh: true)
            return
        }

        guard let savedGame else {
            finishLaunch(with: sessionFactory(stations))
            return
        }

        let restoredSession = sessionFactory(stations)
        do {
            try await restoredSession.restore(from: savedGame)
        } catch {
            presentLaunchFailure(error, canStartFresh: true)
            return
        }

        // `GameSaveStore` presents every successful load as the current in-memory schema,
        // including values migrated from v1/v2. Persist the canonical restored snapshot
        // before exposing the session. This makes synthesized fleet identifiers durable
        // and prevents a second launch from performing the migration differently.
        do {
            try await saveStore.save(restoredSession.makeSaveSnapshot())
            saveErrorMessage = nil
        } catch {
            presentSaveFailure(error)
        }

        finishLaunch(with: restoredSession)
    }

    private func finishLaunch(with session: GameSession) {
        // Restoring intentionally advances the session revision. Record that
        // revision before exposing the session so it is not treated as a new
        // player-authored change and immediately written back to disk.
        lastObservedPersistenceRevision = session.persistenceRevision
        persistenceMonitoringIsActive = true

        session.setSceneActive(currentScenePhase == .active)
        self.session = session
        launchErrorMessage = nil
        canStartFresh = false

        startPeriodicAutosaveIfNeeded()
    }

    private func presentLaunchFailure(_ error: any Error, canStartFresh: Bool) {
        let description = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
        launchErrorMessage = description
        self.canStartFresh = canStartFresh
    }

    private func presentSaveFailure(_ error: any Error) {
        saveErrorMessage = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
    }

    private static func loadStations() async throws -> [Station] {
        try await Task.detached(priority: .userInitiated) {
            try StationCatalog().allStations
        }.value
    }

    private func scheduleDebouncedSave() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.durableChangeDebounce)
            } catch {
                return
            }

            guard !Task.isCancelled, let self else { return }
            self.debounceTask = nil
            self.enqueueSave()
        }
    }

    private func startPeriodicAutosaveIfNeeded() {
        guard currentScenePhase == .active,
              session != nil,
              periodicAutosaveTask == nil else { return }

        periodicAutosaveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Self.trainProgressSaveInterval)
                } catch {
                    return
                }

                guard !Task.isCancelled, let self else { return }
                self.autosaveTrainProgressIfNeeded()
            }
        }
    }

    private func autosaveTrainProgressIfNeeded() {
        guard let session,
              session.isPlaying,
              !session.trains.isEmpty else { return }
        enqueueSave()
    }

    private func enqueueImmediateSave() {
        debounceTask?.cancel()
        debounceTask = nil
        enqueueSave()
    }

    /// Gives the final file write a finite execution window if iOS suspends the app.
    /// The `.inactive` transition arrives early enough to request the assertion before
    /// the app has fully entered the background.
    private func beginLifecycleSave() {
        guard lifecycleSaveTask == nil else { return }

        lifecycleSaveGeneration &+= 1
        let generation = lifecycleSaveGeneration
        backgroundTaskIdentifier = backgroundTaskManager.begin(
            name: "Save railway"
        ) { [weak self] in
            self?.expireLifecycleSave(generation: generation)
        }

        // Register the request synchronously. A second durable change cannot be
        // missed even if the lifecycle task is expired before its body is scheduled.
        enqueueImmediateSave()
        lifecycleSaveTask = Task { [weak self] in
            guard let self else { return }
            while let saveWorkerTask = self.saveWorkerTask {
                await saveWorkerTask.value
            }
            self.finishLifecycleSave(generation: generation)
        }
    }

    private func expireLifecycleSave(generation: UInt64) {
        guard lifecycleSaveGeneration == generation else { return }

        lifecycleSaveTask?.cancel()
        lifecycleSaveTask = nil
        endBackgroundTaskIfNeeded()
    }

    private func finishLifecycleSave(generation: UInt64) {
        guard lifecycleSaveGeneration == generation else { return }

        lifecycleSaveTask = nil
        endBackgroundTaskIfNeeded()
    }

    private func endBackgroundTaskIfNeeded() {
        let identifier = backgroundTaskIdentifier
        guard identifier != .invalid else { return }

        backgroundTaskIdentifier = .invalid
        backgroundTaskManager.end(identifier)
    }

    private func enqueueSave() {
        guard session != nil, persistenceMonitoringIsActive else { return }

        hasPendingSave = true
        guard saveWorkerTask == nil else { return }

        saveWorkerTask = Task { [weak self] in
            await self?.drainPendingSaves()
        }
    }

    /// Serializes all writes. If state changes while a write is in flight, the
    /// loop follows it with one fresh snapshot instead of allowing an older
    /// write to race a newer one.
    private func drainPendingSaves() async {
        while hasPendingSave {
            hasPendingSave = false
            guard let session else { break }

            let snapshot = session.makeSaveSnapshot()
            do {
                try await saveStore.save(snapshot)
                saveErrorMessage = nil
            } catch {
                // A newer request may have arrived while this write was suspended.
                // Preserve that dirty bit so it is retried with a fresh snapshot.
                presentSaveFailure(error)
                break
            }
        }

        saveWorkerTask = nil

        // A request can arrive as the worker is completing. Ensure it cannot
        // be stranded merely because it observed the old worker task.
        if hasPendingSave {
            enqueueSave()
        }
    }
}
