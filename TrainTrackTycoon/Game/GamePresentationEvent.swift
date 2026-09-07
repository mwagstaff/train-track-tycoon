import Foundation

/// A short-lived, typed signal for presentation-only feedback.
///
/// Durable game state remains the source of truth. Views, sound and particle effects can observe
/// this monotonically sequenced stream without guessing intent from broad state changes such as a
/// line-count change (which also happens during a reset).
nonisolated struct GamePresentationEvent: Equatable, Sendable {
    let sequence: UInt64
    let kind: Kind

    nonisolated enum Kind: Equatable, Sendable {
        case constructionStarted(lineID: UUID, railwayClass: RailwayClass)
        case lineOpened(lineID: UUID, railwayClass: RailwayClass)
        case stationUpgraded(stationCRS: String, level: StationLevel)
        case infrastructureUpgraded(lineID: UUID, capacity: TrackCapacity)
        case operatingDayCompleted(day: UInt64, operatingResultPence: Int64)
        case trainArrived(
            lineID: UUID,
            trainID: UUID,
            stationCRS: String,
            fareRevenuePence: Int64,
            soundsHorn: Bool
        )
    }
}
