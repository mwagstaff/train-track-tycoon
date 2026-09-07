import Foundation
import QuartzCore

/// Supplies elapsed wall-clock time. Game simulation remains deterministic because
/// the session consumes deltas rather than deriving movement from frame count.
@MainActor
protocol SimulationClock: AnyObject {
    func start(tick: @escaping @MainActor (TimeInterval) -> Void)
    func stop()
    func setSuspended(_ isSuspended: Bool)
}

extension SimulationClock {
    func setSuspended(_ isSuspended: Bool) {}
}

@MainActor
final class DisplayLinkSimulationClock: SimulationClock {
    /// A display callback delayed by a map gesture or system stall must establish a new baseline,
    /// not ask the main actor to simulate the entire pause in one expensive catch-up frame.
    nonisolated static let maximumAcceptedFrameDelta: TimeInterval = 0.25
    /// Train icons move slowly relative to the map, so ten presentation updates per second remain
    /// visually continuous while halving the amount of SwiftUI and MapKit work requested by the
    /// original proof-of-concept clock.
    nonisolated static let preferredUpdatesPerSecond: Float = 10

    private final class Target: NSObject {
        weak var owner: DisplayLinkSimulationClock?

        init(owner: DisplayLinkSimulationClock) {
            self.owner = owner
        }

        @objc @MainActor
        func displayLinkFired(_ displayLink: CADisplayLink) {
            owner?.displayLinkFired(displayLink)
        }
    }

    private var displayLink: CADisplayLink?
    private var target: Target?
    private var lastTimestamp: CFTimeInterval?
    private var tickHandler: (@MainActor (TimeInterval) -> Void)?
    private var isSuspended = false

    func start(tick: @escaping @MainActor (TimeInterval) -> Void) {
        stop()

        tickHandler = tick
        let target = Target(owner: self)
        let displayLink = CADisplayLink(
            target: target,
            selector: #selector(Target.displayLinkFired(_:))
        )
        // Register in the default run-loop mode so direct manipulation of MapKit gets priority:
        // while the user is panning or pinching in tracking mode, observed network state is not
        // republished underneath it.
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: Self.preferredUpdatesPerSecond,
            maximum: Self.preferredUpdatesPerSecond,
            preferred: Self.preferredUpdatesPerSecond
        )
        displayLink.add(to: .main, forMode: .default)
        displayLink.isPaused = isSuspended

        self.target = target
        self.displayLink = displayLink
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        target = nil
        lastTimestamp = nil
        tickHandler = nil
    }

    func setSuspended(_ isSuspended: Bool) {
        guard self.isSuspended != isSuspended else { return }
        self.isSuspended = isSuspended
        displayLink?.isPaused = isSuspended
        // The first display callback after a resume establishes a fresh baseline. Time spent
        // outside the active scene must not be interpreted as elapsed simulation time.
        lastTimestamp = nil
    }

    private func displayLinkFired(_ displayLink: CADisplayLink) {
        guard !isSuspended else {
            lastTimestamp = nil
            return
        }
        defer { lastTimestamp = displayLink.timestamp }
        guard let lastTimestamp else { return }

        guard let delta = Self.acceptedDelta(
            currentTimestamp: displayLink.timestamp,
            previousTimestamp: lastTimestamp
        ) else { return }
        tickHandler?(delta)
    }

    nonisolated static func acceptedDelta(
        currentTimestamp: CFTimeInterval,
        previousTimestamp: CFTimeInterval,
        maximumDelta: TimeInterval = maximumAcceptedFrameDelta
    ) -> TimeInterval? {
        let delta = currentTimestamp - previousTimestamp
        guard delta.isFinite,
              delta > 0,
              maximumDelta.isFinite,
              maximumDelta > 0,
              delta <= maximumDelta else { return nil }
        return delta
    }

    deinit {
        displayLink?.invalidate()
    }
}
