import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Purchased rolling-stock formations")
struct RollingStockFormationTests {
    private let formationPolicy = RollingStockFormationPolicy()

    @Test("Even formations expose forty seats per carriage")
    func capacitiesMatchCarriageCounts() {
        #expect(RollingStockFormation.twoCar.seatsPerTrain == 80)
        #expect(RollingStockFormation.sixCar.seatsPerTrain == 240)
        #expect(RollingStockFormation.twelveCar.seatsPerTrain == 480)
        #expect(RollingStockFormation.legacyBaseline == .sixCar)
        #expect(RollingStockFormation.allCases.map(\.carriageCount)
            == [2, 4, 6, 8, 10, 12])
    }

    @Test("High-speed rail supports six to twelve cars and clamps legacy short trains")
    func supportedNextAndClamp() {
        #expect(RollingStockFormation.supported(for: .conventional)
            == RollingStockFormation.allCases)
        #expect(RollingStockFormation.supported(for: .highSpeed)
            == [.sixCar, .eightCar, .tenCar, .twelveCar])
        #expect(RollingStockFormation.twoCar.clamped(for: .highSpeed) == .sixCar)
        #expect(RollingStockFormation.sixCar.clamped(for: .highSpeed) == .sixCar)
        #expect(RollingStockFormation.sixCar.next(for: .conventional) == .eightCar)
        #expect(RollingStockFormation.twelveCar.next(for: .conventional) == nil)
        #expect(formationPolicy.next(after: .fourCar, for: .highSpeed) == .sixCar)
    }

    @Test("Recommendations target eighty percent peak loading")
    func demandRecommendation() {
        // Two peak departures provide target capacities of 128, 256 and 384 riders.
        #expect(formationPolicy.recommend(
            attractedPeakDemand: 128,
            departuresDuringPeak: 2,
            railwayClass: .conventional
        ) == .twoCar)
        #expect(formationPolicy.recommend(
            attractedPeakDemand: 129,
            departuresDuringPeak: 2,
            railwayClass: .conventional
        ) == .fourCar)
        #expect(formationPolicy.recommend(
            attractedPeakDemand: 1,
            departuresDuringPeak: 1,
            railwayClass: .highSpeed
        ) == .sixCar)
    }

    @Test("Recommendations safely bound zero and extreme demand")
    func recommendationExtremes() {
        #expect(formationPolicy.recommend(
            attractedPeakDemand: 0,
            departuresDuringPeak: Int.max,
            railwayClass: .conventional
        ) == .twoCar)
        #expect(formationPolicy.recommend(
            attractedPeakDemand: Int.max,
            departuresDuringPeak: 0,
            railwayClass: .conventional
        ) == .twelveCar)
        #expect(formationPolicy.recommend(
            attractedPeakDemand: Int.max,
            departuresDuringPeak: Int.max,
            railwayClass: .conventional
        ) == .twoCar)
    }

    @Test("An owned formation renders exactly and never drifts with demand")
    func purchasedFormationIsAuthoritative() {
        let policy = TrainFormationPolicy()
        let quiet = policy.evaluate(
            serviceRole: .local,
            railwayClass: .conventional,
            routeDistanceKilometres: 2,
            peakOccupancyRatio: 0,
            nominalTrainCapacity: Int.max,
            purchasedFormation: .tenCar
        )
        let busy = policy.evaluate(
            serviceRole: .express,
            railwayClass: .highSpeed,
            routeDistanceKilometres: 1_000,
            peakOccupancyRatio: 1,
            nominalTrainCapacity: 1,
            purchasedFormation: .tenCar
        )

        #expect(quiet.carriageCount == 10)
        #expect(busy.carriageCount == 10)
        #expect(quiet.estimatedPeakPassengers == 0)
        #expect(busy.estimatedPeakPassengers == 400)
    }
}

@Suite("Formation-aware passenger capacity")
struct FormationPassengerCapacityTests {
    private let simulation = PassengerSimulation()
    private let firstID = UUID(uuidString: "C1000000-0000-0000-0000-000000000001")!
    private let secondID = UUID(uuidString: "C2000000-0000-0000-0000-000000000002")!

    @Test("Per-train capacity follows two, six and twelve-car formations")
    func directCapacityUsesFormation() {
        let twoCar = estimate(capacity: RollingStockFormation.twoCar.seatsPerTrain)
        let legacy = estimate(capacity: RollingStockFormation.sixCar.seatsPerTrain)
        let twelveCar = estimate(capacity: RollingStockFormation.twelveCar.seatsPerTrain)

        #expect(twoCar.dailyCapacity == 5_760)
        #expect(legacy.dailyCapacity == 17_280)
        #expect(twelveCar.dailyCapacity == 34_560)
        #expect(twoCar.passengersPerDay <= twoCar.dailyCapacity)
        #expect(twoCar.passengersPerDay < legacy.passengersPerDay)
        #expect(legacy.passengersPerDay <= twelveCar.passengersPerDay)
    }

