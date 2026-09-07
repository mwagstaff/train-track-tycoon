import SwiftUI

struct GameRootView: View {
    @Bindable var session: GameSession
    @Environment(\.colorScheme) private var deviceColorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AccessibilityFocusState private var isUpgradeFocused: Bool
    @State private var profile = PlayerProfileStore()
    @State private var worldEnvironment = WorldEnvironmentController()
    @State private var audio = GameAudioController()
    @State private var showsHappinessHeatmap = false
    @State private var isShowingNetworkPerformance = false
    @State private var isShowingGameMenu = false
    @State private var pendingNewGameMode: GameMode?
    @State private var isShowingOnboarding = false
    @State private var isShowingSettings = false
    @State private var progressSection: PublicBetaHubSection?
    @State private var achievementQueue: [PublicBetaAchievementDefinition] = []
    @State private var completedScenarioBanner: PublicBetaScenarioDefinition?
    @State private var lastHandledPresentationEventSequence: UInt64 = 0
    @State private var majorPresentationFeedbackSequence: UInt64?
    @State private var appliedMapAppearance: WorldMapAppearance?
    @State private var mapAppearanceFadeOpacity = 0.0
    @State private var isShowingLineDirectory = false
    @State private var lineFocusSequence: UInt64 = 0
    @State private var lineFocusRequest: LineMapFocusRequest?

    var body: some View {
        lifecycleContent
    }

    private var lifecycleContent: some View {
        observedContent
            .onChange(of: session.simulationSpeed) { _, _ in
                synchronizeWorldEnvironment()
            }
            .onChange(of: profile.isSoundEnabled) { _, isEnabled in
                audio.isEnabled = isEnabled
            }
            .onChange(of: profile.areWorldEffectsEnabled) { _, _ in
                synchronizeWorldEnvironment()
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                handleScenePhaseChange(oldPhase, newPhase)
            }
            .task {
                await preparePresentation()
            }
            .onDisappear {
                tearDownPresentation()
            }
    }

    private var observedContent: some View {
        feedbackContent
            .onChange(of: session.stationUpgradeEvent?.id) { _, eventID in
                isUpgradeFocused = eventID != nil
            }
            .onChange(of: session.persistenceRevision) { _, _ in
                evaluatePublicBetaProgress()
                if session.networkLineCount == 0 { closeLineDirectory() }
            }
            .onChange(of: session.latestPresentationEvent?.sequence) { _, _ in
                handlePresentationEvent()
            }
            .onChange(of: session.isPlaying) { _, _ in
                synchronizeWorldEnvironment()
            }
            .onChange(of: session.selectedTrainID) { _, selectedTrainID in
                guard selectedTrainID != nil else { return }
                closeLineDirectory()
            }
            .onChange(of: session.selectedStationID) { _, selectedStationID in
                guard selectedStationID != nil else { return }
                closeLineDirectory()
            }
            .onChange(of: isPresentationObscured) { _, isObscured in
                if isObscured {
                    audio.stopAll()
                }
            }
    }

    private var feedbackContent: some View {
        rootLayout
            .foregroundStyle(.primary)
            .sensoryFeedback(
                .impact(weight: .medium),
                trigger: majorPresentationFeedbackSequence
            ) { oldValue, newValue in
                oldValue != newValue && newValue != nil
            }
            .sensoryFeedback(.success, trigger: achievementQueue.first?.id) { _, newValue in
                newValue != nil
            }
            .sensoryFeedback(.success, trigger: completedScenarioBanner?.id) { _, newValue in
                newValue != nil
            }
    }

