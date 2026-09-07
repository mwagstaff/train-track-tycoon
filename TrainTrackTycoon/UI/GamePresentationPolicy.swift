import CoreGraphics
import Foundation

/// The mutually exclusive overlay presented above the game map.
///
/// Keeping this priority outside `GameRootView` makes the modal contract deterministic and
/// independently testable without mounting MapKit in a UI test.
nonisolated enum GameRootModalPresentation: Equatable, Sendable {
    case onboarding
    case stationAddition
    case settings
    case progress
    case gameMenu
    case newGameConfirmation
}

nonisolated enum GameRootPresentationPolicy {
    static func activeModal(
        showsOnboarding: Bool,
        showsSettings: Bool,
        showsProgress: Bool,
        showsGameMenu: Bool,
        showsNewGameConfirmation: Bool,
        showsStationAddition: Bool = false
    ) -> GameRootModalPresentation? {
        if showsOnboarding { return .onboarding }
        if showsStationAddition { return .stationAddition }
        if showsSettings { return .settings }
        if showsProgress { return .progress }
        if showsGameMenu { return .gameMenu }
        if showsNewGameConfirmation { return .newGameConfirmation }
        return nil
    }

    static func allowsJourneyFeedback(
        hasActiveModal: Bool,
        hasSelectedTrain: Bool,
        hasSelectedStation: Bool,
        phase: GamePhase
    ) -> Bool {
        !hasActiveModal
            && !hasSelectedTrain
            && !hasSelectedStation
            && isNormalOperatingPhase(phase)
    }

    static func isNormalOperatingPhase(_ phase: GamePhase) -> Bool {
        switch phase {
        case .idle, .operating:
            true
        case .selectingOrigin, .selectingDestination, .calculating, .preview,
             .constructing, .error:
            false
        }
    }

    static func maximumBottomPanelHeight(
        containerHeight: CGFloat,
        usesAccessibilityTextSize: Bool
    ) -> CGFloat {
        max(containerHeight * (usesAccessibilityTextSize ? 0.60 : 0.56), 260)
    }
}

/// The single presentation shown in the bottom control region.
nonisolated enum BottomPanelPresentation: Hashable, Sendable {
    case build
    case origin
    case destination
    case calculating
    case preview
    case constructing
    case train(UUID)
    case station(String)
    case network
    case bankrupt
    case error
}

nonisolated enum BottomPanelPresentationPolicy {
    static func presentation(
        isBankrupt: Bool,
        phase: GamePhase,
        selectedTrainID: UUID?,
        selectedStationCRS: String?,
        showsNetworkPerformance: Bool,
        hasLines: Bool
    ) -> BottomPanelPresentation {
        if isBankrupt { return .bankrupt }

        switch phase {
        case .selectingOrigin:
            return .origin
        case .selectingDestination:
            return .destination
        case .calculating:
            return .calculating
        case .preview:
            return .preview
        case .constructing:
            return .constructing
        case .error:
            return .error
        case .idle, .operating:
            if let selectedTrainID { return .train(selectedTrainID) }
            if let selectedStationCRS { return .station(selectedStationCRS) }
            if showsNetworkPerformance, hasLines { return .network }
            return .build
        }
    }

    /// A build control is useful only while it can start the build flow. Once the configured
    /// network limit is reached, retaining a disabled completion-shaped control pushes the
    /// actionable network summary away from the bottom thumb zone and needlessly covers the map.
    static func showsBuildAction(
        for presentation: BottomPanelPresentation,
        canBuildAnotherLine: Bool
    ) -> Bool {
        presentation == .build && canBuildAnotherLine
    }
}

/// Stable colour-independent identity shown beside a service wherever a larger palette repeats.
nonisolated enum LineIdentityPresentationPolicy {
    static func displayNumber(styleIndex: Int) -> Int {
        max(styleIndex, 0) + 1
    }
}