    @Test("The default six-car capacity preserves the legacy golden forecast")
    func legacyGoldenIsUnchanged() {
        let estimate = simulation.estimate(
            originCRS: "VIC",
            destinationCRS: "BTN",
            distanceKilometres: 80,
            frequency: .halfHourly
        )

        #expect(estimate.potentialDailyJourneys == 7_360)
        #expect(estimate.attractedDailyJourneys == 5_152)
        #expect(estimate.passengersPerDay == 5_152)
        #expect(estimate.dailyCapacity == 17_280)
        #expect(abs(estimate.peakOccupancyRatio - 0.603_75) < 0.000_000_001)
    }

    @Test("Different-capacity duplicate services allocate riders deterministically")
    func duplicateCapacitiesAreOrderIndependent() throws {
        let short = line(
            id: firstID,
            origin: "VIC",
            destination: "BTN",
            capacity: RollingStockFormation.twoCar.seatsPerTrain
        )
        let long = line(
            id: secondID,
            origin: "BTN",
            destination: "VIC",
            capacity: RollingStockFormation.twelveCar.seatsPerTrain
        )

        let network = simulation.evaluate([short, long])
        let reversed = simulation.evaluate([long, short])
        let shortResult = try #require(network.line(for: firstID))
        let longResult = try #require(network.line(for: secondID))

        #expect(network == reversed)
        #expect(network.passengersPerDay
            == shortResult.passengersPerDay + longResult.passengersPerDay)
        #expect(shortResult.dailyCapacity == 5_760)
        #expect(longResult.dailyCapacity == 34_560)
        #expect(shortResult.passengersPerDay <= shortResult.dailyCapacity)
        #expect(longResult.passengersPerDay <= longResult.dailyCapacity)
        #expect(shortResult.passengersPerDay <= shortResult.attractedDailyJourneys)
        #expect(longResult.passengersPerDay <= longResult.attractedDailyJourneys)
        #expect(longResult.passengersPerDay > shortResult.passengersPerDay)
    }

    @Test("The shorter connecting leg is the formation bottleneck")
    func connectingCapacityUsesBothLegs() throws {
        let constrained = simulation.evaluate([
            line(
                id: firstID,
                origin: "VIC",
                destination: "CLJ",
                capacity: RollingStockFormation.twoCar.seatsPerTrain
            ),
            line(
                id: secondID,
                origin: "CLJ",
                destination: "BTN",
                capacity: RollingStockFormation.twelveCar.seatsPerTrain
            ),
        ])
        let roomy = simulation.evaluate([
            line(
                id: firstID,
                origin: "VIC",
                destination: "CLJ",
                capacity: RollingStockFormation.twelveCar.seatsPerTrain
            ),
            line(
                id: secondID,
                origin: "CLJ",
                destination: "BTN",
                capacity: RollingStockFormation.twelveCar.seatsPerTrain
            ),
        ])
        let constrainedConnection = try #require(
            constrained.connectingJourneySnapshots.first
        )
        let roomyConnection = try #require(roomy.connectingJourneySnapshots.first)

        #expect(constrainedConnection.passengersPerDay < roomyConnection.passengersPerDay)
        #expect(constrained.lineSnapshots.allSatisfy {
            $0.passengersPerDay <= $0.dailyCapacity
        })
        #expect(constrainedConnection.passengersPerDay
            == constrained.line(for: firstID)?.connectingPassengersPerDay)
        #expect(constrainedConnection.passengersPerDay
            == constrained.line(for: secondID)?.connectingPassengersPerDay)
    }

    @Test("Malformed and extreme capacities are bounded without overflow")
    func capacityExtremes() throws {
        let zero = simulation.evaluate([
            line(id: firstID, origin: "AAA", destination: "BBB", capacity: -1),
        ])
        let zeroLine = try #require(zero.line(for: firstID))
        #expect(zeroLine.dailyCapacity == 0)
        #expect(zeroLine.passengersPerDay == 0)

        let hugeFirst = line(
            id: firstID,
            origin: "AAA",
            destination: "BBB",
            capacity: Int.max
        )
        let hugeSecond = line(
            id: secondID,
            origin: "BBB",
            destination: "AAA",
            capacity: Int.max
        )
        let huge = simulation.evaluate([hugeFirst, hugeSecond])
        #expect(huge == simulation.evaluate([hugeSecond, hugeFirst]))
        #expect(huge.lineSnapshots.allSatisfy {
            $0.dailyCapacity >= 0
                && $0.passengersPerDay >= 0
                && $0.passengersPerDay <= $0.dailyCapacity
                && $0.peakOccupancyRatio.isFinite
                && $0.capacityPressure.isFinite
        })
    }

    private func estimate(capacity: Int) -> PassengerDemandEstimate {
        simulation.estimate(
            originCRS: "VIC",
            destinationCRS: "BTN",
            distanceKilometres: 80,
            frequency: .halfHourly,
            capacityPerTrain: capacity
        )
    }

    private func line(
        id: UUID,
        origin: String,
        destination: String,
        capacity: Int
    ) -> PassengerLineInput {
        PassengerLineInput(
            id: id,
            originCRS: origin,
            destinationCRS: destination,
            distanceKilometres: 80,
            frequency: .halfHourly,
            capacityPerTrain: capacity
        )
    }
}
