import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Game presentation policies")
struct GamePresentationPolicyTests {
    @Test("Root overlays have one stable priority order")
    func modalPriority() {
        #expect(activeModal() == nil)
        #expect(activeModal(newGame: true) == .newGameConfirmation)
        #expect(activeModal(stationAddition: true) == .stationAddition)
        #expect(
            activeModal(settings: true, newGame: true, stationAddition: true)
                == .stationAddition
        )
        #expect(activeModal(menu: true, newGame: true) == .gameMenu)
        #expect(activeModal(progress: true, menu: true, newGame: true) == .progress)
        #expect(
            activeModal(settings: true, progress: true, menu: true, newGame: true)
                == .settings
        )
        #expect(
            activeModal(
                onboarding: true,
                settings: true,
                progress: true,
                menu: true,
                newGame: true
            ) == .onboarding
        )
    }

    @Test("Journey rewards only appear over an unobscured operating map")
    func journeyFeedbackVisibility() {
        for phase in GamePhase.allCases {
            let expected = phase == .idle || phase == .operating
            #expect(
                GameRootPresentationPolicy.allowsJourneyFeedback(
                    hasActiveModal: false,
                    hasSelectedTrain: false,
                    hasSelectedStation: false,
                    phase: phase
                ) == expected
            )
        }

        #expect(!allowsJourneyFeedback(modal: true))
        #expect(!allowsJourneyFeedback(train: true))
        #expect(!allowsJourneyFeedback(station: true))
    }

    @Test("Bottom panels preserve blocking and selection precedence")
    func bottomPanelPrecedence() {
        let trainID = UUID(uuidString: "A15C35B1-243D-49C7-8866-FF21BB0DAB01")!

        #expect(
            panel(
                bankrupt: true,
                phase: .operating,
                trainID: trainID,
                stationCRS: "VIC",
                network: true,
                hasLines: true
            ) == .bankrupt
        )
        #expect(
            panel(
                phase: .selectingDestination,
                trainID: trainID,
                stationCRS: "VIC",
                network: true,
                hasLines: true
            ) == .destination
        )
        #expect(
            panel(
                trainID: trainID,
                stationCRS: "VIC",
                network: true,
                hasLines: true
            ) == .train(trainID)
        )
        #expect(
            panel(stationCRS: " vic ", network: true, hasLines: true)
                == .station(" vic ")
        )
        #expect(panel(network: true, hasLines: true) == .network)
        #expect(panel(network: true, hasLines: false) == .build)
    }

    @Test("Dismissing a station returns a completed network to a compact bottom summary")
    func completedNetworkStationDismissal() {
        let selectedPresentation = panel(stationCRS: "ECR", hasLines: true)
        #expect(selectedPresentation == .station("ECR"))
        #expect(
            !BottomPanelPresentationPolicy.showsBuildAction(
                for: selectedPresentation,
                canBuildAnotherLine: false
            )
        )

        let dismissedPresentation = panel(hasLines: true)
        #expect(dismissedPresentation == .build)
        #expect(
            !BottomPanelPresentationPolicy.showsBuildAction(
                for: dismissedPresentation,
                canBuildAnotherLine: false
            )
        )

        #expect(
            BottomPanelPresentationPolicy.showsBuildAction(
                for: dismissedPresentation,
                canBuildAnotherLine: true
            )
        )
    }

    @Test("Every game phase maps to its intended bottom panel")
    func phasePanels() {
        let expected: [GamePhase: BottomPanelPresentation] = [
            .idle: .build,
            .selectingOrigin: .origin,
            .selectingDestination: .destination,
            .calculating: .calculating,
            .preview: .preview,
            .constructing: .constructing,
            .operating: .build,
            .error: .error,
        ]

        for phase in GamePhase.allCases {
            #expect(panel(phase: phase) == expected[phase])
        }
    }

    @Test("Portrait panel height is bounded and accessibility-aware")
    func bottomPanelHeight() {
        #expect(
            GameRootPresentationPolicy.maximumBottomPanelHeight(
                containerHeight: 400,
                usesAccessibilityTextSize: false
            ) == 260
        )
        let regularHeight = GameRootPresentationPolicy.maximumBottomPanelHeight(
            containerHeight: 844,
            usesAccessibilityTextSize: false
        )
        let accessibilityHeight = GameRootPresentationPolicy.maximumBottomPanelHeight(
            containerHeight: 844,
            usesAccessibilityTextSize: true
        )
        #expect(abs(regularHeight - 472.64) < 0.001)
        #expect(abs(accessibilityHeight - 506.4) < 0.001)
    }

    @Test("Line numbers remain stable and one based")
    func stableLineNumbers() {
        #expect(LineIdentityPresentationPolicy.displayNumber(styleIndex: 0) == 1)
        #expect(LineIdentityPresentationPolicy.displayNumber(styleIndex: 5) == 6)
        #expect(LineIdentityPresentationPolicy.displayNumber(styleIndex: 11) == 12)
        #expect(LineIdentityPresentationPolicy.displayNumber(styleIndex: -1) == 1)
    }

    private func activeModal(
        onboarding: Bool = false,
        settings: Bool = false,
        progress: Bool = false,
        menu: Bool = false,
        newGame: Bool = false,
        stationAddition: Bool = false
    ) -> GameRootModalPresentation? {
        GameRootPresentationPolicy.activeModal(
            showsOnboarding: onboarding,
            showsSettings: settings,
            showsProgress: progress,
            showsGameMenu: menu,
            showsNewGameConfirmation: newGame,
            showsStationAddition: stationAddition
        )
    }

    private func allowsJourneyFeedback(
        modal: Bool = false,
        train: Bool = false,
        station: Bool = false
    ) -> Bool {
        GameRootPresentationPolicy.allowsJourneyFeedback(
            hasActiveModal: modal,
            hasSelectedTrain: train,
            hasSelectedStation: station,
            phase: .operating
        )
    }

    private func panel(
        bankrupt: Bool = false,
        phase: GamePhase = .operating,
        trainID: UUID? = nil,
        stationCRS: String? = nil,
        network: Bool = false,
        hasLines: Bool = false
    ) -> BottomPanelPresentation {
        BottomPanelPresentationPolicy.presentation(
            isBankrupt: bankrupt,
            phase: phase,
            selectedTrainID: trainID,
            selectedStationCRS: stationCRS,
            showsNetworkPerformance: network,
            hasLines: hasLines
        )
    }
}
