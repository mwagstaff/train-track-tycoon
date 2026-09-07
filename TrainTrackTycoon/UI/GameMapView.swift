import CoreLocation
import MapKit
import SwiftUI

/// A presentation-only request to frame one service on the map.
///
/// The sequence makes repeated taps on the same service observable without moving transient
/// camera state into `GameSession` or the persisted railway model.
nonisolated struct LineMapFocusRequest: Equatable, Sendable {
    let lineID: UUID
    let sequence: UInt64
}

struct GameMapView: View {
    @Bindable var session: GameSession
    let showsHappinessHeatmap: Bool
    let allowsJourneyFeedback: Bool
    let lineFocusRequest: LineMapFocusRequest?
    let onVisibleTrainArrival: (_ soundsHorn: Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Namespace private var mapScope

    @State private var cameraPosition: MapCameraPosition = .region(Self.initialRegion)
    @State private var cameraHeading = 0.0
    @State private var currentCamera: MapCamera?
    @State private var visibleMapRect: MKMapRect?
    @State private var trainMapDetailLevel: TrainMapDetailLevel = .compact
    @State private var renderingDetailLevel: RailwayMapRenderingDetailLevel = .regional
    @State private var renderedStations: [Station] = []
    @State private var renderedLineIDs: Set<UUID> = []
    @State private var potentialMapAdditionLineIDsByStationCRS: [String: [UUID]] = [:]
    @State private var potentialMapAdditionPreflight: MapStationAdditionPreflight?
    @State private var lastStationRenderMapRect: MKMapRect?
    @State private var builtStationStyleIndices: [String: Int] = [:]
    @State private var renderingCache = RailwayMapRenderingCache()
    @State private var activeArrivalRewards: [TrainArrivalRewardPresentation] = []
    @State private var lastHandledPresentationEventSequence: UInt64 = 0
    @State private var hasAppliedInitialNetworkFrame = false

    init(
        session: GameSession,
        showsHappinessHeatmap: Bool,
        allowsJourneyFeedback: Bool = true,
        lineFocusRequest: LineMapFocusRequest? = nil,
        onVisibleTrainArrival: @escaping (_ soundsHorn: Bool) -> Void = { _ in }
    ) {
        self.session = session
        self.showsHappinessHeatmap = showsHappinessHeatmap
        self.allowsJourneyFeedback = allowsJourneyFeedback
        self.lineFocusRequest = lineFocusRequest
        self.onVisibleTrainArrival = onVisibleTrainArrival
    }

    var body: some View {
        MapReader { mapProxy in
            Map(position: $cameraPosition, interactionModes: .all, scope: mapScope) {
                happinessHeatmapContent
                routeContent
                previewContent
                trainContent
                stationVisualContent
                arrivalRewardContent
            }
        .mapStyle(
            .standard(
                elevation: .flat,
                emphasis: .muted,
                pointsOfInterest: .excludingAll,
                showsTraffic: false
            )
        )
        .mapControlVisibility(.hidden)
        // A spatial tap recognizer fails as soon as a finger starts dragging, leaving MapKit's
        // native pan and pinch interactions fluid. Resolving the closest screen-space station
        // also avoids hundreds of duplicate transparent annotations and overlapping Button hit
        // boxes, both of which made dense maps less responsive and less predictable.
        .simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .local)
                .onEnded { value in
                    handleStationMapTap(at: value.location, mapProxy: mapProxy)
                }
        )
        // MapKit continues moving its already-rendered annotations during a gesture. Rebuilding
        // thousands of catalogue candidates for every camera sample only adds heat and latency,
        // so refresh the bounded render set once the gesture or camera animation settles.
        .onMapCameraChange(frequency: .onEnd) { context in
            cameraHeading = context.camera.heading
            currentCamera = context.camera
            visibleMapRect = context.rect
            updateTrainMapDetailLevel(for: context.camera.distance)
            updateRenderingContext(
                visibleMapRect: context.rect,
                cameraDistance: context.camera.distance
            )
        }
        .onChange(of: previewKey) { _, newValue in
            guard newValue != nil,
                  !session.isUpdatingPreviewRoute,
                  let preview = session.preview else { return }
            frame(preview.route.coordinates)
        }
        .onChange(of: lineFocusRequest) { _, request in
            guard let request,
                  let line = session.lines.first(where: { $0.id == request.lineID }) else {
                return
            }
            frame(line.route.coordinates)
        }
        .onChange(of: session.selectedOrigin?.id) { _, _ in
            frameSearchedOriginIfNeeded()
        }
        .onChange(of: stationRenderingContextKey) { _, _ in
            refreshRenderedStations()
        }
        .onChange(of: followSnapshot) { _, newValue in
            guard session.isFollowingSelectedTrain, let newValue else { return }
            follow(newValue.coordinate)
        }
        .onChange(of: cameraPosition.positionedByUser) { _, isPositionedByUser in
            guard isPositionedByUser, session.isFollowingSelectedTrain else { return }
            session.setFollowingSelectedTrain(false)
        }
        .onChange(of: session.latestPresentationEvent?.sequence) { _, _ in
            handleTrainArrivalEvents()
        }
        .onChange(of: allowsJourneyFeedback) { _, isAllowed in
            if !isAllowed {
                activeArrivalRewards.removeAll()
            }
        }
        .onAppear {
            // Presentation events are transient. A newly created map must never replay the tail
            // of an earlier session before the player could have seen it.
            lastHandledPresentationEventSequence =
                session.latestPresentationEvent?.sequence ?? 0
            refreshRenderedStations()
        }
        .task {
            guard !hasAppliedInitialNetworkFrame, !session.lines.isEmpty else { return }
            hasAppliedInitialNetworkFrame = true
            // Restored lines already exist when this view first appears, so no line-count change
            // is emitted. Yield once for MapKit's layout and then frame the saved network once.
            // Later additions and joins retain the player's camera; preview and explicit line
            // focus requests already provide the appropriate scoped framing behavior.
            await Task.yield()
            let networkRect = session.lines.reduce(MKMapRect.null) { partial, line in
                partial.union(renderingCache.framingMapRect(for: line))
            }
            frame(networkRect)
        }
        .task(id: potentialMapAdditionPreflight?.id) {
            guard let request = potentialMapAdditionPreflight else { return }
            let worker = Task.detached(priority: .userInitiated) {
                RailwayMapRenderingPolicy.potentialIntermediateLineIDs(
                    for: request.stations,
                    among: request.lines,
                    maximumServiceCallCount: request.maximumServiceCallCount
                )
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled,
                  potentialMapAdditionPreflight?.id == request.id else { return }
            if potentialMapAdditionLineIDsByStationCRS != result {
                potentialMapAdditionLineIDsByStationCRS = result
            }
        }
        .overlay(alignment: .topTrailing) {
            MapCompass(scope: mapScope)
                .mapControlVisibility(.visible)
                .safeAreaPadding(.top, 68)
                .padding(.trailing, 12)
        }
        .overlay(alignment: .topLeading) {
            if showsHappinessHeatmap, !session.lines.isEmpty {
                HappinessMapLegend()
                    .safeAreaPadding(.top, 70)
                    .padding(.leading, 12)
                    .allowsHitTesting(false)
            }
        }
            .mapScope(mapScope)
            .accessibilityLabel("Great Britain railway map")
        }
    }

    @MapContentBuilder
    private var happinessHeatmapContent: some MapContent {
        if showsHappinessHeatmap, !session.lines.isEmpty {
            ForEach(heatmapStations) { station in
                if let happiness = session.happinessSnapshot(forStationCRS: station.crs) {
                    let color = TycoonTheme.happinessColor(for: happiness.happinessScore)
                    MapCircle(center: station.coordinate, radius: 2_800)
                        .foregroundStyle(color.opacity(0.16))
                        .stroke(
                            color.opacity(differentiateWithoutColor ? 0.78 : 0.46),
                            style: StrokeStyle(
                                lineWidth: differentiateWithoutColor ? 2 : 1,
                                dash: differentiateWithoutColor ? [5, 4] : []
                            )
                        )
                        .mapOverlayLevel(level: .aboveRoads)
                }
            }
        }
    }

