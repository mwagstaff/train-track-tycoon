import CoreLocation
import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Milestone 14 intermediate-station integration", .serialized)
@MainActor
struct Milestone14GameSessionIntegrationTests {
    @Test("Preview discovers, reroutes through, prices, and builds ordered station calls")
    func previewIntermediateStationFlow() async throws {
        let provider = Milestone14RoutingProvider()
        let session = makeSession(provider: provider, mode: .career)

        await createPreview(in: session)

        #expect(session.previewIntermediateStations.map(\.crs) == ["BRX", "HNH"])
        #expect(session.previewSelectedStationCRSs == ["VIC", "KTH"])

        session.togglePreviewIntermediateStation(brixton)
        #expect(session.isUpdatingPreviewRoute)
        #expect(!session.canConfirmPreview)
        await session.waitForRouteCalculation()

        let preview = try #require(session.preview)
        #expect(session.phase == .preview)
        #expect(!session.isUpdatingPreviewRoute)
        #expect(session.canConfirmPreview)
        #expect(preview.stationCRSs == ["VIC", "BRX", "KTH"])
        #expect(session.previewSelectedStationCRSs == preview.stationCRSs)
        #expect(preview.route.stationCoordinateIndices.count == 3)
        #expect(session.previewCapitalQuote?.stationConstructionPence == 600_000_000)
        #expect(
            await provider.routeRequests == [
                ["VIC", "KTH"],
                ["VIC", "BRX", "KTH"],
            ]
        )

        session.confirmPreview()

