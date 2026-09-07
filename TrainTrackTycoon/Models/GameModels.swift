import CoreLocation
import Foundation

nonisolated enum GamePhase: String, CaseIterable, Sendable {
    case idle
    case selectingOrigin
    case selectingDestination
    case calculating
    case preview
    case constructing
    case operating
    case error
}

nonisolated enum SimulationSpeed: Double, CaseIterable, Sendable {
    case oneX = 1
    case threeX = 3

    var multiplier: Double { rawValue }

    var label: String {
        switch self {
        case .oneX: "1×"
        case .threeX: "3×"
        }
    }
}

nonisolated enum TrainTravelDirection: Sendable {
    case forward
    case reverse
}

nonisolated enum GameSessionRestoreError: LocalizedError, Equatable, Sendable {
    case unsupportedSchema(Int)
    case stationUnavailable(String)
    case invalidEndpoints(String, String)
    case duplicateConnection(String, String)
    case duplicateIdentifier
    case invalidFleet
    case invalidHighSpeedConfiguration
    case invalidStationProgress
    case invalidNumericValue
    case routeUnavailable(String, String, underlyingDescription: String)
    case unusableRoute(String, String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            "This saved game uses unsupported format version \(version)."
        case let .stationUnavailable(crs):
            "The saved station \(crs) is not available in this version of TrainTrack Tycoon."
        case let .invalidEndpoints(origin, destination):
            "The saved line from \(origin) to \(destination) does not have two valid stations."
        case let .duplicateConnection(origin, destination):
            "The saved game contains more than one service between \(origin) and \(destination)."
        case .duplicateIdentifier:
            "The saved game contains duplicate corridor, service or train identifiers."
        case .invalidFleet:
            "The saved game contains an invalid train fleet or construction state."
        case .invalidHighSpeedConfiguration:
            "The saved game contains an invalid high-speed railway configuration."
        case .invalidStationProgress:
            "The saved game contains invalid station evolution data."
        case .invalidNumericValue:
            "The saved game contains an invalid progress value."
        case let .routeUnavailable(origin, destination, underlyingDescription):
            "The saved \(origin) – \(destination) line could not be restored. \(underlyingDescription)"
        case let .unusableRoute(origin, destination):
            "The saved \(origin) – \(destination) line no longer has a usable railway route."
        }
    }
}

extension SavedSimulationSpeed {
    init(_ speed: SimulationSpeed) {
        switch speed {
        case .oneX: self = .oneX
        case .threeX: self = .threeX
        }
    }
}

extension SimulationSpeed {
    init(_ speed: SavedSimulationSpeed) {
        switch speed {
        case .oneX: self = .oneX
        case .threeX: self = .threeX
        }
    }
}

extension SavedTrainDirection {
    init(_ direction: TrainTravelDirection) {
        switch direction {
        case .forward: self = .forward
        case .reverse: self = .reverse
        }
    }
}

extension TrainTravelDirection {
    init(_ direction: SavedTrainDirection) {
        switch direction {
        case .forward: self = .forward
        case .reverse: self = .reverse
        }
    }
}

extension SavedStationLevel {
    init(_ level: StationLevel) {
        switch level {
        case .halt: self = .halt
        case .localStation: self = .localStation
        case .townStation: self = .townStation
        case .majorStation: self = .majorStation
        case .interchange: self = .interchange
        case .terminus: self = .terminus
        }
    }
}

extension StationLevel {
    init(_ level: SavedStationLevel) {
        switch level {
        case .halt: self = .halt
        case .localStation: self = .localStation
        case .townStation: self = .townStation
        case .majorStation: self = .majorStation
        case .interchange: self = .interchange
        case .terminus: self = .terminus
        }
    }
}