    @MapContentBuilder
    private var routeContent: some MapContent {
        ForEach(renderedLines) { rendering in
            let line = rendering.line
            let coordinates = rendering.coordinates
            let routeColor = line.railwayClass == .highSpeed
                ? TycoonTheme.highSpeedViolet
                : TycoonTheme.lineColor(for: line.styleIndex)

            if renderingDetailLevel == .country {
                MapPolyline(coordinates: coordinates)
                    .stroke(
                        routeColor.opacity(0.9),
                        style: StrokeStyle(
                            lineWidth: line.railwayClass == .highSpeed ? 5 : 4,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .mapOverlayLevel(level: .aboveRoads)
            } else if renderingDetailLevel == .regional {
                MapPolyline(coordinates: coordinates)
                    .stroke(
                        Color.primary.opacity(0.7),
                        style: StrokeStyle(
                            lineWidth: line.railwayClass == .highSpeed
                                ? 12
                                : line.trackCapacity == .doubleTrack ? 10 : 8,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .mapOverlayLevel(level: .aboveRoads)
                MapPolyline(coordinates: coordinates)
                    .stroke(
                        routeColor,
                        style: StrokeStyle(
                            lineWidth: line.railwayClass == .highSpeed
                                ? 8
                                : line.trackCapacity == .doubleTrack ? 7 : 5,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .mapOverlayLevel(level: .aboveRoads)
            } else {
                if let operations = session.operationsSnapshot(forLineID: line.id),
                   operations.congestionBand != .flowing {
                    MapPolyline(coordinates: coordinates)
                        .stroke(
                            operations.congestionBand == .congested
                                ? TycoonTheme.construction.opacity(0.64)
                                : Color.orange.opacity(0.48),
                            style: StrokeStyle(
                                lineWidth: operations.congestionBand == .congested ? 18 : 15,
                                lineCap: .round,
                                lineJoin: .round,
                                dash: operations.congestionBand == .congested
                                    ? [3, 7]
                                    : [12, 10]
                            )
                        )
                        .mapOverlayLevel(level: .aboveRoads)
                }

                MapPolyline(coordinates: coordinates)
                    .stroke(
                        Color.primary.opacity(line.railwayClass == .highSpeed ? 0.82 : 0.72),
                        style: StrokeStyle(
                            lineWidth: line.railwayClass == .highSpeed
                                ? 17
                                : line.trackCapacity == .doubleTrack ? 13 : 9,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .mapOverlayLevel(level: .aboveRoads)
                MapPolyline(coordinates: coordinates)
                    .stroke(
                        routeColor,
                        style: StrokeStyle(
                            lineWidth: line.railwayClass == .highSpeed
                                ? 13
                                : line.trackCapacity == .doubleTrack ? 9 : 5,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .mapOverlayLevel(level: .aboveRoads)
                MapPolyline(coordinates: coordinates)
                    .stroke(
                        line.railwayClass == .highSpeed
                            ? TycoonTheme.highSpeedElectric
                            : Color.white.opacity(0.76),
                        style: StrokeStyle(
                            lineWidth: line.railwayClass == .highSpeed
                                ? 2.5
                                : line.trackCapacity == .doubleTrack ? 1.8 : 1.2,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: line.railwayClass == .highSpeed
                                ? []
                                : servicePatternDash(for: line.servicePattern)
                        )
                    )
                    .mapOverlayLevel(level: .aboveRoads)
            }

            if renderingDetailLevel == .local,
               line.trackCapacity == .passingLoop {
                let loopCoordinates = RailwayMapRenderingPolicy.simplifiedCoordinates(
                    line.route.coordinates(
                        fromDistance: line.route.totalLength * 0.42,
                        toDistance: line.route.totalLength * 0.58
                    ),
                    maximumPointCount: min(renderingDetailLevel.maximumRoutePointCount, 320)
                )
                MapPolyline(coordinates: loopCoordinates)
                    .stroke(
                        Color.primary.opacity(0.78),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round)
                    )
                    .mapOverlayLevel(level: .aboveRoads)
                MapPolyline(coordinates: loopCoordinates)
                    .stroke(
                        TycoonTheme.lineColor(for: line.styleIndex),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
                    )
                    .mapOverlayLevel(level: .aboveRoads)
                MapPolyline(coordinates: loopCoordinates)
                    .stroke(
                        Color.primary.opacity(0.76),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                    )
                    .mapOverlayLevel(level: .aboveRoads)

                if let midpoint = line.route.sample(atDistance: line.route.totalLength * 0.5),
                   annotationRenderMapRect.contains(MKMapPoint(midpoint.coordinate)) {
                    Annotation("", coordinate: midpoint.coordinate, anchor: .bottom) {
                        TrackCapacityMapBadge(capacity: .passingLoop)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            } else if renderingDetailLevel == .local,
                      line.trackCapacity == .doubleTrack,
                      line.railwayClass == .conventional,
                      let midpoint = line.route.sample(atDistance: line.route.totalLength * 0.5),
                      annotationRenderMapRect.contains(MKMapPoint(midpoint.coordinate)) {
                Annotation("", coordinate: midpoint.coordinate, anchor: .bottom) {
                    TrackCapacityMapBadge(capacity: .doubleTrack)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }

            if renderingDetailLevel == .local,
               line.railwayClass == .highSpeed,
               let midpoint = line.route.sample(atDistance: line.route.totalLength * 0.5),
               annotationRenderMapRect.contains(MKMapPoint(midpoint.coordinate)) {
                Annotation("", coordinate: midpoint.coordinate, anchor: .bottom) {
                    HighSpeedMapBadge()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }

            if !line.isConstructed,
               let frontier = coordinates.last,
               annotationRenderMapRect.contains(MKMapPoint(frontier)) {
                Annotation("Construction frontier", coordinate: frontier, anchor: .center) {
                    ConstructionSiteAnnotation(
                        color: line.railwayClass == .highSpeed
                            ? TycoonTheme.highSpeedViolet
                            : TycoonTheme.lineColor(for: line.styleIndex),
                        railwayClass: line.railwayClass,
                        progress: line.constructionProgress
                    )
                    .allowsHitTesting(false)
                }
            }
        }
    }

    @MapContentBuilder
    private var previewContent: some MapContent {
        if let preview = session.preview,
           let coordinates = renderedPreviewCoordinates {
            MapPolyline(coordinates: coordinates)
                .stroke(
                    Color.primary.opacity(0.6),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round)
                )
                .mapOverlayLevel(level: .aboveRoads)

            MapPolyline(coordinates: coordinates)
                .stroke(
                    TycoonTheme.construction,
                    style: StrokeStyle(
                        lineWidth: 5,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: [2, 10]
                    )
                )
                .mapOverlayLevel(level: .aboveRoads)

            if preview.railwayClass == .highSpeed {
                MapPolyline(coordinates: coordinates)
                    .stroke(
                        Color.primary.opacity(0.78),
                        style: StrokeStyle(lineWidth: 15, lineCap: .round, lineJoin: .round)
                    )
                    .mapOverlayLevel(level: .aboveRoads)
                MapPolyline(coordinates: coordinates)
                    .stroke(
                        TycoonTheme.highSpeedViolet.opacity(0.92),
                        style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round)
                    )
                    .mapOverlayLevel(level: .aboveRoads)
                MapPolyline(coordinates: coordinates)
                    .stroke(
                        Color.white.opacity(0.88),
                        style: StrokeStyle(
                            lineWidth: 4,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: [8, 5]
                        )
                    )
                    .mapOverlayLevel(level: .aboveRoads)
            }
        }
    }

    @MapContentBuilder
    private var stationVisualContent: some MapContent {
        let premiumStationCRSs = session.premiumHighSpeedStationCRSs
        ForEach(renderedStations) { station in
            let activity = session.passengerSnapshot(forStationCRS: station.crs)
            let happiness = session.happinessSnapshot(forStationCRS: station.crs)
            let evolution = session.stationEvolutionStatus(forStationCRS: station.crs)
            let capacity = session.stationCapacitySnapshot(forStationCRS: station.crs)
            let isPremiumHighSpeed = premiumStationCRSs.contains(
                Self.normalizedCRS(station.crs)
            )
            let isSelectionCandidate = canSelect(station)
            let isAdditionCandidate = canProposeStationAddition(station)
            let hasInspectionDetails = activity != nil || happiness != nil
            let isInteractive = isSelectionCandidate || isAdditionCandidate || hasInspectionDetails
            Annotation("", coordinate: station.coordinate, anchor: .bottom) {
                StationAnnotationView(
                    name: station.name,
                    role: role(for: station),
                    showsName: showsStationName(for: station),
                    activity: activity,
                    evolution: evolution,
                    capacity: capacity,
                    isPremiumHighSpeed: isPremiumHighSpeed
                )
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(station.name) station")
                .accessibilityValue(
                    hasInspectionDetails || isAdditionCandidate
                        ? stationAccessibilityValue(
                            activity: activity,
                            evolution: evolution,
                            capacity: capacity,
                            happiness: happiness,
                            isPremiumHighSpeed: isPremiumHighSpeed,
                            addableLineCount: candidateLineIDs(for: station).count
                        )
                        : ""
                )
                .accessibilityHint(
                    isSelectionCandidate
                        ? stationSelectionHint
                        : isAdditionCandidate
                            ? "Shows the cost and service changes before adding this station"
                        : hasInspectionDetails
                            ? "Opens station, passenger, and platform capacity details"
                            : ""
                )
                .accessibilityAddTraits(.isButton)
                .accessibilityHidden(!isInteractive)
                .accessibilityAction {
                    activateStation(station)
                }
            }
        }
    }

    @MapContentBuilder
    private var arrivalRewardContent: some MapContent {
        ForEach(activeArrivalRewards) { reward in
            Annotation("", coordinate: reward.coordinate, anchor: .center) {
                TrainArrivalRewardView(fareRevenuePence: reward.fareRevenuePence)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    @MapContentBuilder
    private var trainContent: some MapContent {
        ForEach(renderedTrains) { rendering in
            let train = rendering.train
            let formation = rendering.formation
            let occupancy = formation.peakOccupancyRatio
            let estimatedPeakPassengers = formation.estimatedPeakPassengers
            let carriageCount = formation.carriageCount
            let accessibilityValue = trainAccessibilityValue(
                estimatedPeakPassengers: estimatedPeakPassengers,
                occupancy: occupancy,
                feedback: rendering.passengerFeedbackTitle,
                serviceRole: rendering.serviceRole,
                isOvertaking: rendering.isOvertaking,
                railwayClass: rendering.railwayClass,
                carriageCount: carriageCount,
                capacityPerTrain: rendering.seatsPerTrain
            )
            Annotation("", coordinate: train.coordinate, anchor: .center) {
                TrainAnnotationView(
                    lineNumber: rendering.lineStyleIndex + 1,
                    color: TycoonTheme.lineColor(for: rendering.lineStyleIndex),
                    occupancy: occupancy,
                    rotation: train.bearing - cameraHeading,
                    isSelected: session.selectedTrainID == train.id,
                    serviceRole: rendering.serviceRole,
                    railwayClass: rendering.railwayClass,
                    isOvertaking: rendering.isOvertaking,
                    carriageCount: carriageCount,
                    showsDetailedFormation: trainMapDetailLevel == .formation
                ) {
                    session.selectTrain(train.id)
                }
                .accessibilityLabel(
                    rendering.railwayClass == .highSpeed
                        ? "High-speed train \(rendering.number) on \(rendering.lineName)"
                        : "Train \(rendering.number) on \(rendering.lineName)"
                )
                .accessibilityValue(accessibilityValue)
                .accessibilityHint("Opens train controls")
            }
        }
    }

    private func handleStationMapTap(at location: CGPoint, mapProxy: MapProxy) {
        var stations = [Station]()
        var candidates = [StationMapHitCandidate]()
        stations.reserveCapacity(renderedStations.count)
        candidates.reserveCapacity(renderedStations.count)

        for station in renderedStations {
            let isSelectionCandidate = canSelect(station)
            let isAdditionCandidate = canProposeStationAddition(station)
            guard isSelectionCandidate || isAdditionCandidate || canInspect(station),
                  let coordinatePoint = mapProxy.convert(station.coordinate, to: .local) else {
                continue
            }
            stations.append(station)
            candidates.append(
                StationMapHitCandidate(
                    point: CGPoint(
                        x: coordinatePoint.x,
                        y: coordinatePoint.y - StationMapInteractionPolicy.markerCentreVerticalOffset
                    ),
                    targetDiameter: StationMapInteractionPolicy.targetDiameter(
                        detailLevel: renderingDetailLevel,
                        isSelectionCandidate: isSelectionCandidate || isAdditionCandidate
                    )
                )
            )
        }

        guard let nearestIndex = StationMapInteractionPolicy.nearestCandidateIndex(
            to: location,
            candidates: candidates
        ) else {
            return
        }

        // Train controls take precedence where a train is dwelling over a station. The train's
        // own Button handles that tap; skipping the station action prevents both panels opening.
        let trainCandidates = renderedTrains.compactMap { rendering -> StationMapHitCandidate? in
            guard let point = mapProxy.convert(rendering.train.coordinate, to: .local) else {
                return nil
            }
            return StationMapHitCandidate(
                point: point,
                targetDiameter: StationMapInteractionPolicy.trainExclusionDiameter
            )
        }
        guard StationMapInteractionPolicy.nearestCandidateIndex(
            to: location,
            candidates: trainCandidates
        ) == nil else {
            return
        }

        activateStation(stations[nearestIndex])
    }

    private func activateStation(_ station: Station) {
        if canSelect(station) {
            session.selectStation(station)
        } else if canProposeStationAddition(station) {
            session.beginMapStationAddition(
                station,
                candidateLineIDs: Set(candidateLineIDs(for: station))
            )
        } else if canInspect(station) {
            session.selectStationForInspection(station.crs)
        }
    }

    private func canInspect(_ station: Station) -> Bool {
        session.passengerSnapshot(forStationCRS: station.crs) != nil
            || session.happinessSnapshot(forStationCRS: station.crs) != nil
    }

    private func canProposeStationAddition(_ station: Station) -> Bool {
        !candidateLineIDs(for: station).isEmpty
    }

    private func candidateLineIDs(for station: Station) -> [UUID] {
        potentialMapAdditionLineIDsByStationCRS[Self.normalizedCRS(station.crs)] ?? []
    }

    private func stationAccessibilityValue(
        activity: StationPassengerSnapshot?,
        evolution: StationEvolutionStatus?,
        capacity: StationCapacityStationSnapshot?,
        happiness: SettlementHappinessSnapshot?,
        isPremiumHighSpeed: Bool,
        addableLineCount: Int
    ) -> String {
        var details = [String]()
        if addableLineCount > 0 {
            details.append(
                addableLineCount == 1
                    ? "Can be added to one nearby service"
                    : "Can be added to \(addableLineCount) nearby services"
            )
        }
        if isPremiumHighSpeed {
            details.append("Premium high-speed station")
        }
        if let happiness {
            details.append(
                "Happiness \(roundedHappinessScore(happiness.happinessScore)) out of 100, "
                    + happiness.band.label
            )
            details.append(
                "\(happiness.reachableDestinationCount) reachable destinations"
            )
        }
        if let activity {
            details.append(evolution?.level.displayName ?? "Halt")
            details.append(activity.activityLevel.label)
            details.append("\(activity.potentialDailyJourneys) potential journeys per day")
            details.append("\(activity.servedDailyJourneys) served")
        } else {
            details.append("No passenger service")
        }
        if let capacity, capacity.isPlatformConstrained {
            details.append(
                "Platform bottleneck, \(formattedTrainCallRate(capacity.effectiveTrainCallsPerHour)) "
                    + "of \(formattedTrainCallRate(capacity.scheduledTrainCallsPerHour)) scheduled "
                    + "train calls handled per hour"
            )
        }
        return details.joined(separator: ", ")
    }

    private func formattedTrainCallRate(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func roundedHappinessScore(_ score: Double) -> Int {
        guard score.isFinite else { return 0 }
        return Int(min(max(score, 0), 100).rounded())
    }

    private var activeRenderingMapRect: MKMapRect {
        if let visibleMapRect, RailwayMapRenderingPolicy.isUsable(visibleMapRect) {
            return visibleMapRect
        }
        return Self.initialMapRect
    }

    private var annotationRenderMapRect: MKMapRect {
        RailwayMapRenderingPolicy.paddedMapRect(activeRenderingMapRect)
    }

    /// Heatmap circles are useful only near the viewport. Active selections may be kept outside
    /// it briefly while the camera reframes, but offscreen circles add overlays without conveying
    /// anything.
    private var heatmapStations: [Station] {
        renderedStations.filter { station in
            annotationRenderMapRect.contains(MKMapPoint(station.coordinate))
        }
    }

    private var renderedLines: [RenderedRailwayLine] {
        session.lines.compactMap { line in
            guard renderedLineIDs.contains(line.id) else { return nil }
            let coordinates = renderingCache.coordinates(
                for: line,
                detailLevel: renderingDetailLevel
            )
            guard !coordinates.isEmpty else { return nil }
            return RenderedRailwayLine(line: line, coordinates: coordinates)
        }
    }

    private var renderedPreviewCoordinates: [CLLocationCoordinate2D]? {
        guard let preview = session.preview else { return nil }
        let coordinates = renderingCache.previewCoordinates(
            for: preview.route,
            detailLevel: renderingDetailLevel
        )
        return coordinates.count >= 2 ? coordinates : nil
    }

    private var renderedTrains: [TrainPresentationSnapshot] {
        let allTrains = session.trains
        let visibleTrains = RailwayMapRenderingPolicy.renderedTrains(
            from: allTrains,
            selectedTrainID: session.selectedTrainID,
            visibleMapRect: activeRenderingMapRect,
            maximumCount: renderingDetailLevel.maximumVisibleTrainCount
        )
        let snapshots = session.trainPresentationSnapshots(
            for: Set(visibleTrains.map(\.id))
        )
        let snapshotsByID = Dictionary(
            snapshots.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return visibleTrains.compactMap { train in
            snapshotsByID[train.id]
        }
    }

    private var stationRenderingContextKey: StationRenderingContextKey {
        StationRenderingContextKey(
            persistenceRevision: session.persistenceRevision,
            phase: session.phase,
            selectedOriginCRS: session.selectedOrigin?.crs,
            selectedDestinationCRS: session.selectedDestination?.crs,
            selectedStationCRS: session.selectedStationID,
            previewStationCRSs: session.previewSelectedStationCRSs
        )
    }

    private func updateRenderingContext(
        visibleMapRect: MKMapRect,
        cameraDistance: CLLocationDistance
    ) {
        let nextDetailLevel = RailwayMapRenderingDetailLevel(
            cameraDistanceMetres: cameraDistance
        )
        let detailLevelChanged = nextDetailLevel != renderingDetailLevel
        renderingDetailLevel = nextDetailLevel
        guard detailLevelChanged
                || RailwayMapRenderingPolicy.viewportRequiresStationRefresh(
                    previous: lastStationRenderMapRect,
                    current: visibleMapRect
                ) else {
            return
        }
        refreshRenderedStations(
            visibleMapRect: visibleMapRect,
            detailLevel: nextDetailLevel
        )
    }

    private func refreshRenderedStations(
        visibleMapRect: MKMapRect? = nil,
        detailLevel: RailwayMapRenderingDetailLevel? = nil
    ) {
        var styleIndices = [String: Int]()
        for line in session.lines {
            for crs in line.stationCRSs {
                let normalizedCRS = Self.normalizedCRS(crs)
                if styleIndices[normalizedCRS] == nil {
                    styleIndices[normalizedCRS] = line.styleIndex
                }
            }
        }

        var selectedStationCRSs = Set<String>()
        if let selectedOrigin = session.selectedOrigin?.crs {
            selectedStationCRSs.insert(Self.normalizedCRS(selectedOrigin))
        }
        if let selectedDestination = session.selectedDestination?.crs {
            selectedStationCRSs.insert(Self.normalizedCRS(selectedDestination))
        }
        if let selectedStationID = session.selectedStationID {
            selectedStationCRSs.insert(Self.normalizedCRS(selectedStationID))
        }
        selectedStationCRSs.formUnion(session.previewSelectedStationCRSs.map(Self.normalizedCRS))

        let nextStations = RailwayMapRenderingPolicy.renderedStations(
            from: session.stations,
            builtStationCRSs: Set(styleIndices.keys),
            selectedStationCRSs: selectedStationCRSs,
            visibleMapRect: visibleMapRect ?? activeRenderingMapRect,
            detailLevel: detailLevel ?? renderingDetailLevel
        )
        lastStationRenderMapRect = visibleMapRect ?? activeRenderingMapRect
        if builtStationStyleIndices != styleIndices {
            builtStationStyleIndices = styleIndices
        }
        if renderedStations != nextStations {
            renderedStations = nextStations
        }
        renderingCache.removeLines(except: Set(session.lines.map(\.id)))
        let nextLineIDs = refreshRenderedLines(
            visibleMapRect: visibleMapRect ?? activeRenderingMapRect,
            detailLevel: detailLevel ?? renderingDetailLevel
        )
        if session.phase == .operating {
            // Do not leave tappable markers from the previous viewport while a replacement
            // proximity pass is running.
            if !potentialMapAdditionLineIDsByStationCRS.isEmpty {
                potentialMapAdditionLineIDsByStationCRS = [:]
            }
            potentialMapAdditionPreflight = MapStationAdditionPreflight(
                id: UUID(),
                stations: nextStations,
                lines: session.lines.filter { nextLineIDs.contains($0.id) },
                maximumServiceCallCount: session.maximumServiceCallCount
            )
        } else {
            potentialMapAdditionPreflight = nil
            if !potentialMapAdditionLineIDsByStationCRS.isEmpty {
                potentialMapAdditionLineIDsByStationCRS = [:]
            }
        }
    }

    private func refreshRenderedLines(
        visibleMapRect: MKMapRect,
        detailLevel: RailwayMapRenderingDetailLevel
    ) -> Set<UUID> {
        let candidates = session.lines.map { line in
            RailwayMapLineCandidate(
                id: line.id,
                mapRect: renderingCache.framingMapRect(for: line)
            )
        }
        let nextLineIDs = Set(
            RailwayMapRenderingPolicy.renderedLineIDs(
                from: candidates,
                focusedLineID: lineFocusRequest?.lineID,
                visibleMapRect: visibleMapRect,
                maximumCount: detailLevel.maximumVisibleLineCount
            )
        )
        if renderedLineIDs != nextLineIDs {
            renderedLineIDs = nextLineIDs
        }
        return nextLineIDs
    }

    /// Catalogue search can select a station hundreds of miles away. Reframe only when the new
    /// origin is genuinely offscreen, so ordinary map taps retain the player's chosen camera.
    private func frameSearchedOriginIfNeeded() {
        guard session.phase == .selectingDestination,
              let origin = session.selectedOrigin,
              let visibleMapRect,
              RailwayMapRenderingPolicy.isUsable(visibleMapRect),
              !visibleMapRect.contains(MKMapPoint(origin.coordinate)) else {
            return
        }
        let nextCamera = MapCamera(
            centerCoordinate: origin.coordinate,
            distance: min(max(currentCamera?.distance ?? 55_000, 28_000), 90_000),
            heading: currentCamera?.heading ?? 0,
            pitch: currentCamera?.pitch ?? 0
        )
        if reduceMotion {
            cameraPosition = .camera(nextCamera)
        } else {
            withAnimation(.easeInOut(duration: 0.4)) {
                cameraPosition = .camera(nextCamera)
            }
        }
    }

    private var previewKey: String? {
        guard let preview = session.preview else { return nil }
        let coordinates = preview.route.coordinates
        let midpoint = coordinates.isEmpty ? nil : coordinates[coordinates.count / 2]
        let routeFingerprint = [
            coordinates.first.map(Self.coordinateKey) ?? "empty",
            midpoint.map(Self.coordinateKey) ?? "empty",
            coordinates.last.map(Self.coordinateKey) ?? "empty",
            coordinates.count.formatted(),
            preview.route.totalLength.formatted(.number.precision(.fractionLength(1))),
        ].joined(separator: ":")
        return [
            preview.origin.id,
            session.previewSelectedStationCRSs.joined(separator: ">"),
            preview.destination.id,
            routeFingerprint,
        ].joined(separator: "|")
    }

    private var followSnapshot: FollowSnapshot? {
        guard let train = session.selectedTrain else { return nil }
        return FollowSnapshot(id: train.id, coordinate: train.coordinate)
    }

    private var stationSelectionHint: String {
        switch session.phase {
        case .selectingOrigin:
            "Selects this station as the start of a new line"
        case .selectingDestination:
            "Selects this station as the end of the new line"
        default:
            ""
        }
    }

    private func canSelect(_ station: Station) -> Bool {
        session.isStationEligibleForCurrentBuild(station)
    }

    private func showsStationName(for station: Station) -> Bool {
        let isSelected = station.id == session.selectedOrigin?.id
            || station.id == session.selectedDestination?.id
            || station.id == session.selectedStationID
        if isSelected {
            return true
        }
        if builtStationStyleIndices[Self.normalizedCRS(station.crs)] != nil {
            return renderingDetailLevel.showsCandidateStationNames
        }
        if canProposeStationAddition(station) {
            return renderingDetailLevel != .country
        }
        return switch session.phase {
        case .selectingOrigin, .selectingDestination, .calculating, .preview:
            renderingDetailLevel.showsCandidateStationNames
        default:
            false
        }
    }

    private func role(for station: Station) -> StationAnnotationRole {
        if station.id == session.selectedOrigin?.id {
            return .origin
        }
        if station.id == session.selectedDestination?.id {
            return .destination
        }
        if session.phase == .preview,
           session.previewSelectedStationCRSs.contains(where: {
               Self.normalizedCRS($0) == Self.normalizedCRS(station.crs)
           }) {
            return .previewCall
        }
        if station.id == session.selectedStationID {
            let color = builtStationStyleIndices[Self.normalizedCRS(station.crs)].map {
                TycoonTheme.lineColor(for: $0)
            } ?? TycoonTheme.railGreenBright
            return .inspected(color)
        }
        if canProposeStationAddition(station) {
            return .addableStop
        }
        if session.phase == .selectingOrigin || session.phase == .selectingDestination,
           !session.isStationEligibleForCurrentBuild(station) {
            return .unavailable
        }
        if let styleIndex = builtStationStyleIndices[Self.normalizedCRS(station.crs)] {
            return .lineStation(TycoonTheme.lineColor(for: styleIndex))
        }
        return .available
    }

    nonisolated private static func normalizedCRS(_ crs: String) -> String {
        crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    nonisolated private static func coordinateKey(_ coordinate: CLLocationCoordinate2D) -> String {
        "\(coordinate.latitude.formatted(.number.precision(.fractionLength(6))))"
            + ",\(coordinate.longitude.formatted(.number.precision(.fractionLength(6))))"
    }

    private func servicePatternDash(for pattern: ServicePattern) -> [CGFloat] {
        switch pattern {
        case .local: [1, 6]
        case .balanced: [10, 5, 2, 5]
        case .express: []
        }
    }

    private func trainAccessibilityValue(
        estimatedPeakPassengers: Int,
        occupancy: Double,
        feedback: String,
        serviceRole: TrainServiceRole,
        isOvertaking: Bool,
        railwayClass: RailwayClass,
        carriageCount: Int,
        capacityPerTrain: Int
    ) -> String {
        var parts = [
            "Estimated peak service load",
            "\(estimatedPeakPassengers) of \(capacityPerTrain) passengers",
            "\(occupancy.formatted(.percent.precision(.fractionLength(0)))) estimated load",
            feedback,
            serviceRole.name,
            "\(carriageCount)-car formation",
        ]
        if railwayClass == .highSpeed {
            parts.append("Dedicated high-speed rolling stock")
            parts.append("215 miles per hour capability")
        }
        if isOvertaking {
            parts.append("overtaking a local service")
        }
        return parts.joined(separator: ", ")
    }

    private func handleTrainArrivalEvents() {
        let events = session.presentationEvents(after: lastHandledPresentationEventSequence)
        for event in events {
            lastHandledPresentationEventSequence = event.sequence
            guard allowsJourneyFeedback else { continue }
            guard case let .trainArrived(
                _,
                _,
                stationCRS,
                fareRevenuePence,
                soundsHorn
            ) = event.kind,
            let station = session.stations.first(where: {
                StationEvolution.normalizedCRS($0.crs)
                    == StationEvolution.normalizedCRS(stationCRS)
            }),
            journeyFeedbackMapRect?.contains(MKMapPoint(station.coordinate)) == true else {
                continue
            }

            let reward = TrainArrivalRewardPresentation(
                id: event.sequence,
                coordinate: station.coordinate,
                fareRevenuePence: max(fareRevenuePence, 0)
            )
            if activeArrivalRewards.count >= 4 {
                activeArrivalRewards.removeFirst()
            }
            activeArrivalRewards.append(reward)
            onVisibleTrainArrival(soundsHorn)

            Task { @MainActor in
                let lifetimeMilliseconds = reduceMotion
                    ? TrainArrivalRewardTiming.reduceMotionLifetimeMilliseconds
                    : TrainArrivalRewardTiming.animatedLifetimeMilliseconds
                try? await Task.sleep(for: .milliseconds(lifetimeMilliseconds))
                guard !Task.isCancelled else { return }
                activeArrivalRewards.removeAll { $0.id == reward.id }
            }
        }
    }

    private func updateTrainMapDetailLevel(for cameraDistance: CLLocationDistance) {
        let nextLevel = TrainFormationPolicy().detailLevel(
            after: trainMapDetailLevel,
            cameraDistanceMetres: cameraDistance
        )
        guard nextLevel != trainMapDetailLevel else { return }
        if reduceMotion {
            trainMapDetailLevel = nextLevel
        } else {
            withAnimation(.easeOut(duration: 0.16)) {
                trainMapDetailLevel = nextLevel
            }
        }
    }

    /// The map remains visible beneath the floating HUD and bottom controls. Restrict rewards to
    /// the conservative central play area so a station hidden by chrome—or lying in a rotated
    /// camera's bounding-rect corner—does not produce apparently disembodied feedback.
    private var journeyFeedbackMapRect: MKMapRect? {
        guard let visibleMapRect,
              !visibleMapRect.isNull,
              visibleMapRect.width > 0,
              visibleMapRect.height > 0 else {
            return nil
        }
        return MKMapRect(
            x: visibleMapRect.minX + visibleMapRect.width * 0.12,
            y: visibleMapRect.minY + visibleMapRect.height * 0.22,
            width: visibleMapRect.width * 0.76,
            height: visibleMapRect.height * 0.46
        )
    }

    private func frame(_ coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else { return }
        frame(RailwayMapRenderingPolicy.mapRect(containing: coordinates))
    }

    private func frame(_ routeRect: MKMapRect) {
        guard RailwayMapRenderingPolicy.isUsable(routeRect) else { return }

        let horizontalPadding = max(routeRect.width * 0.22, 2_500)
        let northernPadding = max(routeRect.height * 0.20, 2_500)
        let southernPadding = max(routeRect.height * 0.72, 6_000)
        let framedRect = MKMapRect(
            x: routeRect.minX - horizontalPadding,
            y: routeRect.minY - northernPadding,
            width: routeRect.width + horizontalPadding * 2,
            height: routeRect.height + northernPadding + southernPadding
        )

        if reduceMotion {
            cameraPosition = .rect(framedRect)
        } else {
            withAnimation(.easeInOut(duration: 0.45)) {
                cameraPosition = .rect(framedRect)
            }
        }
    }

    private func follow(_ coordinate: CLLocationCoordinate2D) {
        let distance = min(max(currentCamera?.distance ?? 14_000, 4_000), 42_000)
        cameraPosition = .camera(
            MapCamera(
                centerCoordinate: coordinate,
                distance: distance,
                heading: currentCamera?.heading ?? 0,
                pitch: currentCamera?.pitch ?? 0
            )
        )
    }

    private static let initialRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 51.15, longitude: -0.10),
        span: MKCoordinateSpan(latitudeDelta: 1.18, longitudeDelta: 0.78)
    )

    private static let initialMapRect = RailwayMapRenderingPolicy.mapRect(containing: [
        CLLocationCoordinate2D(
            latitude: initialRegion.center.latitude - initialRegion.span.latitudeDelta / 2,
            longitude: initialRegion.center.longitude - initialRegion.span.longitudeDelta / 2
        ),
        CLLocationCoordinate2D(
            latitude: initialRegion.center.latitude + initialRegion.span.latitudeDelta / 2,
            longitude: initialRegion.center.longitude + initialRegion.span.longitudeDelta / 2
        ),
    ])
}

/// Point-space interaction budgets for station annotations.
///
/// The visual marker remains deliberately compact; these values affect only the screen-space
/// nearest-station resolver. Selection is the map's primary action while building, so candidates
/// receive more tolerance than already-built stations that can be opened for inspection. Targets
/// grow as the camera moves closer, when neighbouring stations have more screen-space separation.
nonisolated enum StationMapInteractionPolicy {
    static let minimumTargetDiameter: CGFloat = 44
    static let markerCentreVerticalOffset: CGFloat = 22
    static let trainExclusionDiameter: CGFloat = 52

    static func targetDiameter(
        detailLevel: RailwayMapRenderingDetailLevel,
        isSelectionCandidate: Bool
    ) -> CGFloat {
        if isSelectionCandidate {
            return switch detailLevel {
            case .country: 64
            case .regional: 68
            case .local: 72
            }
        }
        return switch detailLevel {
        case .country: 52
        case .regional: 56
        case .local: 60
        }
    }

    /// Resolves overlapping target circles by proximity rather than annotation insertion order.
    /// A stable lower-index tie break keeps behavior deterministic for exactly coincident stations.
    static func nearestCandidateIndex(
        to location: CGPoint,
        candidates: [StationMapHitCandidate]
    ) -> Int? {
        var best: (index: Int, distanceSquared: CGFloat)?
        for (index, candidate) in candidates.enumerated() {
            let deltaX = candidate.point.x - location.x
            let deltaY = candidate.point.y - location.y
            let distanceSquared = deltaX * deltaX + deltaY * deltaY
            let radius = max(candidate.targetDiameter, minimumTargetDiameter) / 2
            guard distanceSquared <= radius * radius else { continue }
            if best == nil || distanceSquared < best!.distanceSquared {
                best = (index, distanceSquared)
            }
        }
        return best?.index
    }
}

nonisolated struct StationMapHitCandidate: Equatable, Sendable {
    let point: CGPoint
    let targetDiameter: CGFloat
}

/// Immutable input for the potentially expensive route-proximity pass. SwiftUI cancels the
/// preceding task when a new settled viewport arrives, while the actual geometry work runs away
/// from MapKit's main-thread gesture and layout work.
nonisolated private struct MapStationAdditionPreflight: Identifiable, Sendable {
    let id: UUID
    let stations: [Station]
    let lines: [BuiltLine]
    let maximumServiceCallCount: Int
}

private struct RenderedRailwayLine: Identifiable {
    let line: BuiltLine
    let coordinates: [CLLocationCoordinate2D]

    var id: UUID { line.id }
}

private struct StationRenderingContextKey: Equatable {
    let persistenceRevision: UInt64
    let phase: GamePhase
    let selectedOriginCRS: String?
    let selectedDestinationCRS: String?
    let selectedStationCRS: String?
    let previewStationCRSs: [String]
}

private struct FollowSnapshot: Equatable {
    let id: UUID
    let latitude: Double
    let longitude: Double

    init(id: UUID, coordinate: CLLocationCoordinate2D) {
        self.id = id
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private struct TrainArrivalRewardPresentation: Identifiable {
    let id: UInt64
    let coordinate: CLLocationCoordinate2D
    let fareRevenuePence: Int64
}

/// Keeps the fare amount still long enough to read before a short, restrained exit.
/// Integer millisecond values make the view's animation and its owner's cleanup agree exactly.
enum TrainArrivalRewardTiming {
    static let readableHoldMilliseconds = 1_500
    static let exitAnimationMilliseconds = 500
    static let cleanupBufferMilliseconds = 100
    static let reduceMotionLifetimeMilliseconds = 2_000

    static var animatedLifetimeMilliseconds: Int {
        readableHoldMilliseconds + exitAnimationMilliseconds + cleanupBufferMilliseconds
    }
}

private struct TrainArrivalRewardView: View {
    let fareRevenuePence: Int64

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDeparting = false

    var body: some View {
        Text("+\(formattedFareRevenue)")
            .font(.system(size: 14, weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .frame(minHeight: 27)
            .background(TycoonTheme.railGreen, in: .capsule)
            .overlay {
                Capsule().stroke(Color.white.opacity(0.88), lineWidth: 1.2)
            }
            .shadow(color: TycoonTheme.ink.opacity(0.28), radius: 4, y: 2)
            .offset(y: reduceMotion ? -20 : isDeparting ? -48 : -14)
            .opacity(reduceMotion ? 1 : isDeparting ? 0 : 1)
            .scaleEffect(reduceMotion ? 1 : isDeparting ? 0.96 : 1)
            // Keep the MapKit annotation bounds invariant; only the label inside it moves.
            .frame(width: 104, height: 84, alignment: .bottom)
            .task {
                guard !reduceMotion else { return }
                try? await Task.sleep(
                    for: .milliseconds(TrainArrivalRewardTiming.readableHoldMilliseconds)
                )
                guard !Task.isCancelled else { return }
                withAnimation(
                    .easeIn(duration: Double(TrainArrivalRewardTiming.exitAnimationMilliseconds) / 1_000)
                ) {
                    isDeparting = true
                }
            }
    }

    private var formattedFareRevenue: String {
        (Double(max(fareRevenuePence, 0)) / 100).formatted(
            .currency(code: "GBP")
                .precision(.fractionLength(0))
        )
    }
}

private struct HappinessMapLegend: View {
    var body: some View {
        HStack(spacing: 7) {
            Text("HAPPINESS")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(0.4)

            legendItem(symbol: "!", color: TycoonTheme.happinessColor(for: 25))
            legendItem(symbol: "~", color: TycoonTheme.happinessColor(for: 55))
            legendItem(symbol: "✓", color: TycoonTheme.happinessColor(for: 85))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 9)
        .frame(minHeight: 28)
        .background(.regularMaterial, in: .capsule)
        .overlay {
            Capsule().stroke(Color.primary.opacity(0.32), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Happiness heatmap legend. Exclamation low, tilde medium, checkmark high.")
    }

    private func legendItem(symbol: String, color: Color) -> some View {
        Text(symbol)
            .font(.system(size: 9, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(color, in: .circle)
    }
}

private enum StationAnnotationRole {
    case available
    case addableStop
    case origin
    case destination
    case previewCall
    case lineStation(Color)
    case inspected(Color)
    case unavailable

    var fill: Color {
        switch self {
        case .available:
            .white
        case .addableStop:
            TycoonTheme.railGreenBright
        case .origin:
            TycoonTheme.railGreenBright
        case .destination:
            TycoonTheme.construction
        case .previewCall:
            TycoonTheme.construction
        case .lineStation(let color), .inspected(let color):
            color
        case .unavailable:
            .secondary
        }
    }

    var isSelected: Bool {
        switch self {
        case .addableStop, .origin, .destination, .previewCall, .inspected:
            true
        default:
            false
        }
    }
}

private struct StationAnnotationView: View {
    let name: String
    let role: StationAnnotationRole
    let showsName: Bool
    let activity: StationPassengerSnapshot?
    let evolution: StationEvolutionStatus?
    let capacity: StationCapacityStationSnapshot?
    let isPremiumHighSpeed: Bool

    var body: some View {
        VStack(spacing: 3) {
            if showsName {
                Text(name)
                    .font(.caption2.weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.thinMaterial, in: .capsule)
            }

            ZStack {
                if let activity, activity.activity > 0 {
                    Circle()
                        .stroke(
                            TycoonTheme.railGreenBright.opacity(0.56),
                            lineWidth: 2
                        )
                        .frame(
                            width: 25 + CGFloat(activity.activity) * 13,
                            height: 25 + CGFloat(activity.activity) * 13
                        )
                        // A static halo preserves the activity cue without one perpetual animation
                        // per busy station. A national network can display hundreds of markers, so
                        // independent repeating animations create avoidable compositor wakeups.
                        .opacity(0.48)
                        .accessibilityHidden(true)
                }

                if role.isSelected {
                    Circle()
                        .stroke(role.fill.opacity(0.34), lineWidth: 5)
                        .frame(width: markerDiameter + 9, height: markerDiameter + 9)
                }

                StationLevelMarker(
                    level: evolution?.level ?? .halt,
                    fill: role.fill,
                    diameter: markerDiameter,
                    isPremiumHighSpeed: isPremiumHighSpeed
                )

                if case .addableStop = role {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 17, height: 17)
                        .background(TycoonTheme.railGreen, in: .circle)
                        .overlay {
                            Circle().stroke(Color.white.opacity(0.94), lineWidth: 1.2)
                        }
                        .offset(x: 12, y: -11)
                        .accessibilityHidden(true)
                }

                if capacity?.isPlatformConstrained == true {
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(TycoonTheme.ink)
                        .frame(width: 15, height: 15)
                        .background(TycoonTheme.construction, in: .circle)
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.92), lineWidth: 1.2)
                        }
                        .offset(x: 12, y: 12)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 44, height: 44)
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(.rect)
    }

    private var markerDiameter: CGFloat {
        let level = evolution?.level ?? .halt
        let index = StationLevel.allCases.firstIndex(of: level) ?? 0
        return 12 + CGFloat(index) * 1.7
    }
}

private struct StationLevelMarker: View {
    let level: StationLevel
    let fill: Color
    let diameter: CGFloat
    let isPremiumHighSpeed: Bool

    var body: some View {
        ZStack {
            if isPremiumHighSpeed {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(TycoonTheme.highSpeedViolet)
                    .frame(width: diameter + 11, height: diameter + 11)
                    .rotationEffect(.degrees(45))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color.white.opacity(0.92), lineWidth: 1.5)
                            .frame(width: diameter + 11, height: diameter + 11)
                            .rotationEffect(.degrees(45))
                    }
            }

            if level >= .localStation {
                Circle()
                    .stroke(Color.primary.opacity(0.66), lineWidth: 1.3)
                    .frame(width: diameter + 5, height: diameter + 5)
            }

            if level >= .majorStation {
                Circle()
                    .stroke(Color.primary.opacity(0.42), lineWidth: 1)
                    .frame(width: diameter + 10, height: diameter + 10)
            }

            Circle()
                .fill(isPremiumHighSpeed ? TycoonTheme.warmPaper : fill)
                .frame(width: diameter, height: diameter)
                .overlay {
                    Circle()
                        .stroke(
                            isPremiumHighSpeed
                                ? TycoonTheme.highSpeedViolet
                                : Color.primary.opacity(0.86),
                            lineWidth: 2.5
                        )
                }

            if isPremiumHighSpeed {
                Text("H")
                    .font(.system(size: max(diameter * 0.48, 7), weight: .black, design: .rounded))
                    .foregroundStyle(TycoonTheme.highSpeedViolet)
            }

            if level >= .interchange, !isPremiumHighSpeed {
                HStack(spacing: 2) {
                    Capsule().frame(width: 2, height: diameter * 0.54)
                    Capsule().frame(width: 2, height: diameter * 0.54)
                }
                .foregroundStyle(Color.primary.opacity(0.82))
            }

            if level == .terminus, !isPremiumHighSpeed {
                Capsule()
                    .fill(Color.primary.opacity(0.82))
                    .frame(width: diameter * 0.58, height: 2)
            }
        }
        .frame(width: 36, height: 36)
        .shadow(color: TycoonTheme.ink.opacity(0.18), radius: 3, y: 1)
        .accessibilityHidden(true)
    }
}

private struct TrainAnnotationView: View {
    let lineNumber: Int
    let color: Color
    let occupancy: Double
    let rotation: Double
    let isSelected: Bool
    let serviceRole: TrainServiceRole
    let railwayClass: RailwayClass
    let isOvertaking: Bool
    let carriageCount: Int
    let showsDetailedFormation: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isOvertaking {
                    Capsule()
                        .fill(Color.yellow.opacity(0.24))
                        .overlay {
                            Capsule().stroke(Color.yellow.opacity(0.92), lineWidth: 2)
                        }
                        .frame(
                            width: showsDetailedFormation ? 30 : 42,
                            height: showsDetailedFormation ? detailedFormationHighlightHeight : 42
                        )
                        .rotationEffect(.degrees(showsDetailedFormation ? rotation : 0))
                        .accessibilityHidden(true)
                }

                if isSelected {
                    Capsule()
                        .fill(.white.opacity(0.94))
                        .frame(
                            width: showsDetailedFormation ? 29 : 42,
                            height: showsDetailedFormation ? detailedFormationHighlightHeight : 42
                        )
                        .rotationEffect(.degrees(showsDetailedFormation ? rotation : 0))
                        .shadow(color: TycoonTheme.ink.opacity(0.22), radius: 6, y: 2)
                }

                Group {
                    if showsDetailedFormation {
                        DetailedTrainFormationCanvas(
                            carriageCount: carriageCount,
                            color: color,
                            railwayClass: railwayClass
                        )
                        .frame(width: 30, height: 96)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    } else if railwayClass == .highSpeed {
                        ZStack {
                            TopDownHighSpeedTrainShape()
                                .fill(TycoonTheme.highSpeedViolet)
                            TopDownHighSpeedTrainShape()
                                .stroke(Color.white.opacity(0.96), lineWidth: 1.5)
                            Capsule()
                                .fill(TycoonTheme.highSpeedElectric.opacity(0.92))
                                .frame(width: 5, height: 24)
                            Capsule()
                                .fill(Color.white.opacity(0.92))
                                .frame(width: 4, height: 7)
                                .offset(y: -12)
                            Circle()
                                .fill(TycoonTheme.highSpeedGold)
                                .frame(width: 3.5, height: 3.5)
                                .offset(y: -18)
                            Text("\(lineNumber)")
                                .font(.system(size: 7, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .rotationEffect(.degrees(-rotation))
                                .offset(y: 10)
                        }
                        .frame(width: 18, height: 42)
                    } else {
                        ZStack {
                            TopDownTrainShape()
                                .fill(color)
                            TopDownTrainShape()
                                .stroke(.white.opacity(0.95), lineWidth: 1.4)
                            Capsule()
                                .fill(TycoonTheme.ink.opacity(0.78))
                                .frame(width: 6, height: 16)
                            HStack(spacing: 2) {
                                Capsule()
                                Capsule()
                            }
                            .foregroundStyle(Color.white.opacity(0.78))
                            .frame(width: 8, height: 4)
                            .offset(y: -8)
                            Circle()
                                .fill(Color.white.opacity(0.96))
                                .frame(width: 3.5, height: 3.5)
                                .offset(y: -14)
                            Text("\(lineNumber)")
                                .font(.system(size: 7, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .rotationEffect(.degrees(-rotation))
                                .offset(y: 8)
                        }
                        .frame(width: 17, height: 36)
                    }
                }
                .rotationEffect(.degrees(rotation))
                .shadow(color: TycoonTheme.ink.opacity(0.38), radius: 3, y: 2)

                if showsDetailedFormation {
                    Capsule()
                        .fill(.white.opacity(0.92))
                        .frame(width: 4, height: 42)
                        .overlay(alignment: .bottom) {
                            Capsule()
                                .fill(occupancyColor)
                                .frame(
                                    width: 4,
                                    height: 42 * CGFloat(min(max(occupancy, 0), 1))
                                )
                        }
                        .offset(x: -14)
                        .rotationEffect(.degrees(rotation))
                        .accessibilityHidden(true)
                } else {
                    Capsule()
                        .fill(.white.opacity(0.92))
                        .frame(width: 24, height: 4)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(occupancyColor)
                                .frame(
                                    width: 24 * CGFloat(min(max(occupancy, 0), 1)),
                                    height: 4
                                )
                        }
                        .offset(y: 22)
                        .accessibilityHidden(true)
                }

                Text(railwayClass == .highSpeed ? "H" : serviceRole.badge)
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(
                        railwayClass == .highSpeed
                            ? TycoonTheme.ink
                            : serviceRole == .express ? TycoonTheme.ink : .white
                    )
                    .frame(width: 15, height: 15)
                    .background(
                        railwayClass == .highSpeed
                            ? TycoonTheme.highSpeedGold
                            : serviceRole == .express ? Color.white : color,
                        in: .circle
                    )
                    .overlay {
                        Circle().stroke(Color.primary.opacity(0.68), lineWidth: 1)
                    }
                    .offset(
                        x: showsDetailedFormation ? 20 : 13,
                        y: showsDetailedFormation ? 0 : -13
                    )
                    .accessibilityHidden(true)

                if isOvertaking {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(TycoonTheme.ink)
                        .frame(width: 15, height: 15)
                        .background(Color.yellow, in: .circle)
                        .offset(
                            x: showsDetailedFormation ? -20 : -13,
                            y: showsDetailedFormation ? 0 : -13
                        )
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var occupancyColor: Color {
        if occupancy >= 0.9 { return TycoonTheme.construction }
        return railwayClass == .highSpeed ? TycoonTheme.highSpeedElectric : color
    }

    private var detailedFormationHighlightHeight: CGFloat {
        let count = min(max(carriageCount, 2), 12)
        let formationHeight = CGFloat(count) * 6.8 + CGFloat(count - 1) * 1.2
        return min(formationHeight + 6, 100)
    }
}

private struct DetailedTrainFormationCanvas: View {
    let carriageCount: Int
    let color: Color
    let railwayClass: RailwayClass

    var body: some View {
        Canvas { context, size in
            let count = min(max(carriageCount, 2), 12)
            let carriageHeight: CGFloat = 6.8
            let gap: CGFloat = 1.2
            let totalHeight = CGFloat(count) * carriageHeight
                + CGFloat(count - 1) * gap
            let carriageWidth: CGFloat = railwayClass == .highSpeed ? 15 : 14
            let originX = (size.width - carriageWidth) / 2
            let originY = (size.height - totalHeight) / 2
            let bodyColor = railwayClass == .highSpeed
                ? TycoonTheme.highSpeedViolet
                : color
            let windowColor = railwayClass == .highSpeed
                ? TycoonTheme.highSpeedElectric.opacity(0.94)
                : TycoonTheme.ink.opacity(0.78)

            for index in 0..<count {
                let y = originY + CGFloat(index) * (carriageHeight + gap)
                let carriageRect = CGRect(
                    x: originX,
                    y: y,
                    width: carriageWidth,
                    height: carriageHeight
                )
                let carriagePath = Path(
                    roundedRect: carriageRect,
                    cornerRadius: index == 0 || index == count - 1 ? 2.8 : 1.8
                )
                context.fill(carriagePath, with: .color(bodyColor))
                context.stroke(
                    carriagePath,
                    with: .color(Color.white.opacity(0.96)),
                    lineWidth: 0.9
                )

                let windowRect = CGRect(
                    x: carriageRect.midX - 3.2,
                    y: carriageRect.midY - 1.15,
                    width: 6.4,
                    height: 2.3
                )
                context.fill(
                    Path(roundedRect: windowRect, cornerRadius: 1.1),
                    with: .color(windowColor)
                )
            }

            // Identical end lights keep the consist centered when its bearing reverses at a
            // terminal; the whole formation never swings around its coordinate anchor.
            let lightColor = railwayClass == .highSpeed
                ? TycoonTheme.highSpeedGold
                : Color.white
            for y in [originY + 1.5, originY + totalHeight - 1.5] {
                let lightRect = CGRect(
                    x: size.width / 2 - 1.4,
                    y: y - 1.4,
                    width: 2.8,
                    height: 2.8
                )
                context.fill(Path(ellipseIn: lightRect), with: .color(lightColor))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct TrackCapacityMapBadge: View {
    let capacity: TrackCapacity

    var body: some View {
        Label(
            capacity == .passingLoop ? "LOOP" : "2 TRACKS",
            systemImage: capacity == .passingLoop ? "arrow.left.arrow.right" : "equal"
        )
        .font(.system(size: 8, weight: .black, design: .rounded))
        .tracking(0.25)
        .foregroundStyle(.primary)
        .padding(.horizontal, 6)
        .frame(height: 22)
        .background(.regularMaterial, in: .capsule)
        .overlay {
            Capsule().stroke(Color.primary.opacity(0.34), lineWidth: 1)
        }
        .frame(width: 80, height: 44)
    }
}

private struct HighSpeedMapBadge: View {
    var body: some View {
        Label("HIGH SPEED", systemImage: "bolt.fill")
            .font(.system(size: 8, weight: .black, design: .rounded))
            .tracking(0.35)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .frame(height: 23)
            .background(TycoonTheme.highSpeedViolet, in: .capsule)
            .overlay {
                Capsule().stroke(TycoonTheme.highSpeedGold.opacity(0.9), lineWidth: 1.5)
            }
            .frame(width: 94, height: 44)
    }
}

private struct ConstructionSiteAnnotation: View {
    let color: Color
    let railwayClass: RailwayClass
    let progress: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                Circle()
                    .fill(index.isMultiple(of: 2) ? TycoonTheme.construction : .white)
                    .frame(width: index.isMultiple(of: 3) ? 4 : 3)
                    .offset(sparkOffset(for: index))
                    .opacity(reduceMotion ? 0.72 : index.isMultiple(of: 2) ? 0.92 : 0.42)
                    .scaleEffect(reduceMotion ? 1 : index.isMultiple(of: 2) ? 1.1 : 0.72)
                    .accessibilityHidden(true)
            }

            Circle()
                .fill(.regularMaterial)
                .frame(width: 32, height: 32)
                .overlay {
                    Circle().stroke(color.opacity(0.88), lineWidth: 2)
                }
                .shadow(color: TycoonTheme.ink.opacity(0.25), radius: 5, y: 2)

            Image(systemName: railwayClass == .highSpeed ? "bolt.fill" : "hammer.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
                .accessibilityHidden(true)
        }
        // MapKit anchors custom annotations from their content bounds. This invariant frame keeps
        // the construction marker fixed while leaf-only spark opacity and scale animate.
        .frame(width: 52, height: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Line under construction, "
                + progress.formatted(.percent.precision(.fractionLength(0)))
        )
    }

    private func sparkOffset(for index: Int) -> CGSize {
        let angle = Double(index) / 6 * Double.pi * 2 - Double.pi / 2
        let radius = index.isMultiple(of: 2) ? 21.0 : 18.0
        return CGSize(width: cos(angle) * radius, height: sin(angle) * radius)
    }
}

private struct TopDownHighSpeedTrainShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.height * 0.30),
            control1: CGPoint(x: rect.width * 0.78, y: rect.height * 0.08),
            control2: CGPoint(x: rect.maxX, y: rect.height * 0.18)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.84))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.68, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.width * 0.32, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.height * 0.84),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.30))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.height * 0.18),
            control2: CGPoint(x: rect.width * 0.22, y: rect.height * 0.08)
        )
        path.closeSubpath()
        return path
    }
}

private struct TopDownTrainShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.height * 0.25),
            control1: CGPoint(x: rect.width * 0.76, y: rect.height * 0.04),
            control2: CGPoint(x: rect.maxX, y: rect.height * 0.12)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.82))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.72, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.width * 0.28, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.height * 0.82),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.25))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.height * 0.12),
            control2: CGPoint(x: rect.width * 0.24, y: rect.height * 0.04)
        )
        path.closeSubpath()
        return path
    }
}
