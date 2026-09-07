import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Nationwide station search")
struct StationSearchPolicyTests {
    @Test("Exact CRS, name, word prefix, and substring results have useful stable priority")
    func rankedResults() {
        let stations = [
            station("EDB", "Édinburgh Waverley"),
            station("EDG", "Edinburgh Gateway"),
            station("XED", "New Edinburgh"),
            station("ABC", "Across Town"),
            station("CRS", "London Cross"),
        ]

        #expect(StationSearchPolicy.results(matching: " edb ", in: stations).first?.crs
            == "EDB")
        #expect(StationSearchPolicy.results(matching: "EDINBURGH", in: stations).map(\.crs)
            == ["EDG", "EDB", "XED"])
        #expect(StationSearchPolicy.results(matching: "cross", in: stations).map(\.crs)
            == ["CRS", "ABC"])
    }

    @Test("The selected origin is excluded and result work remains bounded")
    func exclusionAndBound() {
        let stations = (0..<2_606).map { index in
            station(String(format: "S%04d", index), "Station \(index)")
        }

        let results = StationSearchPolicy.results(
            matching: "station",
            in: stations,
            excludingCRS: " s0000 "
        )

        #expect(results.count == StationSearchPolicy.defaultMaximumResultCount)
        #expect(!results.contains { $0.crs == "S0000" })
        #expect(results.first?.name == "Station 1")
        #expect(Set(results.map(\.crs)).count == results.count)
    }

    @Test("Whitespace and accents are normalized consistently")
    func normalization() {
        #expect(StationSearchPolicy.normalizedText("  King’s   Cross ") == "king’s cross")
        #expect(StationSearchPolicy.normalizedText("PÉNZANCE") == "penzance")
        #expect(StationSearchPolicy.results(matching: "   ", in: [station("PNZ", "Penzance")])
            .isEmpty)
    }

    private func station(_ crs: String, _ name: String) -> Station {
        Station(crs: crs, name: name, latitude: 51, longitude: 0)
    }
}
