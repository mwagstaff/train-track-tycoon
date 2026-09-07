import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Settlement growth")
struct SettlementGrowthTests {
    @Test("POC baselines are synthetic, stable and CRS-normalized")
    func pocBaselinesAreStable() {
        let growth = SettlementGrowth()

        #expect(growth.baselinePopulation(forStationCRS: " vic ") == 160_000)
        #expect(growth.baselinePopulation(forStationCRS: "SRS") == 65_000)
        #expect(growth.baselinePopulation(forStationCRS: "unknown") == 100_000)
        #expect(growth.initialState(forStationCRS: " ecr ") == SettlementPopulationState(
            stationCRS: "ECR",
            baselinePopulation: 115_000,
            currentPopulation: 115_000
        ))
    }

    @Test("Disconnected settlements neither gain state nor receive rail-led growth")
    func disconnectedSettlementsDoNotGrow() throws {
        let growth = SettlementGrowth(configuration: cappedConfiguration)
        let result = growth.applyOperatingDay(
            inputs: [
                SettlementGrowthInput(
                    stationCRS: "AAA",
                    isConnected: false,
                    localHappinessScore: 100,
                    reachableDestinationCount: 10
                ),
            ],
            existingStatesByCRS: [:]
        )
        let status = try #require(result.status(forStationCRS: "aaa"))

        #expect(result.statesByCRS.isEmpty)
        #expect(result.totalConnectedPopulation == 0)
        #expect(result.latestDailyPopulationChange == 0)
        #expect(result.passengerDemandMultipliersByCRS.isEmpty)
        #expect(status.currentPopulation == 1_000)
        #expect(status.latestDailyChange == 0)
        #expect(status.growthPotential == 0)
        #expect(status.passengerDemandMultiplier == 1)
        #expect(status.feedback == .noRailAccess)
    }

    @Test("Growth requires happiness and a reachable destination")
    func growthRequiresHappinessAndAccessibility() throws {
        let growth = SettlementGrowth(configuration: cappedConfiguration)
        let noDestination = SettlementGrowthInput(
            stationCRS: "AAA",
            isConnected: true,
            localHappinessScore: 100,
            reachableDestinationCount: 0
        )
        let unhappy = SettlementGrowthInput(
            stationCRS: "BBB",
            isConnected: true,
            localHappinessScore: 20,
            reachableDestinationCount: 4
        )

        let result = growth.applyOperatingDay(
            inputs: [noDestination, unhappy],
            existingStatesByCRS: [:]
        )

        #expect(try #require(result.state(forStationCRS: "AAA")).currentPopulation == 1_000)
        #expect(try #require(result.state(forStationCRS: "BBB")).currentPopulation == 2_000)
        #expect(try #require(result.status(forStationCRS: "AAA")).feedback
            == .needsBetterAccessibility)
        #expect(try #require(result.status(forStationCRS: "BBB")).feedback
            == .needsBetterAccessibility)
    }

    @Test("One operating day obeys both proportional and absolute caps")
    func dailyCapsAreStrict() throws {
        let growth = SettlementGrowth(configuration: cappedConfiguration)
        let result = growth.applyOperatingDay(
            inputs: [excellentInput],
            existingStatesByCRS: [:]
        )
        let state = try #require(result.state(forStationCRS: "AAA"))
        let status = try #require(result.status(forStationCRS: "AAA"))

        // Ten percent would be 100 people; the 60-person absolute ceiling wins.
        #expect(state.currentPopulation == 1_060)
        #expect(state.latestDailyChange == 60)
        #expect(result.totalConnectedPopulation == 1_060)
        #expect(result.latestDailyPopulationChange == 60)
        #expect(abs(status.growthPotential - 1) < 0.000_000_001)
        #expect(abs(status.passengerDemandMultiplier - 1.06) < 0.000_000_001)
        #expect(status.feedback == .strongGrowth)

        let proportionalConfiguration = SettlementGrowthConfiguration(
            baselinePopulationByCRS: ["AAA": 1_000],
            minimumHappinessScoreForGrowth: 20,
            happinessScoreForFullGrowth: 80,
            reachableDestinationsForFullGrowth: 4,
            maximumDailyGrowthRate: 0.01,
            maximumDailyPopulationIncrease: 500,
            maximumPopulationMultiplier: 2,
            maximumPassengerDemandMultiplier: 1.5
        )
        let proportionalResult = SettlementGrowth(configuration: proportionalConfiguration)
            .applyOperatingDay(inputs: [excellentInput], existingStatesByCRS: [:])
        #expect(try #require(proportionalResult.state(forStationCRS: "AAA"))
            .latestDailyChange == 10)
    }

    @Test("Lifetime growth and passenger-demand influence are independently capped")
    func lifetimeAndDemandCapsAreStrict() throws {
        let growth = SettlementGrowth(configuration: cappedConfiguration)
        var states = [String: SettlementPopulationState]()
        var latestResult: SettlementGrowthResult?

        for _ in 0..<20 {
            latestResult = growth.applyOperatingDay(
                inputs: [excellentInput],
                existingStatesByCRS: states
            )
            states = try #require(latestResult).statesByCRS
        }

        let result = try #require(latestResult)
        let state = try #require(result.state(forStationCRS: "AAA"))
        let status = try #require(result.status(forStationCRS: "AAA"))
        #expect(state.currentPopulation == 1_200)
        #expect(state.latestDailyChange == 0)
        #expect(abs(status.passengerDemandMultiplier - 1.1) < 0.000_000_001)
        #expect(status.feedback == .maximumReached)
    }

    @Test("Wider accessibility increases growth with diminishing bounded influence")
    func accessibilityImprovesGrowth() throws {
        let growth = SettlementGrowth(configuration: cappedConfiguration)
        let narrow = growth.applyOperatingDay(
            inputs: [
                SettlementGrowthInput(
                    stationCRS: "AAA",
                    isConnected: true,
                    localHappinessScore: 80,
                    reachableDestinationCount: 1
                ),
            ],
            existingStatesByCRS: [:]
        )
        let wide = growth.applyOperatingDay(
            inputs: [excellentInput],
            existingStatesByCRS: [:]
        )

        let narrowState = try #require(narrow.state(forStationCRS: "AAA"))
        let wideState = try #require(wide.state(forStationCRS: "AAA"))
        #expect(narrowState.latestDailyChange > 0)
        #expect(narrowState.latestDailyChange < wideState.latestDailyChange)
        #expect(wideState.latestDailyChange == 60)
    }

    @Test("Reconciliation is normalized, deterministic and limited to connected stations")
    func reconciliationIsDeterministic() {
        let growth = SettlementGrowth(configuration: cappedConfiguration)
        let lower = SettlementPopulationState(
            stationCRS: "AAA",
            baselinePopulation: 1_000,
            currentPopulation: 1_040,
            latestDailyChange: 20
        )
        let higher = SettlementPopulationState(
            stationCRS: "AAA",
            baselinePopulation: 1_000,
            currentPopulation: 1_080,
            latestDailyChange: 60
        )
        let existing = [" aaa ": lower, "AAA": higher, "BBB": higher]

        let result = growth.reconcile(
            connectedStationCRSs: [" AAA ", "aaa", "CCC"],
            existingStatesByCRS: existing
        )

        #expect(result.keys.sorted() == ["AAA", "CCC"])
        #expect(result["AAA"]?.currentPopulation == 1_080)
        #expect(result["CCC"]?.currentPopulation == 1_000)
        #expect(result["BBB"] == nil)
    }

    @Test("Duplicate inputs and input ordering cannot alter progression")
    func duplicateInputsAreOrderIndependent() {
        let growth = SettlementGrowth(configuration: cappedConfiguration)
        let weak = SettlementGrowthInput(
            stationCRS: " aaa ",
            isConnected: false,
            localHappinessScore: 10,
            reachableDestinationCount: 0
        )
        let strong = excellentInput

        let forward = growth.applyOperatingDay(
            inputs: [weak, strong],
            existingStatesByCRS: [:]
        )
        let reverse = growth.applyOperatingDay(
            inputs: [strong, weak],
            existingStatesByCRS: [:]
        )

        #expect(forward == reverse)
        #expect(forward.state(forStationCRS: "AAA")?.latestDailyChange == 60)
    }

    @Test("Population state round-trips without losing the latest change")
    func stateIsCodable() throws {
        let state = SettlementPopulationState(
            stationCRS: " ecr ",
            baselinePopulation: 115_000,
            currentPopulation: 116_250,
            latestDailyChange: 230
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(SettlementPopulationState.self, from: data)

        #expect(decoded == state)
        #expect(decoded.stationCRS == "ECR")
        #expect(decoded.totalGrowth == 1_250)
    }

    @Test("Feedback contains stable player-facing explanations")
    func feedbackIsPresentationReady() {
        for feedback in SettlementGrowthFeedback.allCases {
            #expect(!feedback.title.isEmpty)
            #expect(!feedback.message.isEmpty)
        }

        let initialHighPotential = SettlementGrowth(configuration: cappedConfiguration)
            .status(for: excellentInput, state: nil)
        #expect(initialHighPotential.latestDailyChange == 0)
        #expect(initialHighPotential.feedback == .strongGrowth)
    }

    private var cappedConfiguration: SettlementGrowthConfiguration {
        SettlementGrowthConfiguration(
            baselinePopulationByCRS: ["AAA": 1_000, "BBB": 2_000],
            fallbackBaselinePopulation: 1_000,
            minimumHappinessScoreForGrowth: 20,
            happinessScoreForFullGrowth: 80,
            reachableDestinationsForFullGrowth: 4,
            happinessWeight: 0.75,
            maximumDailyGrowthRate: 0.10,
            maximumDailyPopulationIncrease: 60,
            maximumPopulationMultiplier: 1.20,
            maximumPassengerDemandMultiplier: 1.10,
            strongGrowthPotentialThreshold: 0.72
        )
    }

    private var excellentInput: SettlementGrowthInput {
        SettlementGrowthInput(
            stationCRS: "AAA",
            isConnected: true,
            localHappinessScore: 100,
            reachableDestinationCount: 4
        )
    }
}
