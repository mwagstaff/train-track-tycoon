import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Passenger simulation")
struct PassengerSimulationTests {
    @Test("Known corridor estimate is stable")
    func knownCorridorEstimate() {
        let estimate = PassengerSimulation().estimate(
            originCRS: "VIC",
            destinationCRS: "BTN",
            distanceKilometres: 80,
            frequency: .halfHourly
        )

        #expect(estimate.potentialDailyJourneys == 7_360)
        #expect(estimate.attractedDailyJourneys == 5_152)
        #expect(estimate.passengersPerDay == 5_152)
        #expect(estimate.dailyCapacity == 17_280)
        #expect(estimate.journeyMinutes == 48)
        #expect(estimate.averageWaitMinutes == 15)
        #expect(estimate.demandServedRatio == 1)
        #expect(estimate.demandCapturedRatio == 0.7)
        #expect(abs(estimate.peakOccupancyRatio - 0.603_75) < 0.000_000_001)
        #expect(estimate.feedback == .goodService)
    }

    @Test("Frequency shortens waits and grows captured demand")
    func frequencyIsMonotonic() {
        let simulation = PassengerSimulation()
        let hourly = simulation.estimate(
            originCRS: "VIC",
            destinationCRS: "BTN",
            distanceKilometres: 80,
            frequency: .hourly
        )
        let halfHourly = simulation.estimate(
            originCRS: "VIC",
            destinationCRS: "BTN",
            distanceKilometres: 80,
            frequency: .halfHourly
        )
        let quarterHourly = simulation.estimate(
            originCRS: "VIC",
            destinationCRS: "BTN",
            distanceKilometres: 80,
            frequency: .quarterHourly
        )

        #expect(ServiceFrequency.hourly.departuresPerHour == 1)
        #expect(ServiceFrequency.halfHourly.departuresPerHour == 2)
        #expect(ServiceFrequency.quarterHourly.departuresPerHour == 4)
        #expect(ServiceFrequency.quarterHourly.visibleTrainCount == 4)
        #expect(hourly.averageWaitMinutes > halfHourly.averageWaitMinutes)
        #expect(halfHourly.averageWaitMinutes > quarterHourly.averageWaitMinutes)
        #expect(hourly.passengersPerDay <= halfHourly.passengersPerDay)
        #expect(halfHourly.passengersPerDay <= quarterHourly.passengersPerDay)
        #expect(hourly.capacityPressure > halfHourly.capacityPressure)
        #expect(halfHourly.capacityPressure > quarterHourly.capacityPressure)
        #expect(hourly.feedback == .capacityConstrained)
        #expect(halfHourly.feedback == .goodService)
    }

    @Test("Journey-time multipliers change journey time and attraction monotonically")
    func journeyTimeMultiplierIsMonotonic() {
        let id = UUID(uuidString: "10101010-1010-1010-1010-101010101010")!
        let simulation = PassengerSimulation()

        func estimate(multiplier: Double) -> PassengerLineSnapshot {
            simulation.estimate(for: PassengerLineInput(
                id: id,
                originCRS: "VIC",
                destinationCRS: "BTN",
                distanceKilometres: 80,
                frequency: .halfHourly,
                journeyTimeMultiplier: multiplier
            ))
        }

        let faster = estimate(multiplier: 0.75)
        let baseline = estimate(multiplier: 1)
        let slower = estimate(multiplier: 1.5)

        #expect(abs(faster.journeyMinutes - 36) < 0.000_000_001)
        #expect(abs(baseline.journeyMinutes - 48) < 0.000_000_001)
        #expect(abs(slower.journeyMinutes - 72) < 0.000_000_001)
        #expect(faster.potentialDailyJourneys == baseline.potentialDailyJourneys)
        #expect(baseline.potentialDailyJourneys == slower.potentialDailyJourneys)
        #expect(faster.attractedDailyJourneys > baseline.attractedDailyJourneys)
        #expect(baseline.attractedDailyJourneys > slower.attractedDailyJourneys)
        #expect(faster.passengersPerDay > baseline.passengersPerDay)
        #expect(baseline.passengersPerDay > slower.passengersPerDay)
    }

