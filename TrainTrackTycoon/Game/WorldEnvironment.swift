import Foundation
import Observation

nonisolated enum WorldWeather: String, Codable, CaseIterable, Sendable {
    case clear
    case overcast
    case rain
    case fog

    var displayName: String {
        switch self {
        case .clear: "Clear"
        case .overcast: "Overcast"
        case .rain: "Rain"
        case .fog: "Fog"
        }
    }
}

nonisolated enum WorldDayPhase: String, Codable, Sendable {
    case dawn
    case day
    case dusk
    case night

    var displayName: String {
        rawValue.capitalized
    }

}

nonisolated enum WorldMapAppearance: String, Codable, Equatable, Sendable {
    case light
    case dark
}

/// Keeps the native map readable while the continuous atmosphere layer carries the
/// world through dawn and dusk. The MapKit palette changes at twilight's midpoint,
/// where a short fade-through-colour can conceal its otherwise discrete redraw.
nonisolated struct WorldMapAppearanceTransitionPolicy: Sendable {
    static let daylightThreshold = 0.5
    static let coverDurationMilliseconds = 650
    static let mapRedrawSettleMilliseconds = 90
    static let revealDurationMilliseconds = 850
    static let maximumCoverOpacity = 0.94

    static func appearance(forDaylightFraction daylightFraction: Double) -> WorldMapAppearance {
        let safeDaylight = daylightFraction.isFinite
            ? min(max(daylightFraction, 0), 1)
            : 1
        return safeDaylight >= daylightThreshold ? .light : .dark
    }

    static func shouldAnimate(
        from current: WorldMapAppearance,
        to target: WorldMapAppearance,
        reduceMotion: Bool
    ) -> Bool {
        current != target && !reduceMotion
    }
}

nonisolated enum WorldSimulationRate: String, Codable, CaseIterable, Sendable {
    case halfSpeed
    case normal
    case doubleSpeed
    case tripleSpeed

    var multiplier: Double {
        switch self {
        case .halfSpeed: 0.5
        case .normal: 1
        case .doubleSpeed: 2
        case .tripleSpeed: 3
        }
    }

    var displayName: String {
        switch self {
        case .halfSpeed: "½×"
        case .normal: "1×"
        case .doubleSpeed: "2×"
        case .tripleSpeed: "3×"
        }
    }
}

nonisolated struct WorldEnvironmentState: Codable, Equatable, Sendable {
    var elapsedWorldSeconds: Double
    var rate: WorldSimulationRate
    var isPaused: Bool
    var weatherSeed: UInt64

    static let initial = WorldEnvironmentState(
        // A morning start lets a new network begin in clear, readable light.
        elapsedWorldSeconds: 7.5 * 60 * 60,
        rate: .normal,
        isPaused: false,
        weatherSeed: 0x5452_4149_4E54_5943
    )
}

nonisolated struct WorldEnvironmentSnapshot: Equatable, Sendable {
    let elapsedWorldSeconds: Double
    let day: UInt64
    let secondsIntoDay: Double
    let phase: WorldDayPhase
    let weather: WorldWeather
    let daylightFraction: Double
    let nightIntensity: Double

    var hour: Int {
        Int(secondsIntoDay / 3_600) % 24
    }

    var minute: Int {
        Int(secondsIntoDay / 60) % 60
    }

    var clockText: String {
        String(format: "%02d:%02d", hour, minute)
    }

    var preferredMapAppearance: WorldMapAppearance {
        WorldMapAppearanceTransitionPolicy.appearance(
            forDaylightFraction: daylightFraction
        )
    }
}