nonisolated struct GameConfiguration: Sendable, Equatable {
    var maximumLineCount: Int
    var constructionDuration: TimeInterval
    var trainSpeedMetresPerSecond: CLLocationSpeed
    var maximumOneWayJourneyDuration: TimeInterval?
    var terminalDwellDuration: TimeInterval
    var indicativeCostPerKilometre: Int64
    var operatingDayDuration: TimeInterval
    /// New gameplay edits are bounded so pairwise passenger markets stay responsive. Larger
    /// historical/future save patterns still restore without being truncated.
    var maximumServiceCallCount: Int
    /// Small test catalogues are simulated in full. At national scale, detailed population and
    /// happiness work is restricted to the constructed network so unbuilt reference stations do
    /// not add thousands of low-value calculations to every gameplay edit.
    var maximumGloballySimulatedCatalogueStationCount: Int

    init(
        maximumLineCount: Int,
        constructionDuration: TimeInterval,
        trainSpeedMetresPerSecond: CLLocationSpeed,
        maximumOneWayJourneyDuration: TimeInterval? = nil,
        terminalDwellDuration: TimeInterval,
        indicativeCostPerKilometre: Int64,
        operatingDayDuration: TimeInterval = 30,
        maximumServiceCallCount: Int = 16,
        maximumGloballySimulatedCatalogueStationCount: Int = 256
    ) {
        self.maximumLineCount = maximumLineCount
        self.constructionDuration = constructionDuration
        self.trainSpeedMetresPerSecond = trainSpeedMetresPerSecond
        self.maximumOneWayJourneyDuration = maximumOneWayJourneyDuration
        self.terminalDwellDuration = terminalDwellDuration
        self.indicativeCostPerKilometre = indicativeCostPerKilometre
        self.operatingDayDuration = operatingDayDuration
        self.maximumServiceCallCount = maximumServiceCallCount
        self.maximumGloballySimulatedCatalogueStationCount =
            maximumGloballySimulatedCatalogueStationCount
    }

    static let poc = GameConfiguration(
        maximumLineCount: 512,
        constructionDuration: 2.5,
        trainSpeedMetresPerSecond: 45,
        maximumOneWayJourneyDuration: 32,
        terminalDwellDuration: 2,
        indicativeCostPerKilometre: 1_500_000,
        operatingDayDuration: 30,
        maximumServiceCallCount: 256
    )
}

nonisolated struct StationUpgradeEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let stationCRS: String
    let stationName: String
    let level: StationLevel

    init(
        id: UUID = UUID(),
        stationCRS: String,
        stationName: String,
        level: StationLevel
    ) {
        self.id = id
        self.stationCRS = StationEvolution.normalizedCRS(stationCRS)
        self.stationName = stationName
        self.level = level
    }
}

nonisolated struct LinePreview: Identifiable, Sendable {
    let id: UUID
    let origin: Station
    let destination: Station
    /// Ordered passenger calling points selected for the proposed service, including endpoints.
    let stationCRSs: [String]
    let route: ServiceRailwayRoute
    let distanceMetres: CLLocationDistance
    let indicativeCost: Int64
    let passengerEstimate: PassengerDemandEstimate
    let railwayClass: RailwayClass
    /// The train length the player will purchase if this preview is confirmed.
    let formation: RollingStockFormation
    /// A demand-based starting point. The player's explicit selection remains independent from
    /// this recommendation once they change it.
    let recommendedFormation: RollingStockFormation

    init(
        id: UUID = UUID(),
        origin: Station,
        destination: Station,
        stationCRSs: [String]? = nil,
        route: ServiceRailwayRoute,
        distanceMetres: CLLocationDistance,
        indicativeCost: Int64,
        passengerEstimate: PassengerDemandEstimate = .zero,
        railwayClass: RailwayClass = .conventional,
        formation: RollingStockFormation = .legacyBaseline,
        recommendedFormation: RollingStockFormation = .legacyBaseline
    ) {
        self.id = id
        self.origin = origin
        self.destination = destination
        self.stationCRSs = stationCRSs ?? [origin.crs, destination.crs]
        self.route = route
        self.distanceMetres = distanceMetres
        self.indicativeCost = indicativeCost
        self.passengerEstimate = passengerEstimate
        self.railwayClass = railwayClass
        self.formation = formation
        self.recommendedFormation = recommendedFormation
    }

    var distanceKilometres: Double { distanceMetres / 1_000 }
}

nonisolated struct TrainState: Identifiable, Sendable {
    let id: UUID
    let lineID: UUID
    var coordinate: CLLocationCoordinate2D
    var bearing: CLLocationDirection
    var distanceAlongRoute: CLLocationDistance
    var direction: TrainTravelDirection
    var dwellRemaining: TimeInterval

    init(
        id: UUID = UUID(),
        lineID: UUID,
        coordinate: CLLocationCoordinate2D,
        bearing: CLLocationDirection,
        distanceAlongRoute: CLLocationDistance = 0,
        direction: TrainTravelDirection = .forward,
        dwellRemaining: TimeInterval = 0
    ) {
        self.id = id
        self.lineID = lineID
        self.coordinate = coordinate
        self.bearing = bearing
        self.distanceAlongRoute = distanceAlongRoute
        self.direction = direction
        self.dwellRemaining = dwellRemaining
    }
}

