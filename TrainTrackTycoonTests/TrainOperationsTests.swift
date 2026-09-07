import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Train operations")
struct TrainOperationsTests {
    @Test("Local, balanced and express patterns allocate deterministic train roles")
    func deterministicRoleMix() {
        let operations = TrainOperations()

        #expect((0..<4).map {
            operations.role(forTrainAt: $0, trainCount: 4, pattern: .local)
        } == [.local, .local, .local, .local])
        #expect((0..<4).map {
            operations.role(forTrainAt: $0, trainCount: 4, pattern: .express)
        } == [.express, .express, .express, .express])
        #expect((0..<4).map {
            operations.role(forTrainAt: $0, trainCount: 4, pattern: .balanced)
        } == [.local, .express, .local, .express])

        let hourly = operations.evaluate(LineOperationsInput(
            frequency: .hourly,
            servicePattern: .balanced,
            trackCapacity: .singleTrack
        ))
        let halfHourly = operations.evaluate(LineOperationsInput(
            frequency: .halfHourly,
            servicePattern: .balanced,
            trackCapacity: .singleTrack
        ))
        let quarterHourly = operations.evaluate(LineOperationsInput(
            frequency: .quarterHourly,
            servicePattern: .balanced,
            trackCapacity: .singleTrack
        ))

        #expect(hourly.localTrainCount == 1)
        #expect(hourly.expressTrainCount == 0)
        #expect(!hourly.hasMixedServices)
        #expect(halfHourly.localTrainCount == 1)
        #expect(halfHourly.expressTrainCount == 1)
        #expect(halfHourly.hasMixedServices)
        #expect(quarterHourly.localTrainCount == 2)
        #expect(quarterHourly.expressTrainCount == 2)
        #expect(quarterHourly.hasMixedServices)
    }

    @Test("Role facts do not depend on the order in which trains are queried")
    func roleQueryOrderIsIrrelevant() {
        let operations = TrainOperations()
        let canonical = Dictionary(uniqueKeysWithValues: (0..<4).map { index in
            (
                index,
                operations.role(
                    forTrainAt: index,
                    trainCount: 4,
                    pattern: .balanced
                )
            )
        })
        let shuffled = Dictionary(uniqueKeysWithValues: [3, 1, 0, 2].map { index in
            (
                index,
                operations.role(
                    forTrainAt: index,
                    trainCount: 4,
                    pattern: .balanced
                )
            )
        })

        #expect(shuffled == canonical)
        #expect(operations.role(
            forTrainAt: 0,
            trainCount: 0,
            pattern: .balanced
        ) == .local)
    }

    @Test("Passing loops and double track progressively relieve a busy mixed service")
    func infrastructureRelievesCongestion() {
        let operations = TrainOperations()
        let single = operations.evaluate(LineOperationsInput(
            frequency: .quarterHourly,
            servicePattern: .balanced,
            trackCapacity: .singleTrack
        ))
        let loop = operations.evaluate(LineOperationsInput(
            frequency: .quarterHourly,
            servicePattern: .balanced,
            trackCapacity: .passingLoop
        ))
        let double = operations.evaluate(LineOperationsInput(
            frequency: .quarterHourly,
            servicePattern: .balanced,
            trackCapacity: .doubleTrack
        ))

        #expect(single.congestionRatio == 1)
        #expect(abs(loop.congestionRatio - 0.685) < 0.000_000_001)
        #expect(abs(double.congestionRatio - 0.291_666_666_666_666_63) < 0.000_000_001)
        #expect(single.congestionRatio > loop.congestionRatio)
        #expect(loop.congestionRatio > double.congestionRatio)
        #expect(single.congestionBand == .congested)
        #expect(loop.congestionBand == .congested)
        #expect(double.congestionBand == .flowing)

        #expect(abs(single.reliability - 0.72) < 0.000_000_001)
        #expect(abs(loop.reliability - 0.8082) < 0.000_000_001)
        #expect(abs(double.reliability - 0.918_333_333_333_333_3) < 0.000_000_001)
        #expect(single.reliability < loop.reliability)
        #expect(loop.reliability < double.reliability)

        #expect(abs(single.journeyTimeMultiplier - 1.43) < 0.000_000_001)
        #expect(abs(loop.journeyTimeMultiplier - 1.28825) < 0.000_000_001)
        #expect(abs(double.journeyTimeMultiplier - 1.11125) < 0.000_000_001)
        #expect(single.journeyTimeMultiplier > loop.journeyTimeMultiplier)
        #expect(loop.journeyTimeMultiplier > double.journeyTimeMultiplier)
    }

    @Test("Express journeys are faster while a constrained mixed service loses reliability")
    func patternJourneyAndReliability() {
        let operations = TrainOperations()
        let local = operations.evaluate(LineOperationsInput(
            frequency: .halfHourly,
            servicePattern: .local,
            trackCapacity: .singleTrack
        ))
        let balanced = operations.evaluate(LineOperationsInput(
            frequency: .halfHourly,
            servicePattern: .balanced,
            trackCapacity: .singleTrack
        ))
        let express = operations.evaluate(LineOperationsInput(
            frequency: .halfHourly,
            servicePattern: .express,
            trackCapacity: .singleTrack
        ))

        #expect(abs(local.congestionRatio - 0.525) < 0.000_000_001)
        #expect(abs(balanced.congestionRatio - 0.675) < 0.000_000_001)
        #expect(abs(express.congestionRatio - 0.525) < 0.000_000_001)
        #expect(local.congestionBand == .busy)
        #expect(balanced.congestionBand == .congested)
        #expect(express.congestionBand == .busy)

        #expect(abs(local.journeyTimeMultiplier - 1.41625) < 0.000_000_001)
        #expect(abs(balanced.journeyTimeMultiplier - 1.28375) < 0.000_000_001)
        #expect(abs(express.journeyTimeMultiplier - 1.05625) < 0.000_000_001)
        #expect(express.journeyTimeMultiplier < balanced.journeyTimeMultiplier)
        #expect(balanced.journeyTimeMultiplier < local.journeyTimeMultiplier)

        #expect(abs(local.reliability - 0.853) < 0.000_000_001)
        #expect(abs(balanced.reliability - 0.811) < 0.000_000_001)
        #expect(express.reliability == local.reliability)
        #expect(balanced.reliability < local.reliability)
    }

    @Test("Explicit train plans derive the operating mix from active roles")
    func explicitTrainPlanRolesDriveTheForecast() {
        let operations = TrainOperations()
        let allExpress = operations.evaluate(LineOperationsInput(
            frequency: .halfHourly,
            servicePattern: .balanced,
            trackCapacity: .singleTrack,
            serviceRoles: [.express, .express]
        ))
        let mixed = operations.evaluate(LineOperationsInput(
            frequency: .halfHourly,
            servicePattern: .local,
            trackCapacity: .singleTrack,
            serviceRoles: [.local, .express]
        ))

        #expect(allExpress.servicePattern == .express)
        #expect(allExpress.localTrainCount == 0)
        #expect(allExpress.expressTrainCount == 2)
        #expect(mixed.servicePattern == .balanced)
        #expect(mixed.localTrainCount == 1)
        #expect(mixed.expressTrainCount == 1)
        #expect(allExpress.journeyTimeMultiplier < mixed.journeyTimeMultiplier)
        #expect(allExpress.reliability > mixed.reliability)
    }

    @Test("Every supported combination remains finite, bounded and repeatable")
    func supportedCombinationInvariants() {
        let operations = TrainOperations()

        for frequency in ServiceFrequency.allCases {
            for pattern in ServicePattern.allCases {
                for capacity in TrackCapacity.allCases {
                    let input = LineOperationsInput(
                        frequency: frequency,
                        servicePattern: pattern,
                        trackCapacity: capacity
                    )
                    let first = operations.evaluate(input)
                    let second = operations.evaluate(input)

                    #expect(first == second)
                    #expect(first.congestionRatio.isFinite)
                    #expect((0...1).contains(first.congestionRatio))
                    #expect(first.reliability.isFinite)
                    #expect((0...1).contains(first.reliability))
                    #expect(first.journeyTimeMultiplier.isFinite)
                    #expect(first.journeyTimeMultiplier > 0)
                    #expect(
                        first.localTrainCount + first.expressTrainCount
                            == frequency.visibleTrainCount
                    )
                }
            }
        }
    }

    @Test("Mixed-service status identifies when overtaking infrastructure is missing")
    func mixedServiceStatus() {
        let operations = TrainOperations()
        let constrained = operations.evaluate(LineOperationsInput(
            frequency: .halfHourly,
            servicePattern: .balanced,
            trackCapacity: .singleTrack
        ))
        let flowing = operations.evaluate(LineOperationsInput(
            frequency: .halfHourly,
            servicePattern: .balanced,
            trackCapacity: .passingLoop
        ))

        #expect(constrained.hasMixedServices)
        #expect(constrained.statusMessage.contains("held behind"))
        #expect(constrained.statusMessage.contains("passing loop"))
        #expect(flowing.hasMixedServices)
        #expect(flowing.congestionBand == .flowing)
        #expect(flowing.statusMessage.contains("overtaking is available"))
    }

    @Test("Only local trains stop at the deterministic route midpoint")
    func intermediateStoppingPoints() {
        let operations = TrainOperations()

        #expect(operations.intermediateStopDistances(
            routeLength: 80_000,
            role: .local
        ) == [40_000])
        #expect(operations.intermediateStopDistances(
            routeLength: 80_000,
            role: .express
        ).isEmpty)
        #expect(operations.intermediateStopDistances(
            routeLength: 0,
            role: .local
        ).isEmpty)
        #expect(operations.intermediateStopDistances(
            routeLength: -1,
            role: .local
        ).isEmpty)
        #expect(operations.intermediateStopDistances(
            routeLength: .infinity,
            role: .local
        ).isEmpty)
        #expect(operations.intermediateStopDistances(
            routeLength: .nan,
            role: .local
        ).isEmpty)
    }

    @Test("Legacy balanced single-track speed stays stable until capacity unlocks role speeds")
    func roleSpeedsAndCongestion() {
        let operations = TrainOperations()

        #expect(operations.speedMultiplier(
            for: .local,
            pattern: .balanced,
            trackCapacity: .singleTrack,
            congestionRatio: 0
        ) == 1)
        #expect(operations.speedMultiplier(
            for: .express,
            pattern: .balanced,
            trackCapacity: .singleTrack,
            congestionRatio: 0
        ) == 1)
        #expect(operations.speedMultiplier(
            for: .express,
            pattern: .balanced,
            trackCapacity: .singleTrack,
            congestionRatio: 1
        ) == 1)
        #expect(abs(operations.speedMultiplier(
            for: .express,
            pattern: .balanced,
            trackCapacity: .passingLoop,
            congestionRatio: 0
        ) - 1.24) < 0.000_000_001)
        #expect(abs(operations.speedMultiplier(
            for: .express,
            pattern: .balanced,
            trackCapacity: .doubleTrack,
            congestionRatio: 0.5
        ) - 1.1036) < 0.000_000_001)
        #expect(abs(operations.speedMultiplier(
            for: .local,
            pattern: .balanced,
            trackCapacity: .doubleTrack,
            congestionRatio: 0.5
        ) - 0.7298) < 0.000_000_001)

        // Congestion input is clamped before it affects speed.
        #expect(abs(operations.speedMultiplier(
            for: .express,
            pattern: .express,
            trackCapacity: .singleTrack,
            congestionRatio: -1
        ) - 1.24) < 0.000_000_001)
        #expect(abs(operations.speedMultiplier(
            for: .express,
            pattern: .express,
            trackCapacity: .singleTrack,
            congestionRatio: 2
        ) - 0.9672) < 0.000_000_001)
    }

    @Test("Invalid speed tuning still returns a safe positive multiplier")
    func speedFloorAndNonfiniteCongestion() {
        let operations = TrainOperations(configuration: configuration(
            localSpeedMultiplier: -2,
            expressSpeedMultiplier: -3,
            constrainedMixedExpressSpeedMultiplier: -4
        ))

        #expect(operations.speedMultiplier(
            for: .local,
            pattern: .local,
            trackCapacity: .singleTrack,
            congestionRatio: 0.5
        ) == 0.1)
        #expect(operations.speedMultiplier(
            for: .express,
            pattern: .express,
            trackCapacity: .doubleTrack,
            congestionRatio: .infinity
        ) == 0.1)
        // The stable legacy baseline takes precedence over malformed custom tuning.
        #expect(operations.speedMultiplier(
            for: .express,
            pattern: .balanced,
            trackCapacity: .singleTrack,
            congestionRatio: .nan
        ) == 1)
    }

    @Test("The POC infrastructure ladder has exact incremental and cumulative costs")
    func upgradeCosts() {
        let operations = TrainOperations()
        let constructionCostPounds: Int64 = 120_000_000

        #expect(TrackCapacity.singleTrack.next == .passingLoop)
        #expect(TrackCapacity.passingLoop.next == .doubleTrack)
        #expect(TrackCapacity.doubleTrack.next == nil)
        #expect(!TrackCapacity.singleTrack.allowsOvertaking)
        #expect(TrackCapacity.passingLoop.allowsOvertaking)
        #expect(TrackCapacity.doubleTrack.allowsOvertaking)
        #expect(TrackCapacity.singleTrack.maintenanceMultiplierBasisPoints == 10_000)
        #expect(TrackCapacity.passingLoop.maintenanceMultiplierBasisPoints == 10_750)
        #expect(TrackCapacity.doubleTrack.maintenanceMultiplierBasisPoints == 18_500)

        #expect(operations.upgradeCostPence(
            from: .singleTrack,
            constructionCostPounds: constructionCostPounds
        ) == 800_000_000)
        #expect(operations.upgradeCostPence(
            from: .passingLoop,
            constructionCostPounds: constructionCostPounds
        ) == 5_400_000_000)
        #expect(operations.upgradeCostPence(
            from: .doubleTrack,
            constructionCostPounds: constructionCostPounds
        ) == nil)

        #expect(operations.infrastructureInvestmentPence(
            for: .singleTrack,
            constructionCostPounds: constructionCostPounds
        ) == 0)
        #expect(operations.infrastructureInvestmentPence(
            for: .passingLoop,
            constructionCostPounds: constructionCostPounds
        ) == 800_000_000)
        #expect(operations.infrastructureInvestmentPence(
            for: .doubleTrack,
            constructionCostPounds: constructionCostPounds
        ) == 6_200_000_000)
    }

    @Test("Upgrade costs clamp invalid tuning and saturate extreme investments")
    func upgradeCostSafety() {
        let invalid = TrainOperations(configuration: configuration(
            passingLoopBaseCostPence: -1,
            doubleTrackConstructionCostBasisPoints: -1
        ))
        #expect(invalid.upgradeCostPence(
            from: .singleTrack,
            constructionCostPounds: -1
        ) == 0)
        #expect(invalid.upgradeCostPence(
            from: .passingLoop,
            constructionCostPounds: -1
        ) == 0)
        #expect(invalid.infrastructureInvestmentPence(
            for: .doubleTrack,
            constructionCostPounds: .max
        ) == 0)

        let saturated = TrainOperations(configuration: configuration(
            passingLoopBaseCostPence: .max,
            doubleTrackConstructionCostBasisPoints: .max
        ))
        #expect(saturated.upgradeCostPence(
            from: .singleTrack,
            constructionCostPounds: .max
        ) == .max)
        #expect(saturated.upgradeCostPence(
            from: .passingLoop,
            constructionCostPounds: .max
        ) == .max)
        #expect(saturated.infrastructureInvestmentPence(
            for: .doubleTrack,
            constructionCostPounds: .max
        ) == .max)
    }

    private func configuration(
        localSpeedMultiplier: Double = 0.82,
        expressSpeedMultiplier: Double = 1.24,
        constrainedMixedExpressSpeedMultiplier: Double = 0.86,
        localIntermediateDwellDuration: TimeInterval = 3,
        passingLoopBaseCostPence: Int64 = 800_000_000,
        doubleTrackConstructionCostBasisPoints: Int64 = 4_500
    ) -> TrainOperationsConfiguration {
        TrainOperationsConfiguration(
            localSpeedMultiplier: localSpeedMultiplier,
            expressSpeedMultiplier: expressSpeedMultiplier,
            constrainedMixedExpressSpeedMultiplier: constrainedMixedExpressSpeedMultiplier,
            localIntermediateDwellDuration: localIntermediateDwellDuration,
            passingLoopBaseCostPence: passingLoopBaseCostPence,
            doubleTrackConstructionCostBasisPoints: doubleTrackConstructionCostBasisPoints
        )
    }
}
