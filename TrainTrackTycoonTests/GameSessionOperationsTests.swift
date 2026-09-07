import CoreLocation
import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Game session operations", .serialized)
@MainActor
struct GameSessionOperationsTests {
    @Test("Bounded map train snapshots retain established presentation facts")
    func mapTrainPresentationSnapshotParity() async throws {
        let session = try await makeBuiltSession(routeLength: 1_000)
        let line = try #require(session.lines.first)
        let requestedIDs = Set(line.trains.map(\.id))

        let snapshots = session.trainPresentationSnapshots(for: requestedIDs)

        #expect(snapshots.count == line.trains.count)
        #expect(Set(snapshots.map(\.id)) == requestedIDs)
        for snapshot in snapshots {
            #expect(snapshot.lineName == line.name)
            #expect(snapshot.lineStyleIndex == line.styleIndex)
            #expect(snapshot.railwayClass == line.railwayClass)
            #expect(snapshot.seatsPerTrain == line.formation.seatsPerTrain)
            #expect(snapshot.serviceRole == session.trainServiceRole(for: snapshot.id))
            #expect(snapshot.formation == session.trainFormationSnapshot(for: snapshot.id))
            #expect(snapshot.isOvertaking == session.isTrainOvertaking(snapshot.id))
        }
    }

    @Test("A newly opened line starts as a balanced service on single track")
    func defaultOperationsState() async throws {
        let session = try await makeBuiltSession(routeLength: 1_000)
        let line = try #require(session.lines.first)
        let operations = try #require(session.operationsSnapshot(forLineID: line.id))

        #expect(line.servicePattern == .balanced)
        #expect(line.trackCapacity == .singleTrack)
        #expect(operations.servicePattern == .balanced)
        #expect(operations.trackCapacity == .singleTrack)
        #expect(operations.localTrainCount == 1)
        #expect(operations.expressTrainCount == 1)
        #expect(operations.hasMixedServices)
        #expect(session.trainServiceRole(for: line.trains[0].id) == .local)
        #expect(session.trainServiceRole(for: line.trains[1].id) == .express)
        #expect(session.makeSaveSnapshot().lines.first?.servicePattern == .balanced)
        #expect(session.makeSaveSnapshot().lines.first?.trackCapacity == .singleTrack)
    }

    @Test("Changing a service pattern refreshes operations and advances one revision")
    func servicePatternChangeUpdatesSnapshotAndRevision() async throws {
        let session = try await makeBuiltSession(routeLength: 1_000)
        let lineID = try #require(session.lines.first?.id)
        let revisionBeforeChange = session.persistenceRevision

        session.setServicePattern(.express, forLineID: lineID)

        #expect(session.persistenceRevision == revisionBeforeChange + 1)
        #expect(session.lines.first?.servicePattern == .express)
        let express = try #require(session.operationsSnapshot(forLineID: lineID))
        #expect(express.servicePattern == .express)
        #expect(express.localTrainCount == 0)
        #expect(express.expressTrainCount == 2)
        #expect(!express.hasMixedServices)
        #expect(session.makeSaveSnapshot().lines.first?.servicePattern == .express)

        let revisionAfterChange = session.persistenceRevision
        session.setServicePattern(.express, forLineID: lineID)
        #expect(session.persistenceRevision == revisionAfterChange)

        session.setServicePattern(.local, forLineID: lineID)
        #expect(session.persistenceRevision == revisionAfterChange + 1)
        let local = try #require(session.operationsSnapshot(forLineID: lineID))
        #expect(local.servicePattern == .local)
        #expect(local.localTrainCount == 2)
        #expect(local.expressTrainCount == 0)
    }

