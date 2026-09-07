import Foundation

/// Deterministic tuning for the aggregate platform-throughput model.
///
/// A train uses one platform call when it arrives and another when it departs. Four calls per
/// platform per hour therefore allow one platform to sustain a half-hourly service in each
/// direction without changing the passenger simulation's established baseline.
nonisolated struct StationCapacityConfiguration: Equatable, Sendable {
    let trainCallsPerPlatformPerHour: Double

    init(trainCallsPerPlatformPerHour: Double = 4) {
        self.trainCallsPerPlatformPerHour = trainCallsPerPlatformPerHour.isFinite
            && trainCallsPerPlatformPerHour > 0
            ? trainCallsPerPlatformPerHour
            : 4
    }

    static let poc = StationCapacityConfiguration()
}

/// One independently scheduled service path competing for platform throughput.
///
/// Call lists may use different terminals on the same retained infrastructure. The slot index is
/// stable presentation/domain identity; it also lets the passenger model consume the delivered
/// frequency for the corresponding train path.
nonisolated struct StationCapacityServiceRunInput: Equatable, Sendable {
    let slotIndex: Int
    let stationCRSs: [String]
    let scheduledDeparturesPerHour: Double

    init(
        slotIndex: Int,
        stationCRSs: [String],
        scheduledDeparturesPerHour: Double = 1
    ) {
        self.slotIndex = slotIndex
        self.stationCRSs = stationCRSs.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        self.scheduledDeparturesPerHour = scheduledDeparturesPerHour
    }
}

nonisolated struct StationCapacityLineInput: Identifiable, Equatable, Sendable {
    let id: UUID
    let originCRS: String
    let destinationCRS: String
    /// Ordered selected stations, including both endpoints.
    let stationCRSs: [String]
    let scheduledDeparturesPerHour: Double
    /// Local departures that actually call at intermediate stations.
    let scheduledIntermediateDeparturesPerHour: Double
    /// Exact active train paths. Nil preserves the established aggregate pattern model.
    let serviceRuns: [StationCapacityServiceRunInput]?
    let isOperating: Bool

    init(
        id: UUID,
        originCRS: String,
        destinationCRS: String,
        stationCRSs: [String]? = nil,
        scheduledDeparturesPerHour: Double,
        scheduledIntermediateDeparturesPerHour: Double? = nil,
        serviceRuns: [StationCapacityServiceRunInput]? = nil,
        isOperating: Bool = true
    ) {
        self.id = id
        self.originCRS = Self.normalizedCRS(originCRS)
        self.destinationCRS = Self.normalizedCRS(destinationCRS)
        self.stationCRSs = Self.validatedStationCRSs(
            stationCRSs,
            originCRS: self.originCRS,
            destinationCRS: self.destinationCRS
        )
        self.scheduledDeparturesPerHour = scheduledDeparturesPerHour
        self.scheduledIntermediateDeparturesPerHour =
            scheduledIntermediateDeparturesPerHour ?? scheduledDeparturesPerHour
        self.serviceRuns = serviceRuns
        self.isOperating = isOperating
    }

    init(
        id: UUID,
        originCRS: String,
        destinationCRS: String,
        frequency: ServiceFrequency,
        stationCRSs: [String]? = nil,
        servicePattern: ServicePattern = .local,
        serviceRuns: [StationCapacityServiceRunInput]? = nil,
        isOperating: Bool = true
    ) {
        let intermediateDepartures: Double
        switch servicePattern {
        case .local:
            intermediateDepartures = Double(frequency.departuresPerHour)
        case .express:
            intermediateDepartures = 0
        case .balanced:
            intermediateDepartures = Double((frequency.visibleTrainCount + 1) / 2)
        }
        self.init(
            id: id,
            originCRS: originCRS,
            destinationCRS: destinationCRS,
            stationCRSs: stationCRSs,
            scheduledDeparturesPerHour: Double(frequency.departuresPerHour),
            scheduledIntermediateDeparturesPerHour: intermediateDepartures,
            serviceRuns: serviceRuns,
            isOperating: isOperating
        )
    }

    private static func normalizedCRS(_ crs: String) -> String {
        crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func validatedStationCRSs(
        _ rawCRSs: [String]?,
        originCRS: String,
        destinationCRS: String
    ) -> [String] {
        let fallback = [originCRS, destinationCRS]
        guard let rawCRSs, rawCRSs.count >= 2 else { return fallback }
        let normalized = rawCRSs.map(normalizedCRS)
        guard normalized.first == originCRS,
              normalized.last == destinationCRS,
              !normalized.contains(where: \.isEmpty),
              Set(normalized).count == normalized.count else { return fallback }
        return normalized
    }
}

nonisolated struct StationCapacityLineSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let scheduledDeparturesPerHour: Double
    let effectiveDeparturesPerHour: Double
    let scheduledIntermediateDeparturesPerHour: Double
    let effectiveIntermediateDeparturesPerHour: Double
    /// Delivered one-way departures for each explicit service slot. Empty for legacy inputs.
    let effectiveDeparturesBySlot: [Int: Double]
    /// Stations that impose the line's lowest local throughput factor, in lexical CRS order.
    let limitingStationCRSs: [String]
    let isOperating: Bool

    var throughputRatio: Double {
        guard isOperating, scheduledDeparturesPerHour > 0 else { return 0 }
        return min(max(effectiveDeparturesPerHour / scheduledDeparturesPerHour, 0), 1)
    }

    var isPlatformConstrained: Bool {
        isOperating && effectiveDeparturesPerHour + 0.000_000_001
            < scheduledDeparturesPerHour
    }

    func effectiveDeparturesPerHour(forSlot slotIndex: Int) -> Double? {
        effectiveDeparturesBySlot[slotIndex]
    }
}

