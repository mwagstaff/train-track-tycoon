import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("World environment")
struct WorldEnvironmentTests {
    @Test("World time advances deterministically at the selected rate")
    func deterministicAdvancement() {
        let initial = WorldEnvironmentState(
            elapsedWorldSeconds: 10_000,
            rate: .normal,
            isPaused: false,
            weatherSeed: 123
        )

        let normal = WorldEnvironmentSimulation.advance(initial, byRealSeconds: 10)
        let repeated = WorldEnvironmentSimulation.advance(initial, byRealSeconds: 10)
        var fasterState = initial
        fasterState.rate = .tripleSpeed
        let faster = WorldEnvironmentSimulation.advance(fasterState, byRealSeconds: 10)

        #expect(normal == repeated)
        #expect(normal.elapsedWorldSeconds == 11_200)
        #expect(faster.elapsedWorldSeconds == 13_600)
    }

    @Test("Paused and invalid deltas cannot advance the world")
    func pausedAndInvalidDeltas() {
        var paused = WorldEnvironmentState.initial
        paused.isPaused = true

        #expect(
            WorldEnvironmentSimulation.advance(paused, byRealSeconds: 30)
                .elapsedWorldSeconds == paused.elapsedWorldSeconds
        )

        var running = paused
        running.isPaused = false
        for delta in [-1.0, 0, .nan, .infinity] {
            #expect(
                WorldEnvironmentSimulation.advance(running, byRealSeconds: delta)
                    .elapsedWorldSeconds == running.elapsedWorldSeconds
            )
        }
    }

    @Test("Day phases and daylight use smooth, bounded transitions")
    func dayPhases() {
        #expect(WorldEnvironmentSimulation.phase(atHour: 4) == .night)
        #expect(WorldEnvironmentSimulation.phase(atHour: 6) == .dawn)
        #expect(WorldEnvironmentSimulation.phase(atHour: 12) == .day)
        #expect(WorldEnvironmentSimulation.phase(atHour: 19) == .dusk)
        #expect(WorldEnvironmentSimulation.phase(atHour: 25) == .night)
        #expect(WorldEnvironmentSimulation.daylightFraction(atHour: 5.5) == 0)
        #expect(WorldEnvironmentSimulation.daylightFraction(atHour: 6.5) == 0.5)
        #expect(WorldEnvironmentSimulation.daylightFraction(atHour: 12) == 1)
        #expect(WorldEnvironmentSimulation.daylightFraction(atHour: 19.5) == 0.5)
        #expect(WorldEnvironmentSimulation.daylightFraction(atHour: 21) == 0)
    }

    @Test("Map appearance changes at twilight's midpoint and honours Reduce Motion")
    func mapAppearanceTransitionPolicy() {
        #expect(
            WorldMapAppearanceTransitionPolicy.appearance(forDaylightFraction: 1) == .light
        )
        #expect(
            WorldMapAppearanceTransitionPolicy.appearance(forDaylightFraction: 0.5) == .light
        )
        #expect(
            WorldMapAppearanceTransitionPolicy.appearance(forDaylightFraction: 0.49) == .dark
        )
        #expect(
            WorldMapAppearanceTransitionPolicy.appearance(forDaylightFraction: 0) == .dark
        )
        #expect(
            WorldMapAppearanceTransitionPolicy.appearance(forDaylightFraction: .nan) == .light
        )

        #expect(
            WorldMapAppearanceTransitionPolicy.shouldAnimate(
                from: .light,
                to: .dark,
                reduceMotion: false
            )
        )
        #expect(
            !WorldMapAppearanceTransitionPolicy.shouldAnimate(
                from: .dark,
                to: .dark,
                reduceMotion: false
            )
        )
        #expect(
            !WorldMapAppearanceTransitionPolicy.shouldAnimate(
                from: .light,
                to: .dark,
                reduceMotion: true
            )
        )
        #expect(WorldMapAppearanceTransitionPolicy.coverDurationMilliseconds > 0)
        #expect(WorldMapAppearanceTransitionPolicy.revealDurationMilliseconds > 0)
        #expect((0...1).contains(WorldMapAppearanceTransitionPolicy.maximumCoverOpacity))
    }

    @Test("Snapshots derive map appearance from continuous daylight")
    func snapshotMapAppearance() {
        let dawnDark = WorldEnvironmentSimulation.snapshot(
            for: WorldEnvironmentState(
                elapsedWorldSeconds: 6 * 3_600,
                rate: .normal,
                isPaused: false,
                weatherSeed: 1
            )
        )
        let dawnLight = WorldEnvironmentSimulation.snapshot(
            for: WorldEnvironmentState(
                elapsedWorldSeconds: 7 * 3_600,
                rate: .normal,
                isPaused: false,
                weatherSeed: 1
            )
        )
        let duskLight = WorldEnvironmentSimulation.snapshot(
            for: WorldEnvironmentState(
                elapsedWorldSeconds: 19 * 3_600,
                rate: .normal,
                isPaused: false,
                weatherSeed: 1
            )
        )
        let duskDark = WorldEnvironmentSimulation.snapshot(
            for: WorldEnvironmentState(
                elapsedWorldSeconds: 20 * 3_600,
                rate: .normal,
                isPaused: false,
                weatherSeed: 1
            )
        )

        #expect(dawnDark.phase == .dawn)
        #expect(dawnDark.preferredMapAppearance == .dark)
        #expect(dawnLight.phase == .dawn)
        #expect(dawnLight.preferredMapAppearance == .light)
        #expect(duskLight.phase == .dusk)
        #expect(duskLight.preferredMapAppearance == .light)
        #expect(duskDark.phase == .dusk)
        #expect(duskDark.preferredMapAppearance == .dark)
    }

    @Test("Weather is stable inside a period and varied across a longer run")
    func deterministicWeather() {
        let period = WorldEnvironmentSimulation.weatherPeriodSeconds
        let seed: UInt64 = 987_654
        let first = WorldEnvironmentSimulation.weather(
            atElapsedWorldSeconds: period * 11 + 1,
            seed: seed
        )
        let samePeriod = WorldEnvironmentSimulation.weather(
            atElapsedWorldSeconds: period * 12 - 1,
            seed: seed
        )
        let sequence = Set((0..<80).map { index in
            WorldEnvironmentSimulation.weather(
                atElapsedWorldSeconds: Double(index) * period,
                seed: seed
            )
        })

        #expect(first == samePeriod)
        #expect(sequence == Set(WorldWeather.allCases))
    }

    @Test("Snapshots expose clock, day, light and weather from one state")
    func snapshotFacts() {
        let elapsed = 2 * WorldEnvironmentSimulation.secondsPerDay + 19.5 * 3_600
        let state = WorldEnvironmentState(
            elapsedWorldSeconds: elapsed,
            rate: .normal,
            isPaused: false,
            weatherSeed: 42
        )
        let snapshot = WorldEnvironmentSimulation.snapshot(for: state)

        #expect(snapshot.day == 2)
        #expect(snapshot.clockText == "19:30")
        #expect(snapshot.phase == .dusk)
        #expect(snapshot.daylightFraction == 0.5)
        #expect(snapshot.nightIntensity == 0.5)
    }

    @Test("Extreme finite saved time is safely rebased before integer conversion")
    func extremeFiniteSavedTime() {
        let damaged = WorldEnvironmentState(
            elapsedWorldSeconds: 1e300,
            rate: .tripleSpeed,
            isPaused: false,
            weatherSeed: .max
        )

        let normalized = WorldEnvironmentSimulation.normalized(damaged)
        let snapshot = WorldEnvironmentSimulation.snapshot(for: damaged)
        let weather = WorldEnvironmentSimulation.weather(
            atElapsedWorldSeconds: damaged.elapsedWorldSeconds,
            seed: damaged.weatherSeed
        )

        #expect(normalized.elapsedWorldSeconds == WorldEnvironmentState.initial.elapsedWorldSeconds)
        #expect(snapshot.elapsedWorldSeconds == WorldEnvironmentState.initial.elapsedWorldSeconds)
        #expect(snapshot.day == 0)
        #expect(WorldWeather.allCases.contains(weather))
    }

    @Test("Controller persistence and reset are explicit")
    @MainActor
    func controllerPersistenceAndReset() throws {
        let suiteName = "WorldEnvironmentTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let controller = WorldEnvironmentController(defaults: defaults)
        controller.setRate(.doubleSpeed)
        controller.advance(byRealSeconds: 4)
        controller.setPaused(true)

        let restored = WorldEnvironmentController(defaults: defaults)
        #expect(restored.state == controller.state)
        #expect(restored.state.rate == .doubleSpeed)
        #expect(restored.state.isPaused)

        controller.reset()
        let afterReset = WorldEnvironmentController(defaults: defaults)
        #expect(controller.state == .initial)
        #expect(afterReset.state == .initial)
    }

    @Test("Procedural cues are finite, quiet and repeatable")
    func proceduralAudioSamples() {
        for cue in GameAudioCue.allCases {
            let first = GameSoundSynthesizer.samples(for: cue, sampleRate: 8_000)
            let second = GameSoundSynthesizer.samples(for: cue, sampleRate: 8_000)

            #expect(!first.isEmpty)
            #expect(first == second)
            #expect(first.allSatisfy { $0.isFinite })
            #expect(first.allSatisfy { abs($0) < 0.12 })
        }
        #expect(GameSoundSynthesizer.samples(for: .lineOpened, sampleRate: 0).isEmpty)
    }

    @Test("Fare cue has distinct mechanical and ringing phases")
    func cashRegisterAudioShape() {
        let sampleRate = 8_000.0
        let samples = GameSoundSynthesizer.samples(
            for: .fareCollected,
            sampleRate: sampleRate
        )

        func rootMeanSquare(from start: Double, to end: Double) -> Double {
            let lowerBound = max(Int(start * sampleRate), 0)
            let upperBound = min(Int(end * sampleRate), samples.count)
            guard lowerBound < upperBound else { return 0 }
            let power = samples[lowerBound..<upperBound].reduce(0.0) {
                $0 + Double($1 * $1)
            }
            return sqrt(power / Double(upperBound - lowerBound))
        }

        #expect(samples.count == 5_440)
        #expect(rootMeanSquare(from: 0.01, to: 0.16) > 0.005)
        #expect(rootMeanSquare(from: 0.20, to: 0.48) > 0.005)
        #expect(rootMeanSquare(from: 0.62, to: 0.68)
            < rootMeanSquare(from: 0.20, to: 0.48))
        #expect(abs(samples.last ?? 1) < 0.001)
    }
}
