import Testing
@testable import TrainTrackTycoon

@Suite("Train arrival reward timing")
struct TrainArrivalRewardTimingTests {
    @Test("Animated rewards remain fully readable before departing")
    func readableHoldPrecedesExit() {
        #expect(TrainArrivalRewardTiming.readableHoldMilliseconds >= 1_500)
        #expect(TrainArrivalRewardTiming.exitAnimationMilliseconds == 500)
        #expect(
            TrainArrivalRewardTiming.animatedLifetimeMilliseconds
                == TrainArrivalRewardTiming.readableHoldMilliseconds
                    + TrainArrivalRewardTiming.exitAnimationMilliseconds
                    + TrainArrivalRewardTiming.cleanupBufferMilliseconds
        )
    }

    @Test("Reduce Motion rewards remain static for a readable interval")
    func reducedMotionLifetime() {
        #expect(TrainArrivalRewardTiming.reduceMotionLifetimeMilliseconds >= 2_000)
    }
}