nonisolated struct StationCapacityStationSnapshot: Identifiable, Equatable, Sendable {
    let stationCRS: String
    /// Nil means no capacity record was supplied, which deliberately preserves legacy behaviour.
    let platformCount: Int?
    let scheduledTrainCallsPerHour: Double
    /// Nil represents unbounded legacy throughput for an absent capacity record.
    let trainCallCapacityPerHour: Double?
    let effectiveTrainCallsPerHour: Double

    var id: String { stationCRS }

    var throughputFactor: Double {
        guard scheduledTrainCallsPerHour > 0 else { return 1 }
        guard let trainCallCapacityPerHour else { return 1 }
        guard trainCallCapacityPerHour > 0 else { return 0 }
        return min(max(trainCallCapacityPerHour / scheduledTrainCallsPerHour, 0), 1)
    }

    var capacityPressure: Double {
        guard scheduledTrainCallsPerHour > 0 else { return 0 }
        guard let trainCallCapacityPerHour else { return 0 }
        guard trainCallCapacityPerHour > 0 else { return Double.greatestFiniteMagnitude }
        let pressure = scheduledTrainCallsPerHour / trainCallCapacityPerHour
        return pressure.isFinite
            ? max(pressure, 0)
            : Double.greatestFiniteMagnitude
    }

    var utilization: Double {
        guard let trainCallCapacityPerHour, trainCallCapacityPerHour > 0 else {
            return effectiveTrainCallsPerHour > 0 ? 1 : 0
        }
        return min(max(effectiveTrainCallsPerHour / trainCallCapacityPerHour, 0), 1)
    }

    var blockedTrainCallsPerHour: Double {
        max(scheduledTrainCallsPerHour - effectiveTrainCallsPerHour, 0)
    }

    var isPlatformConstrained: Bool {
        trainCallCapacityPerHour != nil && throughputFactor < 1
    }
}

