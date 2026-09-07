import AVFAudio
import Foundation
import Observation

nonisolated enum GameAudioCue: String, CaseIterable, Sendable {
    case lineOpened
    case trainDeparture
    case stationUpgrade
    case achievementUnlocked
    case fareCollected
    case trainHorn
}

@MainActor
protocol GameAudioControlling: AnyObject {
    var isEnabled: Bool { get set }
    var isPrepared: Bool { get }
    func prepare()
    func play(_ cue: GameAudioCue)
    func stopAll()
}

/// Optional, procedural game feedback. The controller is silent until the player
/// explicitly enables sound and a feature asks it to play a cue.
@Observable
@MainActor
final class GameAudioController: GameAudioControlling {
    private enum Constants {
        static let sampleRate = 44_100.0
    }

    var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            if !isEnabled {
                stopAll()
            }
        }
    }

    private(set) var isPrepared = false
    private(set) var lastErrorDescription: String?

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var player: AVAudioPlayerNode?
    @ObservationIgnored private var playbackGeneration: UInt64 = 0
    @ObservationIgnored private var activeCue: GameAudioCue?
    @ObservationIgnored private var pendingCues: [GameAudioCue] = []
    @ObservationIgnored private var notificationObservers: [NSObjectProtocol] = []

    init() {
        // PlayerProfileStore is the single persistence authority. The root synchronizes that
        // opt-in preference before any cue can play.
        self.isEnabled = false
        installAudioObservers()
    }

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func prepare() {
        guard isEnabled, !isPrepared else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])

            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            let format = AVAudioFormat(
                standardFormatWithSampleRate: Constants.sampleRate,
                channels: 1
            )!
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)

            self.engine = engine
            self.player = player
            isPrepared = true
            lastErrorDescription = nil
        } catch {
            tearDownEngine()
            lastErrorDescription = error.localizedDescription
        }
    }

    func play(_ cue: GameAudioCue) {
        guard isEnabled else { return }

        // Horns are deliberately sparse. Coalescing them also prevents a busy map from building
        // an unrealistic queue of horns while the short fare cues are being played.
        if cue == .trainHorn,
           activeCue == .trainHorn || pendingCues.contains(.trainHorn) {
            return
        }
        if pendingCues.count >= 8 {
            if let journeyCueIndex = pendingCues.firstIndex(where: \.isJourneyFeedback) {
                pendingCues.remove(at: journeyCueIndex)
            } else if cue.isJourneyFeedback {
                return
            } else if pendingCues.count >= 12 {
                pendingCues.removeFirst()
            }
        }
        pendingCues.append(cue)
        playNextCueIfNeeded()
    }

    private func playNextCueIfNeeded() {
        guard isEnabled, activeCue == nil, !pendingCues.isEmpty else { return }
        prepare()
        guard let engine, let player else {
            pendingCues.removeAll()
            return
        }

        let cue = pendingCues.removeFirst()
        guard let buffer = GameSoundSynthesizer.buffer(
            for: cue,
            sampleRate: Constants.sampleRate
        ) else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(true)
            if !engine.isRunning {
                try engine.start()
            }
            let generation = nextPlaybackGeneration()
            activeCue = cue
            player.scheduleBuffer(
                buffer,
                at: nil,
                options: [],
                completionCallbackType: .dataPlayedBack
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.finishPlayback(generation: generation)
                }
            }
            player.play()
            lastErrorDescription = nil
        } catch {
            lastErrorDescription = error.localizedDescription
            stopAll()
        }
    }

    func stopAll() {
        _ = nextPlaybackGeneration()
        pendingCues.removeAll()
        activeCue = nil
        player?.stop()
        engine?.stop()
        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: [.notifyOthersOnDeactivation]
            )
        } catch {
            lastErrorDescription = error.localizedDescription
        }
    }

    /// Releases audio graph resources, for example when the scene is discarded.
    func shutdown() {
        stopAll()
        tearDownEngine()
    }

    private func tearDownEngine() {
        player?.stop()
        if let player, let engine {
            engine.disconnectNodeOutput(player)
            engine.detach(player)
        }
        engine?.stop()
        player = nil
        engine = nil
        activeCue = nil
        pendingCues.removeAll()
        isPrepared = false
    }

    private func nextPlaybackGeneration() -> UInt64 {
        if playbackGeneration == .max {
            playbackGeneration = 0
        } else {
            playbackGeneration += 1
        }
        return playbackGeneration
    }

    private func finishPlayback(generation: UInt64) {
        guard playbackGeneration == generation else { return }
        player?.stop()
        activeCue = nil
        if pendingCues.isEmpty {
            engine?.stop()
            do {
                try AVAudioSession.sharedInstance().setActive(
                    false,
                    options: [.notifyOthersOnDeactivation]
                )
            } catch {
                lastErrorDescription = error.localizedDescription
            }
        } else {
            playNextCueIfNeeded()
        }
    }

    private func installAudioObservers() {
        let center = NotificationCenter.default
        notificationObservers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey]
                    as? UInt,
                    AVAudioSession.InterruptionType(rawValue: rawType) == .began else {
                    return
                }
                Task { @MainActor [weak self] in
                    self?.stopAll()
                }
            }
        )
        notificationObservers.append(
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.stopAll()
                    self?.tearDownEngine()
                }
            }
        )
    }
}

