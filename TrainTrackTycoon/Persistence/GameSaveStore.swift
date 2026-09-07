import Foundation

nonisolated enum GameSaveStoreError: Error, Equatable, LocalizedError, Sendable {
    case applicationSupportDirectoryUnavailable
    case corruptSave(fileURL: URL)
    case unsupportedSchemaVersion(found: Int, supported: Int)
    case invalidSnapshot(reason: String)
    case readFailed(fileURL: URL, reason: String)
    case writeFailed(fileURL: URL, reason: String)
    case deleteFailed(fileURL: URL, reason: String)

    var errorDescription: String? {
        switch self {
        case .applicationSupportDirectoryUnavailable:
            "TrainTrack Tycoon could not locate Application Support for saved games."
        case let .corruptSave(fileURL):
            "The saved game at \(fileURL.lastPathComponent) is damaged or incomplete."
        case let .unsupportedSchemaVersion(found, supported):
            "This saved game uses version \(found), but this version of TrainTrack Tycoon supports version \(supported)."
        case let .invalidSnapshot(reason):
            "The game could not be saved because its data is invalid: \(reason)"
        case let .readFailed(fileURL, reason):
            "The saved game at \(fileURL.lastPathComponent) could not be read: \(reason)"
        case let .writeFailed(fileURL, reason):
            "The game could not be saved to \(fileURL.lastPathComponent): \(reason)"
        case let .deleteFailed(fileURL, reason):
            "The saved game at \(fileURL.lastPathComponent) could not be deleted: \(reason)"
        }
    }
}

