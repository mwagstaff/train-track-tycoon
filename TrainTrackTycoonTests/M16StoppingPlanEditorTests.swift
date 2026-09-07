import CoreGraphics
import SwiftUI
import Testing
@testable import TrainTrackTycoon

@Suite("M16 train stopping-plan policy")
struct M16StoppingPlanPolicyTests {
    private let stations = TrainStoppingPlanPolicy.stations(from: [
        (crs: "VIC", name: "London Victoria"),
        (crs: "BRX", name: "Brixton"),
        (crs: "HNH", name: "Herne Hill"),
        (crs: "SYD", name: "Sydenham Hill"),
        (crs: "ECR", name: "East Croydon"),
    ])

    @Test("Local plans automatically call at every station in either orientation")
    func localPlansUseEveryStationInTheirOrientedSpan() throws {
        let original = TrainServicePlan(
            slotIndex: 1,
            role: .local,
            stationCRSs: ["ECR", "VIC"]
        )
        var draft = TrainStoppingPlanPolicy.makeDraft(
            plan: original,
            availableStations: stations
        )

        let reversed = try #require(
            TrainStoppingPlanPolicy.plan(from: draft, availableStations: stations)
        )
        #expect(reversed.stationCRSs == ["ECR", "SYD", "HNH", "BRX", "VIC"])

        draft.startCRS = "BRX"
        draft.endCRS = "SYD"
        let forward = try #require(
            TrainStoppingPlanPolicy.plan(from: draft, availableStations: stations)
        )
        #expect(forward.stationCRSs == ["BRX", "HNH", "SYD"])
        #expect(forward.slotIndex == 1)
        #expect(forward.role == .local)
    }

    @Test("Express plans keep endpoints fixed and order selected calls by travel direction")
    func expressPlansOrderCallsAndKeepEndpoints() throws {
        let original = TrainServicePlan(
            slotIndex: 2,
            role: .express,
            stationCRSs: ["ECR", "HNH", "VIC"]
        )
        var draft = TrainStoppingPlanPolicy.makeDraft(
            plan: original,
            availableStations: stations
        )

        draft = TrainStoppingPlanPolicy.togglingExpressCall(
            "BRX",
            in: draft,
            availableStations: stations
        )
        draft = TrainStoppingPlanPolicy.togglingExpressCall(
            "SYD",
            in: draft,
            availableStations: stations
        )
        let result = try #require(
            TrainStoppingPlanPolicy.plan(from: draft, availableStations: stations)
        )

        #expect(result.stationCRSs == ["ECR", "SYD", "HNH", "BRX", "VIC"])

        draft = TrainStoppingPlanPolicy.togglingExpressCall(
            "ECR",
            in: draft,
            availableStations: stations
        )
        #expect(
            TrainStoppingPlanPolicy.plan(from: draft, availableStations: stations)
                == result
        )
    }

    @Test("Changing a Local plan to Express begins with terminal-only service")
    func localToExpressBeginsWithTerminalOnlyService() throws {
        let original = TrainServicePlan(
            slotIndex: 0,
            role: .local,
            stationCRSs: stations.map(\.crs)
        )
        var draft = TrainStoppingPlanPolicy.makeDraft(
            plan: original,
            availableStations: stations
        )
        draft = TrainStoppingPlanPolicy.settingRole(.express, in: draft)

        let result = try #require(
            TrainStoppingPlanPolicy.plan(from: draft, availableStations: stations)
        )
        #expect(result.stationCRSs == ["VIC", "ECR"])
        #expect(result.role == .express)
    }

    @Test("Matching or unavailable terminals cannot be saved")
    func validationRejectsInvalidTerminals() {
        let original = TrainServicePlan(
            slotIndex: 0,
            role: .express,
            stationCRSs: ["VIC", "ECR"]
        )
        var draft = TrainStoppingPlanPolicy.makeDraft(
            plan: original,
            availableStations: stations
        )

        draft.endCRS = "VIC"
        #expect(
            TrainStoppingPlanPolicy.validation(for: draft, availableStations: stations)
                == .matchingTerminals
        )
        #expect(TrainStoppingPlanPolicy.plan(from: draft, availableStations: stations) == nil)

        draft.endCRS = "ZZZ"
        #expect(
            TrainStoppingPlanPolicy.validation(for: draft, availableStations: stations)
                == .unavailableTerminal
        )
    }

    @Test("Call limit blocks extra Express calls and overlong Local spans")
    func callLimitIsEnforced() {
        let express = TrainServicePlan(
            slotIndex: 0,
            role: .express,
            stationCRSs: ["VIC", "ECR"]
        )
        var expressDraft = TrainStoppingPlanPolicy.makeDraft(
            plan: express,
            availableStations: stations
        )
        expressDraft = TrainStoppingPlanPolicy.togglingExpressCall(
            "HNH",
            in: expressDraft,
            availableStations: stations,
            maximumCallCount: 3
        )
        expressDraft = TrainStoppingPlanPolicy.togglingExpressCall(
            "BRX",
            in: expressDraft,
            availableStations: stations,
            maximumCallCount: 3
        )
        #expect(
            TrainStoppingPlanPolicy.callingStations(
                for: expressDraft,
                availableStations: stations
            ).map(\.crs) == ["VIC", "HNH", "ECR"]
        )

        let localDraft = TrainStoppingPlanPolicy.makeDraft(
            plan: TrainServicePlan(
                slotIndex: 0,
                role: .local,
                stationCRSs: ["VIC", "ECR"]
            ),
            availableStations: stations
        )
        #expect(
            TrainStoppingPlanPolicy.validation(
                for: localDraft,
                availableStations: stations,
                maximumCallCount: 4
            ) == .tooManyCalls(maximum: 4)
        )
    }

    @Test("New plans enforce the hard 16-call ceiling")
    func hardCallCeiling() {
        let seventeenStations = (1...17).map { number in
            TrainStoppingPlanStation(
                crs: "S\(number)",
                name: "Station \(number)"
            )
        }
        let seventeenCallDraft = TrainStoppingPlanPolicy.makeDraft(
            plan: TrainServicePlan(
                slotIndex: 0,
                role: .local,
                stationCRSs: ["S1", "S17"]
            ),
            availableStations: seventeenStations
        )

        #expect(
            TrainStoppingPlanPolicy.validation(
                for: seventeenCallDraft,
                availableStations: seventeenStations,
                maximumCallCount: 17
            ) == .tooManyCalls(maximum: 16)
        )

        let sixteenStations = Array(seventeenStations.prefix(16))
        let sixteenCallDraft = TrainStoppingPlanPolicy.makeDraft(
            plan: TrainServicePlan(
                slotIndex: 0,
                role: .local,
                stationCRSs: ["S1", "S16"]
            ),
            availableStations: sixteenStations
        )
        #expect(
            TrainStoppingPlanPolicy.validation(
                for: sixteenCallDraft,
                availableStations: sixteenStations,
                maximumCallCount: 17
            ) == .valid
        )
    }

    @Test("Save state and compact summary are deterministic")
    func saveStateAndSummary() {
        let original = TrainServicePlan(
            slotIndex: 3,
            role: .express,
            stationCRSs: ["VIC", "HNH", "ECR"]
        )
        var draft = TrainStoppingPlanPolicy.makeDraft(
            plan: original,
            availableStations: stations
        )
        #expect(
            !TrainStoppingPlanPolicy.canSave(
                draft: draft,
                replacing: original,
                availableStations: stations
            )
        )

        draft = TrainStoppingPlanPolicy.togglingExpressCall(
            "BRX",
            in: draft,
            availableStations: stations
        )
        #expect(
            TrainStoppingPlanPolicy.canSave(
                draft: draft,
                replacing: original,
                availableStations: stations
            )
        )

        let copy = TrainStoppingPlanPolicy.summary(
            plan: original,
            trainNumber: 4,
            availableStations: stations
        )
        #expect(copy.title == "Train 4 · Express")
        #expect(copy.route == "London Victoria ↔ East Croydon")
        #expect(copy.callCount == "3 calls")
        #expect(copy.accessibilityValue.contains("3 calls"))
    }
}

