import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("High-speed rail")
struct HighSpeedRailTests {
    private let firstLineID = UUID(
        uuidString: "10000000-0000-0000-0000-000000000001"
    )!
    private let secondLineID = UUID(
        uuidString: "20000000-0000-0000-0000-000000000002"
    )!

    @Test("Railway class distinguishes infrastructure from service pattern")
    func railwayClasses() throws {
        #expect(RailwayClass.allCases == [.conventional, .highSpeed])
        #expect(RailwayClass.conventional.name == "Conventional")
        #expect(RailwayClass.highSpeed.name == "High speed")
        #expect(!RailwayClass.conventional.isHighSpeed)
        #expect(RailwayClass.highSpeed.isHighSpeed)

        let data = try JSONEncoder().encode(RailwayClass.highSpeed)
        #expect(try JSONDecoder().decode(RailwayClass.self, from: data) == .highSpeed)
    }

    @Test("The POC 80 km high-speed investment is exactly £440m")
    func documentedPOCQuote() {
        let quote = HighSpeedRail().investmentQuote(
            constructionCostPounds: 120_000_000,
            originCRS: "VIC",
            destinationCRS: "BTN",
            existingPremiumStationCRSs: [],
            trainCount: 2
        )

        #expect(quote.conventionalTrackReferencePence == 12_000_000_000)
        #expect(quote.trackAndInfrastructurePence == 36_000_000_000)
        #expect(quote.newPremiumEndpointCount == 2)
        #expect(quote.premiumStationUpgradesPence == 4_000_000_000)
        #expect(quote.initialTrainCount == 2)
        #expect(quote.rollingStockPence == 4_000_000_000)
        #expect(quote.constructionPence == 40_000_000_000)
        #expect(quote.totalPence == 44_000_000_000)
    }

    @Test("Premium endpoint charging is normalized, shared and direction independent")
    func premiumEndpointCharging() {
        let highSpeedRail = HighSpeedRail()
        let forward = highSpeedRail.investmentQuote(
            constructionCostPounds: 10,
            originCRS: " vic ",
            destinationCRS: "ecr",
            existingPremiumStationCRSs: ["VIC", " clj "],
            trainCount: 0
        )
        let reverse = highSpeedRail.investmentQuote(
            constructionCostPounds: 10,
            originCRS: "ECR",
            destinationCRS: " VIC\n",
            existingPremiumStationCRSs: ["vic", "CLJ"],
            trainCount: 0
        )
        let repeatedNewEndpoint = highSpeedRail.investmentQuote(
            constructionCostPounds: 0,
            originCRS: "abc",
            destinationCRS: " ABC ",
            existingPremiumStationCRSs: [],
            trainCount: 0
        )
        let blankEndpoints = highSpeedRail.investmentQuote(
            constructionCostPounds: 0,
            originCRS: " \n",
            destinationCRS: "\t",
            existingPremiumStationCRSs: [],
            trainCount: 0
        )

        #expect(forward == reverse)
        #expect(forward.newPremiumEndpointCount == 1)
        #expect(forward.premiumStationUpgradesPence == 2_000_000_000)
        #expect(repeatedNewEndpoint.newPremiumEndpointCount == 1)
        #expect(repeatedNewEndpoint.premiumStationUpgradesPence == 2_000_000_000)
        #expect(blankEndpoints.newPremiumEndpointCount == 0)
        #expect(blankEndpoints.premiumStationUpgradesPence == 0)
    }

    @Test("Quotes clamp malformed inputs and saturate instead of overflowing")
    func quoteSafety() {
        let highSpeedRail = HighSpeedRail()
        let negative = highSpeedRail.investmentQuote(
            constructionCostPounds: -1,
            originCRS: "A",
            destinationCRS: "B",
            existingPremiumStationCRSs: ["a", "b"],
            trainCount: -3
        )
        #expect(negative.conventionalTrackReferencePence == 0)
        #expect(negative.trackAndInfrastructurePence == 0)
        #expect(negative.premiumStationUpgradesPence == 0)
        #expect(negative.rollingStockPence == 0)
        #expect(negative.initialTrainCount == 0)
        #expect(negative.totalPence == 0)

        let saturated = highSpeedRail.investmentQuote(
            constructionCostPounds: .max,
            originCRS: "A",
            destinationCRS: "B",
            existingPremiumStationCRSs: [],
            trainCount: .max
        )
        #expect(saturated.conventionalTrackReferencePence == .max)
        #expect(saturated.trackAndInfrastructurePence == .max)
        #expect(saturated.rollingStockPence == .max)
        #expect(saturated.constructionPence == .max)
        #expect(saturated.totalPence == .max)

        let invalidTuning = HighSpeedRail(configuration: configuration(
            trackCostMultiplierBasisPoints: -1,
            premiumStationUpgradeCostPence: -1,
            highSpeedTrainUnitCostPence: -1
        )).investmentQuote(
            constructionCostPounds: 100,
            originCRS: "A",
            destinationCRS: "B",
            existingPremiumStationCRSs: [],
            trainCount: 2
        )
        #expect(invalidTuning.trackAndInfrastructurePence == 0)
        #expect(invalidTuning.premiumStationUpgradesPence == 0)
        #expect(invalidTuning.rollingStockPence == 0)
        #expect(invalidTuning.totalPence == 0)
    }