/// Actor-isolated JSON persistence for the single local game slot.
actor GameSaveStore {
    private let suppliedFileURL: URL?

    /// Creates a store at an injectable location, or at the app's default Application Support
    /// location when `fileURL` is nil.
    init(fileURL: URL? = nil) {
        suppliedFileURL = fileURL
    }

    nonisolated static func defaultFileURL() throws -> URL {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw GameSaveStoreError.applicationSupportDirectoryUnavailable
        }

        return applicationSupport
            .appendingPathComponent("TrainTrack Tycoon", isDirectory: true)
            .appendingPathComponent("saved-game.json", isDirectory: false)
    }

    /// Returns nil when no saved game exists.
    func load() throws -> GameSaveSnapshot? {
        let fileURL = try resolvedFileURL()
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw GameSaveStoreError.readFailed(
                fileURL: fileURL,
                reason: error.localizedDescription
            )
        }

        let header: SaveHeader
        do {
            header = try decoder().decode(SaveHeader.self, from: data)
        } catch {
            throw GameSaveStoreError.corruptSave(fileURL: fileURL)
        }

        let snapshot: GameSaveSnapshot
        switch header.schemaVersion {
        case 1:
            do {
                snapshot = migrate(
                    try decoder().decode(LegacyV1Snapshot.self, from: data)
                )
            } catch {
                throw GameSaveStoreError.corruptSave(fileURL: fileURL)
            }

        case 2:
            do {
                snapshot = migrate(
                    try decoder().decode(LegacyV2Snapshot.self, from: data)
                )
            } catch {
                throw GameSaveStoreError.corruptSave(fileURL: fileURL)
            }

        case 3:
            do {
                snapshot = migrate(
                    try decoder().decode(LegacyV3Snapshot.self, from: data)
                )
            } catch {
                throw GameSaveStoreError.corruptSave(fileURL: fileURL)
            }

        case 4:
            do {
                snapshot = migrate(
                    try decoder().decode(LegacyV4Snapshot.self, from: data)
                )
            } catch {
                throw GameSaveStoreError.corruptSave(fileURL: fileURL)
            }

        case 5:
            do {
                snapshot = migrate(
                    try decoder().decode(LegacyV5Snapshot.self, from: data)
                )
            } catch {
                throw GameSaveStoreError.corruptSave(fileURL: fileURL)
            }

        case 6:
            do {
                snapshot = migrate(
                    try decoder().decode(LegacyV6Snapshot.self, from: data)
                )
            } catch {
                throw GameSaveStoreError.corruptSave(fileURL: fileURL)
            }

        case 7:
            do {
                snapshot = migrate(
                    try decoder().decode(LegacyV7Snapshot.self, from: data)
                )
            } catch {
                throw GameSaveStoreError.corruptSave(fileURL: fileURL)
            }

        case 8:
            do {
                snapshot = migrate(
                    try decoder().decode(LegacyV8Snapshot.self, from: data)
                )
            } catch {
                throw GameSaveStoreError.corruptSave(fileURL: fileURL)
            }

        case 9:
            do {
                snapshot = migrate(
                    try decoder().decode(LegacyV9Snapshot.self, from: data)
                )
            } catch {
                throw GameSaveStoreError.corruptSave(fileURL: fileURL)
            }

        case 10:
            do {
                snapshot = migrate(
                    try decoder().decode(LegacyV10Snapshot.self, from: data)
                )
            } catch {
                throw GameSaveStoreError.corruptSave(fileURL: fileURL)
            }

        case 11:
            do {
                snapshot = migrate(
                    try decoder().decode(LegacyV11Snapshot.self, from: data)
                )
            } catch {
                throw GameSaveStoreError.corruptSave(fileURL: fileURL)
            }

        case GameSaveSnapshot.currentSchemaVersion:
            do {
                // Native schema 12 deliberately has no fallback decoding. Corridor identity,
                // ordered stations, per-slot service plans, railway class,
                // operations choices, capital ownership, complete financial state and bounded
                // history must all be explicit, as must connected-station population state and
                // the purchased formation shared by each line's trainsets.
                snapshot = try decoder().decode(GameSaveSnapshot.self, from: data)
            } catch {
                throw GameSaveStoreError.corruptSave(fileURL: fileURL)
            }

        default:
            throw GameSaveStoreError.unsupportedSchemaVersion(
                found: header.schemaVersion,
                supported: GameSaveSnapshot.currentSchemaVersion
            )
        }

        guard validationFailure(
            in: snapshot,
            allowsIncompleteLegacyFleet: header.schemaVersion == 1,
            allowsMissingLegacyStationPopulations: header.schemaVersion <= 8
        ) == nil else {
            throw GameSaveStoreError.corruptSave(fileURL: fileURL)
        }
        return snapshot
    }

    /// Replaces the single save slot using Foundation's atomic file replacement.
    func save(_ snapshot: GameSaveSnapshot) throws {
        guard snapshot.schemaVersion == GameSaveSnapshot.currentSchemaVersion else {
            throw GameSaveStoreError.unsupportedSchemaVersion(
                found: snapshot.schemaVersion,
                supported: GameSaveSnapshot.currentSchemaVersion
            )
        }
        if let failure = validationFailure(in: snapshot) {
            throw GameSaveStoreError.invalidSnapshot(reason: failure)
        }

        let fileURL = try resolvedFileURL()
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch let error as GameSaveStoreError {
            throw error
        } catch {
            throw GameSaveStoreError.writeFailed(
                fileURL: fileURL,
                reason: error.localizedDescription
            )
        }
    }

    /// Deletes the save slot. Deleting an already-empty slot succeeds.
    func delete() throws {
        let fileURL = try resolvedFileURL()
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw GameSaveStoreError.deleteFailed(
                fileURL: fileURL,
                reason: error.localizedDescription
            )
        }
    }

    private func resolvedFileURL() throws -> URL {
        if let suppliedFileURL { return suppliedFileURL }
        return try Self.defaultFileURL()
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private func migrate(_ legacy: LegacyV1Snapshot) -> GameSaveSnapshot {
        let lines = legacy.lines.map { line in
            SavedLineRecord(
                id: line.id,
                originCRS: line.originCRS,
                destinationCRS: line.destinationCRS,
                styleIndex: line.styleIndex,
                constructionProgress: line.constructionProgress,
                frequency: .halfHourly,
                railwayClass: .conventional,
                servicePattern: .balanced,
                trackCapacity: .singleTrack,
                ownedTrainCount: SavedServiceFrequency.halfHourly.visibleTrainCount,
                trains: [
                    SavedTrainRecord(
                        id: line.train.id,
                        normalizedRouteProgress: line.train.normalizedRouteProgress,
                        direction: line.train.direction,
                        dwellRemaining: line.train.dwellRemaining
                    ),
                ],
                stationCRSs: migratedStationCRSs(
                    origin: line.originCRS,
                    destination: line.destinationCRS
                )
            )
        }

        return GameSaveSnapshot(
            schemaVersion: GameSaveSnapshot.currentSchemaVersion,
            savedAt: legacy.savedAt,
            isPlaying: legacy.isPlaying,
            simulationSpeed: legacy.simulationSpeed,
            lines: lines,
            stationProgress: migratedStationProgress(for: lines),
            economy: .zero,
            financialState: .migratedZen(
                trackingStartedOnOperatingDay: 0,
                hasIncompleteCapitalHistory: !lines.isEmpty
            )
        )
    }

    private func migrate(_ legacy: LegacyV2Snapshot) -> GameSaveSnapshot {
        let lines = legacy.lines.map { line in
            SavedLineRecord(
                id: line.id,
                originCRS: line.originCRS,
                destinationCRS: line.destinationCRS,
                styleIndex: line.styleIndex,
                constructionProgress: line.constructionProgress,
                frequency: line.frequency,
                railwayClass: .conventional,
                servicePattern: .balanced,
                trackCapacity: .singleTrack,
                ownedTrainCount: line.trains.count,
                trains: line.trains.map { train in
                    SavedTrainRecord(
                        id: train.id,
                        normalizedRouteProgress: train.normalizedRouteProgress,
                        direction: train.direction,
                        dwellRemaining: train.dwellRemaining
                    )
                },
                stationCRSs: migratedStationCRSs(
                    origin: line.originCRS,
                    destination: line.destinationCRS
                )
            )
        }

        return GameSaveSnapshot(
            schemaVersion: GameSaveSnapshot.currentSchemaVersion,
            savedAt: legacy.savedAt,
            isPlaying: legacy.isPlaying,
            simulationSpeed: legacy.simulationSpeed,
            lines: lines,
            stationProgress: migratedStationProgress(for: lines),
            economy: .zero,
            financialState: .migratedZen(
                trackingStartedOnOperatingDay: 0,
                hasIncompleteCapitalHistory: !lines.isEmpty
            )
        )
    }

    private func migrate(_ legacy: LegacyV3Snapshot) -> GameSaveSnapshot {
        let lines = legacy.lines.map { line in
            SavedLineRecord(
                id: line.id,
                originCRS: line.originCRS,
                destinationCRS: line.destinationCRS,
                styleIndex: line.styleIndex,
                constructionProgress: line.constructionProgress,
                frequency: line.frequency,
                railwayClass: .conventional,
                servicePattern: .balanced,
                trackCapacity: .singleTrack,
                ownedTrainCount: line.trains.count,
                trains: line.trains.map { train in
                    SavedTrainRecord(
                        id: train.id,
                        normalizedRouteProgress: train.normalizedRouteProgress,
                        direction: train.direction,
                        dwellRemaining: train.dwellRemaining
                    )
                },
                stationCRSs: migratedStationCRSs(
                    origin: line.originCRS,
                    destination: line.destinationCRS
                )
            )
        }

        return GameSaveSnapshot(
            schemaVersion: GameSaveSnapshot.currentSchemaVersion,
            savedAt: legacy.savedAt,
            isPlaying: legacy.isPlaying,
            simulationSpeed: legacy.simulationSpeed,
            lines: lines,
            stationProgress: legacy.stationProgress,
            economy: legacy.economy,
            financialState: .migratedZen(
                trackingStartedOnOperatingDay: legacy.economy.completedOperatingDays,
                hasIncompleteCapitalHistory: !lines.isEmpty
            )
        )
    }

    private func migrate(_ legacy: LegacyV4Snapshot) -> GameSaveSnapshot {
        // Schema 4 had no durable way to distinguish a native Zen network from one migrated
        // from an older schema. Preserve accuracy conservatively for every nonempty Zen network,
        // including one that bought more assets after an earlier migration.
        let capitalHistoryWasAlreadyIncomplete = !legacy.lines.isEmpty
            && legacy.financialState.mode == .zen

        return GameSaveSnapshot(
            schemaVersion: GameSaveSnapshot.currentSchemaVersion,
            savedAt: legacy.savedAt,
            isPlaying: legacy.isPlaying,
            simulationSpeed: legacy.simulationSpeed,
            lines: legacy.lines.map(migratedOperationsLine),
            stationProgress: legacy.stationProgress,
            economy: legacy.economy,
            financialState: SavedFinancialState(
                mode: legacy.financialState.mode,
                cashBalancePence: legacy.financialState.cashBalancePence,
                loans: legacy.financialState.loans,
                lifetimeConstructionSpendPence:
                    legacy.financialState.lifetimeConstructionSpendPence,
                lifetimeRollingStockSpendPence:
                    legacy.financialState.lifetimeRollingStockSpendPence,
                lifetimeLoanProceedsPence:
                    legacy.financialState.lifetimeLoanProceedsPence,
                lifetimePrincipalRepaidPence:
                    legacy.financialState.lifetimePrincipalRepaidPence,
                lifetimeInterestPaidPence:
                    legacy.financialState.lifetimeInterestPaidPence,
                hasIncompleteCapitalHistory: capitalHistoryWasAlreadyIncomplete,
                consecutiveNegativeCashDays:
                    legacy.financialState.consecutiveNegativeCashDays,
                bankruptcyOperatingDay: legacy.financialState.bankruptcyOperatingDay,
                trackingStartedOnOperatingDay:
                    legacy.financialState.trackingStartedOnOperatingDay
            )
        )
    }

    private func migrate(_ legacy: LegacyV5Snapshot) -> GameSaveSnapshot {
        GameSaveSnapshot(
            schemaVersion: GameSaveSnapshot.currentSchemaVersion,
            savedAt: legacy.savedAt,
            isPlaying: legacy.isPlaying,
            simulationSpeed: legacy.simulationSpeed,
            lines: legacy.lines.map(migratedOperationsLine),
            stationProgress: legacy.stationProgress,
            economy: legacy.economy,
            financialState: legacy.financialState
        )
    }

    private func migrate(_ legacy: LegacyV6Snapshot) -> GameSaveSnapshot {
        GameSaveSnapshot(
            schemaVersion: GameSaveSnapshot.currentSchemaVersion,
            savedAt: legacy.savedAt,
            isPlaying: legacy.isPlaying,
            simulationSpeed: legacy.simulationSpeed,
            lines: legacy.lines.map { line in
                SavedLineRecord(
                    id: line.id,
                    originCRS: line.originCRS,
                    destinationCRS: line.destinationCRS,
                    styleIndex: line.styleIndex,
                    constructionProgress: line.constructionProgress,
                    frequency: line.frequency,
                    railwayClass: .conventional,
                    servicePattern: line.servicePattern,
                    trackCapacity: line.trackCapacity,
                    ownedTrainCount: line.ownedTrainCount,
                    trains: line.trains,
                    stationCRSs: migratedStationCRSs(
                        origin: line.originCRS,
                        destination: line.destinationCRS
                    )
                )
            },
            stationProgress: legacy.stationProgress,
            economy: legacy.economy,
            financialState: legacy.financialState
        )
    }

    private func migrate(_ legacy: LegacyV7Snapshot) -> GameSaveSnapshot {
        GameSaveSnapshot(
            schemaVersion: GameSaveSnapshot.currentSchemaVersion,
            savedAt: legacy.savedAt,
            isPlaying: legacy.isPlaying,
            simulationSpeed: legacy.simulationSpeed,
            lines: legacy.lines.map(migratedFormationLine),
            stationProgress: legacy.stationProgress,
            economy: legacy.economy,
            financialState: legacy.financialState,
            publicBetaHistory: PublicBetaDailyNetworkHistory()
        )
    }

    private func migrate(_ legacy: LegacyV8Snapshot) -> GameSaveSnapshot {
        GameSaveSnapshot(
            schemaVersion: GameSaveSnapshot.currentSchemaVersion,
            savedAt: legacy.savedAt,
            isPlaying: legacy.isPlaying,
            simulationSpeed: legacy.simulationSpeed,
            lines: legacy.lines.map(migratedFormationLine),
            stationProgress: legacy.stationProgress,
            stationPopulations: [],
            economy: legacy.economy,
            financialState: legacy.financialState,
            publicBetaHistory: legacy.publicBetaHistory.currentHistory
        )
    }

    private func migrate(_ legacy: LegacyV9Snapshot) -> GameSaveSnapshot {
        GameSaveSnapshot(
            schemaVersion: GameSaveSnapshot.currentSchemaVersion,
            savedAt: legacy.savedAt,
            isPlaying: legacy.isPlaying,
            simulationSpeed: legacy.simulationSpeed,
            lines: legacy.lines.map(migratedFormationLine),
            stationProgress: legacy.stationProgress,
            stationPopulations: legacy.stationPopulations,
            economy: legacy.economy,
            financialState: legacy.financialState,
            publicBetaHistory: legacy.publicBetaHistory
        )
    }

    /// Schema 10 represented a line as both infrastructure and service. Give each historical
    /// line a deterministic corridor identity and two-station ordered corridor while preserving
    /// every historical operational, population and financial value exactly. Migration is data
    /// interpretation only: it never records construction or rolling-stock spending.
    private func migrate(_ legacy: LegacyV10Snapshot) -> GameSaveSnapshot {
        GameSaveSnapshot(
            schemaVersion: GameSaveSnapshot.currentSchemaVersion,
            savedAt: legacy.savedAt,
            isPlaying: legacy.isPlaying,
            simulationSpeed: legacy.simulationSpeed,
            lines: legacy.lines.map { line in
                SavedLineRecord(
                    id: line.id,
                    originCRS: line.originCRS,
                    destinationCRS: line.destinationCRS,
                    styleIndex: line.styleIndex,
                    constructionProgress: line.constructionProgress,
                    frequency: line.frequency,
                    railwayClass: line.railwayClass,
                    formation: line.formation,
                    servicePattern: line.servicePattern,
                    trackCapacity: line.trackCapacity,
                    ownedTrainCount: line.ownedTrainCount,
                    trains: line.trains,
                    corridorIDs: [line.id],
                    stationCRSs: [
                        normalizedCRS(line.originCRS),
                        normalizedCRS(line.destinationCRS),
                    ]
                )
            },
            stationProgress: legacy.stationProgress,
            stationPopulations: legacy.stationPopulations,
            economy: legacy.economy,
            financialState: legacy.financialState,
            publicBetaHistory: legacy.publicBetaHistory
        )
    }

    /// Schema 11 separated physical corridors from services but still derived every train's
    /// stopping plan from the service-wide Local/Balanced/Express preset. Preserve every stored
    /// value and materialise the four deterministic timetable-slot plans without a transaction.
    private func migrate(_ legacy: LegacyV11Snapshot) -> GameSaveSnapshot {
        GameSaveSnapshot(
            schemaVersion: GameSaveSnapshot.currentSchemaVersion,
            savedAt: legacy.savedAt,
            isPlaying: legacy.isPlaying,
            simulationSpeed: legacy.simulationSpeed,
            lines: legacy.lines.map { line in
                SavedLineRecord(
                    id: line.id,
                    originCRS: line.originCRS,
                    destinationCRS: line.destinationCRS,
                    styleIndex: line.styleIndex,
                    constructionProgress: line.constructionProgress,
                    frequency: line.frequency,
                    railwayClass: line.railwayClass,
                    formation: line.formation,
                    servicePattern: line.servicePattern,
                    trackCapacity: line.trackCapacity,
                    ownedTrainCount: line.ownedTrainCount,
                    trains: line.trains,
                    corridorIDs: line.corridorIDs,
                    stationCRSs: line.stationCRSs
                )
            },
            corridors: legacy.corridors,
            stationProgress: legacy.stationProgress,
            stationPopulations: legacy.stationPopulations,
            economy: legacy.economy,
            financialState: legacy.financialState,
            publicBetaHistory: legacy.publicBetaHistory
        )
    }

    /// Schemas 1--9 all used the same 240-seat effective capacity. Representing those fleets as
    /// six-car trainsets preserves their passenger and economy behaviour exactly, while leaving
    /// the historical rolling-stock spend untouched because migration is not a transaction.
    private func migratedFormationLine(
        _ legacy: LegacyV9LineRecord
    ) -> SavedLineRecord {
        SavedLineRecord(
            id: legacy.id,
            originCRS: legacy.originCRS,
            destinationCRS: legacy.destinationCRS,
            styleIndex: legacy.styleIndex,
            constructionProgress: legacy.constructionProgress,
            frequency: legacy.frequency,
            railwayClass: legacy.railwayClass,
            formation: .legacyBaseline,
            servicePattern: legacy.servicePattern,
            trackCapacity: legacy.trackCapacity,
            ownedTrainCount: legacy.ownedTrainCount,
            trains: legacy.trains,
            stationCRSs: migratedStationCRSs(
                origin: legacy.originCRS,
                destination: legacy.destinationCRS
            )
        )
    }

    private func migratedOperationsLine(
        _ legacy: LegacyV5LineRecord
    ) -> SavedLineRecord {
        SavedLineRecord(
            id: legacy.id,
            originCRS: legacy.originCRS,
            destinationCRS: legacy.destinationCRS,
            styleIndex: legacy.styleIndex,
            constructionProgress: legacy.constructionProgress,
            frequency: legacy.frequency,
            railwayClass: .conventional,
            servicePattern: .balanced,
            trackCapacity: .singleTrack,
            ownedTrainCount: legacy.ownedTrainCount,
            trains: legacy.trains,
            stationCRSs: migratedStationCRSs(
                origin: legacy.originCRS,
                destination: legacy.destinationCRS
            )
        )
    }

    private func migratedStationCRSs(
        origin: String,
        destination: String
    ) -> [String] {
        [normalizedCRS(origin), normalizedCRS(destination)]
    }

    private func migratedStationProgress(
        for lines: [SavedLineRecord]
    ) -> [SavedStationProgressRecord] {
        Set(lines.flatMap(\.stationCRSs).map(normalizedCRS))
        .sorted()
        .map { stationCRS in
            SavedStationProgressRecord(
                stationCRS: stationCRS,
                level: .halt,
                lifetimePassengerVisits: 0
            )
        }
    }

    private func normalizedCRS(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private func validationFailure(
        in snapshot: GameSaveSnapshot,
        allowsIncompleteLegacyFleet: Bool = false,
        allowsMissingLegacyStationPopulations: Bool = false
    ) -> String? {
        guard snapshot.lines.count <= GameSaveSnapshot.maximumLineCount else {
            return "a maximum of \(GameSaveSnapshot.maximumLineCount) lines is supported"
        }
        guard snapshot.corridors.count <= GameSaveSnapshot.maximumCorridorCount else {
            return "a maximum of \(GameSaveSnapshot.maximumCorridorCount) corridors is supported"
        }

        var corridorsByID = [UUID: SavedRailwayCorridorRecord]()
        var expectedStationCRSs = Set<String>()
        for corridor in snapshot.corridors {
            guard corridorsByID.updateValue(corridor, forKey: corridor.id) == nil else {
                return "corridor identifiers must be unique"
            }
            guard (2...GameSaveSnapshot.maximumStationsPerCorridor)
                .contains(corridor.stationCRSs.count) else {
                return "each corridor must contain between 2 and \(GameSaveSnapshot.maximumStationsPerCorridor) stations"
            }
            let normalizedStations = corridor.stationCRSs.map(normalizedCRS)
            guard corridor.stationCRSs == normalizedStations,
                  normalizedStations.allSatisfy({ !$0.isEmpty }) else {
                return "corridor station CRS codes must be normalized"
            }
            guard Set(normalizedStations).count == normalizedStations.count else {
                return "a corridor cannot contain the same station more than once"
            }
            expectedStationCRSs.formUnion(normalizedStations)
            guard corridor.constructionProgress.isFinite,
                  (0...1).contains(corridor.constructionProgress) else {
                return "corridor construction progress must be between zero and one"
            }
            guard SavedTrackCapacity.allCases.contains(corridor.trackCapacity),
                  SavedRailwayClass.allCases.contains(corridor.railwayClass) else {
                return "corridor infrastructure choices must be supported"
            }
        }

        var lineIDs = Set<UUID>()
        var trainIDs = Set<UUID>()
        var stationPairs = Set<String>()
        var incompleteLineCount = 0
        for line in snapshot.lines {
            guard lineIDs.insert(line.id).inserted else {
                return "line identifiers must be unique"
            }
            let originCRS = normalizedCRS(line.originCRS)
            let destinationCRS = normalizedCRS(line.destinationCRS)
            guard !originCRS.isEmpty, !destinationCRS.isEmpty else {
                return "each line must reference two stations"
            }
            guard originCRS != destinationCRS else {
                return "a line's origin and destination must be different"
            }
            guard !line.corridorIDs.isEmpty,
                  line.corridorIDs.count <= GameSaveSnapshot.maximumCorridorCount,
                  Set(line.corridorIDs).count == line.corridorIDs.count else {
                return "each service must reference an ordered set of unique corridors"
            }
            let referencedCorridors = line.corridorIDs.compactMap { corridorsByID[$0] }
            guard referencedCorridors.count == line.corridorIDs.count else {
                return "each service must reference stored corridors"
            }
            guard (2...GameSaveSnapshot.maximumStationsPerCorridor)
                .contains(line.stationCRSs.count) else {
                return "each service must call at between 2 and \(GameSaveSnapshot.maximumStationsPerCorridor) stations"
            }
            let normalizedServiceStations = line.stationCRSs.map(normalizedCRS)
            guard line.stationCRSs == normalizedServiceStations,
                  normalizedServiceStations.allSatisfy({ !$0.isEmpty }) else {
                return "service station CRS codes must be normalized"
            }
            guard Set(normalizedServiceStations).count == normalizedServiceStations.count else {
                return "a service cannot call at the same station more than once"
            }
            guard normalizedServiceStations.first == originCRS,
                  normalizedServiceStations.last == destinationCRS else {
                return "service endpoints must match the first and last ordered stations"
            }
            let infrastructureStations = Set(referencedCorridors.flatMap(\.stationCRSs))
            guard Set(normalizedServiceStations).isSubset(of: infrastructureStations) else {
                return "service calls must belong to its referenced corridors"
            }
            guard referencedCorridors.first?.stationCRSs.contains(originCRS) == true,
                  referencedCorridors.last?.stationCRSs.contains(destinationCRS) == true else {
                return "service endpoints must lie on its first and last corridors"
            }
            let physicalChains = connectedStationChains(for: referencedCorridors)
            guard !physicalChains.isEmpty else {
                return "a through service's corridors must form a connected chain"
            }
            let servicePhysicalChains = physicalChains.filter {
                isOrderedSubsequence(normalizedServiceStations, of: $0)
            }
            guard !servicePhysicalChains.isEmpty else {
                return "service calls must follow their physical corridors in order"
            }
            let expectedSlotIndices = Set(0..<GameSaveSnapshot.maximumTrainsPerLine)
            let actualSlotIndices = Set(line.trainServicePlans.map(\.slotIndex))
            guard line.trainServicePlans.count == GameSaveSnapshot.maximumTrainsPerLine,
                  actualSlotIndices == expectedSlotIndices else {
                return "service plans must exactly cover timetable slots 0 through 3"
            }
            for plan in line.trainServicePlans {
                guard (2...GameSaveSnapshot.maximumStationsPerCorridor)
                    .contains(plan.stationCRSs.count) else {
                    return "each train service plan must contain between 2 and \(GameSaveSnapshot.maximumStationsPerCorridor) stations"
                }
                let normalizedPlanStations = plan.stationCRSs.map(normalizedCRS)
                guard plan.stationCRSs == normalizedPlanStations,
                      normalizedPlanStations.allSatisfy({ !$0.isEmpty }) else {
                    return "train service plan station CRS codes must be normalized"
                }
                guard Set(normalizedPlanStations).count == normalizedPlanStations.count else {
                    return "a train service plan cannot call at the same station more than once"
                }
                guard Set(normalizedPlanStations).isSubset(of: Set(normalizedServiceStations)) else {
                    return "train service plan calls must belong to the service's built stations"
                }
                guard isValidServicePlan(
                    normalizedPlanStations,
                    role: plan.role,
                    within: normalizedServiceStations
                ) else {
                    return plan.role == .local
                        ? "a local train must call at every service station between its terminals"
                        : "an express train's calls must follow the service stations in either direction"
                }
            }
            guard referencedCorridors.allSatisfy({ $0.railwayClass == line.railwayClass }) else {
                return "a service's railway class must match every referenced corridor"
            }
            guard referencedCorridors.allSatisfy({ $0.trackCapacity == line.trackCapacity }) else {
                return "a through service requires matching track capacity on every corridor"
            }
            let serviceConstructionProgress = referencedCorridors.reduce(1.0) {
                min($0, $1.constructionProgress)
            }
            guard serviceConstructionProgress == line.constructionProgress else {
                return "service construction progress must match its least-complete corridor"
            }
            let stationPair = [originCRS, destinationCRS].sorted().joined(separator: "|")
            guard stationPairs.insert(stationPair).inserted else {
                return "each station pair can have only one service"
            }
            guard (0..<GameSaveSnapshot.maximumLineCount).contains(line.styleIndex) else {
                return "line style indices must identify a supported line"
            }
            guard line.constructionProgress.isFinite,
                  (0...1).contains(line.constructionProgress) else {
                return "construction progress must be between zero and one"
            }
            if line.constructionProgress < 1 {
                incompleteLineCount += 1
                guard incompleteLineCount <= 1 else {
                    return "only one line can be under construction at a time"
                }
            }

            guard SavedServiceFrequency.allCases.contains(line.frequency) else {
                return "service frequency must identify a supported interval"
            }
            guard SavedServicePattern.allCases.contains(line.servicePattern) else {
                return "service pattern must identify a supported stopping pattern"
            }
            guard SavedTrackCapacity.allCases.contains(line.trackCapacity) else {
                return "track capacity must identify supported infrastructure"
            }
            guard RollingStockFormation.supported(
                for: RailwayClass(line.railwayClass)
            ).contains(line.formation) else {
                return line.railwayClass == .highSpeed
                    ? "high-speed rolling stock must contain between 6 and 12 carriages"
                    : "rolling stock must contain an even number of carriages between 2 and 12"
            }
            let expectedTrainCount = line.frequency.visibleTrainCount
            if allowsIncompleteLegacyFleet {
                guard (1...expectedTrainCount).contains(line.trains.count) else {
                    return "a migrated line cannot contain more trains than its frequency"
                }
            } else if line.trains.count != expectedTrainCount {
                return "a \(line.frequency.rawValue) service must contain \(expectedTrainCount) trains"
            }
            guard (expectedTrainCount...GameSaveSnapshot.maximumOwnedTrainCountPerService)
                .contains(line.ownedTrainCount) else {
                return "owned rolling stock must cover the active service without exceeding the supported fleet"
            }
            for train in line.trains {
                guard trainIDs.insert(train.id).inserted else {
                    return "train identifiers must be unique across the network"
                }
                guard train.normalizedRouteProgress.isFinite,
                      (0...1).contains(train.normalizedRouteProgress) else {
                    return "train route progress must be between zero and one"
                }
                guard train.dwellRemaining.isFinite,
                      train.dwellRemaining >= 0 else {
                    return "train dwell time cannot be negative"
                }
            }
        }

        var savedStationCRSs = Set<String>()
        for station in snapshot.stationProgress {
            let stationCRS = normalizedCRS(station.stationCRS)
            guard !stationCRS.isEmpty, station.stationCRS == stationCRS else {
                return "station progress CRS codes must be normalized"
            }
            guard savedStationCRSs.insert(stationCRS).inserted else {
                return "station progress CRS codes must be unique"
            }
            guard station.lifetimePassengerVisits >= 0 else {
                return "lifetime passenger visits cannot be negative"
            }
        }
        guard savedStationCRSs == expectedStationCRSs else {
            return "station progress must exactly match the corridor stations"
        }

        if allowsMissingLegacyStationPopulations, snapshot.stationPopulations.isEmpty {
            // Schemas 1--8 did not persist settlement growth. GameSession reconciles catalogue
            // baselines before the migrated snapshot is next written in the current schema.
        } else {
            var savedPopulationCRSs = Set<String>()
            for population in snapshot.stationPopulations {
                let stationCRS = normalizedCRS(population.stationCRS)
                guard !stationCRS.isEmpty, population.stationCRS == stationCRS else {
                    return "station population CRS codes must be normalized"
                }
                guard savedPopulationCRSs.insert(stationCRS).inserted else {
                    return "station population CRS codes must be unique"
                }
                guard population.currentPopulation > 0 else {
                    return "connected-station populations must be positive"
                }
                guard population.latestOperatingDayChange >= 0,
                      population.latestOperatingDayChange <= population.currentPopulation else {
                    return "latest population growth must be nonnegative and no greater than the current population"
                }
            }
            guard savedPopulationCRSs == expectedStationCRSs else {
                return "station populations must exactly match the corridor stations"
            }
        }

        let economy = snapshot.economy
        guard economy.operatingDayProgress.isFinite,
              (0..<1).contains(economy.operatingDayProgress) else {
            return "operating-day progress must be at least zero and less than one"
        }
        if !snapshot.lines.contains(where: { $0.constructionProgress >= 1 }),
           economy.operatingDayProgress != 0 {
            return "operating-day progress requires an operating line"
        }
        guard economy.lifetimeRevenuePence >= 0 else {
            return "lifetime revenue cannot be negative"
        }
        guard economy.lifetimeOperatingCostPence >= 0 else {
            return "lifetime operating cost cannot be negative"
        }
        if let failure = financialValidationFailure(
            in: snapshot.financialState,
            completedOperatingDays: economy.completedOperatingDays,
            isPlaying: snapshot.isPlaying
        ) {
            return failure
        }
        if let failure = publicBetaHistoryValidationFailure(
            in: snapshot.publicBetaHistory,
            completedOperatingDays: economy.completedOperatingDays
        ) {
            return failure
        }
        return nil
    }

    /// Returns the at-most-two possible orientations for an ordered corridor chain. Once the
    /// first corridor's direction is selected, every subsequent orientation is unambiguous.
    /// This keeps validation bounded even for a malicious document containing the maximum count.
    private func connectedStationChains(
        for corridors: [SavedRailwayCorridorRecord]
    ) -> [[String]] {
        guard let first = corridors.first else { return [] }
        return [first.stationCRSs, Array(first.stationCRSs.reversed())].compactMap { initial in
            var chain = Array(initial)
            for corridor in corridors.dropFirst() {
                guard let joiningStation = chain.last else { return nil }
                let orientedStations: [String]
                if corridor.stationCRSs.first == joiningStation {
                    orientedStations = corridor.stationCRSs
                } else if corridor.stationCRSs.last == joiningStation {
                    orientedStations = Array(corridor.stationCRSs.reversed())
                } else {
                    return nil
                }
                chain.append(contentsOf: orientedStations.dropFirst())
            }
            return chain
        }
    }

    private func isOrderedSubsequence(
        _ candidate: [String],
        of sequence: [String]
    ) -> Bool {
        var candidateIndex = candidate.startIndex
        for value in sequence where candidateIndex < candidate.endIndex {
            if value == candidate[candidateIndex] {
                candidate.formIndex(after: &candidateIndex)
            }
        }
        return candidateIndex == candidate.endIndex
    }

    /// A train may advertise either orientation of the parent service. Express plans can skip any
    /// built station, while Local retains the role's deterministic meaning by calling everywhere
    /// between its independently chosen terminals.
    private func isValidServicePlan(
        _ candidate: [String],
        role: SavedTrainServiceRole,
        within serviceStations: [String]
    ) -> Bool {
        guard candidate.count >= 2 else { return false }
        return [serviceStations, Array(serviceStations.reversed())].contains { orientedStations in
            guard isOrderedSubsequence(candidate, of: orientedStations) else { return false }
            guard role == .local,
                  let firstTerminalIndex = orientedStations.firstIndex(of: candidate[0]),
                  let lastTerminalIndex = orientedStations.firstIndex(of: candidate[candidate.count - 1]),
                  firstTerminalIndex <= lastTerminalIndex
            else {
                return role == .express
            }
            return Array(orientedStations[firstTerminalIndex...lastTerminalIndex]) == candidate
        }
    }

    private func publicBetaHistoryValidationFailure(
        in history: PublicBetaDailyNetworkHistory,
        completedOperatingDays: UInt64
    ) -> String? {
        guard history.maximumRecordCount == PublicBetaDailyNetworkHistory.defaultMaximumRecordCount,
              history.records.count <= PublicBetaDailyNetworkHistory.defaultMaximumRecordCount else {
            return "public-beta history must use the supported 120-day bound"
        }

        var previousDay: UInt64?
        for record in history.records {
            guard record.operatingDay > 0,
                  record.operatingDay <= completedOperatingDays else {
                return "public-beta history days must belong to the saved operating history"
            }
            if let previousDay, record.operatingDay <= previousDay {
                return "public-beta history days must be unique and sorted"
            }
            previousDay = record.operatingDay
            guard record.totalNetworkPopulation >= 0,
                  record.latestPopulationChange >= 0,
                  record.latestPopulationChange <= record.totalNetworkPopulation else {
                return "public-beta history population totals and changes are invalid"
            }
        }
        return nil
    }

    private func financialValidationFailure(
        in financialState: SavedFinancialState,
        completedOperatingDays: UInt64,
        isPlaying: Bool
    ) -> String? {
        guard financialState.trackingStartedOnOperatingDay <= completedOperatingDays else {
            return "financial tracking cannot begin after the latest completed operating day"
        }
        guard financialState.lifetimeConstructionSpendPence >= 0,
              financialState.lifetimeRollingStockSpendPence >= 0,
              financialState.lifetimeLoanProceedsPence >= 0,
              financialState.lifetimePrincipalRepaidPence >= 0,
              financialState.lifetimeInterestPaidPence >= 0 else {
            return "lifetime financial totals cannot be negative"
        }
        guard financialState.lifetimePrincipalRepaidPence
                <= financialState.lifetimeLoanProceedsPence else {
            return "lifetime principal repayments cannot exceed loan proceeds"
        }
        guard financialState.consecutiveNegativeCashDays >= 0 else {
            return "consecutive negative-cash days cannot be negative"
        }
        guard !financialState.hasIncompleteCapitalHistory
                || financialState.mode == .zen else {
            return "only a migrated Zen game can have incomplete capital history"
        }
        guard financialState.loans.count <= GameSaveSnapshot.maximumActiveLoanCount else {
            return "too many active loans are stored"
        }

        var loanIDs = Set<UUID>()
        for loan in financialState.loans {
            guard loanIDs.insert(loan.id).inserted else {
                return "loan identifiers must be unique"
            }
            guard loan.originalPrincipalPence > 0,
                  loan.outstandingPrincipalPence > 0,
                  loan.outstandingPrincipalPence <= loan.originalPrincipalPence else {
                return "active loan principal balances are invalid"
            }
            guard (0...10_000).contains(loan.annualInterestBasisPoints) else {
                return "annual loan interest must be between zero and one hundred percent"
            }
            guard loan.termOperatingDays > 0,
                  (1...loan.termOperatingDays).contains(loan.remainingOperatingDays) else {
                return "loan terms and remaining duration are invalid"
            }
            guard loan.originatedOnOperatingDay >= financialState.trackingStartedOnOperatingDay,
                  loan.originatedOnOperatingDay <= completedOperatingDays else {
                return "loan origination must fall within the tracked operating history"
            }
        }
        let outstandingPrincipal = financialState.loans.reduce(Int64(0)) { result, loan in
            EconomyArithmetic.add(result, loan.outstandingPrincipalPence)
        }
        let activeOriginalPrincipal = financialState.loans.reduce(Int64(0)) { result, loan in
            EconomyArithmetic.add(result, loan.originalPrincipalPence)
        }
        guard activeOriginalPrincipal <= financialState.lifetimeLoanProceedsPence else {
            return "active loan principals cannot exceed lifetime loan proceeds"
        }
        guard EconomyArithmetic.add(
            outstandingPrincipal,
            financialState.lifetimePrincipalRepaidPence
        ) == financialState.lifetimeLoanProceedsPence else {
            return "active debt and lifetime repayments must reconcile with loan proceeds"
        }

        switch financialState.mode {
        case .zen:
            guard financialState.cashBalancePence == 0,
                  financialState.loans.isEmpty,
                  financialState.lifetimeLoanProceedsPence == 0,
                  financialState.lifetimePrincipalRepaidPence == 0,
                  financialState.lifetimeInterestPaidPence == 0,
                  financialState.consecutiveNegativeCashDays == 0,
                  financialState.bankruptcyOperatingDay == nil else {
                return "Zen games cannot contain cash, debt or bankruptcy state"
            }

        case .career:
            if financialState.cashBalancePence < 0 {
                guard financialState.consecutiveNegativeCashDays > 0 else {
                    return "negative Career cash must count toward insolvency"
                }
            } else {
                guard financialState.consecutiveNegativeCashDays == 0 else {
                    return "nonnegative Career cash cannot retain insolvency days"
                }
            }

            if let bankruptcyOperatingDay = financialState.bankruptcyOperatingDay {
                guard bankruptcyOperatingDay >= financialState.trackingStartedOnOperatingDay,
                      bankruptcyOperatingDay <= completedOperatingDays,
                      financialState.cashBalancePence < 0,
                      financialState.consecutiveNegativeCashDays > 0,
                      !isPlaying else {
                    return "bankruptcy state is inconsistent with the saved Career game"
                }
            }
        }
        return nil
    }
}

private nonisolated struct SaveHeader: Decodable {
    let schemaVersion: Int
}

/// Exact decoder-only representation of the schema shipped before multi-train services.
private nonisolated struct LegacyV1Snapshot: Decodable {
    let schemaVersion: Int
    let savedAt: Date
    let isPlaying: Bool
    let simulationSpeed: SavedSimulationSpeed
    let lines: [LegacyV1LineRecord]
}

private nonisolated struct LegacyV1LineRecord: Decodable {
    let id: UUID
    let originCRS: String
    let destinationCRS: String
    let styleIndex: Int
    let constructionProgress: Double
    let train: LegacyV1TrainRecord
}

private nonisolated struct LegacyV1TrainRecord: Decodable {
    let id: UUID
    let normalizedRouteProgress: Double
    let direction: SavedTrainDirection
    let dwellRemaining: TimeInterval
}

/// Exact decoder-only representation of the multi-train schema shipped before station evolution.
private nonisolated struct LegacyV2Snapshot: Decodable {
    let schemaVersion: Int
    let savedAt: Date
    let isPlaying: Bool
    let simulationSpeed: SavedSimulationSpeed
    let lines: [LegacyV2LineRecord]
}

private nonisolated struct LegacyV2LineRecord: Decodable {
    let id: UUID
    let originCRS: String
    let destinationCRS: String
    let styleIndex: Int
    let constructionProgress: Double
    let frequency: SavedServiceFrequency
    let trains: [LegacyV2TrainRecord]
}

private nonisolated struct LegacyV2TrainRecord: Decodable {
    let id: UUID
    let normalizedRouteProgress: Double
    let direction: SavedTrainDirection
    let dwellRemaining: TimeInterval
}

/// Exact decoder-only representation of the schema shipped before capital ownership and modes.
private nonisolated struct LegacyV3Snapshot: Decodable {
    let schemaVersion: Int
    let savedAt: Date
    let isPlaying: Bool
    let simulationSpeed: SavedSimulationSpeed
    let lines: [LegacyV2LineRecord]
    let stationProgress: [SavedStationProgressRecord]
    let economy: SavedEconomyLedger
}

/// Exact decoder-only representation shipped before capital-history completeness was explicit.
private nonisolated struct LegacyV4Snapshot: Decodable {
    let schemaVersion: Int
    let savedAt: Date
    let isPlaying: Bool
    let simulationSpeed: SavedSimulationSpeed
    let lines: [LegacyV5LineRecord]
    let stationProgress: [SavedStationProgressRecord]
    let economy: SavedEconomyLedger
    let financialState: LegacyV4FinancialState
}

/// Exact decoder-only representation shipped before service patterns and track capacity.
private nonisolated struct LegacyV5Snapshot: Decodable {
    let schemaVersion: Int
    let savedAt: Date
    let isPlaying: Bool
    let simulationSpeed: SavedSimulationSpeed
    let lines: [LegacyV5LineRecord]
    let stationProgress: [SavedStationProgressRecord]
    let economy: SavedEconomyLedger
    let financialState: SavedFinancialState
}

private nonisolated struct LegacyV5LineRecord: Decodable {
    let id: UUID
    let originCRS: String
    let destinationCRS: String
    let styleIndex: Int
    let constructionProgress: Double
    let frequency: SavedServiceFrequency
    let ownedTrainCount: Int
    let trains: [SavedTrainRecord]
}

/// Exact decoder-only representation shipped before dedicated high-speed infrastructure.
private nonisolated struct LegacyV6Snapshot: Decodable {
    let schemaVersion: Int
    let savedAt: Date
    let isPlaying: Bool
    let simulationSpeed: SavedSimulationSpeed
    let lines: [LegacyV6LineRecord]
    let stationProgress: [SavedStationProgressRecord]
    let economy: SavedEconomyLedger
    let financialState: SavedFinancialState
}

private nonisolated struct LegacyV6LineRecord: Decodable {
    let id: UUID
    let originCRS: String
    let destinationCRS: String
    let styleIndex: Int
    let constructionProgress: Double
    let frequency: SavedServiceFrequency
    let servicePattern: SavedServicePattern
    let trackCapacity: SavedTrackCapacity
    let ownedTrainCount: Int
    let trains: [SavedTrainRecord]
}

/// Exact decoder-only representation shipped before bounded public-beta daily history.
private nonisolated struct LegacyV7Snapshot: Decodable {
    let schemaVersion: Int
    let savedAt: Date
    let isPlaying: Bool
    let simulationSpeed: SavedSimulationSpeed
    let lines: [LegacyV9LineRecord]
    let stationProgress: [SavedStationProgressRecord]
    let economy: SavedEconomyLedger
    let financialState: SavedFinancialState
}

/// Exact decoder-only representation shipped before settlement population became durable.
///
/// Its nested history records also predate population totals, so they are converted explicitly
/// rather than weakening native schema-10 decoding with missing-key defaults.
private nonisolated struct LegacyV8Snapshot: Decodable {
    let schemaVersion: Int
    let savedAt: Date
    let isPlaying: Bool
    let simulationSpeed: SavedSimulationSpeed
    let lines: [LegacyV9LineRecord]
    let stationProgress: [SavedStationProgressRecord]
    let economy: SavedEconomyLedger
    let financialState: SavedFinancialState
    let publicBetaHistory: LegacyV8DailyNetworkHistory
}

/// Exact decoder-only representation shipped before purchased carriage formations.
///
/// Keeping this separate from `SavedLineRecord` makes native schema-10 decoding strict without
/// breaking genuine schema 7--9 documents, all of which lacked the formation key.
private nonisolated struct LegacyV9Snapshot: Decodable {
    let schemaVersion: Int
    let savedAt: Date
    let isPlaying: Bool
    let simulationSpeed: SavedSimulationSpeed
    let lines: [LegacyV9LineRecord]
    let stationProgress: [SavedStationProgressRecord]
    let stationPopulations: [SavedStationPopulationRecord]
    let economy: SavedEconomyLedger
    let financialState: SavedFinancialState
    let publicBetaHistory: PublicBetaDailyNetworkHistory
}

private nonisolated struct LegacyV9LineRecord: Decodable {
    let id: UUID
    let originCRS: String
    let destinationCRS: String
    let styleIndex: Int
    let constructionProgress: Double
    let frequency: SavedServiceFrequency
    let servicePattern: SavedServicePattern
    let trackCapacity: SavedTrackCapacity
    let railwayClass: SavedRailwayClass
    let ownedTrainCount: Int
    let trains: [SavedTrainRecord]
}

/// Exact decoder-only representation shipped before infrastructure corridor identity and ordered
/// corridor stations became durable. Keeping it separate makes native schema-11 decoding strict.
private nonisolated struct LegacyV10Snapshot: Decodable {
    let schemaVersion: Int
    let savedAt: Date
    let isPlaying: Bool
    let simulationSpeed: SavedSimulationSpeed
    let lines: [LegacyV10LineRecord]
    let stationProgress: [SavedStationProgressRecord]
    let stationPopulations: [SavedStationPopulationRecord]
    let economy: SavedEconomyLedger
    let financialState: SavedFinancialState
    let publicBetaHistory: PublicBetaDailyNetworkHistory
}

private nonisolated struct LegacyV10LineRecord: Decodable {
    let id: UUID
    let originCRS: String
    let destinationCRS: String
    let styleIndex: Int
    let constructionProgress: Double
    let frequency: SavedServiceFrequency
    let servicePattern: SavedServicePattern
    let trackCapacity: SavedTrackCapacity
    let railwayClass: SavedRailwayClass
    let formation: RollingStockFormation
    let ownedTrainCount: Int
    let trains: [SavedTrainRecord]
}

/// Exact decoder-only representation shipped before per-slot Local/Express service plans.
/// Keeping it separate makes the new schema's plan collection mandatory and strict.
private nonisolated struct LegacyV11Snapshot: Decodable {
    let schemaVersion: Int
    let savedAt: Date
    let isPlaying: Bool
    let simulationSpeed: SavedSimulationSpeed
    let corridors: [SavedRailwayCorridorRecord]
    let lines: [LegacyV11LineRecord]
    let stationProgress: [SavedStationProgressRecord]
    let stationPopulations: [SavedStationPopulationRecord]
    let economy: SavedEconomyLedger
    let financialState: SavedFinancialState
    let publicBetaHistory: PublicBetaDailyNetworkHistory
}

private nonisolated struct LegacyV11LineRecord: Decodable {
    let id: UUID
    let corridorIDs: [UUID]
    let originCRS: String
    let destinationCRS: String
    let stationCRSs: [String]
    let styleIndex: Int
    let constructionProgress: Double
    let frequency: SavedServiceFrequency
    let servicePattern: SavedServicePattern
    let trackCapacity: SavedTrackCapacity
    let railwayClass: SavedRailwayClass
    let formation: RollingStockFormation
    let ownedTrainCount: Int
    let trains: [SavedTrainRecord]
}

private nonisolated struct LegacyV8DailyNetworkHistory: Decodable {
    let maximumRecordCount: Int
    let records: [LegacyV8DailyNetworkRecord]

    var currentHistory: PublicBetaDailyNetworkHistory {
        PublicBetaDailyNetworkHistory(
            maximumRecordCount: maximumRecordCount,
            records: records.map(\.currentRecord)
        )
    }
}

private nonisolated struct LegacyV8DailyNetworkRecord: Decodable {
    let operatingDay: UInt64
    let facts: PublicBetaNetworkFacts
    let operatingResultPence: Int64

    var currentRecord: PublicBetaDailyNetworkRecord {
        PublicBetaDailyNetworkRecord(
            operatingDay: operatingDay,
            facts: facts,
            operatingResultPence: operatingResultPence,
            totalNetworkPopulation: 0,
            latestPopulationChange: 0
        )
    }
}

private nonisolated struct LegacyV4FinancialState: Decodable {
    let mode: GameMode
    let cashBalancePence: Int64
    let loans: [SavedLoanAccount]
    let lifetimeConstructionSpendPence: Int64
    let lifetimeRollingStockSpendPence: Int64
    let lifetimeLoanProceedsPence: Int64
    let lifetimePrincipalRepaidPence: Int64
    let lifetimeInterestPaidPence: Int64
    let consecutiveNegativeCashDays: Int
    let bankruptcyOperatingDay: UInt64?
    let trackingStartedOnOperatingDay: UInt64
}
