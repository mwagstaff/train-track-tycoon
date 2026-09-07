import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Passenger population multipliers")
struct PassengerPopulationMultiplierTests {
    @Test("Omitted and unit multipliers preserve every existing result")
    func defaultIsBackwardCompatible() {
        let simulation = PassengerSimulation()
        let baseline = simulation.estimate(
            originCRS: "VIC",
            destinationCRS: "BTN",
            distanceKilometres: 80,
            frequency: .halfHourly
        )

        #expect(baseline == simulation.estimate(
            originCRS: "VIC",
            destinationCRS: "BTN",
            distanceKilometres: 80,
            frequency: .halfHourly,
            stationPopulationMultipliers: ["VIC": 1, "BTN": 1]
        ))
        #expect(baseline.potentialDailyJourneys == 7_360)
        #expect(baseline.passengersPerDay == 5_152)
    }

    @Test("Growth at either endpoint increases only the market demand inputs")
    func endpointGrowthIncreasesDemand() {
        let simulation = PassengerSimulation()
        let baseline = estimate(using: [:], simulation: simulation)
        let oneGrowing = estimate(using: ["VIC": 1.21], simulation: simulation)
        let bothGrowing = estimate(
            using: ["VIC": 1.21, "BTN": 1.21],
            simulation: simulation
        )

        #expect(baseline.potentialDailyJourneys < oneGrowing.potentialDailyJourneys)
        #expect(oneGrowing.potentialDailyJourneys < bothGrowing.potentialDailyJourneys)
        #expect(bothGrowing.attractedDailyJourneys > baseline.attractedDailyJourneys)
        #expect(bothGrowing.journeyMinutes == baseline.journeyMinutes)
        #expect(bothGrowing.averageWaitMinutes == baseline.averageWaitMinutes)
        #expect(bothGrowing.dailyCapacity == baseline.dailyCapacity)
    }

    @Test("Population multiplier keys are CRS-normalized")
    func multiplierKeysAreNormalized() {
        let simulation = PassengerSimulation()
        let canonical = estimate(
            using: ["VIC": 1.15, "BTN": 1.10],
            simulation: simulation
        )
        let untidy = estimate(
            using: [" vic ": 1.15, " btn\n": 1.10],
            simulation: simulation
        )

        #expect(untidy == canonical)
    }

    @Test("Invalid and unrelated multipliers preserve baseline demand")
    func invalidMultipliersFallBackToBaseline() {
        let simulation = PassengerSimulation()
        let baseline = estimate(using: [:], simulation: simulation)

        for invalid in [0, -1, Double.nan, Double.infinity, -Double.infinity] {
            #expect(estimate(
                using: ["VIC": invalid, "BTN": invalid, "AAA": 4],
                simulation: simulation
            ) == baseline)
        }
    }

    @Test("Network evaluation applies population growth once to a shared market")
    func networkEvaluationAppliesMultiplierOnce() throws {
        let first = PassengerLineInput(
            id: UUID(uuidString: "91919191-9191-9191-9191-919191919191")!,
            originCRS: "VIC",
            destinationCRS: "BTN",
            distanceKilometres: 80,
            frequency: .hourly
        )
        let second = PassengerLineInput(
            id: UUID(uuidString: "92929292-9292-9292-9292-929292929292")!,
            originCRS: "BTN",
            destinationCRS: "VIC",
            distanceKilometres: 80,
            frequency: .quarterHourly
        )
        let simulation = PassengerSimulation()
        let multipliers = ["VIC": 1.10, "BTN": 1.10]

        let baseline = simulation.evaluate([first, second])
        let grown = simulation.evaluate(
            [first, second],
            stationPopulationMultipliers: multipliers
        )
        let reversed = simulation.evaluate(
            [second, first],
            stationPopulationMultipliers: multipliers
        )

        #expect(grown == reversed)
        #expect(grown.potentialDailyJourneys > baseline.potentialDailyJourneys)
        #expect(
            try #require(grown.line(for: first.id)).potentialDailyJourneys
                + (try #require(grown.line(for: second.id)).potentialDailyJourneys)
                == grown.potentialDailyJourneys
        )
    }

    @Test("A not-yet-operating line exposes grown latent demand but carries nobody")
    func nonOperatingLineUsesGrownLatentDemand() {
        let line = PassengerLineInput(
            id: UUID(uuidString: "93939393-9393-9393-9393-939393939393")!,
            originCRS: "VIC",
            destinationCRS: "BTN",
            distanceKilometres: 80,
            frequency: .halfHourly,
            isOperating: false
        )
        let simulation = PassengerSimulation()
        let baseline = simulation.estimate(for: line)
        let grown = simulation.estimate(
            for: line,
            stationPopulationMultipliers: ["VIC": 1.25, "BTN": 1.25]
        )

        #expect(grown.potentialDailyJourneys > baseline.potentialDailyJourneys)
        #expect(grown.attractedDailyJourneys == 0)
        #expect(grown.passengersPerDay == 0)
        #expect(grown.dailyCapacity == 0)
        #expect(grown.feedback == .notOperating)
    }

    private func estimate(
        using multipliers: [String: Double],
        simulation: PassengerSimulation
    ) -> PassengerDemandEstimate {
        simulation.estimate(
            originCRS: "VIC",
            destinationCRS: "BTN",
            distanceKilometres: 80,
            frequency: .halfHourly,
            stationPopulationMultipliers: multipliers
        )
    }
}
