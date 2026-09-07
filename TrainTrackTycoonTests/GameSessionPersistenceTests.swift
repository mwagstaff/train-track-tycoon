import CoreLocation
import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Game session persistence", .serialized)
@MainActor
struct GameSessionPersistenceTests {
    @Test("A snapshot restores gameplay state against fresh route geometry")
    func roundTripRestoration() async throws {
        let sourceClock = PersistenceManualClock()
        let source = makeSession(routeLength: 100, clock: sourceClock)
        await createAndConfirmLine(in: source)

        let sourceLineID = try #require(source.lines.first?.id)
        source.setServiceFrequency(.quarterHourly, forLineID: sourceLineID)

        sourceClock.advance(by: 13)
        source.setSimulationSpeed(.threeX)
        source.togglePlayPause()
        let originalLine = try #require(source.lines.first)
        let snapshot = source.makeSaveSnapshot()

        let destinationClock = PersistenceManualClock()
        let destination = makeSession(routeLength: 200, clock: destinationClock)
        try await destination.restore(from: snapshot)

        let restoredLine = try #require(destination.lines.first)
        #expect(restoredLine.id == originalLine.id)
        #expect(restoredLine.serviceFrequency == .quarterHourly)
        #expect(restoredLine.trains.count == 4)
        #expect(restoredLine.trains.map(\.id) == originalLine.trains.map(\.id))
        #expect(restoredLine.origin == origin)
        #expect(restoredLine.destination == destinationStation)
        #expect(restoredLine.distanceMetres == 200)
        #expect(restoredLine.indicativeCost == 300_000)
        #expect(restoredLine.constructionProgress == 1)
        #expect(abs(restoredLine.trains[0].distanceAlongRoute - 180) < 0.000_001)
        #expect(restoredLine.trains[0].direction == .reverse)
        #expect(restoredLine.trains[0].dwellRemaining == 0)
        #expect(abs(restoredLine.trains[1].distanceAlongRoute - 60) < 0.000_001)
        #expect(restoredLine.trains[1].direction == .reverse)
        #expect(destination.passengerSnapshot.line(for: restoredLine.id)?.passengersPerDay ?? 0 > 0)
        #expect(destination.phase == .operating)
        #expect(!destination.isPlaying)
        #expect(destination.simulationSpeed == .threeX)
        #expect(destination.persistenceRevision == 1)
    }

    @Test("Daily public-beta history restores with the saved railway")
    func publicBetaHistoryRestoration() async throws {
        let sourceClock = PersistenceManualClock()
        let source = makeSession(routeLength: 80_000, clock: sourceClock)
        await createAndConfirmLine(in: source)
        sourceClock.advance(by: 30)

        let sourceHistory = source.publicBetaHistory
        #expect(sourceHistory.records.count == 1)

        let destinationClock = PersistenceManualClock()
        let destination = makeSession(routeLength: 80_000, clock: destinationClock)
        await createAndConfirmLine(in: destination)
        #expect(destination.latestPresentationEvent != nil)
        try await destination.restore(from: source.makeSaveSnapshot())

        #expect(destination.publicBetaHistory == sourceHistory)
        #expect(destination.publicBetaHistory.latestRecord?.operatingDay == 1)
        #expect(destination.publicBetaFacts.completedLineCount == 1)
        #expect(destination.latestPresentationEvent == nil)

        destination.reset()
        #expect(destination.publicBetaHistory.records.isEmpty)
    }

    @Test("Restore clamps finite progress and honors the configured line limit")
    func clampingAndLineLimit() async throws {
        let session = GameSession(
            stations: [origin, destinationStation, alternateDestination],
            routingProvider: PersistenceFixedRoutingProvider(route: makeRoute(length: 100)),
            clock: PersistenceManualClock(),
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: 2,
                trainSpeedMetresPerSecond: 10,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000
            )
        )
        let records = [
            savedLine(
                originCRS: origin.crs,
                destinationCRS: destinationStation.crs,
                styleIndex: -4,
                constructionProgress: -2,
                normalizedRouteProgress: 3,
                dwellRemaining: -5
            ),
            savedLine(
                originCRS: destinationStation.crs,
                destinationCRS: alternateDestination.crs,
                styleIndex: .max,
                constructionProgress: 4,
                normalizedRouteProgress: -3,
                dwellRemaining: 1
            ),
            savedLine(
                originCRS: origin.crs,
                destinationCRS: alternateDestination.crs,
                styleIndex: 2,
                constructionProgress: 1,
                normalizedRouteProgress: 0.5,
                dwellRemaining: 0
            ),
        ]