/// The independently reusable operating plan assigned to one timetable slot.
///
/// `stationCRSs` includes the train's chosen terminals. Persistence validates that it is a unique,
/// ordered subset of the service's built stations. Multiple trains can reuse an identical value
/// without coupling the plan to replaceable train identities.
nonisolated struct TrainServicePlan: Equatable, Sendable {
    let slotIndex: Int
    var role: TrainServiceRole
    var stationCRSs: [String]

    init(
        slotIndex: Int,
        role: TrainServiceRole,
        stationCRSs: [String]
    ) {
        self.slotIndex = slotIndex
        self.role = role
        self.stationCRSs = stationCRSs
    }

    /// Reconstructs the established global presets for all timetable slots. Local trains retain
    /// every existing service call; express trains retain only the existing outer terminals.
    static func legacyDefaults(
        servicePattern: ServicePattern,
        serviceStationCRSs: [String],
        slotCount: Int = 4
    ) -> [Self] {
        let terminalStationCRSs: [String]
        if let first = serviceStationCRSs.first, let last = serviceStationCRSs.last {
            terminalStationCRSs = first == last ? [first] : [first, last]
        } else {
            terminalStationCRSs = []
        }
        return (0..<max(slotCount, 0)).map { slotIndex in
            let role: TrainServiceRole = switch servicePattern {
            case .local: .local
            case .express: .express
            case .balanced: slotIndex.isMultiple(of: 2) ? .local : .express
            }
            return Self(
                slotIndex: slotIndex,
                role: role,
                stationCRSs: role == .local ? serviceStationCRSs : terminalStationCRSs
            )
        }
    }
}

/// Physical railway infrastructure that can be retained while train services are reorganised.
///
/// The current game still owns these values through `BuiltLine`. This standalone value provides
/// the boundary needed for a later `GameSession.corridors` collection without changing route
/// rendering or construction behaviour during the schema migration.
nonisolated struct RailwayCorridor: Identifiable, Sendable {
    let id: UUID
    let stationCRSs: [String]
    let route: ServiceRailwayRoute
    let distanceMetres: CLLocationDistance
    let indicativeCost: Int64
    var railwayClass: RailwayClass
    var trackCapacity: TrackCapacity
    var constructionProgress: Double

    var distanceKilometres: Double { distanceMetres / 1_000 }
    var isConstructed: Bool { constructionProgress >= 1 }

    var visibleCoordinates: [CLLocationCoordinate2D] {
        if isConstructed {
            return route.coordinates
        }
        return route.coordinates(
            upToDistance: route.totalLength * min(max(constructionProgress, 0), 1)
        )
    }
}

