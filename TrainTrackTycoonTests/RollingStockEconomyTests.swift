import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Rolling-stock economy")
struct RollingStockEconomyTests {
    private let lineID = UUID(
        uuidString: "A1100000-0000-0000-0000-000000000001"
    )!

    @Test("Six-car formations preserve every established operating golden")
    func sixCarOperatingBaseline() throws {
        let line = try operatingLine(formation: .sixCar)

        #expect(line.revenuePencePerDay == 5_800_000)
        #expect(line.energyCostPencePerDay == 1_728_000)
        #expect(line.rollingStockMaintenanceCostPencePerDay == 1_302_000)
        #expect(line.trainOperatingCostPencePerDay == 3_030_000)
        #expect(line.trackUpkeepPencePerDay == 960_000)
        #expect(line.totalOperatingCostPencePerDay == 3_990_000)
        #expect(line.operatingResultPencePerDay == 1_810_000)
    }

    @Test("Distance-based energy and maintenance scale by carriages while trainset overhead stays fixed")
    func formationScalesOnlyVariableTrainCosts() throws {
        let twoCar = try operatingLine(formation: .twoCar)
        let sixCar = try operatingLine(formation: .sixCar)
        let twelveCar = try operatingLine(formation: .twelveCar)

        #expect(twoCar.energyCostPencePerDay == 576_000)
        #expect(sixCar.energyCostPencePerDay == 1_728_000)
        #expect(twelveCar.energyCostPencePerDay == 3_456_000)

        // The fixed 150,000p two-train overhead does not change with carriage count.
        #expect(twoCar.rollingStockMaintenanceCostPencePerDay == 534_000)
        #expect(sixCar.rollingStockMaintenanceCostPencePerDay == 1_302_000)
        #expect(twelveCar.rollingStockMaintenanceCostPencePerDay == 2_454_000)
        #expect(
            twoCar.rollingStockMaintenanceCostPencePerDay - 150_000
                == (sixCar.rollingStockMaintenanceCostPencePerDay - 150_000) / 3
        )
        #expect(
            twelveCar.rollingStockMaintenanceCostPencePerDay - 150_000
                == (sixCar.rollingStockMaintenanceCostPencePerDay - 150_000) * 2
        )
        #expect(twoCar.revenuePencePerDay == sixCar.revenuePencePerDay)
        #expect(sixCar.revenuePencePerDay == twelveCar.revenuePencePerDay)
        #expect(twoCar.trackUpkeepPencePerDay == twelveCar.trackUpkeepPencePerDay)
    }

    @Test("High-speed multipliers are applied after formation scaling")
    func highSpeedFormationScalingOrder() throws {
        let snapshot = OperatingEconomy().evaluate(
            lines: [
                EconomyLineInput(
                    id: lineID,
                    originCRS: "VIC",
                    destinationCRS: "BTN",
                    distanceMetres: 80_000,
                    frequency: .halfHourly,
                    trackCapacity: .doubleTrack,
                    passengerJourneysPerDay: 5_000,
                    railwayClass: .highSpeed,
                    formation: .twelveCar
                ),
            ],
            stationLevelsByCRS: [:]
        )
        let line = try #require(snapshot.lineSnapshot(for: lineID))

        // Six-car energy is 1,728,000p; twelve cars double it, then HSR doubles it.
        #expect(line.energyCostPencePerDay == 6_912_000)
        // (2,304,000p variable + 150,000p fixed) * 1.75 HSR multiplier.
        #expect(line.rollingStockMaintenanceCostPencePerDay == 4_294_500)

        let malformedShortHighSpeed = OperatingEconomy().evaluate(
            lines: [
                EconomyLineInput(
                    id: lineID,
                    originCRS: "VIC",
                    destinationCRS: "BTN",
                    distanceMetres: 80_000,
                    frequency: .halfHourly,
                    passengerJourneysPerDay: 5_000,
                    railwayClass: .highSpeed,
                    formation: .twoCar
                ),
            ],
            stationLevelsByCRS: [:]
        )
        let clampedLine = try #require(malformedShortHighSpeed.lineSnapshot(for: lineID))
        #expect(clampedLine.energyCostPencePerDay == 3_456_000)
        #expect(clampedLine.rollingStockMaintenanceCostPencePerDay == 2_278_500)
    }

    @Test("Capital prices and new-line quotes scale from the six-car unit price")
    func formationSpecificCapitalPrices() {
        let economy = CapitalEconomy()

        #expect(economy.rollingStockCost(
            forTrainCount: 1,
            formation: .twoCar
        ) == 133_333_333)
        #expect(economy.rollingStockCost(
            forTrainCount: 1,
            formation: .sixCar
        ) == 400_000_000)
        #expect(economy.rollingStockCost(
            forTrainCount: 1,
            formation: .twelveCar
        ) == 800_000_000)
        #expect(economy.rollingStockCost(
            forTrainCount: 1,
            formation: .twoCar,
            railwayClass: .highSpeed
        ) == 2_000_000_000)
        #expect(economy.rollingStockCost(
            forTrainCount: 1,
            formation: .twelveCar,
            railwayClass: .highSpeed
        ) == 4_000_000_000)

        let conventional = economy.quoteForNewLine(
            constructionCostPounds: 0,
            originCRS: "VIC",
            destinationCRS: "BTN",
            existingStationCRSs: ["VIC", "BTN"],
            initialTrainCount: 2,
            initialFormation: .twelveCar
        )
        #expect(conventional.rollingStockPence == 1_600_000_000)

        let highSpeed = economy.quoteForNewLine(
            constructionCostPounds: 0,
            originCRS: "VIC",
            destinationCRS: "BTN",
            existingStationCRSs: ["VIC", "BTN"],
            initialTrainCount: 2,
            initialFormation: .twelveCar,
            railwayClass: .highSpeed,
            existingPremiumStationCRSs: ["VIC", "BTN"]
        )
        #expect(highSpeed.rollingStockPence == 8_000_000_000)
    }

    @Test("Fleet extensions equal the next formation price difference")
    func formationExtensionQuote() throws {
        let economy = CapitalEconomy()
        let quote = try #require(economy.quoteForFormationExtension(
            ownedTrainCount: 2,
            currentFormation: .fourCar
        ))

        #expect(quote.currentFormation == .fourCar)
        #expect(quote.upgradedFormation == .sixCar)
        #expect(quote.ownedTrainCount == 2)
        #expect(quote.totalCostPence == 266_666_668)
        #expect(quote.totalCostPence == EconomyArithmetic.subtract(
            economy.rollingStockCost(forTrainCount: 2, formation: .sixCar),
            economy.rollingStockCost(forTrainCount: 2, formation: .fourCar)
        ))

        let highSpeed = try #require(economy.quoteForFormationExtension(
            ownedTrainCount: 3,
            currentFormation: .twoCar,
            railwayClass: .highSpeed
        ))
        #expect(highSpeed.currentFormation == .sixCar)
        #expect(highSpeed.upgradedFormation == .eightCar)
        #expect(highSpeed.totalCostPence == 1_999_999_998)

        #expect(economy.quoteForFormationExtension(
            ownedTrainCount: 4,
            currentFormation: .twelveCar
        ) == nil)
        #expect(economy.quoteForFormationExtension(
            ownedTrainCount: -1,
            currentFormation: .sixCar
        )?.totalCostPence == 0)
    }

    @Test("Ownership value and extension prices saturate deterministically")
    func capitalSaturationAndOrdering() {
        let economy = CapitalEconomy(configuration: configuration(
            rollingStockUnitCostPence: .max
        ))
        let first = CapitalLineInput(
            id: UUID(uuidString: "A1100000-0000-0000-0000-000000000002")!,
            constructionCostPounds: 0,
            ownedTrainCount: .max,
            formation: .twoCar
        )
        let second = CapitalLineInput(
            id: UUID(uuidString: "A1100000-0000-0000-0000-000000000003")!,
            constructionCostPounds: 0,
            ownedTrainCount: .max,
            formation: .twelveCar
        )
        let ledger = FinanceLedger(mode: .zen)

        let forward = economy.evaluate(
            lines: [first, second],
            stationLevelsByCRS: [:],
            operatingEconomy: .zero,
            ledger: ledger
        )
        let reverse = economy.evaluate(
            lines: [second, first],
            stationLevelsByCRS: [:],
            operatingEconomy: .zero,
            ledger: ledger
        )

        #expect(forward == reverse)
        #expect(forward.rollingStockValuePence == .max)
        #expect(economy.rollingStockCost(
            forTrainCount: .max,
            formation: .twelveCar
        ) == .max)
        #expect(economy.quoteForFormationExtension(
            ownedTrainCount: .max,
            currentFormation: .sixCar
        )?.totalCostPence == .max)
    }

    private func operatingLine(
        formation: RollingStockFormation
    ) throws -> LineOperatingEconomySnapshot {
        let snapshot = OperatingEconomy().evaluate(
            lines: [
                EconomyLineInput(
                    id: lineID,
                    originCRS: "VIC",
                    destinationCRS: "BTN",
                    distanceMetres: 80_000,
                    frequency: .halfHourly,
                    passengerJourneysPerDay: 5_000,
                    formation: formation
                ),
            ],
            stationLevelsByCRS: ["VIC": .localStation, "BTN": .townStation]
        )
        return try #require(snapshot.lineSnapshot(for: lineID))
    }

    private func configuration(
        rollingStockUnitCostPence: Int64
    ) -> CapitalEconomyConfiguration {
        CapitalEconomyConfiguration(
            startingCashPence: 0,
            stationConstructionCostPence: 0,
            rollingStockUnitCostPence: rollingStockUnitCostPence,
            loanPrincipalPence: 0,
            earlyRepaymentPence: 0,
            loanAnnualInterestBasisPoints: 0,
            loanTermOperatingDays: 1,
            maximumConcurrentLoans: 0,
            insolvencyGraceOperatingDays: 1,
            lowCashThresholdPence: 0,
            stationValuePenceByLevel: [:]
        )
    }
}
