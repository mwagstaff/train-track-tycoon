import CoreGraphics
import SwiftUI
import Testing
@testable import TrainTrackTycoon

@Suite("Through-service SwiftUI rendering", .serialized)
@MainActor
struct ThroughServiceSwiftUIRenderTests {
    private let narrowPortraitSize = CGSize(width: 320, height: 568)

    @Test("Compatible service choice remains bounded in portrait contexts")
    func compatibleServiceChoicePortraitContexts() throws {
        let line = makeLine(corridorIDs: [UUID()])
        let option = makeAutomaticOption(primaryLineID: line.id)

        for (colorScheme, dynamicTypeSize) in [
            (ColorScheme.light, DynamicTypeSize.large),
            (.dark, .large),
            (.dark, .accessibility5),
        ] {
            let maximumHeight = GameRootPresentationPolicy.maximumBottomPanelHeight(
                containerHeight: narrowPortraitSize.height,
                usesAccessibilityTextSize: dynamicTypeSize.isAccessibilitySize
            )
            let content = DeterministicRenderHost(
                colorScheme: colorScheme,
                dynamicTypeSize: dynamicTypeSize
            ) {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)

                    BottomControlsViewport(maximumHeight: maximumHeight) {
                        ScrollView {
                            ThroughServiceSection(
                                line: line,
                                options: [option],
                                incompatibilities: [],
                                gameMode: .career,
                                join: { _ in true }
                            )
                        }
                        .frame(height: maximumHeight)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 5)
            }

            try assertPortraitRender(content)
            #expect(
                narrowPortraitSize.height - maximumHeight + 0.001
                    >= narrowPortraitSize.height * 0.40
            )
        }
    }

    @Test("Joined service summary remains bounded in portrait")
    func joinedServiceSummaryPortrait() throws {
        let content = DeterministicRenderHost(
            colorScheme: .dark,
            dynamicTypeSize: .accessibility5
        ) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ThroughServiceSection(
                    line: makeLine(corridorIDs: [UUID(), UUID()]),
                    options: [],
                    incompatibilities: [],
                    gameMode: .zen,
                    join: { _ in false }
                )
            }
            .padding(12)
        }

        try assertPortraitRender(content)
    }

    @Test("A joined-line extension choice remains usable in portrait and Accessibility text")
    func joinedServiceExtensionPortraitContexts() throws {
        let line = makeLine(corridorIDs: [UUID(), UUID()])
        let option = makeOption(
            primaryLineID: line.id,
            primaryCorridorCount: 2,
            candidateCorridorCount: 1,
            resultingCorridorCount: 3
        )

        for (colorScheme, dynamicTypeSize) in [
            (ColorScheme.light, DynamicTypeSize.large),
            (.dark, .accessibility5),
        ] {
            let maximumHeight = GameRootPresentationPolicy.maximumBottomPanelHeight(
                containerHeight: narrowPortraitSize.height,
                usesAccessibilityTextSize: dynamicTypeSize.isAccessibilitySize
            )
            let content = DeterministicRenderHost(
                colorScheme: colorScheme,
                dynamicTypeSize: dynamicTypeSize
            ) {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)
                    BottomControlsViewport(maximumHeight: maximumHeight) {
                        ScrollView {
                            ThroughServiceSection(
                                line: line,
                                options: [option],
                                incompatibilities: [],
                                gameMode: .career,
                                join: { _ in true },
                                openFinances: {}
                            )
                        }
                        .frame(height: maximumHeight)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 5)
            }

            try assertPortraitRender(content)
        }
    }

    @Test("Compatibility guidance remains readable at accessibility sizes")
    func incompatibilityGuidancePortrait() throws {
        let line = makeLine(corridorIDs: [UUID()])
        let incompatibility = makeIncompatibility(primaryLineID: line.id)
        let content = DeterministicRenderHost(
            colorScheme: .dark,
            dynamicTypeSize: .accessibility5
        ) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ThroughServiceSection(
                    line: line,
                    options: [],
                    incompatibilities: [incompatibility],
                    gameMode: .career,
                    join: { _ in false }
                )
            }
            .padding(12)
        }

        try assertPortraitRender(content)
    }

    @Test("Automatic join review remains scrollable in narrow portrait contexts")
    func automaticJoinReviewPortraitContexts() throws {
        let option = makeAutomaticOption(primaryLineID: UUID())

        for (colorScheme, dynamicTypeSize) in [
            (ColorScheme.light, DynamicTypeSize.large),
            (.dark, .accessibility5),
        ] {
            let content = DeterministicRenderHost(
                colorScheme: colorScheme,
                dynamicTypeSize: dynamicTypeSize
            ) {
                ThroughServiceReviewSheet(
                    option: option,
                    orderedStationNames: ["Purley", "East Croydon", "Horley"],
                    gameMode: .career,
                    cancel: {},
                    confirm: {},
                    openFinances: {}
                )
            }

            try assertPortraitRender(content)
        }
    }

    @Test("Underfunded join review remains readable in narrow portrait")
    func underfundedJoinReviewPortrait() throws {
        let option = makeAutomaticOption(
            primaryLineID: UUID(),
            canAfford: false,
            fundingShortfallPence: 100_000_000
        )
        let content = DeterministicRenderHost(
            colorScheme: .light,
            dynamicTypeSize: .accessibility5
        ) {
            ThroughServiceReviewSheet(
                option: option,
                orderedStationNames: ["Purley", "East Croydon", "Horley"],
                gameMode: .career,
                cancel: {},
                confirm: {},
                openFinances: {}
            )
        }

        try assertPortraitRender(content)
    }

    @Test("Merge confirmation explains closure, retained fleet, and no charge")
    func mergeConfirmationCopy() {
        let copy = ThroughServiceConfirmationCopy(
            option: makeOption(primaryLineID: UUID()),
            orderedStationNames: ["Purley", "East Croydon", "Horley"]
        )

        #expect(copy.title == "Join as Purley – Horley?")
        #expect(copy.actionTitle == "Merge services")
        #expect(copy.message.contains("Line 1 will run through East Croydon"))
        #expect(copy.message.contains("Calling points: Purley → East Croydon → Horley"))
        #expect(copy.message.contains("Line 2 will close as a separate service"))
        #expect(copy.message.contains("its 2 trainsets stay owned"))
        #expect(copy.message.contains("4 trainsets: 2 active and 2 spares"))
        #expect(copy.message.contains("no cash is charged"))
        #expect(copy.message.contains("cannot be undone"))
    }

    @Test("Extension confirmation names all corridors and preserved custom plans")
    func extensionConfirmationCopy() {
        let option = makeOption(
            primaryLineID: UUID(),
            primaryCorridorCount: 2,
            candidateCorridorCount: 2,
            resultingCorridorCount: 4,
            preservesPrimaryCustomServicePlans: true
        )
        let copy = ThroughServiceConfirmationCopy(
            option: option,
            orderedStationNames: ["Purley", "East Croydon", "Horley"]
        )

        #expect(copy.title == "Extend as Purley – Horley?")
        #expect(copy.actionTitle == "Extend service")
        #expect(copy.message.contains("4 retained corridors"))
        #expect(copy.message.contains("over all 4 retained physical corridors"))
        #expect(copy.message.contains("four custom train plans keep their existing terminals and calls"))
        #expect(copy.message.contains("extension cannot be undone"))
    }

    @Test("Automatic join copy itemises service changes, investment, and a funding shortfall")
    func automaticJoinCopy() {
        let option = makeAutomaticOption(
            primaryLineID: UUID(),
            canAfford: false,
            fundingShortfallPence: 100_000_000
        )
        let copy = ThroughServiceConfirmationCopy(
            option: option,
            orderedStationNames: ["Purley", "East Croydon", "Horley"],
            gameMode: .career
        )

        #expect(copy.message.contains("Automatic changes"))
        #expect(copy.message.contains("Line 2 timetable: Hourly → Half-hourly"))
        #expect(copy.message.contains("Line 2 stopping pattern: Local → Balanced"))
        #expect(copy.message.contains("Line 2 fleet: 2 trainsets, 6 → 8 cars"))
        #expect(copy.message.contains("Automatic investment"))
        #expect(copy.message.contains("more cash"))
        #expect(copy.message.contains("cannot be undone"))
    }

    @Test("Structural blocker copy names the adjacent line and next steps")
    func incompatibilityCopy() {
        let copy = ThroughServiceIncompatibilityCopy(
            incompatibility: makeIncompatibility(primaryLineID: UUID())
        )

        #expect(copy.title == "Line 2 via East Croydon")
        #expect(copy.message.contains("Finish construction"))
        #expect(copy.message.contains("must be conventional railways"))
        #expect(copy.message.contains("overlap or would create a branch or loop"))
        #expect(copy.message.contains("route or fleet limit"))
    }

    private func assertPortraitRender<Content: View>(_ content: Content) throws {
        let image = try #require(
            SwiftUIRenderHarness.hostedImage(of: content, size: narrowPortraitSize)
        )
        let metrics = try #require(SwiftUIRenderMetrics(image: image))

        #expect(image.width == Int(narrowPortraitSize.width))
        #expect(image.height == Int(narrowPortraitSize.height))
        #expect(metrics.opaquePixelFraction > 0.99)
        #expect(metrics.luminanceSpan > 0.28)
        #expect(metrics.quantizedColorCount >= 8)
    }

    private func makeOption(
        primaryLineID: UUID,
        primaryCorridorCount: Int = 1,
        candidateCorridorCount: Int = 1,
        resultingCorridorCount: Int = 2,
        preservesPrimaryCustomServicePlans: Bool = false
    ) -> ThroughServiceOption {
        ThroughServiceOption(
            primaryLineID: primaryLineID,
            candidateLineID: UUID(),
            primaryLineNumber: 1,
            candidateLineNumber: 2,
            primaryCorridorCount: primaryCorridorCount,
            candidateCorridorCount: candidateCorridorCount,
            resultingCorridorCount: resultingCorridorCount,
            originCRS: "PUR",
            originName: "Purley",
            junctionCRS: "ECR",
            junctionName: "East Croydon",
            destinationCRS: "HOR",
            destinationName: "Horley",
            stationCRSs: ["PUR", "ECR", "HOR"],
            stationNames: ["Purley", "East Croydon", "Horley"],
            primaryOwnedTrainCount: 2,
            candidateOwnedTrainCount: 2,
            resultingOwnedTrainCount: 4,
            activeTrainCount: 2,
            primaryFrequency: .halfHourly,
            candidateFrequency: .halfHourly,
            primaryServicePattern: .local,
            candidateServicePattern: .local,
            primaryFormation: .sixCar,
            candidateFormation: .sixCar,
            primaryTrackCapacity: .singleTrack,
            candidateTrackCapacity: .singleTrack,
            frequency: .halfHourly,
            servicePattern: .local,
            formation: .sixCar,
            trackCapacity: .singleTrack,
            preservesPrimaryCustomServicePlans: preservesPrimaryCustomServicePlans,
            automaticChanges: [],
            capitalQuote: .zero,
            canAfford: true,
            fundingShortfallPence: 0
        )
    }

    private func makeAutomaticOption(
        primaryLineID: UUID,
        canAfford: Bool = true,
        fundingShortfallPence: Int64 = 0
    ) -> ThroughServiceOption {
        let candidateLineID = UUID()
        let upgradeCostPence: Int64 = 266_000_000
        return ThroughServiceOption(
            primaryLineID: primaryLineID,
            candidateLineID: candidateLineID,
            primaryLineNumber: 1,
            candidateLineNumber: 2,
            primaryCorridorCount: 1,
            candidateCorridorCount: 1,
            resultingCorridorCount: 2,
            originCRS: "PUR",
            originName: "Purley",
            junctionCRS: "ECR",
            junctionName: "East Croydon",
            destinationCRS: "HOR",
            destinationName: "Horley",
            stationCRSs: ["PUR", "ECR", "HOR"],
            stationNames: ["Purley", "East Croydon", "Horley"],
            primaryOwnedTrainCount: 2,
            candidateOwnedTrainCount: 2,
            resultingOwnedTrainCount: 4,
            activeTrainCount: 2,
            primaryFrequency: .halfHourly,
            candidateFrequency: .hourly,
            primaryServicePattern: .balanced,
            candidateServicePattern: .local,
            primaryFormation: .eightCar,
            candidateFormation: .sixCar,
            primaryTrackCapacity: .singleTrack,
            candidateTrackCapacity: .singleTrack,
            frequency: .halfHourly,
            servicePattern: .balanced,
            formation: .eightCar,
            trackCapacity: .singleTrack,
            preservesPrimaryCustomServicePlans: false,
            automaticChanges: [
                .serviceFrequency(
                    lineID: candidateLineID,
                    lineNumber: 2,
                    from: .hourly,
                    to: .halfHourly
                ),
                .servicePattern(
                    lineID: candidateLineID,
                    lineNumber: 2,
                    from: .local,
                    to: .balanced
                ),
                .formation(
                    lineID: candidateLineID,
                    lineNumber: 2,
                    ownedTrainCount: 2,
                    from: .sixCar,
                    to: .eightCar,
                    costPence: upgradeCostPence
                ),
            ],
            capitalQuote: CapitalPurchaseQuote(
                trackAndInfrastructurePence: 0,
                stationConstructionPence: 0,
                rollingStockPence: upgradeCostPence
            ),
            canAfford: canAfford,
            fundingShortfallPence: fundingShortfallPence
        )
    }

    private func makeIncompatibility(
        primaryLineID: UUID
    ) -> ThroughServiceIncompatibility {
        ThroughServiceIncompatibility(
            primaryLineID: primaryLineID,
            candidateLineID: UUID(),
            primaryLineNumber: 1,
            candidateLineNumber: 2,
            junctionCRS: "ECR",
            junctionName: "East Croydon",
            reasons: [
                .incompleteConstruction,
                .conventionalServicesOnly,
                .overlappingOrBranchedRoute,
                .serviceLimitExceeded,
            ]
        )
    }

    private func makeLine(corridorIDs: [UUID]) -> BuiltLine {
        let origin = Station(
            crs: "PUR",
            name: "Purley",
            latitude: 51.3376,
            longitude: -0.1140
        )
        let destination = Station(
            crs: "ECR",
            name: "East Croydon",
            latitude: 51.3752,
            longitude: -0.0923
        )
        let route = ServiceRailwayRoute(
            coordinates: [origin.coordinate, destination.coordinate]
        )
        return BuiltLine(
            id: UUID(),
            name: "Purley – East Croydon",
            origin: origin,
            destination: destination,
            route: route,
            distanceMetres: route.totalLength,
            indicativeCost: 1_000_000,
            styleIndex: 0,
            railwayClass: .conventional,
            formation: .sixCar,
            servicePattern: .local,
            trackCapacity: .singleTrack,
            serviceFrequency: .halfHourly,
            ownedTrainCount: 2,
            constructionProgress: 1,
            trains: [],
            corridorIDs: corridorIDs,
            stationCRSs: [origin.crs, destination.crs]
        )
    }

}