        try await session.restore(
            from: GameSaveSnapshot(
                isPlaying: true,
                simulationSpeed: .oneX,
                lines: records
            )
        )

        #expect(session.lines.count == 2)
        #expect(session.lines[0].constructionProgress == 0)
        #expect(session.lines[0].trains.count == 2)
        #expect(session.lines[0].trains[0].distanceAlongRoute == 100)
        #expect(session.lines[0].trains[0].dwellRemaining == 0)
        #expect(session.lines[0].styleIndex == 0)
        #expect(session.lines[1].constructionProgress == 1)
        #expect(session.lines[1].trains.count == 2)
        #expect(session.lines[1].trains[0].distanceAlongRoute == 0)
        #expect(session.lines[1].trains[0].dwellRemaining == 1)
        #expect(session.lines[1].styleIndex == 1)
        #expect(session.phase == .constructing)
        #expect(!session.canBuildAnotherLine)
        #expect(session.makeSaveSnapshot().lines.allSatisfy { line in
            line.trains.count == line.frequency.visibleTrainCount
        })
    }

    @Test("An invalid station leaves the live session untouched")
    func invalidStationRestorationIsAtomic() async throws {
        let clock = PersistenceManualClock()
        let session = makeSession(routeLength: 100, clock: clock)
        await createAndConfirmLine(in: session)
        session.togglePlayPause()

        let originalSnapshot = session.makeSaveSnapshot()
        let originalRevision = session.persistenceRevision
        let invalidSnapshot = GameSaveSnapshot(
            isPlaying: true,
            simulationSpeed: .threeX,
            lines: [
                savedLine(
                    originCRS: origin.crs,
                    destinationCRS: destinationStation.crs
                ),
                savedLine(
                    originCRS: origin.crs,
                    destinationCRS: "ZZZ"
                ),
            ]
        )

        do {
            try await session.restore(from: invalidSnapshot)
            Issue.record("Expected invalid station restoration to fail")
        } catch let error as GameSessionRestoreError {
            #expect(error == .stationUnavailable("ZZZ"))
            #expect(error.errorDescription?.contains("ZZZ") == true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(session.makeSaveSnapshot().lines == originalSnapshot.lines)
        #expect(session.isPlaying == originalSnapshot.isPlaying)
        #expect(session.simulationSpeed == .oneX)
        #expect(session.phase == .operating)
        #expect(session.persistenceRevision == originalRevision)
    }

    @Test("Station evolution and the economy ledger survive restore without replaying notices")
    func livingNetworkRoundTrip() async throws {
        let sourceClock = PersistenceManualClock()
        let source = makeSession(routeLength: 80_000, clock: sourceClock)
        await createAndConfirmLine(in: source)
        // The default balanced single-track service now carries the operations model's
        // congestion journey-time penalty, so it reaches the first station threshold on day 3.
        sourceClock.advance(by: 95)

        #expect(source.economyLedger.completedOperatingDays == 3)
        #expect(source.economyLedger.operatingDayProgress > 0)
        #expect(source.stationProgressByCRS[origin.crs]?.level == .localStation)
        #expect(source.stationUpgradeEvent != nil)
        let snapshot = source.makeSaveSnapshot()

        let restored = makeSession(
            routeLength: 70_000,
            clock: PersistenceManualClock()
        )
        try await restored.restore(from: snapshot)

        #expect(restored.economyLedger == source.economyLedger)
        #expect(restored.stationProgressByCRS == source.stationProgressByCRS)
        #expect(restored.stationUpgradeEvent == nil)
        #expect(restored.economySnapshot.totalRevenuePencePerDay > 0)
        #expect(restored.economySnapshot.totalOperatingCostPencePerDay > 0)
        #expect(restored.lines.first?.distanceMetres == 70_000)
    }

    @Test("Partial operating-day progress requires an operating service")
    func partialDayRequiresOperatingLine() async {
        let session = makeSession(
            routeLength: 100,
            clock: PersistenceManualClock()
        )
        let snapshot = GameSaveSnapshot(
            isPlaying: true,
            simulationSpeed: .oneX,
            lines: [],
            economy: SavedEconomyLedger(
                completedOperatingDays: 0,
                operatingDayProgress: 0.5,
                lifetimeRevenuePence: 0,
                lifetimeOperatingCostPence: 0
            )
        )

        do {
            try await session.restore(from: snapshot)
            Issue.record("Expected partial day without a service to be rejected")
        } catch let error as GameSessionRestoreError {
            #expect(error == .invalidNumericValue)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(session.lines.isEmpty)
        #expect(session.economyLedger == .zero)
        #expect(session.persistenceRevision == 0)
    }

    @Test("Two simultaneous construction projects are rejected atomically")
    func concurrentConstructionRestorationIsAtomic() async {
        let session = GameSession(
            stations: [origin, destinationStation, alternateDestination],
            routingProvider: PersistenceFixedRoutingProvider(route: makeRoute(length: 100)),
            clock: PersistenceManualClock(),
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: 2,
                trainSpeedMetresPerSecond: 10,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000
            )
        )
        let snapshot = GameSaveSnapshot(
            isPlaying: false,
            simulationSpeed: .oneX,
            lines: [
                savedLine(
                    originCRS: origin.crs,
                    destinationCRS: destinationStation.crs,
                    constructionProgress: 0.25
                ),
                savedLine(
                    originCRS: destinationStation.crs,
                    destinationCRS: alternateDestination.crs,
                    constructionProgress: 0.75
                ),
            ]
        )

        do {
            try await session.restore(from: snapshot)
            Issue.record("Expected concurrent construction restoration to fail")
        } catch let error as GameSessionRestoreError {
            #expect(error == .invalidFleet)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(session.lines.isEmpty)
        #expect(session.phase == .idle)
        #expect(session.economyLedger == .zero)
        #expect(session.persistenceRevision == 0)
    }

    @Test("A near-complete restored day cannot exceed the per-tick settlement cap")
    func restoredDayProgressHonorsSettlementCap() async throws {
        let clock = PersistenceManualClock()
        let session = makeSession(routeLength: 80_000, clock: clock)
        let snapshot = GameSaveSnapshot(
            isPlaying: true,
            simulationSpeed: .oneX,
            lines: [
                savedLine(
                    originCRS: origin.crs,
                    destinationCRS: destinationStation.crs
                ),
            ],
            economy: SavedEconomyLedger(
                completedOperatingDays: 0,
                operatingDayProgress: 0.999_999_999_5,
                lifetimeRevenuePence: 0,
                lifetimeOperatingCostPence: 0
            )
        )
        try await session.restore(from: snapshot)

        clock.advance(by: .greatestFiniteMagnitude)

        #expect(session.economyLedger.completedOperatingDays == 120)
        #expect(session.economyLedger.operatingDayProgress == 0)
    }

    @Test("Durable gameplay transitions advance the persistence revision")
    func persistenceRevisionChanges() async {
        let clock = PersistenceManualClock()
        let session = GameSession(
            stations: [origin, destinationStation],
            routingProvider: PersistenceFixedRoutingProvider(route: makeRoute(length: 100)),
            clock: clock,
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: 1,
                trainSpeedMetresPerSecond: 10,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000
            )
        )

        #expect(session.persistenceRevision == 0)
        session.togglePlayPause()
        #expect(session.persistenceRevision == 1)
        session.setSimulationSpeed(.oneX)
        #expect(session.persistenceRevision == 1)
        session.toggleSimulationSpeed()
        #expect(session.persistenceRevision == 2)
        session.togglePlayPause()
        #expect(session.persistenceRevision == 3)

        await createPreview(in: session)
        session.confirmPreview()
        #expect(session.persistenceRevision == 4)

        clock.advance(by: 1)
        #expect(session.phase == .operating)
        #expect(session.persistenceRevision == 5)

        session.reset()
        #expect(session.persistenceRevision == 6)
    }

    @Test("Current-schema export and restore preserve non-default line operations")
    func operationsRoundTrip() async throws {
        let source = makeSession(
            routeLength: 1_000,
            clock: PersistenceManualClock()
        )
        await createAndConfirmLine(in: source)
        let lineID = try #require(source.lines.first?.id)

        source.setServicePattern(.express, forLineID: lineID)
        #expect(source.upgradeTrackCapacity(forLineID: lineID))
        #expect(source.upgradeTrackCapacity(forLineID: lineID))

        let snapshot = source.makeSaveSnapshot()
        let savedLine = try #require(snapshot.lines.first)
        #expect(snapshot.schemaVersion == GameSaveSnapshot.currentSchemaVersion)
        #expect(savedLine.servicePattern == .express)
        #expect(savedLine.trackCapacity == .doubleTrack)

        let restored = makeSession(
            routeLength: 2_000,
            clock: PersistenceManualClock()
        )
        try await restored.restore(from: snapshot)

        let restoredLine = try #require(restored.lines.first)
        let restoredOperations = try #require(
            restored.operationsSnapshot(forLineID: restoredLine.id)
        )
        #expect(restoredLine.id == lineID)
        #expect(restoredLine.servicePattern == .express)
        #expect(restoredLine.trackCapacity == .doubleTrack)
        #expect(restoredOperations.servicePattern == .express)
        #expect(restoredOperations.trackCapacity == .doubleTrack)
        #expect(restoredOperations.localTrainCount == 0)
        #expect(restoredOperations.expressTrainCount == 2)
        #expect(restored.makeSaveSnapshot().lines.first?.servicePattern == .express)
        #expect(restored.makeSaveSnapshot().lines.first?.trackCapacity == .doubleTrack)
    }

    private var origin: Station {
        Station(crs: "VIC", name: "London Victoria", latitude: 51.4952, longitude: -0.1441)
    }

    private var destinationStation: Station {
        Station(crs: "BTN", name: "Brighton", latitude: 50.829, longitude: -0.141)
    }

    private var alternateDestination: Station {
        Station(crs: "GTW", name: "Gatwick Airport", latitude: 51.1565, longitude: -0.161)
    }

    private func makeSession(
        routeLength: CLLocationDistance,
        clock: PersistenceManualClock
    ) -> GameSession {
        GameSession(
            stations: [origin, destinationStation],
            routingProvider: PersistenceFixedRoutingProvider(
                route: makeRoute(length: routeLength)
            ),
            clock: clock,
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 10,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000
            )
        )
    }

    private func makeRoute(length: CLLocationDistance) -> ServiceRailwayRoute {
        ServiceRailwayRoute(
            coordinates: [
                CLLocationCoordinate2D(latitude: 51, longitude: -0.1),
                CLLocationCoordinate2D(latitude: 51, longitude: 0.1),
            ],
            cumulativeDistances: [0, length],
            stationCoordinateIndices: [0, 1]
        )
    }

    private func savedLine(
        originCRS: String,
        destinationCRS: String,
        styleIndex: Int = 0,
        constructionProgress: Double = 1,
        normalizedRouteProgress: Double = 0.5,
        direction: SavedTrainDirection = .forward,
        dwellRemaining: TimeInterval = 0
    ) -> SavedLineRecord {
        SavedLineRecord(
            id: UUID(),
            originCRS: originCRS,
            destinationCRS: destinationCRS,
            styleIndex: styleIndex,
            constructionProgress: constructionProgress,
            train: SavedTrainRecord(
                id: UUID(),
                normalizedRouteProgress: normalizedRouteProgress,
                direction: direction,
                dwellRemaining: dwellRemaining
            )
        )
    }

    private func createPreview(in session: GameSession) async {
        session.startBuilding()
        session.selectStation(origin)
        session.selectStation(destinationStation)
        await session.waitForRouteCalculation()
        #expect(session.phase == .preview)
    }

    private func createAndConfirmLine(in session: GameSession) async {
        await createPreview(in: session)
        session.confirmPreview()
        #expect(session.phase == .operating)
    }
}

private nonisolated struct PersistenceFixedRoutingProvider: RailwayRouteProviding {
    let route: ServiceRailwayRoute

    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        route
    }
}

@MainActor
private final class PersistenceManualClock: SimulationClock {
    private var tickHandler: (@MainActor (TimeInterval) -> Void)?

    func start(tick: @escaping @MainActor (TimeInterval) -> Void) {
        tickHandler = tick
    }

    func stop() {
        tickHandler = nil
    }

    func advance(by delta: TimeInterval) {
        tickHandler?(delta)
    }
}
