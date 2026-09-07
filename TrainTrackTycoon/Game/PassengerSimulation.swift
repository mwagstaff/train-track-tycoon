import Foundation

/// A deliberately small service choice for the living-network proof of concept.
///
/// The number of visible trains mirrors the planned departures per hour for now. A later
/// operations milestone can decouple rolling-stock diagrams from the passenger-facing service.
nonisolated enum ServiceFrequency: String, CaseIterable, Codable, Equatable, Sendable, Identifiable {
    case hourly
    case halfHourly
    case quarterHourly

    var id: Self { self }

    var departuresPerHour: Int {
        switch self {
        case .hourly: 1
        case .halfHourly: 2
        case .quarterHourly: 4
        }
    }

    var visibleTrainCount: Int { departuresPerHour }

    var headwayMinutes: Double { 60 / Double(departuresPerHour) }

    var name: String {
        switch self {
        case .hourly: "Hourly"
        case .halfHourly: "Half-hourly"
        case .quarterHourly: "Every 15 minutes"
        }
    }

    var compactLabel: String { "\(departuresPerHour)/hr" }
}

/// One advertised station call on a service, measured along its routed geometry.
///
/// Distances are cumulative from the service origin. `PassengerLineInput` validates the complete
/// sequence and falls back to its two endpoints when a caller supplies incomplete route data.
nonisolated struct PassengerStationCallInput: Equatable, Sendable {
    let stationCRS: String
    let distanceKilometresFromOrigin: Double

    init(stationCRS: String, distanceKilometresFromOrigin: Double) {
        self.stationCRS = stationCRS
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        self.distanceKilometresFromOrigin = distanceKilometresFromOrigin
    }
}

/// One independently scheduled train path over a service's retained infrastructure.
///
/// A slot represents one departure per hour. Its first and last calls may be inside the parent
/// service's physical envelope, allowing different trains on the same infrastructure to use
/// different terminals. Station-capacity delivery can reduce that departure through
/// `effectiveDeparturesPerHour` without changing the advertised calling pattern.
nonisolated struct PassengerServiceRunInput: Equatable, Sendable {
    let slotIndex: Int
    let stationCalls: [PassengerStationCallInput]
    let scheduledDeparturesPerHour: Double
    let effectiveDeparturesPerHour: Double?

    init(
        slotIndex: Int,
        stationCalls: [PassengerStationCallInput],
        scheduledDeparturesPerHour: Double = 1,
        effectiveDeparturesPerHour: Double? = nil
    ) {
        self.slotIndex = slotIndex
        self.stationCalls = stationCalls
        self.scheduledDeparturesPerHour = scheduledDeparturesPerHour.isFinite
            && scheduledDeparturesPerHour > 0
            ? scheduledDeparturesPerHour
            : 0
        self.effectiveDeparturesPerHour = effectiveDeparturesPerHour
    }

    var passengerDeparturesPerHour: Double {
        let scheduled = scheduledDeparturesPerHour.isFinite
            ? max(scheduledDeparturesPerHour, 0)
            : 0
        guard let effectiveDeparturesPerHour,
              effectiveDeparturesPerHour.isFinite else { return scheduled }
        return min(max(effectiveDeparturesPerHour, 0), scheduled)
    }
}

nonisolated struct PassengerLineInput: Identifiable, Equatable, Sendable {
    let id: UUID
    let originCRS: String
    let destinationCRS: String
    let distanceKilometres: Double
    /// Ordered physical station calls selected for the service, including both endpoints.
    /// Local trains call at every entry; express trains use only the two endpoints.
    let stationCalls: [PassengerStationCallInput]
    let frequency: ServiceFrequency
    let servicePattern: ServicePattern
    /// Multiplies the unconstrained in-vehicle journey time before the configured minimum is
    /// applied. Operations can therefore expose a deterministic delay without coupling passenger
    /// demand to animation ticks.
    let journeyTimeMultiplier: Double
    /// The current scheduled-service reliability, used only when passengers must trust both legs
    /// of a connecting journey. Direct demand remains backward-compatible.
    let reliability: Double
    /// Seats available on each scheduled train. The six-car default preserves every pre-rolling-
    /// stock passenger result while allowing purchased formations to constrain real demand.
    let capacityPerTrain: Int
    /// Optional one-way seat throughput reserved for this market. Ordinary service inputs leave
    /// this nil and derive throughput from formation and frequency. Multi-stop evaluation uses it
    /// to partition one train's seats across overlapping origin/destination markets, preventing
    /// the same seat from being sold independently on every market that traverses a segment.
    let reservedHourlySeatCapacityPerDirection: Double?
    /// Delivered passenger-facing frequency after derived endpoint capacity is applied. Nil keeps
    /// the selected timetable exactly, preserving callers that do not model station capacity.
    let effectiveDeparturesPerHour: Double?
    /// Delivered local departures at intermediate calls. Nil derives the same throughput ratio
    /// as the endpoint timetable. It is separate because Balanced services only call with their
    /// local trains and Express services do not call at all.
    let effectiveIntermediateDeparturesPerHour: Double?
    /// Exact active train paths. Nil retains the established Local/Balanced/Express projection;
    /// an empty array intentionally represents no active custom departures.
    let serviceRuns: [PassengerServiceRunInput]?
    let isOperating: Bool

    init(
        id: UUID,
        originCRS: String,
        destinationCRS: String,
        distanceKilometres: Double,
        stationCalls: [PassengerStationCallInput]? = nil,
        frequency: ServiceFrequency = .halfHourly,
        servicePattern: ServicePattern = .balanced,
        journeyTimeMultiplier: Double = 1,
        reliability: Double = 1,
        capacityPerTrain: Int = RollingStockFormation.legacyBaseline.seatsPerTrain,
        reservedHourlySeatCapacityPerDirection: Double? = nil,
        effectiveDeparturesPerHour: Double? = nil,
        effectiveIntermediateDeparturesPerHour: Double? = nil,
        serviceRuns: [PassengerServiceRunInput]? = nil,
        isOperating: Bool = true
    ) {
        self.id = id
        self.originCRS = Self.normalizedCRS(originCRS)
        self.destinationCRS = Self.normalizedCRS(destinationCRS)
        self.distanceKilometres = distanceKilometres
        let validatedStationCalls = Self.validatedStationCalls(
            stationCalls,
            originCRS: self.originCRS,
            destinationCRS: self.destinationCRS,
            distanceKilometres: distanceKilometres
        )
        self.stationCalls = validatedStationCalls
        self.frequency = frequency
        self.servicePattern = servicePattern
        self.journeyTimeMultiplier = journeyTimeMultiplier
        self.reliability = reliability
        self.capacityPerTrain = capacityPerTrain
        self.reservedHourlySeatCapacityPerDirection =
            reservedHourlySeatCapacityPerDirection
        self.effectiveDeparturesPerHour = effectiveDeparturesPerHour
        self.effectiveIntermediateDeparturesPerHour = effectiveIntermediateDeparturesPerHour
        self.serviceRuns = serviceRuns.map {
            Self.validatedServiceRuns(
                $0,
                parentStationCalls: validatedStationCalls,
                distanceKilometres: distanceKilometres
            )
        }
        self.isOperating = isOperating
    }

    /// Convenience boundary for route providers that already expose parallel station and
    /// cumulative-distance arrays.
    init(
        id: UUID,
        originCRS: String,
        destinationCRS: String,
        distanceKilometres: Double,
        stationCRSs: [String],
        cumulativeStationDistancesKilometres: [Double],
        frequency: ServiceFrequency = .halfHourly,
        servicePattern: ServicePattern = .balanced,
        journeyTimeMultiplier: Double = 1,
        reliability: Double = 1,
        capacityPerTrain: Int = RollingStockFormation.legacyBaseline.seatsPerTrain,
        reservedHourlySeatCapacityPerDirection: Double? = nil,
        effectiveDeparturesPerHour: Double? = nil,
        effectiveIntermediateDeparturesPerHour: Double? = nil,
        serviceRuns: [PassengerServiceRunInput]? = nil,
        isOperating: Bool = true
    ) {
        let calls = zip(stationCRSs, cumulativeStationDistancesKilometres).map {
            PassengerStationCallInput(
                stationCRS: $0.0,
                distanceKilometresFromOrigin: $0.1
            )
        }
        self.init(
            id: id,
            originCRS: originCRS,
            destinationCRS: destinationCRS,
            distanceKilometres: distanceKilometres,
            stationCalls: calls,
            frequency: frequency,
            servicePattern: servicePattern,
            journeyTimeMultiplier: journeyTimeMultiplier,
            reliability: reliability,
            capacityPerTrain: capacityPerTrain,
            reservedHourlySeatCapacityPerDirection:
                reservedHourlySeatCapacityPerDirection,
            effectiveDeparturesPerHour: effectiveDeparturesPerHour,
            effectiveIntermediateDeparturesPerHour: effectiveIntermediateDeparturesPerHour,
            serviceRuns: serviceRuns,
            isOperating: isOperating
        )
    }

    var stationCRSs: [String] { stationCalls.map(\.stationCRS) }

    var scheduledDeparturesPerHour: Double {
        if let customScheduledDeparturesPerHour { return customScheduledDeparturesPerHour }
        return Double(max(frequency.departuresPerHour, 0))
    }

    var passengerDeparturesPerHour: Double {
        if let customPassengerDeparturesPerHour { return customPassengerDeparturesPerHour }
        guard let effectiveDeparturesPerHour else { return scheduledDeparturesPerHour }
        guard effectiveDeparturesPerHour.isFinite else { return scheduledDeparturesPerHour }
        return min(max(effectiveDeparturesPerHour, 0), scheduledDeparturesPerHour)
    }

    var scheduledIntermediateDeparturesPerHour: Double {
        if let serviceRuns {
            let intermediateCRSs = Set(stationCalls.dropFirst().dropLast().map(\.stationCRS))
            return serviceRuns.reduce(0) { total, run in
                total + (run.stationCalls.contains(where: {
                    intermediateCRSs.contains($0.stationCRS)
                }) ? max(run.scheduledDeparturesPerHour, 0) : 0)
            }
        }
        guard stationCalls.count > 2 else { return scheduledDeparturesPerHour }
        switch servicePattern {
        case .local:
            return scheduledDeparturesPerHour
        case .express:
            return 0
        case .balanced:
            let trainCount = max(frequency.visibleTrainCount, 0)
            let localCount = (trainCount + 1) / 2
            return min(Double(localCount), scheduledDeparturesPerHour)
        }
    }

    var passengerIntermediateDeparturesPerHour: Double {
        if let serviceRuns {
            let intermediateCRSs = Set(stationCalls.dropFirst().dropLast().map(\.stationCRS))
            return serviceRuns.reduce(0) { total, run in
                guard run.stationCalls.contains(where: {
                    intermediateCRSs.contains($0.stationCRS)
                }) else { return total }
                let next = total + run.passengerDeparturesPerHour
                return next.isFinite ? next : Double.greatestFiniteMagnitude
            }
        }
        let scheduled = scheduledIntermediateDeparturesPerHour
        guard scheduled > 0 else { return 0 }
        if let effectiveIntermediateDeparturesPerHour,
           effectiveIntermediateDeparturesPerHour.isFinite {
            return min(max(effectiveIntermediateDeparturesPerHour, 0), scheduled)
        }
        guard scheduledDeparturesPerHour > 0 else { return 0 }
        let throughputRatio = passengerDeparturesPerHour / scheduledDeparturesPerHour
        return min(max(scheduled * throughputRatio, 0), scheduled)
    }

    var isStationCapacityConstrained: Bool {
        guard isOperating else { return false }
        if let serviceRuns {
            return serviceRuns.contains {
                $0.passengerDeparturesPerHour + 0.000_000_001
                    < max($0.scheduledDeparturesPerHour, 0)
            }
        }
        let epsilon = 0.000_000_001
        return passengerDeparturesPerHour + epsilon < scheduledDeparturesPerHour
            || passengerIntermediateDeparturesPerHour + epsilon
                < scheduledIntermediateDeparturesPerHour
    }

    var oneWayHourlySeatCapacity: Double {
        if let reservedHourlySeatCapacityPerDirection,
           reservedHourlySeatCapacityPerDirection.isFinite {
            return max(reservedHourlySeatCapacityPerDirection, 0)
        }
        let capacity = Double(max(capacityPerTrain, 0))
        guard capacity > 0, passengerDeparturesPerHour > 0,
              capacity <= Double.greatestFiniteMagnitude / passengerDeparturesPerHour else {
            return capacity > 0 && passengerDeparturesPerHour > 0
                ? Double.greatestFiniteMagnitude
                : 0
        }
        return capacity * passengerDeparturesPerHour
    }

    var hasRealIntermediateCalls: Bool {
        if let serviceRuns {
            let intermediateCRSs = Set(stationCalls.dropFirst().dropLast().map(\.stationCRS))
            return serviceRuns.contains { run in
                run.stationCalls.contains { intermediateCRSs.contains($0.stationCRS) }
            }
        }
        return stationCalls.count > 2 && scheduledIntermediateDeparturesPerHour > 0
    }

    var customScheduledDeparturesPerHour: Double? {
        serviceRuns.map { runs in
            runs.reduce(0) { total, run in
                let next = total + max(run.scheduledDeparturesPerHour, 0)
                return next.isFinite ? next : Double.greatestFiniteMagnitude
            }
        }
    }

    var customPassengerDeparturesPerHour: Double? {
        serviceRuns.map { runs in
            runs.reduce(0) { total, run in
                let next = total + run.passengerDeparturesPerHour
                return next.isFinite ? next : Double.greatestFiniteMagnitude
            }
        }
    }

    private static func normalizedCRS(_ crs: String) -> String {
        crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func validatedStationCalls(
        _ rawCalls: [PassengerStationCallInput]?,
        originCRS: String,
        destinationCRS: String,
        distanceKilometres: Double
    ) -> [PassengerStationCallInput] {
        let fallback = [
            PassengerStationCallInput(
                stationCRS: originCRS,
                distanceKilometresFromOrigin: 0
            ),
            PassengerStationCallInput(
                stationCRS: destinationCRS,
                distanceKilometresFromOrigin: distanceKilometres
            ),
        ]
        guard let rawCalls,
              rawCalls.count >= 2,
              distanceKilometres.isFinite,
              distanceKilometres > 0 else { return fallback }

        let calls = rawCalls.map {
            PassengerStationCallInput(
                stationCRS: $0.stationCRS,
                distanceKilometresFromOrigin: $0.distanceKilometresFromOrigin
            )
        }
        guard calls.first?.stationCRS == originCRS,
              calls.last?.stationCRS == destinationCRS,
              Set(calls.map(\.stationCRS)).count == calls.count,
              !calls.contains(where: { $0.stationCRS.isEmpty }),
              abs((calls.first?.distanceKilometresFromOrigin ?? .infinity))
                <= 0.000_001,
              abs((calls.last?.distanceKilometresFromOrigin ?? 0) - distanceKilometres)
                <= max(distanceKilometres * 0.000_001, 0.000_001) else {
            return fallback
        }
        for index in calls.indices.dropFirst() {
            let previous = calls[calls.index(before: index)].distanceKilometresFromOrigin
            let current = calls[index].distanceKilometresFromOrigin
            guard current.isFinite, current > previous else { return fallback }
        }
        return calls
    }

    private static func validatedServiceRuns(
        _ rawRuns: [PassengerServiceRunInput],
        parentStationCalls: [PassengerStationCallInput],
        distanceKilometres: Double
    ) -> [PassengerServiceRunInput] {
        guard distanceKilometres.isFinite, distanceKilometres > 0 else { return [] }
        let distanceTolerance = max(distanceKilometres * 0.000_001, 0.000_001)
        let parentMatchesByCRS = Dictionary(uniqueKeysWithValues:
            parentStationCalls.enumerated().map { index, call in
                (call.stationCRS, (index: index, call: call))
            }
        )
        var runsBySlot = [Int: PassengerServiceRunInput]()
        for rawRun in rawRuns where rawRun.slotIndex >= 0 {
            var calls = rawRun.stationCalls.map {
                PassengerStationCallInput(
                    stationCRS: $0.stationCRS,
                    distanceKilometresFromOrigin: $0.distanceKilometresFromOrigin
                )
            }
            guard calls.count >= 2,
                  Set(calls.map(\.stationCRS)).count == calls.count,
                  !calls.contains(where: { $0.stationCRS.isEmpty }),
                  calls.allSatisfy({ call in
                      call.distanceKilometresFromOrigin.isFinite
                          && call.distanceKilometresFromOrigin >= 0
                          && call.distanceKilometresFromOrigin <= distanceKilometres
                              + distanceTolerance
                  })
            else { continue }
            var isIncreasing = true
            var isDecreasing = true
            for index in calls.indices.dropFirst() {
                let previous = calls[calls.index(before: index)].distanceKilometresFromOrigin
                let current = calls[index].distanceKilometresFromOrigin
                guard current.isFinite else {
                    isIncreasing = false
                    isDecreasing = false
                    break
                }
                if current <= previous { isIncreasing = false }
                if current >= previous { isDecreasing = false }
            }
            guard isIncreasing || isDecreasing else { continue }
            if isDecreasing { calls.reverse() }

            // A run may stop at any ordered subset of retained stations, but it cannot invent
            // infrastructure or move a station along the parent route. Canonicalizing back to
            // the parent calls also prevents tiny accepted distance tolerances accumulating in
            // the downstream market projection.
            let parentMatches = calls.compactMap { call -> (
                index: Int,
                call: PassengerStationCallInput
            )? in
                guard let match = parentMatchesByCRS[call.stationCRS],
                      abs(
                          match.call.distanceKilometresFromOrigin
                              - call.distanceKilometresFromOrigin
                      ) <= distanceTolerance else { return nil }
                return match
            }
            guard parentMatches.count == calls.count,
                  zip(parentMatches, parentMatches.dropFirst()).allSatisfy({
                      $0.index < $1.index
                  }) else { continue }
            calls = parentMatches.map(\.call)

            let candidate = PassengerServiceRunInput(
                slotIndex: rawRun.slotIndex,
                stationCalls: calls,
                scheduledDeparturesPerHour: rawRun.scheduledDeparturesPerHour,
                effectiveDeparturesPerHour: rawRun.effectiveDeparturesPerHour
            )
            if let existing = runsBySlot[rawRun.slotIndex],
               !serviceRunPrecedes(candidate, existing) {
                continue
            }
            runsBySlot[rawRun.slotIndex] = candidate
        }
        return runsBySlot.values.sorted { $0.slotIndex < $1.slotIndex }
    }

    private static func serviceRunPrecedes(
        _ lhs: PassengerServiceRunInput,
        _ rhs: PassengerServiceRunInput
    ) -> Bool {
        let lhsCRSs = lhs.stationCalls.map(\.stationCRS)
        let rhsCRSs = rhs.stationCalls.map(\.stationCRS)
        if lhsCRSs != rhsCRSs { return lhsCRSs.lexicographicallyPrecedes(rhsCRSs) }
        let lhsDistances = lhs.stationCalls.map(\.distanceKilometresFromOrigin)
        let rhsDistances = rhs.stationCalls.map(\.distanceKilometresFromOrigin)
        if lhsDistances != rhsDistances {
            return lhsDistances.lexicographicallyPrecedes(rhsDistances)
        }
        if lhs.scheduledDeparturesPerHour != rhs.scheduledDeparturesPerHour {
            return lhs.scheduledDeparturesPerHour < rhs.scheduledDeparturesPerHour
        }
        return lhs.passengerDeparturesPerHour < rhs.passengerDeparturesPerHour
    }
}

nonisolated enum PassengerServiceFeedback: String, Codable, Equatable, Sendable {
    case notOperating
    case noDemand
    case stationCapacityConstrained
    case capacityConstrained
    case infrequent
    case busy
    case plentyOfCapacity
    case goodService

    var title: String {
        switch self {
        case .notOperating: "Not yet operating"
        case .noDemand: "No demand estimate"
        case .stationCapacityConstrained: "Station capacity needed"
        case .capacityConstrained: "More service needed"
        case .infrequent: "Long wait between trains"
        case .busy: "Nearly full"
        case .plentyOfCapacity: "Light service"
        case .goodService: "Comfortable"
        }
    }

    var message: String {
        switch self {
        case .notOperating:
            "Passenger service begins when construction finishes."
        case .noDemand:
            "A valid pair of different stations is needed to estimate demand."
        case .stationCapacityConstrained:
            "Platforms cannot handle the full timetable yet. Station growth will unlock more service."
        case .capacityConstrained:
            "Peak trains are full. Increase frequency or lengthen trains to carry more passengers."
        case .infrequent:
            "More frequent departures would shorten waits and attract more passengers."
        case .busy:
            "Peak trains are nearly full, but demand is still being served."
        case .plentyOfCapacity:
            "The service has room to attract more passengers."
        case .goodService:
            "Waiting time and available capacity are well balanced."
        }
    }
}

nonisolated enum StationActivityLevel: Int, CaseIterable, Codable, Comparable, Equatable, Sendable {
    case quiet
    case active
    case busy
    case hub

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .quiet: "Quiet"
        case .active: "Active"
        case .busy: "Busy"
        case .hub: "Very busy"
        }
    }
}

