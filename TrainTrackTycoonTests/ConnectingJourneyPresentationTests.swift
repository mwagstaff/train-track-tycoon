import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Connecting journey presentation")
struct ConnectingJourneyPresentationTests {
    @Test("Line rider mix normalizes invalid counts and stays hidden without transfers")
    func lineRiderMixNormalization() {
        let directOnly = ConnectingRidersUIPresentation(
            directRidersPerDay: -40,
            connectingRidersPerDay: -10
        )

        #expect(directOnly.directRidersPerDay == 0)
        #expect(directOnly.connectingRidersPerDay == 0)
        #expect(directOnly.totalRidersPerDay == 0)
        #expect(directOnly.connectingSharePercentage == 0)
        #expect(!directOnly.shouldShow)
    }

    @Test("Line rider mix reports a rounded connecting share")
    func lineRiderMixShare() {
        let mix = ConnectingRidersUIPresentation(
            directRidersPerDay: 7_500,
            connectingRidersPerDay: 2_500
        )

        #expect(mix.totalRidersPerDay == 10_000)
        #expect(mix.connectingSharePercentage == 25)
        #expect(mix.shouldShow)
    }

    @Test("Line rider total saturates safely at the integer limit")
    func lineRiderMixOverflow() {
        let mix = ConnectingRidersUIPresentation(
            directRidersPerDay: .max,
            connectingRidersPerDay: 1
        )

        #expect(mix.totalRidersPerDay == .max)
        #expect((0...100).contains(mix.connectingSharePercentage))
    }

    @Test("Interchange panel appears only for positive unique transfer demand")
    func interchangeVisibility() {
        let empty = InterchangeDemandUIPresentation(transferJourneysPerDay: -1)
        let active = InterchangeDemandUIPresentation(transferJourneysPerDay: 875)

        #expect(empty.transferJourneysPerDay == 0)
        #expect(!empty.shouldShow)
        #expect(active.transferJourneysPerDay == 875)
        #expect(active.shouldShow)
    }

    @Test("Rider count formatting is compact and clamps negative values")
    func riderCountFormatting() {
        #expect(
            ConnectingJourneyUIPresentation.compactRiderCount(-20)
                == ConnectingJourneyUIPresentation.compactRiderCount(0)
        )
        #expect(
            ConnectingJourneyUIPresentation.fullRiderCount(-20)
                == ConnectingJourneyUIPresentation.fullRiderCount(0)
        )
        #expect(!ConnectingJourneyUIPresentation.compactRiderCount(12_500).isEmpty)
        #expect(!ConnectingJourneyUIPresentation.fullRiderCount(12_500).isEmpty)
    }
}
