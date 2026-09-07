import SwiftUI

struct TopStatusHUD: View {
    @Bindable var session: GameSession
    let showLineDirectory: () -> Void
    let showGameMenu: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            networkIdentity

            Spacer(minLength: 2)

            Button {
                session.togglePlayPause()
            } label: {
                Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                    .font(.callout.weight(.bold))
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.isPlaying ? "Pause trains" : "Play trains")

            Button {
                session.toggleSimulationSpeed()
            } label: {
                Text(speedLabel)
                    .font(.caption.weight(.heavy).monospacedDigit())
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Simulation speed, \(speedLabel)")
            .accessibilityHint("Switches between normal and three times speed")

            Button(action: showGameMenu) {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.bold))
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Game menu, \(session.gameMode.title) mode")
        }
        .foregroundStyle(.primary)
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .padding(.vertical, 5)
        .railPanel(cornerRadius: 22)
    }

    @ViewBuilder
    private var networkIdentity: some View {
        if session.networkLineCount == 0 {
            ViewThatFits(in: .horizontal) {
                fullBrand
                RailwayGlyph()
            }
        } else {
            Button(action: showLineDirectory) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) {
                        fullBrand
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 5) {
                        RailwayGlyph()
                        Text(session.networkLineCount.formatted())
                            .font(.caption.weight(.black).monospacedDigit())
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!canShowLineDirectory)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(lineDirectoryAccessibilityLabel)
            .accessibilityHint(lineDirectoryAccessibilityHint)
        }
    }

    private var fullBrand: some View {
        HStack(spacing: 8) {
            RailwayGlyph()

            VStack(alignment: .leading, spacing: -1) {
                Text("TRAINTRACK TYCOON")
                    .font(.system(.caption2, design: .rounded, weight: .black))
                    .tracking(0.45)

                Text(statusText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .layoutPriority(1)
    }

    private var statusText: String {
        if case .constructing = session.phase {
            return "BUILDING LINE"
        }
        if !session.isPlaying, !session.trains.isEmpty {
            return "NETWORK PAUSED"
        }
        switch session.networkLineCount {
        case 0:
            return "SOUTH EAST POC"
        case 1:
            return passengerStatus(prefix: "1 LINE")
        default:
            return passengerStatus(prefix: "\(session.networkLineCount) LINES")
        }
    }

    private func passengerStatus(prefix: String) -> String {
        guard session.passengerSnapshot.passengersPerDay > 0 else {
            return "\(prefix) LIVE"
        }
        let passengers = session.passengerSnapshot.passengersPerDay.formatted(
            .number.notation(.compactName)
        )
        return "\(prefix) · \(passengers) RIDES/DAY"
    }

    private var speedLabel: String {
        switch session.simulationSpeed {
        case .oneX:
            "1×"
        case .threeX:
            "3×"
        }
    }

    private var canShowLineDirectory: Bool {
        !session.financeLedger.isBankrupt
            && GameRootPresentationPolicy.isNormalOperatingPhase(session.phase)
    }

    private var lineDirectoryAccessibilityLabel: String {
        let count = session.networkLineCount
        return "Browse \(count) line\(count == 1 ? "" : "s")"
    }

    private var lineDirectoryAccessibilityHint: String {
        canShowLineDirectory
            ? "Opens a list for selecting and framing a line on the map"
            : "Available when construction and route planning are complete"
    }

}

/// A thumb-reachable service picker that occupies only the existing bounded bottom-control area.
/// Rows use a stable number and operating symbol in addition to colour so identities survive
/// colour-vision differences and larger networks with a repeating map palette.
struct LineDirectoryPanel: View {
    let lines: [BuiltLine]
    var maximumHeight: CGFloat?
    let manageLine: (UUID) -> Void
    let close: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var isHeaderFocused: Bool

    var body: some View {
        VStack(spacing: 7) {
            VStack(alignment: .leading, spacing: 10) {
                header

                Text("Choose a service to frame it and open its controls.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(orderedLines) { line in
                            lineButton(
                                line,
                                number: LineIdentityPresentationPolicy.displayNumber(
                                    styleIndex: line.styleIndex
                                )
                            )
                        }
                    }
                }
                .scrollIndicators(linesContentHeight > listHeight ? .visible : .hidden)
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: listHeight)
            }
            .padding(.leading, 14)
            .padding(.trailing, 7)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .railPanel(cornerRadius: 20)
            .accessibilityElement(children: .contain)

            Link(destination: URL(string: "https://www.openstreetmap.org/copyright")!) {
                Text("Railway data © OpenStreetMap contributors")
                    .font(.caption2.weight(.medium))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: .capsule)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("OpenStreetMap data attribution")
        }
        .onAppear {
            isHeaderFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.headline.weight(.bold))
                .foregroundStyle(TycoonTheme.panelAccent)

            VStack(alignment: .leading, spacing: 1) {
                Text("Your lines")
                    .font(.headline.weight(.bold))
                Text("\(lines.count) active service\(lines.count == 1 ? "" : "s")")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityFocused($isHeaderFocused)

            Spacer(minLength: 4)

            Button("Done", action: close)
                .font(.subheadline.weight(.bold))
                .frame(minWidth: 56, minHeight: 44)
                .contentShape(.rect)
                .accessibilityHint("Closes the line list")
        }
    }

    private func lineButton(_ line: BuiltLine, number: Int) -> some View {
        let color = TycoonTheme.lineColor(for: line.styleIndex)

        return Button {
            manageLine(line.id)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(color)
                    Text(number.formatted())
                        .font(.caption.weight(.black).monospacedDigit())
                        .foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)
                .overlay {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.74), lineWidth: 1.5)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(line.origin.name) → \(line.destination.name)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 5) {
                            Label(lineStatus(line), systemImage: lineStatusSymbol(line))
                            Text("·")
                            Text(stopCount(line))
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Label(lineStatus(line), systemImage: lineStatusSymbol(line))
                            Text(stopCount(line))
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Image(systemName: "slider.horizontal.3")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background(
                Color.secondary.opacity(0.07),
                in: .rect(cornerRadius: 13, style: .continuous)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Line \(number), \(line.origin.name) to \(line.destination.name)"
        )
        .accessibilityValue("\(lineStatus(line)), \(stopCount(line))")
        .accessibilityHint("Frames this line on the map and opens its service controls")
    }

    private var orderedLines: [BuiltLine] {
        lines.sorted { lhs, rhs in
            if lhs.styleIndex != rhs.styleIndex {
                return lhs.styleIndex < rhs.styleIndex
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private var listHeight: CGFloat {
        let contentHeight = linesContentHeight
        guard let maximumHeight else { return contentHeight }
        let nonListHeight: CGFloat = dynamicTypeSize.isAccessibilitySize ? 217 : 160
        let availableHeight = max(maximumHeight - nonListHeight, estimatedRowHeight)
        return min(contentHeight, availableHeight)
    }

    private var linesContentHeight: CGFloat {
        CGFloat(max(lines.count, 1)) * estimatedRowHeight
    }

    private var estimatedRowHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 124 : 62
    }

    private func lineStatus(_ line: BuiltLine) -> String {
        guard line.isConstructed else {
            return "Building \(line.constructionProgress.formatted(.percent.precision(.fractionLength(0))))"
        }
        if line.railwayClass == .highSpeed {
            return "High speed · \(line.serviceFrequency.name)"
        }
        if usesCustomServicePlans(line) {
            return "Custom mix · \(line.serviceFrequency.name)"
        }
        return "\(line.servicePattern.name) · \(line.serviceFrequency.name)"
    }

    private func lineStatusSymbol(_ line: BuiltLine) -> String {
        if !line.isConstructed { return "hammer.fill" }
        if line.railwayClass == .highSpeed { return "bolt.fill" }
        if usesCustomServicePlans(line) { return "slider.horizontal.3" }
        return switch line.servicePattern {
        case .local: "l.circle.fill"
        case .balanced: "b.circle.fill"
        case .express: "e.circle.fill"
        }
    }

    private func stopCount(_ line: BuiltLine) -> String {
        let count = max(line.stationCRSs.count, 2)
        return "\(count) built station\(count == 1 ? "" : "s")"
    }

    private func usesCustomServicePlans(_ line: BuiltLine) -> Bool {
        line.trainServicePlans != TrainServicePlan.legacyDefaults(
            servicePattern: line.servicePattern,
            serviceStationCRSs: line.stationCRSs
        )
    }
}

struct GameMenuOverlay: View {
    let currentMode: GameMode
    let showProgress: () -> Void
    let showSettings: () -> Void
    let startNewGame: (GameMode) -> Void
    let cancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            ScrollView {
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        RailwayGlyph()

                        VStack(alignment: .leading, spacing: 2) {
                            Text("GAME MENU")
                                .font(.caption.weight(.black))
                                .tracking(0.55)
                            Label(
                                "Currently playing \(currentMode.title) mode",
                                systemImage: currentMode == .career
                                    ? "briefcase.fill"
                                    : "infinity"
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                    }

                    Divider()

                    VStack(spacing: 8) {
                        menuButton(
                            title: "Progress & scenarios",
                            detail: "Achievements, challenges and statistics",
                            systemImage: "trophy.fill",
                            action: showProgress
                        )
                        menuButton(
                            title: "Settings & guide",
                            detail: "Sound, atmosphere and quick start",
                            systemImage: "gearshape.fill",
                            action: showSettings
                        )
                    }

                    Divider()

                    Text("NEW GAME")
                        .font(.caption2.weight(.black))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 10) {
                        newGameButton(for: .career)
                        newGameButton(for: .zen)
                    }

                    Button("Cancel", action: cancel)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .buttonStyle(.bordered)
                }
                .padding(20)
            }
            .frame(maxWidth: 360)
            .frame(maxHeight: 650)
            .scrollBounceBehavior(.basedOnSize)
            .railPanel(cornerRadius: 24)
            .padding(.horizontal, 24)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }

    private func menuButton(
        title: String,
        detail: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(TycoonTheme.railGreen)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Color.secondary.opacity(0.075), in: .rect(cornerRadius: 14))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private func newGameButton(for mode: GameMode) -> some View {
        Button(role: .destructive) {
            startNewGame(mode)
        } label: {
            HStack(spacing: 12) {
                Image(
                    systemName: mode == .career
                        ? "sterlingsign.circle.fill"
                        : "infinity.circle.fill"
                )
                .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("New \(mode.title) Game")
                        .font(.headline)
                    Text(mode.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Color.red.opacity(0.10), in: .rect(cornerRadius: 14))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

struct NewGameConfirmationOverlay: View {
    let mode: GameMode
    let confirm: () -> Void
    let cancel: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack {
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 18) {
                Image(systemName: mode == .career ? "sterlingsign.circle.fill" : "infinity.circle.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(TycoonTheme.construction)
                    .accessibilityHidden(true)

                VStack(spacing: 7) {
                    Text("Start a new game?")
                        .font(.title3.weight(.bold))

                    Text(
                        "Your railway, finances and progress will be replaced. "
                            + mode.subtitle + "."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    Button(role: .destructive, action: confirm) {
                        Text("Start \(mode.title) Game")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)

                    Button("Cancel", action: cancel)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .buttonStyle(.bordered)
                }
            }
            .padding(dynamicTypeSize.isAccessibilitySize ? 20 : 24)
            .frame(maxWidth: 360)
            .railPanel(cornerRadius: 24)
            .padding(.horizontal, 24)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }
}

struct StationUpgradeBanner: View {
    let event: StationUpgradeEvent
    let dismiss: () -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "building.2.crop.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(TycoonTheme.panelAccent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("STATION UPGRADED")
                    .font(.caption2.weight(.black))
                    .tracking(0.55)
                    .foregroundStyle(TycoonTheme.panelAccent)
                Text("\(event.stationName) is now a \(event.level.displayName)")
                    .font(.subheadline.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(
                    "\(event.level.platformCount) platforms · "
                        + "\(trainCallCapacityPerHour.formatted()) calls/hour"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss station upgrade")
        }
        .padding(.leading, 14)
        .padding(.trailing, 5)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .railPanel(cornerRadius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Station upgraded. \(event.stationName) is now a "
                + "\(event.level.displayName) with \(event.level.platformCount) platforms and "
                + "capacity for \(trainCallCapacityPerHour.formatted()) train calls per hour."
        )
        .task(id: event.id) {
            // Keep the notice available for deliberate VoiceOver navigation. Reduce Motion only
            // changes its transition; it should not change how long the information remains.
            guard !voiceOverEnabled else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    private var trainCallCapacityPerHour: Int {
        Int(
            (Double(event.level.platformCount)
                * StationCapacityConfiguration.poc.trainCallsPerPlatformPerHour).rounded()
        )
    }
}

private struct FleetPresetResetRequest: Identifiable {
    let lineID: UUID
    let pattern: ServicePattern

    var id: String { "\(lineID.uuidString)|\(pattern.rawValue)" }
}

struct BottomControlPanel: View {
    @Bindable var session: GameSession
    @Binding var showsHappinessHeatmap: Bool
    @Binding var isShowingNetworkPerformance: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var accessibilityFocus: BottomPanelPresentation?
    @State private var networkDashboardSection: NetworkDashboardSection = .finance
    @State private var isConfirmingBankruptcyReset = false
    @State private var bankruptcyResetMode: GameMode = .career
    @State private var isEditingPreviewCallingPoints = false
    @State private var editingServicePlanTrainID: UUID?
    @State private var pendingFleetPresetReset: FleetPresetResetRequest?
    @State private var isFindingBuildStation = false

    var body: some View {
        VStack(spacing: 7) {
            if presentation == .build, session.networkLineCount > 0 {
                networkPulse
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Group {
                switch presentation {
                case .build:
                    if BottomPanelPresentationPolicy.showsBuildAction(
                        for: presentation,
                        canBuildAnotherLine: session.canBuildAnotherLine
                    ) {
                        buildButton
                    }
                case .origin:
                    BuildGuidanceCard(
                        step: 1,
                        title: "Choose a starting station",
                        message: "Tap a nearby marker or search all Great Britain stations.",
                        findStation: { isFindingBuildStation = true },
                        cancel: session.cancelBuild
                    )
                case .destination:
                    BuildGuidanceCard(
                        step: 2,
                        title: "Where should the line go?",
                        message: session.selectedOrigin.map { "Starting at \($0.name)" }
                            ?? "Tap a marker or search for a destination.",
                        findStation: { isFindingBuildStation = true },
                        cancel: session.cancelBuild
                    )
                case .calculating:
                    calculatingCard
                case .preview:
                    previewCard
                case .constructing:
                    constructionCard
                case .train(let id):
                    trainPresentation(id: id)
                case .station(let crs):
                    stationCard(crs: crs)
                case .network:
                    networkPerformanceCard
                case .bankrupt:
                    bankruptcyCard
                case .error:
                    errorCard
                }
            }
            .id(presentation)
            .transition(.move(edge: .bottom).combined(with: .opacity))

            Link(destination: URL(string: "https://www.openstreetmap.org/copyright")!) {
                Text("Railway data © OpenStreetMap contributors")
                    .font(.caption2.weight(.medium))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: .capsule)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("OpenStreetMap data attribution")
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.26), value: presentation)
        .onChange(of: presentation) { _, newPresentation in
            if newPresentation != .origin, newPresentation != .destination {
                isFindingBuildStation = false
            }
            if newPresentation != .preview {
                isEditingPreviewCallingPoints = false
            }
            if case .train(let trainID) = newPresentation {
                if editingServicePlanTrainID != trainID {
                    editingServicePlanTrainID = nil
                }
            } else {
                editingServicePlanTrainID = nil
            }
            switch newPresentation {
            case .train, .station, .network:
                accessibilityFocus = newPresentation
            default:
                accessibilityFocus = nil
            }
        }
        .onChange(of: session.networkLineCount == 0) { _, isEmpty in
            guard isEmpty else { return }
            isShowingNetworkPerformance = false
            showsHappinessHeatmap = false
        }
        .onChange(of: isShowingNetworkPerformance) { _, isShowing in
            guard isShowing else { return }
            networkDashboardSection = .finance
        }
        .onChange(of: session.preview?.railwayClass) { _, railwayClass in
            if railwayClass == .highSpeed {
                isEditingPreviewCallingPoints = false
            }
        }
        .confirmationDialog(
            "Start a new \(bankruptcyResetMode.title) game?",
            isPresented: $isConfirmingBankruptcyReset,
            titleVisibility: .visible
        ) {
            Button("Start \(bankruptcyResetMode.title) Game", role: .destructive) {
                session.reset(gameMode: bankruptcyResetMode)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your bankrupt company and current railway will be replaced.")
        }
        .confirmationDialog(
            "Apply \(pendingFleetPresetReset?.pattern.name ?? "fleet") preset?",
            isPresented: Binding(
                get: { pendingFleetPresetReset != nil },
                set: { if !$0 { pendingFleetPresetReset = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let request = pendingFleetPresetReset {
                Button("Apply \(request.pattern.name) to every train") {
                    session.setServicePattern(request.pattern, forLineID: request.lineID)
                    pendingFleetPresetReset = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingFleetPresetReset = nil
            }
        } message: {
            Text("This replaces the custom terminals and calls saved for all four timetable slots.")
        }
        .sheet(isPresented: $isFindingBuildStation) {
            StationFinderView(
                title: presentation == .destination
                    ? "Choose destination"
                    : "Choose starting station",
                stations: session.stations,
                eligibleStationCRSs: session.eligibleBuildStationCRSs,
                isLoadingEligibility: session.isLoadingBuildStationEligibility,
                excludedStationCRS: presentation == .destination
                    ? session.selectedOrigin?.crs
                    : nil
            ) { station in
                session.selectStation(station)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func trainPresentation(id: UUID) -> some View {
        if editingServicePlanTrainID == id,
           let train = session.trains.first(where: { $0.id == id }),
           let line = session.lines.first(where: { $0.id == train.lineID }),
           let plan = session.trainServicePlan(for: id) {
            TrainStoppingPlanEditor(
                availableStations: session.serviceStations(forLineID: line.id).map {
                    (crs: $0.crs, name: $0.name)
                },
                plan: plan,
                trainNumber: (line.trains.firstIndex(where: { $0.id == id }) ?? 0) + 1,
                maximumCallCount: session.maximumServiceCallCount,
                validationMessage: { candidate in
                    session.servicePlanValidationMessage(candidate, forTrainID: id)
                },
                onCancel: {
                    editingServicePlanTrainID = nil
                },
                onSave: { updatedPlan in
                    if session.setTrainServicePlan(updatedPlan, forTrainID: id) {
                        editingServicePlanTrainID = nil
                    }
                }
            )
        } else {
            trainCard(id: id)
        }
    }

    private var networkPulse: some View {
        let operatingDay = session.economyLedger.completedOperatingDays == .max
            ? UInt64.max
            : session.economyLedger.completedOperatingDays + 1
        let finance = session.financeSnapshot
        let balanceTitle = session.gameMode == .career ? "Cash" : "Budget"
        let balanceValue = session.gameMode == .career
            ? formattedPence(session.financeLedger.cashBalancePence)
            : "Unlimited"
        let projectionTitle = session.gameMode == .career
            ? "Cash change/day"
            : "Result/day"
        let projectionValue = formattedPence(
            session.gameMode == .career
                ? finance.projectedCashChangePencePerDay
                : finance.projectedProfitPencePerDay
        )
        let populationValue = PopulationUIPresentation.compactPopulation(
            session.networkPopulation
        )
        let populationChange = PopulationUIPresentation.compactChange(
            session.latestNetworkPopulationChange
        )

        return Button {
            networkDashboardSection = .finance
            isShowingNetworkPerformance = true
        } label: {
            VStack(spacing: 7) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 8) {
                            NetworkPulseMetric(
                                title: balanceTitle,
                                value: balanceValue,
                                systemImage: session.gameMode == .career
                                    ? "banknote.fill"
                                    : "infinity",
                                isRow: true
                            )
                            NetworkPulseMetric(
                                title: projectionTitle,
                                value: projectionValue,
                                systemImage: "plusminus.circle.fill",
                                isRow: true
                            )
                            NetworkPulseMetric(
                                title: "Gross network value",
                                value: formattedPence(finance.networkValuePence),
                                systemImage: "building.columns.fill",
                                isRow: true
                            )
                        }
                    } else {
                        HStack(spacing: 0) {
                            NetworkPulseMetric(
                                title: balanceTitle,
                                value: balanceValue,
                                systemImage: session.gameMode == .career
                                    ? "banknote.fill"
                                    : "infinity"
                            )

                            Divider().frame(height: 30)

                            NetworkPulseMetric(
                                title: projectionTitle,
                                value: projectionValue,
                                systemImage: "plusminus.circle.fill"
                            )

                            Divider().frame(height: 30)

                            NetworkPulseMetric(
                                title: "Network value",
                                value: formattedPence(finance.networkValuePence),
                                systemImage: "building.columns.fill"
                            )
                        }
                    }
                }

                Divider()

                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 8) {
                            NetworkPulseMetric(
                                title: "Network happiness",
                                value: formattedHappinessScore(
                                    session.happinessSnapshot.globalHappinessScore
                                ),
                                systemImage: "heart.fill",
                                isRow: true
                            )
                            NetworkPulseMetric(
                                title: "Passengers / day",
                                value: formattedPassengerCount(
                                    session.passengerSnapshot.passengersPerDay
                                ),
                                systemImage: "person.2.fill",
                                isRow: true
                            )
                            NetworkPulseMetric(
                                title: "Synthetic gameplay population",
                                value: "\(populationValue) · \(populationChange)",
                                systemImage: "house.fill",
                                isRow: true
                            )
                            NetworkPulseMetric(
                                title: "High-speed prestige",
                                value: "\(session.prestigeSnapshot.score)/100",
                                systemImage: "star.fill",
                                isRow: true
                            )
                        }
                    } else {
                        HStack(spacing: 8) {
                            Label(
                                formattedHappinessScore(
                                    session.happinessSnapshot.globalHappinessScore
                                ),
                                systemImage: "heart.fill"
                            )
                            Label(
                                formattedPassengerCount(
                                    session.passengerSnapshot.passengersPerDay
                                ) + "/day",
                                systemImage: "person.2.fill"
                            )
                            Label(
                                "\(session.prestigeSnapshot.score)",
                                systemImage: "star.fill"
                            )
                            Spacer(minLength: 4)
                            Label(
                                "GAME POP \(populationValue) · \(populationChange)",
                                systemImage: "house.fill"
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.70)
                        }
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Text("DAY \(operatingDay) · LIFETIME RESULT")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Text(
                        formattedPence(session.economyLedger.lifetimeOperatingResultPence)
                    )
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .railPanel(cornerRadius: 18)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Network summary")
        .accessibilityValue(networkSummaryAccessibilityValue)
        .accessibilityHint("Opens network performance details")
    }

    private var buildButton: some View {
        Button {
            session.startBuilding()
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(
                            "Build a line",
                            systemImage: "plus"
                        )
                        .font(.headline.weight(.bold))

                        Text(buildButtonSubtitle)
                            .font(.caption)
                            .opacity(0.78)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.headline.weight(.black))

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Build a line")
                            .font(.headline.weight(.bold))
                            Text(buildButtonSubtitle)
                                .font(.caption)
                                .opacity(0.78)
                        }

                        Spacer()

                        Image(systemName: "arrow.up.right")
                            .font(.subheadline.weight(.bold))
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(
                TycoonTheme.railGreen,
                in: .rect(cornerRadius: 21, style: .continuous)
            )
            .shadow(color: TycoonTheme.ink.opacity(0.24), radius: 14, y: 7)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Starts the two-step station selection")
    }

    private var buildButtonSubtitle: String {
        switch session.networkLineCount {
        case 0:
            "Connect two real stations"
        case 1:
            "Add one more test service"
        default:
            "Expand your railway network"
        }
    }

    private var calculatingCard: some View {
        HStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(TycoonTheme.railGreen)

            VStack(alignment: .leading, spacing: 3) {
                Text("Finding the railway path")
                    .font(.headline)
                Text(routeSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            }

            Spacer(minLength: 4)

            Button("Cancel") {
                session.cancelBuild()
            }
            .buttonStyle(.borderless)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .railPanel()
    }

    @ViewBuilder
    private var previewCard: some View {
        if let preview = session.preview {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top, spacing: 10) {
                    RouteSignalView()

                    VStack(alignment: .leading, spacing: 3) {
                        Text(preview.origin.name)
                            .font(.headline)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        Text(preview.destination.name)
                            .font(.headline)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    }

                    Spacer(minLength: 4)

                    Text(preview.railwayClass == .highSpeed ? "HIGH SPEED" : "PREVIEW")
                        .font(.caption2.weight(.black))
                        .tracking(0.8)
                        .foregroundStyle(
                            preview.railwayClass == .highSpeed
                                ? TycoonTheme.highSpeedViolet
                                : TycoonTheme.railGreen
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            (preview.railwayClass == .highSpeed
                                ? TycoonTheme.highSpeedViolet
                                : TycoonTheme.railGreen).opacity(0.12),
                            in: .capsule
                        )
                }

                railwayClassPreviewControl(preview)

                if preview.railwayClass == .conventional {
                    PreviewCallingPointsSection(
                        origin: preview.origin,
                        destination: preview.destination,
                        intermediateStations: session.previewIntermediateStations,
                        selectedStationCRSs: session.previewSelectedStationCRSs,
                        maximumStopCount: session.maximumServiceCallCount,
                        isUpdatingRoute: session.isUpdatingPreviewRoute,
                        isExpanded: $isEditingPreviewCallingPoints,
                        toggleIntermediateStation: session.togglePreviewIntermediateStation
                    )
                } else {
                    Label(
                        "Dedicated high-speed services call at their two endpoints. Custom stopping patterns arrive in a later milestone.",
                        systemImage: "bolt.horizontal.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 13))
                    .accessibilityElement(children: .combine)
                }

                rollingStockPreviewControl(preview)

                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 10) {
                            PreviewMetric(
                                title: "Route length",
                                value: formattedDistance(preview.distanceKilometres),
                                systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                            )
                            PreviewMetric(
                                title: "Total upfront",
                                value: formattedPence(
                                    session.previewCapitalQuote?.totalPence
                                        ?? preview.indicativeCost * 100
                                ),
                                systemImage: "sterlingsign.circle"
                            )
                        }
                    } else {
                        HStack(spacing: 0) {
                            PreviewMetric(
                                title: "Route length",
                                value: formattedDistance(preview.distanceKilometres),
                                systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Divider()
                                .frame(height: 34)

                            PreviewMetric(
                                title: "Total upfront",
                                value: formattedPence(
                                    session.previewCapitalQuote?.totalPence
                                        ?? preview.indicativeCost * 100
                                ),
                                systemImage: "sterlingsign.circle"
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 14)
                        }
                    }
                }

                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 5) {
                            Label("Estimated passenger demand", systemImage: "person.2.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(
                                formattedPassengerCount(
                                    preview.passengerEstimate.potentialDailyJourneys
                                ) + " / day"
                            )
                            .font(.subheadline.weight(.bold).monospacedDigit())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        HStack(spacing: 9) {
                            Image(systemName: "person.2.fill")
                                .foregroundStyle(TycoonTheme.railGreen)
                            Text("Estimated passenger demand")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 6)
                            Text(
                                formattedPassengerCount(
                                    preview.passengerEstimate.potentialDailyJourneys
                                ) + " / day"
                            )
                            .font(.subheadline.weight(.bold).monospacedDigit())
                        }
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(TycoonTheme.railGreen.opacity(0.09), in: .capsule)
                .accessibilityElement(children: .combine)

                if let quote = session.previewCapitalQuote {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("UPFRONT INVESTMENT")
                            .font(.caption2.weight(.black))
                            .tracking(0.55)
                            .foregroundStyle(.secondary)

                        FinanceBreakdownRow(
                            title: preview.railwayClass == .highSpeed
                                ? "Dedicated high-speed track"
                                : "Track and infrastructure",
                            value: formattedPence(quote.trackAndInfrastructurePence)
                        )
                        FinanceBreakdownRow(
                            title: preview.railwayClass == .highSpeed
                                ? "Premium station facilities"
                                : "Station construction",
                            value: formattedPence(quote.stationConstructionPence)
                        )
                        FinanceBreakdownRow(
                            title: preview.railwayClass == .highSpeed
                                ? "215 mph train fleet"
                                : "Initial train fleet",
                            value: formattedPence(quote.rollingStockPence)
                        )

                        if let highSpeedQuote = session.previewHighSpeedInvestmentQuote {
                            FinanceBreakdownRow(
                                title: "Conventional track reference",
                                value: formattedPence(
                                    highSpeedQuote.conventionalTrackReferencePence
                                )
                            )
                            FinanceBreakdownRow(
                                title: "Prestige on completion",
                                value: "+\(session.previewProjectedPrestigeGain)"
                            )
                        }

                        Divider()

                        FinanceBreakdownRow(
                            title: "Total upfront",
                            value: formattedPence(quote.totalPence),
                            emphasis: true
                        )
                        FinanceBreakdownRow(
                            title: "Available balance",
                            value: session.gameMode == .career
                                ? formattedPence(session.financeLedger.cashBalancePence)
                                : "Unlimited",
                            emphasis: true
                        )

                        if session.gameMode == .career {
                            let shortfall = session.previewFundingShortfallPence

                            FinanceBreakdownRow(
                                title: "Funding shortfall",
                                value: shortfall > 0 ? formattedPence(shortfall) : "Fully funded",
                                emphasis: shortfall > 0,
                                isWarning: shortfall > 0
                            )

                            Button {
                                _ = session.takeStandardLoan()
                            } label: {
                                VStack(spacing: 2) {
                                    Label(
                                        "Borrow \(formattedPence(session.standardLoanPence))",
                                        systemImage: "building.columns.fill"
                                    )
                                    Text(standardLoanTermsSummary)
                                        .font(.caption2.weight(.semibold))
                                        .opacity(0.78)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .disabled(!session.financeSnapshot.canBorrow)
                            .accessibilityHint(
                                session.financeSnapshot.canBorrow
                                    ? standardLoanAccessibilityHint
                                    : "No further standard loans are available"
                            )
                        }
                    }
                    .padding(11)
                    .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 12))
                    .accessibilityElement(children: .contain)
                }

                HStack(spacing: 10) {
                    Button("Cancel") {
                        session.cancelBuild()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        session.confirmPreview()
                    } label: {
                        Group {
                            if session.isUpdatingPreviewRoute {
                                Label("Updating route", systemImage: "arrow.triangle.2.circlepath")
                            } else {
                                Label(
                                    preview.railwayClass == .highSpeed
                                        ? "Build high-speed"
                                        : "Build line",
                                    systemImage: preview.railwayClass == .highSpeed
                                        ? "bolt.fill"
                                        : "checkmark"
                                )
                            }
                        }
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(
                        preview.railwayClass == .highSpeed
                            ? TycoonTheme.highSpeedViolet
                            : TycoonTheme.railGreen
                    )
                    .disabled(
                        !session.canConfirmPreview
                            || (session.gameMode == .career && !session.canAffordPreview)
                    )
                    .accessibilityHint(
                        session.isUpdatingPreviewRoute
                            ? "Wait while the selected station calls are applied"
                            : session.gameMode == .career && !session.canAffordPreview
                                ? "Borrow enough funding before building this line"
                                : "Pays the upfront cost and begins construction"
                    )
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .railPanel()
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private func railwayClassPreviewControl(_ preview: LinePreview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 6) {
                    ForEach(RailwayClass.allCases) { railwayClass in
                        Button {
                            session.setPreviewRailwayClass(railwayClass)
                        } label: {
                            HStack(spacing: 9) {
                                Text(railwayClass.compactSymbol)
                                    .font(.caption.weight(.black))
                                    .frame(width: 26, height: 26)
                                    .foregroundStyle(
                                        railwayClass == preview.railwayClass
                                            ? .white
                                            : .primary
                                    )
                                    .background(
                                        railwayClass == preview.railwayClass
                                            ? railwayClass == .highSpeed
                                                ? TycoonTheme.highSpeedViolet
                                                : TycoonTheme.railGreen
                                            : Color.secondary.opacity(0.15),
                                        in: .circle
                                    )
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(railwayClass.name)
                                        .font(.caption.weight(.bold))
                                    Text(
                                        railwayClass == .highSpeed
                                            ? "Dedicated fast railway, premium stations and trains"
                                            : "Classic railway with flexible stopping patterns"
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                if railwayClass == preview.railwayClass {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(
                            railwayClass == preview.railwayClass ? .isSelected : []
                        )
                    }
                }
            } else {
                Picker(
                    "Railway class",
                    selection: Binding(
                        get: { preview.railwayClass },
                        set: { session.setPreviewRailwayClass($0) }
                    )
                ) {
                    ForEach(RailwayClass.allCases) { railwayClass in
                        Text(railwayClass.name).tag(railwayClass)
                    }
                }
                .pickerStyle(.segmented)
            }

            if preview.railwayClass == .highSpeed {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(TycoonTheme.highSpeedGold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("A transformational 215 mph corridor")
                            .font(.caption.weight(.bold))
                        Text(
                            "Dedicated infrastructure, two premium endpoint facilities, "
                                + "high-speed trainsets and premium fares. "
                                + "Estimated journey: "
                                + formattedMinutes(session.previewEstimatedJourneyMinutes ?? 0)
                                + "."
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .background(
                    TycoonTheme.highSpeedViolet.opacity(0.11),
                    in: .rect(cornerRadius: 11)
                )
                .accessibilityElement(children: .combine)
            } else {
                Text("Flexible Local, Balanced and Express operation on upgradeable track.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(session.isUpdatingPreviewRoute)
        .accessibilityHint(
            session.isUpdatingPreviewRoute
                ? "Available when the selected station calls finish updating"
                : ""
        )
    }

    private func rollingStockPreviewControl(_ preview: LinePreview) -> some View {
        let formations = RollingStockFormation.supported(for: preview.railwayClass)
        let currentIndex = formations.firstIndex(of: preview.formation) ?? 0
        let recommendationMatches = preview.formation == preview.recommendedFormation

        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Train formation", systemImage: "tram.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TycoonTheme.panelAccent)

                Spacer(minLength: 4)

                if recommendationMatches {
                    Text("RECOMMENDED")
                        .font(.caption2.weight(.black))
                        .tracking(0.35)
                        .foregroundStyle(TycoonTheme.panelAccent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            TycoonTheme.panelAccent.opacity(0.12),
                            in: .capsule
                        )
                }
            }

            Stepper(
                value: Binding(
                    get: { currentIndex },
                    set: { newIndex in
                        guard formations.indices.contains(newIndex) else { return }
                        session.setPreviewFormation(formations[newIndex])
                    }
                ),
                in: 0...max(formations.count - 1, 0)
            ) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 2) {
                            formationTitle(preview.formation)
                            formationCapacityLabel(preview.formation)
                        }
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                formationTitle(preview.formation)
                                Spacer(minLength: 4)
                                formationCapacityLabel(preview.formation)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                formationTitle(preview.formation)
                                formationCapacityLabel(preview.formation)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityLabel("Train length")
            .accessibilityValue(
                "\(preview.formation.carriageCount) cars, "
                    + "\(preview.formation.seatsPerTrain) seats per train"
            )
            .accessibilityHint(
                "Adjusts every train in the initial fleet by two cars and updates capacity, "
                    + "cost and the passenger forecast"
            )

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 6) {
                        PassengerCardMetric(
                            title: "Projected peak load",
                            value: preview.passengerEstimate.peakOccupancyRatio.formatted(
                                .percent.precision(.fractionLength(0))
                            ),
                            isRow: true
                        )
                        PassengerCardMetric(
                            title: "Seats across the day",
                            value: formattedPassengerCount(
                                preview.passengerEstimate.dailyCapacity
                            ),
                            isRow: true
                        )
                        PassengerCardMetric(
                            title: "Unserved journeys/day",
                            value: formattedPassengerCount(
                                preview.passengerEstimate.unservedDailyJourneys
                            ),
                            isRow: true
                        )
                    }
                } else {
                    HStack(spacing: 0) {
                        PassengerCardMetric(
                            title: "Peak load",
                            value: preview.passengerEstimate.peakOccupancyRatio.formatted(
                                .percent.precision(.fractionLength(0))
                            )
                        )
                        Divider().frame(height: 30)
                        PassengerCardMetric(
                            title: "Seats/day",
                            value: formattedPassengerCount(
                                preview.passengerEstimate.dailyCapacity
                            )
                        )
                        Divider().frame(height: 30)
                        PassengerCardMetric(
                            title: "Unserved/day",
                            value: formattedPassengerCount(
                                preview.passengerEstimate.unservedDailyJourneys
                            )
                        )
                    }
                }
            }

            Text(formationRecommendationMessage(for: preview))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .disabled(session.isUpdatingPreviewRoute)
        .accessibilityHint(
            session.isUpdatingPreviewRoute
                ? "Available when the selected station calls finish updating"
                : ""
        )
    }

    private func formationTitle(_ formation: RollingStockFormation) -> some View {
        Text("\(formation.carriageCount)-car trains")
            .font(.subheadline.weight(.bold).monospacedDigit())
    }

    private func formationCapacityLabel(_ formation: RollingStockFormation) -> some View {
        Text("\(formation.seatsPerTrain) seats each")
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private func formationRecommendationMessage(for preview: LinePreview) -> String {
        let recommended = preview.recommendedFormation
        if preview.formation == recommended {
            return "Matches the recommendation for this route and its opening timetable."
        }
        return "Recommended: \(recommended.carriageCount) cars and "
            + "\(recommended.seatsPerTrain) seats per train for this opening timetable."
    }

    private var constructionCard: some View {
        let line = session.lines.last
        let progress = line?.constructionProgress ?? 0

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        line?.railwayClass == .highSpeed
                            ? "Building a high-speed landmark"
                            : "Bringing the line to life"
                    )
                        .font(.headline)
                    Text(line.map { "\($0.origin.name) to \($0.destination.name)" } ?? routeSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                }

                Spacer()

                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(
                        line?.railwayClass == .highSpeed
                            ? TycoonTheme.highSpeedViolet
                            : TycoonTheme.railGreen
                    )
                    .accessibilityLabel("Construction progress")
            }

            ProgressView(value: progress)
                .tint(
                    line?.railwayClass == .highSpeed
                        ? TycoonTheme.highSpeedViolet
                        : TycoonTheme.lineColor(for: line?.styleIndex ?? 0)
                )
                .scaleEffect(x: 1, y: 1.45, anchor: .center)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .railPanel()
    }

    private var networkPerformanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            networkDashboardHeader

            Picker("Network dashboard", selection: $networkDashboardSection) {
                ForEach(NetworkDashboardSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityHint(
                "Switches between financial, happiness and high-speed prestige performance"
            )

            switch networkDashboardSection {
            case .finance:
                financeDashboardContent
            case .happiness:
                happinessDashboardContent
            case .prestige:
                prestigeDashboardContent
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .railPanel()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var financeDashboardContent: some View {
        let operating = session.economySnapshot
        let finance = session.financeSnapshot

        VStack(alignment: .leading, spacing: 12) {
            financeHealthBanner(finance.financialHealth)

            VStack(alignment: .leading, spacing: 7) {
                financeSectionTitle("Daily forecast")
                FinanceBreakdownRow(
                    title: "Passenger fares",
                    value: formattedPence(operating.totalRevenuePencePerDay)
                )
                if operating.totalHighSpeedFarePremiumPencePerDay > 0 {
                    FinanceBreakdownRow(
                        title: "Included high-speed premium",
                        value: "+" + formattedPence(
                            operating.totalHighSpeedFarePremiumPencePerDay
                        )
                    )
                }
                FinanceBreakdownRow(
                    title: "Energy",
                    value: formattedExpense(operating.totalEnergyCostPencePerDay)
                )
                FinanceBreakdownRow(
                    title: "Rolling stock maintenance",
                    value: formattedExpense(
                        operating.totalRollingStockMaintenanceCostPencePerDay
                    )
                )
                FinanceBreakdownRow(
                    title: "Track maintenance",
                    value: formattedExpense(operating.totalTrackUpkeepPencePerDay)
                )
                FinanceBreakdownRow(
                    title: "Station maintenance",
                    value: formattedExpense(operating.stationUpkeepPencePerDay)
                )
                if operating.premiumStationUpkeepPencePerDay > 0 {
                    FinanceBreakdownRow(
                        title: "Included premium-station upkeep",
                        value: formattedExpense(
                            operating.premiumStationUpkeepPencePerDay
                        )
                    )
                }

                Divider()

                FinanceBreakdownRow(
                    title: "Operating result",
                    value: formattedPence(operating.operatingResultPencePerDay),
                    emphasis: true,
                    isWarning: operating.operatingResultPencePerDay < 0
                )
                FinanceBreakdownRow(
                    title: "Loan interest",
                    value: formattedExpense(finance.projectedInterestPencePerDay)
                )
                FinanceBreakdownRow(
                    title: "Profit after interest",
                    value: formattedPence(finance.projectedProfitPencePerDay),
                    emphasis: true,
                    isWarning: finance.projectedProfitPencePerDay < 0
                )
                FinanceBreakdownRow(
                    title: "Loan principal",
                    value: formattedExpense(
                        finance.projectedPrincipalRepaymentPencePerDay
                    )
                )
                FinanceBreakdownRow(
                    title: session.gameMode == .career
                        ? "Projected cash change"
                        : "Projected result",
                    value: formattedPence(
                        session.gameMode == .career
                            ? finance.projectedCashChangePencePerDay
                            : finance.projectedProfitPencePerDay
                    ),
                    emphasis: true,
                    isWarning: finance.projectedCashChangePencePerDay < 0
                )
            }
            .financeSectionSurface()

            VStack(alignment: .leading, spacing: 7) {
                financeSectionTitle("Company value")
                FinanceBreakdownRow(
                    title: "Gross network value",
                    value: formattedPence(finance.networkValuePence)
                )
                FinanceBreakdownRow(
                    title: "Outstanding debt",
                    value: formattedExpense(finance.outstandingDebtPence)
                )
                FinanceBreakdownRow(
                    title: "Net company value",
                    value: formattedPence(finance.netCompanyValuePence),
                    emphasis: true,
                    isWarning: finance.netCompanyValuePence < 0
                )
                FinanceBreakdownRow(
                    title: "Commercial viability",
                    value: finance.commercialViability.label,
                    emphasis: true,
                    isWarning: finance.commercialViability == .lossMaking
                )
            }
            .financeSectionSurface()

            VStack(alignment: .leading, spacing: 7) {
                financeSectionTitle("Lifetime tracked")
                if session.financeLedger.hasIncompleteCapitalHistory {
                    Text(
                        incompleteCapitalHistoryDisclosure
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(
                        incompleteCapitalHistoryAccessibilityDisclosure
                    )
                }
                FinanceBreakdownRow(
                    title: "Capital investment",
                    value: formattedPence(session.financeLedger.lifetimeCapitalSpendPence)
                )
                FinanceBreakdownRow(
                    title: "Construction",
                    value: formattedPence(
                        session.financeLedger.lifetimeConstructionSpendPence
                    )
                )
                FinanceBreakdownRow(
                    title: "Rolling stock purchases",
                    value: formattedPence(
                        session.financeLedger.lifetimeRollingStockSpendPence
                    )
                )
                FinanceBreakdownRow(
                    title: "Loan interest paid",
                    value: formattedPence(session.financeLedger.lifetimeInterestPaidPence)
                )
            }
            .financeSectionSurface()

            if session.gameMode == .career {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        loanButton(finance: finance)
                        repaymentButton(finance: finance)
                    }

                    VStack(spacing: 8) {
                        loanButton(finance: finance)
                        repaymentButton(finance: finance)
                    }
                }
            } else {
                Label(
                    "Zen mode keeps these statistics but never limits spending.",
                    systemImage: "infinity"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var happinessDashboardContent: some View {
        let happiness = session.happinessSnapshot
        let statistics = happiness.statistics
        let score = happiness.globalHappinessScore

        VStack(alignment: .leading, spacing: 12) {
            ProgressView(value: clampedUnitScore(score / 100))
                .tint(TycoonTheme.happinessColor(for: score))
                .accessibilityLabel("Global happiness")
                .accessibilityValue(formattedHappinessScore(score))

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 8) {
                        NetworkPerformanceMetric(
                            title: "Connected settlements",
                            value: "\(statistics.connectedSettlementCount) of \(statistics.settlementCount)",
                            isRow: true
                        )
                        NetworkPerformanceMetric(
                            title: "Reachable pairs",
                            value: "\(statistics.reachableSettlementPairCount) of \(statistics.possibleSettlementPairCount)",
                            isRow: true
                        )
                        NetworkPerformanceMetric(
                            title: "Operating services",
                            value: statistics.operatingServiceCount.formatted(),
                            isRow: true
                        )
                    }
                } else {
                    HStack(spacing: 0) {
                        NetworkPerformanceMetric(
                            title: "Connected",
                            value: "\(statistics.connectedSettlementCount)/\(statistics.settlementCount)"
                        )
                        Divider().frame(height: 30)
                        NetworkPerformanceMetric(
                            title: "Reachable pairs",
                            value: "\(statistics.reachableSettlementPairCount)/\(statistics.possibleSettlementPairCount)"
                        )
                        Divider().frame(height: 30)
                        NetworkPerformanceMetric(
                            title: "Services",
                            value: statistics.operatingServiceCount.formatted()
                        )
                    }
                }
            }

            VStack(spacing: 7) {
                HappinessComponentRow(
                    title: "Reachable destinations",
                    weight: 30,
                    score: happiness.componentScores.reachableDestinations
                )
                HappinessComponentRow(
                    title: "Destination importance",
                    weight: 20,
                    score: happiness.componentScores.destinationImportance
                )
                HappinessComponentRow(
                    title: "Journey time",
                    weight: 20,
                    score: happiness.componentScores.journeyTime
                )
                HappinessComponentRow(
                    title: "Frequency",
                    weight: 15,
                    score: happiness.componentScores.frequency
                )
                HappinessComponentRow(
                    title: "Reliability",
                    weight: 10,
                    score: happiness.componentScores.reliability
                )
                HappinessComponentRow(
                    title: "Comfort",
                    weight: 5,
                    score: happiness.componentScores.crowding
                )
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 12))
            .accessibilityElement(children: .contain)

            if !happiness.feedback.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(happiness.feedback.enumerated()), id: \.offset) { _, item in
                        HappinessFeedbackRow(
                            item: item,
                            message: happinessFeedbackMessage(item)
                        )
                    }
                }
            }

            Toggle(isOn: $showsHappinessHeatmap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility heatmap")
                        .font(.subheadline.weight(.bold))
                    Text("Limited · Developing · Strong")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(TycoonTheme.railGreen)
            .frame(minHeight: 44)
            .accessibilityHint("Shows local happiness around every catalogue station")

            Text(
                "Reliability is a stable POC baseline until delays and cancellations are simulated."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var prestigeDashboardContent: some View {
        let prestige = session.prestigeSnapshot

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 13) {
                ZStack {
                    Circle()
                        .fill(TycoonTheme.highSpeedViolet.opacity(0.14))
                    Image(systemName: "star.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(TycoonTheme.highSpeedGold)
                }
                .frame(width: 54, height: 54)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(prestige.score)/100")
                        .font(.title2.weight(.black).monospacedDigit())
                    Text(prestige.tier.name)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TycoonTheme.highSpeedViolet)
                }
            }

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 7) {
                        PassengerCardMetric(
                            title: "Completed corridors",
                            value: prestige.completedCorridorCount.formatted(),
                            isRow: true
                        )
                        PassengerCardMetric(
                            title: "Premium stations",
                            value: prestige.premiumEndpointCount.formatted(),
                            isRow: true
                        )
                    }
                } else {
                    HStack(spacing: 0) {
                        PassengerCardMetric(
                            title: "HS corridors",
                            value: prestige.completedCorridorCount.formatted()
                        )
                        Divider().frame(height: 30)
                        PassengerCardMetric(
                            title: "Premium stations",
                            value: prestige.premiumEndpointCount.formatted()
                        )
                    }
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 12))

            Label(prestige.summary, systemImage: "bolt.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(
                "Prestige is awarded only when dedicated high-speed corridors complete. "
                    + "Their shorter journeys also improve accessibility through the normal "
                    + "happiness calculation."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var networkDashboardHeader: some View {
        let score = session.happinessSnapshot.globalHappinessScore

        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 10) {
                        networkDashboardIcon(score: score)
                        Text(networkDashboardSection.heading)
                            .font(.headline)
                            .accessibilityFocused($accessibilityFocus, equals: .network)
                        Spacer(minLength: 4)
                        closeNetworkPerformanceButton
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(networkDashboardSection.subtitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        networkDashboardSummary(score: score)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    networkDashboardIcon(score: score)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(networkDashboardSection.heading)
                            .font(.headline)
                            .accessibilityFocused($accessibilityFocus, equals: .network)
                        Text(networkDashboardSection.subtitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 4)
                    networkDashboardSummary(score: score)
                    closeNetworkPerformanceButton
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func networkDashboardIcon(score: Double) -> some View {
        let color: Color
        let systemImage: String

        switch networkDashboardSection {
        case .finance:
            color = TycoonTheme.railGreen
            systemImage = "sterlingsign.circle.fill"
        case .happiness:
            color = TycoonTheme.happinessColor(for: score)
            systemImage = "heart.fill"
        case .prestige:
            color = TycoonTheme.highSpeedViolet
            systemImage = "bolt.circle.fill"
        }

        return Image(systemName: systemImage)
            .font(.title3)
            .foregroundStyle(color)
            .frame(width: 38, height: 38)
            .background(
                color.opacity(0.14),
                in: .circle
            )
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func networkDashboardSummary(score: Double) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            switch networkDashboardSection {
            case .finance:
                Text(
                    session.gameMode == .career
                        ? formattedPence(session.financeLedger.cashBalancePence)
                        : "Unlimited"
                )
                .font(.title3.weight(.black).monospacedDigit())
                Text(session.financeSnapshot.commercialViability.label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            case .happiness:
                Text(formattedHappinessScore(score))
                    .font(.title3.weight(.black).monospacedDigit())
                Text(happinessBandLabel(for: score))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            case .prestige:
                Text("\(session.prestigeSnapshot.score)/100")
                    .font(.title3.weight(.black).monospacedDigit())
                Text(session.prestigeSnapshot.tier.name)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(TycoonTheme.highSpeedViolet)
                    .lineLimit(1)
            }
        }
    }

    private func financeHealthBanner(_ health: FinancialHealth) -> some View {
        let content = financeHealthContent(health)

        return HStack(alignment: .top, spacing: 9) {
            Image(systemName: content.systemImage)
                .foregroundStyle(content.color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(content.title)
                    .font(.caption.weight(.bold))
                Text(content.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(content.color.opacity(0.10), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func financeHealthContent(
        _ health: FinancialHealth
    ) -> (title: String, message: String, systemImage: String, color: Color) {
        switch health {
        case .zen:
            return (
                "Zen mode · Unlimited budget",
                "Financial results are tracked for comparison but never stop expansion.",
                "infinity",
                TycoonTheme.railGreen
            )
        case .healthy:
            return (
                "Career finances healthy",
                "Cash is positive; expansion still needs to be funded upfront.",
                "checkmark.circle.fill",
                TycoonTheme.railGreenBright
            )
        case .lowCash:
            return (
                "Career cash is running low",
                "Review the daily cash forecast or borrow before the next expansion.",
                "exclamationmark.circle.fill",
                TycoonTheme.construction
            )
        case .insolvent(let daysRemaining):
            return (
                "Insolvent · \(daysRemaining) day\(daysRemaining == 1 ? "" : "s") remaining",
                "Restore a nonnegative balance before the grace period ends to avoid bankruptcy.",
                "exclamationmark.triangle.fill",
                TycoonTheme.construction
            )
        case .bankrupt:
            return (
                "Company bankrupt",
                "This company can no longer build, borrow or operate. Start a new game.",
                "xmark.octagon.fill",
                TycoonTheme.construction
            )
        }
    }

    private func financeSectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.black))
            .tracking(0.55)
            .foregroundStyle(.secondary)
    }

    private func loanButton(finance: NetworkFinanceSnapshot) -> some View {
        Button {
            _ = session.takeStandardLoan()
        } label: {
            VStack(spacing: 2) {
                Label(
                    "Borrow \(formattedPence(session.standardLoanPence))",
                    systemImage: "building.columns.fill"
                )
                Text(standardLoanTermsSummary)
                    .font(.caption2.weight(.semibold))
                    .opacity(0.82)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(TycoonTheme.railGreen)
        .disabled(!finance.canBorrow)
        .accessibilityHint(
            finance.canBorrow
                ? standardLoanAccessibilityHint
                : "No further standard loans are available"
        )
    }

    private func repaymentButton(finance: NetworkFinanceSnapshot) -> some View {
        Button {
            _ = session.makeStandardLoanRepayment()
        } label: {
            Label(
                "Repay \(formattedPence(session.availableEarlyRepaymentPence))",
                systemImage: "arrow.down.to.line.compact"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(!finance.canMakeEarlyRepayment)
        .accessibilityHint(
            finance.canMakeEarlyRepayment
                ? "Repays \(formattedPence(session.availableEarlyRepaymentPence)) "
                    + "of loan principal from available cash"
                : "Requires both positive cash and outstanding debt"
        )
    }

    private var closeNetworkPerformanceButton: some View {
        Button {
            isShowingNetworkPerformance = false
        } label: {
            Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close network dashboard")
    }

    private func trainCard(id: UUID) -> some View {
        let train = session.trains.first(where: { $0.id == id })
        let line = train.flatMap { selectedTrain in
            session.lines.first(where: { $0.id == selectedTrain.lineID })
        }
        let passengerMetrics = line.flatMap { session.passengerSnapshot(forLineID: $0.id) }
        let stationCapacityMetrics = line.flatMap {
            session.stationCapacitySnapshot(forLineID: $0.id)
        }
        let economyMetrics = line.flatMap { session.economySnapshot(forLineID: $0.id) }
        let occupancy = passengerMetrics?.peakOccupancyRatio ?? 0
        let selectedTrainCapacity = line?.formation.seatsPerTrain ?? session.trainCapacity
        let estimatedPeakPassengers = min(
            Int((occupancy * Double(selectedTrainCapacity)).rounded()),
            selectedTrainCapacity
        )
        let feedback = passengerMetrics?.feedback ?? .notOperating

        return VStack(alignment: .leading, spacing: 11) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        trainIdentity(line: line, id: id)
                        HStack {
                            Spacer()
                            trainHeaderActions
                                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        }
                    }
                } else {
                    HStack(spacing: 11) {
                        trainIdentity(line: line, id: id)
                        Spacer(minLength: 4)
                        trainHeaderActions
                    }
                }
            }

            if let line,
               let plan = session.trainServicePlan(for: id),
               session.canCustomizeServicePlan(for: id) {
                let trainNumber = (line.trains.firstIndex(where: { $0.id == id }) ?? 0) + 1
                TrainStoppingPlanSummary(
                    availableStations: session.serviceStations(forLineID: line.id).map {
                        (crs: $0.crs, name: $0.name)
                    },
                    plan: plan,
                    trainNumber: trainNumber,
                    onEdit: {
                        editingServicePlanTrainID = id
                    }
                )

                if line.trains.count > 1 {
                    Menu {
                        ForEach(Array(line.trains.enumerated()), id: \.element.id) {
                            index, train in
                            Button {
                                editingServicePlanTrainID = nil
                                session.selectTrain(train.id)
                            } label: {
                                let role = line.servicePlan(forSlot: index)?.role
                                    ?? session.trainServiceRole(for: train.id)
                                Label(
                                    "Train \(index + 1) · \(role?.name ?? "Service")",
                                    systemImage: train.id == id ? "checkmark" : "tram"
                                )
                            }
                        }
                    } label: {
                        Label("Choose another train", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.bold))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Selects another active train to inspect or customise")
                }
            }

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 8) {
                        PassengerCardMetric(
                            title: "Estimated peak load",
                            value: occupancy.formatted(.percent.precision(.fractionLength(0))),
                            isRow: true
                        )
                        PassengerCardMetric(
                            title: "Estimated peak passengers",
                            value: "\(estimatedPeakPassengers) / \(selectedTrainCapacity)",
                            isRow: true
                        )
                        PassengerCardMetric(
                            title: "Average wait",
                            value: formattedMinutes(passengerMetrics?.averageWaitMinutes ?? 0),
                            isRow: true
                        )
                    }
                } else {
                    HStack(spacing: 0) {
                        PassengerCardMetric(
                            title: "Est. peak load",
                            value: occupancy.formatted(.percent.precision(.fractionLength(0)))
                        )
                        Divider().frame(height: 30)
                        PassengerCardMetric(
                            title: "Estimated peak passengers",
                            value: "\(estimatedPeakPassengers) / \(selectedTrainCapacity)"
                        )
                        Divider().frame(height: 30)
                        PassengerCardMetric(
                            title: "Average wait",
                            value: formattedMinutes(passengerMetrics?.averageWaitMinutes ?? 0)
                        )
                    }
                }
            }

            ProgressView(value: occupancy)
                .tint(occupancy >= 0.9 ? TycoonTheme.construction : TycoonTheme.railGreenBright)
                .accessibilityLabel("Estimated peak load")
                .accessibilityValue(occupancy.formatted(.percent.precision(.fractionLength(0))))

            if let passengerMetrics {
                let connectingRiders = ConnectingRidersUIPresentation(
                    directRidersPerDay: passengerMetrics.directPassengersPerDay,
                    connectingRidersPerDay: passengerMetrics.connectingPassengersPerDay
                )
                if connectingRiders.shouldShow {
                    ConnectingRidersPanel(presentation: connectingRiders)
                }
            }

            if let economyMetrics {
                VStack(spacing: 8) {
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(spacing: 8) {
                                PassengerCardMetric(
                                    title: "Revenue / day",
                                    value: formattedPence(economyMetrics.revenuePencePerDay),
                                    isRow: true
                                )
                                PassengerCardMetric(
                                    title: "Operating cost / day",
                                    value: formattedPence(
                                        economyMetrics.totalOperatingCostPencePerDay
                                    ),
                                    isRow: true
                                )
                                PassengerCardMetric(
                                    title: "Line result / day",
                                    value: formattedPence(
                                        economyMetrics.operatingResultPencePerDay
                                    ),
                                    isRow: true
                                )
                            }
                        } else {
                            HStack(spacing: 0) {
                                PassengerCardMetric(
                                    title: "Revenue/day",
                                    value: formattedPence(economyMetrics.revenuePencePerDay)
                                )
                                Divider().frame(height: 30)
                                PassengerCardMetric(
                                    title: "Operating cost/day",
                                    value: formattedPence(
                                        economyMetrics.totalOperatingCostPencePerDay
                                    )
                                )
                                Divider().frame(height: 30)
                                PassengerCardMetric(
                                    title: "Line result/day",
                                    value: formattedPence(
                                        economyMetrics.operatingResultPencePerDay
                                    )
                                )
                            }
                        }
                    }

                    Divider()

                    VStack(spacing: 5) {
                        FinanceBreakdownRow(
                            title: "Energy",
                            value: formattedExpense(economyMetrics.energyCostPencePerDay)
                        )
                        FinanceBreakdownRow(
                            title: "Rolling stock maintenance",
                            value: formattedExpense(
                                economyMetrics.rollingStockMaintenanceCostPencePerDay
                            )
                        )
                        FinanceBreakdownRow(
                            title: "Track maintenance",
                            value: formattedExpense(economyMetrics.trackUpkeepPencePerDay)
                        )
                    }
                    .padding(.horizontal, 8)
                }
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 12))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Line operating forecast")
            }

            HStack(spacing: 8) {
                Image(
                    systemName: feedback == .capacityConstrained
                        || feedback == .stationCapacityConstrained
                        ? "exclamationmark.circle.fill"
                        : "checkmark.circle.fill"
                )
                    .foregroundStyle(
                        feedback == .capacityConstrained
                            || feedback == .stationCapacityConstrained
                            ? TycoonTheme.construction
                            : TycoonTheme.railGreenBright
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(feedback.title)
                        .font(.caption.weight(.bold))
                    Text(feedback.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                }
            }

            if let line, let stationCapacityMetrics {
                LineStationCapacityPanel(
                    presentation: LineStationCapacityUIPresentation(
                        scheduledDeparturesPerHour: stationCapacityMetrics
                            .scheduledDeparturesPerHour,
                        effectiveDeparturesPerHour: stationCapacityMetrics
                            .effectiveDeparturesPerHour,
                        limitingStationNames: stationCapacityMetrics.limitingStationCRSs.map {
                            limitingCRS in
                            session.stations.first(where: { $0.crs == limitingCRS })?.name
                                ?? limitingCRS
                        },
                        isOperating: line.isConstructed
                    )
                )
            }

            if let line {
                if line.railwayClass == .conventional {
                    BuiltLineStopsSection(
                        line: line,
                        stationCatalog: session.stations,
                        availableIntermediateStations: session.editingStopsLineID == line.id
                            ? session.editableIntermediateStations
                            : [],
                        maximumStopCount: session.maximumServiceCallCount,
                        isEditing: session.editingStopsLineID == line.id,
                        isUpdating: session.editingStopsLineID == line.id
                            && session.isUpdatingLineStops,
                        gameMode: session.gameMode,
                        beginEditing: {
                            session.beginEditingStops(forLineID: line.id)
                        },
                        addStation: { station in
                            session.addIntermediateStation(station, toLineID: line.id)
                        },
                        finishEditing: session.finishEditingStops,
                        additionCostPence: { station in
                            session.intermediateStationAdditionCostPence(
                                station,
                                toLineID: line.id
                            )
                        },
                        canAfford: { station in
                            session.canAffordIntermediateStation(station, toLineID: line.id)
                        },
                        editingUnavailableReason: line.corridorIDs.count > 1
                            ? "Physical stations on a joined railway cannot be rebuilt here. Use each train's Edit plan control to choose its existing terminals and calls."
                            : nil
                    )

                    let throughServiceAvailability = session.throughServiceAvailability(
                        forLineID: line.id
                    )
                    ThroughServiceSection(
                        line: line,
                        options: throughServiceAvailability.options,
                        incompatibilities: throughServiceAvailability.incompatibilities,
                        gameMode: session.gameMode,
                        join: { option in
                            session.joinThroughService(
                                primaryLineID: option.primaryLineID,
                                withLineID: option.candidateLineID
                            )
                        },
                        openFinances: {
                            session.selectTrain(nil)
                            networkDashboardSection = .finance
                            isShowingNetworkPerformance = true
                        }
                    )
                }

                rollingStockPanel(for: line)
                lineOperationsPanel(for: line)
                serviceFrequencyStepper(for: line)
                Text(
                    frequencyPurchaseMessage(for: line)
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .railPanel()
        .accessibilityElement(children: .contain)
    }

    private func trainIdentity(line: BuiltLine?, id: UUID) -> some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                Circle()
                    .fill(
                        (line?.railwayClass == .highSpeed
                            ? TycoonTheme.highSpeedViolet
                            : TycoonTheme.lineColor(for: line?.styleIndex ?? 0)).opacity(0.16)
                    )
                    .frame(width: 44, height: 44)

                Image(systemName: line?.railwayClass == .highSpeed ? "bolt.fill" : "tram.fill")
                    .foregroundStyle(
                        line?.railwayClass == .highSpeed
                            ? TycoonTheme.highSpeedViolet
                            : TycoonTheme.lineColor(for: line?.styleIndex ?? 0)
                    )
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(line?.name ?? "Test train")
                    .font(.headline)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .accessibilityFocused($accessibilityFocus, equals: .train(id))
                Text(
                    line.map {
                        ($0.railwayClass == .highSpeed ? "High speed · " : "")
                            + "\($0.origin.name) ↔ \($0.destination.name)"
                    } ?? "Running"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }
        }
    }

    private var trainHeaderActions: some View {
        HStack(spacing: 8) {
            Button {
                session.setFollowingSelectedTrain(!session.isFollowingSelectedTrain)
            } label: {
                Image(
                    systemName: session.isFollowingSelectedTrain
                        ? "location.fill"
                        : "location"
                )
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .tint(session.isFollowingSelectedTrain ? TycoonTheme.railGreen : .secondary)
            .accessibilityLabel(
                session.isFollowingSelectedTrain ? "Stop following train" : "Follow train"
            )

            Button {
                session.selectTrain(nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close train controls")
        }
    }

    private func stationCard(crs: String) -> some View {
        let station = session.stations.first { $0.crs == crs }
        let metrics = session.passengerSnapshot(forStationCRS: crs)
        let happiness = session.happinessSnapshot(forStationCRS: crs)
        let evolution = session.stationEvolutionStatus(forStationCRS: crs)
        let stationCapacity = session.stationCapacitySnapshot(forStationCRS: crs)
        let upkeepPencePerDay = session.stationUpkeepPencePerDay(forStationCRS: crs)
        let isPremiumHighSpeed = session.isPremiumHighSpeedStation(crs)
        let busiestName = metrics?.busiestDirectDestinationCRS.flatMap { destinationCRS in
            session.stations.first { $0.crs == destinationCRS }?.name
        }
        let servedRatio: Double
        if let metrics, metrics.potentialDailyJourneys > 0 {
            servedRatio = Double(metrics.servedDailyJourneys)
                / Double(metrics.potentialDailyJourneys)
        } else {
            servedRatio = 0
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: isPremiumHighSpeed ? "bolt.fill" : "building.2.fill")
                    .font(.title3)
                    .foregroundStyle(
                        isPremiumHighSpeed
                            ? TycoonTheme.highSpeedViolet
                            : TycoonTheme.panelAccent
                    )
                    .frame(width: 38, height: 38)
                    .background(
                        (isPremiumHighSpeed
                            ? TycoonTheme.highSpeedViolet
                            : TycoonTheme.panelAccent).opacity(0.12),
                        in: .circle
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(station?.name ?? "Station")
                        .font(.headline)
                        .accessibilityFocused($accessibilityFocus, equals: .station(crs))
                    Text(
                        stationSummary(
                            evolution: evolution,
                            metrics: metrics,
                            happiness: happiness
                        )
                    )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    session.selectStationForInspection(nil)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close station details")
            }

            if isPremiumHighSpeed {
                Label(
                    "Premium high-speed station · 215 mph services",
                    systemImage: "star.fill"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(TycoonTheme.highSpeedViolet)
                .padding(.horizontal, 10)
                .frame(minHeight: 36)
                .background(
                    TycoonTheme.highSpeedViolet.opacity(0.10),
                    in: .capsule
                )
                .accessibilityLabel("Premium high-speed station")
            }

            if let stationCapacity,
               let platformCount = stationCapacity.platformCount,
               let trainCallCapacityPerHour = stationCapacity.trainCallCapacityPerHour {
                StationCapacityPanel(
                    presentation: StationCapacityUIPresentation(
                        platformCount: platformCount,
                        scheduledTrainCallsPerHour: stationCapacity
                            .scheduledTrainCallsPerHour,
                        effectiveTrainCallsPerHour: stationCapacity
                            .effectiveTrainCallsPerHour,
                        trainCallCapacityPerHour: trainCallCapacityPerHour,
                        isConstrained: stationCapacity.isPlatformConstrained,
                        nextLevelName: evolution?.nextLevel?.displayName,
                        nextLevelPlatformCount: evolution?.nextLevel?.platformCount
                    )
                )
            }

            if let metrics {
                let interchangeDemand = InterchangeDemandUIPresentation(
                    transferJourneysPerDay: metrics.transferJourneysPerDay
                )
                if interchangeDemand.shouldShow {
                    InterchangeDemandPanel(presentation: interchangeDemand)
                }
            }

            if let growth = settlementGrowthPresentation(forStationCRS: crs) {
                SettlementGrowthPanel(presentation: growth)
            }

            if let happiness {
                stationHappinessCard(happiness)
            }

            if let evolution {
                stationEvolutionCard(
                    evolution,
                    upkeepPencePerDay: upkeepPencePerDay ?? 0
                )
            }

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 8) {
                        PassengerCardMetric(
                            title: "Potential / day",
                            value: formattedPassengerCount(metrics?.potentialDailyJourneys ?? 0),
                            isRow: true
                        )
                        PassengerCardMetric(
                            title: "Rail passengers",
                            value: formattedPassengerCount(metrics?.servedDailyJourneys ?? 0),
                            isRow: true
                        )
                        PassengerCardMetric(
                            title: "Unserved",
                            value: formattedPassengerCount(metrics?.unservedDailyJourneys ?? 0),
                            isRow: true
                        )
                    }
                } else {
                    HStack(spacing: 0) {
                        PassengerCardMetric(
                            title: "Potential / day",
                            value: formattedPassengerCount(metrics?.potentialDailyJourneys ?? 0)
                        )
                        Divider().frame(height: 30)
                        PassengerCardMetric(
                            title: "Rail passengers",
                            value: formattedPassengerCount(metrics?.servedDailyJourneys ?? 0)
                        )
                        Divider().frame(height: 30)
                        PassengerCardMetric(
                            title: "Unserved",
                            value: formattedPassengerCount(metrics?.unservedDailyJourneys ?? 0)
                        )
                    }
                }
            }

            ProgressView(value: servedRatio)
                .tint(TycoonTheme.railGreenBright)
                .accessibilityLabel("Potential journeys served")
                .accessibilityValue(servedRatio.formatted(.percent.precision(.fractionLength(0))))

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        stationDestinationLabel(metrics: metrics)
                        if let busiestName {
                            Text("Busiest: \(busiestName)")
                                .font(.caption.weight(.semibold))
                        }
                    }
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        stationDestinationLabel(metrics: metrics)

                        Spacer(minLength: 8)

                        if let busiestName {
                            Text("Busiest: \(busiestName)")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                    }
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .railPanel()
        .accessibilityElement(children: .contain)
    }

    private func settlementGrowthPresentation(
        forStationCRS crs: String
    ) -> SettlementGrowthUIPresentation? {
        guard let status = session.settlementGrowthStatus(forStationCRS: crs) else {
            return nil
        }
        return SettlementGrowthUIPresentation(
            population: status.currentPopulation,
            latestChange: status.latestDailyChange,
            demandMultiplier: status.passengerDemandMultiplier,
            reason: "\(status.feedback.title). \(status.feedback.message)"
        )
    }

    private func serviceFrequencyStepper(for line: BuiltLine) -> some View {
        let frequencies = ServiceFrequency.allCases
        let currentIndex = frequencies.firstIndex(of: line.serviceFrequency) ?? 0

        return Stepper {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Service frequency")
                            .font(.caption.weight(.semibold))
                        Text(line.serviceFrequency.name)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(TycoonTheme.railGreen)
                        Text("\(line.trains.count) running · \(line.ownedTrainCount) owned")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Service frequency")
                                .font(.caption.weight(.semibold))
                            Text("\(line.trains.count) running · \(line.ownedTrainCount) owned")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(line.serviceFrequency.name)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(TycoonTheme.railGreen)
                    }
                }
            }
        } onIncrement: {
            guard frequencies.indices.contains(currentIndex + 1) else { return }
            session.setServiceFrequency(frequencies[currentIndex + 1], forLineID: line.id)
        } onDecrement: {
            guard frequencies.indices.contains(currentIndex - 1) else { return }
            session.setServiceFrequency(frequencies[currentIndex - 1], forLineID: line.id)
        }
        .accessibilityValue("\(line.serviceFrequency.name), \(line.serviceFrequency.departuresPerHour) departures per hour")
        .accessibilityHint(
            "Changes passenger demand, daily revenue, energy and maintenance costs. "
                + frequencyPurchaseMessage(for: line)
        )
    }

    private func rollingStockPanel(for line: BuiltLine) -> some View {
        let nextFormation = line.formation.next(for: line.railwayClass)
        let extensionCost = session.formationExtensionCost(forLineID: line.id)
        let fleetSeatCapacity = saturatedProduct(
            line.formation.seatsPerTrain,
            line.ownedTrainCount
        )

        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Rolling stock", systemImage: "tram.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TycoonTheme.panelAccent)

                Spacer(minLength: 4)

                Text("\(line.formation.carriageCount) CARS")
                    .font(.caption2.weight(.black).monospacedDigit())
                    .tracking(0.35)
                    .foregroundStyle(TycoonTheme.panelAccent)
            }

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 6) {
                        PassengerCardMetric(
                            title: "Seats per train",
                            value: line.formation.seatsPerTrain.formatted(),
                            isRow: true
                        )
                        PassengerCardMetric(
                            title: "Trainsets owned",
                            value: line.ownedTrainCount.formatted(),
                            isRow: true
                        )
                        PassengerCardMetric(
                            title: "Seats across owned fleet",
                            value: fleetSeatCapacity.formatted(),
                            isRow: true
                        )
                    }
                } else {
                    HStack(spacing: 0) {
                        PassengerCardMetric(
                            title: "Seats/train",
                            value: line.formation.seatsPerTrain.formatted()
                        )
                        Divider().frame(height: 30)
                        PassengerCardMetric(
                            title: "Owned trains",
                            value: line.ownedTrainCount.formatted()
                        )
                        Divider().frame(height: 30)
                        PassengerCardMetric(
                            title: "Fleet seats",
                            value: fleetSeatCapacity.formatted()
                        )
                    }
                }
            }

            if let nextFormation, let extensionCost {
                Button {
                    _ = session.extendFormation(forLineID: line.id)
                } label: {
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 3) {
                                formationExtensionTitle
                                formationExtensionDetail(
                                    nextFormation: nextFormation,
                                    cost: extensionCost
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            HStack(spacing: 10) {
                                Image(systemName: "plus")
                                    .font(.headline.weight(.bold))
                                VStack(alignment: .leading, spacing: 1) {
                                    formationExtensionTitle
                                    formationExtensionDetail(
                                        nextFormation: nextFormation,
                                        cost: extensionCost
                                    )
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(
                    line.railwayClass == .highSpeed
                        ? TycoonTheme.highSpeedViolet
                        : TycoonTheme.railGreen
                )
                .accessibilityHint(formationExtensionAccessibilityHint(cost: extensionCost))
            } else {
                Label("Maximum 12-car formation", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TycoonTheme.panelAccent)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
        .padding(10)
        .background(TycoonTheme.panelAccent.opacity(0.08), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rolling stock formation")
    }

    private var formationExtensionTitle: some View {
        Text("Add 2 cars to every train")
            .font(.caption.weight(.bold))
    }

    private func formationExtensionDetail(
        nextFormation: RollingStockFormation,
        cost: Int64
    ) -> some View {
        Text(
            "\(nextFormation.carriageCount) cars · \(nextFormation.seatsPerTrain) seats each · "
                + formationExtensionPriceText(cost)
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func formationExtensionPriceText(_ cost: Int64) -> String {
        if session.gameMode == .zen {
            return "\(formattedPence(cost)), unlimited Zen budget"
        }
        let affordable = session.financeLedger.cashBalancePence >= cost
        return "\(formattedPence(cost)), "
            + (affordable ? "available cash covers it" : "more funding needed")
    }

    private func formationExtensionAccessibilityHint(cost: Int64) -> String {
        "Permanently adds 80 seats to every trainset owned by this line for "
            + "\(formattedPence(cost)). "
            + (session.gameMode == .career
                ? "The full fleet upgrade must be affordable."
                : "Zen budget is unlimited.")
    }

    private func saturatedProduct(_ lhs: Int, _ rhs: Int) -> Int {
        let product = max(lhs, 0).multipliedReportingOverflow(by: max(rhs, 0))
        return product.overflow ? .max : max(product.partialValue, 0)
    }

    private func lineOperationsPanel(for line: BuiltLine) -> some View {
        let operations = session.operationsSnapshot(forLineID: line.id)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Line operations", systemImage: "slider.horizontal.3")
                    .font(.caption.weight(.bold))
                Spacer(minLength: 8)
                Text(
                    line.railwayClass == .highSpeed
                        ? "DEDICATED HSR"
                        : line.trackCapacity.name.uppercased()
                )
                    .font(.caption2.weight(.black))
                    .tracking(0.35)
                    .foregroundStyle(.secondary)
            }

            if line.railwayClass == .highSpeed {
                highSpeedOperationsSummary(for: line)
            } else {
                servicePatternControl(for: line)
            }

            if let operations {
                operationsMetrics(operations)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: operations.congestionBand == .congested
                        ? "exclamationmark.triangle.fill"
                        : "checkmark.shield.fill")
                        .foregroundStyle(operations.congestionBand == .congested
                            ? TycoonTheme.construction
                            : TycoonTheme.railGreenBright)
                    Text(operations.statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if line.railwayClass == .highSpeed {
                Label(
                    "Dedicated double track · premium stations · high-speed fleet",
                    systemImage: "bolt.fill"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(TycoonTheme.highSpeedViolet)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else {
                trackCapacityControl(for: line)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Line operations")
    }

    private func highSpeedOperationsSummary(for line: BuiltLine) -> some View {
        let premiumRevenue = session.economySnapshot(forLineID: line.id)?
            .highSpeedFarePremiumPencePerDay ?? 0

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(TycoonTheme.highSpeedGold)
                VStack(alignment: .leading, spacing: 1) {
                    Text("215 mph high-speed service")
                        .font(.caption.weight(.bold))
                    Text("Express-only operation on its own railway")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            FinanceBreakdownRow(
                title: "Premium fare revenue / day",
                value: formattedPence(premiumRevenue)
            )
            FinanceBreakdownRow(
                title: "Network prestige",
                value: "\(session.prestigeSnapshot.score)/100"
            )
        }
        .padding(9)
        .background(
            TycoonTheme.highSpeedViolet.opacity(0.10),
            in: .rect(cornerRadius: 10)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dedicated high-speed service")
    }

    @ViewBuilder
    private func servicePatternControl(for line: BuiltLine) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 6) {
                ForEach(ServicePattern.allCases) { pattern in
                    Button {
                        applyFleetPreset(pattern, to: line)
                    } label: {
                        HStack(spacing: 9) {
                            Text(pattern.compactSymbol)
                                .font(.caption.weight(.black))
                                .frame(width: 24, height: 24)
                                .background(
                                    pattern == line.servicePattern
                                        ? TycoonTheme.railGreen
                                        : Color.secondary.opacity(0.16),
                                    in: .circle
                                )
                                .foregroundStyle(
                                    pattern == line.servicePattern ? .white : .primary
                                )
                            VStack(alignment: .leading, spacing: 1) {
                                Text(pattern.name)
                                    .font(.caption.weight(.bold))
                                Text(pattern.summary)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            if pattern == line.servicePattern {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(TycoonTheme.railGreen)
                            }
                        }
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(
                        pattern == line.servicePattern ? .isSelected : []
                    )
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Picker(
                    "Fleet preset",
                    selection: Binding(
                        get: { line.servicePattern },
                        set: { applyFleetPreset($0, to: line) }
                    )
                ) {
                    ForEach(ServicePattern.allCases) { pattern in
                        Text(pattern.name).tag(pattern)
                    }
                }
                .pickerStyle(.segmented)

                Text(
                    session.hasCustomServicePlans(forLineID: line.id)
                        ? "Custom per-train plans are active. Choosing a preset resets all four timetable slots."
                        : line.servicePattern.summary
                )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if session.hasCustomServicePlans(forLineID: line.id) {
            Button {
                pendingFleetPresetReset = FleetPresetResetRequest(
                    lineID: line.id,
                    pattern: line.servicePattern
                )
            } label: {
                Label(
                    "Reset every train to \(line.servicePattern.name)",
                    systemImage: "arrow.counterclockwise"
                )
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Replaces all custom train terminals and calls")
        }
    }

    private func applyFleetPreset(_ pattern: ServicePattern, to line: BuiltLine) {
        if session.hasCustomServicePlans(forLineID: line.id) {
            pendingFleetPresetReset = FleetPresetResetRequest(
                lineID: line.id,
                pattern: pattern
            )
        } else {
            session.setServicePattern(pattern, forLineID: line.id)
        }
    }

    @ViewBuilder
    private func operationsMetrics(_ operations: LineOperationsSnapshot) -> some View {
        let reliability = operations.reliability.formatted(
            .percent.precision(.fractionLength(0))
        )
        let mix = operations.hasMixedServices
            ? "\(operations.localTrainCount)L + \(operations.expressTrainCount)X"
            : operations.localTrainCount > 0 ? "Local" : "Express"

        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 6) {
                PassengerCardMetric(title: "Service mix", value: mix, isRow: true)
                PassengerCardMetric(
                    title: "Track flow",
                    value: operations.congestionBand.name,
                    isRow: true
                )
                PassengerCardMetric(title: "Reliability", value: reliability, isRow: true)
            }
        } else {
            HStack(spacing: 0) {
                PassengerCardMetric(title: "Service mix", value: mix)
                Divider().frame(height: 30)
                PassengerCardMetric(title: "Track flow", value: operations.congestionBand.name)
                Divider().frame(height: 30)
                PassengerCardMetric(title: "Reliability", value: reliability)
            }
        }
    }

    @ViewBuilder
    private func trackCapacityControl(for line: BuiltLine) -> some View {
        if line.corridorIDs.count > 1 {
            Label {
                Text("Track upgrades for joined services are managed corridor by corridor in a later milestone.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "link")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else if let nextCapacity = line.trackCapacity.next,
           let cost = session.trackUpgradeCost(forLineID: line.id) {
            Button {
                session.upgradeTrackCapacity(forLineID: line.id)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: nextCapacity == .passingLoop
                        ? "arrow.trianglehead.swap"
                        : "equal")
                        .font(.headline.weight(.bold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(nextCapacity == .passingLoop
                            ? "Build passing loop"
                            : "Add second track")
                            .font(.caption.weight(.bold))
                        Text(upgradePriceText(cost))
                            .font(.caption2)
                            .opacity(0.78)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(TycoonTheme.railGreen)
            .accessibilityHint(nextCapacity.summary)
        } else {
            Label("Maximum track capacity", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(TycoonTheme.railGreen)
                .frame(minHeight: 44)
        }
    }

    private func upgradePriceText(_ cost: Int64) -> String {
        if session.gameMode == .zen {
            return "\(formattedPence(cost)) · unlimited Zen budget"
        }
        let affordable = session.financeLedger.cashBalancePence >= cost
        return "\(formattedPence(cost)) · "
            + (affordable ? "available cash covers it" : "more funding needed")
    }

    private func frequencyPurchaseMessage(for line: BuiltLine) -> String {
        let frequencies = ServiceFrequency.allCases
        guard let currentIndex = frequencies.firstIndex(of: line.serviceFrequency),
              frequencies.indices.contains(currentIndex + 1) else {
            return "Maximum frequency. Reducing service keeps all purchased trains."
        }

        let nextFrequency = frequencies[currentIndex + 1]
        let additionalTrainCount = max(
            nextFrequency.visibleTrainCount - line.ownedTrainCount,
            0
        )
        guard additionalTrainCount > 0 else {
            return "The next frequency uses your existing fleet. Reducing service keeps purchased trains."
        }

        let purchaseCost = session.rollingStockPurchaseCost(
            for: nextFrequency,
            lineID: line.id
        ) ?? 0
        let trainLabel = additionalTrainCount == 1 ? "train" : "trains"

        if session.gameMode == .zen {
            return "Next frequency buys \(additionalTrainCount) \(trainLabel) for "
                + "\(formattedPence(purchaseCost)); Zen budget is unlimited."
        }

        let canAfford = purchaseCost <= max(session.financeLedger.cashBalancePence, 0)
        return "Next frequency buys \(additionalTrainCount) \(trainLabel) for "
            + "\(formattedPence(purchaseCost)). "
            + (canAfford ? "Available cash covers it." : "More funding is needed.")
    }

    private var bankruptcyCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.title3)
                    .foregroundStyle(TycoonTheme.construction)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Company bankrupt")
                        .font(.headline)
                    Text(
                        "The Career company remained below £0 for the full grace period. "
                            + "Start again to keep building."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                FinanceBreakdownRow(
                    title: "Final cash balance",
                    value: formattedPence(session.financeLedger.cashBalancePence),
                    emphasis: true,
                    isWarning: true
                )
                FinanceBreakdownRow(
                    title: "Outstanding debt",
                    value: formattedPence(session.financeSnapshot.outstandingDebtPence)
                )
                if let day = session.financeLedger.bankruptcyOperatingDay {
                    FinanceBreakdownRow(
                        title: "Bankruptcy declared",
                        value: "Operating day \(day)"
                    )
                }
            }
            .financeSectionSurface()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    bankruptcyResetButton(mode: .career)
                    bankruptcyResetButton(mode: .zen)
                }

                VStack(spacing: 8) {
                    bankruptcyResetButton(mode: .career)
                    bankruptcyResetButton(mode: .zen)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .railPanel()
        .accessibilityElement(children: .contain)
    }

    private func bankruptcyResetButton(mode: GameMode) -> some View {
        Button {
            bankruptcyResetMode = mode
            isConfirmingBankruptcyReset = true
        } label: {
            Label(
                "New \(mode.title) Game",
                systemImage: mode == .career ? "briefcase.fill" : "infinity"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(TycoonTheme.railGreen)
    }

    private var errorCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(TycoonTheme.construction)

                VStack(alignment: .leading, spacing: 3) {
                    Text("That route couldn’t be built")
                        .font(.headline)
                    Text(session.errorMessage ?? "Try another pair of stations.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button("Close") {
                    session.cancelBuild()
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)

                Button("Choose again") {
                    session.cancelBuild()
                    session.startBuilding()
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
                .tint(TycoonTheme.railGreen)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .railPanel()
    }

    private var routeSummary: String {
        let origin = session.selectedOrigin?.name ?? "Start"
        let destination = session.selectedDestination?.name ?? "destination"
        return "\(origin) to \(destination)"
    }

    private func formattedDistance(_ kilometres: Double) -> String {
        kilometres.formatted(.number.precision(.fractionLength(1))) + " km"
    }

    private func formattedPassengerCount(_ passengers: Int) -> String {
        max(passengers, 0).formatted(.number.notation(.compactName))
    }

    private func formattedPassengerVisits(_ visits: Int64) -> String {
        max(visits, 0).formatted(.number.notation(.compactName))
    }

    private func formattedPence(_ pence: Int64) -> String {
        (Double(pence) / 100).formatted(
            .currency(code: "GBP")
                .notation(.compactName)
                .precision(.fractionLength(0))
        )
    }

    private func formattedExpense(_ pence: Int64) -> String {
        let normalized = max(pence, 0)
        guard normalized > 0 else { return formattedPence(0) }
        return "−" + formattedPence(normalized)
    }

    private var standardLoanTermsSummary: String {
        let offer = session.standardLoanOffer
        return "\(formattedAnnualPercentage(offer.annualInterestBasisPoints)) APR · "
            + "\(offer.termOperatingDays.formatted()) days · "
            + "first payment \(formattedPence(offer.firstDayPaymentPence))"
    }

    private var standardLoanAccessibilityHint: String {
        let offer = session.standardLoanOffer
        return "Adds \(formattedPence(offer.principalPence)) to company cash. "
            + "The loan has \(formattedAnnualPercentage(offer.annualInterestBasisPoints)) "
            + "annual interest over \(offer.termOperatingDays.formatted()) operating days. "
            + "The first scheduled payment is \(formattedPence(offer.firstDayPaymentPence)), "
            + "including \(formattedPence(offer.firstDayInterestPence)) interest."
    }

    private func formattedAnnualPercentage(_ basisPoints: Int) -> String {
        (Double(max(basisPoints, 0)) / 10_000).formatted(
            .percent.precision(.fractionLength(0...2))
        )
    }

    private func formattedMinutes(_ minutes: Double) -> String {
        guard minutes.isFinite, minutes > 0 else { return "—" }
        return minutes.formatted(.number.precision(.fractionLength(0))) + " min"
    }

    private func formattedHappinessScore(_ score: Double) -> String {
        let normalized = score.isFinite ? min(max(score, 0), 100) : 0
        return "\(Int(normalized.rounded()))/100"
    }

    private func clampedUnitScore(_ score: Double) -> Double {
        guard score.isFinite else { return 0 }
        return min(max(score, 0), 1)
    }

    private func happinessBandLabel(for score: Double) -> String {
        let normalized = score.isFinite ? min(max(score, 0), 100) : 0
        return switch normalized {
        case 80...: HappinessBand.excellent.label
        case 60..<80: HappinessBand.good.label
        case 40..<60: HappinessBand.average.label
        case 20..<40: HappinessBand.poor.label
        default: HappinessBand.veryPoor.label
        }
    }

    private func happinessFeedbackMessage(_ item: HappinessFeedbackItem) -> String {
        guard item.kind == .excellentDestinationAccess,
              let relatedCRS = item.relatedStationCRS else {
            return item.message
        }
        let destinationName = session.stations.first { $0.crs == relatedCRS }?.name
            ?? relatedCRS
        return "\(destinationName) is an important destination within easy reach."
    }

    private var networkSummaryAccessibilityValue: String {
        let finance = session.financeSnapshot
        let balance = session.gameMode == .career
            ? formattedPence(session.financeLedger.cashBalancePence)
            : "unlimited"
        let projected = formattedPence(
            session.gameMode == .career
                ? finance.projectedCashChangePencePerDay
                : finance.projectedProfitPencePerDay
        )
        let happiness = formattedHappinessScore(
            session.happinessSnapshot.globalHappinessScore
        )
        let passengers = session.passengerSnapshot.passengersPerDay.formatted()
        let prestige = session.prestigeSnapshot.score
        let unserved = session.passengerSnapshot.unservedDailyJourneys.formatted()
        let population = PopulationUIPresentation.fullPopulation(session.networkPopulation)
        let populationChange = PopulationUIPresentation.changeDescription(
            session.latestNetworkPopulationChange
        ).lowercased()
        let lifetimeResult = formattedPence(
            session.economyLedger.lifetimeOperatingResultPence
        )
        let trackingDisclosure = session.financeLedger.hasIncompleteCapitalHistory
            ? ", " + incompleteCapitalHistoryAccessibilityDisclosure.lowercased()
            : ""
        return "\(session.gameMode.title) mode, balance \(balance), "
            + "projected daily \(session.gameMode == .career ? "cash change" : "result") "
            + "\(projected), gross network value \(formattedPence(finance.networkValuePence)), "
            + "network happiness \(happiness), "
            + "high-speed prestige \(prestige) out of 100, "
            + "\(passengers) projected passenger journeys per day, "
            + "\(population) synthetic gameplay population, \(populationChange), "
            + "\(unserved) unserved journeys, \(lifetimeResult) lifetime operating result"
            + trackingDisclosure
    }

    private var incompleteCapitalHistoryDisclosure: String {
        let trackingDay = session.financeLedger.trackingStartedOnOperatingDay
        if trackingDay > 0 {
            return "Tracking began on operating day \(trackingDay). "
                + "Earlier capital spending is not included."
        }
        return "This game began before capital tracking. "
            + "Earlier capital spending is not included."
    }

    private var incompleteCapitalHistoryAccessibilityDisclosure: String {
        "Financial " + incompleteCapitalHistoryDisclosure.lowercased()
    }

    @ViewBuilder
    private func stationEvolutionCard(
        _ evolution: StationEvolutionStatus,
        upkeepPencePerDay: Int64
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(evolution.level.displayName, systemImage: "building.2.fill")
                            .font(.caption.weight(.bold))
                        Text(platformLabel(evolution.platformCount))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("Upkeep \(formattedPence(upkeepPencePerDay)) / day")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        Label(evolution.level.displayName, systemImage: "building.2.fill")
                            .font(.caption.weight(.bold))
                        Spacer(minLength: 8)
                        Text(
                            "\(platformLabel(evolution.platformCount)) · "
                                + "\(formattedPence(upkeepPencePerDay))/day upkeep"
                        )
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ProgressView(value: evolution.progressToNextLevel)
                .tint(TycoonTheme.railGreen)
                .accessibilityLabel("Progress to next station level")
                .accessibilityValue(
                    evolution.progressToNextLevel.formatted(
                        .percent.precision(.fractionLength(0))
                    )
                )

            Text(stationEvolutionMessage(evolution))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(TycoonTheme.railGreen.opacity(0.08), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Station evolution")
        .accessibilityValue(
            "\(evolution.level.displayName), \(platformLabel(evolution.platformCount)), "
                + "\(formattedPence(upkeepPencePerDay)) upkeep per day, "
                + stationEvolutionMessage(evolution)
        )
    }

    private func stationSummary(
        evolution: StationEvolutionStatus?,
        metrics: StationPassengerSnapshot?,
        happiness: SettlementHappinessSnapshot?
    ) -> String {
        let activity = metrics?.activityLevel.label ?? "No passenger service"
        let score = happiness.map { formattedHappinessScore($0.happinessScore) }
        let stationDescription = evolution.map { "\($0.level.displayName) · \(activity)" }
            ?? activity
        guard let score else { return stationDescription }
        return "\(stationDescription) · Happiness \(score)"
    }

    @ViewBuilder
    private func stationHappinessCard(_ happiness: SettlementHappinessSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("Local happiness", systemImage: "heart.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(
                        TycoonTheme.happinessColor(for: happiness.happinessScore)
                    )

                Spacer(minLength: 6)

                Text(
                    "\(formattedHappinessScore(happiness.happinessScore)) · "
                        + happiness.band.label
                )
                .font(.caption.weight(.bold).monospacedDigit())
            }

            ProgressView(value: clampedUnitScore(happiness.happinessScore / 100))
                .tint(TycoonTheme.happinessColor(for: happiness.happinessScore))
                .accessibilityLabel("Local happiness")
                .accessibilityValue(formattedHappinessScore(happiness.happinessScore))

            HStack(alignment: .firstTextBaseline) {
                Text(
                    "\(happiness.reachableDestinationCount) reachable destination"
                        + (happiness.reachableDestinationCount == 1 ? "" : "s")
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

                Spacer(minLength: 6)

                if happiness.averageJourneyMinutes > 0 {
                    Text("Avg. \(formattedMinutes(happiness.averageJourneyMinutes))")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 6) {
                HappinessComponentRow(
                    title: "Reachable destinations",
                    weight: 30,
                    score: happiness.componentScores.reachableDestinations
                )
                HappinessComponentRow(
                    title: "Destination importance",
                    weight: 20,
                    score: happiness.componentScores.destinationImportance
                )
                HappinessComponentRow(
                    title: "Journey time",
                    weight: 20,
                    score: happiness.componentScores.journeyTime
                )
                HappinessComponentRow(
                    title: "Frequency",
                    weight: 15,
                    score: happiness.componentScores.frequency
                )
                HappinessComponentRow(
                    title: "Reliability",
                    weight: 10,
                    score: happiness.componentScores.reliability
                )
                HappinessComponentRow(
                    title: "Comfort",
                    weight: 5,
                    score: happiness.componentScores.crowding
                )
            }

            ForEach(Array(happiness.feedback.prefix(2).enumerated()), id: \.offset) { _, item in
                HappinessFeedbackRow(
                    item: item,
                    message: happinessFeedbackMessage(item)
                )
            }
        }
        .padding(10)
        .background(
            TycoonTheme.happinessColor(for: happiness.happinessScore).opacity(0.08),
            in: .rect(cornerRadius: 12)
        )
        .accessibilityElement(children: .contain)
    }

    private func stationEvolutionMessage(_ evolution: StationEvolutionStatus) -> String {
        guard let nextLevel = evolution.nextLevel else {
            return "Highest station level reached through served passenger visits."
        }

        switch evolution.promotionEligibility {
        case .eligible:
            return "Ready to upgrade to \(nextLevel.displayName) at the end of this operating day."
        case .needsPassengerVisits:
            return "\(formattedPassengerVisits(evolution.remainingPassengerVisits)) more served visits to \(nextLevel.displayName)."
        case let .needsConnectedDestinations(_, current, required):
            let remaining = max(required - current, 0)
            return "Connect \(remaining) more direct destination\(remaining == 1 ? "" : "s") to reach \(nextLevel.displayName)."
        case let .needsPassengerVisitsAndDestinations(
            _,
            remainingVisits,
            currentDestinations,
            requiredDestinations
        ):
            let remainingDestinations = max(requiredDestinations - currentDestinations, 0)
            return "\(formattedPassengerVisits(remainingVisits)) more served visits and "
                + "\(remainingDestinations) more direct destination"
                + "\(remainingDestinations == 1 ? "" : "s") to \(nextLevel.displayName)."
        case .maximumLevel:
            return "Highest station level reached through served passenger visits."
        }
    }

    private func platformLabel(_ count: Int) -> String {
        "\(count) platform\(count == 1 ? "" : "s")"
    }

    private func stationDestinationLabel(
        metrics: StationPassengerSnapshot?
    ) -> some View {
        let count = metrics?.connectedDestinationCount ?? 0
        return Label(
            "\(count) direct destination\(count == 1 ? "" : "s")",
            systemImage: "point.3.connected.trianglepath.dotted"
        )
        .font(.caption)
    }

    private var presentation: BottomPanelPresentation {
        BottomPanelPresentationPolicy.presentation(
            isBankrupt: session.financeLedger.isBankrupt,
            phase: session.phase,
            selectedTrainID: session.selectedTrain?.id,
            selectedStationCRS: session.selectedStation?.crs,
            showsNetworkPerformance: isShowingNetworkPerformance,
            hasLines: session.networkLineCount > 0
        )
    }
}

private enum NetworkDashboardSection: String, CaseIterable, Identifiable {
    case finance
    case happiness
    case prestige

    var id: Self { self }

    var title: String {
        switch self {
        case .finance: "Finance"
        case .happiness: "Happiness"
        case .prestige: "Prestige"
        }
    }

    var heading: String {
        switch self {
        case .finance: "Network finances"
        case .happiness: "Network happiness"
        case .prestige: "High-speed prestige"
        }
    }

    var subtitle: String {
        switch self {
        case .finance: "What your railway earns and owns"
        case .happiness: "Why your railway is useful"
        case .prestige: "Your landmark high-speed achievements"
        }
    }
}

private struct FinanceBreakdownRow: View {
    let title: String
    let value: String
    var emphasis = false
    var isWarning = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    rowTitle
                    rowValue
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    rowTitle
                    Spacer(minLength: 8)
                    rowValue
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var rowTitle: some View {
        Text(title)
            .font(emphasis ? .caption.weight(.bold) : .caption)
            .foregroundStyle(emphasis ? .primary : .secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var rowValue: some View {
        Text(value)
            .font(.caption.weight(emphasis ? .bold : .semibold).monospacedDigit())
            .foregroundStyle(isWarning ? TycoonTheme.construction : .primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private extension View {
    func financeSectionSurface() -> some View {
        padding(11)
            .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 12))
            .accessibilityElement(children: .contain)
    }
}

private struct BuildGuidanceCard: View {
    let step: Int
    let title: String
    let message: String
    let findStation: () -> Void
    let cancel: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(TycoonTheme.railGreen)
                    .frame(width: 44, height: 44)
                Text("\(step)")
                    .font(.headline.weight(.black).monospacedDigit())
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)

                Button(action: findStation) {
                    Label("Find station", systemImage: "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .accessibilityHint("Search the complete Great Britain station catalogue")
            }

            Spacer(minLength: 2)

            Button(action: cancel) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel building")
        }
        .padding(.leading, 13)
        .padding(.trailing, 8)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .railPanel()
    }
}

private struct StationFinderView: View {
    let title: String
    let stations: [Station]
    let eligibleStationCRSs: Set<String>
    let isLoadingEligibility: Bool
    let excludedStationCRS: String?
    let select: (Station) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let results = matchingStations
        NavigationStack {
            Group {
                if isLoadingEligibility {
                    ContentUnavailableView {
                        Label("Checking railway connections", systemImage: "point.3.connected.trianglepath.dotted")
                    } description: {
                        Text("Finding stations with a direct path through the railway map.")
                    }
                    .overlay(alignment: .top) {
                        ProgressView()
                            .padding(.top, 22)
                    }
                } else if normalizedQuery.isEmpty {
                    ContentUnavailableView(
                        "Find a connected station",
                        systemImage: "tram.fill",
                        description: Text(
                            "Search by station name or three-letter CRS code. \(eligibleStations.count.formatted()) of \(stations.count.formatted()) catalogue stations have a valid railway path for this line."
                        )
                    )
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(results) { station in
                        Button {
                            select(station)
                            dismiss()
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(station.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(station.crs)
                                        .font(.caption.monospaced().weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(station.name), code \(station.crs)")
                        .accessibilityHint("Selects this station")
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Station name or CRS"
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var normalizedQuery: String {
        StationSearchPolicy.normalizedText(query)
    }

    private var matchingStations: [Station] {
        StationSearchPolicy.results(
            matching: query,
            in: eligibleStations,
            excludingCRS: excludedStationCRS
        )
    }

    private var eligibleStations: [Station] {
        stations.filter {
            eligibleStationCRSs.contains(normalizedCRS($0.crs))
        }
    }

    private func normalizedCRS(_ crs: String) -> String {
        crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

private struct RouteSignalView: View {
    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(TycoonTheme.railGreenBright)
                .frame(width: 11, height: 11)
            Rectangle()
                .fill(Color.primary.opacity(0.42))
                .frame(width: 2, height: 24)
            Circle()
                .fill(TycoonTheme.construction)
                .frame(width: 11, height: 11)
        }
        .padding(.top, 4)
        .accessibilityHidden(true)
    }
}

private struct PreviewMetric: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct NetworkPerformanceMetric: View {
    let title: String
    let value: String
    var isRow = false

    var body: some View {
        Group {
            if isRow {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.caption.weight(.bold).monospacedDigit())
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(minHeight: 28, alignment: .bottomLeading)
                    Text(value)
                        .font(.caption.weight(.bold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .accessibilityElement(children: .combine)
    }
}

private struct HappinessComponentRow: View {
    let title: String
    let weight: Int
    let score: Double

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let normalized = score.isFinite ? min(max(score, 0), 1) : 0

        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    componentLabel(normalized: normalized)
                    ProgressView(value: normalized)
                }
            } else {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ProgressView(value: normalized)
                        .frame(width: 72)
                    Text(componentValue(normalized))
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 76, alignment: .trailing)
                }
            }
        }
        .tint(TycoonTheme.happinessColor(for: normalized * 100))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(weight) percent of happiness")
        .accessibilityValue(normalized.formatted(.percent.precision(.fractionLength(0))))
    }

    private func componentLabel(normalized: Double) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption2.weight(.semibold))
            Spacer(minLength: 6)
            Text(componentValue(normalized))
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func componentValue(_ normalized: Double) -> String {
        "\(weight)% weight · "
            + normalized.formatted(.percent.precision(.fractionLength(0)))
    }
}

private struct HappinessFeedbackRow: View {
    let item: HappinessFeedbackItem
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(
                systemName: item.sentiment == .positive
                    ? "checkmark.circle.fill"
                    : "exclamationmark.circle.fill"
            )
            .foregroundStyle(
                item.sentiment == .positive
                    ? TycoonTheme.railGreenBright
                    : TycoonTheme.construction
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.caption.weight(.bold))
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

nonisolated struct StationCapacityUIPresentation: Equatable, Sendable {
    let platformCount: Int
    let scheduledTrainCallsPerHour: Double
    let effectiveTrainCallsPerHour: Double
    let trainCallCapacityPerHour: Double
    let isConstrained: Bool
    let nextLevelName: String?
    let nextLevelPlatformCount: Int?

    init(
        platformCount: Int,
        scheduledTrainCallsPerHour: Double,
        effectiveTrainCallsPerHour: Double,
        trainCallCapacityPerHour: Double,
        isConstrained: Bool,
        nextLevelName: String?,
        nextLevelPlatformCount: Int?
    ) {
        self.platformCount = max(platformCount, 0)
        self.scheduledTrainCallsPerHour = Self.nonnegativeFinite(
            scheduledTrainCallsPerHour
        )
        self.effectiveTrainCallsPerHour = Self.nonnegativeFinite(
            effectiveTrainCallsPerHour
        )
        self.trainCallCapacityPerHour = Self.nonnegativeFinite(
            trainCallCapacityPerHour
        )
        self.isConstrained = isConstrained
            && self.scheduledTrainCallsPerHour > self.effectiveTrainCallsPerHour
        self.nextLevelName = nextLevelName
        self.nextLevelPlatformCount = nextLevelPlatformCount.map { max($0, 0) }
    }

    var utilization: Double {
        guard trainCallCapacityPerHour > 0 else {
            return effectiveTrainCallsPerHour > 0 ? 1 : 0
        }
        return min(max(effectiveTrainCallsPerHour / trainCallCapacityPerHour, 0), 1)
    }

    var nextLevelTrainCallCapacityPerHour: Double? {
        guard let nextLevelPlatformCount else { return nil }
        return Double(nextLevelPlatformCount)
            * StationCapacityConfiguration.poc.trainCallsPerPlatformPerHour
    }

    private static func nonnegativeFinite(_ value: Double) -> Double {
        value.isFinite ? max(value, 0) : 0
    }
}

nonisolated struct LineStationCapacityUIPresentation: Equatable, Sendable {
    let scheduledDeparturesPerHour: Double
    let effectiveDeparturesPerHour: Double
    let limitingStationNames: [String]
    let isOperating: Bool

    init(
        scheduledDeparturesPerHour: Double,
        effectiveDeparturesPerHour: Double,
        limitingStationNames: [String],
        isOperating: Bool
    ) {
        self.scheduledDeparturesPerHour = Self.nonnegativeFinite(
            scheduledDeparturesPerHour
        )
        self.effectiveDeparturesPerHour = Self.nonnegativeFinite(
            effectiveDeparturesPerHour
        )
        self.limitingStationNames = Array(Set(
            limitingStationNames.filter { !$0.isEmpty }
        )).sorted()
        self.isOperating = isOperating
    }

    var isConstrained: Bool {
        isOperating
            && effectiveDeparturesPerHour + 0.000_000_001 < scheduledDeparturesPerHour
    }

    var limitingStationsText: String {
        switch limitingStationNames.count {
        case 0:
            return "an endpoint station"
        case 1:
            return limitingStationNames[0]
        case 2:
            return limitingStationNames.joined(separator: " and ")
        default:
            return limitingStationNames.dropLast().joined(separator: ", ")
                + ", and " + (limitingStationNames.last ?? "an endpoint station")
        }
    }

    private static func nonnegativeFinite(_ value: Double) -> Double {
        value.isFinite ? max(value, 0) : 0
    }
}

struct StationCapacityPanel: View {
    let presentation: StationCapacityUIPresentation

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Platform throughput", systemImage: "arrow.up.arrow.down.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(
                    presentation.isConstrained
                        ? TycoonTheme.construction
                        : TycoonTheme.panelAccent
                )

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 6) {
                        capacityMetric(
                            title: "Platforms",
                            value: presentation.platformCount.formatted(),
                            isRow: true
                        )
                        capacityMetric(
                            title: "Scheduled calls/hour",
                            value: formattedRate(presentation.scheduledTrainCallsPerHour),
                            isRow: true
                        )
                        capacityMetric(
                            title: "Handled / capacity",
                            value: formattedRate(presentation.effectiveTrainCallsPerHour)
                                + " / "
                                + formattedRate(presentation.trainCallCapacityPerHour),
                            isRow: true
                        )
                    }
                } else {
                    HStack(spacing: 0) {
                        capacityMetric(
                            title: "Platforms",
                            value: presentation.platformCount.formatted()
                        )
                        Divider().frame(height: 30)
                        capacityMetric(
                            title: "Scheduled calls/hr",
                            value: formattedRate(presentation.scheduledTrainCallsPerHour)
                        )
                        Divider().frame(height: 30)
                        capacityMetric(
                            title: "Handled / capacity",
                            value: formattedRate(presentation.effectiveTrainCallsPerHour)
                                + " / "
                                + formattedRate(presentation.trainCallCapacityPerHour)
                        )
                    }
                }
            }

            ProgressView(value: presentation.utilization)
                .tint(
                    presentation.isConstrained
                        ? TycoonTheme.construction
                        : TycoonTheme.railGreenBright
                )
                .accessibilityLabel("Platform capacity used")
                .accessibilityValue(
                    presentation.utilization.formatted(
                        .percent.precision(.fractionLength(0))
                    )
                )

            HStack(alignment: .top, spacing: 7) {
                Image(
                    systemName: presentation.isConstrained
                        ? "exclamationmark.circle.fill"
                        : "checkmark.circle.fill"
                )
                .foregroundStyle(
                    presentation.isConstrained
                        ? TycoonTheme.construction
                        : TycoonTheme.railGreenBright
                )
                .accessibilityHidden(true)

                Text(statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (presentation.isConstrained
                ? TycoonTheme.construction
                : TycoonTheme.panelAccent).opacity(0.09),
            in: .rect(cornerRadius: 12)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Platform throughput")
        .accessibilityValue(accessibilityValue)
    }

    private var statusMessage: String {
        let capacity = formattedRate(presentation.trainCallCapacityPerHour)
        if presentation.isConstrained {
            let scheduled = formattedRate(presentation.scheduledTrainCallsPerHour)
            return "Platform bottleneck: \(scheduled) calls are scheduled each hour, but this "
                + "station can handle \(capacity). Services are being reduced proportionally. "
                + nextLevelMessage
        }
        return "This station can handle the full timetable. " + nextLevelMessage
    }

    private var nextLevelMessage: String {
        guard let nextLevelName = presentation.nextLevelName,
              let nextCapacity = presentation.nextLevelTrainCallCapacityPerHour else {
            return "This is the highest current station tier."
        }
        return "Automatic growth to \(nextLevelName) raises capacity to "
            + "\(formattedRate(nextCapacity)) calls/hour."
    }

    private var accessibilityValue: String {
        "\(presentation.platformCount) platforms, "
            + "\(formattedRate(presentation.scheduledTrainCallsPerHour)) scheduled train calls "
            + "per hour, \(formattedRate(presentation.effectiveTrainCallsPerHour)) handled, "
            + "capacity \(formattedRate(presentation.trainCallCapacityPerHour).lowercased()) "
            + "calls per hour. " + statusMessage
    }

    private func formattedRate(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func capacityMetric(title: String, value: String, isRow: Bool = false) -> some View {
        Group {
            if isRow {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(value)
                        .font(.caption.weight(.bold).monospacedDigit())
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(value)
                        .font(.caption.weight(.bold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
    }
}

struct LineStationCapacityPanel: View {
    let presentation: LineStationCapacityUIPresentation

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Station throughput", systemImage: "arrow.up.arrow.down.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(
                    presentation.isConstrained
                        ? TycoonTheme.construction
                        : TycoonTheme.panelAccent
                )

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 6) {
                        lineMetric(
                            title: "Scheduled departures/hour",
                            value: formattedRate(presentation.scheduledDeparturesPerHour),
                            isRow: true
                        )
                        lineMetric(
                            title: "Effective departures/hour",
                            value: formattedRate(presentation.effectiveDeparturesPerHour),
                            isRow: true
                        )
                    }
                } else {
                    HStack(spacing: 0) {
                        lineMetric(
                            title: "Scheduled departures/hr",
                            value: formattedRate(presentation.scheduledDeparturesPerHour)
                        )
                        Divider().frame(height: 30)
                        lineMetric(
                            title: "Effective departures/hr",
                            value: formattedRate(presentation.effectiveDeparturesPerHour)
                        )
                    }
                }
            }

            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (presentation.isConstrained
                ? TycoonTheme.construction
                : TycoonTheme.panelAccent).opacity(0.09),
            in: .rect(cornerRadius: 12)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Station throughput for this line")
        .accessibilityValue(
            "\(formattedRate(presentation.scheduledDeparturesPerHour)) scheduled and "
                + "\(formattedRate(presentation.effectiveDeparturesPerHour)) effective "
                + "departures per hour. " + message
        )
    }

    private var message: String {
        guard presentation.isOperating else {
            return "Effective service begins after construction finishes."
        }
        guard presentation.isConstrained else {
            return "Both endpoint stations can handle the full timetable."
        }
        return "\(presentation.limitingStationsText) cannot handle the full timetable yet. "
            + "Its station tier grows automatically with served passenger visits."
    }

    private func formattedRate(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func lineMetric(title: String, value: String, isRow: Bool = false) -> some View {
        Group {
            if isRow {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(value)
                        .font(.caption.weight(.bold).monospacedDigit())
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(value)
                        .font(.caption.weight(.bold).monospacedDigit())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
    }
}

nonisolated struct ConnectingRidersUIPresentation: Equatable, Sendable {
    let directRidersPerDay: Int
    let connectingRidersPerDay: Int

    init(directRidersPerDay: Int, connectingRidersPerDay: Int) {
        self.directRidersPerDay = max(directRidersPerDay, 0)
        self.connectingRidersPerDay = max(connectingRidersPerDay, 0)
    }

    var shouldShow: Bool { connectingRidersPerDay > 0 }

    var totalRidersPerDay: Int {
        let (total, overflow) = directRidersPerDay.addingReportingOverflow(
            connectingRidersPerDay
        )
        return overflow ? .max : total
    }

    var connectingSharePercentage: Int {
        let total = Double(directRidersPerDay) + Double(connectingRidersPerDay)
        guard total > 0, total.isFinite else { return 0 }
        return Int((Double(connectingRidersPerDay) / total * 100).rounded())
    }
}

nonisolated struct InterchangeDemandUIPresentation: Equatable, Sendable {
    let transferJourneysPerDay: Int

    init(transferJourneysPerDay: Int) {
        self.transferJourneysPerDay = max(transferJourneysPerDay, 0)
    }

    var shouldShow: Bool { transferJourneysPerDay > 0 }
}

nonisolated enum ConnectingJourneyUIPresentation {
    static func compactRiderCount(_ value: Int) -> String {
        max(value, 0).formatted(
            .number
                .notation(.compactName)
                .precision(.fractionLength(0...1))
        )
    }

    static func fullRiderCount(_ value: Int) -> String {
        max(value, 0).formatted(.number)
    }
}

struct ConnectingRidersPanel: View {
    let presentation: ConnectingRidersUIPresentation

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Rider mix", systemImage: "arrow.triangle.branch")
                .font(.caption.weight(.bold))
                .foregroundStyle(TycoonTheme.panelAccent)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 6) {
                        ConnectingJourneyMetric(
                            title: "Direct riders/day",
                            value: ConnectingJourneyUIPresentation.compactRiderCount(
                                presentation.directRidersPerDay
                            ),
                            isRow: true
                        )
                        ConnectingJourneyMetric(
                            title: "Connecting riders/day",
                            value: ConnectingJourneyUIPresentation.compactRiderCount(
                                presentation.connectingRidersPerDay
                            ),
                            isRow: true,
                            isAccented: true
                        )
                    }
                } else {
                    HStack(spacing: 0) {
                        ConnectingJourneyMetric(
                            title: "Direct riders/day",
                            value: ConnectingJourneyUIPresentation.compactRiderCount(
                                presentation.directRidersPerDay
                            )
                        )
                        Divider().frame(height: 30)
                        ConnectingJourneyMetric(
                            title: "Connecting riders/day",
                            value: ConnectingJourneyUIPresentation.compactRiderCount(
                                presentation.connectingRidersPerDay
                            ),
                            isAccented: true
                        )
                    }
                }
            }

            Text(
                "\(presentation.connectingSharePercentage)% continue beyond this line "
                    + "with one change."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TycoonTheme.panelAccent.opacity(0.08), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rider mix")
        .accessibilityValue(
            "\(ConnectingJourneyUIPresentation.fullRiderCount(presentation.directRidersPerDay)) "
                + "direct riders per day. "
                + "\(ConnectingJourneyUIPresentation.fullRiderCount(presentation.connectingRidersPerDay)) "
                + "connecting riders per day. "
                + "\(presentation.connectingSharePercentage) percent continue beyond this line "
                + "with one change."
        )
    }
}

struct InterchangeDemandPanel: View {
    let presentation: InterchangeDemandUIPresentation

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        heading
                        transferValue
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        heading
                        Spacer(minLength: 4)
                        transferValue
                    }
                }
            }

            Text("Passengers change between services here. Each through journey is counted once.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TycoonTheme.panelAccent.opacity(0.08), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Interchange demand")
        .accessibilityValue(
            "\(ConnectingJourneyUIPresentation.fullRiderCount(presentation.transferJourneysPerDay)) "
                + "unique transfer journeys per day. Passengers change between services here."
        )
    }

    private var heading: some View {
        Label("Interchange demand", systemImage: "arrow.left.arrow.right.circle.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(TycoonTheme.panelAccent)
    }

    private var transferValue: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(
                ConnectingJourneyUIPresentation.compactRiderCount(
                    presentation.transferJourneysPerDay
                )
            )
            .font(.subheadline.weight(.black).monospacedDigit())
            .foregroundStyle(TycoonTheme.panelAccent)
            Text("unique transfers/day")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ConnectingJourneyMetric: View {
    let title: String
    let value: String
    var isRow = false
    var isAccented = false

    var body: some View {
        Group {
            if isRow {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    metricValue
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    metricValue
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 7)
            }
        }
    }

    private var metricValue: some View {
        Text(value)
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(isAccented ? TycoonTheme.panelAccent : Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
    }
}

nonisolated struct SettlementGrowthUIPresentation: Equatable, Sendable {
    let population: Int64
    let latestChange: Int64
    let demandMultiplier: Double
    let reason: String

    init(
        population: Int64,
        latestChange: Int64,
        demandMultiplier: Double,
        reason: String
    ) {
        self.population = max(population, 0)
        self.latestChange = latestChange
        self.demandMultiplier = demandMultiplier.isFinite && demandMultiplier > 0
            ? demandMultiplier
            : 1
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        self.reason = normalizedReason.isEmpty
            ? "Railway accessibility is not changing local growth yet."
            : normalizedReason
    }
}

struct SettlementGrowthPanel: View {
    let presentation: SettlementGrowthUIPresentation

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 3) {
                        heading
                        populationValue
                        growthAndDemand
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        heading
                        Spacer(minLength: 4)
                        populationValue
                    }
                    growthAndDemand
                }
            }

            Text(presentation.reason)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TycoonTheme.railGreen.opacity(0.08), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Synthetic gameplay population")
        .accessibilityValue(
            "\(PopulationUIPresentation.fullPopulation(presentation.population)). "
                + "\(PopulationUIPresentation.changeDescription(presentation.latestChange)). "
                + "Passenger demand multiplier "
                + "\(PopulationUIPresentation.demandMultiplier(presentation.demandMultiplier)). "
                + presentation.reason
        )
    }

    private var heading: some View {
        Label("Synthetic gameplay population", systemImage: "house.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(TycoonTheme.panelAccent)
    }

    private var populationValue: some View {
        Text(PopulationUIPresentation.fullPopulation(presentation.population))
            .font(.subheadline.weight(.black).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    private var growthAndDemand: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 3) {
                    changeLabel
                    demandLabel
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    changeLabel
                    Spacer(minLength: 4)
                    demandLabel
                }
            }
        }
    }

    private var changeLabel: some View {
        Label(
            PopulationUIPresentation.compactChange(presentation.latestChange),
            systemImage: PopulationUIPresentation.changeSymbol(presentation.latestChange)
        )
        .font(.caption2.weight(.bold).monospacedDigit())
        .foregroundStyle(
            presentation.latestChange < 0 ? Color.orange : TycoonTheme.panelAccent
        )
    }

    private var demandLabel: some View {
        Text(
            "Demand \(PopulationUIPresentation.demandMultiplier(presentation.demandMultiplier))"
        )
        .font(.caption2.weight(.semibold).monospacedDigit())
        .foregroundStyle(.secondary)
    }
}

private struct NetworkPulseMetric: View {
    let title: String
    let value: String
    let systemImage: String
    var isRow = false

    var body: some View {
        Group {
            if isRow {
                VStack(alignment: .leading, spacing: 2) {
                    Label(title, systemImage: systemImage)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.caption.weight(.bold).monospacedDigit())
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Label(title, systemImage: systemImage)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 28, alignment: .bottomLeading)
                    Text(value)
                        .font(.caption.weight(.bold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
    }
}

private struct PassengerCardMetric: View {
    let title: String
    let value: String
    var isRow = false

    var body: some View {
        Group {
            if isRow {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.caption.weight(.bold).monospacedDigit())
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(value)
                        .font(.caption.weight(.bold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }
}