/// An estimate for one direct origin-to-destination market, before it is associated with a line.
nonisolated struct PassengerDemandEstimate: Equatable, Sendable {
    let potentialDailyJourneys: Int
    let attractedDailyJourneys: Int
    let passengersPerDay: Int
    let dailyCapacity: Int
    let journeyMinutes: Double
    let averageWaitMinutes: Double
    /// The proportion of attracted demand that can board, in the range zero through one.
    let demandServedRatio: Double
    /// The proportion of all latent demand carried, in the range zero through one.
    let demandCapturedRatio: Double
    /// Peak seats occupied, capped at one because a train cannot carry more than its capacity.
    let peakOccupancyRatio: Double
    /// Requested peak load divided by peak capacity. Values above one identify unmet demand.
    let capacityPressure: Double
    let feedback: PassengerServiceFeedback

    var servedDailyJourneys: Int { passengersPerDay }
    var unservedDailyJourneys: Int {
        max(potentialDailyJourneys - passengersPerDay, 0)
    }

    static let zero = PassengerDemandEstimate(
        potentialDailyJourneys: 0,
        attractedDailyJourneys: 0,
        passengersPerDay: 0,
        dailyCapacity: 0,
        journeyMinutes: 0,
        averageWaitMinutes: 0,
        demandServedRatio: 0,
        demandCapturedRatio: 0,
        peakOccupancyRatio: 0,
        capacityPressure: 0,
        feedback: .noDemand
    )
}

nonisolated struct PassengerLineSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let originCRS: String
    let destinationCRS: String
    /// Ordered selected station calls. Whether every train calls is determined by the pattern.
    let stationCRSs: [String]
    let frequency: ServiceFrequency
    let servicePattern: ServicePattern
    /// Delivered frequency after endpoint platform constraints, never above the timetable.
    let effectiveDeparturesPerHour: Double
    let potentialDailyJourneys: Int
    let attractedDailyJourneys: Int
    /// Boardings whose whole journey is made on this direct service.
    let directPassengersPerDay: Int
    /// Transfer passengers using this service as one leg of a connecting journey.
    let connectingPassengersPerDay: Int
    /// Total boardings on this service. A transfer passenger is included on both legs.
    let passengersPerDay: Int
    /// Distance actually travelled by all direct and connecting riders on this service.
    /// Unlike `passengersPerDay * lineLength`, this preserves shorter intermediate journeys.
    let passengerKilometresPerDay: Double
    let dailyCapacity: Int
    let journeyMinutes: Double
    let averageWaitMinutes: Double
    let demandServedRatio: Double
    let demandCapturedRatio: Double
    let peakOccupancyRatio: Double
    let capacityPressure: Double
    let feedback: PassengerServiceFeedback

    var servedDailyJourneys: Int { passengersPerDay }
    var unservedDailyJourneys: Int {
        max(potentialDailyJourneys - passengersPerDay, 0)
    }

    init(
        input: PassengerLineInput,
        estimate: PassengerDemandEstimate,
        directPassengersPerDay: Int? = nil,
        connectingPassengersPerDay: Int = 0,
        passengerKilometresPerDay: Double? = nil
    ) {
        id = input.id
        originCRS = input.originCRS
        destinationCRS = input.destinationCRS
        stationCRSs = input.stationCRSs
        frequency = input.frequency
        servicePattern = input.servicePattern
        effectiveDeparturesPerHour = input.isOperating ? input.passengerDeparturesPerHour : 0
        potentialDailyJourneys = estimate.potentialDailyJourneys
        attractedDailyJourneys = estimate.attractedDailyJourneys
        self.directPassengersPerDay = max(
            directPassengersPerDay ?? estimate.passengersPerDay,
            0
        )
        self.connectingPassengersPerDay = max(connectingPassengersPerDay, 0)
        passengersPerDay = estimate.passengersPerDay
        self.passengerKilometresPerDay = passengerKilometresPerDay
            ?? max(Double(estimate.passengersPerDay) * max(input.distanceKilometres, 0), 0)
        dailyCapacity = estimate.dailyCapacity
        journeyMinutes = estimate.journeyMinutes
        averageWaitMinutes = estimate.averageWaitMinutes
        demandServedRatio = estimate.demandServedRatio
        demandCapturedRatio = estimate.demandCapturedRatio
        peakOccupancyRatio = estimate.peakOccupancyRatio
        capacityPressure = estimate.capacityPressure
        feedback = estimate.feedback
    }
}

/// One no-change origin/destination market offered by a service.
///
/// A multi-stop service contributes one entry for every pair of stations that the same train can
/// serve. Keeping these edges separate from the aggregate line snapshot lets accessibility treat
/// an end-to-end journey as direct rather than inventing transfers at intermediate calls.
nonisolated struct PassengerServiceMarketSnapshot: Identifiable, Equatable, Sendable {
    let serviceID: UUID
    let originCRS: String
    let destinationCRS: String
    let journeyMinutes: Double
    let departuresPerHour: Double
    let averageWaitMinutes: Double
    let peakOccupancyRatio: Double
    let directPassengersPerDay: Int
    let isOperating: Bool

    var id: String {
        "\(serviceID.uuidString)|\(originCRS)|\(destinationCRS)"
    }
}

nonisolated struct StationPassengerSnapshot: Identifiable, Equatable, Sendable {
    let stationCRS: String
    let potentialDailyJourneys: Int
    let servedDailyJourneys: Int
    let unservedDailyJourneys: Int
    let connectedLineCount: Int
    let connectedDestinationCount: Int
    let busiestDirectDestinationCRS: String?
    /// Unique journeys changing trains here. Station activity additionally counts the two
    /// boarding/alighting movements made by each transfer.
    let transferJourneysPerDay: Int
    let activityLevel: StationActivityLevel
    /// A normalized value suitable for a station marker halo.
    let activity: Double

    var id: String { stationCRS }
    var passengersPerDay: Int { servedDailyJourneys }

    init(
        stationCRS: String,
        potentialDailyJourneys: Int,
        servedDailyJourneys: Int,
        unservedDailyJourneys: Int,
        connectedLineCount: Int,
        connectedDestinationCount: Int,
        busiestDirectDestinationCRS: String?,
        transferJourneysPerDay: Int = 0,
        activityLevel: StationActivityLevel,
        activity: Double
    ) {
        self.stationCRS = stationCRS
        self.potentialDailyJourneys = potentialDailyJourneys
        self.servedDailyJourneys = servedDailyJourneys
        self.unservedDailyJourneys = unservedDailyJourneys
        self.connectedLineCount = connectedLineCount
        self.connectedDestinationCount = connectedDestinationCount
        self.busiestDirectDestinationCRS = busiestDirectDestinationCRS
        self.transferJourneysPerDay = transferJourneysPerDay
        self.activityLevel = activityLevel
        self.activity = activity
    }
}

/// One canonical outer-station market served by a change of train.
///
/// `passengersPerDay` counts people once. The network and line headline totals count their two
/// boardings, preserving the game's existing definition of a ride.
nonisolated struct PassengerConnectingJourneySnapshot: Identifiable, Equatable, Sendable {
    let originCRS: String
    let destinationCRS: String
    let interchangeCRS: String
    let potentialDailyJourneys: Int
    let attractedDailyJourneys: Int
    let passengersPerDay: Int
    let inVehicleJourneyMinutes: Double
    let averageWaitMinutes: Double
    let interchangePenaltyMinutes: Double
    /// The product of both sanitized leg reliabilities, in the range zero through one.
    let combinedReliability: Double
    let demandServedRatio: Double
    let demandCapturedRatio: Double

    var id: String { "\(originCRS)-\(interchangeCRS)-\(destinationCRS)" }
    var servedDailyJourneys: Int { passengersPerDay }
    var unservedDailyJourneys: Int {
        max(potentialDailyJourneys - passengersPerDay, 0)
    }
    var generalizedJourneyMinutes: Double {
        let first = inVehicleJourneyMinutes.addingProduct(1, averageWaitMinutes)
        guard first.isFinite,
              first <= Double.greatestFiniteMagnitude - interchangePenaltyMinutes else {
            return Double.greatestFiniteMagnitude
        }
        return first + interchangePenaltyMinutes
    }
}

