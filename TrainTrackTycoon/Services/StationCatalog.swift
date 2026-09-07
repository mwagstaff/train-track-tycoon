import Foundation

nonisolated enum StationCatalogError: LocalizedError, Equatable, Sendable {
    case resourceMissing
    case invalidResource
    case curatedStationMissing(String)

    var errorDescription: String? {
        switch self {
        case .resourceMissing:
            return "The station catalogue is unavailable."
        case .invalidResource:
            return "The station catalogue couldn't be loaded."
        case .curatedStationMissing(let crs):
            return "The station catalogue is missing required station \(crs)."
        }
    }
}

nonisolated struct StationCatalog: Sendable {
    /// The deliberately small, stable order used by the proof-of-concept station picker.
    /// Append new entries so existing stations retain their established order.
    static let southEastStationCRSs = [
        "VIC", "CLJ", "SRS", "ECR", "PUR", "HOR",
        "GTW", "TBD", "HHE", "BTN", "LBG", "BFR",
        "BRX", "HNH", "KTH",
    ]

    let allStations: [Station]
    let curatedStations: [Station]

    private let stationsByCRS: [String: Station]

    init(bundle: Bundle = .main) throws {
        let resourceURL = bundle.url(
            forResource: "stations",
            withExtension: "json",
            subdirectory: "Resources"
        ) ?? bundle.url(forResource: "stations", withExtension: "json")
        guard let resourceURL else {
            throw StationCatalogError.resourceMissing
        }

        let decodedStations: [Station]
        do {
            let data = try Data(contentsOf: resourceURL, options: .mappedIfSafe)
            decodedStations = try JSONDecoder().decode([Station].self, from: data)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw StationCatalogError.invalidResource
        }

        var lookup = [String: Station](minimumCapacity: decodedStations.count)
        for station in decodedStations {
            guard lookup.updateValue(station, forKey: station.crs) == nil else {
                throw StationCatalogError.invalidResource
            }
        }

        var curated = [Station]()
        curated.reserveCapacity(Self.southEastStationCRSs.count)
        for crs in Self.southEastStationCRSs {
            guard let station = lookup[crs] else {
                throw StationCatalogError.curatedStationMissing(crs)
            }
            curated.append(station)
        }

        allStations = decodedStations
        curatedStations = curated
        stationsByCRS = lookup
    }

    func station(forCRS crs: String) -> Station? {
        stationsByCRS[Self.normalizedCRS(crs)]
    }

    subscript(crs: String) -> Station? {
        station(forCRS: crs)
    }

    private static func normalizedCRS(_ crs: String) -> String {
        crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