        let line = try #require(session.lines.first)
        #expect(session.phase == .operating)
        #expect(line.stationCRSs == ["VIC", "BRX", "KTH"])
        #expect(line.corridorStationCRSs == ["VIC", "BRX", "KTH"])
        #expect(session.stationProgressByCRS["BRX"] != nil)
        #expect(session.passengerSnapshot.station(forCRS: "BRX") != nil)
    }

    @Test("New calling-point edits respect the configured simulation bound")
    func callingPointLimitIsEnforced() async throws {
        let provider = Milestone14RoutingProvider()
        let session = makeSession(
            provider: provider,
            mode: .zen,
            maximumServiceCallCount: 3
        )
        await createPreview(in: session)

        session.togglePreviewIntermediateStation(brixton)
        await session.waitForRouteCalculation()
        #expect(session.preview?.stationCRSs == ["VIC", "BRX", "KTH"])

        session.togglePreviewIntermediateStation(herneHill)
        #expect(!session.isUpdatingPreviewRoute)
        #expect(session.previewSelectedStationCRSs == ["VIC", "BRX", "KTH"])

        session.confirmPreview()
        let line = try #require(session.lines.first)
        session.beginEditingStops(forLineID: line.id)
        #expect(session.editingStopsLineID == line.id)
        #expect(!session.isUpdatingLineStops)
        #expect(session.editableIntermediateStations.isEmpty)
        #expect(session.intermediateStationAdditionCostPence(herneHill, toLineID: line.id) == nil)
    }

    @Test("Adding a stop is station-only, preserves identities, and survives restore")
    func addStopTransactionAndPersistence() async throws {
        let provider = Milestone14RoutingProvider()
        let clock = Milestone14ManualClock()
        let session = makeSession(provider: provider, mode: .career, clock: clock)
        await buildLineCallingAtBrixton(in: session)

        clock.advance(by: 0.5)
        let originalLine = try #require(session.lines.first)
        let originalLineID = originalLine.id
        let originalTrainIDs = originalLine.trains.map(\.id)
        let originalTrainProgress = originalLine.trains.map {
            $0.distanceAlongRoute / originalLine.route.totalLength
        }
        let originalTrains = originalLine.trains
        let originalCorridorCoordinates = originalLine.corridorRoute.coordinates
        let originalCorridorTotalLength = originalLine.corridorRoute.totalLength
        let originalDistanceMetres = originalLine.distanceMetres
        let originalIndicativeCost = originalLine.indicativeCost
        let originalCorridorDistanceMetres = originalLine.corridorDistanceMetres
        let originalCorridorIndicativeCost = originalLine.corridorIndicativeCost
        let routeRequestsBeforeEdit = await provider.routeRequests
        let originalFinance = session.financeLedger

        session.beginEditingStops(forLineID: originalLineID)
        await session.waitForLineStopUpdate()
        #expect(session.editableIntermediateStations.map(\.crs) == ["HNH"])
        #expect(
            session.intermediateStationAdditionCostPence(
                herneHill,
                toLineID: originalLineID
            ) == 200_000_000
        )
        #expect(session.canAffordIntermediateStation(herneHill, toLineID: originalLineID))

        session.addIntermediateStation(herneHill, toLineID: originalLineID)
        await session.waitForLineStopUpdate()

        let updatedLine = try #require(session.lines.first)
        #expect(updatedLine.id == originalLineID)
        #expect(updatedLine.stationCRSs == ["VIC", "BRX", "HNH", "KTH"])
        #expect(updatedLine.corridorStationCRSs == ["VIC", "BRX", "HNH", "KTH"])
        #expect(updatedLine.route.stationCoordinateIndices == [0, 1, 2, 3])
        #expect(updatedLine.corridorRoute.stationCoordinateIndices == [0, 1, 2, 3])
        #expect(updatedLine.route.cumulativeDistances == [0, 1_000, 2_000, 3_000])
        #expect(updatedLine.corridorRoute.cumulativeDistances == [0, 1_000, 2_000, 3_000])
        #expect(
            coordinatesEqual(
                [
                    updatedLine.corridorRoute.coordinates[0],
                    updatedLine.corridorRoute.coordinates[1],
                    updatedLine.corridorRoute.coordinates[3],
                ],
                originalCorridorCoordinates
            )
        )
        #expect(updatedLine.corridorRoute.totalLength == originalCorridorTotalLength)
        #expect(updatedLine.distanceMetres == originalDistanceMetres)
        #expect(updatedLine.indicativeCost == originalIndicativeCost)
        #expect(updatedLine.corridorDistanceMetres == originalCorridorDistanceMetres)
        #expect(updatedLine.corridorIndicativeCost == originalCorridorIndicativeCost)
        #expect(await provider.routeRequests == routeRequestsBeforeEdit)
        #expect(updatedLine.trains.map(\.id) == originalTrainIDs)
        for ((train, originalTrain), priorProgress) in zip(
            zip(updatedLine.trains, originalTrains),
            originalTrainProgress
        ) {
            #expect(
                abs(train.distanceAlongRoute / updatedLine.route.totalLength - priorProgress)
                    < 0.000_001
            )
            #expect(train.coordinate.latitude == originalTrain.coordinate.latitude)
            #expect(train.coordinate.longitude == originalTrain.coordinate.longitude)
            #expect(train.distanceAlongRoute == originalTrain.distanceAlongRoute)
            #expect(train.bearing == originalTrain.bearing)
            #expect(train.direction == originalTrain.direction)
            #expect(train.dwellRemaining == originalTrain.dwellRemaining)
        }
        #expect(
            session.financeLedger.lifetimeConstructionSpendPence
                == originalFinance.lifetimeConstructionSpendPence + 200_000_000
        )
        #expect(
            session.financeLedger.lifetimeRollingStockSpendPence
                == originalFinance.lifetimeRollingStockSpendPence
        )
        #expect(
            session.financeLedger.cashBalancePence
                == originalFinance.cashBalancePence - 200_000_000
        )
        #expect(session.stationProgressByCRS["HNH"] != nil)
        #expect(session.passengerSnapshot.station(forCRS: "HNH") != nil)

        let snapshot = session.makeSaveSnapshot()
        let restoredProvider = Milestone14RoutingProvider()
        let restored = makeSession(provider: restoredProvider, mode: .zen)
        try await restored.restore(from: snapshot)

        let restoredLine = try #require(restored.lines.first)
        #expect(restoredLine.id == originalLineID)
        #expect(restoredLine.stationCRSs == updatedLine.stationCRSs)
        #expect(restoredLine.corridorStationCRSs == updatedLine.corridorStationCRSs)
        #expect(restoredLine.trains.map(\.id) == originalTrainIDs)
        #expect(restored.financeLedger == session.financeLedger)
        #expect(restored.stationProgressByCRS["BRX"] != nil)
        #expect(restored.stationProgressByCRS["HNH"] != nil)
    }

    @Test("Sequential projected calls sharing one coarse segment retain its exact shape")
    func sequentialProjectedCallsOnOneSegment() async throws {
        let provider = Milestone14RoutingProvider()
        let session = makeSession(provider: provider, mode: .zen)
        await buildEndpointOnlyLine(in: session)
        let originalLine = try #require(session.lines.first)
        let originalTrains = originalLine.trains
        let originalCoordinates = originalLine.corridorRoute.coordinates
        let originalTotalLength = originalLine.corridorRoute.totalLength
        let originalCorridorCost = originalLine.corridorIndicativeCost
        let routeRequestsBeforeAdd = await provider.routeRequests

        session.beginEditingStops(forLineID: originalLine.id)
        await session.waitForLineStopUpdate()
        session.addIntermediateStation(brixton, toLineID: originalLine.id)
        await session.waitForLineStopUpdate()
        #expect(session.editableIntermediateStations.map(\.crs) == ["HNH"])

        session.addIntermediateStation(herneHill, toLineID: originalLine.id)
        await session.waitForLineStopUpdate()

        let updatedLine = try #require(session.lines.first)
        #expect(updatedLine.stationCRSs == ["VIC", "BRX", "HNH", "KTH"])
        #expect(updatedLine.corridorStationCRSs == ["VIC", "BRX", "HNH", "KTH"])
        #expect(updatedLine.route.cumulativeDistances == [0, 1_000, 2_000, 3_000])
        #expect(updatedLine.route.stationCoordinateIndices == [0, 1, 2, 3])
        #expect(updatedLine.corridorRoute.totalLength == originalTotalLength)
        #expect(updatedLine.corridorDistanceMetres == originalLine.corridorDistanceMetres)
        #expect(updatedLine.corridorIndicativeCost == originalCorridorCost)
        #expect(
            coordinatesEqual(
                [updatedLine.corridorRoute.coordinates.first!,
                 updatedLine.corridorRoute.coordinates.last!],
                originalCoordinates
            )
        )
        #expect(trainStatesEqual(updatedLine.trains, originalTrains))
        #expect(await provider.routeRequests == routeRequestsBeforeAdd)
    }

    @Test("An out-of-span discovered corridor distance is hidden and cannot mutate the network")
    func invalidDiscoveredDistanceIsAtomic() async throws {
        let provider = Milestone14RoutingProvider()
        let session = makeSession(provider: provider, mode: .career)
        await buildEndpointOnlyLine(in: session)
        let line = try #require(session.lines.first)

        await provider.useInvalidRouteDistanceForNextDiscovery()
        session.beginEditingStops(forLineID: line.id)
        await session.waitForLineStopUpdate()
        #expect(session.editableIntermediateStations.map(\.crs) == ["HNH"])
        let originalLine = try #require(session.lines.first)
        let originalSavedLine = try #require(session.makeSaveSnapshot().lines.first)
        let originalFinance = session.financeLedger
        let originalRevision = session.persistenceRevision

        session.addIntermediateStation(brixton, toLineID: line.id)
        await session.waitForLineStopUpdate()

        #expect(session.makeSaveSnapshot().lines.first == originalSavedLine)
        #expect(session.lines.first?.id == originalLine.id)
        #expect(session.financeLedger == originalFinance)
        #expect(session.persistenceRevision == originalRevision)
        #expect(session.phase == .operating)
        #expect(session.errorMessage == nil)
    }

    @Test("An unaffordable stop addition remains an atomic no-op after routing")
    func unaffordableAddStopIsAtomic() async throws {
        let sourceProvider = Milestone14RoutingProvider()
        let source = makeSession(provider: sourceProvider, mode: .zen)
        await buildEndpointOnlyLine(in: source)
        let lowCashSnapshot = snapshot(
            source.makeSaveSnapshot(),
            replacingFinancialStateWithCash: 100_000_000
        )

        let provider = Milestone14RoutingProvider()
        let session = makeSession(provider: provider, mode: .career)
        try await session.restore(from: lowCashSnapshot)
        let line = try #require(session.lines.first)
        session.beginEditingStops(forLineID: line.id)
        await session.waitForLineStopUpdate()

        #expect(!session.canAffordIntermediateStation(brixton, toLineID: line.id))
        let originalLine = try #require(session.lines.first)
        let originalSavedLine = try #require(session.makeSaveSnapshot().lines.first)
        let originalFinance = session.financeLedger
        let originalRevision = session.persistenceRevision

        session.addIntermediateStation(brixton, toLineID: line.id)
        await session.waitForLineStopUpdate()

        #expect(session.makeSaveSnapshot().lines.first == originalSavedLine)
        #expect(session.lines.first?.id == originalLine.id)
        #expect(session.financeLedger == originalFinance)
        #expect(session.persistenceRevision == originalRevision)
        #expect(session.phase == .error)
        #expect(session.errorMessage?.contains("more funding") == true)
    }

    @Test("Failed High Speed conversion keeps the conventional multi-stop preview atomic")
    func failedHighSpeedConversionIsAtomic() async throws {
        let provider = Milestone14RoutingProvider()
        let session = makeSession(provider: provider, mode: .career)
        await createPreview(in: session)
        session.togglePreviewIntermediateStation(brixton)
        await session.waitForRouteCalculation()

        let originalPreview = try #require(session.preview)
        let originalFinance = session.financeLedger
        let originalRevision = session.persistenceRevision
        await provider.failNextRoute()

        session.setPreviewRailwayClass(.highSpeed)

        #expect(session.isUpdatingPreviewRoute)
        #expect(!session.canConfirmPreview)
        #expect(session.preview?.railwayClass == .conventional)
        #expect(session.preview?.stationCRSs == ["VIC", "BRX", "KTH"])
        #expect(session.previewSelectedStationCRSs == ["VIC", "BRX", "KTH"])

        session.confirmPreview()
        #expect(session.lines.isEmpty)
        #expect(session.financeLedger == originalFinance)
        await session.waitForRouteCalculation()

        let retainedPreview = try #require(session.preview)
        #expect(session.phase == .error)
        #expect(retainedPreview.id == originalPreview.id)
        #expect(retainedPreview.railwayClass == .conventional)
        #expect(retainedPreview.stationCRSs == originalPreview.stationCRSs)
        #expect(retainedPreview.route.stationCoordinateIndices
            == originalPreview.route.stationCoordinateIndices)
        #expect(coordinatesEqual(retainedPreview.route.coordinates, originalPreview.route.coordinates))
        #expect(retainedPreview.route.cumulativeDistances
            == originalPreview.route.cumulativeDistances)
        #expect(session.previewSelectedStationCRSs == originalPreview.stationCRSs)
        #expect(session.lines.isEmpty)
        #expect(session.financeLedger == originalFinance)
        #expect(session.persistenceRevision == originalRevision)
    }

    @Test(
        "Malformed calling-point positions cannot become purchasable",
        arguments: Milestone14RouteDefect.allCases
    )
    func malformedCallingPointRouteIsRejected(_ defect: Milestone14RouteDefect) async throws {
        let provider = Milestone14RoutingProvider()
        let session = makeSession(provider: provider, mode: .career)
        await createPreview(in: session)
        let originalFinance = session.financeLedger
        let originalRevision = session.persistenceRevision
        await provider.makeNextMultiStopRouteMalformed(defect)

        session.togglePreviewIntermediateStation(brixton)
        #expect(!session.canConfirmPreview)
        session.confirmPreview()
        #expect(session.lines.isEmpty)
        #expect(session.financeLedger == originalFinance)
        await session.waitForRouteCalculation()

        #expect(session.phase == .error)
        #expect(session.preview?.stationCRSs == ["VIC", "KTH"])
        #expect(session.previewSelectedStationCRSs == ["VIC", "KTH"])
        #expect(session.lines.isEmpty)
        #expect(session.financeLedger == originalFinance)
        #expect(session.persistenceRevision == originalRevision)
    }

    @Test("Adding a stop to a reverse service preserves and restores service orientation")
    func reverseServiceAddStopPreservesOrientation() async throws {
        let sourceProvider = Milestone14RoutingProvider()
        let source = makeSession(provider: sourceProvider, mode: .zen)
        await buildEndpointOnlyLine(in: source)
        let reversedSnapshot = snapshotWithReversedService(source.makeSaveSnapshot())

        let provider = Milestone14RoutingProvider()
        let session = makeSession(provider: provider, mode: .zen)
        try await session.restore(from: reversedSnapshot)
        let originalLine = try #require(session.lines.first)
        let originalTrains = originalLine.trains
        let originalCorridorCoordinates = originalLine.corridorRoute.coordinates
        let originalCorridorTotalLength = originalLine.corridorRoute.totalLength
        let originalCorridorDistance = originalLine.corridorDistanceMetres
        let originalCorridorCost = originalLine.corridorIndicativeCost
        let routeRequestsBeforeAdd = await provider.routeRequests

        session.beginEditingStops(forLineID: originalLine.id)
        await session.waitForLineStopUpdate()
        session.addIntermediateStation(herneHill, toLineID: originalLine.id)
        await session.waitForLineStopUpdate()

        let updatedLine = try #require(session.lines.first)
        #expect(updatedLine.stationCRSs == ["KTH", "HNH", "VIC"])
        #expect(updatedLine.corridorStationCRSs == ["VIC", "HNH", "KTH"])
        #expect(updatedLine.route.stationCoordinateIndices == [0, 1, 2])
        #expect(updatedLine.corridorRoute.stationCoordinateIndices == [0, 1, 2])
        #expect(updatedLine.corridorRoute.coordinates.count == originalCorridorCoordinates.count + 1)
        #expect(updatedLine.corridorRoute.totalLength == originalCorridorTotalLength)
        #expect(updatedLine.corridorDistanceMetres == originalCorridorDistance)
        #expect(updatedLine.corridorIndicativeCost == originalCorridorCost)
        #expect(await provider.routeRequests == routeRequestsBeforeAdd)
        #expect(trainStatesEqual(updatedLine.trains, originalTrains))

        let restoredProvider = Milestone14RoutingProvider()
        let restored = makeSession(provider: restoredProvider, mode: .zen)
        try await restored.restore(from: session.makeSaveSnapshot())
        let restoredLine = try #require(restored.lines.first)
        #expect(restoredLine.origin.crs == "KTH")
        #expect(restoredLine.destination.crs == "VIC")
        #expect(restoredLine.stationCRSs == ["KTH", "HNH", "VIC"])
        #expect(restoredLine.corridorStationCRSs == ["VIC", "HNH", "KTH"])
    }

    @Test("A skipped physical station becomes a free service call without duplicating the corridor")
    func skippedPhysicalStationCanBecomeAServiceCall() async throws {
        let sourceProvider = Milestone14RoutingProvider()
        let source = makeSession(provider: sourceProvider, mode: .career)
        await buildLineCallingAtBrixton(in: source)
        let endpointOnlySnapshot = snapshotWithEndpointOnlyService(source.makeSaveSnapshot())

        let provider = Milestone14RoutingProvider()
        let session = makeSession(provider: provider, mode: .career)
        try await session.restore(from: endpointOnlySnapshot)
        let originalLine = try #require(session.lines.first)
        let originalFinance = session.financeLedger
        let originalTrains = originalLine.trains
        let originalCorridorCoordinates = originalLine.corridorRoute.coordinates
        let originalCorridorDistances = originalLine.corridorRoute.cumulativeDistances
        let originalCorridorCost = originalLine.corridorIndicativeCost

        session.beginEditingStops(forLineID: originalLine.id)
        await session.waitForLineStopUpdate()
        #expect(session.intermediateStationAdditionCostPence(brixton, toLineID: originalLine.id) == 0)
        session.addIntermediateStation(brixton, toLineID: originalLine.id)
        await session.waitForLineStopUpdate()

        let updatedLine = try #require(session.lines.first)
        #expect(updatedLine.stationCRSs == ["VIC", "BRX", "KTH"])
        #expect(updatedLine.corridorStationCRSs == ["VIC", "BRX", "KTH"])
        #expect(updatedLine.corridorStationCRSs.filter { $0 == "BRX" }.count == 1)
        #expect(updatedLine.route.stationCoordinateIndices == [0, 1, 2])
        #expect(coordinatesEqual(updatedLine.corridorRoute.coordinates, originalCorridorCoordinates))
        #expect(updatedLine.corridorRoute.cumulativeDistances == originalCorridorDistances)
        #expect(updatedLine.corridorIndicativeCost == originalCorridorCost)
        #expect(session.financeLedger == originalFinance)
        #expect(trainStatesEqual(updatedLine.trains, originalTrains))

        let restoredProvider = Milestone14RoutingProvider()
        let restored = makeSession(provider: restoredProvider, mode: .career)
        try await restored.restore(from: session.makeSaveSnapshot())
        let restoredLine = try #require(restored.lines.first)
        #expect(restoredLine.stationCRSs == ["VIC", "BRX", "KTH"])
        #expect(restoredLine.corridorStationCRSs == ["VIC", "BRX", "KTH"])
    }

    @Test("A new stop and its physical capital basis remain stable through a cold restore")
    func newStopRemapsCustomServiceOntoCorridor() async throws {
        let sourceProvider = Milestone14RoutingProvider()
        let source = makeSession(provider: sourceProvider, mode: .career)
        await buildLineCallingAtBrixton(in: source)
        let endpointOnlySnapshot = snapshotWithEndpointOnlyService(
            source.makeSaveSnapshot(),
            trackCapacity: .passingLoop
        )

        let provider = Milestone14RoutingProvider(usesCustomEndpointRoute: true)
        let clock = Milestone14ManualClock()
        let session = makeSession(provider: provider, mode: .career, clock: clock)
        try await session.restore(from: endpointOnlySnapshot)
        clock.advance(by: 0.5)
        let originalLine = try #require(session.lines.first)
        let originalCorridorDistance = originalLine.corridorDistanceMetres
        let originalCorridorCost = originalLine.corridorIndicativeCost
        let originalTrackValue = session.financeSnapshot.trackAndInfrastructureValuePence
        #expect(originalLine.indicativeCost == originalCorridorCost)
        #expect(session.trackUpgradeCost(forLineID: originalLine.id) == 202_500_000)
        #expect(await provider.routeRequests == [["VIC", "BRX", "KTH"]])

        session.beginEditingStops(forLineID: originalLine.id)
        await session.waitForLineStopUpdate()
        session.addIntermediateStation(herneHill, toLineID: originalLine.id)
        await session.waitForLineStopUpdate()

        let updatedLine = try #require(session.lines.first)
        #expect(updatedLine.stationCRSs == ["VIC", "HNH", "KTH"])
        #expect(updatedLine.corridorStationCRSs == ["VIC", "BRX", "HNH", "KTH"])
        #expect(updatedLine.route.stationCoordinateIndices == [0, 2, 3])
        #expect(updatedLine.route.totalLength == 3_000)
        #expect(updatedLine.distanceMetres == updatedLine.route.totalLength)
        #expect(updatedLine.corridorDistanceMetres == originalCorridorDistance)
        #expect(updatedLine.corridorIndicativeCost == originalCorridorCost)
        #expect(updatedLine.indicativeCost == originalCorridorCost)
        #expect(updatedLine.trains.map(\.id) == originalLine.trains.map(\.id))
        #expect(trainStatesEqual(updatedLine.trains, originalLine.trains))
        #expect(session.financeSnapshot.trackAndInfrastructureValuePence == originalTrackValue)
        #expect(session.trackUpgradeCost(forLineID: updatedLine.id) == 202_500_000)

        let warmFinance = session.financeLedger
        let warmFinanceSnapshot = session.financeSnapshot
        let restoredProvider = Milestone14RoutingProvider(usesCustomEndpointRoute: true)
        let restored = makeSession(provider: restoredProvider, mode: .career)
        try await restored.restore(from: session.makeSaveSnapshot())

        let restoredLine = try #require(restored.lines.first)
        #expect(restoredLine.stationCRSs == updatedLine.stationCRSs)
        #expect(restoredLine.corridorStationCRSs == updatedLine.corridorStationCRSs)
        #expect(coordinatesEqual(restoredLine.route.coordinates, updatedLine.route.coordinates))
        #expect(restoredLine.route.cumulativeDistances == updatedLine.route.cumulativeDistances)
        #expect(restoredLine.route.stationCoordinateIndices
            == updatedLine.route.stationCoordinateIndices)
        #expect(coordinatesEqual(
            restoredLine.corridorRoute.coordinates,
            updatedLine.corridorRoute.coordinates
        ))
        #expect(restoredLine.corridorRoute.cumulativeDistances
            == updatedLine.corridorRoute.cumulativeDistances)
        #expect(restoredLine.distanceMetres == updatedLine.distanceMetres)
        #expect(restoredLine.corridorDistanceMetres == updatedLine.corridorDistanceMetres)
        #expect(restoredLine.indicativeCost == updatedLine.indicativeCost)
        #expect(restoredLine.corridorIndicativeCost == updatedLine.corridorIndicativeCost)
        #expect(trainStatesEqual(restoredLine.trains, updatedLine.trains))
        #expect(restored.financeLedger == warmFinance)
        #expect(restored.financeSnapshot.trackAndInfrastructureValuePence
            == warmFinanceSnapshot.trackAndInfrastructureValuePence)
        #expect(restored.financeSnapshot.networkValuePence == warmFinanceSnapshot.networkValuePence)
        #expect(restored.trackUpgradeCost(forLineID: restoredLine.id) == 202_500_000)
        #expect(await restoredProvider.routeRequests == [["VIC", "BRX", "HNH", "KTH"]])
    }

    @Test("Restore slices a forward interior service from its full physical corridor")
    func forwardInteriorServiceRestore() async throws {
        let sourceProvider = Milestone14RoutingProvider()
        let source = makeSession(provider: sourceProvider, mode: .zen)
        await buildEndpointOnlyLine(in: source)
        let snapshot = snapshotWithInteriorService(
            source.makeSaveSnapshot(),
            reversed: false
        )

        let provider = Milestone14RoutingProvider(usesCustomEndpointRoute: true)
        let session = makeSession(provider: provider, mode: .zen)
        try await session.restore(from: snapshot)

        let line = try #require(session.lines.first)
        #expect(line.origin.crs == "BRX")
        #expect(line.destination.crs == "HNH")
        #expect(line.stationCRSs == ["BRX", "HNH"])
        #expect(line.corridorStationCRSs == ["VIC", "BRX", "HNH", "KTH"])
        #expect(line.route.stationCoordinateIndices == [0, 1])
        #expect(line.route.cumulativeDistances == [0, 1_000])
        #expect(coordinatesEqual(
            line.route.coordinates,
            Array(line.corridorRoute.coordinates[1...2])
        ))
        #expect(line.distanceMetres == 1_000)
        #expect(line.corridorDistanceMetres == 3_000)
        #expect(line.indicativeCost == 4_500_000)
        #expect(line.corridorIndicativeCost == 4_500_000)
        #expect(await provider.routeRequests == [["VIC", "BRX", "HNH", "KTH"]])
    }

    @Test("Restore slices and reverses an interior service without reversing its corridor")
    func reverseInteriorServiceRestore() async throws {
        let sourceProvider = Milestone14RoutingProvider()
        let source = makeSession(provider: sourceProvider, mode: .zen)
        await buildEndpointOnlyLine(in: source)
        let snapshot = snapshotWithInteriorService(
            source.makeSaveSnapshot(),
            reversed: true
        )

        let provider = Milestone14RoutingProvider(usesCustomEndpointRoute: true)
        let session = makeSession(provider: provider, mode: .zen)
        try await session.restore(from: snapshot)

        let line = try #require(session.lines.first)
        #expect(line.origin.crs == "HNH")
        #expect(line.destination.crs == "BRX")
        #expect(line.stationCRSs == ["HNH", "BRX"])
        #expect(line.corridorStationCRSs == ["VIC", "BRX", "HNH", "KTH"])
        #expect(line.route.stationCoordinateIndices == [0, 1])
        #expect(line.route.cumulativeDistances == [0, 1_000])
        #expect(coordinatesEqual(
            line.route.coordinates,
            [line.corridorRoute.coordinates[2], line.corridorRoute.coordinates[1]]
        ))
        #expect(line.distanceMetres == 1_000)
        #expect(line.corridorDistanceMetres == 3_000)
        #expect(line.indicativeCost == 4_500_000)
        #expect(line.corridorIndicativeCost == 4_500_000)
        #expect(await provider.routeRequests == [["VIC", "BRX", "HNH", "KTH"]])
    }

    @Test("Forward interior-service editing exposes only in-span calls in travel order")
    func forwardInteriorServiceDiscoverySpan() async throws {
        let sourceProvider = Milestone14RoutingProvider()
        let source = makeSession(provider: sourceProvider, mode: .zen)
        await buildEndpointOnlyLine(in: source)
        let snapshot = snapshotWithInteriorService(
            source.makeSaveSnapshot(),
            reversed: false
        )

        let provider = Milestone14RoutingProvider(includesExtendedDiscoveryCandidates: true)
        let session = makeSession(provider: provider, mode: .zen)
        try await session.restore(from: snapshot)
        let line = try #require(session.lines.first)

        session.beginEditingStops(forLineID: line.id)
        await session.waitForLineStopUpdate()

        #expect(session.editableIntermediateStations.map(\.crs) == ["TUL", "WDU"])
        session.addIntermediateStation(tulseHill, toLineID: line.id)
        await session.waitForLineStopUpdate()
        let updatedLine = try #require(session.lines.first)
        #expect(updatedLine.stationCRSs == ["BRX", "TUL", "HNH"])
        #expect(updatedLine.corridorRoute.cumulativeDistances.contains(1_250))
        #expect(updatedLine.route.cumulativeDistances == [0, 250, 1_000])
    }

    @Test("Reverse interior-service editing exposes only in-span calls in reverse travel order")
    func reverseInteriorServiceDiscoverySpan() async throws {
        let sourceProvider = Milestone14RoutingProvider()
        let source = makeSession(provider: sourceProvider, mode: .zen)
        await buildEndpointOnlyLine(in: source)
        let snapshot = snapshotWithInteriorService(
            source.makeSaveSnapshot(),
            reversed: true
        )

        let provider = Milestone14RoutingProvider(includesExtendedDiscoveryCandidates: true)
        let session = makeSession(provider: provider, mode: .zen)
        try await session.restore(from: snapshot)
        let line = try #require(session.lines.first)

        session.beginEditingStops(forLineID: line.id)
        await session.waitForLineStopUpdate()

        #expect(session.editableIntermediateStations.map(\.crs) == ["WDU", "TUL"])
        session.addIntermediateStation(westDulwich, toLineID: line.id)
        await session.waitForLineStopUpdate()
        let updatedLine = try #require(session.lines.first)
        #expect(updatedLine.stationCRSs == ["HNH", "WDU", "BRX"])
        #expect(updatedLine.corridorRoute.cumulativeDistances.contains(1_750))
        #expect(updatedLine.route.cumulativeDistances == [0, 250, 1_000])
    }

    @Test("A dwelling train remains pinned to its retained station after geometry changes")
    func dwellingTrainRemapUsesRetainedStation() throws {
        let session = makeSession(provider: Milestone14RoutingProvider(), mode: .zen)
        let oldRoute = remapOldRoute()
        let newRoute = remapNewRoute()
        let lineID = UUID()
        let trainID = UUID()
        let train = TrainState(
            id: trainID,
            lineID: lineID,
            coordinate: oldRoute.coordinates[1],
            bearing: 12,
            distanceAlongRoute: 600,
            direction: .reverse,
            dwellRemaining: 1.25
        )

        let remapped = try #require(session.remappingTrains(
            [train],
            from: oldRoute,
            stationCRSs: ["VIC", "BRX", "KTH"],
            to: newRoute,
            stationCRSs: ["VIC", "BRX", "HNH", "KTH"]
        ).first)

        #expect(remapped.id == trainID)
        #expect(remapped.lineID == lineID)
        #expect(remapped.distanceAlongRoute == 1_000)
        #expect(remapped.coordinate.latitude == newRoute.coordinates[1].latitude)
        #expect(remapped.coordinate.longitude == newRoute.coordinates[1].longitude)
        #expect(remapped.direction == .reverse)
        #expect(remapped.bearing == 180)
        #expect(remapped.dwellRemaining == 1.25)
    }

    @Test("A moving train keeps progress within its retained station leg")
    func movingTrainRemapUsesLegRelativeProgress() throws {
        let session = makeSession(provider: Milestone14RoutingProvider(), mode: .zen)
        let oldRoute = remapOldRoute()
        let newRoute = remapNewRoute()
        let lineID = UUID()
        let trainID = UUID()
        let train = TrainState(
            id: trainID,
            lineID: lineID,
            coordinate: oldRoute.sample(atDistance: 1_050)?.coordinate
                ?? oldRoute.coordinates[1],
            bearing: 12,
            distanceAlongRoute: 1_050,
            direction: .forward,
            dwellRemaining: 0
        )

        let remapped = try #require(session.remappingTrains(
            [train],
            from: oldRoute,
            stationCRSs: ["VIC", "BRX", "KTH"],
            to: newRoute,
            stationCRSs: ["VIC", "BRX", "HNH", "KTH"]
        ).first)
        let expectedSample = try #require(newRoute.sample(atDistance: 1_500))

        #expect(remapped.id == trainID)
        #expect(remapped.lineID == lineID)
        #expect(remapped.distanceAlongRoute == 1_500)
        #expect(remapped.distanceAlongRoute != newRoute.totalLength * (1_050 / 2_400))
        #expect(remapped.coordinate.latitude == expectedSample.coordinate.latitude)
        #expect(remapped.coordinate.longitude == expectedSample.coordinate.longitude)
        #expect(remapped.direction == .forward)
        #expect(remapped.bearing == expectedSample.bearing)
        #expect(remapped.dwellRemaining == 0)
    }

    @Test("Milestone 16 custom plans drive exact markets, capacity, and train movement")
    func customTrainPlansDriveTheLiveNetwork() async throws {
        let provider = Milestone14RoutingProvider()
        let clock = Milestone14ManualClock()
        let session = makeSession(provider: provider, mode: .zen, clock: clock)
        await buildFourStopLine(in: session)

        let line = try #require(session.lines.first)
        let trainIDs = line.trains.map(\.id)
        #expect(trainIDs.count == 2)
        let financeBefore = session.financeLedger

        #expect(session.setTrainServicePlan(
            TrainServicePlan(
                slotIndex: 99,
                role: .local,
                stationCRSs: ["VIC", "BRX", "HNH"]
            ),
            forTrainID: trainIDs[0]
        ))
        #expect(session.setTrainServicePlan(
            TrainServicePlan(
                slotIndex: 99,
                role: .express,
                stationCRSs: ["BRX", "KTH"]
            ),
            forTrainID: trainIDs[1]
        ))

        #expect(session.financeLedger == financeBefore)
        #expect(session.hasCustomServicePlans(forLineID: line.id))
        #expect(session.trainServicePlan(for: trainIDs[0]) == TrainServicePlan(
            slotIndex: 0,
            role: .local,
            stationCRSs: ["VIC", "BRX", "HNH"]
        ))
        #expect(session.trainServicePlan(for: trainIDs[1]) == TrainServicePlan(
            slotIndex: 1,
            role: .express,
            stationCRSs: ["BRX", "KTH"]
        ))

        let directMarkets = Set(
            session.passengerSnapshot.serviceMarketSnapshots
                .filter { $0.serviceID == line.id }
                .map { "\($0.originCRS)-\($0.destinationCRS)" }
        )
        #expect(directMarkets == Set([
            "VIC-BRX",
            "VIC-HNH",
            "BRX-HNH",
            "BRX-KTH",
        ]))
        let capacity = try #require(session.stationCapacitySnapshot(forLineID: line.id))
        #expect(Set(capacity.effectiveDeparturesBySlot.keys) == Set([0, 1]))

        var localCalledAtBrixton = false
        var expressStoppedAtOmittedHerneHill = false
        for _ in 0..<240 {
            clock.advance(by: 0.25)
            let current = try #require(session.lines.first)
            let local = try #require(current.trains.first(where: { $0.id == trainIDs[0] }))
            let express = try #require(current.trains.first(where: { $0.id == trainIDs[1] }))
            #expect(local.distanceAlongRoute >= -0.001)
            #expect(local.distanceAlongRoute <= 2_000.001)
            #expect(express.distanceAlongRoute >= 999.999)
            #expect(express.distanceAlongRoute <= 3_000.001)
            if local.dwellRemaining > 0,
               abs(local.distanceAlongRoute - 1_000) < 0.001 {
                localCalledAtBrixton = true
            }
            if express.dwellRemaining > 0,
               abs(express.distanceAlongRoute - 2_000) < 0.001 {
                expressStoppedAtOmittedHerneHill = true
            }
        }
        #expect(localCalledAtBrixton)
        #expect(!expressStoppedAtOmittedHerneHill)
    }

    @Test("Changing a live stopping plan invalidates its cached movement bounds")
    func changingStoppingPlanRefreshesMovementTopology() async throws {
        let provider = Milestone14RoutingProvider()
        let clock = Milestone14ManualClock()
        let session = makeSession(provider: provider, mode: .zen, clock: clock)
        await buildFourStopLine(in: session)

        let line = try #require(session.lines.first)
        let trainID = try #require(line.trains.first?.id)
        #expect(session.setTrainServicePlan(
            TrainServicePlan(
                slotIndex: 0,
                role: .local,
                stationCRSs: ["VIC", "BRX"]
            ),
            forTrainID: trainID
        ))

        // Prime the per-slot movement cache with the western short working.
        clock.advance(by: 0.25)
        let westernTrain = try #require(
            session.lines.first?.trains.first(where: { $0.id == trainID })
        )
        #expect(westernTrain.distanceAlongRoute >= -0.001)
        #expect(westernTrain.distanceAlongRoute <= 1_000.001)

        #expect(session.setTrainServicePlan(
            TrainServicePlan(
                slotIndex: 0,
                role: .local,
                stationCRSs: ["HNH", "KTH"]
            ),
            forTrainID: trainID
        ))

        for _ in 0..<20 {
            clock.advance(by: 0.25)
            let easternTrain = try #require(
                session.lines.first?.trains.first(where: { $0.id == trainID })
            )
            #expect(easternTrain.distanceAlongRoute >= 1_999.999)
            #expect(easternTrain.distanceAlongRoute <= 3_000.001)
        }
    }

    @Test("Milestone 16 dormant plans survive frequency changes and fleet presets reset them")
    func customPlansSurviveFrequencyChangesUntilReset() async throws {
        let provider = Milestone14RoutingProvider()
        let session = makeSession(provider: provider, mode: .zen)
        await buildFourStopLine(in: session)
        let lineID = try #require(session.lines.first?.id)

        session.setServiceFrequency(.quarterHourly, forLineID: lineID)
        let expanded = try #require(session.lines.first)
        #expect(expanded.trains.count == 4)
        let financeBeforePlanEdits = session.financeLedger
        let slotTwoPlan = TrainServicePlan(
            slotIndex: 2,
            role: .express,
            stationCRSs: ["KTH", "HNH", "BRX"]
        )
        let slotThreePlan = TrainServicePlan(
            slotIndex: 3,
            role: .local,
            stationCRSs: ["BRX", "HNH", "KTH"]
        )
        #expect(session.setTrainServicePlan(slotTwoPlan, forTrainID: expanded.trains[2].id))
        #expect(session.setTrainServicePlan(slotThreePlan, forTrainID: expanded.trains[3].id))
        #expect(session.financeLedger == financeBeforePlanEdits)

        let unchangedBeforeInvalidEdit = try #require(session.lines.first).trainServicePlans
        #expect(!session.setTrainServicePlan(
            TrainServicePlan(
                slotIndex: 2,
                role: .local,
                stationCRSs: ["VIC", "HNH"]
            ),
            forTrainID: expanded.trains[2].id
        ))
        #expect(session.lines.first?.trainServicePlans == unchangedBeforeInvalidEdit)

        session.setServiceFrequency(.hourly, forLineID: lineID)
        #expect(session.lines.first?.trains.count == 1)
        #expect(session.lines.first?.servicePlan(forSlot: 2) == slotTwoPlan)
        #expect(session.lines.first?.servicePlan(forSlot: 3) == slotThreePlan)

        session.setServiceFrequency(.quarterHourly, forLineID: lineID)
        let restoredFleet = try #require(session.lines.first)
        #expect(restoredFleet.trains.count == 4)
        #expect(session.trainServicePlan(for: restoredFleet.trains[2].id) == slotTwoPlan)
        #expect(session.trainServicePlan(for: restoredFleet.trains[3].id) == slotThreePlan)

        session.setServicePattern(.balanced, forLineID: lineID)
        let resetLine = try #require(session.lines.first)
        #expect(resetLine.trainServicePlans == TrainServicePlan.legacyDefaults(
            servicePattern: .balanced,
            serviceStationCRSs: ["VIC", "BRX", "HNH", "KTH"]
        ))
        #expect(!session.hasCustomServicePlans(forLineID: lineID))
    }

    @Test("Milestone 16 plans and safe train positions round-trip through a save")
    func customPlansRoundTripThroughGameSessionRestore() async throws {
        let provider = Milestone14RoutingProvider()
        let clock = Milestone14ManualClock()
        let session = makeSession(provider: provider, mode: .zen, clock: clock)
        await buildFourStopLine(in: session)
        let lineID = try #require(session.lines.first?.id)
        session.setServiceFrequency(.quarterHourly, forLineID: lineID)
        let active = try #require(session.lines.first)
        let requestedPlans = [
            TrainServicePlan(
                slotIndex: 0,
                role: .local,
                stationCRSs: ["VIC", "BRX", "HNH"]
            ),
            TrainServicePlan(
                slotIndex: 1,
                role: .express,
                stationCRSs: ["BRX", "KTH"]
            ),
            TrainServicePlan(
                slotIndex: 2,
                role: .express,
                stationCRSs: ["KTH", "HNH", "VIC"]
            ),
            TrainServicePlan(
                slotIndex: 3,
                role: .local,
                stationCRSs: ["KTH", "HNH", "BRX"]
            ),
        ]
        for (train, plan) in zip(active.trains, requestedPlans) {
            #expect(session.setTrainServicePlan(plan, forTrainID: train.id))
        }
        clock.advance(by: 7.25)

        let savedLine = try #require(session.lines.first)
        let snapshot = session.makeSaveSnapshot()
        #expect(snapshot.schemaVersion == 12)
        let restored = makeSession(
            provider: Milestone14RoutingProvider(),
            mode: .career
        )
        try await restored.restore(from: snapshot)

        let restoredLine = try #require(restored.lines.first)
        #expect(restoredLine.id == savedLine.id)
        #expect(restoredLine.trainServicePlans == requestedPlans)
        #expect(restoredLine.trains.map(\.id) == savedLine.trains.map(\.id))
        #expect(restored.financeLedger == session.financeLedger)
        for (slot, train) in restoredLine.trains.enumerated() {
            let plan = try #require(restoredLine.servicePlan(forSlot: slot))
            let available = restoredLine.stationCRSs
            let firstIndex = try #require(available.firstIndex(of: plan.stationCRSs[0]))
            let lastIndex = try #require(available.firstIndex(of: plan.stationCRSs.last!))
            let lower = Double(min(firstIndex, lastIndex)) * 1_000
            let upper = Double(max(firstIndex, lastIndex)) * 1_000
            #expect(train.distanceAlongRoute >= lower - 0.001)
            #expect(train.distanceAlongRoute <= upper + 0.001)
        }
    }

    private var victoria: Station {
        Station(crs: "VIC", name: "London Victoria", latitude: 51.4952, longitude: -0.1441)
    }

    private var brixton: Station {
        Station(crs: "BRX", name: "Brixton", latitude: 51.4633, longitude: -0.1142)
    }

    private var herneHill: Station {
        Station(crs: "HNH", name: "Herne Hill", latitude: 51.4535, longitude: -0.1026)
    }

    private var northOutside: Station {
        Station(crs: "NPH", name: "North of Brixton", latitude: 51.48, longitude: -0.125)
    }

    private var tulseHill: Station {
        Station(crs: "TUL", name: "Tulse Hill", latitude: 51.46, longitude: -0.1075)
    }

    private var westDulwich: Station {
        Station(crs: "WDU", name: "West Dulwich", latitude: 51.455, longitude: -0.1025)
    }

    private var southOutside: Station {
        Station(crs: "PNR", name: "South of Herne Hill", latitude: 51.44, longitude: -0.085)
    }

    private var kentHouse: Station {
        Station(crs: "KTH", name: "Kent House", latitude: 51.4122, longitude: -0.0453)
    }

    private func makeSession(
        provider: Milestone14RoutingProvider,
        mode: GameMode,
        clock: Milestone14ManualClock? = nil,
        maximumServiceCallCount: Int = 16
    ) -> GameSession {
        let resolvedClock = clock ?? Milestone14ManualClock()
        return GameSession(
            stations: [
                victoria,
                northOutside,
                brixton,
                tulseHill,
                westDulwich,
                herneHill,
                southOutside,
                kentHouse,
            ],
            routingProvider: provider,
            stationCapacitySimulation: StationCapacitySimulation(
                configuration: StationCapacityConfiguration(
                    trainCallsPerPlatformPerHour: 1_000_000
                )
            ),
            capitalEconomy: CapitalEconomy(),
            gameMode: mode,
            clock: resolvedClock,
            configuration: GameConfiguration(
                maximumLineCount: 12,
                constructionDuration: 0,
                trainSpeedMetresPerSecond: 100,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: 1_500_000,
                operatingDayDuration: 30,
                maximumServiceCallCount: maximumServiceCallCount
            )
        )
    }

    private func createPreview(in session: GameSession) async {
        session.startBuilding()
        session.selectStation(victoria)
        session.selectStation(kentHouse)
        await session.waitForRouteCalculation()
        #expect(session.phase == .preview)
    }

    private func buildEndpointOnlyLine(in session: GameSession) async {
        await createPreview(in: session)
        session.setPreviewFormation(.legacyBaseline)
        session.confirmPreview()
        #expect(session.phase == .operating)
    }

    private func buildLineCallingAtBrixton(in session: GameSession) async {
        await createPreview(in: session)
        session.togglePreviewIntermediateStation(brixton)
        await session.waitForRouteCalculation()
        session.setPreviewFormation(.legacyBaseline)
        session.confirmPreview()
        #expect(session.phase == .operating)
    }

    private func buildFourStopLine(in session: GameSession) async {
        await createPreview(in: session)
        session.togglePreviewIntermediateStation(brixton)
        await session.waitForRouteCalculation()
        session.togglePreviewIntermediateStation(herneHill)
        await session.waitForRouteCalculation()
        session.setPreviewFormation(.legacyBaseline)
        session.confirmPreview()
        #expect(session.phase == .operating)
        #expect(session.lines.first?.stationCRSs == ["VIC", "BRX", "HNH", "KTH"])
    }

    private func snapshot(
        _ source: GameSaveSnapshot,
        replacingFinancialStateWithCash cashBalancePence: Int64
    ) -> GameSaveSnapshot {
        let old = source.financialState
        return GameSaveSnapshot(
            savedAt: source.savedAt,
            isPlaying: source.isPlaying,
            simulationSpeed: source.simulationSpeed,
            lines: source.lines,
            corridors: source.corridors,
            stationProgress: source.stationProgress,
            stationPopulations: source.stationPopulations,
            economy: source.economy,
            financialState: SavedFinancialState(
                mode: .career,
                cashBalancePence: cashBalancePence,
                loans: old.loans,
                lifetimeConstructionSpendPence: old.lifetimeConstructionSpendPence,
                lifetimeRollingStockSpendPence: old.lifetimeRollingStockSpendPence,
                lifetimeLoanProceedsPence: old.lifetimeLoanProceedsPence,
                lifetimePrincipalRepaidPence: old.lifetimePrincipalRepaidPence,
                lifetimeInterestPaidPence: old.lifetimeInterestPaidPence,
                hasIncompleteCapitalHistory: old.hasIncompleteCapitalHistory,
                consecutiveNegativeCashDays: 0,
                bankruptcyOperatingDay: nil,
                trackingStartedOnOperatingDay: old.trackingStartedOnOperatingDay
            ),
            publicBetaHistory: source.publicBetaHistory
        )
    }

    private func snapshotWithReversedService(_ source: GameSaveSnapshot) -> GameSaveSnapshot {
        guard let line = source.lines.first else { return source }
        let reversedLine = SavedLineRecord(
            id: line.id,
            originCRS: line.destinationCRS,
            destinationCRS: line.originCRS,
            styleIndex: line.styleIndex,
            constructionProgress: line.constructionProgress,
            frequency: line.frequency,
            railwayClass: line.railwayClass,
            formation: line.formation,
            servicePattern: line.servicePattern,
            trackCapacity: line.trackCapacity,
            ownedTrainCount: line.ownedTrainCount,
            trains: line.trains,
            corridorIDs: line.corridorIDs,
            stationCRSs: Array(line.stationCRSs.reversed())
        )
        return GameSaveSnapshot(
            schemaVersion: source.schemaVersion,
            savedAt: source.savedAt,
            isPlaying: source.isPlaying,
            simulationSpeed: source.simulationSpeed,
            lines: [reversedLine],
            corridors: source.corridors,
            stationProgress: source.stationProgress,
            stationPopulations: source.stationPopulations,
            economy: source.economy,
            financialState: source.financialState,
            publicBetaHistory: source.publicBetaHistory
        )
    }

    private func snapshotWithEndpointOnlyService(
        _ source: GameSaveSnapshot,
        trackCapacity: SavedTrackCapacity? = nil
    ) -> GameSaveSnapshot {
        guard let line = source.lines.first else { return source }
        let resolvedTrackCapacity = trackCapacity ?? line.trackCapacity
        let endpointOnlyLine = SavedLineRecord(
            id: line.id,
            originCRS: line.originCRS,
            destinationCRS: line.destinationCRS,
            styleIndex: line.styleIndex,
            constructionProgress: line.constructionProgress,
            frequency: line.frequency,
            railwayClass: line.railwayClass,
            formation: line.formation,
            servicePattern: line.servicePattern,
            trackCapacity: resolvedTrackCapacity,
            ownedTrainCount: line.ownedTrainCount,
            trains: line.trains,
            corridorIDs: line.corridorIDs,
            stationCRSs: [line.originCRS, line.destinationCRS]
        )
        return GameSaveSnapshot(
            schemaVersion: source.schemaVersion,
            savedAt: source.savedAt,
            isPlaying: source.isPlaying,
            simulationSpeed: source.simulationSpeed,
            lines: [endpointOnlyLine],
            corridors: source.corridors.map { corridor in
                SavedRailwayCorridorRecord(
                    id: corridor.id,
                    stationCRSs: corridor.stationCRSs,
                    constructionProgress: corridor.constructionProgress,
                    railwayClass: corridor.railwayClass,
                    trackCapacity: trackCapacity ?? corridor.trackCapacity
                )
            },
            stationProgress: source.stationProgress,
            stationPopulations: source.stationPopulations,
            economy: source.economy,
            financialState: source.financialState,
            publicBetaHistory: source.publicBetaHistory
        )
    }

    private func snapshotWithInteriorService(
        _ source: GameSaveSnapshot,
        reversed: Bool
    ) -> GameSaveSnapshot {
        guard let line = source.lines.first,
              let corridor = source.corridors.first else { return source }
        let serviceCRSs = reversed ? ["HNH", "BRX"] : ["BRX", "HNH"]
        let interiorLine = SavedLineRecord(
            id: line.id,
            originCRS: serviceCRSs[0],
            destinationCRS: serviceCRSs[1],
            styleIndex: line.styleIndex,
            constructionProgress: line.constructionProgress,
            frequency: line.frequency,
            railwayClass: line.railwayClass,
            formation: line.formation,
            servicePattern: line.servicePattern,
            trackCapacity: line.trackCapacity,
            ownedTrainCount: line.ownedTrainCount,
            trains: line.trains,
            corridorIDs: line.corridorIDs,
            stationCRSs: serviceCRSs
        )
        let fullCorridor = SavedRailwayCorridorRecord(
            id: corridor.id,
            stationCRSs: ["VIC", "BRX", "HNH", "KTH"],
            constructionProgress: corridor.constructionProgress,
            railwayClass: corridor.railwayClass,
            trackCapacity: corridor.trackCapacity
        )
        return GameSaveSnapshot(
            schemaVersion: source.schemaVersion,
            savedAt: source.savedAt,
            isPlaying: source.isPlaying,
            simulationSpeed: source.simulationSpeed,
            lines: [interiorLine],
            corridors: [fullCorridor],
            stationProgress: source.stationProgress,
            stationPopulations: [],
            economy: source.economy,
            financialState: source.financialState,
            publicBetaHistory: source.publicBetaHistory
        )
    }

    private func remapOldRoute() -> ServiceRailwayRoute {
        ServiceRailwayRoute(
            coordinates: [
                CLLocationCoordinate2D(latitude: 0, longitude: 0),
                CLLocationCoordinate2D(latitude: 0.01, longitude: 0),
                CLLocationCoordinate2D(latitude: 0.03, longitude: 0),
            ],
            cumulativeDistances: [0, 600, 2_400],
            stationCoordinateIndices: [0, 1, 2]
        )
    }

    private func remapNewRoute() -> ServiceRailwayRoute {
        ServiceRailwayRoute(
            coordinates: [
                CLLocationCoordinate2D(latitude: 0, longitude: 0),
                CLLocationCoordinate2D(latitude: 0.01, longitude: 0),
                CLLocationCoordinate2D(latitude: 0.02, longitude: 0),
                CLLocationCoordinate2D(latitude: 0.03, longitude: 0),
            ],
            cumulativeDistances: [0, 1_000, 2_000, 3_000],
            stationCoordinateIndices: [0, 1, 2, 3]
        )
    }

    private func trainStatesEqual(_ lhs: [TrainState], _ rhs: [TrainState]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        let bearingTolerance = 0.01
        return zip(lhs, rhs).allSatisfy { pair in
            pair.0.id == pair.1.id
                && pair.0.lineID == pair.1.lineID
                && pair.0.coordinate.latitude == pair.1.coordinate.latitude
                && pair.0.coordinate.longitude == pair.1.coordinate.longitude
                && abs(pair.0.bearing - pair.1.bearing) <= bearingTolerance
                && pair.0.distanceAlongRoute == pair.1.distanceAlongRoute
                && pair.0.direction == pair.1.direction
                && pair.0.dwellRemaining == pair.1.dwellRemaining
        }
    }

    private func coordinatesEqual(
        _ lhs: [CLLocationCoordinate2D],
        _ rhs: [CLLocationCoordinate2D]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        let tolerance = 0.000_000_000_001
        return zip(lhs, rhs).allSatisfy { pair in
            abs(pair.0.latitude - pair.1.latitude) <= tolerance
                && abs(pair.0.longitude - pair.1.longitude) <= tolerance
        }
    }
}

