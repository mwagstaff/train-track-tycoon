import CoreLocation
import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("M13 network persistence", .serialized)
struct M13NetworkPersistenceTests {
    @Test("Schema 10 becomes one retained corridor and one service without a transaction")
    func schemaTenMigrationPreservesAllPriorState() async throws {
        let lineID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let line = makeLine(id: lineID, origin: "VIC", destination: "BTN", styleIndex: 1)
        let economy = SavedEconomyLedger(
            completedOperatingDays: 7,
            operatingDayProgress: 0.25,
            lifetimeRevenuePence: 987_654,
            lifetimeOperatingCostPence: 123_456
        )
        let finances = SavedFinancialState(
            mode: .career,
            cashBalancePence: 4_500_000_000,
            loans: [],
            lifetimeConstructionSpendPence: 2_345_678_900,
            lifetimeRollingStockSpendPence: 456_789_000,
            lifetimeLoanProceedsPence: 0,
            lifetimePrincipalRepaidPence: 0,
            lifetimeInterestPaidPence: 0,
            consecutiveNegativeCashDays: 0,
            bankruptcyOperatingDay: nil,
            trackingStartedOnOperatingDay: 3
        )
        let expected = snapshot(lines: [line], economy: economy, finances: finances)
        var legacyRoot = try encodedJSONObject(expected)
        legacyRoot["schemaVersion"] = 10
        legacyRoot.removeValue(forKey: "corridors")
        var legacyLines = try #require(legacyRoot["lines"] as? [[String: Any]])
        legacyLines[0].removeValue(forKey: "corridorIDs")
        legacyLines[0].removeValue(forKey: "stationCRSs")
        legacyRoot["lines"] = legacyLines

        let saveURL = temporarySaveURL()
        defer { try? FileManager.default.removeItem(at: saveURL.deletingLastPathComponent()) }
        try write(try JSONSerialization.data(withJSONObject: legacyRoot), to: saveURL)

        let migrated = try #require(try await GameSaveStore(fileURL: saveURL).load())

        #expect(migrated == expected)
        #expect(migrated.lines[0].serviceID == lineID)
        #expect(migrated.lines[0].corridorIDs == [lineID])
        #expect(migrated.lines[0].stationCRSs == ["VIC", "BTN"])
        #expect(migrated.corridors == [
            SavedRailwayCorridorRecord(
                id: lineID,
                stationCRSs: ["VIC", "BTN"],
                constructionProgress: 1
            ),
        ])
        #expect(migrated.economy == economy)
        #expect(migrated.financialState == finances)
    }

    @Test("Schema 11 round-trips a corridor separately from an express service")
    func schemaElevenCorridorAndServiceRoundTrip() async throws {
        let corridorID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let serviceID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let physicalStations = ["VIC", "BRI", "HNH", "KTH"]
        let service = makeLine(
            id: serviceID,
            origin: "VIC",
            destination: "KTH",
            styleIndex: 3,
            corridorIDs: [corridorID],
            stationCRSs: ["VIC", "HNH", "KTH"],
            servicePattern: .express
        )
        let source = snapshot(
            lines: [service],
            corridors: [
                SavedRailwayCorridorRecord(
                    id: corridorID,
                    stationCRSs: physicalStations,
                    constructionProgress: 1
                ),
            ]
        )
        let saveURL = temporarySaveURL()
        defer { try? FileManager.default.removeItem(at: saveURL.deletingLastPathComponent()) }
        let store = GameSaveStore(fileURL: saveURL)

        try await store.save(source)
        let restored = try await store.load()

        #expect(restored == source)
        #expect(restored?.corridors.first?.stationCRSs == physicalStations)
        #expect(restored?.lines.first?.stationCRSs == ["VIC", "HNH", "KTH"])
        #expect(restored?.lines.first?.corridorIDs == [corridorID])
    }

    @Test("Game session restore preserves stations skipped by an express service")
    @MainActor
    func gameSessionPreservesPhysicalCorridorTopology() async throws {
        let corridorID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let serviceID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let physicalStations = ["VIC", "BRI", "HNH", "KTH"]
        let serviceCalls = ["VIC", "HNH", "KTH"]
        let source = snapshot(
            lines: [
                makeLine(
                    id: serviceID,
                    origin: "VIC",
                    destination: "KTH",
                    styleIndex: 0,
                    corridorIDs: [corridorID],
                    stationCRSs: serviceCalls,
                    servicePattern: .express
                ),
            ],
            corridors: [
                SavedRailwayCorridorRecord(
                    id: corridorID,
                    stationCRSs: physicalStations,
                    constructionProgress: 1
                ),
            ],
            includesStationPopulations: false
        )
        let stations = physicalStations.enumerated().map { index, crs in
            Station(
                crs: crs,
                name: crs,
                latitude: 51 + (Double(index) * 0.01),
                longitude: -0.1
            )
        }
        let session = GameSession(
            stations: stations,
            routingProvider: M13OrderedRoutingProvider(),
            configuration: .poc
        )

        try await session.restore(from: source)

        let restoredLine = try #require(session.lines.first)
        #expect(restoredLine.id == serviceID)
        #expect(restoredLine.stationCRSs == serviceCalls)
        #expect(restoredLine.corridorIDs == [corridorID])
        #expect(restoredLine.corridor.stationCRSs == physicalStations)
        #expect(restoredLine.route.stationCoordinateIndices.count == serviceCalls.count)
        #expect(restoredLine.corridor.route.stationCoordinateIndices.count == physicalStations.count)

        let savedAgain = session.makeSaveSnapshot()
        #expect(savedAgain.lines.first?.id == serviceID)
        #expect(savedAgain.lines.first?.stationCRSs == serviceCalls)
        #expect(savedAgain.corridors.first?.id == corridorID)
        #expect(savedAgain.corridors.first?.stationCRSs == physicalStations)
        #expect(Set(savedAgain.stationProgress.map(\.stationCRS)) == Set(physicalStations))
        #expect(Set(savedAgain.stationPopulations.map(\.stationCRS)) == Set(physicalStations))
    }

    @Test("A through service durably references two retained connected corridors")
    func throughServiceRoundTrip() async throws {
        let firstCorridorID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAA1")!
        let secondCorridorID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAA2")!
        let service = makeLine(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            origin: "PUR",
            destination: "HOR",
            styleIndex: 0,
            corridorIDs: [firstCorridorID, secondCorridorID],
            stationCRSs: ["PUR", "ECR", "HOR"]
        )
        let source = snapshot(
            lines: [service],
            corridors: [
                SavedRailwayCorridorRecord(
                    id: firstCorridorID,
                    stationCRSs: ["PUR", "ECR"],
                    constructionProgress: 1
                ),
                SavedRailwayCorridorRecord(
                    id: secondCorridorID,
                    stationCRSs: ["ECR", "HOR"],
                    constructionProgress: 1
                ),
            ]
        )
        let saveURL = temporarySaveURL()
        defer { try? FileManager.default.removeItem(at: saveURL.deletingLastPathComponent()) }
        let store = GameSaveStore(fileURL: saveURL)

        try await store.save(source)

        #expect(try await store.load() == source)
        #expect(try await store.load()?.lines[0].corridorIDs == [
            firstCorridorID,
            secondCorridorID,
        ])
        #expect(try await store.load()?.corridors.count == 2)
    }

    @Test("A service cannot reorder stations along retained infrastructure")
    func serviceCallsFollowPhysicalOrder() async throws {
        let corridorID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let service = makeLine(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            origin: "VIC",
            destination: "KTH",
            styleIndex: 0,
            corridorIDs: [corridorID],
            stationCRSs: ["VIC", "HNH", "BRI", "KTH"]
        )
        let invalid = snapshot(
            lines: [service],
            corridors: [
                SavedRailwayCorridorRecord(
                    id: corridorID,
                    stationCRSs: ["VIC", "BRI", "HNH", "KTH"],
                    constructionProgress: 1
                ),
            ]
        )
        let saveURL = temporarySaveURL()
        defer { try? FileManager.default.removeItem(at: saveURL.deletingLastPathComponent()) }

        do {
            try await GameSaveStore(fileURL: saveURL).save(invalid)
            Issue.record("Expected out-of-order service calls to be rejected")
        } catch let error as GameSaveStoreError {
            guard case let .invalidSnapshot(reason) = error else {
                Issue.record("Expected invalidSnapshot, received \(error)")
                return
            }
            #expect(reason.contains("physical corridors in order"))
        }
    }

    @Test("Five hundred twelve services are durable and the next is rejected")
    func boundedNationalServiceNetwork() async throws {
        #expect(GameConfiguration.poc.maximumLineCount == 512)
        #expect(GameSaveSnapshot.maximumServiceCount == 512)
        #expect(GameSaveSnapshot.maximumLineCount == 512)

        let supportedLines = (0..<512).map(makeNumberedLine)
        let supportedSnapshot = snapshot(lines: supportedLines)
        let saveURL = temporarySaveURL()
        defer { try? FileManager.default.removeItem(at: saveURL.deletingLastPathComponent()) }
        let store = GameSaveStore(fileURL: saveURL)

        try await store.save(supportedSnapshot)
        #expect(try await store.load()?.lines.count == 512)
        #expect(try await store.load()?.corridors.count == 512)

        let overLimitSnapshot = snapshot(lines: (0..<513).map(makeNumberedLine))
        do {
            try await store.save(overLimitSnapshot)
            Issue.record("Expected service 513 to exceed the persistence bound")
        } catch let error as GameSaveStoreError {
            guard case let .invalidSnapshot(reason) = error else {
                Issue.record("Expected invalidSnapshot, received \(error)")
                return
            }
            #expect(reason.contains("maximum of 512 lines"))
        }
    }

    @Test("Native schema 11 requires corridor topology and service references")
    func strictSchemaElevenNetworkDecode() async throws {
        let validRoot = try encodedJSONObject(snapshot(lines: [
            makeLine(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                origin: "VIC",
                destination: "BTN",
                styleIndex: 0
            ),
        ]))

        for missingKey in ["corridors", "corridorIDs", "stationCRSs"] {
            var malformedRoot = validRoot
            if missingKey == "corridors" {
                malformedRoot.removeValue(forKey: missingKey)
            } else {
                var lines = try #require(malformedRoot["lines"] as? [[String: Any]])
                lines[0].removeValue(forKey: missingKey)
                malformedRoot["lines"] = lines
            }
            let saveURL = temporarySaveURL()
            defer { try? FileManager.default.removeItem(at: saveURL.deletingLastPathComponent()) }
            try write(try JSONSerialization.data(withJSONObject: malformedRoot), to: saveURL)

            do {
                _ = try await GameSaveStore(fileURL: saveURL).load()
                Issue.record("Expected missing \(missingKey) to be corrupt")
            } catch let error as GameSaveStoreError {
                #expect(error == .corruptSave(fileURL: saveURL))
            }
        }
    }

    private func makeNumberedLine(_ index: Int) -> SavedLineRecord {
        makeLine(
            id: UUID(uuidString: String(
                format: "10000000-0000-0000-0000-%012d",
                index + 1
            ))!,
            origin: String(format: "A%02d", index),
            destination: String(format: "B%02d", index),
            styleIndex: index,
            trainNumberOffset: index * 2
        )
    }

    private func makeLine(
        id: UUID,
        origin: String,
        destination: String,
        styleIndex: Int,
        corridorIDs: [UUID]? = nil,
        stationCRSs: [String]? = nil,
        servicePattern: SavedServicePattern = .balanced,
        trainNumberOffset: Int = 0
    ) -> SavedLineRecord {
        SavedLineRecord(
            id: id,
            originCRS: origin,
            destinationCRS: destination,
            styleIndex: styleIndex,
            constructionProgress: 1,
            frequency: .halfHourly,
            servicePattern: servicePattern,
            ownedTrainCount: 2,
            trains: (0..<2).map { trainIndex in
                SavedTrainRecord(
                    id: UUID(uuidString: String(
                        format: "20000000-0000-0000-0000-%012d",
                        trainNumberOffset + trainIndex + 1
                    ))!,
                    normalizedRouteProgress: Double(trainIndex) / 2,
                    direction: trainIndex == 0 ? .forward : .reverse,
                    dwellRemaining: 0
                )
            },
            corridorIDs: corridorIDs,
            stationCRSs: stationCRSs
        )
    }

    private func snapshot(
        lines: [SavedLineRecord],
        corridors: [SavedRailwayCorridorRecord]? = nil,
        economy: SavedEconomyLedger = .zero,
        finances: SavedFinancialState = .zero,
        includesStationPopulations: Bool = true
    ) -> GameSaveSnapshot {
        let resolvedCorridors = corridors ?? lines.map { line in
            SavedRailwayCorridorRecord(
                id: line.corridorID,
                stationCRSs: line.stationCRSs,
                constructionProgress: line.constructionProgress,
                railwayClass: line.railwayClass,
                trackCapacity: line.trackCapacity
            )
        }
        let stationCRSs = Set(resolvedCorridors.flatMap(\.stationCRSs)).sorted()
        return GameSaveSnapshot(
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            isPlaying: false,
            simulationSpeed: .threeX,
            lines: lines,
            corridors: resolvedCorridors,
            stationProgress: stationCRSs.map {
                SavedStationProgressRecord(
                    stationCRS: $0,
                    level: .halt,
                    lifetimePassengerVisits: 0
                )
            },
            stationPopulations: includesStationPopulations
                ? stationCRSs.map {
                    SavedStationPopulationRecord(
                        stationCRS: $0,
                        currentPopulation: 100_000,
                        latestOperatingDayChange: 0
                    )
                }
                : [],
            economy: economy,
            financialState: finances
        )
    }

    private func encodedJSONObject(_ snapshot: GameSaveSnapshot) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try #require(
            JSONSerialization.jsonObject(with: encoder.encode(snapshot)) as? [String: Any]
        )
    }

    private func temporarySaveURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TrainTrackTycoon-M13-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("save.json", isDirectory: false)
    }

    private func write(_ data: Data, to fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}

private nonisolated struct M13OrderedRoutingProvider: RailwayRouteProviding {
    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        ServiceRailwayRoute(
            coordinates: stationCRSs.indices.map { index in
                CLLocationCoordinate2D(
                    latitude: 51 + (Double(index) * 0.01),
                    longitude: -0.1
                )
            },
            cumulativeDistances: stationCRSs.indices.map { Double($0) * 1_000 },
            stationCoordinateIndices: Array(stationCRSs.indices)
        )
    }
}
