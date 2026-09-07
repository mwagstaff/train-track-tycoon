import Testing
@testable import TrainTrackTycoon

@Suite("Display-link simulation pacing")
struct SimulationClockTests {
    @Test("Presentation cadence is bounded for mobile energy use")
    func usesEnergyConsciousPresentationCadence() {
        #expect(DisplayLinkSimulationClock.preferredUpdatesPerSecond == 10)
    }

    @Test("Normal frame deltas advance simulation")
    func acceptsNormalFrameDelta() {
        let delta = DisplayLinkSimulationClock.acceptedDelta(
            currentTimestamp: 10.05,
            previousTimestamp: 10
        )
        #expect(delta != nil)
        #expect(abs((delta ?? 0) - 0.05) < 0.000_001)
    }

    @Test("A gesture-sized pause does not trigger one catch-up frame")
    func rejectsDelayedFrameDelta() {
        #expect(DisplayLinkSimulationClock.acceptedDelta(
            currentTimestamp: 12,
            previousTimestamp: 10
        ) == nil)
        #expect(DisplayLinkSimulationClock.acceptedDelta(
            currentTimestamp: 10,
            previousTimestamp: 10
        ) == nil)
    }
}
