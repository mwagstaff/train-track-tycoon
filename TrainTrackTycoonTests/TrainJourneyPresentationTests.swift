import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Train journey presentation")
struct TrainJourneyPresentationTests {
    @Test("Fare revenue is divided across scheduled one-way terminal arrivals")
    func fareRevenuePerTerminalArrival() {
        let revenue = TrainJourneyPresentation.fareRevenuePencePerTerminalArrival(
            dailyRevenuePence: 72_000,
            frequency: .halfHourly,
            serviceHoursPerDay: 18,
            directionCount: 2
        )

        #expect(revenue == 1_000)
    }

    @Test("Multi-stop revenue is divided across endpoint and local station arrivals")
    func fareRevenuePerStationArrival() {
        let revenue = TrainJourneyPresentation.fareRevenuePencePerStationArrival(
            dailyRevenuePence: 108_000,
            endpointDeparturesPerHour: 2,
            intermediateDeparturesPerHour: 1,
            intermediateStationCount: 1,
            serviceHoursPerDay: 18,
            directionCount: 2
        )

        #expect(revenue == 1_000)
    }

    @Test("Overflowing or invalid multi-stop arrival schedules safely return zero")
    func invalidStationArrivalSchedulesReturnZero() {
        #expect(TrainJourneyPresentation.fareRevenuePencePerStationArrival(
            dailyRevenuePence: .max,
            endpointDeparturesPerHour: .max,
            intermediateDeparturesPerHour: .max,
            intermediateStationCount: .max,
            serviceHoursPerDay: .max,
            directionCount: .max
        ) == 0)
        #expect(TrainJourneyPresentation.fareRevenuePencePerStationArrival(
            dailyRevenuePence: 1_000,
            endpointDeparturesPerHour: 2,
            intermediateDeparturesPerHour: -1,
            intermediateStationCount: 1,
            serviceHoursPerDay: 18,
            directionCount: 2
        ) == 0)
    }

    @Test("Fare allocation uses deterministic whole-pence truncation")
    func fareRevenueTruncatesFractionalPence() {
        let revenue = TrainJourneyPresentation.fareRevenuePencePerTerminalArrival(
            dailyRevenuePence: 1_000,
            departuresPerHour: 3,
            serviceHoursPerDay: 7,
            directionCount: 2
        )

        #expect(revenue == 23)
    }

    @Test("Invalid fare or schedule inputs safely return zero")
    func invalidFareInputsReturnZero() {
        let cases: [(Int64, Int, Int64, Int64)] = [
            (-1 as Int64, 2, 18 as Int64, 2 as Int64),
            (0 as Int64, 2, 18 as Int64, 2 as Int64),
            (1_000 as Int64, 0, 18 as Int64, 2 as Int64),
            (1_000 as Int64, -1, 18 as Int64, 2 as Int64),
            (1_000 as Int64, 2, 0 as Int64, 2 as Int64),
            (1_000 as Int64, 2, -1 as Int64, 2 as Int64),
            (1_000 as Int64, 2, 18 as Int64, 0 as Int64),
            (1_000 as Int64, 2, 18 as Int64, -1 as Int64),
        ]

        for (dailyRevenue, departures, serviceHours, directions) in cases {
            #expect(
                TrainJourneyPresentation.fareRevenuePencePerTerminalArrival(
                    dailyRevenuePence: dailyRevenue,
                    departuresPerHour: departures,
                    serviceHoursPerDay: serviceHours,
                    directionCount: directions
                ) == 0
            )
        }
    }

    @Test("An overflowing scheduled-arrival count safely returns zero")
    func overflowingScheduleReturnsZero() {
        let revenue = TrainJourneyPresentation.fareRevenuePencePerTerminalArrival(
            dailyRevenuePence: .max,
            departuresPerHour: .max,
            serviceHoursPerDay: .max,
            directionCount: .max
        )

        #expect(revenue == 0)
    }

    @Test("A maximum valid fare remains representable")
    func maximumFareRemainsRepresentable() {
        let revenue = TrainJourneyPresentation.fareRevenuePencePerTerminalArrival(
            dailyRevenuePence: .max,
            departuresPerHour: 1,
            serviceHoursPerDay: 1,
            directionCount: 1
        )

        #expect(revenue == .max)
    }

    @Test("Horn cadence is stable and exactly one in every eight arrivals")
    func hornCadenceIsStableAndSparse() throws {
        let trainID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let firstRun = (1...80).compactMap { ordinal -> UInt64? in
            let ordinal = UInt64(ordinal)
            return TrainJourneyPresentation.shouldSoundHorn(
                trainID: trainID,
                arrivalOrdinal: ordinal
            ) ? ordinal : nil
        }
        let secondRun = (1...80).compactMap { ordinal -> UInt64? in
            let ordinal = UInt64(ordinal)
            return TrainJourneyPresentation.shouldSoundHorn(
                trainID: trainID,
                arrivalOrdinal: ordinal
            ) ? ordinal : nil
        }

        #expect(firstRun == secondRun)
        let firstHorn = try #require(firstRun.first)
        #expect(firstHorn >= TrainJourneyPresentation.earliestHornArrival)
        #expect(
            firstHorn
                < TrainJourneyPresentation.earliestHornArrival
                    + TrainJourneyPresentation.hornIntervalArrivals
        )
        #expect(
            zip(firstRun, firstRun.dropFirst()).allSatisfy { previous, next in
                next - previous == TrainJourneyPresentation.hornIntervalArrivals
            }
        )
        #expect((9...10).contains(firstRun.count))
    }

    @Test("Stable UUID phases stagger different trains")
    func uuidPhasesStaggerTrains() throws {
        let firstTrainID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        )
        let secondTrainID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")
        )
        let firstTrainHorns = (1...32).filter {
            TrainJourneyPresentation.shouldSoundHorn(
                trainID: firstTrainID,
                arrivalOrdinal: UInt64($0)
            )
        }
        let secondTrainHorns = (1...32).filter {
            TrainJourneyPresentation.shouldSoundHorn(
                trainID: secondTrainID,
                arrivalOrdinal: UInt64($0)
            )
        }

        #expect(firstTrainHorns != secondTrainHorns)
    }

    @Test("A zero ordinal never sounds and the maximum ordinal is safe")
    func hornOrdinalBoundaries() throws {
        let trainID = try #require(UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"))

        #expect(
            !TrainJourneyPresentation.shouldSoundHorn(
                trainID: trainID,
                arrivalOrdinal: 0
            )
        )
        let firstEvaluation = TrainJourneyPresentation.shouldSoundHorn(
            trainID: trainID,
            arrivalOrdinal: .max
        )
        let secondEvaluation = TrainJourneyPresentation.shouldSoundHorn(
            trainID: trainID,
            arrivalOrdinal: .max
        )
        #expect(firstEvaluation == secondEvaluation)
    }
}
