import CoreLocation
import Foundation

nonisolated struct Station: Identifiable, Hashable, Codable, Sendable {
    let crs: String
    let name: String
    let latitude: Double
    let longitude: Double

    var id: String { crs }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(crs: String, name: String, latitude: Double, longitude: Double) {
        self.crs = crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    private enum CodingKeys: String, CodingKey {
        case crs
        case name
        case latitude
        case longitude
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedCRS = try container.decode(String.self, forKey: .crs)
        crs = decodedCRS.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        name = try container.decode(String.self, forKey: .name)
        latitude = try Self.decodeCoordinate(
            from: container,
            forKey: .latitude,
            validRange: -90...90
        )
        longitude = try Self.decodeCoordinate(
            from: container,
            forKey: .longitude,
            validRange: -180...180
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(crs, forKey: .crs)
        try container.encode(name, forKey: .name)
        // Preserve the string-backed shape of the existing TrainTrack UK resource.
        try container.encode(String(latitude), forKey: .latitude)
        try container.encode(String(longitude), forKey: .longitude)
    }

    private static func decodeCoordinate(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys,
        validRange: ClosedRange<Double>
    ) throws -> Double {
        let value: Double
        if let string = try? container.decode(String.self, forKey: key),
           let parsed = Double(string) {
            value = parsed
        } else {
            value = try container.decode(Double.self, forKey: key)
        }

        guard value.isFinite, validRange.contains(value) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Expected a finite coordinate in \(validRange)."
            )
        }
        return value
    }
}
