import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Population presentation")
struct PopulationPresentationTests {
    @Test("Station presentation normalizes invalid display inputs")
    func stationPresentationNormalization() {
        let presentation = SettlementGrowthUIPresentation(
            population: -25,
            latestChange: -80,
            demandMultiplier: .nan,
            reason: "   "
        )

        #expect(presentation.population == 0)
        #expect(presentation.latestChange == -80)
        #expect(presentation.demandMultiplier == 1)
        #expect(
            presentation.reason
                == "Railway accessibility is not changing local growth yet."
        )
    }

    @Test("Population changes always retain text and symbol meaning")
    func populationChangePresentation() {
        #expect(PopulationUIPresentation.compactChange(0) == "No change")
        #expect(PopulationUIPresentation.changeSymbol(0) == "arrow.right")
        #expect(PopulationUIPresentation.compactChange(1_250).hasPrefix("+"))
        #expect(PopulationUIPresentation.changeSymbol(1_250) == "arrow.up.right")
        #expect(PopulationUIPresentation.compactChange(-1_250).hasPrefix("−"))
        #expect(PopulationUIPresentation.changeSymbol(-1_250) == "arrow.down.right")
        #expect(
            PopulationUIPresentation.changeDescription(50)
                .hasPrefix("Increased by")
        )
        #expect(
            PopulationUIPresentation.changeDescription(-50)
                .hasPrefix("Decreased by")
        )
    }

    @Test("Demand multiplier is stable for finite and invalid values")
    func demandMultiplierPresentation() {
        #expect(PopulationUIPresentation.demandMultiplier(1.125) == "1.12×")
        #expect(PopulationUIPresentation.demandMultiplier(.infinity) == "1.00×")
        #expect(PopulationUIPresentation.demandMultiplier(-2) == "1.00×")
    }

    @Test("Population trend describes growth, decline, steady state, and missing history")
    func populationTrendPresentation() {
        let growing = points([10_000, 10_250, 10_600])
        let declining = points([10_000, 9_900, 9_700])
        let steady = points([10_000, 10_100, 10_000])

        #expect(PopulationUIPresentation.trendDirection([]) == .unavailable)
        #expect(PopulationUIPresentation.trendDirection(points([10_000])) == .unavailable)
        #expect(PopulationUIPresentation.trendDirection(growing) == .growing)
        #expect(PopulationUIPresentation.trendDirection(declining) == .declining)
        #expect(PopulationUIPresentation.trendDirection(steady) == .steady)
        #expect(PopulationUIPresentation.trendSummary([]).contains("first operating day"))
        #expect(PopulationUIPresentation.trendSummary(growing).hasPrefix("Up"))
        #expect(PopulationUIPresentation.trendSummary(declining).hasPrefix("Down"))
        #expect(PopulationUIPresentation.trendSummary(steady).hasPrefix("No net change"))
    }

    @Test("Population history stays bounded to the latest 120 operating days")
    func populationHistoryBound() {
        var records: [PublicBetaDailyNetworkRecord] = []
        for day in 1...130 {
            records.append(
                PublicBetaDailyNetworkRecord(
                    operatingDay: UInt64(day),
                    facts: .zero,
                    operatingResultPence: 0,
                    totalNetworkPopulation: Int64(day * 1_000),
                    latestPopulationChange: Int64(day)
                )
            )
        }

        let points = PopulationUIPresentation.historyPoints(from: records)

        #expect(points.count == PopulationUIPresentation.maximumHistoryCount)
        #expect(points.first?.operatingDay == 11)
        #expect(points.first?.population == 11_000)
        #expect(points.last?.operatingDay == 130)
        #expect(points.last?.change == 130)
    }

    @Test("Legacy history without a population measurement is not charted as zero")
    func legacyUnknownPopulationIsFiltered() {
        let records = [
            PublicBetaDailyNetworkRecord(
                operatingDay: 8,
                facts: .zero,
                operatingResultPence: 0,
                totalNetworkPopulation: 0,
                latestPopulationChange: 0
            ),
            PublicBetaDailyNetworkRecord(
                operatingDay: 9,
                facts: .zero,
                operatingResultPence: 0,
                totalNetworkPopulation: 195_000,
                latestPopulationChange: 140
            ),
        ]

        let points = PopulationUIPresentation.historyPoints(from: records)

        #expect(points == [
            PopulationHistoryPoint(
                operatingDay: 9,
                population: 195_000,
                change: 140
            ),
        ])
    }

    @Test("Chart domain remains visible for flat and changing histories")
    func chartDomain() {
        let flatDomain = PopulationUIPresentation.chartDomain(points([12_000, 12_000]))
        #expect(flatDomain.lowerBound < 12_000)
        #expect(flatDomain.upperBound > 12_000)

        let changingDomain = PopulationUIPresentation.chartDomain(points([10_000, 20_000]))
        #expect(changingDomain.lowerBound < 10_000)
        #expect(changingDomain.upperBound > 20_000)
        #expect(PopulationUIPresentation.chartDomain([]) == 0...1)
    }

    private func points(_ populations: [Int64]) -> [PopulationHistoryPoint] {
        populations.enumerated().map { index, population in
            let previous = index > 0 ? populations[index - 1] : population
            return PopulationHistoryPoint(
                operatingDay: UInt64(index + 1),
                population: population,
                change: population - previous
            )
        }
    }
}