nonisolated struct NetworkPassengerSnapshot: Equatable, Sendable {
    let potentialDailyJourneys: Int
    let passengersPerDay: Int
    let unservedDailyJourneys: Int
    /// The mean occupied share of peak seats, weighted by each service's capacity.
    let averagePeakOccupancyRatio: Double
    let linesByID: [UUID: PassengerLineSnapshot]
    let stationsByCRS: [String: StationPassengerSnapshot]
    /// Unique people completing a connecting journey, rather than their two boardings.
    let connectingJourneysPerDay: Int
    let connectingJourneySnapshots: [PassengerConnectingJourneySnapshot]
    /// Direct passenger-facing edges, including adjacent and through markets on multi-stop lines.
    let serviceMarketSnapshots: [PassengerServiceMarketSnapshot]

    static let empty = NetworkPassengerSnapshot(
        potentialDailyJourneys: 0,
        passengersPerDay: 0,
        unservedDailyJourneys: 0,
        averagePeakOccupancyRatio: 0,
        linesByID: [:],
        stationsByCRS: [:],
        connectingJourneysPerDay: 0,
        connectingJourneySnapshots: [],
        serviceMarketSnapshots: []
    )

    var servedDailyJourneys: Int { passengersPerDay }

    var lineSnapshots: [PassengerLineSnapshot] {
        linesByID.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    var stationSnapshots: [StationPassengerSnapshot] {
        stationsByCRS.values.sorted { $0.stationCRS < $1.stationCRS }
    }

    init(
        potentialDailyJourneys: Int,
        passengersPerDay: Int,
        unservedDailyJourneys: Int,
        averagePeakOccupancyRatio: Double,
        linesByID: [UUID: PassengerLineSnapshot],
        stationsByCRS: [String: StationPassengerSnapshot],
        connectingJourneysPerDay: Int = 0,
        connectingJourneySnapshots: [PassengerConnectingJourneySnapshot] = [],
        serviceMarketSnapshots: [PassengerServiceMarketSnapshot] = []
    ) {
        self.potentialDailyJourneys = potentialDailyJourneys
        self.passengersPerDay = passengersPerDay
        self.unservedDailyJourneys = unservedDailyJourneys
        self.averagePeakOccupancyRatio = averagePeakOccupancyRatio
        self.linesByID = linesByID
        self.stationsByCRS = stationsByCRS
        self.connectingJourneysPerDay = connectingJourneysPerDay
        self.connectingJourneySnapshots = connectingJourneySnapshots
        self.serviceMarketSnapshots = serviceMarketSnapshots.sorted { lhs, rhs in
            if lhs.serviceID != rhs.serviceID {
                return lhs.serviceID.uuidString < rhs.serviceID.uuidString
            }
            if lhs.originCRS != rhs.originCRS { return lhs.originCRS < rhs.originCRS }
            return lhs.destinationCRS < rhs.destinationCRS
        }
    }

    func line(for id: UUID) -> PassengerLineSnapshot? { linesByID[id] }

    func station(forCRS crs: String) -> StationPassengerSnapshot? {
        stationsByCRS[crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()]
    }
}

nonisolated struct PassengerSimulationConfiguration: Equatable, Sendable {
    let stationDemandWeights: [String: Double]
    let fallbackStationDemandWeight: Double
    let baseDailyJourneys: Double
    let minimumDistanceFactor: Double
    let distanceDecayKilometres: Double
    let averageRailSpeedKilometresPerHour: Double
    let minimumJourneyMinutes: Double
    let serviceAttractionBaseline: Double
    let servicePenaltyWindowMinutes: Double
    let minimumAttractionRatio: Double
    let trainCapacity: Int
    let operatingHoursPerDay: Double
    let peakHoursPerDay: Double
    let peakDemandShare: Double
    let infrequentWaitThresholdMinutes: Double
    let constrainedCapacityPressure: Double
    let busyCapacityPressure: Double
    let quietCapacityPressure: Double
    let activeStationThreshold: Int
    let busyStationThreshold: Int
    let hubStationThreshold: Int

    init(
        stationDemandWeights: [String: Double],
        fallbackStationDemandWeight: Double,
        baseDailyJourneys: Double,
        minimumDistanceFactor: Double,
        distanceDecayKilometres: Double,
        averageRailSpeedKilometresPerHour: Double,
        minimumJourneyMinutes: Double,
        serviceAttractionBaseline: Double,
        servicePenaltyWindowMinutes: Double,
        minimumAttractionRatio: Double,
        trainCapacity: Int,
        operatingHoursPerDay: Double,
        peakHoursPerDay: Double,
        peakDemandShare: Double,
        infrequentWaitThresholdMinutes: Double,
        constrainedCapacityPressure: Double,
        busyCapacityPressure: Double,
        quietCapacityPressure: Double,
        activeStationThreshold: Int,
        busyStationThreshold: Int,
        hubStationThreshold: Int
    ) {
        var normalizedWeights = [String: Double]()
        for (key, value) in stationDemandWeights.sorted(by: { $0.key < $1.key }) {
            normalizedWeights[
                key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            ] = value
        }
        self.stationDemandWeights = normalizedWeights
        self.fallbackStationDemandWeight = fallbackStationDemandWeight
        self.baseDailyJourneys = baseDailyJourneys
        self.minimumDistanceFactor = minimumDistanceFactor
        self.distanceDecayKilometres = distanceDecayKilometres
        self.averageRailSpeedKilometresPerHour = averageRailSpeedKilometresPerHour
        self.minimumJourneyMinutes = minimumJourneyMinutes
        self.serviceAttractionBaseline = serviceAttractionBaseline
        self.servicePenaltyWindowMinutes = servicePenaltyWindowMinutes
        self.minimumAttractionRatio = minimumAttractionRatio
        self.trainCapacity = trainCapacity
        self.operatingHoursPerDay = operatingHoursPerDay
        self.peakHoursPerDay = peakHoursPerDay
        self.peakDemandShare = peakDemandShare
        self.infrequentWaitThresholdMinutes = infrequentWaitThresholdMinutes
        self.constrainedCapacityPressure = constrainedCapacityPressure
        self.busyCapacityPressure = busyCapacityPressure
        self.quietCapacityPressure = quietCapacityPressure
        self.activeStationThreshold = activeStationThreshold
        self.busyStationThreshold = busyStationThreshold
        self.hubStationThreshold = hubStationThreshold
    }

    /// Synthetic tuning values for the POC only. They are intentionally not presented as real
    /// passenger counts, population data, or station usage statistics.
    static let poc = PassengerSimulationConfiguration(
        stationDemandWeights: [
            "VIC": 1.60,
            "LBG": 1.60,
            "GTW": 1.45,
            "BFR": 1.40,
            "CLJ": 1.40,
            "BTN": 1.35,
            "ECR": 1.15,
            "TBD": 1.00,
            "HHE": 0.95,
            "HOR": 0.80,
            "PUR": 0.80,
            "SRS": 0.65,
        ],
        fallbackStationDemandWeight: 1.0,
        baseDailyJourneys: 8_500,
        minimumDistanceFactor: 0.35,
        distanceDecayKilometres: 80,
        averageRailSpeedKilometresPerHour: 100,
        minimumJourneyMinutes: 8,
        serviceAttractionBaseline: 1.05,
        servicePenaltyWindowMinutes: 180,
        minimumAttractionRatio: 0.40,
        trainCapacity: 240,
        operatingHoursPerDay: 18,
        peakHoursPerDay: 4,
        peakDemandShare: 0.45,
        infrequentWaitThresholdMinutes: 20,
        constrainedCapacityPressure: 1.00,
        busyCapacityPressure: 0.80,
        quietCapacityPressure: 0.35,
        activeStationThreshold: 750,
        busyStationThreshold: 2_000,
        hubStationThreshold: 4_500
    )
}

/// A deterministic, steady-state direct and one-change service model.
///
/// Passenger results depend only on the supplied network and configuration. They deliberately do
/// not consume animation ticks, wall-clock time, or random numbers, so UI pacing cannot change the
/// outcome. Direct duplicate services share one origin-destination market instead of multiplying it.
nonisolated struct PassengerSimulation: Sendable {
    static let connectingInterchangePenaltyMinutes = 12.0
    /// A national hub can expose hundreds of thousands of theoretical one-change markets. Keep
    /// the detailed allocator bounded while preserving every market for ordinary networks.
    static let maximumConnectingJourneyCandidatesPerInterchange = 2_048
    private static let connectingJourneyCandidateSearchMultiplier = 8

    let configuration: PassengerSimulationConfiguration

    init(configuration: PassengerSimulationConfiguration = .poc) {
        self.configuration = configuration
    }

    func estimate(
        originCRS: String,
        destinationCRS: String,
        distanceKilometres: Double,
        frequency: ServiceFrequency = .halfHourly,
        journeyTimeMultiplier: Double = 1,
        capacityPerTrain: Int = RollingStockFormation.legacyBaseline.seatsPerTrain,
        stationPopulationMultipliers: [String: Double] = [:]
    ) -> PassengerDemandEstimate {
        let populationMultipliers = normalizedStationPopulationMultipliers(
            stationPopulationMultipliers
        )
        return estimateMarket(
            originCRS: normalizedCRS(originCRS),
            destinationCRS: normalizedCRS(destinationCRS),
            distanceKilometres: distanceKilometres,
            departuresPerHour: Double(frequency.departuresPerHour),
            journeyTimeMultiplier: journeyTimeMultiplier,
            capacityPerTrain: capacityPerTrain,
            stationPopulationMultipliers: populationMultipliers
        )
    }

    func estimate(
        for input: PassengerLineInput,
        stationPopulationMultipliers: [String: Double] = [:]
    ) -> PassengerLineSnapshot {
        let populationMultipliers = normalizedStationPopulationMultipliers(
            stationPopulationMultipliers
        )
        guard input.isOperating else {
            let latentDemand = estimateMarket(
                originCRS: input.originCRS,
                destinationCRS: input.destinationCRS,
                distanceKilometres: input.distanceKilometres,
                departuresPerHour: input.scheduledDeparturesPerHour,
                journeyTimeMultiplier: input.journeyTimeMultiplier,
                capacityPerTrain: input.capacityPerTrain,
                stationPopulationMultipliers: populationMultipliers
            )
            let estimate = PassengerDemandEstimate(
                potentialDailyJourneys: latentDemand.potentialDailyJourneys,
                attractedDailyJourneys: 0,
                passengersPerDay: 0,
                dailyCapacity: 0,
                journeyMinutes: latentDemand.journeyMinutes,
                averageWaitMinutes: 0,
                demandServedRatio: 0,
                demandCapturedRatio: 0,
                peakOccupancyRatio: 0,
                capacityPressure: 0,
                feedback: .notOperating
            )
            return PassengerLineSnapshot(input: input, estimate: estimate)
        }

        let market = estimateMarket(
                originCRS: input.originCRS,
                destinationCRS: input.destinationCRS,
                distanceKilometres: input.distanceKilometres,
                departuresPerHour: input.passengerDeparturesPerHour,
                journeyTimeMultiplier: input.journeyTimeMultiplier,
                capacityPerTrain: input.capacityPerTrain,
                hourlySeatCapacityPerDirection: input.oneWayHourlySeatCapacity,
                stationPopulationMultipliers: populationMultipliers
            )
        return PassengerLineSnapshot(
            input: input,
            estimate: applyingStationCapacityFeedback(market, for: input)
        )
    }

    func evaluate(
        _ lines: [PassengerLineInput],
        stationPopulationMultipliers: [String: Double] = [:]
    ) -> NetworkPassengerSnapshot {
        guard !lines.isEmpty else { return .empty }
        if lines.contains(where: { $0.serviceRuns != nil }) {
            return evaluateServiceRunNetwork(
                lines,
                stationPopulationMultipliers: stationPopulationMultipliers
            )
        }
        if lines.contains(where: { $0.stationCalls.count > 2 }) {
            return evaluateMultiStopNetwork(
                lines,
                stationPopulationMultipliers: stationPopulationMultipliers
            )
        }
        let populationMultipliers = normalizedStationPopulationMultipliers(
            stationPopulationMultipliers
        )

        let sortedLines = lines.sorted { lhs, rhs in
            if lhs.id != rhs.id { return lhs.id.uuidString < rhs.id.uuidString }
            if lhs.originCRS != rhs.originCRS { return lhs.originCRS < rhs.originCRS }
            if lhs.destinationCRS != rhs.destinationCRS {
                return lhs.destinationCRS < rhs.destinationCRS
            }
            if lhs.distanceKilometres != rhs.distanceKilometres {
                return lhs.distanceKilometres < rhs.distanceKilometres
            }
            if lhs.frequency != rhs.frequency {
                return lhs.frequency.rawValue < rhs.frequency.rawValue
            }
            let lhsMultiplier = normalizedJourneyTimeMultiplier(lhs.journeyTimeMultiplier)
            let rhsMultiplier = normalizedJourneyTimeMultiplier(rhs.journeyTimeMultiplier)
            if lhsMultiplier != rhsMultiplier { return lhsMultiplier < rhsMultiplier }
            let lhsReliability = normalizedReliability(lhs.reliability)
            let rhsReliability = normalizedReliability(rhs.reliability)
            if lhsReliability != rhsReliability { return lhsReliability < rhsReliability }
            if lhs.capacityPerTrain != rhs.capacityPerTrain {
                return lhs.capacityPerTrain < rhs.capacityPerTrain
            }
            if lhs.oneWayHourlySeatCapacity != rhs.oneWayHourlySeatCapacity {
                return lhs.oneWayHourlySeatCapacity < rhs.oneWayHourlySeatCapacity
            }
            let lhsEffective = lhs.passengerDeparturesPerHour
            let rhsEffective = rhs.passengerDeparturesPerHour
            if lhsEffective != rhsEffective { return lhsEffective < rhsEffective }
            if lhs.isOperating != rhs.isOperating { return !lhs.isOperating }
            return false
        }

        var linesByID = [UUID: PassengerLineSnapshot](minimumCapacity: sortedLines.count)
        var groups = [StationPairKey: [PassengerLineInput]]()

        for line in sortedLines {
            guard line.isOperating else {
                linesByID[line.id] = estimate(
                    for: line,
                    stationPopulationMultipliers: populationMultipliers
                )
                continue
            }
            guard let pair = StationPairKey(line: line) else {
                linesByID[line.id] = estimate(
                    for: line,
                    stationPopulationMultipliers: populationMultipliers
                )
                continue
            }
            groups[pair, default: []].append(line)
        }

        var stationPotentialTotals = [String: Int]()
        var stationServedTotals = [String: Int]()
        var stationLineIDs = [String: Set<UUID>]()
        var stationDestinationTotals = [String: [String: Int]]()
        var stationTransferTotals = [String: Int]()
        var networkPotential = 0
        var networkPassengers = 0
        var totalCapacityWeight = 0
        var weightedPeakOccupancy = 0.0
        var directGroups = [DirectPassengerGroupSnapshot]()

        for pair in groups.keys.sorted() {
            guard let group = groups[pair] else { continue }
            let departures = group.reduce(0.0) {
                addingFiniteNonnegative($0, $1.passengerDeparturesPerHour)
            }
            let distance = group
                .map(\.distanceKilometres)
                .filter { $0.isFinite && $0 > 0 }
                .min() ?? 0
            let market = estimateMarket(
                originCRS: pair.firstCRS,
                destinationCRS: pair.secondCRS,
                distanceKilometres: distance,
                departuresPerHour: departures,
                journeyTimeMultiplier: departuresWeightedJourneyTimeMultiplier(for: group),
                hourlySeatCapacityPerDirection: hourlySeatCapacityPerDirection(for: group),
                stationPopulationMultipliers: populationMultipliers
            )
            directGroups.append(DirectPassengerGroupSnapshot(
                pair: pair,
                lines: group,
                market: market,
                distanceKilometres: distance
            ))
            let capacityWeights = serviceCapacityWeights(for: group)
            let potentialAllocation = allocate(
                market.potentialDailyJourneys,
                using: capacityWeights
            )
            let attractedAllocation = allocate(
                market.attractedDailyJourneys,
                using: capacityWeights
            )
            let capacityAllocation = Dictionary(uniqueKeysWithValues: group.map { line in
                (line.id, dailyCapacity(for: line))
            })
            let passengerAllocation = allocateBounded(
                market.passengersPerDay,
                using: capacityWeights,
                capacitiesByID: capacityAllocation
            )

            for line in group {
                let potential = potentialAllocation[line.id, default: 0]
                let attracted = attractedAllocation[line.id, default: 0]
                let passengers = passengerAllocation[line.id, default: 0]
                let capacity = capacityAllocation[line.id, default: 0]
                let allocatedEstimate = PassengerDemandEstimate(
                    potentialDailyJourneys: potential,
                    attractedDailyJourneys: attracted,
                    passengersPerDay: passengers,
                    dailyCapacity: capacity,
                    journeyMinutes: market.journeyMinutes,
                    averageWaitMinutes: market.averageWaitMinutes,
                    demandServedRatio: ratio(passengers, over: attracted),
                    demandCapturedRatio: ratio(passengers, over: potential),
                    peakOccupancyRatio: market.peakOccupancyRatio,
                    capacityPressure: market.capacityPressure,
                    feedback: line.isStationCapacityConstrained
                        ? .stationCapacityConstrained
                        : market.feedback
                )
                linesByID[line.id] = PassengerLineSnapshot(
                    input: line,
                    estimate: allocatedEstimate
                )
            }

            networkPotential = addingWithoutOverflow(
                networkPotential,
                market.potentialDailyJourneys
            )
            networkPassengers = addingWithoutOverflow(
                networkPassengers,
                market.passengersPerDay
            )
            totalCapacityWeight = addingWithoutOverflow(
                totalCapacityWeight,
                market.dailyCapacity
            )
            weightedPeakOccupancy += market.peakOccupancyRatio
                * Double(market.dailyCapacity)

            stationPotentialTotals[pair.firstCRS, default: 0] = addingWithoutOverflow(
                stationPotentialTotals[pair.firstCRS, default: 0],
                market.potentialDailyJourneys
            )
            stationPotentialTotals[pair.secondCRS, default: 0] = addingWithoutOverflow(
                stationPotentialTotals[pair.secondCRS, default: 0],
                market.potentialDailyJourneys
            )
            stationServedTotals[pair.firstCRS, default: 0] = addingWithoutOverflow(
                stationServedTotals[pair.firstCRS, default: 0],
                market.passengersPerDay
            )
            stationServedTotals[pair.secondCRS, default: 0] = addingWithoutOverflow(
                stationServedTotals[pair.secondCRS, default: 0],
                market.passengersPerDay
            )
            let firstDirectionTotal = addingWithoutOverflow(
                stationDestinationTotals[pair.firstCRS]?[pair.secondCRS] ?? 0,
                market.passengersPerDay
            )
            stationDestinationTotals[pair.firstCRS, default: [:]][pair.secondCRS]
                = firstDirectionTotal
            let secondDirectionTotal = addingWithoutOverflow(
                stationDestinationTotals[pair.secondCRS]?[pair.firstCRS] ?? 0,
                market.passengersPerDay
            )
            stationDestinationTotals[pair.secondCRS, default: [:]][pair.firstCRS]
                = secondDirectionTotal
            for line in group {
                stationLineIDs[pair.firstCRS, default: []].insert(line.id)
                stationLineIDs[pair.secondCRS, default: []].insert(line.id)
            }
        }

        let connection = connectingJourneys(
            between: directGroups,
            directLinesByID: linesByID,
            stationPopulationMultipliers: populationMultipliers
        )
        for (id, snapshot) in connection.linesByID {
            linesByID[id] = snapshot
        }

        let connectingJourneySnapshots = connection.snapshots
        let connectingJourneysPerDay = connectingJourneySnapshots.reduce(0) {
            addingWithoutOverflow($0, $1.passengersPerDay)
        }
        for snapshot in connectingJourneySnapshots {
            let potentialBoardings = multiplyingWithoutOverflow(
                snapshot.potentialDailyJourneys,
                by: 2
            )
            let servedBoardings = multiplyingWithoutOverflow(
                snapshot.passengersPerDay,
                by: 2
            )
            networkPotential = addingWithoutOverflow(networkPotential, potentialBoardings)
            networkPassengers = addingWithoutOverflow(networkPassengers, servedBoardings)

            for outerCRS in [snapshot.originCRS, snapshot.destinationCRS] {
                stationPotentialTotals[outerCRS, default: 0] = addingWithoutOverflow(
                    stationPotentialTotals[outerCRS, default: 0],
                    snapshot.potentialDailyJourneys
                )
                stationServedTotals[outerCRS, default: 0] = addingWithoutOverflow(
                    stationServedTotals[outerCRS, default: 0],
                    snapshot.passengersPerDay
                )
            }

            let interchangeCRS = snapshot.interchangeCRS
            stationPotentialTotals[interchangeCRS, default: 0] = addingWithoutOverflow(
                stationPotentialTotals[interchangeCRS, default: 0],
                potentialBoardings
            )
            stationServedTotals[interchangeCRS, default: 0] = addingWithoutOverflow(
                stationServedTotals[interchangeCRS, default: 0],
                servedBoardings
            )
            stationTransferTotals[interchangeCRS, default: 0] = addingWithoutOverflow(
                stationTransferTotals[interchangeCRS, default: 0],
                snapshot.passengersPerDay
            )
        }

        if !connectingJourneySnapshots.isEmpty {
            // Direct-only evaluation retains its original accumulation path exactly. Once a
            // connecting market is present, recalculate from the combined line snapshots.
            totalCapacityWeight = 0
            weightedPeakOccupancy = 0
            for lineID in linesByID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
                guard let line = linesByID[lineID] else { continue }
                totalCapacityWeight = addingWithoutOverflow(
                    totalCapacityWeight,
                    line.dailyCapacity
                )
                weightedPeakOccupancy += line.peakOccupancyRatio
                    * Double(line.dailyCapacity)
            }
        }

        var stationsByCRS = [String: StationPassengerSnapshot]()
        for crs in stationPotentialTotals.keys.sorted() {
            let potential = stationPotentialTotals[crs, default: 0]
            let served = stationServedTotals[crs, default: 0]
            let destinations = stationDestinationTotals[crs] ?? [:]
            let busiestDestination = destinations.filter { $0.value > 0 }.sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }.first?.key
            stationsByCRS[crs] = StationPassengerSnapshot(
                stationCRS: crs,
                potentialDailyJourneys: potential,
                servedDailyJourneys: served,
                unservedDailyJourneys: max(potential - served, 0),
                connectedLineCount: stationLineIDs[crs]?.count ?? 0,
                connectedDestinationCount: destinations.count,
                busiestDirectDestinationCRS: busiestDestination,
                transferJourneysPerDay: stationTransferTotals[crs, default: 0],
                activityLevel: activityLevel(for: served),
                activity: activity(for: served)
            )
        }

        let averagePeakOccupancy: Double
        if totalCapacityWeight > 0 {
            averagePeakOccupancy = clamp(
                finite(
                    weightedPeakOccupancy / Double(totalCapacityWeight),
                    fallback: 0
                ),
                lower: 0,
                upper: 1
            )
        } else {
            averagePeakOccupancy = 0
        }

        let serviceMarketSnapshots = sortedLines.compactMap { line -> PassengerServiceMarketSnapshot? in
            guard let snapshot = linesByID[line.id] else { return nil }
            return PassengerServiceMarketSnapshot(
                serviceID: line.id,
                originCRS: line.originCRS,
                destinationCRS: line.destinationCRS,
                journeyMinutes: snapshot.journeyMinutes,
                departuresPerHour: snapshot.effectiveDeparturesPerHour,
                averageWaitMinutes: snapshot.averageWaitMinutes,
                peakOccupancyRatio: snapshot.peakOccupancyRatio,
                directPassengersPerDay: snapshot.directPassengersPerDay,
                isOperating: line.isOperating
            )
        }

        return NetworkPassengerSnapshot(
            potentialDailyJourneys: networkPotential,
            passengersPerDay: networkPassengers,
            unservedDailyJourneys: max(networkPotential - networkPassengers, 0),
            averagePeakOccupancyRatio: averagePeakOccupancy,
            linesByID: linesByID,
            stationsByCRS: stationsByCRS,
            connectingJourneysPerDay: connectingJourneysPerDay,
            connectingJourneySnapshots: connectingJourneySnapshots,
            serviceMarketSnapshots: serviceMarketSnapshots
        )
    }

    /// Projects explicit per-slot paths into the no-change markets offered by the exact trains
    /// that call at both stations. Duplicate markets from several slots are combined before the
    /// mature direct/connecting allocator runs, while seat reservations are made independently
    /// against every train path so overlapping OD markets cannot sell the same seat twice.
    private func evaluateServiceRunNetwork(
        _ lines: [PassengerLineInput],
        stationPopulationMultipliers: [String: Double]
    ) -> NetworkPassengerSnapshot {
        var legacyProjections = [PassengerMarketProjection]()
        var customProjections = [PassengerMarketProjection]()

        for line in lines.sorted(by: passengerLinePrecedes) {
            guard line.serviceRuns != nil else {
                let calls = line.stationCalls
                guard calls.count >= 2 else { continue }
                if !line.isOperating {
                    legacyProjections.append(marketProjection(
                        for: line,
                        startIndex: 0,
                        endIndex: calls.count - 1,
                        usesIntermediateTimetable: false
                    ))
                    continue
                }
                for startIndex in 0..<(calls.count - 1) {
                    for endIndex in (startIndex + 1)..<calls.count {
                        let isEndToEnd = startIndex == 0 && endIndex == calls.count - 1
                        guard isEndToEnd || line.scheduledIntermediateDeparturesPerHour > 0 else {
                            continue
                        }
                        legacyProjections.append(marketProjection(
                            for: line,
                            startIndex: startIndex,
                            endIndex: endIndex,
                            usesIntermediateTimetable: !isEndToEnd
                        ))
                    }
                }
                continue
            }
            // Construction-period forecasts historically expose only the parent service's outer
            // market. Explicit default slots must not multiply latent demand before trains run.
            if !line.isOperating {
                customProjections.append(marketProjection(
                    for: line,
                    startIndex: 0,
                    endIndex: line.stationCalls.count - 1,
                    usesIntermediateTimetable: false
                ))
                continue
            }
            customProjections.append(contentsOf: serviceRunMarketProjections(for: line))
        }

        let projections = (
            reservingSegmentCapacity(in: legacyProjections, sourceLines: lines)
                + customProjections
        ).sorted(by: marketProjectionPrecedes)
        return aggregateServiceRunNetwork(
            sourceLines: lines,
            projections: projections,
            stationPopulationMultipliers: stationPopulationMultipliers
        )
    }

    private func serviceRunMarketProjections(
        for line: PassengerLineInput
    ) -> [PassengerMarketProjection] {
        guard let runs = line.serviceRuns else { return [] }
        var contributionsByPair = [StationPairKey: [PassengerRunMarketContribution]]()

        for run in runs.sorted(by: { $0.slotIndex < $1.slotIndex }) {
            let calls = run.stationCalls
            guard calls.count >= 2 else { continue }
            var candidates = [PassengerRunMarketCandidate]()
            for startIndex in 0..<(calls.count - 1) {
                for endIndex in (startIndex + 1)..<calls.count {
                    guard let pair = StationPairKey(
                        firstCRS: calls[startIndex].stationCRS,
                        secondCRS: calls[endIndex].stationCRS
                    ) else { continue }
                    candidates.append(PassengerRunMarketCandidate(
                        id: PassengerRunMarketID(
                            slotIndex: run.slotIndex,
                            startIndex: startIndex,
                            endIndex: endIndex
                        ),
                        pair: pair,
                        startCall: calls[startIndex],
                        endCall: calls[endIndex]
                    ))
                }
            }
            let effectiveDepartures = line.isOperating
                ? run.passengerDeparturesPerHour
                : 0
            let reservations = fairRunSegmentCapacityReservations(
                candidates: candidates,
                segmentCount: calls.count - 1,
                hourlyCapacityPerSegment: boundedNonnegativeProduct(
                    Double(max(line.capacityPerTrain, 0)),
                    effectiveDepartures
                )
            )
            for candidate in candidates {
                contributionsByPair[candidate.pair, default: []].append(
                    PassengerRunMarketContribution(
                        slotIndex: run.slotIndex,
                        startCall: candidate.startCall,
                        endCall: candidate.endCall,
                        scheduledDeparturesPerHour: run.scheduledDeparturesPerHour,
                        effectiveDeparturesPerHour: effectiveDepartures,
                        reservedHourlySeats: reservations[candidate.id, default: 0]
                    )
                )
            }
        }

        return contributionsByPair.keys.sorted().compactMap { pair in
            guard let contributions = contributionsByPair[pair],
                  let representative = contributions.sorted(by: runContributionPrecedes).first
            else { return nil }
            let scheduledDepartures = contributions.reduce(0.0) {
                addingFiniteNonnegative($0, $1.scheduledDeparturesPerHour)
            }
            let effectiveDepartures = contributions.reduce(0.0) {
                addingFiniteNonnegative($0, $1.effectiveDeparturesPerHour)
            }
            let reservedSeats = contributions.reduce(0.0) {
                addingFiniteNonnegative($0, $1.reservedHourlySeats)
            }
            let distance = contributions.compactMap { contribution -> Double? in
                let value = contribution.endCall.distanceKilometresFromOrigin
                    - contribution.startCall.distanceKilometresFromOrigin
                return value.isFinite && value > 0 ? value : nil
            }.min() ?? 0
            let projectionID = derivedServiceRunMarketID(sourceID: line.id, pair: pair)
            return PassengerMarketProjection(
                sourceLineID: line.id,
                startIndex: 0,
                endIndex: 1,
                input: PassengerLineInput(
                    id: projectionID,
                    originCRS: representative.startCall.stationCRS,
                    destinationCRS: representative.endCall.stationCRS,
                    distanceKilometres: distance,
                    frequency: frequency(accommodating: scheduledDepartures),
                    servicePattern: line.servicePattern,
                    journeyTimeMultiplier: line.journeyTimeMultiplier,
                    reliability: line.reliability,
                    capacityPerTrain: line.capacityPerTrain,
                    reservedHourlySeatCapacityPerDirection: reservedSeats,
                    effectiveDeparturesPerHour: effectiveDepartures,
                    isOperating: line.isOperating
                )
            )
        }
    }

    private func fairRunSegmentCapacityReservations(
        candidates: [PassengerRunMarketCandidate],
        segmentCount: Int,
        hourlyCapacityPerSegment: Double
    ) -> [PassengerRunMarketID: Double] {
        guard segmentCount > 0,
              hourlyCapacityPerSegment.isFinite,
              hourlyCapacityPerSegment > 0,
              !candidates.isEmpty else {
            return Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, 0) })
        }
        var reservations = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, 0.0) })
        var activeIDs = Set(candidates.map(\.id))
        let epsilon = 0.000_000_001

        for _ in 0..<max(segmentCount + candidates.count, 1) where !activeIDs.isEmpty {
            var delta = Double.greatestFiniteMagnitude
            var deltaBySegment = [Int: Double]()
            for segment in 0..<segmentCount {
                let users = candidates.filter {
                    activeIDs.contains($0.id) && $0.uses(segment: segment)
                }
                guard !users.isEmpty else { continue }
                let used = candidates.reduce(0.0) { total, candidate in
                    guard candidate.uses(segment: segment) else { return total }
                    return addingFiniteNonnegative(total, reservations[candidate.id, default: 0])
                }
                let segmentDelta = max(hourlyCapacityPerSegment - used, 0)
                    / Double(users.count)
                deltaBySegment[segment] = segmentDelta
                delta = min(delta, segmentDelta)
            }
            guard delta.isFinite else { break }
            delta = max(delta, 0)
            for id in activeIDs.sorted() {
                reservations[id] = addingFiniteNonnegative(reservations[id, default: 0], delta)
            }
            let saturatedSegments = Set(deltaBySegment.compactMap { segment, value in
                value <= delta + epsilon ? segment : nil
            })
            let completed = Set(candidates.compactMap { candidate -> PassengerRunMarketID? in
                guard activeIDs.contains(candidate.id),
                      (candidate.id.startIndex..<candidate.id.endIndex).contains(where: {
                          saturatedSegments.contains($0)
                      }) else { return nil }
                return candidate.id
            })
            guard !completed.isEmpty else { break }
            activeIDs.subtract(completed)
        }
        return reservations
    }

    private func runContributionPrecedes(
        _ lhs: PassengerRunMarketContribution,
        _ rhs: PassengerRunMarketContribution
    ) -> Bool {
        if lhs.slotIndex != rhs.slotIndex { return lhs.slotIndex < rhs.slotIndex }
        if lhs.startCall.stationCRS != rhs.startCall.stationCRS {
            return lhs.startCall.stationCRS < rhs.startCall.stationCRS
        }
        return lhs.endCall.stationCRS < rhs.endCall.stationCRS
    }

    private func frequency(accommodating departures: Double) -> ServiceFrequency {
        switch departures {
        case 3...: .quarterHourly
        case 1.5...: .halfHourly
        default: .hourly
        }
    }

    private func derivedServiceRunMarketID(
        sourceID: UUID,
        pair: StationPairKey
    ) -> UUID {
        stableDerivedID(
            bytes: Array("\(sourceID.uuidString)|run|\(pair.firstCRS)|\(pair.secondCRS)".utf8),
            fallback: sourceID
        )
    }

    private func aggregateServiceRunNetwork(
        sourceLines lines: [PassengerLineInput],
        projections: [PassengerMarketProjection],
        stationPopulationMultipliers: [String: Double]
    ) -> NetworkPassengerSnapshot {
        let projectionByID = Dictionary(uniqueKeysWithValues: projections.map {
            ($0.input.id, $0)
        })
        let projectedSnapshot = evaluate(
            projections.map(\.input),
            stationPopulationMultipliers: stationPopulationMultipliers
        )

        var lineSnapshotsBySourceID = [UUID: [PassengerLineSnapshot]]()
        for projectedLine in projectedSnapshot.lineSnapshots {
            guard let projection = projectionByID[projectedLine.id] else { continue }
            lineSnapshotsBySourceID[projection.sourceLineID, default: []].append(projectedLine)
        }

        var aggregateLinesByID = [UUID: PassengerLineSnapshot]()
        for line in lines.sorted(by: passengerLinePrecedes) {
            let markets = lineSnapshotsBySourceID[line.id, default: []]
            guard !markets.isEmpty else {
                aggregateLinesByID[line.id] = estimate(
                    for: line,
                    stationPopulationMultipliers: stationPopulationMultipliers
                )
                continue
            }

            let potential = markets.reduce(0) {
                addingWithoutOverflow($0, $1.potentialDailyJourneys)
            }
            let attracted = markets.reduce(0) {
                addingWithoutOverflow($0, $1.attractedDailyJourneys)
            }
            let direct = markets.reduce(0) {
                addingWithoutOverflow($0, $1.directPassengersPerDay)
            }
            let connecting = markets.reduce(0) {
                addingWithoutOverflow($0, $1.connectingPassengersPerDay)
            }
            let passengers = markets.reduce(0) {
                addingWithoutOverflow($0, $1.passengersPerDay)
            }
            let passengerKilometres = markets.reduce(0.0) {
                addingFiniteNonnegative($0, $1.passengerKilometresPerDay)
            }
            let capacity = line.isOperating ? dailyCapacity(for: line) : 0
            let representativeProjection = projections
                .filter { projection in
                    guard projection.sourceLineID == line.id,
                          let pair = StationPairKey(line: projection.input),
                          let linePair = StationPairKey(line: line) else { return false }
                    return pair == linePair
                }
                .sorted(by: marketProjectionPrecedes)
                .first
                ?? projections
                    .filter { $0.sourceLineID == line.id }
                    .sorted(by: marketProjectionPrecedes)
                    .first
            let representative = representativeProjection.flatMap {
                projectedSnapshot.line(for: $0.input.id)
            } ?? markets.sorted { $0.id.uuidString < $1.id.uuidString }[0]
            let peakOccupancy = markets.map(\.peakOccupancyRatio).max() ?? 0
            let capacityPressure = markets.map(\.capacityPressure).max() ?? 0
            let aggregateFeedback = line.isStationCapacityConstrained
                ? PassengerServiceFeedback.stationCapacityConstrained
                : strongestFeedback(in: markets.map(\.feedback))
            let estimate = PassengerDemandEstimate(
                potentialDailyJourneys: potential,
                attractedDailyJourneys: attracted,
                passengersPerDay: passengers,
                dailyCapacity: capacity,
                journeyMinutes: representative.journeyMinutes,
                averageWaitMinutes: representative.averageWaitMinutes,
                demandServedRatio: ratio(passengers, over: attracted),
                demandCapturedRatio: ratio(passengers, over: potential),
                peakOccupancyRatio: peakOccupancy,
                capacityPressure: capacityPressure,
                feedback: aggregateFeedback
            )
            aggregateLinesByID[line.id] = PassengerLineSnapshot(
                input: line,
                estimate: estimate,
                directPassengersPerDay: direct,
                connectingPassengersPerDay: connecting,
                passengerKilometresPerDay: passengerKilometres
            )
        }

        var connectedLineIDsByCRS = [String: Set<UUID>]()
        for projection in projections where projection.input.isOperating
            && projection.input.passengerDeparturesPerHour > 0 {
            connectedLineIDsByCRS[projection.input.originCRS, default: []]
                .insert(projection.sourceLineID)
            connectedLineIDsByCRS[projection.input.destinationCRS, default: []]
                .insert(projection.sourceLineID)
        }
        let adjustedStations = projectedSnapshot.stationsByCRS.mapValues { station in
            StationPassengerSnapshot(
                stationCRS: station.stationCRS,
                potentialDailyJourneys: station.potentialDailyJourneys,
                servedDailyJourneys: station.servedDailyJourneys,
                unservedDailyJourneys: station.unservedDailyJourneys,
                connectedLineCount: connectedLineIDsByCRS[station.stationCRS]?.count ?? 0,
                connectedDestinationCount: station.connectedDestinationCount,
                busiestDirectDestinationCRS: station.busiestDirectDestinationCRS,
                transferJourneysPerDay: station.transferJourneysPerDay,
                activityLevel: station.activityLevel,
                activity: station.activity
            )
        }

        let serviceMarkets = projectedSnapshot.serviceMarketSnapshots.compactMap {
            market -> PassengerServiceMarketSnapshot? in
            guard let projection = projectionByID[market.serviceID] else { return nil }
            return PassengerServiceMarketSnapshot(
                serviceID: projection.sourceLineID,
                originCRS: market.originCRS,
                destinationCRS: market.destinationCRS,
                journeyMinutes: market.journeyMinutes,
                departuresPerHour: market.departuresPerHour,
                averageWaitMinutes: market.averageWaitMinutes,
                peakOccupancyRatio: market.peakOccupancyRatio,
                directPassengersPerDay: market.directPassengersPerDay,
                isOperating: market.isOperating
            )
        }

        var aggregateCapacityWeight = 0
        var aggregateWeightedPeakOccupancy = 0.0
        for line in aggregateLinesByID.values {
            aggregateCapacityWeight = addingWithoutOverflow(
                aggregateCapacityWeight,
                line.dailyCapacity
            )
            aggregateWeightedPeakOccupancy += line.peakOccupancyRatio
                * Double(line.dailyCapacity)
        }
        let aggregateAveragePeakOccupancy = aggregateCapacityWeight > 0
            ? clamp(
                finite(
                    aggregateWeightedPeakOccupancy / Double(aggregateCapacityWeight),
                    fallback: 0
                ),
                lower: 0,
                upper: 1
            )
            : 0

        return NetworkPassengerSnapshot(
            potentialDailyJourneys: projectedSnapshot.potentialDailyJourneys,
            passengersPerDay: projectedSnapshot.passengersPerDay,
            unservedDailyJourneys: projectedSnapshot.unservedDailyJourneys,
            averagePeakOccupancyRatio: aggregateAveragePeakOccupancy,
            linesByID: aggregateLinesByID,
            stationsByCRS: adjustedStations,
            connectingJourneysPerDay: projectedSnapshot.connectingJourneysPerDay,
            connectingJourneySnapshots: projectedSnapshot.connectingJourneySnapshots,
            serviceMarketSnapshots: serviceMarkets
        )
    }

    /// Projects a multi-stop service into every no-change market that its stopping pattern offers,
    /// then folds the mature endpoint/connection model back into one aggregate service snapshot.
    /// The endpoint-only path above remains byte-for-byte unchanged for the established game.
    private func evaluateMultiStopNetwork(
        _ lines: [PassengerLineInput],
        stationPopulationMultipliers: [String: Double]
    ) -> NetworkPassengerSnapshot {
        var projections = [PassengerMarketProjection]()
        for line in lines.sorted(by: passengerLinePrecedes) {
            let calls = line.stationCalls
            guard calls.count >= 2 else { continue }

            if !line.isOperating {
                projections.append(marketProjection(
                    for: line,
                    startIndex: 0,
                    endIndex: calls.count - 1,
                    usesIntermediateTimetable: false
                ))
                continue
            }

            for startIndex in 0..<(calls.count - 1) {
                for endIndex in (startIndex + 1)..<calls.count {
                    let isEndToEnd = startIndex == 0 && endIndex == calls.count - 1
                    guard isEndToEnd || line.scheduledIntermediateDeparturesPerHour > 0 else {
                        continue
                    }
                    projections.append(marketProjection(
                        for: line,
                        startIndex: startIndex,
                        endIndex: endIndex,
                        usesIntermediateTimetable: !isEndToEnd
                    ))
                }
            }
        }

        projections = reservingSegmentCapacity(
            in: projections,
            sourceLines: lines
        )
        let projectionByID = Dictionary(uniqueKeysWithValues: projections.map {
            ($0.input.id, $0)
        })
        let projectedSnapshot = evaluate(
            projections.map(\.input),
            stationPopulationMultipliers: stationPopulationMultipliers
        )

        var lineSnapshotsBySourceID = [UUID: [PassengerLineSnapshot]]()
        for projectedLine in projectedSnapshot.lineSnapshots {
            guard let projection = projectionByID[projectedLine.id] else { continue }
            lineSnapshotsBySourceID[projection.sourceLineID, default: []].append(projectedLine)
        }

        var aggregateLinesByID = [UUID: PassengerLineSnapshot]()
        for line in lines.sorted(by: passengerLinePrecedes) {
            let markets = lineSnapshotsBySourceID[line.id, default: []]
            guard !markets.isEmpty else {
                aggregateLinesByID[line.id] = estimate(
                    for: line,
                    stationPopulationMultipliers: stationPopulationMultipliers
                )
                continue
            }

            let potential = markets.reduce(0) {
                addingWithoutOverflow($0, $1.potentialDailyJourneys)
            }
            let attracted = markets.reduce(0) {
                addingWithoutOverflow($0, $1.attractedDailyJourneys)
            }
            let direct = markets.reduce(0) {
                addingWithoutOverflow($0, $1.directPassengersPerDay)
            }
            let connecting = markets.reduce(0) {
                addingWithoutOverflow($0, $1.connectingPassengersPerDay)
            }
            let passengers = markets.reduce(0) {
                addingWithoutOverflow($0, $1.passengersPerDay)
            }
            let passengerKilometres = markets.reduce(0.0) {
                addingFiniteNonnegative($0, $1.passengerKilometresPerDay)
            }
            // A line's headline capacity is the physical endpoint seat supply, not the sum of
            // each OD market's reserved bucket. Non-overlapping markets may reuse a seat after an
            // intermediate passenger alights, so summing those buckets would overstate trains.
            let capacity = line.isOperating ? dailyCapacity(for: line) : 0
            let fullMarketID = derivedMarketID(
                sourceID: line.id,
                startIndex: 0,
                endIndex: line.stationCalls.count - 1
            )
            let representative = projectedSnapshot.line(for: fullMarketID) ?? markets[0]
            let peakOccupancy = markets.map(\.peakOccupancyRatio).max() ?? 0
            let capacityPressure = markets.map(\.capacityPressure).max() ?? 0
            let aggregateFeedback = line.isStationCapacityConstrained
                ? PassengerServiceFeedback.stationCapacityConstrained
                : strongestFeedback(in: markets.map(\.feedback))
            let estimate = PassengerDemandEstimate(
                potentialDailyJourneys: potential,
                attractedDailyJourneys: attracted,
                passengersPerDay: passengers,
                dailyCapacity: capacity,
                journeyMinutes: representative.journeyMinutes,
                averageWaitMinutes: representative.averageWaitMinutes,
                demandServedRatio: ratio(passengers, over: attracted),
                demandCapturedRatio: ratio(passengers, over: potential),
                peakOccupancyRatio: peakOccupancy,
                capacityPressure: capacityPressure,
                feedback: aggregateFeedback
            )
            aggregateLinesByID[line.id] = PassengerLineSnapshot(
                input: line,
                estimate: estimate,
                directPassengersPerDay: direct,
                connectingPassengersPerDay: connecting,
                passengerKilometresPerDay: passengerKilometres
            )
        }

        var connectedLineIDsByCRS = [String: Set<UUID>]()
        for projection in projections where projection.input.isOperating
            && projection.input.passengerDeparturesPerHour > 0 {
            connectedLineIDsByCRS[projection.input.originCRS, default: []]
                .insert(projection.sourceLineID)
            connectedLineIDsByCRS[projection.input.destinationCRS, default: []]
                .insert(projection.sourceLineID)
        }
        let adjustedStations = projectedSnapshot.stationsByCRS.mapValues { station in
            StationPassengerSnapshot(
                stationCRS: station.stationCRS,
                potentialDailyJourneys: station.potentialDailyJourneys,
                servedDailyJourneys: station.servedDailyJourneys,
                unservedDailyJourneys: station.unservedDailyJourneys,
                connectedLineCount: connectedLineIDsByCRS[station.stationCRS]?.count ?? 0,
                connectedDestinationCount: station.connectedDestinationCount,
                busiestDirectDestinationCRS: station.busiestDirectDestinationCRS,
                transferJourneysPerDay: station.transferJourneysPerDay,
                activityLevel: station.activityLevel,
                activity: station.activity
            )
        }

        let serviceMarkets: [PassengerServiceMarketSnapshot] = projectedSnapshot
            .serviceMarketSnapshots.compactMap { market -> PassengerServiceMarketSnapshot? in
            guard let projection = projectionByID[market.serviceID] else {
                return nil
            }
            return PassengerServiceMarketSnapshot(
                serviceID: projection.sourceLineID,
                originCRS: market.originCRS,
                destinationCRS: market.destinationCRS,
                journeyMinutes: market.journeyMinutes,
                departuresPerHour: market.departuresPerHour,
                averageWaitMinutes: market.averageWaitMinutes,
                peakOccupancyRatio: market.peakOccupancyRatio,
                directPassengersPerDay: market.directPassengersPerDay,
                isOperating: market.isOperating
            )
        }

        var aggregateCapacityWeight = 0
        var aggregateWeightedPeakOccupancy = 0.0
        for line in aggregateLinesByID.values {
            aggregateCapacityWeight = addingWithoutOverflow(
                aggregateCapacityWeight,
                line.dailyCapacity
            )
            aggregateWeightedPeakOccupancy += line.peakOccupancyRatio
                * Double(line.dailyCapacity)
        }
        let aggregateAveragePeakOccupancy = aggregateCapacityWeight > 0
            ? clamp(
                finite(
                    aggregateWeightedPeakOccupancy / Double(aggregateCapacityWeight),
                    fallback: 0
                ),
                lower: 0,
                upper: 1
            )
            : 0

        return NetworkPassengerSnapshot(
            potentialDailyJourneys: projectedSnapshot.potentialDailyJourneys,
            passengersPerDay: projectedSnapshot.passengersPerDay,
            unservedDailyJourneys: projectedSnapshot.unservedDailyJourneys,
            averagePeakOccupancyRatio: aggregateAveragePeakOccupancy,
            linesByID: aggregateLinesByID,
            stationsByCRS: adjustedStations,
            connectingJourneysPerDay: projectedSnapshot.connectingJourneysPerDay,
            connectingJourneySnapshots: projectedSnapshot.connectingJourneySnapshots,
            serviceMarketSnapshots: serviceMarkets
        )
    }

    private func marketProjection(
        for line: PassengerLineInput,
        startIndex: Int,
        endIndex: Int,
        usesIntermediateTimetable: Bool
    ) -> PassengerMarketProjection {
        let start = line.stationCalls[startIndex]
        let end = line.stationCalls[endIndex]
        let distance = max(
            end.distanceKilometresFromOrigin - start.distanceKilometresFromOrigin,
            0
        )
        let frequency = usesIntermediateTimetable
            ? intermediateFrequency(for: line)
            : line.frequency
        let effectiveDepartures = usesIntermediateTimetable
            ? line.passengerIntermediateDeparturesPerHour
            : line.passengerDeparturesPerHour
        let projectionID = line.stationCalls.count == 2
            ? line.id
            : derivedMarketID(
                sourceID: line.id,
                startIndex: startIndex,
                endIndex: endIndex
            )
        return PassengerMarketProjection(
            sourceLineID: line.id,
            startIndex: startIndex,
            endIndex: endIndex,
            input: PassengerLineInput(
                id: projectionID,
                originCRS: start.stationCRS,
                destinationCRS: end.stationCRS,
                distanceKilometres: distance,
                frequency: frequency,
                servicePattern: line.servicePattern,
                journeyTimeMultiplier: line.journeyTimeMultiplier,
                reliability: line.reliability,
                capacityPerTrain: line.capacityPerTrain,
                effectiveDeparturesPerHour: effectiveDepartures,
                isOperating: line.isOperating
            )
        )
    }

    /// Reserves one-way seat throughput for every OD market against the physical segments that it
    /// traverses. Without this partition, A-B and A-C could each sell the train's complete seat
    /// supply even though both groups occupy the same seats between A and B.
    ///
    /// Express capacity is exclusive to the endpoint market. Local capacity is max-min shared by
    /// every market that uses each segment. The reservation is intentionally independent of input
    /// ordering and also bounds any later connecting passengers assigned to a projected market.
    private func reservingSegmentCapacity(
        in rawProjections: [PassengerMarketProjection],
        sourceLines: [PassengerLineInput]
    ) -> [PassengerMarketProjection] {
        let linesByID = Dictionary(
            sourceLines.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let projectionsBySourceID = Dictionary(
            grouping: rawProjections,
            by: \.sourceLineID
        )
        var result = [PassengerMarketProjection]()
        result.reserveCapacity(rawProjections.count)

        for sourceID in projectionsBySourceID.keys.sorted(by: {
            $0.uuidString < $1.uuidString
        }) {
            guard let sourceLine = linesByID[sourceID],
                  let sourceProjections = projectionsBySourceID[sourceID] else {
                continue
            }
            let sortedProjections = sourceProjections.sorted(by: marketProjectionPrecedes)
            guard sourceLine.isOperating, sourceLine.stationCalls.count > 2 else {
                result.append(contentsOf: sortedProjections)
                continue
            }

            let seatsPerTrain = Double(max(sourceLine.capacityPerTrain, 0))
            let localHourlySeats = boundedNonnegativeProduct(
                seatsPerTrain,
                min(
                    sourceLine.passengerIntermediateDeparturesPerHour,
                    sourceLine.passengerDeparturesPerHour
                )
            )
            let expressHourlySeats = boundedNonnegativeProduct(
                seatsPerTrain,
                max(
                    sourceLine.passengerDeparturesPerHour
                        - sourceLine.passengerIntermediateDeparturesPerHour,
                    0
                )
            )
            let localReservations = fairSegmentCapacityReservations(
                projections: sortedProjections,
                segmentCount: sourceLine.stationCalls.count - 1,
                hourlyCapacityPerSegment: localHourlySeats
            )
            let finalCallIndex = sourceLine.stationCalls.count - 1

            for projection in sortedProjections {
                var reservedSeats = localReservations[projection.input.id, default: 0]
                if projection.startIndex == 0, projection.endIndex == finalCallIndex {
                    reservedSeats = addingFiniteNonnegative(
                        reservedSeats,
                        expressHourlySeats
                    )
                }
                result.append(projection.reservingHourlySeats(reservedSeats))
            }
        }
        return result.sorted(by: marketProjectionPrecedes)
    }

    /// Continuous max-min filling over interval resources. Every pass saturates at least one
    /// corridor segment and freezes all still-active markets using it, so the result is bounded
    /// and deterministic for a fixed ordered calling pattern.
    private func fairSegmentCapacityReservations(
        projections: [PassengerMarketProjection],
        segmentCount: Int,
        hourlyCapacityPerSegment: Double
    ) -> [UUID: Double] {
        guard segmentCount > 0,
              hourlyCapacityPerSegment.isFinite,
              hourlyCapacityPerSegment > 0,
              !projections.isEmpty else {
            return Dictionary(uniqueKeysWithValues: projections.map { ($0.input.id, 0) })
        }

        var reservations = Dictionary(
            uniqueKeysWithValues: projections.map { ($0.input.id, 0.0) }
        )
        var activeIDs = Set(projections.map(\.input.id))
        let epsilon = 0.000_000_001

        for _ in 0..<max(segmentCount + projections.count, 1) where !activeIDs.isEmpty {
            var delta = Double.greatestFiniteMagnitude
            var deltaBySegment = [Int: Double]()

            for segment in 0..<segmentCount {
                let users = projections.filter {
                    activeIDs.contains($0.input.id) && $0.uses(segment: segment)
                }
                guard !users.isEmpty else { continue }
                let used = projections.reduce(0.0) { partial, projection in
                    guard projection.uses(segment: segment) else { return partial }
                    return addingFiniteNonnegative(
                        partial,
                        reservations[projection.input.id, default: 0]
                    )
                }
                let remaining = max(hourlyCapacityPerSegment - used, 0)
                let segmentDelta = remaining / Double(users.count)
                deltaBySegment[segment] = segmentDelta
                delta = min(delta, segmentDelta)
            }

            guard delta.isFinite else { break }
            delta = max(delta, 0)
            for id in activeIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
                reservations[id] = addingFiniteNonnegative(
                    reservations[id, default: 0],
                    delta
                )
            }

            let saturatedSegments = Set(deltaBySegment.compactMap { segment, value in
                value <= delta + epsilon ? segment : nil
            })
            let completedIDs: Set<UUID> = Set(projections.compactMap {
                projection -> UUID? in
                guard activeIDs.contains(projection.input.id),
                      (projection.startIndex..<projection.endIndex).contains(where: {
                          saturatedSegments.contains($0)
                      }) else {
                    return nil
                }
                return projection.input.id
            })
            guard !completedIDs.isEmpty else { break }
            activeIDs.subtract(completedIDs)
        }
        return reservations
    }

    private func marketProjectionPrecedes(
        _ lhs: PassengerMarketProjection,
        _ rhs: PassengerMarketProjection
    ) -> Bool {
        if lhs.sourceLineID != rhs.sourceLineID {
            return lhs.sourceLineID.uuidString < rhs.sourceLineID.uuidString
        }
        if lhs.startIndex != rhs.startIndex { return lhs.startIndex < rhs.startIndex }
        if lhs.endIndex != rhs.endIndex { return lhs.endIndex < rhs.endIndex }
        return lhs.input.id.uuidString < rhs.input.id.uuidString
    }

    private func intermediateFrequency(for line: PassengerLineInput) -> ServiceFrequency {
        switch Int(line.scheduledIntermediateDeparturesPerHour.rounded()) {
        case 4...: .quarterHourly
        case 2...: .halfHourly
        default: .hourly
        }
    }

    private func passengerLinePrecedes(
        _ lhs: PassengerLineInput,
        _ rhs: PassengerLineInput
    ) -> Bool {
        if lhs.id != rhs.id { return lhs.id.uuidString < rhs.id.uuidString }
        if lhs.originCRS != rhs.originCRS { return lhs.originCRS < rhs.originCRS }
        return lhs.destinationCRS < rhs.destinationCRS
    }

    private func strongestFeedback(
        in feedback: [PassengerServiceFeedback]
    ) -> PassengerServiceFeedback {
        let priority: [PassengerServiceFeedback] = [
            .notOperating,
            .stationCapacityConstrained,
            .capacityConstrained,
            .infrequent,
            .busy,
            .goodService,
            .plentyOfCapacity,
            .noDemand,
        ]
        return priority.first(where: feedback.contains) ?? .noDemand
    }

    private func derivedMarketID(
        sourceID: UUID,
        startIndex: Int,
        endIndex: Int
    ) -> UUID {
        stableDerivedID(
            bytes: Array("\(sourceID.uuidString)|\(startIndex)|\(endIndex)".utf8),
            fallback: sourceID
        )
    }

    private func stableDerivedID(bytes: [UInt8], fallback: UUID) -> UUID {
        func hash(seed: UInt64) -> UInt64 {
            bytes.reduce(seed) { partial, byte in
                (partial ^ UInt64(byte)) &* 1_099_511_628_211
            }
        }
        let first = hash(seed: 14_695_981_039_346_656_037)
        let second = hash(seed: 7_809_847_782_469_553_597)
        let hex = String(format: "%016llx%016llx", first, second)
        let firstDash = hex.index(hex.startIndex, offsetBy: 8)
        let secondDash = hex.index(firstDash, offsetBy: 4)
        let thirdDash = hex.index(secondDash, offsetBy: 4)
        let fourthDash = hex.index(thirdDash, offsetBy: 4)
        let pieces = [
            String(hex[..<firstDash]),
            String(hex[firstDash..<secondDash]),
            String(hex[secondDash..<thirdDash]),
            String(hex[thirdDash..<fourthDash]),
            String(hex[fourthDash...]),
        ]
        return UUID(uuidString: pieces.joined(separator: "-")) ?? fallback
    }

    /// Builds at most one deterministic one-change itinerary for every outer station pair that
    /// lacks a direct service. Multiple markets share residual seats through progressive filling,
    /// so adding a third (or twelfth) service cannot make passenger allocation depend on array or
    /// UUID ordering.
    private func connectingJourneys(
        between groups: [DirectPassengerGroupSnapshot],
        directLinesByID: [UUID: PassengerLineSnapshot],
        stationPopulationMultipliers: [String: Double]
    ) -> ConnectingPassengerAllocation {
        guard groups.count >= 2 else { return .empty }
        let sortedGroups = groups.sorted { $0.pair < $1.pair }
        let directPairs = Set(sortedGroups.map(\.pair))
        var bestCandidateByMarket = [ConnectingMarketKey: ConnectingJourneyCandidate]()

        // Only services incident to the same station can form a one-change itinerary. Indexing by
        // station avoids comparing every direct market with every other market: a nationwide
        // chain now scales with local station degree rather than the square of every OD pair.
        var groupsByInterchange = [String: [DirectPassengerGroupSnapshot]]()
        groupsByInterchange.reserveCapacity(sortedGroups.count)
        for group in sortedGroups {
            for stationCRS in group.pair.stationCRSs {
                groupsByInterchange[stationCRS, default: []].append(group)
            }
        }

        for interchangeCRS in groupsByInterchange.keys.sorted() {
            guard let incidentGroups = groupsByInterchange[interchangeCRS]?.sorted(by: {
                $0.pair < $1.pair
            }), incidentGroups.count >= 2 else { continue }

            let interchangeCandidates = connectingCandidates(
                at: interchangeCRS,
                between: incidentGroups,
                excludingDirectPairs: directPairs,
                stationPopulationMultipliers: stationPopulationMultipliers
            )
            for candidate in interchangeCandidates {
                if let existing = bestCandidateByMarket[candidate.market],
                   !candidate.precedes(existing) {
                    continue
                }
                bestCandidateByMarket[candidate.market] = candidate
            }
        }

        let candidates = bestCandidateByMarket.values.sorted { $0.market < $1.market }
        guard !candidates.isEmpty else { return .empty }
        let groupsByPair = Dictionary(
            uniqueKeysWithValues: sortedGroups.map { ($0.pair, $0) }
        )
        let capacityPhasesByPair = Dictionary(
            uniqueKeysWithValues: sortedGroups.map { ($0.pair, capacityPhases(for: $0)) }
        )
        let peakCapacityByPair = capacityPhasesByPair.mapValues(\.residualPeak)
        let offPeakCapacityByPair = capacityPhasesByPair.mapValues(\.residualOffPeak)
        let carriedPeakByMarket = fairConnectingPhaseAllocation(
            candidates: candidates,
            capacityByPair: peakCapacityByPair,
            requested: \.requestedPeak
        )
        let carriedOffPeakByMarket = fairConnectingPhaseAllocation(
            candidates: candidates,
            capacityByPair: offPeakCapacityByPair,
            requested: \.requestedOffPeak
        )
        let dailyResidualByPair = Dictionary(uniqueKeysWithValues: sortedGroups.map { group in
            (
                group.pair,
                max(group.market.dailyCapacity - group.market.passengersPerDay, 0)
            )
        })
        let carriedByMarket = roundedConnectingPassengerAllocation(
            candidates: candidates,
            carriedPeakByMarket: carriedPeakByMarket,
            carriedOffPeakByMarket: carriedOffPeakByMarket,
            dailyResidualByPair: dailyResidualByPair
        )

        var potentialByPair = [StationPairKey: Int]()
        var attractedByPair = [StationPairKey: Int]()
        var carriedByPair = [StationPairKey: Int]()
        var requestedPeakByPair = [StationPairKey: Double]()
        var carriedPeakByPair = [StationPairKey: Double]()
        var snapshots = [PassengerConnectingJourneySnapshot]()
        snapshots.reserveCapacity(candidates.count)

        for candidate in candidates {
            let carried = carriedByMarket[candidate.market, default: 0]
            snapshots.append(PassengerConnectingJourneySnapshot(
                originCRS: candidate.market.originCRS,
                destinationCRS: candidate.market.destinationCRS,
                interchangeCRS: candidate.interchangeCRS,
                potentialDailyJourneys: candidate.potentialDailyJourneys,
                attractedDailyJourneys: candidate.attractedDailyJourneys,
                passengersPerDay: carried,
                inVehicleJourneyMinutes: candidate.inVehicleJourneyMinutes,
                averageWaitMinutes: candidate.averageWaitMinutes,
                interchangePenaltyMinutes: Self.connectingInterchangePenaltyMinutes,
                combinedReliability: candidate.combinedReliability,
                demandServedRatio: ratio(carried, over: candidate.attractedDailyJourneys),
                demandCapturedRatio: ratio(carried, over: candidate.potentialDailyJourneys)
            ))

            for pair in candidate.servicePairs {
                potentialByPair[pair, default: 0] = addingWithoutOverflow(
                    potentialByPair[pair, default: 0],
                    candidate.potentialDailyJourneys
                )
                attractedByPair[pair, default: 0] = addingWithoutOverflow(
                    attractedByPair[pair, default: 0],
                    candidate.attractedDailyJourneys
                )
                carriedByPair[pair, default: 0] = addingWithoutOverflow(
                    carriedByPair[pair, default: 0],
                    carried
                )
                requestedPeakByPair[pair, default: 0] = addingFiniteNonnegative(
                    requestedPeakByPair[pair, default: 0],
                    candidate.requestedPeak
                )
                carriedPeakByPair[pair, default: 0] = addingFiniteNonnegative(
                    carriedPeakByPair[pair, default: 0],
                    carriedPeakByMarket[candidate.market, default: 0]
                )
            }
        }

        var combinedLinesByID = [UUID: PassengerLineSnapshot]()
        for pair in potentialByPair.keys.sorted() {
            guard let group = groupsByPair[pair],
                  let phases = capacityPhasesByPair[pair] else { continue }
            let potential = potentialByPair[pair, default: 0]
            let attracted = attractedByPair[pair, default: 0]
            let carried = carriedByPair[pair, default: 0]
            let capacityWeights = serviceCapacityWeights(for: group.lines)
            let potentialAllocation = allocate(potential, using: capacityWeights)
            let attractedAllocation = allocate(attracted, using: capacityWeights)
            let residualByID = Dictionary(uniqueKeysWithValues: group.lines.map { line in
                let direct = directLinesByID[line.id]?.passengersPerDay ?? 0
                let capacity = directLinesByID[line.id]?.dailyCapacity ?? 0
                return (line.id, max(capacity - direct, 0))
            })
            let connectingAllocation = allocateBounded(
                carried,
                using: capacityWeights,
                capacitiesByID: residualByID
            )
            let combinedAttracted = addingWithoutOverflow(
                group.market.attractedDailyJourneys,
                attracted
            )
            let combinedPassengers = addingWithoutOverflow(
                group.market.passengersPerDay,
                carried
            )
            let peakCapacity = phases.peakCapacity
            let combinedPeakDemand = addingFiniteNonnegative(
                phases.directPeakDemand,
                requestedPeakByPair[pair, default: 0]
            )
            let combinedPeakCarried = addingFiniteNonnegative(
                phases.directPeakCarried,
                carriedPeakByPair[pair, default: 0]
            )
            let capacityPressure = peakCapacity > 0
                ? max(finite(combinedPeakDemand / peakCapacity, fallback: 0), 0)
                : 0
            let peakOccupancy = peakCapacity > 0
                ? clamp(
                    finite(combinedPeakCarried / peakCapacity, fallback: 0),
                    lower: 0,
                    upper: 1
                )
                : 0
            let groupFeedback = feedback(
                attractedDailyJourneys: combinedAttracted,
                averageWaitMinutes: group.market.averageWaitMinutes,
                capacityPressure: capacityPressure,
                demandServedRatio: ratio(combinedPassengers, over: combinedAttracted)
            )

            for line in group.lines {
                guard let direct = directLinesByID[line.id] else { continue }
                let linePotential = addingWithoutOverflow(
                    direct.potentialDailyJourneys,
                    potentialAllocation[line.id, default: 0]
                )
                let lineAttracted = addingWithoutOverflow(
                    direct.attractedDailyJourneys,
                    attractedAllocation[line.id, default: 0]
                )
                let lineConnecting = connectingAllocation[line.id, default: 0]
                let linePassengers = min(
                    addingWithoutOverflow(direct.passengersPerDay, lineConnecting),
                    direct.dailyCapacity
                )
                let estimate = PassengerDemandEstimate(
                    potentialDailyJourneys: linePotential,
                    attractedDailyJourneys: lineAttracted,
                    passengersPerDay: linePassengers,
                    dailyCapacity: direct.dailyCapacity,
                    journeyMinutes: direct.journeyMinutes,
                    averageWaitMinutes: direct.averageWaitMinutes,
                    demandServedRatio: ratio(linePassengers, over: lineAttracted),
                    demandCapturedRatio: ratio(linePassengers, over: linePotential),
                    peakOccupancyRatio: peakOccupancy,
                    capacityPressure: capacityPressure,
                    feedback: line.isStationCapacityConstrained
                        ? .stationCapacityConstrained
                        : groupFeedback
                )
                combinedLinesByID[line.id] = PassengerLineSnapshot(
                    input: line,
                    estimate: estimate,
                    directPassengersPerDay: direct.directPassengersPerDay,
                    connectingPassengersPerDay: lineConnecting
                )
            }
        }
        return ConnectingPassengerAllocation(
            snapshots: snapshots,
            linesByID: combinedLinesByID
        )
    }

    /// Keeps compact interchanges byte-for-byte equivalent to the original exhaustive scan. Once
    /// the theoretical pair count exceeds the detail budget, a k-way merge visits the best leg
    /// pairs without materialising the complete quadratic cross-product. The ranking favours
    /// lower generalized time, then reliability, distance and stable service-pair identity.
    private func connectingCandidates(
        at interchangeCRS: String,
        between incidentGroups: [DirectPassengerGroupSnapshot],
        excludingDirectPairs directPairs: Set<StationPairKey>,
        stationPopulationMultipliers: [String: Double]
    ) -> [ConnectingJourneyCandidate] {
        guard incidentGroups.count >= 2 else { return [] }
        let pairCount = unorderedPairCount(incidentGroups.count)
        let candidateLimit = max(
            Self.maximumConnectingJourneyCandidatesPerInterchange,
            0
        )
        guard candidateLimit > 0 else { return [] }

        if pairCount <= candidateLimit {
            var candidates = [ConnectingJourneyCandidate]()
            candidates.reserveCapacity(pairCount)
            for firstIndex in 0..<(incidentGroups.count - 1) {
                for secondIndex in (firstIndex + 1)..<incidentGroups.count {
                    guard let candidate = connectingCandidate(
                        at: interchangeCRS,
                        firstGroup: incidentGroups[firstIndex],
                        secondGroup: incidentGroups[secondIndex],
                        excludingDirectPairs: directPairs,
                        stationPopulationMultipliers: stationPopulationMultipliers
                    ) else { continue }
                    candidates.append(candidate)
                }
            }
            return candidates
        }

        let legs = incidentGroups.compactMap { group -> RankedInterchangeLeg? in
            guard let outerCRS = group.pair.otherStation(than: interchangeCRS) else {
                return nil
            }
            let reliability = departuresWeightedReliability(for: group.lines)
            return RankedInterchangeLeg(
                group: group,
                outerCRS: outerCRS,
                generalizedMinutes: addingFiniteNonnegative(
                    group.market.journeyMinutes,
                    group.market.averageWaitMinutes
                ),
                reliabilityPenalty: 1 - reliability,
                distanceKilometres: group.distanceKilometres
            )
        }
        .sorted(by: RankedInterchangeLeg.precedes)
        guard legs.count >= 2 else { return [] }

        var frontier = RankedInterchangePairHeap()
        for firstIndex in 0..<(legs.count - 1) {
            frontier.insert(rankedInterchangePair(
                firstIndex: firstIndex,
                secondIndex: firstIndex + 1,
                legs: legs
            ))
        }

        let multiplication = candidateLimit.multipliedReportingOverflow(
            by: Self.connectingJourneyCandidateSearchMultiplier
        )
        let searchLimit = multiplication.overflow ? Int.max : multiplication.partialValue
        var examinedCount = 0
        var candidates = [ConnectingJourneyCandidate]()
        candidates.reserveCapacity(candidateLimit)
        while candidates.count < candidateLimit,
              examinedCount < searchLimit,
              let pair = frontier.removeMinimum() {
            examinedCount += 1
            let lhs = legs[pair.firstIndex].group
            let rhs = legs[pair.secondIndex].group
            let orderedGroups = lhs.pair < rhs.pair ? (lhs, rhs) : (rhs, lhs)
            if let candidate = connectingCandidate(
                at: interchangeCRS,
                firstGroup: orderedGroups.0,
                secondGroup: orderedGroups.1,
                excludingDirectPairs: directPairs,
                stationPopulationMultipliers: stationPopulationMultipliers
            ) {
                candidates.append(candidate)
            }

            let nextSecondIndex = pair.secondIndex + 1
            if nextSecondIndex < legs.count {
                frontier.insert(rankedInterchangePair(
                    firstIndex: pair.firstIndex,
                    secondIndex: nextSecondIndex,
                    legs: legs
                ))
            }
        }
        return candidates
    }

    private func connectingCandidate(
        at interchangeCRS: String,
        firstGroup: DirectPassengerGroupSnapshot,
        secondGroup: DirectPassengerGroupSnapshot,
        excludingDirectPairs directPairs: Set<StationPairKey>,
        stationPopulationMultipliers: [String: Double]
    ) -> ConnectingJourneyCandidate? {
        guard let firstOuterCRS = firstGroup.pair.otherStation(than: interchangeCRS),
              let secondOuterCRS = secondGroup.pair.otherStation(than: interchangeCRS),
              firstOuterCRS != secondOuterCRS,
              let market = ConnectingMarketKey(
                  firstCRS: firstOuterCRS,
                  secondCRS: secondOuterCRS
              ),
              !directPairs.contains(market.stationPair) else { return nil }
        return connectingCandidate(
            market: market,
            interchangeCRS: interchangeCRS,
            firstGroup: firstGroup,
            secondGroup: secondGroup,
            stationPopulationMultipliers: stationPopulationMultipliers
        )
    }

    private func rankedInterchangePair(
        firstIndex: Int,
        secondIndex: Int,
        legs: [RankedInterchangeLeg]
    ) -> RankedInterchangePair {
        let first = legs[firstIndex]
        let second = legs[secondIndex]
        let orderedPairs = first.group.pair < second.group.pair
            ? (first.group.pair, second.group.pair)
            : (second.group.pair, first.group.pair)
        return RankedInterchangePair(
            firstIndex: firstIndex,
            secondIndex: secondIndex,
            generalizedMinutes: addingFiniteNonnegative(
                first.generalizedMinutes,
                second.generalizedMinutes
            ),
            reliabilityPenalty: addingFiniteNonnegative(
                first.reliabilityPenalty,
                second.reliabilityPenalty
            ),
            distanceKilometres: addingFiniteNonnegative(
                first.distanceKilometres,
                second.distanceKilometres
            ),
            firstPair: orderedPairs.0,
            secondPair: orderedPairs.1
        )
    }

    private func connectingCandidate(
        market: ConnectingMarketKey,
        interchangeCRS: String,
        firstGroup: DirectPassengerGroupSnapshot,
        secondGroup: DirectPassengerGroupSnapshot,
        stationPopulationMultipliers: [String: Double]
    ) -> ConnectingJourneyCandidate? {
        let totalDistance = addingFiniteNonnegative(
            firstGroup.distanceKilometres,
            secondGroup.distanceKilometres
        )
        guard totalDistance > 0 else { return nil }

        // Latent demand uses only the outer endpoints. The interchange therefore never creates
        // demand, and settlement population multipliers apply exactly once at each journey end.
        let potential = estimateMarket(
            originCRS: market.originCRS,
            destinationCRS: market.destinationCRS,
            distanceKilometres: totalDistance,
            departuresPerHour: 1,
            stationPopulationMultipliers: stationPopulationMultipliers
        ).potentialDailyJourneys
        let inVehicleMinutes = addingFiniteNonnegative(
            firstGroup.market.journeyMinutes,
            secondGroup.market.journeyMinutes
        )
        let waitMinutes = addingFiniteNonnegative(
            firstGroup.market.averageWaitMinutes,
            secondGroup.market.averageWaitMinutes
        )
        let generalizedMinutes = addingFiniteNonnegative(
            addingFiniteNonnegative(inVehicleMinutes, waitMinutes),
            Self.connectingInterchangePenaltyMinutes
        )
        let penaltyWindow = positiveFinite(
            configuration.servicePenaltyWindowMinutes,
            fallback: 180
        )
        let minimumAttraction = clamp(
            finite(configuration.minimumAttractionRatio, fallback: 0.4),
            lower: 0,
            upper: 1
        )
        let timetableAttraction = clamp(
            finite(configuration.serviceAttractionBaseline, fallback: 1)
                - generalizedMinutes / penaltyWindow,
            lower: minimumAttraction,
            upper: 1
        )
        let combinedReliability = clamp(
            departuresWeightedReliability(for: firstGroup.lines)
                * departuresWeightedReliability(for: secondGroup.lines),
            lower: 0,
            upper: 1
        )
        let attracted = roundedCount(
            Double(potential) * timetableAttraction * combinedReliability
        )
        let peakShare = clamp(
            finite(configuration.peakDemandShare, fallback: 0),
            lower: 0,
            upper: 1
        )
        return ConnectingJourneyCandidate(
            market: market,
            interchangeCRS: interchangeCRS,
            firstPair: firstGroup.pair,
            secondPair: secondGroup.pair,
            totalDistanceKilometres: totalDistance,
            potentialDailyJourneys: potential,
            attractedDailyJourneys: attracted,
            inVehicleJourneyMinutes: inVehicleMinutes,
            averageWaitMinutes: waitMinutes,
            generalizedJourneyMinutes: generalizedMinutes,
            combinedReliability: combinedReliability,
            requestedPeak: boundedNonnegativeProduct(Double(attracted), peakShare),
            requestedOffPeak: boundedNonnegativeProduct(
                Double(attracted),
                1 - peakShare
            )
        )
    }

    private func fairConnectingPhaseAllocation(
        candidates: [ConnectingJourneyCandidate],
        capacityByPair: [StationPairKey: Double],
        requested: KeyPath<ConnectingJourneyCandidate, Double>
    ) -> [ConnectingMarketKey: Double] {
        let requestsByMarket = Dictionary(uniqueKeysWithValues: candidates.map {
            ($0.market, max($0[keyPath: requested], 0))
        })
        var ratiosByMarket = Dictionary(uniqueKeysWithValues: candidates.map {
            ($0.market, 0.0)
        })
        var activeMarkets = Set(candidates.compactMap {
            requestsByMarket[$0.market, default: 0] > 0 ? $0.market : nil
        })
        var candidateIndicesByPair = [StationPairKey: [Int]]()
        candidateIndicesByPair.reserveCapacity(capacityByPair.count)
        for (candidateIndex, candidate) in candidates.enumerated() {
            for pair in candidate.servicePairs {
                candidateIndicesByPair[pair, default: []].append(candidateIndex)
            }
        }
        let epsilon = 0.000_000_001
        let maximumPasses = max(candidates.count + capacityByPair.count + 1, 1)

        for _ in 0..<maximumPasses where !activeMarkets.isEmpty {
            var delta = activeMarkets.reduce(1.0) { current, market in
                min(current, max(1 - ratiosByMarket[market, default: 0], 0))
            }
            var pairDelta = [StationPairKey: Double]()

            for pair in capacityByPair.keys.sorted() {
                let pairCandidateIndices = candidateIndicesByPair[pair] ?? []
                let activeCandidateIndices = pairCandidateIndices.filter {
                    activeMarkets.contains(candidates[$0].market)
                }
                guard !activeCandidateIndices.isEmpty else { continue }
                let used = pairCandidateIndices.reduce(0.0) { total, candidateIndex in
                    let candidate = candidates[candidateIndex]
                    return addingFiniteNonnegative(
                        total,
                        boundedNonnegativeProduct(
                            requestsByMarket[candidate.market, default: 0],
                            ratiosByMarket[candidate.market, default: 0]
                        )
                    )
                }
                let capacity = max(capacityByPair[pair, default: 0], 0)
                let remaining = max(capacity - min(used, capacity), 0)
                let activeRequest = activeCandidateIndices.reduce(0.0) {
                    addingFiniteNonnegative(
                        $0,
                        requestsByMarket[candidates[$1].market, default: 0]
                    )
                }
                guard activeRequest > 0 else { continue }
                let resourceDelta = min(max(remaining / activeRequest, 0), 1)
                pairDelta[pair] = resourceDelta
                delta = min(delta, resourceDelta)
            }

            delta = delta.isFinite ? max(delta, 0) : 0
            for market in activeMarkets.sorted() {
                ratiosByMarket[market] = min(
                    ratiosByMarket[market, default: 0] + delta,
                    1
                )
            }

            var completedMarkets = Set<ConnectingMarketKey>()
            for candidate in candidates where activeMarkets.contains(candidate.market) {
                if ratiosByMarket[candidate.market, default: 0] >= 1 - epsilon {
                    ratiosByMarket[candidate.market] = 1
                    completedMarkets.insert(candidate.market)
                    continue
                }
                if candidate.servicePairs.contains(where: {
                    pairDelta[$0].map { $0 <= delta + epsilon } ?? false
                }) {
                    completedMarkets.insert(candidate.market)
                }
            }
            if completedMarkets.isEmpty {
                completedMarkets = activeMarkets
            }
            activeMarkets.subtract(completedMarkets)
        }

        return Dictionary(uniqueKeysWithValues: candidates.map { candidate in
            (
                candidate.market,
                boundedNonnegativeProduct(
                    requestsByMarket[candidate.market, default: 0],
                    ratiosByMarket[candidate.market, default: 0]
                )
            )
        })
    }

    private func unorderedPairCount(_ count: Int) -> Int {
        guard count > 1 else { return 0 }
        let first = count.isMultiple(of: 2) ? count / 2 : count
        let second = count.isMultiple(of: 2) ? count - 1 : (count - 1) / 2
        let result = first.multipliedReportingOverflow(by: second)
        return result.overflow ? Int.max : result.partialValue
    }

    private func roundedConnectingPassengerAllocation(
        candidates: [ConnectingJourneyCandidate],
        carriedPeakByMarket: [ConnectingMarketKey: Double],
        carriedOffPeakByMarket: [ConnectingMarketKey: Double],
        dailyResidualByPair: [StationPairKey: Int]
    ) -> [ConnectingMarketKey: Int] {
        var remainingByPair = dailyResidualByPair.mapValues { max($0, 0) }
        var allocation = Dictionary(uniqueKeysWithValues: candidates.map { ($0.market, 0) })
        var rawByMarket = [ConnectingMarketKey: Double]()

        for candidate in candidates {
            let raw = addingFiniteNonnegative(
                carriedPeakByMarket[candidate.market, default: 0],
                carriedOffPeakByMarket[candidate.market, default: 0]
            )
            rawByMarket[candidate.market] = raw
            let floorTarget = min(
                roundedCount(raw.rounded(.down)),
                candidate.attractedDailyJourneys
            )
            let available = candidate.servicePairs.map {
                remainingByPair[$0, default: 0]
            }.min() ?? 0
            let base = min(floorTarget, available)
            allocation[candidate.market] = base
            for pair in candidate.servicePairs {
                remainingByPair[pair, default: 0] -= base
            }
        }

        let remainderOrder = candidates.sorted { lhs, rhs in
            let lhsRaw = rawByMarket[lhs.market, default: 0]
            let rhsRaw = rawByMarket[rhs.market, default: 0]
            let lhsRemainder = lhsRaw - lhsRaw.rounded(.down)
            let rhsRemainder = rhsRaw - rhsRaw.rounded(.down)
            if lhsRemainder != rhsRemainder { return lhsRemainder > rhsRemainder }
            return lhs.market < rhs.market
        }
        for candidate in remainderOrder {
            let target = min(
                roundedCount(rawByMarket[candidate.market, default: 0]),
                candidate.attractedDailyJourneys
            )
            let current = allocation[candidate.market, default: 0]
            guard target > current else { continue }
            let available = candidate.servicePairs.map {
                remainingByPair[$0, default: 0]
            }.min() ?? 0
            let addition = min(target - current, available)
            guard addition > 0 else { continue }
            allocation[candidate.market] = current + addition
            for pair in candidate.servicePairs {
                remainingByPair[pair, default: 0] -= addition
            }
        }
        return allocation
    }

    private func capacityPhases(
        for group: DirectPassengerGroupSnapshot
    ) -> PassengerCapacityPhases {
        let operatingHours = max(
            finite(configuration.operatingHoursPerDay, fallback: 0),
            0
        )
        let peakHours = clamp(
            finite(configuration.peakHoursPerDay, fallback: 0),
            lower: 0,
            upper: operatingHours
        )
        let peakCapacityShare = operatingHours > 0 ? peakHours / operatingHours : 0
        let dailyCapacity = Double(max(group.market.dailyCapacity, 0))
        let peakCapacity = boundedNonnegativeProduct(dailyCapacity, peakCapacityShare)
        let offPeakCapacity = max(dailyCapacity - peakCapacity, 0)
        let peakDemandShare = clamp(
            finite(configuration.peakDemandShare, fallback: 0),
            lower: 0,
            upper: 1
        )
        let directPeakDemand = boundedNonnegativeProduct(
            Double(group.market.attractedDailyJourneys),
            peakDemandShare
        )
        let directOffPeakDemand = boundedNonnegativeProduct(
            Double(group.market.attractedDailyJourneys),
            1 - peakDemandShare
        )
        let directPeakCarried = min(directPeakDemand, peakCapacity)
        let directOffPeakCarried = min(directOffPeakDemand, offPeakCapacity)
        return PassengerCapacityPhases(
            peakCapacity: peakCapacity,
            directPeakDemand: directPeakDemand,
            directPeakCarried: directPeakCarried,
            residualPeak: max(peakCapacity - directPeakCarried, 0),
            residualOffPeak: max(offPeakCapacity - directOffPeakCarried, 0)
        )
    }

    /// Largest-remainder allocation followed by a deterministic capacity reconciliation. In the
    /// POC each leg has one line; the bounded form also keeps future duplicate service groups safe.
    private func allocateBounded(
        _ total: Int,
        using weights: [(id: UUID, weight: Int)],
        capacitiesByID: [UUID: Int]
    ) -> [UUID: Int] {
        let target = min(
            max(total, 0),
            capacitiesByID.values.reduce(0, addingWithoutOverflow)
        )
        var allocation = allocate(target, using: weights)
        var allocated = 0
        for id in allocation.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            allocation[id] = min(
                max(allocation[id, default: 0], 0),
                max(capacitiesByID[id, default: 0], 0)
            )
            allocated = addingWithoutOverflow(allocated, allocation[id, default: 0])
        }

        var remaining = max(target - allocated, 0)
        for id in allocation.keys.sorted(by: { $0.uuidString < $1.uuidString })
        where remaining > 0 {
            let available = max(
                capacitiesByID[id, default: 0] - allocation[id, default: 0],
                0
            )
            let addition = min(remaining, available)
            allocation[id, default: 0] = addingWithoutOverflow(
                allocation[id, default: 0],
                addition
            )
            remaining -= addition
        }
        return allocation
    }

    private func estimateMarket(
        originCRS: String,
        destinationCRS: String,
        distanceKilometres: Double,
        departuresPerHour rawDeparturesPerHour: Double,
        journeyTimeMultiplier rawJourneyTimeMultiplier: Double = 1,
        capacityPerTrain rawCapacityPerTrain: Int? = nil,
        hourlySeatCapacityPerDirection rawHourlySeatCapacityPerDirection: Double? = nil,
        stationPopulationMultipliers: [String: Double] = [:]
    ) -> PassengerDemandEstimate {
        guard !originCRS.isEmpty,
              !destinationCRS.isEmpty,
              originCRS != destinationCRS,
              distanceKilometres.isFinite,
              distanceKilometres > 0 else {
            return .zero
        }

        let fallbackWeight = positiveFinite(
            configuration.fallbackStationDemandWeight,
            fallback: 1
        )
        let baselineOriginWeight = positiveFinite(
            configuration.stationDemandWeights[originCRS] ?? fallbackWeight,
            fallback: fallbackWeight
        )
        let baselineDestinationWeight = positiveFinite(
            configuration.stationDemandWeights[destinationCRS] ?? fallbackWeight,
            fallback: fallbackWeight
        )
        let originWeight = positiveFinite(
            baselineOriginWeight
                * (stationPopulationMultipliers[originCRS] ?? 1),
            fallback: baselineOriginWeight
        )
        let destinationWeight = positiveFinite(
            baselineDestinationWeight
                * (stationPopulationMultipliers[destinationCRS] ?? 1),
            fallback: baselineDestinationWeight
        )
        let distanceFloor = clamp(
            finite(configuration.minimumDistanceFactor, fallback: 0.35),
            lower: 0,
            upper: 1
        )
        let distanceDecay = positiveFinite(
            configuration.distanceDecayKilometres,
            fallback: 80
        )
        let distanceFactor = distanceFloor
            + (1 - distanceFloor) * exp(-distanceKilometres / distanceDecay)
        let baseDailyJourneys = max(
            finite(configuration.baseDailyJourneys, fallback: 0),
            0
        )
        let potential = roundedCount(
            baseDailyJourneys * sqrt(originWeight * destinationWeight) * distanceFactor
        )

        let averageSpeed = positiveFinite(
            configuration.averageRailSpeedKilometresPerHour,
            fallback: 100
        )
        let minimumJourney = max(
            finite(configuration.minimumJourneyMinutes, fallback: 0),
            0
        )
        let journeyTimeMultiplier = normalizedJourneyTimeMultiplier(
            rawJourneyTimeMultiplier
        )
        let unscaledJourneyMinutes = distanceKilometres / averageSpeed * 60
        let scaledJourneyMinutes = unscaledJourneyMinutes * journeyTimeMultiplier
        let journeyMinutes = max(
            minimumJourney,
            finite(scaledJourneyMinutes, fallback: Double.greatestFiniteMagnitude)
        )
        let departuresPerHour = rawDeparturesPerHour.isFinite
            ? max(rawDeparturesPerHour, 0)
            : 0
        guard departuresPerHour > 0 else {
            return PassengerDemandEstimate(
                potentialDailyJourneys: potential,
                attractedDailyJourneys: 0,
                passengersPerDay: 0,
                dailyCapacity: 0,
                journeyMinutes: journeyMinutes,
                averageWaitMinutes: 0,
                demandServedRatio: 0,
                demandCapturedRatio: 0,
                peakOccupancyRatio: 0,
                capacityPressure: 0,
                feedback: .noDemand
            )
        }
        let waitMinutes = 30 / departuresPerHour
        let penaltyWindow = positiveFinite(
            configuration.servicePenaltyWindowMinutes,
            fallback: 180
        )
        let minimumAttraction = clamp(
            finite(configuration.minimumAttractionRatio, fallback: 0.4),
            lower: 0,
            upper: 1
        )
        let attraction = clamp(
            finite(configuration.serviceAttractionBaseline, fallback: 1)
                - (journeyMinutes + waitMinutes) / penaltyWindow,
            lower: minimumAttraction,
            upper: 1
        )
        let attracted = roundedCount(Double(potential) * attraction)

        let capacityPerTrain = max(
            rawCapacityPerTrain ?? configuration.trainCapacity,
            0
        )
        let operatingHours = max(
            finite(configuration.operatingHoursPerDay, fallback: 0),
            0
        )
        let peakHours = clamp(
            finite(configuration.peakHoursPerDay, fallback: 0),
            lower: 0,
            upper: operatingHours
        )
        let offPeakHours = max(operatingHours - peakHours, 0)
        let peakShare = clamp(
            finite(configuration.peakDemandShare, fallback: 0),
            lower: 0,
            upper: 1
        )
        let peakDemand = Double(attracted) * peakShare
        let offPeakDemand = Double(attracted) - peakDemand
        let hourlySeatCapacityPerDirection: Double
        if let rawHourlySeatCapacityPerDirection {
            hourlySeatCapacityPerDirection = max(
                finite(rawHourlySeatCapacityPerDirection, fallback: 0),
                0
            )
        } else {
            hourlySeatCapacityPerDirection = boundedNonnegativeProduct(
                Double(capacityPerTrain),
                departuresPerHour
            )
        }
        let twoWayHourlyCapacity = boundedNonnegativeProduct(
            hourlySeatCapacityPerDirection,
            2
        )
        let peakCapacity = twoWayHourlyCapacity * peakHours
        let offPeakCapacity = twoWayHourlyCapacity * offPeakHours
        let carried = roundedCount(
            min(peakDemand, peakCapacity) + min(offPeakDemand, offPeakCapacity)
        )
        let dailyCapacity = roundedCount(peakCapacity + offPeakCapacity)
        let capacityPressure = peakCapacity > 0 ? peakDemand / peakCapacity : 0
        let peakOccupancy = clamp(capacityPressure, lower: 0, upper: 1)
        let servedRatio = ratio(carried, over: attracted)
        let capturedRatio = ratio(carried, over: potential)
        let feedback = feedback(
            attractedDailyJourneys: attracted,
            averageWaitMinutes: waitMinutes,
            capacityPressure: capacityPressure,
            demandServedRatio: servedRatio
        )

        return PassengerDemandEstimate(
            potentialDailyJourneys: potential,
            attractedDailyJourneys: attracted,
            passengersPerDay: carried,
            dailyCapacity: dailyCapacity,
            journeyMinutes: journeyMinutes,
            averageWaitMinutes: waitMinutes,
            demandServedRatio: servedRatio,
            demandCapturedRatio: capturedRatio,
            peakOccupancyRatio: peakOccupancy,
            capacityPressure: max(capacityPressure, 0),
            feedback: feedback
        )
    }

    private func applyingStationCapacityFeedback(
        _ estimate: PassengerDemandEstimate,
        for input: PassengerLineInput
    ) -> PassengerDemandEstimate {
        guard input.isStationCapacityConstrained else { return estimate }
        return PassengerDemandEstimate(
            potentialDailyJourneys: estimate.potentialDailyJourneys,
            attractedDailyJourneys: estimate.attractedDailyJourneys,
            passengersPerDay: estimate.passengersPerDay,
            dailyCapacity: estimate.dailyCapacity,
            journeyMinutes: estimate.journeyMinutes,
            averageWaitMinutes: estimate.averageWaitMinutes,
            demandServedRatio: estimate.demandServedRatio,
            demandCapturedRatio: estimate.demandCapturedRatio,
            peakOccupancyRatio: estimate.peakOccupancyRatio,
            capacityPressure: estimate.capacityPressure,
            feedback: .stationCapacityConstrained
        )
    }

    private func feedback(
        attractedDailyJourneys: Int,
        averageWaitMinutes: Double,
        capacityPressure: Double,
        demandServedRatio: Double
    ) -> PassengerServiceFeedback {
        guard attractedDailyJourneys > 0 else { return .noDemand }

        let constrainedThreshold = max(
            finite(configuration.constrainedCapacityPressure, fallback: 0.9),
            0
        )
        if capacityPressure >= constrainedThreshold || demandServedRatio < 0.98 {
            return .capacityConstrained
        }

        let infrequentThreshold = max(
            finite(configuration.infrequentWaitThresholdMinutes, fallback: 20),
            0
        )
        if averageWaitMinutes >= infrequentThreshold {
            return .infrequent
        }

        let busyThreshold = max(
            finite(configuration.busyCapacityPressure, fallback: 0.7),
            0
        )
        if capacityPressure >= busyThreshold {
            return .busy
        }

        let quietThreshold = max(
            finite(configuration.quietCapacityPressure, fallback: 0.25),
            0
        )
        if capacityPressure < quietThreshold {
            return .plentyOfCapacity
        }

        return .goodService
    }

    private func allocate(
        _ total: Int,
        using weights: [(id: UUID, weight: Int)]
    ) -> [UUID: Int] {
        guard total > 0, !weights.isEmpty else {
            return Dictionary(uniqueKeysWithValues: weights.map { ($0.id, 0) })
        }

        let sortedWeights = normalizedAllocationWeights(
            weights.sorted { $0.id.uuidString < $1.id.uuidString }
        )
        let totalWeight = sortedWeights.reduce(0) {
            addingWithoutOverflow($0, max($1.weight, 0))
        }
        guard totalWeight > 0 else {
            return Dictionary(uniqueKeysWithValues: sortedWeights.map { ($0.id, 0) })
        }

        var allocation = [UUID: Int](minimumCapacity: sortedWeights.count)
        var remainders = [(id: UUID, remainder: Int)]()
        var allocated = 0
        for item in sortedWeights {
            let weight = max(item.weight, 0)
            // Decompose before multiplying so even an Int.max synthetic demand remains bounded.
            let quotient = total / totalWeight
            let residual = total % totalWeight
            let share = addingWithoutOverflow(
                quotient * weight,
                residual * weight / totalWeight
            )
            allocation[item.id] = share
            allocated = addingWithoutOverflow(allocated, share)
            remainders.append((item.id, residual * weight % totalWeight))
        }

        var remaining = max(total - allocated, 0)
        remainders.sort { lhs, rhs in
            if lhs.remainder != rhs.remainder { return lhs.remainder > rhs.remainder }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        for item in remainders where remaining > 0 {
            let id = item.id
            allocation[id, default: 0] += 1
            remaining -= 1
        }

        return allocation
    }

    /// Real formations have small weights, so this is an identity transform in gameplay. It only
    /// scales adversarial synthetic capacities enough to keep largest-remainder multiplication
    /// representable while retaining deterministic proportions and non-zero services.
    private func normalizedAllocationWeights(
        _ weights: [(id: UUID, weight: Int)]
    ) -> [(id: UUID, weight: Int)] {
        guard !weights.isEmpty else { return [] }
        let positiveWeights = weights.map { max($0.weight, 0) }
        guard let largest = positiveWeights.max(), largest > 0 else { return weights }

        let count = max(weights.count, 1)
        let multiplicationSafeLimit = Int(
            sqrt(Double(Int.max) / Double(count)).rounded(.down)
        )
        let maximumWeight = max(min(multiplicationSafeLimit, 1_000_000), 1)
        guard largest > maximumWeight else { return weights }

        let quotient = largest / maximumWeight
        let divisor = quotient + (largest % maximumWeight == 0 ? 0 : 1)
        return zip(weights, positiveWeights).map { item, positiveWeight in
            guard positiveWeight > 0 else { return (item.id, 0) }
            return (item.id, max(positiveWeight / divisor, 1))
        }
    }

    private func activityLevel(for passengers: Int) -> StationActivityLevel {
        let active = max(configuration.activeStationThreshold, 0)
        let busy = max(configuration.busyStationThreshold, active)
        let hub = max(configuration.hubStationThreshold, busy)
        return switch passengers {
        case hub...: .hub
        case busy..<hub: .busy
        case active..<busy: .active
        default: .quiet
        }
    }

    private func activity(for passengers: Int) -> Double {
        let hub = max(configuration.hubStationThreshold, 1)
        return clamp(Double(max(passengers, 0)) / Double(hub), lower: 0, upper: 1)
    }

    private func normalizedCRS(_ crs: String) -> String {
        crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func finite(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? value : fallback
    }

    private func positiveFinite(_ value: Double, fallback: Double) -> Double {
        value.isFinite && value > 0 ? value : fallback
    }

    private func normalizedJourneyTimeMultiplier(_ value: Double) -> Double {
        positiveFinite(value, fallback: 1)
    }

    /// Normalizes caller-supplied growth factors once at the simulation boundary. Missing,
    /// non-finite and non-positive values retain the existing baseline demand result.
    private func normalizedStationPopulationMultipliers(
        _ multipliers: [String: Double]
    ) -> [String: Double] {
        var result = [String: Double]()
        for (rawCRS, rawMultiplier) in multipliers.sorted(by: { $0.key < $1.key }) {
            let crs = normalizedCRS(rawCRS)
            guard !crs.isEmpty,
                  rawMultiplier.isFinite,
                  rawMultiplier > 0 else { continue }
            result[crs] = max(result[crs] ?? 0, rawMultiplier)
        }
        return result
    }

    /// Direct duplicate services share one market, so use their delivered departures as the
    /// deterministic weight for the market's representative journey time. Scaling by the largest
    /// multiplier avoids overflowing an otherwise finite weighted mean.
    private func departuresWeightedJourneyTimeMultiplier(
        for lines: [PassengerLineInput]
    ) -> Double {
        let weightedValues = lines.map { line in
            (
                multiplier: normalizedJourneyTimeMultiplier(line.journeyTimeMultiplier),
                departures: line.passengerDeparturesPerHour
            )
        }
        let totalDepartures = weightedValues.reduce(0.0) {
            addingFiniteNonnegative($0, $1.departures)
        }
        guard totalDepartures > 0,
              let scale = weightedValues.map(\.multiplier).max(),
              scale.isFinite,
              scale > 0 else {
            return 1
        }

        let normalizedTotal = weightedValues.reduce(0.0) { result, item in
            addingFiniteNonnegative(
                result,
                boundedNonnegativeProduct(item.multiplier / scale, item.departures)
            )
        }
        let weightedMean = scale * (normalizedTotal / totalDepartures)
        return normalizedJourneyTimeMultiplier(weightedMean)
    }

    private func departuresWeightedReliability(
        for lines: [PassengerLineInput]
    ) -> Double {
        let weightedValues = lines.map { line in
            (
                reliability: normalizedReliability(line.reliability),
                departures: line.passengerDeparturesPerHour
            )
        }
        let totalDepartures = weightedValues.reduce(0.0) {
            addingFiniteNonnegative($0, $1.departures)
        }
        guard totalDepartures > 0 else { return 1 }
        let weightedTotal = weightedValues.reduce(0.0) { result, item in
            addingFiniteNonnegative(
                result,
                boundedNonnegativeProduct(item.reliability, item.departures)
            )
        }
        return clamp(
            finite(weightedTotal / totalDepartures, fallback: 1),
            lower: 0,
            upper: 1
        )
    }

    /// Seat-departures are the deterministic capacity weight for duplicate services. With the
    /// legacy six-car formation this reduces exactly to the former frequency weighting.
    private func serviceCapacityWeights(
        for lines: [PassengerLineInput]
    ) -> [(id: UUID, weight: Int)] {
        let usesWholeDepartures = lines.allSatisfy { line in
            guard line.reservedHourlySeatCapacityPerDirection == nil else { return false }
            let departures = line.passengerDeparturesPerHour
            return departures.rounded() == departures && departures <= Double(Int.max)
        }
        return lines.map { line in
            let capacity = max(line.capacityPerTrain, 0)
            let departures = line.passengerDeparturesPerHour
            if usesWholeDepartures {
                let product = capacity.multipliedReportingOverflow(by: Int(departures))
                return (line.id, product.overflow ? Int.max : max(product.partialValue, 0))
            }
            let seatDepartures = line.oneWayHourlySeatCapacity
            let fixedPointWeight = boundedNonnegativeProduct(seatDepartures, 1_000_000)
            return (line.id, roundedCount(fixedPointWeight))
        }
    }

    private func hourlySeatCapacityPerDirection(
        for lines: [PassengerLineInput]
    ) -> Double {
        lines.reduce(0.0) { total, line in
            addingFiniteNonnegative(
                total,
                line.oneWayHourlySeatCapacity
            )
        }
    }

    private func dailyCapacity(for line: PassengerLineInput) -> Int {
        let oneWayHourly = line.oneWayHourlySeatCapacity
        let twoWayHourly = boundedNonnegativeProduct(oneWayHourly, 2)
        let operatingHours = max(
            finite(configuration.operatingHoursPerDay, fallback: 0),
            0
        )
        return roundedCount(boundedNonnegativeProduct(twoWayHourly, operatingHours))
    }

    private func normalizedReliability(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return clamp(value, lower: 0, upper: 1)
    }

    private func boundedNonnegativeProduct(_ lhs: Double, _ rhs: Double) -> Double {
        guard lhs.isFinite, rhs.isFinite, lhs > 0, rhs > 0 else { return 0 }
        guard lhs <= Double.greatestFiniteMagnitude / rhs else {
            return Double.greatestFiniteMagnitude
        }
        return lhs * rhs
    }

    private func addingFiniteNonnegative(_ lhs: Double, _ rhs: Double) -> Double {
        let safeLHS = lhs.isFinite ? max(lhs, 0) : 0
        let safeRHS = rhs.isFinite ? max(rhs, 0) : 0
        guard safeLHS <= Double.greatestFiniteMagnitude - safeRHS else {
            return Double.greatestFiniteMagnitude
        }
        return safeLHS + safeRHS
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    private func roundedCount(_ value: Double) -> Int {
        guard !value.isNaN, value > 0 else { return 0 }
        guard value.isFinite else { return Int.max }
        let rounded = value.rounded()
        // `Double(Int.max)` rounds up to 2^63, which is not itself representable as Int. Check the
        // boundary before conversion rather than relying on `min` and trapping at runtime.
        guard rounded < Double(Int.max) else { return Int.max }
        return Int(rounded)
    }

    private func ratio(_ numerator: Int, over denominator: Int) -> Double {
        guard denominator > 0 else { return 0 }
        return clamp(Double(max(numerator, 0)) / Double(denominator), lower: 0, upper: 1)
    }

    private func addingWithoutOverflow(_ lhs: Int, _ rhs: Int) -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? Int.max : result.partialValue
    }

    private func multiplyingWithoutOverflow(_ value: Int, by multiplier: Int) -> Int {
        let result = value.multipliedReportingOverflow(by: multiplier)
        return result.overflow ? Int.max : max(result.partialValue, 0)
    }
}

private nonisolated struct StationPairKey: Hashable, Comparable, Sendable {
    let firstCRS: String
    let secondCRS: String

    init?(line: PassengerLineInput) {
        guard !line.originCRS.isEmpty,
              !line.destinationCRS.isEmpty,
              line.originCRS != line.destinationCRS,
              line.distanceKilometres.isFinite,
              line.distanceKilometres > 0 else {
            return nil
        }

        if line.originCRS < line.destinationCRS {
            firstCRS = line.originCRS
            secondCRS = line.destinationCRS
        } else {
            firstCRS = line.destinationCRS
            secondCRS = line.originCRS
        }
    }

    init?(firstCRS: String, secondCRS: String) {
        guard !firstCRS.isEmpty, !secondCRS.isEmpty, firstCRS != secondCRS else {
            return nil
        }
        if firstCRS < secondCRS {
            self.firstCRS = firstCRS
            self.secondCRS = secondCRS
        } else {
            self.firstCRS = secondCRS
            self.secondCRS = firstCRS
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.firstCRS != rhs.firstCRS { return lhs.firstCRS < rhs.firstCRS }
        return lhs.secondCRS < rhs.secondCRS
    }

    var stationCRSs: [String] { [firstCRS, secondCRS] }

    func otherStation(than stationCRS: String) -> String? {
        if stationCRS == firstCRS { return secondCRS }
        if stationCRS == secondCRS { return firstCRS }
        return nil
    }
}

private nonisolated struct DirectPassengerGroupSnapshot: Sendable {
    let pair: StationPairKey
    let lines: [PassengerLineInput]
    let market: PassengerDemandEstimate
    let distanceKilometres: Double
}

private nonisolated struct RankedInterchangeLeg: Sendable {
    let group: DirectPassengerGroupSnapshot
    let outerCRS: String
    let generalizedMinutes: Double
    let reliabilityPenalty: Double
    let distanceKilometres: Double

    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.generalizedMinutes != rhs.generalizedMinutes {
            return lhs.generalizedMinutes < rhs.generalizedMinutes
        }
        if lhs.reliabilityPenalty != rhs.reliabilityPenalty {
            return lhs.reliabilityPenalty < rhs.reliabilityPenalty
        }
        if lhs.distanceKilometres != rhs.distanceKilometres {
            return lhs.distanceKilometres < rhs.distanceKilometres
        }
        if lhs.outerCRS != rhs.outerCRS { return lhs.outerCRS < rhs.outerCRS }
        return lhs.group.pair < rhs.group.pair
    }
}

private nonisolated struct RankedInterchangePair: Sendable {
    let firstIndex: Int
    let secondIndex: Int
    let generalizedMinutes: Double
    let reliabilityPenalty: Double
    let distanceKilometres: Double
    let firstPair: StationPairKey
    let secondPair: StationPairKey

    func precedes(_ other: Self) -> Bool {
        if generalizedMinutes != other.generalizedMinutes {
            return generalizedMinutes < other.generalizedMinutes
        }
        if reliabilityPenalty != other.reliabilityPenalty {
            return reliabilityPenalty < other.reliabilityPenalty
        }
        if distanceKilometres != other.distanceKilometres {
            return distanceKilometres < other.distanceKilometres
        }
        if firstPair != other.firstPair { return firstPair < other.firstPair }
        if secondPair != other.secondPair { return secondPair < other.secondPair }
        if firstIndex != other.firstIndex { return firstIndex < other.firstIndex }
        return secondIndex < other.secondIndex
    }
}

private nonisolated struct RankedInterchangePairHeap {
    private var storage = [RankedInterchangePair]()

    mutating func insert(_ item: RankedInterchangePair) {
        storage.append(item)
        var child = storage.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard storage[child].precedes(storage[parent]) else { break }
            storage.swapAt(child, parent)
            child = parent
        }
    }

    mutating func removeMinimum() -> RankedInterchangePair? {
        guard !storage.isEmpty else { return nil }
        if storage.count == 1 { return storage.removeLast() }
        let minimum = storage[0]
        storage[0] = storage.removeLast()
        var parent = 0
        while true {
            let left = 2 * parent + 1
            guard left < storage.count else { break }
            let right = left + 1
            let child = right < storage.count && storage[right].precedes(storage[left])
                ? right
                : left
            guard storage[child].precedes(storage[parent]) else { break }
            storage.swapAt(child, parent)
            parent = child
        }
        return minimum
    }
}

