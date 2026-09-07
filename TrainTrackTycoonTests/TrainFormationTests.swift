import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Train formations")
struct TrainFormationTests {
    private let policy = TrainFormationPolicy()

    @Test("A short lightly used local service has two carriages")
    func shortLightLocalFormation() {
        let formation = policy.evaluate(
            serviceRole: .local,
            railwayClass: .conventional,
            routeDistanceKilometres: 5,
            peakOccupancyRatio: 0.05,
            nominalTrainCapacity: 240
        )

        #expect(formation.carriageCount == 2)
        #expect(formation.estimatedPeakPassengers == 12)
        #expect(formation.peakOccupancyRatio == 0.05)
    }

    @Test("A long fully used express service has twelve carriages")
    func longFullExpressFormation() {
        let formation = policy.evaluate(
            serviceRole: .express,
            railwayClass: .conventional,
            routeDistanceKilometres: 250,
            peakOccupancyRatio: 1,
            nominalTrainCapacity: 240
        )

        #expect(formation.carriageCount == 12)
        #expect(formation.estimatedPeakPassengers == 240)
    }

    @Test("High-speed trains retain a substantial minimum formation")
    func highSpeedMinimumFormation() {
        let formation = policy.evaluate(
            serviceRole: .express,
            railwayClass: .highSpeed,
            routeDistanceKilometres: 0,
            peakOccupancyRatio: 0,
            nominalTrainCapacity: 240
        )

        #expect(formation.carriageCount == 6)
        #expect(formation.estimatedPeakPassengers == 0)
    }

    @Test("Formation length increases monotonically with passenger load and distance")
    func monotonicFormationLength() {
        let occupancies = [0.0, 0.25, 0.5, 0.75, 1.0]
        let distances = [0.0, 50, 100, 175, 250]

        let byLoad = occupancies.map { occupancy in
            policy.evaluate(
                serviceRole: .express,
                railwayClass: .conventional,
                routeDistanceKilometres: 100,
                peakOccupancyRatio: occupancy,
                nominalTrainCapacity: 240
            ).carriageCount
        }
        let byDistance = distances.map { distance in
            policy.evaluate(
                serviceRole: .express,
                railwayClass: .conventional,
                routeDistanceKilometres: distance,
                peakOccupancyRatio: 0.6,
                nominalTrainCapacity: 240
            ).carriageCount
        }

        #expect(zip(byLoad, byLoad.dropFirst()).allSatisfy { pair in
            pair.0 <= pair.1
        })
        #expect(zip(byDistance, byDistance.dropFirst()).allSatisfy { pair in
            pair.0 <= pair.1
        })
    }

    @Test("Every service produces an even carriage count inside its supported range")
    func supportedFormationBounds() {
        let inputs: [(TrainServiceRole, RailwayClass, ClosedRange<Int>)] = [
            (.local, .conventional, 2...6),
            (.express, .conventional, 4...12),
            (.local, .highSpeed, 6...12),
            (.express, .highSpeed, 6...12),
        ]

        for (role, railwayClass, expectedRange) in inputs {
            for occupancy in [-1.0, 0, 0.33, 0.66, 1, 2, .nan, .infinity] {
                for distance in [-1.0, 0, 20, 100, 500, .nan, .infinity] {
                    let count = policy.evaluate(
                        serviceRole: role,
                        railwayClass: railwayClass,
                        routeDistanceKilometres: distance,
                        peakOccupancyRatio: occupancy,
                        nominalTrainCapacity: 240
                    ).carriageCount

                    #expect(expectedRange.contains(count))
                    #expect(count.isMultiple(of: 2))
                }
            }
        }
    }

    @Test("Malformed demand inputs normalize safely")
    func invalidDemandInputs() {
        let invalid = policy.evaluate(
            serviceRole: .local,
            railwayClass: .conventional,
            routeDistanceKilometres: .nan,
            peakOccupancyRatio: .infinity,
            nominalTrainCapacity: -1
        )
        let overCapacity = policy.evaluate(
            serviceRole: .express,
            railwayClass: .conventional,
            routeDistanceKilometres: -10,
            peakOccupancyRatio: 4,
            nominalTrainCapacity: 240
        )
        let extremeCapacity = policy.evaluate(
            serviceRole: .express,
            railwayClass: .conventional,
            routeDistanceKilometres: 250,
            peakOccupancyRatio: 1,
            nominalTrainCapacity: .max
        )

        #expect(invalid.carriageCount == 2)
        #expect(invalid.estimatedPeakPassengers == 0)
        #expect(invalid.peakOccupancyRatio == 0)
        #expect(overCapacity.peakOccupancyRatio == 1)
        #expect(overCapacity.estimatedPeakPassengers == 240)
        #expect(extremeCapacity.estimatedPeakPassengers == .max)
    }

    @Test("Map detail uses nine and twelve kilometre hysteresis thresholds")
    func mapDetailHysteresis() {
        #expect(policy.detailLevel(
            after: .compact,
            cameraDistanceMetres: 9_001
        ) == .compact)
        #expect(policy.detailLevel(
            after: .compact,
            cameraDistanceMetres: 9_000
        ) == .formation)
        #expect(policy.detailLevel(
            after: .formation,
            cameraDistanceMetres: 10_500
        ) == .formation)
        #expect(policy.detailLevel(
            after: .formation,
            cameraDistanceMetres: 12_000
        ) == .compact)
        #expect(policy.detailLevel(
            after: .formation,
            cameraDistanceMetres: 11_999
        ) == .formation)
    }

    @Test("Invalid camera distances preserve the current detail representation")
    func invalidCameraDistances() {
        for distance in [-1.0, .nan, .infinity, -.infinity] {
            #expect(policy.detailLevel(
                after: .compact,
                cameraDistanceMetres: distance
            ) == .compact)
            #expect(policy.detailLevel(
                after: .formation,
                cameraDistanceMetres: distance
            ) == .formation)
        }
    }
}