private actor Milestone14RoutingProvider: RailwayRouteProviding {
    private(set) var routeRequests = [[String]]()
    private let usesCustomEndpointRoute: Bool
    private let includesExtendedDiscoveryCandidates: Bool
    private var shouldFailNextRoute = false
    private var nextMultiStopDefect: Milestone14RouteDefect?
    private var shouldUseInvalidDiscoveryDistance = false

    init(
        usesCustomEndpointRoute: Bool = false,
        includesExtendedDiscoveryCandidates: Bool = false
    ) {
        self.usesCustomEndpointRoute = usesCustomEndpointRoute
        self.includesExtendedDiscoveryCandidates = includesExtendedDiscoveryCandidates
    }

    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        let normalized = stationCRSs.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        routeRequests.append(normalized)
        if shouldFailNextRoute {
            shouldFailNextRoute = false
            throw Milestone14RoutingError.unavailable
        }

        let routePositions: [String: CLLocationDistance] = [
            "VIC": 0,
            "NPH": 500,
            "BRX": 1_000,
            "TUL": 1_250,
            "WDU": 1_750,
            "HNH": 2_000,
            "PNR": 2_500,
            "KTH": 3_000,
        ]
        let callPositions = normalized.compactMap { routePositions[$0] }
        guard callPositions.count == normalized.count,
              callPositions.count >= 2,
              let startPosition = callPositions.first,
              let endPosition = callPositions.last,
              startPosition != endPosition else {
            throw Milestone14RoutingError.unavailable
        }
        let isForward = startPosition < endPosition
        guard zip(callPositions, callPositions.dropFirst()).allSatisfy({ pair in
            isForward ? pair.0 < pair.1 : pair.0 > pair.1
        }) else {
            throw Milestone14RoutingError.unavailable
        }
        if usesCustomEndpointRoute, normalized == ["VIC", "KTH"] {
            let originCoordinate = coordinate(at: startPosition)
            let destinationCoordinate = coordinate(at: endPosition)
            return ServiceRailwayRoute(
                coordinates: [
                    originCoordinate,
                    CLLocationCoordinate2D(
                        latitude: (originCoordinate.latitude + destinationCoordinate.latitude) / 2
                            + 0.01,
                        longitude: (originCoordinate.longitude + destinationCoordinate.longitude) / 2
                    ),
                    destinationCoordinate,
                ],
                cumulativeDistances: [0, 1_200, 2_400],
                stationCoordinateIndices: [0, 2]
            )
        }
        let routePositionsAlongDirection = callPositions
        var stationCoordinateIndices = Array(callPositions.indices)
        if normalized.count > 2, let defect = nextMultiStopDefect {
            nextMultiStopDefect = nil
            switch defect {
            case .outOfRange:
                stationCoordinateIndices[1] = routePositionsAlongDirection.count
            case .duplicate:
                stationCoordinateIndices[1] = stationCoordinateIndices[0]
            case .nonIncreasing:
                stationCoordinateIndices[1] = stationCoordinateIndices.last ?? 0
                stationCoordinateIndices[stationCoordinateIndices.count - 1] = 1
            }
        }
        return ServiceRailwayRoute(
            coordinates: routePositionsAlongDirection.map(coordinate(at:)),
            cumulativeDistances: routePositionsAlongDirection.map {
                abs($0 - startPosition)
            },
            stationCoordinateIndices: stationCoordinateIndices
        )
    }

    func discoverIntermediateStations(
        on route: ServiceRailwayRoute,
        endpointCRSs: [String],
        catalogStations: [Station]
    ) async throws -> [CorridorStationMatch] {
        let byCRS = Dictionary(
            catalogStations.map { ($0.crs.uppercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let invalidDiscoveryDistance = shouldUseInvalidDiscoveryDistance
        shouldUseInvalidDiscoveryDistance = false
        let discoveryPositions: [(String, CLLocationDistance)] =
            includesExtendedDiscoveryCandidates
                ? [
                    ("PNR", 2_500),
                    ("TUL", 1_250),
                    ("NPH", 500),
                    ("WDU", 1_750),
                ]
                : [
                    ("BRX", invalidDiscoveryDistance ? 0 : 1_000),
                    ("HNH", 2_000),
                ]
        return discoveryPositions.compactMap { crs, distance in
            guard let station = byCRS[crs] else { return nil }
            let coordinateIndex = route.cumulativeDistances.indices.min { lhs, rhs in
                abs(route.cumulativeDistances[lhs] - distance)
                    < abs(route.cumulativeDistances[rhs] - distance)
            } ?? 0
            return CorridorStationMatch(
                station: station,
                routeDistance: distance,
                routeProgress: route.totalLength > 0 ? distance / route.totalLength : 0,
                routeCoordinateIndex: coordinateIndex,
                offsetFromRoute: 0
            )
        }
    }

    func failNextRoute() {
        shouldFailNextRoute = true
    }

    func makeNextMultiStopRouteMalformed(_ defect: Milestone14RouteDefect) {
        nextMultiStopDefect = defect
    }

    func useInvalidRouteDistanceForNextDiscovery() {
        shouldUseInvalidDiscoveryDistance = true
    }

    private func coordinate(at position: CLLocationDistance) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: 51.5 - position / 100_000,
            longitude: -0.14 + position / 100_000
        )
    }
}

nonisolated enum Milestone14RouteDefect: CaseIterable, Sendable {
    case outOfRange
    case duplicate
    case nonIncreasing
}

private nonisolated enum Milestone14RoutingError: LocalizedError {
    case unavailable

    var errorDescription: String? { "The intermediate route is unavailable." }
}

@MainActor
private final class Milestone14ManualClock: SimulationClock {
    private var tickHandler: (@MainActor (TimeInterval) -> Void)?

    func start(tick: @escaping @MainActor (TimeInterval) -> Void) {
        tickHandler = tick
    }

    func stop() {
        tickHandler = nil
    }

    func setSuspended(_ isSuspended: Bool) {}

    func advance(by delta: TimeInterval) {
        tickHandler?(delta)
    }
}