nonisolated struct BuiltLine: Identifiable, Sendable {
    /// Stable identity for the train service exposed by this compatibility model.
    ///
    /// `BuiltLine` still presents the pre-network-foundation API to the rest of the game, while
    /// `corridorIDs` lets later milestones run one service across retained infrastructure.
    let id: UUID
    let corridorIDs: [UUID]
    let name: String
    let origin: Station
    let destination: Station
    /// Ordered stations called at by the service, including both endpoints.
    ///
    /// Existing two-terminal lines receive `[origin.crs, destination.crs]`. Keeping this durable
    /// sequence beside the corridor identity provides the migration bridge for real intermediate
    /// stations without forcing the current UI and simulations to change in the same release.
    let stationCRSs: [String]
    let route: ServiceRailwayRoute
    let distanceMetres: CLLocationDistance
    let indicativeCost: Int64
    /// Ordered stations and geometry belonging to the retained physical corridor.
    ///
    /// These intentionally remain separate from `stationCRSs` and `route`, which describe the
    /// service's calling pattern. They are equal for lines built by the current endpoint builder,
    /// but can differ after restoring a schema-11 express service that skips an intermediate
    /// station on its corridor.
    let corridorStationCRSs: [String]
    let corridorRoute: ServiceRailwayRoute
    let corridorDistanceMetres: CLLocationDistance
    let corridorIndicativeCost: Int64
    let styleIndex: Int
    var railwayClass: RailwayClass = .conventional
    /// The purchased formation shared by every owned trainset on this service.
    var formation: RollingStockFormation = .legacyBaseline
    var servicePattern: ServicePattern = .balanced
    var trackCapacity: TrackCapacity = .singleTrack
    /// Four durable timetable slots survive frequency reductions and subsequent increases even
    /// when inactive train identities are recreated.
    var trainServicePlans: [TrainServicePlan]
    var serviceFrequency: ServiceFrequency
    /// Rolling stock already purchased for this line. Reducing frequency keeps surplus units
    /// available on the line, so raising it again cannot create a buy/sell exploit.
    var ownedTrainCount: Int
    var constructionProgress: Double
    var trains: [TrainState]

    init(
        id: UUID,
        name: String,
        origin: Station,
        destination: Station,
        route: ServiceRailwayRoute,
        distanceMetres: CLLocationDistance,
        indicativeCost: Int64,
        styleIndex: Int,
        railwayClass: RailwayClass = .conventional,
        formation: RollingStockFormation = .legacyBaseline,
        servicePattern: ServicePattern = .balanced,
        trackCapacity: TrackCapacity = .singleTrack,
        serviceFrequency: ServiceFrequency,
        ownedTrainCount: Int,
        constructionProgress: Double,
        trains: [TrainState],
        corridorIDs: [UUID]? = nil,
        stationCRSs: [String]? = nil,
        trainServicePlans: [TrainServicePlan]? = nil,
        corridorStationCRSs: [String]? = nil,
        corridorRoute: ServiceRailwayRoute? = nil,
        corridorDistanceMetres: CLLocationDistance? = nil,
        corridorIndicativeCost: Int64? = nil
    ) {
        self.id = id
        self.corridorIDs = corridorIDs ?? [id]
        self.name = name
        self.origin = origin
        self.destination = destination
        let resolvedStationCRSs = stationCRSs ?? [origin.crs, destination.crs]
        self.stationCRSs = resolvedStationCRSs
        self.route = route
        self.distanceMetres = distanceMetres
        self.indicativeCost = indicativeCost
        self.corridorStationCRSs = corridorStationCRSs ?? stationCRSs
            ?? [origin.crs, destination.crs]
        self.corridorRoute = corridorRoute ?? route
        self.corridorDistanceMetres = corridorDistanceMetres ?? distanceMetres
        self.corridorIndicativeCost = corridorIndicativeCost ?? indicativeCost
        self.styleIndex = styleIndex
        self.railwayClass = railwayClass
        self.formation = formation
        self.servicePattern = servicePattern
        self.trackCapacity = trackCapacity
        self.trainServicePlans = trainServicePlans ?? TrainServicePlan.legacyDefaults(
            servicePattern: servicePattern,
            serviceStationCRSs: resolvedStationCRSs
        )
        self.serviceFrequency = serviceFrequency
        self.ownedTrainCount = ownedTrainCount
        self.constructionProgress = constructionProgress
        self.trains = trains
    }

    /// Explicit service terminology for code migrating away from the overloaded `line.id` name.
    var serviceID: UUID { id }

    /// Source-compatible convenience for the historical one-service, one-corridor model.
    var corridorID: UUID { corridorIDs.first ?? id }

    func servicePlan(forSlot index: Int) -> TrainServicePlan? {
        trainServicePlans.first { $0.slotIndex == index }
    }

    /// One-corridor physical projection used while `GameSession` still stores `BuiltLine` values.
    /// Multi-corridor services will resolve their entries from the session's corridor collection.
    var corridor: RailwayCorridor {
        RailwayCorridor(
            id: corridorID,
            stationCRSs: corridorStationCRSs,
            route: corridorRoute,
            distanceMetres: corridorDistanceMetres,
            indicativeCost: corridorIndicativeCost,
            railwayClass: railwayClass,
            trackCapacity: trackCapacity,
            constructionProgress: constructionProgress
        )
    }

    var distanceKilometres: Double { distanceMetres / 1_000 }
    var isConstructed: Bool { constructionProgress >= 1 }

    var visibleCoordinates: [CLLocationCoordinate2D] {
        if isConstructed {
            return route.coordinates
        }
        return route.coordinates(
            upToDistance: route.totalLength * min(max(constructionProgress, 0), 1)
        )
    }
}