    @Test("Career track upgrades charge each purchase and commit atomically")
    func careerTrackUpgradePurchases() async throws {
        let session = try await makeBuiltSession(routeLength: 1_000, mode: .career)
        let lineID = try #require(session.lines.first?.id)
        let ledgerBeforeUpgrades = session.financeLedger
        let revisionBeforeUpgrades = session.persistenceRevision
        let valueBeforeUpgrades = session.financeSnapshot.networkValuePence

        let passingLoopCost = try #require(session.trackUpgradeCost(forLineID: lineID))
        #expect(passingLoopCost == 800_000_000)
        #expect(session.upgradeTrackCapacity(forLineID: lineID))
        #expect(session.lines.first?.trackCapacity == .passingLoop)
        #expect(
            session.financeLedger.cashBalancePence
                == ledgerBeforeUpgrades.cashBalancePence - passingLoopCost
        )
        #expect(
            session.financeLedger.lifetimeConstructionSpendPence
                == ledgerBeforeUpgrades.lifetimeConstructionSpendPence + passingLoopCost
        )
        #expect(session.persistenceRevision == revisionBeforeUpgrades + 1)
        #expect(session.financeSnapshot.networkValuePence == valueBeforeUpgrades + passingLoopCost)

        let doubleTrackCost = try #require(session.trackUpgradeCost(forLineID: lineID))
        #expect(doubleTrackCost == 67_500_000)
        #expect(session.upgradeTrackCapacity(forLineID: lineID))
        #expect(session.lines.first?.trackCapacity == .doubleTrack)
        #expect(
            session.financeLedger.cashBalancePence
                == ledgerBeforeUpgrades.cashBalancePence - passingLoopCost - doubleTrackCost
        )
        #expect(
            session.financeLedger.lifetimeConstructionSpendPence
                == ledgerBeforeUpgrades.lifetimeConstructionSpendPence
                    + passingLoopCost + doubleTrackCost
        )
        #expect(session.persistenceRevision == revisionBeforeUpgrades + 2)
        #expect(
            session.financeSnapshot.networkValuePence
                == valueBeforeUpgrades + passingLoopCost + doubleTrackCost
        )

        let ledgerAtMaximum = session.financeLedger
        let revisionAtMaximum = session.persistenceRevision
        #expect(session.trackUpgradeCost(forLineID: lineID) == nil)
        #expect(!session.upgradeTrackCapacity(forLineID: lineID))
        #expect(session.lines.first?.trackCapacity == .doubleTrack)
        #expect(session.financeLedger == ledgerAtMaximum)
        #expect(session.persistenceRevision == revisionAtMaximum)
    }

    @Test("Zen track upgrades preserve unlimited cash while tracking both investments")
    func zenTrackUpgradePurchases() async throws {
        let session = try await makeBuiltSession(routeLength: 1_000, mode: .zen)
        let lineID = try #require(session.lines.first?.id)
        let ledgerBeforeUpgrades = session.financeLedger
        let revisionBeforeUpgrades = session.persistenceRevision
        let passingLoopCost = try #require(session.trackUpgradeCost(forLineID: lineID))

        #expect(session.upgradeTrackCapacity(forLineID: lineID))
        let doubleTrackCost = try #require(session.trackUpgradeCost(forLineID: lineID))
        #expect(session.upgradeTrackCapacity(forLineID: lineID))

        #expect(session.lines.first?.trackCapacity == .doubleTrack)
        #expect(session.financeLedger.cashBalancePence == 0)
        #expect(session.financeLedger.loans.isEmpty)
        #expect(
            session.financeLedger.lifetimeConstructionSpendPence
                == ledgerBeforeUpgrades.lifetimeConstructionSpendPence
                    + passingLoopCost + doubleTrackCost
        )
        #expect(session.persistenceRevision == revisionBeforeUpgrades + 2)
    }

    @Test("An unaffordable Career upgrade is a line, treasury and revision no-op")
    func unaffordableTrackUpgradeIsAtomic() async throws {
        let session = try await makeBuiltSession(
            routeLength: 1_000,
            mode: .career,
            capitalConfiguration: capitalConfiguration(startingCashPence: 1_400_000_000)
        )
        let lineID = try #require(session.lines.first?.id)
        #expect(session.financeLedger.cashBalancePence == 50_000_000)

        let lineBeforeFailure = try #require(session.makeSaveSnapshot().lines.first)
        let operationsBeforeFailure = try #require(
            session.operationsSnapshot(forLineID: lineID)
        )
        let financeBeforeFailure = session.financeLedger
        let economyBeforeFailure = session.economySnapshot
        let revisionBeforeFailure = session.persistenceRevision

        #expect(!session.upgradeTrackCapacity(forLineID: lineID))

        #expect(session.lines.first?.trackCapacity == .singleTrack)
        #expect(session.makeSaveSnapshot().lines.first == lineBeforeFailure)
        #expect(session.operationsSnapshot(forLineID: lineID) == operationsBeforeFailure)
        #expect(session.financeLedger == financeBeforeFailure)
        #expect(session.economySnapshot == economyBeforeFailure)
        #expect(session.persistenceRevision == revisionBeforeFailure)
        #expect(session.phase == .error)
        #expect(session.errorMessage?.contains("more funding") == true)
    }

    @Test("A passing loop stages a mixed local and express overtaking encounter")
    func stagedMixedServiceOvertaking() async throws {
        let session = try await makeBuiltSession(routeLength: 1_000)
        let lineID = try #require(session.lines.first?.id)
        #expect(!session.lines[0].trains.contains { session.isTrainOvertaking($0.id) })

        #expect(session.upgradeTrackCapacity(forLineID: lineID))

        let line = try #require(session.lines.first)
        let operations = try #require(session.operationsSnapshot(forLineID: lineID))
        #expect(line.trackCapacity == .passingLoop)
        #expect(operations.hasMixedServices)
        #expect(line.trains.count == 2)
        #expect(session.trainServiceRole(for: line.trains[0].id) == .local)
        #expect(session.trainServiceRole(for: line.trains[1].id) == .express)
        #expect(abs(line.trains[0].distanceAlongRoute - 500) < 0.000_001)
        #expect(abs(line.trains[1].distanceAlongRoute - 420) < 0.000_001)
        #expect(line.trains[0].dwellRemaining == 3)
        #expect(line.trains[1].dwellRemaining == 0)
        #expect(session.isTrainOvertaking(line.trains[1].id))
        #expect(!session.isTrainOvertaking(line.trains[0].id))
    }

    @Test("Capacity upgrades reduce congestion and improve operations and happiness reliability")
    func capacityImprovesCongestionAndReliability() async throws {
        let session = try await makeBuiltSession(routeLength: 1_000)
        let lineID = try #require(session.lines.first?.id)
        session.setServiceFrequency(.quarterHourly, forLineID: lineID)

        let single = try #require(session.operationsSnapshot(forLineID: lineID))
        let singleHappinessReliability = session.happinessSnapshot.componentScores.reliability
        #expect(single.congestionBand == .congested)

        #expect(session.upgradeTrackCapacity(forLineID: lineID))
        let passingLoop = try #require(session.operationsSnapshot(forLineID: lineID))
        let passingLoopHappinessReliability = session.happinessSnapshot.componentScores.reliability

        #expect(session.upgradeTrackCapacity(forLineID: lineID))
        let doubleTrack = try #require(session.operationsSnapshot(forLineID: lineID))
        let doubleTrackHappinessReliability = session.happinessSnapshot.componentScores.reliability

        #expect(single.congestionRatio > passingLoop.congestionRatio)
        #expect(passingLoop.congestionRatio > doubleTrack.congestionRatio)
        #expect(single.reliability < passingLoop.reliability)
        #expect(passingLoop.reliability < doubleTrack.reliability)
        #expect(singleHappinessReliability < passingLoopHappinessReliability)
        #expect(passingLoopHappinessReliability < doubleTrackHappinessReliability)
        #expect(doubleTrack.congestionBand == .flowing)
    }

    private var origin: Station {
        Station(crs: "VIC", name: "London Victoria", latitude: 51.4952, longitude: -0.1441)
    }

    private var destination: Station {
        Station(crs: "BTN", name: "Brighton", latitude: 50.829, longitude: -0.141)
    }

    private func makeBuiltSession(
        routeLength: CLLocationDistance,
        mode: GameMode = .zen,
        capitalConfiguration: CapitalEconomyConfiguration = .poc
    ) async throws -> GameSession {
        let session = GameSession(
            stations: [origin, destination],
            routingProvider: OperationsFixedRoutingProvider(
                route: makeRoute(length: routeLength)
            ),
            capitalEconomy: CapitalEconomy(configuration: capitalConfiguration),
            gameMode: mode,
            clock: OperationsManualClock(),
            configuration: GameConfiguration(
                maximumLineCount: 2,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 10,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000
            )
        )

        session.startBuilding()
        session.selectStation(origin)
        session.selectStation(destination)
        await session.waitForRouteCalculation()
        #expect(session.phase == .preview)
        // Keep operations affordability fixtures on the historical six-car cost baseline.
        session.setPreviewFormation(.legacyBaseline)
        session.confirmPreview()
        #expect(session.phase == .operating)
        _ = try #require(session.lines.first)
        return session
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

    private func capitalConfiguration(
        startingCashPence: Int64
    ) -> CapitalEconomyConfiguration {
        CapitalEconomyConfiguration(
            startingCashPence: startingCashPence,
            stationConstructionCostPence: 200_000_000,
            rollingStockUnitCostPence: 400_000_000,
            loanPrincipalPence: 4_000_000_000,
            earlyRepaymentPence: 1_000_000_000,
            loanAnnualInterestBasisPoints: 420,
            loanTermOperatingDays: 7_200,
            maximumConcurrentLoans: 3,
            insolvencyGraceOperatingDays: 7,
            lowCashThresholdPence: 1_000_000_000,
            stationValuePenceByLevel: Dictionary(
                uniqueKeysWithValues: StationLevel.allCases.map { ($0, 200_000_000) }
            )
        )
    }
}

private nonisolated struct OperationsFixedRoutingProvider: RailwayRouteProviding {
    let route: ServiceRailwayRoute

    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        route
    }
}

@MainActor
private final class OperationsManualClock: SimulationClock {
    private var tickHandler: (@MainActor (TimeInterval) -> Void)?

    func start(tick: @escaping @MainActor (TimeInterval) -> Void) {
        tickHandler = tick
    }

    func stop() {
        tickHandler = nil
    }
}