nonisolated struct NetworkStationCapacitySnapshot: Equatable, Sendable {
    let linesByID: [UUID: StationCapacityLineSnapshot]
    let stationsByCRS: [String: StationCapacityStationSnapshot]

    static let empty = NetworkStationCapacitySnapshot(linesByID: [:], stationsByCRS: [:])

    var lineSnapshots: [StationCapacityLineSnapshot] {
        linesByID.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    var stationSnapshots: [StationCapacityStationSnapshot] {
        stationsByCRS.values.sorted { $0.stationCRS < $1.stationCRS }
    }

    var constrainedStationCount: Int {
        stationsByCRS.values.reduce(0) { $0 + ($1.isPlatformConstrained ? 1 : 0) }
    }

    func line(for id: UUID) -> StationCapacityLineSnapshot? { linesByID[id] }

    func station(forCRS crs: String) -> StationCapacityStationSnapshot? {
        stationsByCRS[Self.normalizedCRS(crs)]
    }

    private static func normalizedCRS(_ crs: String) -> String {
        crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

/// A steady-state platform model for endpoint and intermediate station calls. It intentionally
/// does not assign individual trains to named platforms.
///
/// Capacity is shared using deterministic progressive filling. Every calling flow initially
/// receives the same proportion of its requested timetable. A mixed local/express service has
/// separate flows so an intermediate platform can constrain its local trains without blocking
/// express trains that skip the station. When another station prevents a flow from using its
/// share, the remaining capacity is offered to flows that can still use it. This is max-min fair,
/// independent of UUID/input ordering, and avoids leaving a busy hub artificially under-used.
nonisolated struct StationCapacitySimulation: Sendable {
    let configuration: StationCapacityConfiguration

    init(configuration: StationCapacityConfiguration = .poc) {
        self.configuration = configuration
    }

    func evaluate(
        lines: [StationCapacityLineInput],
        platformCountsByStationCRS rawPlatformCounts: [String: Int]
    ) -> NetworkStationCapacitySnapshot {
        let platformCounts = normalizedPlatformCounts(rawPlatformCounts)
        let canonicalLines = canonicalizedLines(lines)
        guard !canonicalLines.isEmpty || !platformCounts.isEmpty else { return .empty }

        var requestedCallsByCRS = [String: Double]()
        for line in canonicalLines where line.isValidOperatingService {
            if line.serviceRuns != nil {
                for flow in line.capacityFlows {
                    for crs in flow.stationCRSs {
                        requestedCallsByCRS[crs, default: 0] = boundedSum(
                            requestedCallsByCRS[crs, default: 0],
                            boundedProduct(flow.scheduledDeparturesPerHour, 2)
                        )
                    }
                }
            } else {
                for crs in line.stationCRSs {
                    let calls = boundedProduct(line.scheduledDepartures(at: crs), 2)
                    requestedCallsByCRS[crs, default: 0] = boundedSum(
                        requestedCallsByCRS[crs, default: 0],
                        calls
                    )
                }
            }
        }

        let stationCRSs = Set(platformCounts.keys)
            .union(requestedCallsByCRS.keys)
            .sorted()
        let fairAllocation = fairThroughputAllocation(
            lines: canonicalLines,
            platformCountsByStationCRS: platformCounts
        )

        var linesByID = [UUID: StationCapacityLineSnapshot](
            minimumCapacity: canonicalLines.count
        )
        var effectiveCallsByCRS = [String: Double]()
        for line in canonicalLines {
            let scheduled = line.sanitizedScheduledDeparturesPerHour
            guard line.isValidOperatingService else {
                linesByID[line.id] = StationCapacityLineSnapshot(
                    id: line.id,
                    scheduledDeparturesPerHour: scheduled,
                    effectiveDeparturesPerHour: 0,
                    scheduledIntermediateDeparturesPerHour:
                        line.sanitizedScheduledIntermediateDeparturesPerHour,
                    effectiveIntermediateDeparturesPerHour: 0,
                    effectiveDeparturesBySlot: Dictionary(
                        uniqueKeysWithValues: (line.serviceRuns ?? []).map {
                            ($0.slotIndex, 0)
                        }
                    ),
                    limitingStationCRSs: [],
                    isOperating: false
                )
                continue
            }

            let effective = min(
                max(fairAllocation.departuresByLineID[line.id, default: 0], 0),
                scheduled
            )
            let effectiveIntermediate = min(
                max(
                    fairAllocation.intermediateDeparturesByLineID[line.id, default: 0],
                    0
                ),
                line.sanitizedScheduledIntermediateDeparturesPerHour
            )
            let limitingCRSs = fairAllocation
                .limitingStationCRSsByLineID[line.id, default: []]
            linesByID[line.id] = StationCapacityLineSnapshot(
                id: line.id,
                scheduledDeparturesPerHour: scheduled,
                effectiveDeparturesPerHour: effective,
                scheduledIntermediateDeparturesPerHour:
                    line.sanitizedScheduledIntermediateDeparturesPerHour,
                effectiveIntermediateDeparturesPerHour: effectiveIntermediate,
                effectiveDeparturesBySlot: fairAllocation
                    .effectiveDeparturesBySlotByLineID[line.id, default: [:]],
                limitingStationCRSs: limitingCRSs,
                isOperating: true
            )

            if line.serviceRuns != nil {
                for flow in line.capacityFlows {
                    let flowEffective = fairAllocation
                        .departuresByFlowID[flow.id, default: 0]
                    for crs in flow.stationCRSs {
                        effectiveCallsByCRS[crs, default: 0] = boundedSum(
                            effectiveCallsByCRS[crs, default: 0],
                            boundedProduct(flowEffective, 2)
                        )
                    }
                }
            } else {
                for (index, crs) in line.stationCRSs.enumerated() {
                    let effectiveAtStation = index == line.stationCRSs.startIndex
                        || index == line.stationCRSs.index(before: line.stationCRSs.endIndex)
                        ? effective
                        : effectiveIntermediate
                    let calls = boundedProduct(effectiveAtStation, 2)
                    effectiveCallsByCRS[crs, default: 0] = boundedSum(
                        effectiveCallsByCRS[crs, default: 0],
                        calls
                    )
                }
            }
        }

        var stationsByCRS = [String: StationCapacityStationSnapshot](
            minimumCapacity: stationCRSs.count
        )
        for crs in stationCRSs {
            let platformCount = platformCounts[crs]
            let capacity = platformCount.map(hourlyCallCapacity)
            let requested = requestedCallsByCRS[crs, default: 0]
            let effective = min(
                effectiveCallsByCRS[crs, default: 0],
                capacity ?? Double.greatestFiniteMagnitude
            )
            stationsByCRS[crs] = StationCapacityStationSnapshot(
                stationCRS: crs,
                platformCount: platformCount,
                scheduledTrainCallsPerHour: requested,
                trainCallCapacityPerHour: capacity,
                effectiveTrainCallsPerHour: effective
            )
        }

        return NetworkStationCapacitySnapshot(
            linesByID: linesByID,
            stationsByCRS: stationsByCRS
        )
    }

    private func normalizedPlatformCounts(_ counts: [String: Int]) -> [String: Int] {
        var normalized = [String: Int]()
        for (rawCRS, rawCount) in counts.sorted(by: { $0.key < $1.key }) {
            let crs = CanonicalLine.normalizedCRS(rawCRS)
            guard !crs.isEmpty else { continue }
            normalized[crs] = max(normalized[crs, default: 0], max(rawCount, 0))
        }
        return normalized
    }

    private func canonicalizedLines(_ inputs: [StationCapacityLineInput]) -> [CanonicalLine] {
        var byID = [UUID: CanonicalLine]()
        for input in inputs {
            let candidate = CanonicalLine(input)
            if let existing = byID[input.id], !candidate.precedes(existing) { continue }
            byID[input.id] = candidate
        }
        return byID.values.sorted(by: { $0.precedes($1) })
    }

    private func fairThroughputAllocation(
        lines: [CanonicalLine],
        platformCountsByStationCRS platformCounts: [String: Int]
    ) -> FairThroughputAllocation {
        let operatingLines = lines.filter(\.isValidOperatingService)
        guard !operatingLines.isEmpty else { return .empty }
        let flows = operatingLines.flatMap(\.capacityFlows)
        guard !flows.isEmpty else { return .empty }

        var ratiosByFlowID = Dictionary(
            uniqueKeysWithValues: flows.map { ($0.id, 0.0) }
        )
        var activeFlowIDs = Set(flows.map(\.id))
        var limitingStationsByFlowID = [CapacityFlowID: Set<String>]()
        let epsilon = 0.000_000_001

        // Each pass saturates at least one station or completes at least one flow, so the
        // bounded loop normally needs no more than the number of flows plus stations.
        let maximumPasses = max(flows.count + platformCounts.count + 1, 1)
        for _ in 0..<maximumPasses where !activeFlowIDs.isEmpty {
            var delta = activeFlowIDs.reduce(1.0) { current, flowID in
                min(current, max(1 - ratiosByFlowID[flowID, default: 0], 0))
            }
            var stationDeltaByCRS = [String: Double]()

            for crs in platformCounts.keys.sorted() {
                let activeIncidentLines = flows.filter {
                    activeFlowIDs.contains($0.id) && $0.isIncident(to: crs)
                }
                guard !activeIncidentLines.isEmpty else { continue }

                let usedCalls = flows.reduce(0.0) { total, line in
                    guard line.isIncident(to: crs) else { return total }
                    let departures = boundedProduct(
                        line.scheduledDeparturesPerHour,
                        ratiosByFlowID[line.id, default: 0]
                    )
                    return boundedSum(total, boundedProduct(departures, 2))
                }
                let capacity = hourlyCallCapacity(platformCounts[crs, default: 0])
                let remainingCalls = max(capacity - min(usedCalls, capacity), 0)
                let activeCallsPerRatio = activeIncidentLines.reduce(0.0) { total, line in
                    boundedSum(
                        total,
                        boundedProduct(line.scheduledDeparturesPerHour, 2)
                    )
                }
                guard activeCallsPerRatio > 0 else { continue }
                let stationDelta = min(
                    max(remainingCalls / activeCallsPerRatio, 0),
                    1
                )
                stationDeltaByCRS[crs] = stationDelta
                delta = min(delta, stationDelta)
            }

            delta = delta.isFinite ? max(delta, 0) : 0
            for flowID in activeFlowIDs.sorted(by: { $0.precedes($1) }) {
                ratiosByFlowID[flowID] = min(
                    ratiosByFlowID[flowID, default: 0] + delta,
                    1
                )
            }

            var completedFlowIDs = Set<CapacityFlowID>()
            for line in flows where activeFlowIDs.contains(line.id) {
                let ratio = ratiosByFlowID[line.id, default: 0]
                if ratio >= 1 - epsilon {
                    ratiosByFlowID[line.id] = 1
                    completedFlowIDs.insert(line.id)
                    continue
                }

                let saturatedStations = line.stationCRSs
                    .filter { crs in
                        guard let stationDelta = stationDeltaByCRS[crs] else { return false }
                        return stationDelta <= delta + epsilon
                }
                if !saturatedStations.isEmpty {
                    limitingStationsByFlowID[line.id, default: []]
                        .formUnion(saturatedStations)
                    completedFlowIDs.insert(line.id)
                }
            }

            // Defensive progress guarantee for adversarial floating-point inputs. Gameplay values
            // always complete through one of the branches above.
            if completedFlowIDs.isEmpty {
                for flowID in activeFlowIDs {
                    ratiosByFlowID[flowID] = 1
                    completedFlowIDs.insert(flowID)
                }
            }
            activeFlowIDs.subtract(completedFlowIDs)
        }

        var departuresByLineID = [UUID: Double](minimumCapacity: operatingLines.count)
        var intermediateDeparturesByLineID = [UUID: Double](
            minimumCapacity: operatingLines.count
        )
        var departuresByFlowID = [CapacityFlowID: Double](minimumCapacity: flows.count)
        var effectiveDeparturesBySlotByLineID = [UUID: [Int: Double]]()
        var limitingStationsByCanonicalLineID = [UUID: Set<String>]()
        for flow in flows {
            let departures = min(
                boundedProduct(
                    flow.scheduledDeparturesPerHour,
                    ratiosByFlowID[flow.id, default: 0]
                ),
                flow.scheduledDeparturesPerHour
            )
            departuresByFlowID[flow.id] = departures
            departuresByLineID[flow.id.lineID, default: 0] = boundedSum(
                departuresByLineID[flow.id.lineID, default: 0],
                departures
            )
            if flow.servesParentIntermediateStation {
                intermediateDeparturesByLineID[flow.id.lineID, default: 0] = boundedSum(
                    intermediateDeparturesByLineID[flow.id.lineID, default: 0],
                    departures
                )
            }
            if let slotIndex = flow.id.kind.slotIndex {
                effectiveDeparturesBySlotByLineID[flow.id.lineID, default: [:]][slotIndex]
                    = departures
            }
            limitingStationsByCanonicalLineID[flow.id.lineID, default: []]
                .formUnion(limitingStationsByFlowID[flow.id, default: []])
        }
        let limitingStationCRSsByLineID = Dictionary(uniqueKeysWithValues:
            operatingLines.map { line in
                (line.id, Array(limitingStationsByCanonicalLineID[line.id, default: []]).sorted())
            }
        )
        return FairThroughputAllocation(
            departuresByLineID: departuresByLineID,
            intermediateDeparturesByLineID: intermediateDeparturesByLineID,
            departuresByFlowID: departuresByFlowID,
            effectiveDeparturesBySlotByLineID: effectiveDeparturesBySlotByLineID,
            limitingStationCRSsByLineID: limitingStationCRSsByLineID
        )
    }

    private func hourlyCallCapacity(_ platformCount: Int) -> Double {
        boundedProduct(
            Double(max(platformCount, 0)),
            configuration.trainCallsPerPlatformPerHour
        )
    }

    private func boundedProduct(_ lhs: Double, _ rhs: Double) -> Double {
        guard lhs.isFinite, rhs.isFinite, lhs > 0, rhs > 0 else { return 0 }
        guard lhs <= Double.greatestFiniteMagnitude / rhs else {
            return Double.greatestFiniteMagnitude
        }
        return lhs * rhs
    }

    private func boundedSum(_ lhs: Double, _ rhs: Double) -> Double {
        let lhs = lhs.isFinite && lhs > 0 ? lhs : 0
        let rhs = rhs.isFinite && rhs > 0 ? rhs : 0
        guard lhs <= Double.greatestFiniteMagnitude - rhs else {
            return Double.greatestFiniteMagnitude
        }
        return lhs + rhs
    }
}

private nonisolated struct CanonicalLine: Equatable, Sendable {
    let id: UUID
    let originCRS: String
    let destinationCRS: String
    let stationCRSs: [String]
    let scheduledDeparturesPerHour: Double
    let scheduledIntermediateDeparturesPerHour: Double
    let serviceRuns: [CanonicalServiceRun]?
    let isOperating: Bool

    init(_ input: StationCapacityLineInput) {
        id = input.id
        originCRS = Self.normalizedCRS(input.originCRS)
        destinationCRS = Self.normalizedCRS(input.destinationCRS)
        let canonicalStationCRSs = input.stationCRSs.map(Self.normalizedCRS)
        stationCRSs = canonicalStationCRSs
        scheduledDeparturesPerHour = input.scheduledDeparturesPerHour
        scheduledIntermediateDeparturesPerHour = input.scheduledIntermediateDeparturesPerHour
        serviceRuns = input.serviceRuns.map {
            Self.canonicalServiceRuns($0, parentStationCRSs: canonicalStationCRSs)
        }
        isOperating = input.isOperating
    }

    var sanitizedScheduledDeparturesPerHour: Double {
        if let serviceRuns {
            return serviceRuns.reduce(0) { total, run in
                Self.boundedSum(total, run.scheduledDeparturesPerHour)
            }
        }
        return scheduledDeparturesPerHour.isFinite && scheduledDeparturesPerHour > 0
            ? scheduledDeparturesPerHour
            : 0
    }

    var sanitizedScheduledIntermediateDeparturesPerHour: Double {
        if let serviceRuns {
            let intermediateCRSs = Set(stationCRSs.dropFirst().dropLast())
            return serviceRuns.reduce(0) { total, run in
                guard run.stationCRSs.contains(where: intermediateCRSs.contains) else {
                    return total
                }
                return Self.boundedSum(total, run.scheduledDeparturesPerHour)
            }
        }
        guard stationCRSs.count > 2,
              scheduledIntermediateDeparturesPerHour.isFinite else {
            return sanitizedScheduledDeparturesPerHour
        }
        return min(
            max(scheduledIntermediateDeparturesPerHour, 0),
            sanitizedScheduledDeparturesPerHour
        )
    }

    var isValidOperatingService: Bool {
        isOperating
            && !originCRS.isEmpty
            && !destinationCRS.isEmpty
            && originCRS != destinationCRS
            && stationCRSs.count >= 2
            && sanitizedScheduledDeparturesPerHour > 0
    }

    func isIncident(to stationCRS: String) -> Bool {
        scheduledDepartures(at: stationCRS) > 0
    }

    func scheduledDepartures(at stationCRS: String) -> Double {
        guard let index = stationCRSs.firstIndex(of: stationCRS) else { return 0 }
        return index == stationCRSs.startIndex || index == stationCRSs.index(before: stationCRSs.endIndex)
            ? sanitizedScheduledDeparturesPerHour
            : sanitizedScheduledIntermediateDeparturesPerHour
    }

    var capacityFlows: [CanonicalCapacityFlow] {
        guard isValidOperatingService else { return [] }

        if let serviceRuns {
            let intermediateCRSs = Set(stationCRSs.dropFirst().dropLast())
            return serviceRuns.map { run in
                CanonicalCapacityFlow(
                    id: CapacityFlowID(lineID: id, kind: .serviceRun(run.slotIndex)),
                    stationCRSs: run.stationCRSs,
                    scheduledDeparturesPerHour: run.scheduledDeparturesPerHour,
                    servesParentIntermediateStation: run.stationCRSs.contains(
                        where: intermediateCRSs.contains
                    )
                )
            }
        }

        let total = sanitizedScheduledDeparturesPerHour
        guard stationCRSs.count > 2 else {
            return [CanonicalCapacityFlow(
                id: CapacityFlowID(lineID: id, kind: .legacyAllStations),
                stationCRSs: stationCRSs,
                scheduledDeparturesPerHour: total,
                servesParentIntermediateStation: true
            )]
        }

        let local = sanitizedScheduledIntermediateDeparturesPerHour
        var flows = [CanonicalCapacityFlow]()
        if local > 0 {
            flows.append(CanonicalCapacityFlow(
                id: CapacityFlowID(lineID: id, kind: .legacyAllStations),
                stationCRSs: stationCRSs,
                scheduledDeparturesPerHour: local,
                servesParentIntermediateStation: true
            ))
        }
        let express = max(total - local, 0)
        if express > 0 {
            flows.append(CanonicalCapacityFlow(
                id: CapacityFlowID(lineID: id, kind: .legacyEndpointsOnly),
                stationCRSs: [
                    stationCRSs[stationCRSs.startIndex],
                    stationCRSs[stationCRSs.index(before: stationCRSs.endIndex)],
                ],
                scheduledDeparturesPerHour: express,
                servesParentIntermediateStation: false
            ))
        }
        return flows
    }

    func precedes(_ other: Self) -> Bool {
        if id != other.id { return id.uuidString < other.id.uuidString }
        if originCRS != other.originCRS { return originCRS < other.originCRS }
        if destinationCRS != other.destinationCRS { return destinationCRS < other.destinationCRS }
        if stationCRSs != other.stationCRSs {
            return stationCRSs.lexicographicallyPrecedes(other.stationCRSs)
        }
        let lhsDepartures = sanitizedScheduledDeparturesPerHour
        let rhsDepartures = other.sanitizedScheduledDeparturesPerHour
        if lhsDepartures != rhsDepartures { return lhsDepartures < rhsDepartures }
        let lhsIntermediate = sanitizedScheduledIntermediateDeparturesPerHour
        let rhsIntermediate = other.sanitizedScheduledIntermediateDeparturesPerHour
        if lhsIntermediate != rhsIntermediate { return lhsIntermediate < rhsIntermediate }
        let lhsRuns = serviceRuns ?? []
        let rhsRuns = other.serviceRuns ?? []
        if (serviceRuns == nil) != (other.serviceRuns == nil) { return serviceRuns == nil }
        if lhsRuns != rhsRuns { return lhsRuns.lexicographicallyPrecedes(rhsRuns) }
        if isOperating != other.isOperating { return !isOperating }
        return false
    }

    static func normalizedCRS(_ crs: String) -> String {
        crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func canonicalServiceRuns(
        _ rawRuns: [StationCapacityServiceRunInput],
        parentStationCRSs: [String]
    ) -> [CanonicalServiceRun] {
        var runsBySlot = [Int: CanonicalServiceRun]()
        for rawRun in rawRuns where rawRun.slotIndex >= 0 {
            let candidate = CanonicalServiceRun(rawRun)
            guard candidate.isValid else { continue }
            let parentIndices = candidate.stationCRSs.compactMap {
                parentStationCRSs.firstIndex(of: $0)
            }
            guard parentIndices.count == candidate.stationCRSs.count else { continue }
            let isIncreasing = zip(parentIndices, parentIndices.dropFirst()).allSatisfy(<)
            let isDecreasing = zip(parentIndices, parentIndices.dropFirst()).allSatisfy(>)
            guard isIncreasing || isDecreasing else { continue }
            if let existing = runsBySlot[candidate.slotIndex],
               !candidate.precedes(existing) {
                continue
            }
            runsBySlot[candidate.slotIndex] = candidate
        }
        return runsBySlot.values.sorted { $0.slotIndex < $1.slotIndex }
    }

    private static func boundedSum(_ lhs: Double, _ rhs: Double) -> Double {
        let lhs = lhs.isFinite && lhs > 0 ? lhs : 0
        let rhs = rhs.isFinite && rhs > 0 ? rhs : 0
        guard lhs <= Double.greatestFiniteMagnitude - rhs else {
            return Double.greatestFiniteMagnitude
        }
        return lhs + rhs
    }
}

private nonisolated struct CanonicalServiceRun: Equatable, Comparable, Sendable {
    let slotIndex: Int
    let stationCRSs: [String]
    let scheduledDeparturesPerHour: Double

    init(_ input: StationCapacityServiceRunInput) {
        slotIndex = input.slotIndex
        stationCRSs = input.stationCRSs.map(CanonicalLine.normalizedCRS)
        scheduledDeparturesPerHour = input.scheduledDeparturesPerHour.isFinite
            && input.scheduledDeparturesPerHour > 0
            ? input.scheduledDeparturesPerHour
            : 0
    }

    var isValid: Bool {
        slotIndex >= 0
            && stationCRSs.count >= 2
            && stationCRSs.allSatisfy { !$0.isEmpty }
            && Set(stationCRSs).count == stationCRSs.count
            && scheduledDeparturesPerHour > 0
    }

    func precedes(_ other: Self) -> Bool { self < other }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.slotIndex != rhs.slotIndex { return lhs.slotIndex < rhs.slotIndex }
        if lhs.stationCRSs != rhs.stationCRSs {
            return lhs.stationCRSs.lexicographicallyPrecedes(rhs.stationCRSs)
        }
        return lhs.scheduledDeparturesPerHour < rhs.scheduledDeparturesPerHour
    }
}

private nonisolated enum CapacityFlowKind: Hashable, Sendable {
    case legacyAllStations
    case legacyEndpointsOnly
    case serviceRun(Int)

    var slotIndex: Int? {
        guard case let .serviceRun(slotIndex) = self else { return nil }
        return slotIndex
    }

    func precedes(_ other: Self) -> Bool {
        switch (self, other) {
        case (.legacyAllStations, .legacyAllStations),
             (.legacyEndpointsOnly, .legacyEndpointsOnly):
            return false
        case (.legacyAllStations, _):
            return true
        case (_, .legacyAllStations):
            return false
        case (.legacyEndpointsOnly, _):
            return true
        case (_, .legacyEndpointsOnly):
            return false
        case let (.serviceRun(lhs), .serviceRun(rhs)):
            return lhs < rhs
        }
    }
}

private nonisolated struct CapacityFlowID: Hashable, Sendable {
    let lineID: UUID
    let kind: CapacityFlowKind

    func precedes(_ other: Self) -> Bool {
        if lineID != other.lineID { return lineID.uuidString < other.lineID.uuidString }
        return kind.precedes(other.kind)
    }
}

private nonisolated struct CanonicalCapacityFlow: Sendable {
    let id: CapacityFlowID
    let stationCRSs: [String]
    let scheduledDeparturesPerHour: Double
    let servesParentIntermediateStation: Bool

    func isIncident(to stationCRS: String) -> Bool {
        stationCRSs.contains(stationCRS)
    }
}

private nonisolated struct FairThroughputAllocation: Sendable {
    let departuresByLineID: [UUID: Double]
    let intermediateDeparturesByLineID: [UUID: Double]
    let departuresByFlowID: [CapacityFlowID: Double]
    let effectiveDeparturesBySlotByLineID: [UUID: [Int: Double]]
    let limitingStationCRSsByLineID: [UUID: [String]]

    static let empty = Self(
        departuresByLineID: [:],
        intermediateDeparturesByLineID: [:],
        departuresByFlowID: [:],
        effectiveDeparturesBySlotByLineID: [:],
        limitingStationCRSsByLineID: [:]
    )
}