    @Test("POC capability is 215 mph and safely exceeds a 200 mph movement target")
    func speedAndJourneyCapability() {
        let highSpeedRail = HighSpeedRail()
        let twoHundredMPHMultiplier = 200.0 * 0.44704 / 45.0

        #expect(highSpeedRail.advertisedSpeedMilesPerHour == 215)
        #expect(
            abs(highSpeedRail.movementSpeedMultiplier - 2.135_857_777_777_778)
                < 0.000_000_000_001
        )
        #expect(highSpeedRail.movementSpeedMultiplier > twoHundredMPHMultiplier)
        #expect(abs(highSpeedRail.journeyTimeMultiplier - 0.55) < 0.000_000_001)
    }

    @Test("Malformed movement and journey tuning produces bounded safe facts")
    func speedAndJourneySafety() {
        let invalidBaseline = HighSpeedRail(configuration: configuration(
            movementBaselineMetresPerSecond: .nan,
            journeyTimeMultiplier: .infinity
        ))
        #expect(invalidBaseline.movementSpeedMultiplier == 0)
        #expect(invalidBaseline.journeyTimeMultiplier == 1)

        let invalidSpeed = HighSpeedRail(configuration: configuration(
            advertisedSpeedMilesPerHour: -1,
            movementBaselineMetresPerSecond: 45,
            journeyTimeMultiplier: -1
        ))
        #expect(invalidSpeed.advertisedSpeedMilesPerHour == 0)
        #expect(invalidSpeed.movementSpeedMultiplier == 0)
        #expect(invalidSpeed.journeyTimeMultiplier == 1)

        let slowerThanConventional = HighSpeedRail(configuration: configuration(
            journeyTimeMultiplier: 2
        ))
        #expect(slowerThanConventional.journeyTimeMultiplier == 1)
    }

    @Test("Only completed high-speed corridors and their unique endpoints earn prestige")
    func completedHighSpeedPrestige() {
        let highSpeedRail = HighSpeedRail()
        let completedHighSpeed = line(
            id: firstLineID,
            railwayClass: .highSpeed,
            originCRS: " vic ",
            destinationCRS: "b hm",
            isCompleted: true
        )
        let incompleteHighSpeed = line(
            id: secondLineID,
            railwayClass: .highSpeed,
            originCRS: "BTN",
            destinationCRS: "ASH",
            isCompleted: false
        )
        let completedConventional = line(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!,
            railwayClass: .conventional,
            originCRS: "KGX",
            destinationCRS: "EDB",
            isCompleted: true
        )

        let snapshot = highSpeedRail.prestigeSnapshot(lines: [
            incompleteHighSpeed,
            completedConventional,
            completedHighSpeed,
        ])

        #expect(snapshot.score == 25)
        #expect(snapshot.completedCorridorCount == 1)
        #expect(snapshot.premiumEndpointCount == 2)
        #expect(snapshot.tier == .pioneer)
        #expect(snapshot.summary.contains("1 completed corridor serves 2 premium stations"))
    }

    @Test("Prestige facts are normalized, duplicate-safe and input-order independent")
    func deterministicPrestige() {
        let highSpeedRail = HighSpeedRail()
        let first = line(
            id: firstLineID,
            originCRS: " vic ",
            destinationCRS: "BHM",
            isCompleted: true
        )
        let duplicateFirst = line(
            id: firstLineID,
            originCRS: "VIC",
            destinationCRS: " bhm\n",
            isCompleted: true
        )
        let second = line(
            id: secondLineID,
            originCRS: "bhm",
            destinationCRS: "MAN",
            isCompleted: true
        )

        let forward = highSpeedRail.prestigeSnapshot(lines: [
            first,
            duplicateFirst,
            second,
        ])
        let reverse = highSpeedRail.prestigeSnapshot(lines: [
            second,
            duplicateFirst,
            first,
        ])

        #expect(forward == reverse)
        #expect(forward.score == 45)
        #expect(forward.completedCorridorCount == 2)
        #expect(forward.premiumEndpointCount == 3)
        #expect(forward.tier == .national)
        #expect(forward.summary.contains("2 completed corridors serve 3 premium stations"))
    }

    @Test("Projected prestige counts only genuinely new completed infrastructure")
    func projectedPrestige() {
        let highSpeedRail = HighSpeedRail()
        let first = line(
            id: firstLineID,
            originCRS: "VIC",
            destinationCRS: "BHM",
            isCompleted: true
        )
        let second = line(
            id: secondLineID,
            originCRS: "BHM",
            destinationCRS: "MAN",
            isCompleted: true
        )
        let incomplete = line(
            id: secondLineID,
            originCRS: "BHM",
            destinationCRS: "MAN",
            isCompleted: false
        )
        let conventional = line(
            id: secondLineID,
            railwayClass: .conventional,
            originCRS: "BHM",
            destinationCRS: "MAN",
            isCompleted: true
        )

        #expect(highSpeedRail.projectedPrestigeGain(
            for: second,
            existingLines: [first]
        ) == 20)
        #expect(highSpeedRail.projectedPrestigeGain(
            for: first,
            existingLines: [first]
        ) == 0)
        #expect(highSpeedRail.projectedPrestigeGain(
            for: incomplete,
            existingLines: [first]
        ) == 0)
        #expect(highSpeedRail.projectedPrestigeGain(
            for: conventional,
            existingLines: [first]
        ) == 0)
    }

    @Test("Prestige score saturates at 100 and malformed weights cannot reduce it")
    func prestigeBounds() {
        let saturated = HighSpeedRail(configuration: configuration(
            prestigePointsPerCompletedCorridor: .max,
            prestigePointsPerPremiumEndpoint: .max
        )).prestigeSnapshot(lines: [line(
            id: firstLineID,
            originCRS: "VIC",
            destinationCRS: "BHM",
            isCompleted: true
        )])
        #expect(saturated.score == 100)
        #expect(saturated.tier == .iconic)
        #expect(saturated.summary.contains("iconic status"))

        let negative = HighSpeedRail(configuration: configuration(
            prestigePointsPerCompletedCorridor: -1,
            prestigePointsPerPremiumEndpoint: -1
        )).prestigeSnapshot(lines: [line(
            id: firstLineID,
            originCRS: "VIC",
            destinationCRS: "BHM",
            isCompleted: true
        )])
        #expect(negative.score == 0)
        #expect(negative.completedCorridorCount == 1)
        #expect(negative.premiumEndpointCount == 2)
        #expect(negative.tier == .none)
        #expect(negative.summary.contains("current tuning awards no high-speed prestige"))
        #expect((0...100).contains(negative.score))
    }

    private func line(
        id: UUID,
        railwayClass: RailwayClass = .highSpeed,
        originCRS: String,
        destinationCRS: String,
        isCompleted: Bool
    ) -> HighSpeedPrestigeLineInput {
        HighSpeedPrestigeLineInput(
            id: id,
            railwayClass: railwayClass,
            originCRS: originCRS,
            destinationCRS: destinationCRS,
            isCompleted: isCompleted
        )
    }

    private func configuration(
        trackCostMultiplierBasisPoints: Int64 = 30_000,
        premiumStationUpgradeCostPence: Int64 = 2_000_000_000,
        highSpeedTrainUnitCostPence: Int64 = 2_000_000_000,
        advertisedSpeedMilesPerHour: Int = 215,
        movementBaselineMetresPerSecond: Double = 45,
        journeyTimeMultiplier: Double = 0.55,
        prestigePointsPerCompletedCorridor: Int64 = 15,
        prestigePointsPerPremiumEndpoint: Int64 = 5
    ) -> HighSpeedRailConfiguration {
        HighSpeedRailConfiguration(
            trackCostMultiplierBasisPoints: trackCostMultiplierBasisPoints,
            premiumStationUpgradeCostPence: premiumStationUpgradeCostPence,
            highSpeedTrainUnitCostPence: highSpeedTrainUnitCostPence,
            advertisedSpeedMilesPerHour: advertisedSpeedMilesPerHour,
            movementBaselineMetresPerSecond: movementBaselineMetresPerSecond,
            journeyTimeMultiplier: journeyTimeMultiplier,
            prestigePointsPerCompletedCorridor: prestigePointsPerCompletedCorridor,
            prestigePointsPerPremiumEndpoint: prestigePointsPerPremiumEndpoint
        )
    }
}