    @Test("Duplicate services use a departures-weighted journey multiplier in either order")
    func duplicatePairJourneyMultiplierIsWeightedAndOrderIndependent() throws {
        let hourlyID = UUID(uuidString: "12121212-1212-1212-1212-121212121212")!
        let frequentID = UUID(uuidString: "13131313-1313-1313-1313-131313131313")!
        let hourly = PassengerLineInput(
            id: hourlyID,
            originCRS: "VIC",
            destinationCRS: "BTN",
            distanceKilometres: 80,
            frequency: .hourly,
            journeyTimeMultiplier: 0.5
        )
        let frequent = PassengerLineInput(
            id: frequentID,
            originCRS: "BTN",
            destinationCRS: "VIC",
            distanceKilometres: 80,
            frequency: .quarterHourly,
            journeyTimeMultiplier: 1.5
        )
        let simulation = PassengerSimulation()

        let network = simulation.evaluate([hourly, frequent])

        // (1 departure * 0.5 + 4 departures * 1.5) / 5 departures = 1.3.
        #expect(network == simulation.evaluate([frequent, hourly]))
        #expect(abs(try #require(network.line(for: hourlyID)).journeyMinutes - 62.4)
            < 0.000_000_001)
        #expect(abs(try #require(network.line(for: frequentID)).journeyMinutes - 62.4)
            < 0.000_000_001)
    }

    @Test("Invalid journey-time multipliers fall back to one in direct-service groups")
    func invalidJourneyTimeMultipliersFallBackToOne() {
        let testedID = UUID(uuidString: "14141414-1414-1414-1414-141414141414")!
        let companion = PassengerLineInput(
            id: UUID(uuidString: "15151515-1515-1515-1515-151515151515")!,
            originCRS: "BTN",
            destinationCRS: "VIC",
            distanceKilometres: 80,
            frequency: .quarterHourly,
            journeyTimeMultiplier: 1.5
        )
        let simulation = PassengerSimulation()

        func network(multiplier: Double) -> NetworkPassengerSnapshot {
            simulation.evaluate([
                PassengerLineInput(
                    id: testedID,
                    originCRS: "VIC",
                    destinationCRS: "BTN",
                    distanceKilometres: 80,
                    frequency: .hourly,
                    journeyTimeMultiplier: multiplier
                ),
                companion,
            ])
        }

        let baseline = network(multiplier: 1)
        for invalid in [0, -1, Double.nan, Double.infinity, -Double.infinity] {
            #expect(network(multiplier: invalid) == baseline)
        }
    }

    @Test("Distance reduces latent demand and stronger station profiles increase it")
    func demandInputsAreMonotonic() {
        let simulation = PassengerSimulation()
        let shortFallback = simulation.estimate(
            originCRS: "AAA",
            destinationCRS: "BBB",
            distanceKilometres: 10
        )
        let longFallback = simulation.estimate(
            originCRS: "AAA",
            destinationCRS: "BBB",
            distanceKilometres: 100
        )
        let strongStations = simulation.estimate(
            originCRS: "VIC",
            destinationCRS: "LBG",
            distanceKilometres: 10
        )

        #expect(shortFallback.potentialDailyJourneys > longFallback.potentialDailyJourneys)
        #expect(strongStations.potentialDailyJourneys
            > shortFallback.potentialDailyJourneys)
    }

    @Test("Capacity never carries more than seats or attracted demand")
    func capacityConstraint() {
        let estimate = PassengerSimulation().estimate(
            originCRS: "VIC",
            destinationCRS: "BTN",
            distanceKilometres: 80,
            frequency: .hourly
        )

        #expect(estimate.capacityPressure > 1)
        #expect(estimate.peakOccupancyRatio == 1)
        #expect(estimate.passengersPerDay < estimate.attractedDailyJourneys)
        #expect(estimate.passengersPerDay <= estimate.dailyCapacity)
        #expect(estimate.demandServedRatio < 1)
        #expect(estimate.feedback == .capacityConstrained)
    }

    @Test("Duplicate direct lines share one market deterministically")
    func duplicatePairSharesDemand() throws {
        let firstID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let secondID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let first = PassengerLineInput(
            id: firstID,
            originCRS: "VIC",
            destinationCRS: "BTN",
            distanceKilometres: 80,
            frequency: .halfHourly
        )
        let second = PassengerLineInput(
            id: secondID,
            originCRS: " btn ",
            destinationCRS: "vic",
            distanceKilometres: 80,
            frequency: .halfHourly
        )
        let simulation = PassengerSimulation()

        let network = simulation.evaluate([first, second])
        let reversed = simulation.evaluate([second, first])
        let combinedMarket = simulation.estimate(
            originCRS: "VIC",
            destinationCRS: "BTN",
            distanceKilometres: 80,
            frequency: .quarterHourly
        )
        let firstResult = try #require(network.line(for: firstID))
        let secondResult = try #require(network.line(for: secondID))

        #expect(network == reversed)
        #expect(network.passengersPerDay == combinedMarket.passengersPerDay)
        #expect(firstResult.passengersPerDay + secondResult.passengersPerDay
            == combinedMarket.passengersPerDay)
        #expect(firstResult.potentialDailyJourneys + secondResult.potentialDailyJourneys
            == combinedMarket.potentialDailyJourneys)
        #expect(abs(firstResult.passengersPerDay - secondResult.passengersPerDay) <= 1)
        #expect(network.potentialDailyJourneys == combinedMarket.potentialDailyJourneys)
        #expect(network.unservedDailyJourneys
            == combinedMarket.potentialDailyJourneys - combinedMarket.passengersPerDay)
        #expect(abs(network.averagePeakOccupancyRatio
            - combinedMarket.peakOccupancyRatio) < 0.000_000_001)
        #expect(network.station(forCRS: " vic ")?.passengersPerDay
            == combinedMarket.passengersPerDay)
        #expect(network.station(forCRS: "BTN")?.connectedLineCount == 2)
        #expect(network.station(forCRS: "BTN")?.connectedDestinationCount == 1)
        #expect(network.station(forCRS: "BTN")?.busiestDirectDestinationCRS == "VIC")
    }

    @Test("Network totals and station activity do not depend on input order")
    func networkAggregationIsOrderIndependent() throws {
        let first = PassengerLineInput(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            originCRS: "VIC",
            destinationCRS: "CLJ",
            distanceKilometres: 6,
            frequency: .hourly
        )
        let second = PassengerLineInput(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            originCRS: "CLJ",
            destinationCRS: "ECR",
            distanceKilometres: 17,
            frequency: .halfHourly
        )
        let simulation = PassengerSimulation()
        let network = simulation.evaluate([first, second])

        #expect(network == simulation.evaluate([second, first]))
        #expect(network.passengersPerDay
            == network.lineSnapshots.reduce(0) { $0 + $1.passengersPerDay })
        let capacity = network.lineSnapshots.reduce(0) { $0 + $1.dailyCapacity }
        let weightedPeakLoad = network.lineSnapshots.reduce(0.0) {
            $0 + $1.peakOccupancyRatio * Double($1.dailyCapacity)
        } / Double(capacity)
        #expect(abs(network.averagePeakOccupancyRatio - weightedPeakLoad)
            < 0.000_000_001)

        let clapham = try #require(network.station(forCRS: "CLJ"))
        #expect(clapham.connectedLineCount == 2)
        #expect(clapham.passengersPerDay
            == network.line(for: first.id)!.passengersPerDay
                + network.line(for: second.id)!.passengersPerDay)
        #expect(clapham.potentialDailyJourneys >= clapham.servedDailyJourneys)
        #expect(clapham.unservedDailyJourneys
            == clapham.potentialDailyJourneys - clapham.servedDailyJourneys)
        #expect(clapham.connectedDestinationCount == 2)
        #expect(clapham.busiestDirectDestinationCRS != nil)
        #expect(clapham.activity > 0)
        #expect(clapham.activityLevel >= .active)
    }

    @Test("Busiest destination ties use the CRS as a stable tiebreaker")
    func busiestDestinationTieBreak() throws {
        let toAlpha = PassengerLineInput(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            originCRS: "HUB",
            destinationCRS: "AAA",
            distanceKilometres: 20
        )
        let toBeta = PassengerLineInput(
            id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
            originCRS: "HUB",
            destinationCRS: "BBB",
            distanceKilometres: 20
        )

        let station = try #require(
            PassengerSimulation().evaluate([toBeta, toAlpha]).station(forCRS: "HUB")
        )

        #expect(station.connectedDestinationCount == 2)
        #expect(station.busiestDirectDestinationCRS == "AAA")
    }

    @Test("Unknown stations use a stable fallback and invalid lines stay inert")
    func fallbackAndInvalidInputs() throws {
        let simulation = PassengerSimulation()
        let firstFallback = simulation.estimate(
            originCRS: "AAA",
            destinationCRS: "BBB",
            distanceKilometres: 20
        )
        let secondFallback = simulation.estimate(
            originCRS: "XXX",
            destinationCRS: "YYY",
            distanceKilometres: 20
        )
        let invalid = simulation.estimate(
            originCRS: "AAA",
            destinationCRS: "AAA",
            distanceKilometres: .infinity
        )
        let buildingID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let building = PassengerLineInput(
            id: buildingID,
            originCRS: "AAA",
            destinationCRS: "BBB",
            distanceKilometres: 20,
            isOperating: false
        )
        let network = simulation.evaluate([building])
        let buildingResult = try #require(network.line(for: buildingID))

        #expect(firstFallback == secondFallback)
        #expect(firstFallback.passengersPerDay > 0)
        #expect(invalid == .zero)
        #expect(buildingResult.potentialDailyJourneys == firstFallback.potentialDailyJourneys)
        #expect(buildingResult.passengersPerDay == 0)
        #expect(buildingResult.feedback == .notOperating)
        #expect(network.passengersPerDay == 0)
        #expect(network.stationsByCRS.isEmpty)
    }
}
