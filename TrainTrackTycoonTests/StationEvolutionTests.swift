import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Station evolution")
struct StationEvolutionTests {
    @Test("Canonical levels expose their next tier and platform count")
    func canonicalLevels() {
        #expect(StationLevel.allCases == [
            .halt,
            .localStation,
            .townStation,
            .majorStation,
            .interchange,
            .terminus,
        ])
        #expect(StationLevel.allCases.map(\.platformCount) == [1, 2, 3, 4, 6, 8])
        #expect(StationLevel.halt.nextLevel == .localStation)
        #expect(StationLevel.interchange.nextLevel == .terminus)
        #expect(StationLevel.terminus.nextLevel == nil)

        let configuration = StationEvolutionConfiguration.poc
        #expect(configuration.lifetimePassengerVisitThreshold(toReach: .halt) == 0)
        #expect(configuration.lifetimePassengerVisitThreshold(toReach: .localStation) == 10_000)
        #expect(configuration.lifetimePassengerVisitThreshold(toReach: .townStation) == 50_000)
        #expect(configuration.lifetimePassengerVisitThreshold(toReach: .majorStation) == 200_000)
        #expect(configuration.lifetimePassengerVisitThreshold(toReach: .interchange) == 600_000)
        #expect(configuration.lifetimePassengerVisitThreshold(toReach: .terminus) == 1_500_000)
    }

    @Test("One large operating day promotes by only one level")
    func maximumOnePromotionPerDay() throws {
        let evolution = StationEvolution(configuration: compactConfiguration)
        let firstDay = evolution.applyOperatingDay(
            stationCRSs: [" vic "],
            existingProgress: [:],
            passengerSnapshot: network([
                ("VIC", 100, 2),
            ])
        )
        let firstProgress = try #require(firstDay.progressByStationCRS["VIC"])

        #expect(firstProgress.lifetimePassengerVisits == 100)
        #expect(firstProgress.level == .localStation)
        #expect(firstDay.promotedStationCRSs == ["VIC"])

        let secondDay = evolution.applyOperatingDay(
            stationCRSs: ["VIC"],
            existingProgress: firstDay.progressByStationCRS,
            passengerSnapshot: .empty
        )
        #expect(secondDay.progressByStationCRS["VIC"]?.level == .townStation)
        #expect(secondDay.progressByStationCRS["VIC"]?.lifetimePassengerVisits == 100)
    }

    @Test("Advanced levels require two connected destinations")
    func advancedLevelTopologyRequirement() throws {
        let evolution = StationEvolution(configuration: compactConfiguration)
        let major = StationProgress(level: .majorStation, lifetimePassengerVisits: 45)

        let blockedStatus = evolution.status(for: major, connectedDestinationCount: 1)
        #expect(blockedStatus.nextLevel == .interchange)
        #expect(blockedStatus.remainingPassengerVisits == 0)
        #expect(blockedStatus.progressToNextLevel == 1)
        #expect(!blockedStatus.isEligibleForPromotion)
        #expect(blockedStatus.eligibilityExplanation.contains("1 more direct destinations"))

        let blockedDay = evolution.applyOperatingDay(
            stationCRSs: ["VIC"],
            existingProgress: ["VIC": major],
            passengerSnapshot: network([
                ("VIC", 0, 1),
            ])
        )
        #expect(blockedDay.progressByStationCRS["VIC"]?.level == .majorStation)
        #expect(blockedDay.promotedStationCRSs.isEmpty)

        let eligibleDay = evolution.applyOperatingDay(
            stationCRSs: ["VIC"],
            existingProgress: blockedDay.progressByStationCRS,
            passengerSnapshot: network([
                ("VIC", 0, 2),
            ])
        )
        #expect(eligibleDay.progressByStationCRS["VIC"]?.level == .interchange)
        #expect(eligibleDay.promotedStationCRSs == ["VIC"])

        let terminusBlocked = evolution.status(
            for: StationProgress(level: .interchange, lifetimePassengerVisits: 45),
            connectedDestinationCount: 1
        )
        #expect(!terminusBlocked.isEligibleForPromotion)
    }

    @Test("Status derives progress and remaining visits within the current level")
    func derivedStatus() {
        let evolution = StationEvolution(configuration: compactConfiguration)
        let status = evolution.status(
            for: StationProgress(level: .localStation, lifetimePassengerVisits: 15),
            connectedDestinationCount: 1
        )

        #expect(status.level == .localStation)
        #expect(status.platformCount == 2)
        #expect(status.nextLevel == .townStation)
        #expect(status.remainingPassengerVisits == 5)
        #expect(abs(status.progressToNextLevel - 0.5) < 0.000_001)
        #expect(!status.isEligibleForPromotion)
        #expect(status.eligibilityExplanation.contains("5 more lifetime passenger visits"))

        let maximum = evolution.status(
            for: StationProgress(level: .terminus, lifetimePassengerVisits: 100),
            connectedDestinationCount: 2
        )
        #expect(maximum.nextLevel == nil)
        #expect(maximum.remainingPassengerVisits == 0)
        #expect(maximum.progressToNextLevel == 1)
        #expect(maximum.platformCount == 8)
        #expect(!maximum.isEligibleForPromotion)
    }

    @Test("Passenger visits saturate instead of overflowing")
    func saturatingLifetimeVisits() throws {
        let evolution = StationEvolution(configuration: compactConfiguration)
        let result = evolution.applyOperatingDay(
            stationCRSs: ["VIC"],
            existingProgress: [
                "VIC": StationProgress(
                    level: .terminus,
                    lifetimePassengerVisits: Int64.max - 3
                ),
            ],
            passengerSnapshot: network([
                ("VIC", 10, 2),
            ])
        )

        let progress = try #require(result.progressByStationCRS["VIC"])
        #expect(progress.lifetimePassengerVisits == Int64.max)
        #expect(progress.level == .terminus)
        #expect(result.promotedStationCRSs.isEmpty)
    }

    @Test("Reconciliation normalizes, merges, adds, and removes station keys")
    func reconcileStationSet() {
        let evolution = StationEvolution(configuration: compactConfiguration)
        let reconciled = evolution.reconcile(
            stationCRSs: [" vic ", "BTN", "vic", "   "],
            existingProgress: [
                "VIC": StationProgress(level: .halt, lifetimePassengerVisits: 100),
                " vic ": StationProgress(level: .townStation, lifetimePassengerVisits: 50),
                "ZZZ": StationProgress(level: .terminus, lifetimePassengerVisits: 1_000),
            ]
        )

        #expect(Set(reconciled.keys) == ["BTN", "VIC"])
        #expect(reconciled["BTN"] == StationProgress())
        #expect(reconciled["VIC"]?.level == .townStation)
        #expect(reconciled["VIC"]?.lifetimePassengerVisits == 100)
    }

    @Test("Daily aggregation is normalized, deterministic, and never downgrades")
    func deterministicDailyAggregation() throws {
        let evolution = StationEvolution(
            configuration: StationEvolutionConfiguration(
                localStationThreshold: 100,
                townStationThreshold: 200,
                majorStationThreshold: 300,
                interchangeThreshold: 400,
                terminusThreshold: 500
            )
        )
        let existing = [
            "VIC": StationProgress(level: .townStation, lifetimePassengerVisits: 10),
        ]
        let firstNetwork = network([
            (" vic ", 7, 1),
            ("VIC", 5, 1),
        ])
        let secondNetwork = network([
            ("VIC", 5, 1),
            (" vic ", 7, 1),
        ])

        let first = evolution.applyOperatingDay(
            stationCRSs: ["VIC"],
            existingProgress: existing,
            passengerSnapshot: firstNetwork
        )
        let second = evolution.applyOperatingDay(
            stationCRSs: ["VIC"],
            existingProgress: existing,
            passengerSnapshot: secondNetwork
        )

        #expect(first == second)
        let progress = try #require(first.progressByStationCRS["VIC"])
        #expect(progress.lifetimePassengerVisits == 22)
        #expect(progress.level == .townStation)
    }

    private var compactConfiguration: StationEvolutionConfiguration {
        StationEvolutionConfiguration(
            localStationThreshold: 10,
            townStationThreshold: 20,
            majorStationThreshold: 30,
            interchangeThreshold: 40,
            terminusThreshold: 50
        )
    }

    private func network(
        _ stations: [(crs: String, served: Int, destinations: Int)]
    ) -> NetworkPassengerSnapshot {
        var stationsByCRS = [String: StationPassengerSnapshot]()
        for station in stations {
            stationsByCRS[station.crs] = StationPassengerSnapshot(
                stationCRS: station.crs,
                potentialDailyJourneys: max(station.served, 0),
                servedDailyJourneys: station.served,
                unservedDailyJourneys: 0,
                connectedLineCount: station.destinations,
                connectedDestinationCount: station.destinations,
                busiestDirectDestinationCRS: nil,
                activityLevel: .quiet,
                activity: 0
            )
        }
        let served = stations.reduce(0) { partial, station in
            partial + max(station.served, 0)
        }
        return NetworkPassengerSnapshot(
            potentialDailyJourneys: served,
            passengersPerDay: served,
            unservedDailyJourneys: 0,
            averagePeakOccupancyRatio: 0,
            linesByID: [:],
            stationsByCRS: stationsByCRS
        )
    }
}
