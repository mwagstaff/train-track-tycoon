import Testing
@testable import TrainTrackTycoon

@Suite("Station capacity presentation")
struct StationCapacityPresentationTests {
    @Test("Station presentation derives finite utilization and next-tier throughput")
    func stationPresentation() {
        let presentation = StationCapacityUIPresentation(
            platformCount: 1,
            scheduledTrainCallsPerHour: 8,
            effectiveTrainCallsPerHour: 4,
            trainCallCapacityPerHour: 4,
            isConstrained: true,
            nextLevelName: "Local Station",
            nextLevelPlatformCount: 2
        )

        #expect(presentation.isConstrained)
        #expect(presentation.utilization == 1)
        #expect(presentation.nextLevelTrainCallCapacityPerHour == 8)
    }

    @Test("Malformed station values are safe and never create a false warning")
    func malformedStationPresentation() {
        let presentation = StationCapacityUIPresentation(
            platformCount: -1,
            scheduledTrainCallsPerHour: .infinity,
            effectiveTrainCallsPerHour: .nan,
            trainCallCapacityPerHour: -.infinity,
            isConstrained: true,
            nextLevelName: nil,
            nextLevelPlatformCount: nil
        )

        #expect(presentation.platformCount == 0)
        #expect(presentation.scheduledTrainCallsPerHour == 0)
        #expect(presentation.effectiveTrainCallsPerHour == 0)
        #expect(presentation.trainCallCapacityPerHour == 0)
        #expect(presentation.utilization == 0)
        #expect(!presentation.isConstrained)
    }

    @Test("Line presentation identifies limiting stations in stable order")
    func linePresentation() {
        let presentation = LineStationCapacityUIPresentation(
            scheduledDeparturesPerHour: 4,
            effectiveDeparturesPerHour: 2,
            limitingStationNames: ["Purley", "East Croydon", "Purley", ""],
            isOperating: true
        )

        #expect(presentation.isConstrained)
        #expect(presentation.limitingStationNames == ["East Croydon", "Purley"])
        #expect(presentation.limitingStationsText == "East Croydon and Purley")
    }

    @Test("A nonoperating service does not report a live bottleneck")
    func nonoperatingLine() {
        let presentation = LineStationCapacityUIPresentation(
            scheduledDeparturesPerHour: 4,
            effectiveDeparturesPerHour: 0,
            limitingStationNames: ["Purley"],
            isOperating: false
        )

        #expect(!presentation.isConstrained)
    }
}
