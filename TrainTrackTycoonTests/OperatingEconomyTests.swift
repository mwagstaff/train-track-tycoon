import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Operating economy")
struct OperatingEconomyTests {
    @Test("POC fares and daily line costs use the documented formula")
    func pocFormula() throws {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let input = EconomyLineInput(
            id: id,
            originCRS: "VIC",
            destinationCRS: "BTN",
            distanceMetres: 80_000,
            frequency: .halfHourly,
            passengerJourneysPerDay: 5_000
        )

        let snapshot = OperatingEconomy().evaluate(
            lines: [input],
            stationLevelsByCRS: [
                "VIC": .localStation,
                "BTN": .townStation,
            ]
        )
        let line = try #require(snapshot.lineSnapshot(for: id))

        // Fare: 200p + (80 km * 12p) = 1,160p per journey.
        #expect(line.revenuePencePerDay == 5_800_000)
        #expect(line.highSpeedFarePremiumPencePerDay == 0)
        // 2 departures/hour * 18 hours * 2 directions = 72 one-way trips.
        #expect(line.energyCostPencePerDay == 1_728_000)
        // Variable: 5,760 train-km * 200p. Fixed: 2 assigned trains * 75,000p.
        #expect(line.rollingStockMaintenanceCostPencePerDay == 1_302_000)
        #expect(line.trainOperatingCostPencePerDay == 3_030_000)
        #expect(line.trackUpkeepPencePerDay == 960_000)
        #expect(line.totalOperatingCostPencePerDay == 3_990_000)
        #expect(line.operatingResultPencePerDay == 1_810_000)
        #expect(snapshot.stationUpkeepPencePerDay == 150_000)
        #expect(snapshot.premiumStationUpkeepPencePerDay == 0)
        #expect(snapshot.totalRevenuePencePerDay == 5_800_000)
        #expect(snapshot.totalHighSpeedFarePremiumPencePerDay == 0)
        #expect(snapshot.totalEnergyCostPencePerDay == 1_728_000)
        #expect(snapshot.totalRollingStockMaintenanceCostPencePerDay == 1_302_000)
        #expect(snapshot.totalTrainOperatingCostPencePerDay == 3_030_000)
        #expect(snapshot.totalOperatingCostPencePerDay == 4_140_000)
        #expect(snapshot.operatingResultPencePerDay == 1_660_000)
    }

    @Test("High-speed fares and daily costs use the documented premiums")
    func highSpeedFormula() throws {
        let id = UUID(uuidString: "12121212-1212-1212-1212-121212121212")!
        let input = EconomyLineInput(
            id: id,
            originCRS: "VIC",
            destinationCRS: "BTN",
            distanceMetres: 80_000,
            frequency: .halfHourly,
            trackCapacity: .doubleTrack,
            passengerJourneysPerDay: 5_000,
            railwayClass: .highSpeed
        )

        let snapshot = OperatingEconomy().evaluate(
            lines: [input],
            stationLevelsByCRS: [
                "VIC": .localStation,
                "BTN": .townStation,
            ]
        )
        let line = try #require(snapshot.lineSnapshot(for: id))

        #expect(line.highSpeedFarePremiumPencePerDay == 2_030_000)
        #expect(line.revenuePencePerDay == 7_830_000)
        #expect(line.energyCostPencePerDay == 3_456_000)
        #expect(line.rollingStockMaintenanceCostPencePerDay == 2_278_500)
        #expect(line.trainOperatingCostPencePerDay == 5_734_500)
        #expect(line.trackUpkeepPencePerDay == 1_920_000)
        #expect(line.totalOperatingCostPencePerDay == 7_654_500)
        #expect(line.operatingResultPencePerDay == 175_500)
        #expect(snapshot.totalHighSpeedFarePremiumPencePerDay == 2_030_000)
        #expect(snapshot.premiumStationUpkeepPencePerDay == 1_000_000)
        #expect(snapshot.stationUpkeepPencePerDay == 1_150_000)
        #expect(snapshot.totalOperatingCostPencePerDay == 8_804_500)
        #expect(snapshot.operatingResultPencePerDay == -974_500)
    }