/// Pure deterministic rules for the cosmetic world clock and weather cycle.
/// The game economy does not depend on these values, so presentation can be
/// paused, accelerated, reset, and unit tested independently.
nonisolated struct WorldEnvironmentSimulation: Sendable {
    static let secondsPerDay = 24.0 * 60 * 60
    static let worldSecondsPerRealSecond = 120.0
    static let weatherPeriodSeconds = 6.0 * 60 * 60
    /// Far beyond any realistic save lifetime while remaining safely convertible to UInt64.
    static let maximumElapsedWorldSeconds = secondsPerDay * 365_000

    static func advance(
        _ state: WorldEnvironmentState,
        byRealSeconds realSeconds: TimeInterval
    ) -> WorldEnvironmentState {
        var result = normalized(state)
        guard !result.isPaused,
              realSeconds.isFinite,
              realSeconds > 0 else {
            return result
        }

        let worldDelta = realSeconds
            * worldSecondsPerRealSecond
            * result.rate.multiplier
        guard worldDelta.isFinite, worldDelta > 0 else { return result }

        let advancedElapsed = result.elapsedWorldSeconds + worldDelta
        if !advancedElapsed.isFinite || advancedElapsed > maximumElapsedWorldSeconds {
            result.elapsedWorldSeconds = WorldEnvironmentState.initial.elapsedWorldSeconds
        } else {
            result.elapsedWorldSeconds = advancedElapsed
        }
        return result
    }

    static func snapshot(for state: WorldEnvironmentState) -> WorldEnvironmentSnapshot {
        let state = normalized(state)
        let day = UInt64(state.elapsedWorldSeconds / secondsPerDay)
        let secondsIntoDay = state.elapsedWorldSeconds
            .truncatingRemainder(dividingBy: secondsPerDay)
        let hour = secondsIntoDay / 3_600
        let daylight = daylightFraction(atHour: hour)

        return WorldEnvironmentSnapshot(
            elapsedWorldSeconds: state.elapsedWorldSeconds,
            day: day,
            secondsIntoDay: secondsIntoDay,
            phase: phase(atHour: hour),
            weather: weather(
                atElapsedWorldSeconds: state.elapsedWorldSeconds,
                seed: state.weatherSeed
            ),
            daylightFraction: daylight,
            nightIntensity: 1 - daylight
        )
    }

    static func normalized(_ state: WorldEnvironmentState) -> WorldEnvironmentState {
        var result = state
        if !result.elapsedWorldSeconds.isFinite
            || result.elapsedWorldSeconds < 0
            || result.elapsedWorldSeconds > maximumElapsedWorldSeconds {
            result.elapsedWorldSeconds = WorldEnvironmentState.initial.elapsedWorldSeconds
        }
        return result
    }

    static func phase(atHour hour: Double) -> WorldDayPhase {
        let normalizedHour = normalizedHour(hour)
        return switch normalizedHour {
        case 5.5..<7.5: .dawn
        case 7.5..<18.5: .day
        case 18.5..<20.5: .dusk
        default: .night
        }
    }

    static func daylightFraction(atHour hour: Double) -> Double {
        let normalizedHour = normalizedHour(hour)
        return switch normalizedHour {
        case 5.5..<7.5:
            smoothStep((normalizedHour - 5.5) / 2)
        case 7.5..<18.5:
            1
        case 18.5..<20.5:
            1 - smoothStep((normalizedHour - 18.5) / 2)
        default:
            0
        }
    }

    static func weather(
        atElapsedWorldSeconds elapsedWorldSeconds: Double,
        seed: UInt64
    ) -> WorldWeather {
        let safeElapsed: Double
        if elapsedWorldSeconds.isFinite,
           elapsedWorldSeconds >= 0,
           elapsedWorldSeconds <= maximumElapsedWorldSeconds {
            safeElapsed = elapsedWorldSeconds
        } else {
            safeElapsed = WorldEnvironmentState.initial.elapsedWorldSeconds
        }
        let period = UInt64(safeElapsed / weatherPeriodSeconds)
        let sample = splitMix64(seed &+ period &* 0x9E37_79B9_7F4A_7C15) % 100

        return switch sample {
        case 0..<48: .clear
        case 48..<72: .overcast
        case 72..<90: .rain
        default: .fog
        }
    }

    private static func normalizedHour(_ hour: Double) -> Double {
        guard hour.isFinite else { return 12 }
        let remainder = hour.truncatingRemainder(dividingBy: 24)
        return remainder >= 0 ? remainder : remainder + 24
    }

    private static func smoothStep(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    private static func splitMix64(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@MainActor
protocol WorldEnvironmentControlling: AnyObject {
    var state: WorldEnvironmentState { get }
    var snapshot: WorldEnvironmentSnapshot { get }
    func start()
    func stop()
    func setSuspended(_ isSuspended: Bool)
    func setPaused(_ isPaused: Bool)
    func setRate(_ rate: WorldSimulationRate)
    func reset()
}

@Observable
@MainActor
final class WorldEnvironmentController: WorldEnvironmentControlling {
    private enum Constants {
        static let storageKey = "dev.skynolimit.traintracktycoon.world-environment.v1"
        static let tickInterval = Duration.milliseconds(500)
        static let persistenceInterval: TimeInterval = 5
        static let maximumTickInterval: TimeInterval = 2
    }

    private(set) var state: WorldEnvironmentState
    private(set) var isRunning = false

    var snapshot: WorldEnvironmentSnapshot {
        WorldEnvironmentSimulation.snapshot(for: state)
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var lastTickDate: Date?
    @ObservationIgnored private var lastPersistDate: Date?
    @ObservationIgnored private var isSuspended = false

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.now = now
        self.state = Self.load(from: defaults) ?? .initial
    }

    func start() {
        guard tickTask == nil else { return }
        isRunning = true
        lastTickDate = now()
        lastPersistDate = lastTickDate

        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Constants.tickInterval)
                } catch {
                    return
                }
                guard let self else { return }
                self.tick(at: self.now())
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
        isRunning = false
        lastTickDate = nil
        persist()
    }

    func setSuspended(_ isSuspended: Bool) {
        guard self.isSuspended != isSuspended else { return }
        self.isSuspended = isSuspended
        lastTickDate = isSuspended ? nil : now()
        if isSuspended {
            persist()
        }
    }

    func setPaused(_ isPaused: Bool) {
        guard state.isPaused != isPaused else { return }
        state.isPaused = isPaused
        lastTickDate = now()
        persist()
    }

    func setRate(_ rate: WorldSimulationRate) {
        guard state.rate != rate else { return }
        state.rate = rate
        lastTickDate = now()
        persist()
    }

    func reset() {
        defaults.removeObject(forKey: Constants.storageKey)
        state = .initial
        lastTickDate = now()
        lastPersistDate = lastTickDate
    }

    /// Explicit advancement is useful for previews, deterministic integration tests,
    /// and hosts that already own a low-frequency application clock.
    func advance(byRealSeconds realSeconds: TimeInterval) {
        state = WorldEnvironmentSimulation.advance(state, byRealSeconds: realSeconds)
    }

    private func tick(at date: Date) {
        guard !isSuspended else {
            lastTickDate = nil
            return
        }
        guard let previousDate = lastTickDate else {
            lastTickDate = date
            return
        }

        let elapsed = min(
            max(date.timeIntervalSince(previousDate), 0),
            Constants.maximumTickInterval
        )
        lastTickDate = date
        let advancedState = WorldEnvironmentSimulation.advance(state, byRealSeconds: elapsed)
        guard advancedState != state else { return }
        state = advancedState

        if lastPersistDate.map({ date.timeIntervalSince($0) >= Constants.persistenceInterval }) != false {
            persist()
            lastPersistDate = date
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Constants.storageKey)
    }

    private static func load(from defaults: UserDefaults) -> WorldEnvironmentState? {
        guard let data = defaults.data(forKey: Constants.storageKey),
              let decoded = try? JSONDecoder().decode(WorldEnvironmentState.self, from: data) else {
            return nil
        }
        return WorldEnvironmentSimulation.normalized(decoded)
    }
}