@Suite("M16 train stopping-plan SwiftUI rendering", .serialized)
@MainActor
struct M16StoppingPlanEditorRenderTests {
    private let portraitSize = CGSize(width: 320, height: 568)
    private let stationTuples: [(crs: String, name: String)] = [
        ("VIC", "London Victoria"),
        ("BRX", "Brixton"),
        ("HNH", "Herne Hill and Tulse Hill Interchange"),
        ("SYD", "Sydenham Hill"),
        ("ECR", "East Croydon"),
    ]

    @Test("Editor remains useful in compact portrait and Accessibility text")
    func editorRenderContexts() throws {
        let plan = TrainServicePlan(
            slotIndex: 1,
            role: .express,
            stationCRSs: ["VIC", "HNH", "ECR"]
        )

        for (scheme, typeSize) in [
            (ColorScheme.light, DynamicTypeSize.large),
            (.dark, .accessibility5),
        ] {
            let maximumHeight = GameRootPresentationPolicy.maximumBottomPanelHeight(
                containerHeight: portraitSize.height,
                usesAccessibilityTextSize: typeSize.isAccessibilitySize
            )
            let content = DeterministicRenderHost(
                colorScheme: scheme,
                dynamicTypeSize: typeSize
            ) {
                VStack(spacing: 0) {
                    Spacer(minLength: 0).allowsHitTesting(false)
                    BottomControlsViewport(maximumHeight: maximumHeight) {
                        TrainStoppingPlanEditor(
                            availableStations: stationTuples,
                            plan: plan,
                            trainNumber: 2,
                            onCancel: {},
                            onSave: { _ in }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 5)
            }

            let image = try #require(
                SwiftUIRenderHarness.hostedImage(of: content, size: portraitSize)
            )
            try assertUseful(image)
            #expect(
                portraitSize.height - maximumHeight + 0.001
                    >= portraitSize.height * 0.40
            )
        }
    }

    @Test("Compact summary reflows at Accessibility text")
    func summaryRenderContexts() throws {
        let plan = TrainServicePlan(
            slotIndex: 1,
            role: .local,
            stationCRSs: ["VIC", "BRX", "HNH", "SYD", "ECR"]
        )

        for (scheme, typeSize) in [
            (ColorScheme.light, DynamicTypeSize.large),
            (.dark, .accessibility5),
        ] {
            let content = DeterministicRenderHost(
                colorScheme: scheme,
                dynamicTypeSize: typeSize
            ) {
                VStack {
                    Spacer(minLength: 0)
                    TrainStoppingPlanSummary(
                        availableStations: stationTuples,
                        plan: plan,
                        trainNumber: 2,
                        onEdit: {}
                    )
                }
                .padding(12)
            }
            let image = try #require(
                SwiftUIRenderHarness.hostedImage(of: content, size: portraitSize)
            )
            try assertUseful(image)
        }
    }

    private func assertUseful(_ image: CGImage) throws {
        let metrics = try #require(SwiftUIRenderMetrics(image: image))
        #expect(image.width == Int(portraitSize.width))
        #expect(image.height == Int(portraitSize.height))
        #expect(metrics.opaquePixelFraction > 0.99)
        #expect(metrics.luminanceSpan > 0.28)
        #expect(metrics.quantizedColorCount >= 8)
    }
}