    @Test("Shared premium endpoints are charged once and only while operating")
    func premiumStationUpkeepIsUnique() {
        let lines = [
            EconomyLineInput(
                id: UUID(uuidString: "13131313-1313-1313-1313-131313131301")!,
                originCRS: " aaa ",
                destinationCRS: "bbb",
                distanceMetres: 0,
                passengerJourneysPerDay: 0,
                railwayClass: .highSpeed
            ),
            EconomyLineInput(
                id: UUID(uuidString: "13131313-1313-1313-1313-131313131302")!,
                originCRS: " BBB ",
                destinationCRS: "ccc",
                distanceMetres: 0,
                passengerJourneysPerDay: 0,
                railwayClass: .highSpeed
            ),
            EconomyLineInput(
                id: UUID(uuidString: "13131313-1313-1313-1313-131313131303")!,
                originCRS: "CCC",
                destinationCRS: "DDD",
                distanceMetres: 0,
                passengerJourneysPerDay: 0,
                isOperating: false,
                railwayClass: .highSpeed
            ),
        ]
        let economy = OperatingEconomy()
        let snapshot = economy.evaluate(lines: lines, stationLevelsByCRS: [:])

        #expect(snapshot == economy.evaluate(
            lines: lines.reversed(),
            stationLevelsByCRS: [:]
        ))
        #expect(snapshot.premiumStationUpkeepPencePerDay == 1_500_000)
        #expect(snapshot.stationUpkeepPencePerDay == 1_575_000)
    }

    @Test("High-speed arithmetic saturates without changing conventional defaults")
    func highSpeedSaturation() throws {
        let id = UUID(uuidString: "14141414-1414-1414-1414-141414141414")!
        let input = EconomyLineInput(
            id: id,
            originCRS: "AAA",
            destinationCRS: "BBB",
            distanceMetres: .max,
            frequency: .quarterHourly,
            passengerJourneysPerDay: .max,
            railwayClass: .highSpeed
        )

        let snapshot = OperatingEconomy().evaluate(
            lines: [input],
            stationLevelsByCRS: [:]
        )
        let line = try #require(snapshot.lineSnapshot(for: id))

        #expect(line.revenuePencePerDay == .max)
        #expect(line.highSpeedFarePremiumPencePerDay > 0)
        #expect(line.energyCostPencePerDay == .max)
        #expect(line.rollingStockMaintenanceCostPencePerDay == .max)
        #expect(line.trackUpkeepPencePerDay == .max)
        #expect(line.totalOperatingCostPencePerDay == .max)
        #expect(snapshot.totalRevenuePencePerDay == .max)
        #expect(snapshot.totalOperatingCostPencePerDay == .max)
    }

    @Test("Metres convert to whole-pence kilometre charges without floating point")
    func metreConversionAndBothDirections() throws {
        let id = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let input = EconomyLineInput(
            id: id,
            originCRS: "AAA",
            destinationCRS: "BBB",
            distanceMetres: 1_500,
            frequency: .hourly,
            passengerJourneysPerDay: 1
        )

        let snapshot = OperatingEconomy().evaluate(
            lines: [input],
            stationLevelsByCRS: [:]
        )
        let line = try #require(snapshot.lineSnapshot(for: id))

        #expect(line.revenuePencePerDay == 218)
        #expect(line.energyCostPencePerDay == 16_200)
        #expect(line.rollingStockMaintenanceCostPencePerDay == 85_800)
        #expect(line.trainOperatingCostPencePerDay == 102_000)
        #expect(line.trackUpkeepPencePerDay == 18_000)
        #expect(line.totalOperatingCostPencePerDay == 120_000)
        #expect(line.operatingResultPencePerDay == -119_782)
        #expect(snapshot.stationUpkeepPencePerDay == 50_000)
    }

    @Test("Energy and rolling-stock maintenance rise with service frequency")
    func operatingCategoriesAreFrequencyMonotonic() throws {
        let id = UUID(uuidString: "29000000-0000-0000-0000-000000000001")!
        let economy = OperatingEconomy()

        func line(for frequency: ServiceFrequency) throws -> LineOperatingEconomySnapshot {
            let snapshot = economy.evaluate(
                lines: [
                    EconomyLineInput(
                        id: id,
                        originCRS: "AAA",
                        destinationCRS: "BBB",
                        distanceMetres: 10_000,
                        frequency: frequency,
                        passengerJourneysPerDay: 0
                    ),
                ],
                stationLevelsByCRS: [:]
            )
            return try #require(snapshot.lineSnapshot(for: id))
        }

        let hourly = try line(for: .hourly)
        let halfHourly = try line(for: .halfHourly)
        let quarterHourly = try line(for: .quarterHourly)

        #expect(hourly.energyCostPencePerDay == 108_000)
        #expect(hourly.rollingStockMaintenanceCostPencePerDay == 147_000)
        #expect(hourly.trainOperatingCostPencePerDay == 255_000)
        #expect(halfHourly.energyCostPencePerDay == 2 * hourly.energyCostPencePerDay)
        #expect(halfHourly.rollingStockMaintenanceCostPencePerDay
            == 2 * hourly.rollingStockMaintenanceCostPencePerDay)
        #expect(quarterHourly.energyCostPencePerDay
            == 2 * halfHourly.energyCostPencePerDay)
        #expect(quarterHourly.rollingStockMaintenanceCostPencePerDay
            == 2 * halfHourly.rollingStockMaintenanceCostPencePerDay)
        #expect(hourly.trackUpkeepPencePerDay == halfHourly.trackUpkeepPencePerDay)
        #expect(halfHourly.trackUpkeepPencePerDay == quarterHourly.trackUpkeepPencePerDay)
        #expect(hourly.totalOperatingCostPencePerDay
            < halfHourly.totalOperatingCostPencePerDay)
        #expect(halfHourly.totalOperatingCostPencePerDay
            < quarterHourly.totalOperatingCostPencePerDay)
    }

    @Test("Track capacity scales only track upkeep")
    func trackCapacityUpkeepIsMonotonic() throws {
        let id = UUID(uuidString: "29292929-2929-2929-2929-292929292929")!
        let economy = OperatingEconomy()

        func line(for capacity: TrackCapacity) throws -> LineOperatingEconomySnapshot {
            let snapshot = economy.evaluate(
                lines: [
                    EconomyLineInput(
                        id: id,
                        originCRS: "VIC",
                        destinationCRS: "BTN",
                        distanceMetres: 80_000,
                        frequency: .halfHourly,
                        trackCapacity: capacity,
                        passengerJourneysPerDay: 5_000
                    ),
                ],
                stationLevelsByCRS: [:]
            )
            return try #require(snapshot.lineSnapshot(for: id))
        }

        let single = try line(for: .singleTrack)
        let loop = try line(for: .passingLoop)
        let double = try line(for: .doubleTrack)

        #expect(single.trackUpkeepPencePerDay == 960_000)
        #expect(loop.trackUpkeepPencePerDay == 1_032_000)
        #expect(double.trackUpkeepPencePerDay == 1_776_000)
        #expect(single.trackUpkeepPencePerDay < loop.trackUpkeepPencePerDay)
        #expect(loop.trackUpkeepPencePerDay < double.trackUpkeepPencePerDay)
        #expect(single.revenuePencePerDay == loop.revenuePencePerDay)
        #expect(loop.revenuePencePerDay == double.revenuePencePerDay)
        #expect(single.energyCostPencePerDay == loop.energyCostPencePerDay)
        #expect(loop.energyCostPencePerDay == double.energyCostPencePerDay)
        #expect(single.rollingStockMaintenanceCostPencePerDay
            == loop.rollingStockMaintenanceCostPencePerDay)
        #expect(loop.rollingStockMaintenanceCostPencePerDay
            == double.rollingStockMaintenanceCostPencePerDay)
        #expect(single.trainOperatingCostPencePerDay == loop.trainOperatingCostPencePerDay)
        #expect(loop.trainOperatingCostPencePerDay == double.trainOperatingCostPencePerDay)
    }

    @Test("Track-capacity upkeep multiplication saturates")
    func trackCapacityUpkeepSaturates() throws {
        let id = UUID(uuidString: "2A2A2A2A-2A2A-2A2A-2A2A-2A2A2A2A2A2A")!
        let distanceMetres: Int64 = 500_000_000_000_000_000
        let economy = OperatingEconomy()

        func trackUpkeep(for capacity: TrackCapacity) throws -> Int64 {
            let snapshot = economy.evaluate(
                lines: [
                    EconomyLineInput(
                        id: id,
                        originCRS: "AAA",
                        destinationCRS: "BBB",
                        distanceMetres: distanceMetres,
                        trackCapacity: capacity,
                        passengerJourneysPerDay: 0
                    ),
                ],
                stationLevelsByCRS: [:]
            )
            return try #require(snapshot.lineSnapshot(for: id)).trackUpkeepPencePerDay
        }

        #expect(try trackUpkeep(for: .singleTrack) == 6_000_000_000_000_000_000)
        #expect(try trackUpkeep(for: .passingLoop) == 6_450_000_000_000_000_000)
        #expect(try trackUpkeep(for: .doubleTrack) == .max)
    }

    @Test("Every station level has its configured upkeep and each station is charged once")
    func uniqueStationUpkeepAndLevels() {
        let lines = [
            EconomyLineInput(
                id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
                originCRS: "A",
                destinationCRS: "B",
                distanceMetres: 0,
                passengerJourneysPerDay: 0
            ),
            EconomyLineInput(
                id: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
                originCRS: "C",
                destinationCRS: "D",
                distanceMetres: 0,
                passengerJourneysPerDay: 0
            ),
            EconomyLineInput(
                id: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!,
                originCRS: "E",
                destinationCRS: "F",
                distanceMetres: 0,
                passengerJourneysPerDay: 0
            ),
        ]
        let levels: [String: StationLevel] = [
            "A": .halt,
            "B": .localStation,
            "C": .townStation,
            "D": .majorStation,
            "E": .interchange,
            "F": .terminus,
        ]
        let economy = OperatingEconomy()
        let snapshot = economy.evaluate(lines: lines, stationLevelsByCRS: levels)

        #expect(snapshot == economy.evaluate(
            lines: lines.reversed(),
            stationLevelsByCRS: levels
        ))
        #expect(snapshot.lineSnapshotsByID.count == 3)
        #expect(snapshot.stationUpkeepPencePerDay == 1_475_000)
        #expect(snapshot.totalEnergyCostPencePerDay == 0)
        #expect(snapshot.totalRollingStockMaintenanceCostPencePerDay == 450_000)
        #expect(snapshot.totalOperatingCostPencePerDay == 1_925_000)
        #expect(snapshot.operatingResultPencePerDay == -1_925_000)
    }

    @Test("A shared station is not charged twice and CRS matching is normalized")
    func sharedStationUpkeepIsUnique() {
        let first = EconomyLineInput(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!,
            originCRS: " vic ",
            destinationCRS: "clj",
            distanceMetres: 0,
            passengerJourneysPerDay: 0
        )
        let second = EconomyLineInput(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000002")!,
            originCRS: "CLJ",
            destinationCRS: "ecr",
            distanceMetres: 0,
            passengerJourneysPerDay: 0
        )
        let levels: [String: StationLevel] = [
            " vic ": .localStation,
            "ClJ": .interchange,
            "ECR": .townStation,
        ]
        let economy = OperatingEconomy()
        let firstOrder = economy.evaluate(
            lines: [first, second],
            stationLevelsByCRS: levels
        )
        let secondOrder = economy.evaluate(
            lines: [second, first],
            stationLevelsByCRS: levels
        )

        #expect(firstOrder == secondOrder)
        #expect(firstOrder.stationUpkeepPencePerDay == 550_000)
    }

    @Test("Non-operating lines are zero and do not incur station upkeep")
    func nonOperatingLineIsZero() throws {
        let id = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let input = EconomyLineInput(
            id: id,
            originCRS: "VIC",
            destinationCRS: "BTN",
            distanceMetres: .max,
            frequency: .quarterHourly,
            passengerJourneysPerDay: .max,
            isOperating: false
        )

        let snapshot = OperatingEconomy().evaluate(
            lines: [input],
            stationLevelsByCRS: ["VIC": .terminus, "BTN": .terminus]
        )

        #expect(try #require(snapshot.lineSnapshot(for: id)) == .zero(id: id))
        #expect(snapshot.stationUpkeepPencePerDay == 0)
        #expect(snapshot.totalRevenuePencePerDay == 0)
        #expect(snapshot.totalOperatingCostPencePerDay == 0)
        #expect(snapshot.operatingResultPencePerDay == 0)
    }

    @Test("Large values saturate while a loss remains negative")
    func saturationAndNegativeResult() throws {
        let lossID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let lossInput = EconomyLineInput(
            id: lossID,
            originCRS: "AAA",
            destinationCRS: "BBB",
            distanceMetres: .max,
            frequency: .quarterHourly,
            passengerJourneysPerDay: 0
        )
        let saturatedLoss = OperatingEconomy().evaluate(
            lines: [lossInput],
            stationLevelsByCRS: [:]
        )
        let lossLine = try #require(saturatedLoss.lineSnapshot(for: lossID))

        #expect(lossLine.revenuePencePerDay == 0)
        #expect(lossLine.trainOperatingCostPencePerDay == .max)
        #expect(lossLine.trackUpkeepPencePerDay == .max)
        #expect(lossLine.totalOperatingCostPencePerDay == .max)
        #expect(lossLine.operatingResultPencePerDay == -Int64.max)
        #expect(saturatedLoss.totalOperatingCostPencePerDay == .max)
        #expect(saturatedLoss.operatingResultPencePerDay == -Int64.max)

        let revenueID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let saturatedRevenue = OperatingEconomy().evaluate(
            lines: [
                EconomyLineInput(
                    id: revenueID,
                    originCRS: "CCC",
                    destinationCRS: "DDD",
                    distanceMetres: .max,
                    frequency: .quarterHourly,
                    passengerJourneysPerDay: .max
                ),
            ],
            stationLevelsByCRS: [:]
        )
        #expect(try #require(saturatedRevenue.lineSnapshot(for: revenueID))
            .revenuePencePerDay == .max)
    }

    @Test("Duplicate line IDs are resolved deterministically")
    func duplicateIDsRemainInputOrderIndependent() {
        let id = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        let first = EconomyLineInput(
            id: id,
            originCRS: "AAA",
            destinationCRS: "BBB",
            distanceMetres: 10_000,
            frequency: .hourly,
            passengerJourneysPerDay: 100
        )
        let second = EconomyLineInput(
            id: id,
            originCRS: "CCC",
            destinationCRS: "DDD",
            distanceMetres: 20_000,
            frequency: .quarterHourly,
            passengerJourneysPerDay: 200
        )
        let economy = OperatingEconomy()

        #expect(economy.evaluate(
            lines: [first, second],
            stationLevelsByCRS: [:]
        ) == economy.evaluate(
            lines: [second, first],
            stationLevelsByCRS: [:]
        ))
    }

    @Test("The lifetime ledger derives a saturating operating result")
    func economyLedger() {
        #expect(EconomyLedger.zero == EconomyLedger())
        #expect(EconomyLedger(
            completedOperatingDays: 3,
            operatingDayProgress: 0.5,
            lifetimeRevenuePence: 100,
            lifetimeOperatingCostPence: 250
        ).lifetimeOperatingResultPence == -150)
        #expect(EconomyLedger(
            lifetimeRevenuePence: .min,
            lifetimeOperatingCostPence: .max
        ).lifetimeOperatingResultPence == .min)
        #expect(EconomyLedger(
            lifetimeRevenuePence: .max,
            lifetimeOperatingCostPence: .min
        ).lifetimeOperatingResultPence == .max)
    }
}
