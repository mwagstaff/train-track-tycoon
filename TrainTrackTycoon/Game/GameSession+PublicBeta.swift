import Foundation

extension GameSession {
    /// A compact, sanitized snapshot used by achievements, scenarios and daily statistics.
    /// Keeping this mapping at the session boundary prevents presentation code from duplicating
    /// gameplay rules or reaching into individual simulation engines.
    var publicBetaFacts: PublicBetaNetworkFacts {
        let completedServices = lines.filter(\.isConstructed)
        let completedCorridorCount = corridors.lazy.filter(\.isConstructed).count
        let stationCRSs = Set(completedServices.flatMap { line in
            line.stationCRSs.map(StationEvolution.normalizedCRS)
        }.filter { !$0.isEmpty })
        let expressLineCount = completedServices.lazy.filter { line in
            line.railwayClass == .highSpeed
                || line.servicePattern == .express
                || (line.servicePattern == .balanced && line.trains.count >= 2)
        }.count
        let happiness = happinessSnapshot.globalHappinessScore
        let happinessBasisPoints: Int
        if happiness.isFinite {
            happinessBasisPoints = Int((min(max(happiness, 0), 100) * 100).rounded())
        } else {
            happinessBasisPoints = 0
        }

        return PublicBetaNetworkFacts(
            // Progress describes railway infrastructure built by the player. Reorganising two
            // paid corridors into one through service must never undo that achievement.
            completedLineCount: completedCorridorCount,
            stationCount: stationCRSs.count,
            expressLineCount: expressLineCount,
            passengersPerDay: Int64(max(passengerSnapshot.passengersPerDay, 0)),
            globalHappinessBasisPoints: happinessBasisPoints,
            completedHighSpeedCorridorCount: prestigeSnapshot.completedCorridorCount,
            prestigeScore: prestigeSnapshot.score,
            interchangeOrHigherStationCount: stationProgressByCRS.values.lazy.filter {
                $0.level >= .interchange
            }.count,
            lifetimeProfitableOperatingDays: publicBetaHistory.statistics.profitableDayCount,
            networkValuePence: financeSnapshot.networkValuePence
        )
    }
}