/// Pure sample generation keeps the audio asset-free and independently testable.
nonisolated enum GameSoundSynthesizer {
    private static let defaultCashRegisterSamples = renderCashRegisterSamples(
        sampleRate: 44_100
    )

    static func samples(
        for cue: GameAudioCue,
        sampleRate: Double = 44_100
    ) -> [Float] {
        guard sampleRate.isFinite, sampleRate >= 8_000 else { return [] }

        // A cash register is an impact followed by a resonant bell, rather than a short
        // two-note melody. Keeping it procedural makes the cue original, deterministic and
        // asset-free while the separate layers give it the familiar "cha-ching" character.
        if cue == .fareCollected {
            return cashRegisterSamples(sampleRate: sampleRate)
        }

        let duration = cue.duration
        let sampleCount = max(Int(duration * sampleRate), 1)
        var result = [Float](repeating: 0, count: sampleCount)
        var phase = 0.0

        for index in result.indices {
            let time = Double(index) / sampleRate
            let progress = time / duration
            let frequency = cue.frequency(at: progress)
            phase += 2 * Double.pi * frequency / sampleRate

            let attack = min(progress / 0.08, 1)
            let release = min((1 - progress) / 0.28, 1)
            let envelope = max(min(attack, release), 0)
            let fundamental = sin(phase)
            let softHarmonic = sin(phase * 2) * 0.12
            result[index] = Float((fundamental + softHarmonic) * envelope * cue.gain)
        }
        return result
    }

    private static func cashRegisterSamples(sampleRate: Double) -> [Float] {
        if sampleRate == 44_100 {
            return defaultCashRegisterSamples
        }
        return renderCashRegisterSamples(sampleRate: sampleRate)
    }

    private static func renderCashRegisterSamples(sampleRate: Double) -> [Float] {
        let duration = GameAudioCue.fareCollected.duration
        let sampleCount = max(Int(duration * sampleRate), 1)
        var result = [Float](repeating: 0, count: sampleCount)

        // Fixed-seed noise provides the texture of a latch, drawer rails and loose coins.
        // It deliberately resets for every cue so tests and playback remain repeatable.
        var noiseState: UInt64 = 0xC451_5EED_DA7A_2026
        var smoothedNoise = 0.0

        for index in result.indices {
            let time = Double(index) / sampleRate

            noiseState ^= noiseState << 13
            noiseState ^= noiseState >> 7
            noiseState ^= noiseState << 17
            let rawNoise = Double(noiseState & 0xffff) / 32_767.5 - 1
            smoothedNoise += (rawNoise - smoothedNoise) * 0.22
            let crispNoise = rawNoise - smoothedNoise

            // "Cha": a low drawer thump, short latch snap and two uneven rail clacks.
            let drawerThump = sin(2 * Double.pi * 82 * time)
                * exp(-25 * time)
                * 0.042
            let drawerTravel = time < 0.155
                ? crispNoise * sin(Double.pi * time / 0.155) * 0.013
                : 0

            let latchAge = time - 0.028
            let latchSnap = latchAge >= 0
                ? (crispNoise * 0.026 + sin(2 * Double.pi * 510 * latchAge) * 0.014)
                    * exp(-72 * latchAge)
                : 0

            let railClackAge = time - 0.118
            let railClack = railClackAge >= 0
                ? (crispNoise * 0.031 + sin(2 * Double.pi * 235 * railClackAge) * 0.018)
                    * exp(-58 * railClackAge)
                : 0

            // "Ching": a struck metal bell with deliberately inharmonic partials. A small
            // downward drift and unequal partial decay avoid the synthetic beep-boop quality.
            let bellAge = time - 0.185
            var bell = 0.0
            if bellAge >= 0 {
                let strike = min(bellAge / 0.0025, 1)
                let bellEnvelope = strike * exp(-5.7 * bellAge)
                let fundamentalCycles = 1_246 * bellAge - 10 * bellAge * bellAge
                let partials =
                    sin(2 * Double.pi * fundamentalCycles) * 0.62
                    + sin(2 * Double.pi * 1_887 * bellAge + 0.31) * 0.31
                    + sin(2 * Double.pi * 2_743 * bellAge + 0.83) * 0.20
                    + sin(2 * Double.pi * 3_217 * bellAge + 1.27) * 0.10
                bell = partials * bellEnvelope * 0.058
            }

            // Three tiny, irregular impacts suggest coins settling in the open drawer.
            var coinRattle = 0.0
            for strikeTime in [0.255, 0.302, 0.371] {
                let age = time - strikeTime
                if age >= 0 {
                    coinRattle += (crispNoise * 0.015
                        + sin(2 * Double.pi * 2_960 * age) * 0.010)
                        * exp(-86 * age)
                }
            }

            // Fade the ringing tail to silence so back-to-back queued cues never click.
            let tailFade = min(max((duration - time) / 0.065, 0), 1)
            let mixed = (drawerThump + drawerTravel + latchSnap + railClack + bell + coinRattle)
                * tailFade
            result[index] = Float(min(max(mixed, -0.115), 0.115))
        }

        return result
    }

    static func buffer(
        for cue: GameAudioCue,
        sampleRate: Double = 44_100
    ) -> AVAudioPCMBuffer? {
        let samples = samples(for: cue, sampleRate: sampleRate)
        guard !samples.isEmpty,
              let format = AVAudioFormat(
                  standardFormatWithSampleRate: sampleRate,
                  channels: 1
              ),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(samples.count)
              ),
              let channel = buffer.floatChannelData?[0] else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            guard let baseAddress = source.baseAddress else { return }
            channel.update(from: baseAddress, count: samples.count)
        }
        return buffer
    }
}