    private var rootLayout: some View {
        GeometryReader { geometry in
            ZStack {
                mapAndAtmosphere
                statusBarContrastScrim(in: geometry)
                gameChrome(maximumBottomPanelHeight: maximumBottomPanelHeight(in: geometry))
                modalOverlay
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.18),
                value: isShowingGameMenu
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.18),
                value: pendingNewGameMode
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.18),
                value: isShowingSettings
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.18),
                value: progressSection
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.18),
                value: session.mapStationAdditionProposal?.id
            )
        }
    }

    @ViewBuilder
    private var mapAndAtmosphere: some View {
        GameMapView(
            session: session,
            showsHappinessHeatmap: showsHappinessHeatmap,
            allowsJourneyFeedback: !isPresentationObscured,
            lineFocusRequest: lineFocusRequest,
            onVisibleTrainArrival: handleVisibleTrainArrival
        )
        .environment(\.colorScheme, mapColorScheme)
        .overlay {
            MapAppearanceFadeVeil(
                targetAppearance: desiredMapAppearance,
                opacity: mapAppearanceFadeOpacity
            )
        }
        .task(id: mapAppearanceTransitionRequest) {
            await transitionMapAppearance(to: desiredMapAppearance)
        }
        .ignoresSafeArea()

        if profile.areWorldEffectsEnabled {
            WorldEffectsView(
                snapshot: worldEnvironment.snapshot,
                intensity: 0.92,
                showsWeather: profile.isWeatherEnabled
            )
            .ignoresSafeArea()
        }
    }

    private var mapColorScheme: ColorScheme {
        switch appliedMapAppearance ?? desiredMapAppearance {
        case .light: .light
        case .dark: .dark
        }
    }

    private var desiredMapAppearance: WorldMapAppearance {
        guard profile.areWorldEffectsEnabled else {
            return deviceColorScheme == .dark ? .dark : .light
        }
        return worldEnvironment.snapshot.preferredMapAppearance
    }

    private var mapAppearanceTransitionRequest: MapAppearanceTransitionRequest {
        MapAppearanceTransitionRequest(
            appearance: desiredMapAppearance,
            reduceMotion: reduceMotion
        )
    }

    private var isPresentationObscured: Bool {
        !GameRootPresentationPolicy.allowsJourneyFeedback(
            hasActiveModal: activeModalPresentation != nil || isShowingLineDirectory,
            hasSelectedTrain: session.selectedTrainID != nil,
            hasSelectedStation: session.selectedStationID != nil,
            phase: session.phase
        )
    }

    private var activeModalPresentation: GameRootModalPresentation? {
        GameRootPresentationPolicy.activeModal(
            showsOnboarding: isShowingOnboarding,
            showsSettings: isShowingSettings,
            showsProgress: progressSection != nil,
            showsGameMenu: isShowingGameMenu,
            showsNewGameConfirmation: pendingNewGameMode != nil,
            showsStationAddition: session.mapStationAdditionProposal != nil
        )
    }

    private func statusBarContrastScrim(in geometry: GeometryProxy) -> some View {
        let scrimColor = deviceColorScheme == .dark ? Color.black : Color.white
        return LinearGradient(
            colors: [scrimColor.opacity(0.62), scrimColor.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: max(geometry.safeAreaInsets.top + 28, 58))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func gameChrome(maximumBottomPanelHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            TopStatusHUD(session: session, showLineDirectory: openLineDirectory) {
                closeLineDirectory()
                isShowingGameMenu = true
            }
            .frame(maxWidth: 430)

            worldStatus
            noticeBanner

            Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 16 : 84)
            bottomControls(maximumHeight: maximumBottomPanelHeight)
        }
        .padding(.horizontal, 12)
        .safeAreaPadding(.top, 8)
        .safeAreaPadding(.bottom, 5)
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.32),
            value: session.stationUpgradeEvent?.id
        )
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.32),
            value: achievementQueue.first?.id
        )
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.32),
            value: completedScenarioBanner?.id
        )
    }

    @ViewBuilder
    private var worldStatus: some View {
        if profile.areWorldEffectsEnabled {
            HStack {
                Spacer(minLength: 0)
                WorldStatusBadge(
                    snapshot: worldEnvironment.snapshot,
                    showsWeather: profile.isWeatherEnabled
                )
            }
            .frame(maxWidth: 430)
            .padding(.top, 7)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var noticeBanner: some View {
        if let upgrade = session.stationUpgradeEvent {
            StationUpgradeBanner(event: upgrade) {
                session.dismissStationUpgradeEvent(id: upgrade.id)
            }
            .frame(maxWidth: 430)
            .padding(.top, 7)
            .accessibilityFocused($isUpgradeFocused)
            .transition(
                reduceMotion
                    ? .opacity
                    : .move(edge: .top).combined(with: .opacity)
            )
        } else if let scenario = completedScenarioBanner {
            ScenarioCompletedBanner(scenario: scenario) {
                completedScenarioBanner = nil
            }
            .frame(maxWidth: 430)
            .padding(.top, 7)
            .transition(
                reduceMotion
                    ? .opacity
                    : .move(edge: .top).combined(with: .opacity)
            )
        } else if let achievement = achievementQueue.first {
            AchievementUnlockedBanner(achievement: achievement) {
                dismissAchievement(id: achievement.id)
            }
            .frame(maxWidth: 430)
            .padding(.top, 7)
            .transition(
                reduceMotion
                    ? .opacity
                    : .move(edge: .top).combined(with: .opacity)
            )
        }
    }

    @ViewBuilder
    private var modalOverlay: some View {
        switch activeModalPresentation {
        case .onboarding:
            onboardingOverlay
        case .stationAddition:
            if let proposal = session.mapStationAdditionProposal {
                MapStationAdditionOverlay(
                    proposal: proposal,
                    isLoading: session.isLoadingMapStationAdditionProposal,
                    confirm: { lineID in
                        session.confirmMapStationAddition(onLineID: lineID)
                    },
                    cancel: session.cancelMapStationAddition
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(115)
            }
        case .settings:
            settingsOverlay
        case .progress:
            if let progressSection {
                progressOverlay(initialSection: progressSection)
            }
        case .gameMenu:
            gameMenuOverlay
        case .newGameConfirmation:
            if let pendingNewGameMode {
                newGameOverlay(mode: pendingNewGameMode)
            }
        case nil:
            EmptyView()
        }
    }

    private var onboardingOverlay: some View {
        OnboardingOverlay(profile: profile) {
            isShowingOnboarding = false
        } onBuildLine: {
            isShowingOnboarding = false
            session.startBuilding()
        }
        .transition(.opacity)
        .zIndex(120)
    }

    private var settingsOverlay: some View {
        PublicBetaSettingsOverlay(profile: profile) {
            isShowingSettings = false
        } onShowTutorial: {
            isShowingSettings = false
            isShowingOnboarding = true
        } onShowAchievements: {
            isShowingSettings = false
            progressSection = .achievements
        } onShowScenarios: {
            isShowingSettings = false
            progressSection = .scenarios
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .zIndex(110)
    }

    private func progressOverlay(initialSection: PublicBetaHubSection) -> some View {
        PublicBetaProgressOverlay(
            session: session,
            profile: profile,
            initialSection: initialSection
        ) {
            progressSection = nil
        } onStartScenario: { scenario in
            startScenario(scenario)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .zIndex(110)
    }

    private var gameMenuOverlay: some View {
        GameMenuOverlay(
            currentMode: session.gameMode,
            showProgress: {
                isShowingGameMenu = false
                progressSection = .achievements
            },
            showSettings: {
                isShowingGameMenu = false
                isShowingSettings = true
            }
        ) { mode in
            isShowingGameMenu = false
            pendingNewGameMode = mode
        } cancel: {
            isShowingGameMenu = false
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .zIndex(100)
    }

    private func newGameOverlay(mode: GameMode) -> some View {
        NewGameConfirmationOverlay(mode: mode) {
            pendingNewGameMode = nil
            audio.stopAll()
            profile.clearActiveScenario()
            completedScenarioBanner = nil
            worldEnvironment.reset()
            session.reset(gameMode: mode)
        } cancel: {
            pendingNewGameMode = nil
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .zIndex(100)
    }

    private func maximumBottomPanelHeight(in geometry: GeometryProxy) -> CGFloat {
        GameRootPresentationPolicy.maximumBottomPanelHeight(
            containerHeight: geometry.size.height,
            usesAccessibilityTextSize: dynamicTypeSize.isAccessibilitySize
        )
    }

    private func bottomControls(maximumHeight: CGFloat) -> some View {
        BottomControlsViewport(maximumHeight: maximumHeight) {
            bottomControlPanel(maximumHeight: maximumHeight)
        }
    }

    @ViewBuilder
    private func bottomControlPanel(maximumHeight: CGFloat) -> some View {
        if isShowingLineDirectory {
            LineDirectoryPanel(
                lines: session.lines,
                maximumHeight: maximumHeight,
                manageLine: manageLine,
                close: closeLineDirectory
            )
        } else {
            BottomControlPanel(
                session: session,
                showsHappinessHeatmap: $showsHappinessHeatmap,
                isShowingNetworkPerformance: $isShowingNetworkPerformance
            )
        }
    }

    private func openLineDirectory() {
        guard !session.lines.isEmpty,
              GameRootPresentationPolicy.isNormalOperatingPhase(session.phase) else {
            return
        }
        session.selectTrain(nil)
        session.selectStationForInspection(nil)
        isShowingNetworkPerformance = false
        isShowingLineDirectory = true
    }

    private func manageLine(_ lineID: UUID) {
        guard let line = session.lines.first(where: { $0.id == lineID }) else { return }
        lineFocusSequence = lineFocusSequence == .max ? 1 : lineFocusSequence + 1
        lineFocusRequest = LineMapFocusRequest(
            lineID: lineID,
            sequence: lineFocusSequence
        )
        closeLineDirectory()
        if let firstTrain = line.trains.first {
            session.selectTrain(firstTrain.id)
        }
    }

    private func closeLineDirectory() {
        isShowingLineDirectory = false
    }

    private func synchronizeWorldEnvironment() {
        worldEnvironment.setPaused(!session.isPlaying)
        worldEnvironment.setRate(
            session.simulationSpeed == .threeX ? .tripleSpeed : .normal
        )
        if scenePhase == .active,
           session.isPlaying,
           profile.areWorldEffectsEnabled {
            worldEnvironment.start()
        } else {
            worldEnvironment.stop()
        }
    }

    private func preparePresentation() async {
        audio.isEnabled = profile.isSoundEnabled
        synchronizeWorldEnvironment()
        evaluatePublicBetaProgress()
        if !profile.hasCompletedTutorial {
            isShowingOnboarding = true
        }
    }

    private func handleScenePhaseChange(_ oldPhase: ScenePhase, _ newPhase: ScenePhase) {
        let isActive = newPhase == .active
        if isActive {
            synchronizeWorldEnvironment()
        } else {
            worldEnvironment.stop()
            audio.stopAll()
        }
    }

    private func tearDownPresentation() {
        worldEnvironment.stop()
        audio.shutdown()
    }

    private func handlePresentationEvent() {
        guard session.latestPresentationEvent != nil else {
            audio.stopAll()
            return
        }
        let events = session.presentationEvents(after: lastHandledPresentationEventSequence)
        var cueToPlay: GameAudioCue?
        var majorFeedbackSequence: UInt64?
        for event in events {
            lastHandledPresentationEventSequence = event.sequence
            switch event.kind {
            case .lineOpened:
                cueToPlay = .lineOpened
                majorFeedbackSequence = event.sequence
            case .stationUpgraded, .infrastructureUpgraded:
                cueToPlay = .stationUpgrade
                majorFeedbackSequence = event.sequence
            case .constructionStarted:
                majorFeedbackSequence = event.sequence
            case .operatingDayCompleted, .trainArrived:
                break
            }
        }
        if let majorFeedbackSequence {
            self.majorPresentationFeedbackSequence = majorFeedbackSequence
        }
        if let cueToPlay { audio.play(cueToPlay) }
    }

    private func handleVisibleTrainArrival(soundsHorn: Bool) {
        audio.play(.fareCollected)
        if soundsHorn {
            audio.play(.trainHorn)
        }
    }

    @MainActor
    private func transitionMapAppearance(to target: WorldMapAppearance) async {
        guard let current = appliedMapAppearance else {
            appliedMapAppearance = target
            mapAppearanceFadeOpacity = 0
            return
        }

        guard WorldMapAppearanceTransitionPolicy.shouldAnimate(
            from: current,
            to: target,
            reduceMotion: reduceMotion
        ) else {
            appliedMapAppearance = target
            mapAppearanceFadeOpacity = 0
            return
        }

        let coverDuration = Double(
            WorldMapAppearanceTransitionPolicy.coverDurationMilliseconds
        ) / 1_000
        withAnimation(.easeInOut(duration: coverDuration)) {
            mapAppearanceFadeOpacity = WorldMapAppearanceTransitionPolicy.maximumCoverOpacity
        }

        do {
            try await Task.sleep(
                for: .milliseconds(
                    WorldMapAppearanceTransitionPolicy.coverDurationMilliseconds
                )
            )
        } catch {
            return
        }
        guard !Task.isCancelled else { return }

        // The same Map remains mounted, retaining its camera, gestures and annotation state.
        // Only its environment-driven native palette changes beneath the nearly opaque veil.
        appliedMapAppearance = target

        do {
            try await Task.sleep(
                for: .milliseconds(
                    WorldMapAppearanceTransitionPolicy.mapRedrawSettleMilliseconds
                )
            )
        } catch {
            return
        }
        guard !Task.isCancelled else { return }

        let revealDuration = Double(
            WorldMapAppearanceTransitionPolicy.revealDurationMilliseconds
        ) / 1_000
        withAnimation(.easeOut(duration: revealDuration)) {
            mapAppearanceFadeOpacity = 0
        }
    }

    private func evaluatePublicBetaProgress() {
        let previouslyUnlocked = Set(
            profile.unlockedAchievementIDs.compactMap(achievementID(from:))
        )
        let evaluation = PublicBetaAchievementCatalogue.publicBeta.evaluate(
            facts: session.publicBetaFacts,
            previouslyUnlocked: previouslyUnlocked
        )

        for id in evaluation.newlyUnlockedIDs {
            profile.unlockAchievement(id: id.rawValue)
            guard let definition = PublicBetaAchievementCatalogue.publicBeta.definition(for: id),
                  !achievementQueue.contains(where: { $0.id == id }) else { continue }
            achievementQueue.append(definition)
        }
        if !evaluation.newlyUnlockedIDs.isEmpty {
            audio.play(.achievementUnlocked)
        }

        guard let storedScenarioID = profile.activeScenarioID,
              let scenarioID = scenarioID(from: storedScenarioID),
              let scenario = PublicBetaScenarioCatalogue.publicBeta.evaluate(
                  scenarioID: scenarioID,
                  facts: session.publicBetaFacts
              ),
              scenario.isComplete else { return }
        let alreadyCompleted = profile.completedScenarioIDs.contains {
            $0.caseInsensitiveCompare(scenarioID.rawValue) == .orderedSame
        }
        guard !alreadyCompleted else { return }
        profile.markScenarioCompleted(id: scenarioID.rawValue)
        completedScenarioBanner = scenario.scenario
        audio.play(.achievementUnlocked)
    }

    private func startScenario(_ scenario: PublicBetaScenarioDefinition) {
        audio.stopAll()
        profile.setActiveScenario(id: scenario.id.rawValue)
        completedScenarioBanner = nil
        worldEnvironment.reset()
        session.reset(gameMode: scenario.recommendedMode)
        progressSection = nil
    }

    private func dismissAchievement(id: PublicBetaAchievementID) {
        guard achievementQueue.first?.id == id else { return }
        achievementQueue.removeFirst()
    }

    private func achievementID(from storedID: String) -> PublicBetaAchievementID? {
        PublicBetaAchievementID.allCases.first {
            $0.rawValue.caseInsensitiveCompare(storedID) == .orderedSame
        }
    }

    private func scenarioID(from storedID: String) -> PublicBetaScenarioID? {
        PublicBetaScenarioID.allCases.first {
            $0.rawValue.caseInsensitiveCompare(storedID) == .orderedSame
        }
    }

}

/// Keeps compact controls at their intrinsic height so visually empty space continues to belong
/// to the map. Detail cards gain a bounded scroll region only when their content truly needs it.
struct BottomControlsViewport<Content: View>: View {
    let maximumHeight: CGFloat
    let content: Content

    init(maximumHeight: CGFloat, @ViewBuilder content: () -> Content) {
        self.maximumHeight = maximumHeight
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
                .frame(maxWidth: 430)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                content
                    .frame(maxWidth: 430)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: maximumHeight)
        }
        .frame(maxWidth: 430)
        .frame(maxHeight: maximumHeight, alignment: .bottom)
    }
}

private struct MapAppearanceTransitionRequest: Equatable {
    let appearance: WorldMapAppearance
    let reduceMotion: Bool
}

private struct MapAppearanceFadeVeil: View {
    let targetAppearance: WorldMapAppearance
    let opacity: Double

    var body: some View {
        LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var colors: [Color] {
        switch targetAppearance {
        case .light:
            [
                Color(red: 0.91, green: 0.91, blue: 0.86),
                Color(red: 0.78, green: 0.84, blue: 0.81),
            ]
        case .dark:
            [
                Color(red: 0.025, green: 0.065, blue: 0.12),
                Color(red: 0.045, green: 0.10, blue: 0.15),
            ]
        }
    }
}

#Preview {
    let stations = [
        Station(crs: "VIC", name: "London Victoria", latitude: 51.4952, longitude: -0.1441),
        Station(crs: "BTN", name: "Brighton", latitude: 50.8289, longitude: -0.1410),
    ]
    GameRootView(session: GameSession(stations: stations))
}