private nonisolated struct PassengerMarketProjection: Sendable {
    let sourceLineID: UUID
    let startIndex: Int
    let endIndex: Int
    let input: PassengerLineInput

    func uses(segment: Int) -> Bool {
        segment >= startIndex && segment < endIndex
    }

    func reservingHourlySeats(_ hourlySeats: Double) -> Self {
        Self(
            sourceLineID: sourceLineID,
            startIndex: startIndex,
            endIndex: endIndex,
            input: PassengerLineInput(
                id: input.id,
                originCRS: input.originCRS,
                destinationCRS: input.destinationCRS,
                distanceKilometres: input.distanceKilometres,
                frequency: input.frequency,
                servicePattern: input.servicePattern,
                journeyTimeMultiplier: input.journeyTimeMultiplier,
                reliability: input.reliability,
                capacityPerTrain: input.capacityPerTrain,
                reservedHourlySeatCapacityPerDirection: hourlySeats,
                effectiveDeparturesPerHour: input.effectiveDeparturesPerHour,
                effectiveIntermediateDeparturesPerHour:
                    input.effectiveIntermediateDeparturesPerHour,
                isOperating: input.isOperating
            )
        )
    }
}

private nonisolated struct PassengerRunMarketID: Hashable, Comparable, Sendable {
    let slotIndex: Int
    let startIndex: Int
    let endIndex: Int

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.slotIndex != rhs.slotIndex { return lhs.slotIndex < rhs.slotIndex }
        if lhs.startIndex != rhs.startIndex { return lhs.startIndex < rhs.startIndex }
        return lhs.endIndex < rhs.endIndex
    }
}