private nonisolated extension GameAudioCue {
    var isJourneyFeedback: Bool {
        self == .fareCollected || self == .trainHorn
    }

    var duration: TimeInterval {
        switch self {
        case .lineOpened: 0.48
        case .trainDeparture: 0.32
        case .stationUpgrade: 0.56
        case .achievementUnlocked: 0.72
        case .fareCollected: 0.68
        case .trainHorn: 0.62
        }
    }

    var gain: Double {
        switch self {
        case .trainDeparture: 0.055
        case .fareCollected: 0.06
        case .trainHorn: 0.052
        case .lineOpened, .stationUpgrade: 0.07
        case .achievementUnlocked: 0.075
        }
    }

    func frequency(at progress: Double) -> Double {
        let progress = min(max(progress, 0), 1)
        switch self {
        case .lineOpened:
            return progress < 0.52 ? 392 : 523.25
        case .trainDeparture:
            return 196 + progress * 36
        case .stationUpgrade:
            if progress < 0.33 { return 329.63 }
            if progress < 0.66 { return 415.30 }
            return 523.25
        case .achievementUnlocked:
            if progress < 0.25 { return 392 }
            if progress < 0.5 { return 493.88 }
            if progress < 0.75 { return 587.33 }
            return 783.99
        case .fareCollected:
            // This cue has a dedicated layered cash-register synthesizer above.
            return 1_246
        case .trainHorn:
            return progress < 0.52 ? 369.99 : 311.13
        }
    }
}
