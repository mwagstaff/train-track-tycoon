import Foundation

/// Deterministic catalogue search shared by the nationwide station picker and its tests.
nonisolated enum StationSearchPolicy {
    static let defaultMaximumResultCount = 80

    static func results(
        matching query: String,
        in stations: [Station],
        excludingCRS: String? = nil,
        maximumResultCount: Int = defaultMaximumResultCount
    ) -> [Station] {
        let needle = normalizedText(query)
        guard !needle.isEmpty, maximumResultCount > 0 else { return [] }
        let excluded = excludingCRS.map(normalizedCRS)

        return stations.lazy
            .filter { normalizedCRS($0.crs) != excluded }
            .compactMap { station -> RankedStation? in
                let name = normalizedText(station.name)
                let crs = normalizedCRS(station.crs).lowercased()
                let rank: Int
                if crs == needle {
                    rank = 0
                } else if name == needle {
                    rank = 1
                } else if crs.hasPrefix(needle) {
                    rank = 2
                } else if name.hasPrefix(needle) {
                    rank = 3
                } else if name.split(separator: " ").contains(where: {
                    $0.hasPrefix(needle)
                }) {
                    rank = 4
                } else if name.contains(needle) {
                    rank = 5
                } else if crs.contains(needle) {
                    rank = 6
                } else {
                    return nil
                }
                return RankedStation(station: station, rank: rank, normalizedName: name)
            }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                if lhs.normalizedName != rhs.normalizedName {
                    return lhs.normalizedName < rhs.normalizedName
                }
                return lhs.station.crs < rhs.station.crs
            }
            .prefix(maximumResultCount)
            .map(\.station)
    }

    static func normalizedText(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_GB")
        )
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
        .lowercased()
    }

    private static func normalizedCRS(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

private nonisolated struct RankedStation {
    let station: Station
    let rank: Int
    let normalizedName: String
}