private nonisolated struct PassengerRunMarketCandidate: Sendable {
    let id: PassengerRunMarketID
    let pair: StationPairKey
    let startCall: PassengerStationCallInput
    let endCall: PassengerStationCallInput

    func uses(segment: Int) -> Bool {
        segment >= id.startIndex && segment < id.endIndex
    }
}

private nonisolated struct PassengerRunMarketContribution: Sendable {
    let slotIndex: Int
    let startCall: PassengerStationCallInput
    let endCall: PassengerStationCallInput
    let scheduledDeparturesPerHour: Double
    let effectiveDeparturesPerHour: Double
    let reservedHourlySeats: Double
}

private nonisolated struct PassengerCapacityPhases: Sendable {
    let peakCapacity: Double
    let directPeakDemand: Double
    let directPeakCarried: Double
    let residualPeak: Double
    let residualOffPeak: Double
}

private nonisolated struct ConnectingMarketKey: Hashable, Comparable, Sendable {
    let stationPair: StationPairKey

    init?(firstCRS: String, secondCRS: String) {
        guard let stationPair = StationPairKey(
            firstCRS: firstCRS,
            secondCRS: secondCRS
        ) else { return nil }
        self.stationPair = stationPair
    }

    var originCRS: String { stationPair.firstCRS }
    var destinationCRS: String { stationPair.secondCRS }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.stationPair < rhs.stationPair
    }
}

private nonisolated struct ConnectingJourneyCandidate: Sendable {
    let market: ConnectingMarketKey
    let interchangeCRS: String
    let firstPair: StationPairKey
    let secondPair: StationPairKey
    let totalDistanceKilometres: Double
    let potentialDailyJourneys: Int
    let attractedDailyJourneys: Int
    let inVehicleJourneyMinutes: Double
    let averageWaitMinutes: Double
    let generalizedJourneyMinutes: Double
    let combinedReliability: Double
    let requestedPeak: Double
    let requestedOffPeak: Double

    var servicePairs: [StationPairKey] { [firstPair, secondPair].sorted() }

    func uses(_ pair: StationPairKey) -> Bool {
        firstPair == pair || secondPair == pair
    }

    /// Lowest generalized time wins. The remaining comparisons are stable semantic tiebreakers,
    /// never array position or UUID ordering.
    func precedes(_ other: Self) -> Bool {
        if generalizedJourneyMinutes != other.generalizedJourneyMinutes {
            return generalizedJourneyMinutes < other.generalizedJourneyMinutes
        }
        if combinedReliability != other.combinedReliability {
            return combinedReliability > other.combinedReliability
        }
        if totalDistanceKilometres != other.totalDistanceKilometres {
            return totalDistanceKilometres < other.totalDistanceKilometres
        }
        if interchangeCRS != other.interchangeCRS {
            return interchangeCRS < other.interchangeCRS
        }
        if firstPair != other.firstPair { return firstPair < other.firstPair }
        return secondPair < other.secondPair
    }
}

private nonisolated struct ConnectingPassengerAllocation: Sendable {
    let snapshots: [PassengerConnectingJourneySnapshot]
    let linesByID: [UUID: PassengerLineSnapshot]

    static let empty = Self(snapshots: [], linesByID: [:])
}
