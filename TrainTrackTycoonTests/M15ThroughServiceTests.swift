import CoreLocation
import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Milestone 15 through services", .serialized)
@MainActor
struct M15ThroughServiceTests {
    @Test("Corridor composition handles both reversed segments and distinct junction anchors")
    func corridorCompositionOrientation() throws {
        let first = RailwayCorridor(
            id: UUID(),
            stationCRSs: ["ECR", "PUR"],
            route: ServiceRailwayRoute(
                coordinates: [coordinate(1), coordinate(0)],
                stationCoordinateIndices: [0, 1]
            ),
            distanceMetres: 1_000,
            indicativeCost: 10,
            railwayClass: .conventional,
            trackCapacity: .singleTrack,
            constructionProgress: 1
        )
        let second = RailwayCorridor(
            id: UUID(),
            stationCRSs: ["HOR", "ECR"],
            route: ServiceRailwayRoute(
                coordinates: [coordinate(2), shiftedJunctionCoordinate],
                stationCoordinateIndices: [0, 1]
            ),
            distanceMetres: 1_000,
            indicativeCost: 20,
            railwayClass: .conventional,
            trackCapacity: .singleTrack,
            constructionProgress: 1
        )

        let assembly = try #require(
            RailwayCorridorChainAssembler.assemblies(for: [first, second]).first {
                $0.stationCRSs == ["PUR", "ECR", "HOR"]
            }
        )

        #expect(assembly.corridorIDs == [first.id, second.id])
        #expect(assembly.stationCRSs == ["PUR", "ECR", "HOR"])
        #expect(assembly.route.stationCoordinateIndices.count == 3)
        #expect(assembly.route.stationCoordinateIndices == assembly.route.stationCoordinateIndices.sorted())
        #expect(assembly.route.coordinates.count == 4)
        #expect(assembly.indicativeCost == 30)
        #expect(zip(
            assembly.route.cumulativeDistances,
            assembly.route.cumulativeDistances.dropFirst()
        ).allSatisfy { $0.0 < $0.1 })
        let seamLength = CLLocation(
            latitude: coordinate(1).latitude,
            longitude: coordinate(1).longitude
        ).distance(from: CLLocation(
            latitude: shiftedJunctionCoordinate.latitude,
            longitude: shiftedJunctionCoordinate.longitude
        ))
        let expectedLength = first.route.totalLength + seamLength + second.route.totalLength
        #expect(abs(assembly.route.totalLength - expectedLength) < 0.001)
        let secondSegmentDistance = first.route.totalLength + seamLength
            + second.route.totalLength / 2
        let joinedSample = try #require(assembly.route.sample(atDistance: secondSegmentDistance))
        let secondSample = try #require(
            RailwayCorridorChainAssembler.reversedRoute(second.route).sample(
                atDistance: second.route.totalLength / 2
            )
        )
        #expect(abs(joinedSample.coordinate.latitude - secondSample.coordinate.latitude) < 0.000_001)
        #expect(abs(joinedSample.coordinate.longitude - secondSample.coordinate.longitude) < 0.000_001)
    }

    @Test("Two matching endpoint services merge atomically without buying assets")
    func destructiveMergePreservesAssetsAndPrimaryIdentity() async throws {
        let session = makeSession()
        await buildLine(in: session, from: purley, to: eastCroydon)
        await buildLine(in: session, from: eastCroydon, to: horley)
        let primary = session.lines[0]
        let candidate = session.lines[1]
        let primaryTrainIDs = primary.trains.map(\.id)
        let candidateTrainIDs = Set(candidate.trains.map(\.id))
        let financeLedger = session.financeLedger
        let networkValue = session.financeSnapshot.networkValuePence
        let corridorIDs = session.corridors.map(\.id)
        #expect(session.publicBetaFacts.completedLineCount == 2)

        let option = try #require(session.throughServiceOptions(forLineID: primary.id).first)
        #expect(option.candidateLineID == candidate.id)
        #expect(option.originName == "Purley")
        #expect(option.junctionName == "East Croydon")
        #expect(option.destinationName == "Horley")
        #expect(option.stationCRSs == ["PUR", "ECR", "HOR"])
        #expect(option.stationNames == ["Purley", "East Croydon", "Horley"])
        #expect(option.stationNames.count == option.stationCRSs.count)
        #expect(option.resultingOwnedTrainCount == 4)
        #expect(option.automaticChanges.isEmpty)
        #expect(option.capitalQuote == .zero)
        #expect(option.canAfford)
        #expect(option.fundingShortfallPence == 0)

        #expect(session.joinThroughService(primaryLineID: primary.id, withLineID: candidate.id))

        let joined = try #require(session.lines.first)
        #expect(session.lines.count == 1)
        #expect(session.corridors.map(\.id) == corridorIDs)
        #expect(joined.id == primary.id)
        #expect(joined.styleIndex == primary.styleIndex)
        #expect(joined.corridorIDs == corridorIDs)
        #expect(joined.stationCRSs == ["PUR", "ECR", "HOR"])
        #expect(joined.origin.crs == "PUR")
        #expect(joined.destination.crs == "HOR")
        #expect(joined.trains.map(\.id) == primaryTrainIDs)
        #expect(candidateTrainIDs.isDisjoint(with: joined.trains.map(\.id)))
        #expect(joined.ownedTrainCount == 4)
        #expect(session.financeLedger == financeLedger)
        #expect(session.financeSnapshot.networkValuePence == networkValue)
        #expect(session.publicBetaFacts.completedLineCount == 2)
        #expect(!session.canEditStops(forLineID: joined.id))
        #expect(!session.canUpgradeTrack(forLineID: joined.id))
        #expect(session.passengerSnapshot.connectingJourneySnapshots.isEmpty)
        #expect(session.passengerSnapshot.line(for: joined.id)?.stationCRSs == ["PUR", "ECR", "HOR"])
        #expect(session.passengerSnapshot.serviceMarketSnapshots.contains { market in
            market.originCRS == "PUR"
                && market.destinationCRS == "HOR"
                && market.directPassengersPerDay > 0
        })
    }

    @Test("A joined through service supports independent local and express terminals")
    func joinedServiceSupportsCustomStoppingPlans() async throws {
        let session = makeSession()
        await buildLine(in: session, from: purley, to: eastCroydon)
        await buildLine(in: session, from: eastCroydon, to: horley)
        let primaryID = session.lines[0].id
        let candidateID = session.lines[1].id
        #expect(session.joinThroughService(
            primaryLineID: primaryID,
            withLineID: candidateID
        ))

        let joined = try #require(session.lines.first)
        #expect(joined.stationCRSs == ["PUR", "ECR", "HOR"])
        #expect(joined.trains.count == 2)
        #expect(session.canCustomizeServicePlan(for: joined.trains[0].id))
        let financeBefore = session.financeLedger
        #expect(session.setTrainServicePlan(
            TrainServicePlan(
                slotIndex: 0,
                role: .local,
                stationCRSs: ["PUR", "ECR"]
            ),
            forTrainID: joined.trains[0].id
        ))
        #expect(session.setTrainServicePlan(
            TrainServicePlan(
                slotIndex: 1,
                role: .express,
                stationCRSs: ["ECR", "HOR"]
            ),
            forTrainID: joined.trains[1].id
        ))

        #expect(session.financeLedger == financeBefore)
        #expect(session.hasCustomServicePlans(forLineID: joined.id))
        let markets = Set(
            session.passengerSnapshot.serviceMarketSnapshots
                .filter { $0.serviceID == joined.id }
                .map { "\($0.originCRS)-\($0.destinationCRS)" }
        )
        #expect(markets == Set(["PUR-ECR", "ECR-HOR"]))
        #expect(!markets.contains("PUR-HOR"))
        #expect(session.passengerSnapshot.connectingJourneySnapshots.contains { journey in
            journey.originCRS == "HOR"
                && journey.interchangeCRS == "ECR"
                && journey.destinationCRS == "PUR"
                && journey.passengersPerDay > 0
        } || session.passengerSnapshot.connectingJourneySnapshots.contains { journey in
            journey.originCRS == "PUR"
                && journey.interchangeCRS == "ECR"
                && journey.destinationCRS == "HOR"
                && journey.passengersPerDay > 0
        })
    }

    @Test("Service directions do not affect the outer-terminal through route")
    func reversedSourceServicesJoinInPhysicalOrder() async throws {
        let session = makeSession()
        await buildLine(in: session, from: eastCroydon, to: purley)
        await buildLine(in: session, from: horley, to: eastCroydon)
        let primary = session.lines[0]
        let candidate = session.lines[1]
        let primaryTrainIDs = primary.trains.map(\.id)

        let option = try #require(session.throughServiceOptions(forLineID: primary.id).first)
        #expect(option.stationCRSs == ["PUR", "ECR", "HOR"])
        #expect(session.joinThroughService(primaryLineID: primary.id, withLineID: candidate.id))

        let joined = try #require(session.lines.first)
        #expect(joined.stationCRSs == ["PUR", "ECR", "HOR"])
        #expect(joined.route.stationCoordinateIndices.count == 3)
        #expect(joined.trains.map(\.id) == primaryTrainIDs)
        #expect(joined.trains.allSatisfy { $0.distanceAlongRoute.isFinite })
    }

    @Test("Disconnected services stay excluded while operating mismatches are reconcilable")
    func operatingMismatchesAreOffered() async throws {
        let session = makeSession(stations: [purley, eastCroydon, horley, redhill])
        await buildLine(in: session, from: purley, to: eastCroydon)
        await buildLine(in: session, from: horley, to: redhill)
        let primaryID = try #require(session.lines.first?.id)
        #expect(session.throughServiceOptions(forLineID: primaryID).isEmpty)

        let matching = makeSession()
        await buildLine(in: matching, from: purley, to: eastCroydon)
        await buildLine(in: matching, from: eastCroydon, to: horley)
        let matchingPrimaryID = matching.lines[0].id
        let candidateID = matching.lines[1].id
        matching.setServiceFrequency(.hourly, forLineID: candidateID)

        let option = try #require(
            matching.throughServiceOptions(forLineID: matchingPrimaryID).first
        )
        #expect(option.frequency == .halfHourly)
        #expect(option.candidateFrequency == .hourly)
        #expect(option.capitalQuote == .zero)
        #expect(option.automaticChanges == [
            .serviceFrequency(
                lineID: candidateID,
                lineNumber: 2,
                from: .hourly,
                to: .halfHourly
            ),
        ])
        #expect(matching.joinThroughService(
            primaryLineID: matchingPrimaryID,
            withLineID: candidateID
        ))
        #expect(matching.lines.count == 1)
        #expect(matching.corridors.count == 2)
        #expect(matching.lines[0].serviceFrequency == .halfHourly)
    }

    @Test("Join quote itemises free operating changes and paid upward asset reconciliation")
    func automaticReconciliationQuoteAndCommit() async throws {
        let session = makeSession()
        await buildLine(
            in: session,
            from: purley,
            to: eastCroydon,
            formation: .fourCar
        )
        await buildLine(
            in: session,
            from: eastCroydon,
            to: horley,
            formation: .eightCar
        )
        let primaryID = session.lines[0].id
        let candidateID = session.lines[1].id
        session.setServiceFrequency(.quarterHourly, forLineID: primaryID)
        session.setServiceFrequency(.hourly, forLineID: candidateID)
        session.setServicePattern(.local, forLineID: primaryID)
        session.setServicePattern(.express, forLineID: candidateID)
        #expect(session.upgradeTrackCapacity(forLineID: candidateID))
        #expect(session.upgradeTrackCapacity(forLineID: candidateID))

        let ledgerBeforeJoin = session.financeLedger
        let option = try #require(session.throughServiceOptions(forLineID: primaryID).first)
        #expect(session.throughServiceIncompatibilities(forLineID: primaryID).isEmpty)
        #expect(option.frequency == .quarterHourly)
        #expect(option.servicePattern == .local)
        #expect(option.formation == .eightCar)
        #expect(option.trackCapacity == .doubleTrack)
        #expect(option.primaryFormation == .fourCar)
        #expect(option.candidateFormation == .eightCar)
        #expect(option.primaryTrackCapacity == .singleTrack)
        #expect(option.candidateTrackCapacity == .doubleTrack)
        #expect(option.capitalQuote.rollingStockPence > 0)
        #expect(option.capitalQuote.trackAndInfrastructurePence > 0)
        #expect(option.capitalQuote.totalPence > 0)
        #expect(option.canAfford)
        #expect(option.fundingShortfallPence == 0)
        let primaryCorridor = try #require(
            session.corridors.first { $0.id == session.lines[0].corridorIDs[0] }
        )
        let expectedTrackCost = (TrainOperations().upgradeCostPence(
            from: .singleTrack,
            constructionCostPounds: primaryCorridor.indicativeCost
        ) ?? 0) + (TrainOperations().upgradeCostPence(
            from: .passingLoop,
            constructionCostPounds: primaryCorridor.indicativeCost
        ) ?? 0)
        #expect(option.capitalQuote.trackAndInfrastructurePence == expectedTrackCost)
        let fourToSix = try #require(CapitalEconomy().quoteForFormationExtension(
            ownedTrainCount: 4,
            currentFormation: .fourCar
        ))
        let sixToEight = try #require(CapitalEconomy().quoteForFormationExtension(
            ownedTrainCount: 4,
            currentFormation: .sixCar
        ))
        #expect(
            option.capitalQuote.rollingStockPence
                == fourToSix.totalCostPence + sixToEight.totalCostPence
        )
        #expect(option.automaticChanges.count == 4)
        #expect(option.automaticChanges.contains {
            guard case let .serviceFrequency(
                lineID: id,
                lineNumber: number,
                from: oldFrequency,
                to: newFrequency
            ) = $0 else { return false }
            return id == candidateID
                && number == 2
                && oldFrequency == .hourly
                && newFrequency == .quarterHourly
        })
        #expect(option.automaticChanges.contains {
            guard case let .servicePattern(
                lineID: id,
                lineNumber: number,
                from: oldPattern,
                to: newPattern
            ) = $0 else { return false }
            return id == candidateID
                && number == 2
                && oldPattern == .express
                && newPattern == .local
        })
        #expect(option.automaticChanges.contains {
            guard case let .formation(
                lineID: id,
                lineNumber: 1,
                ownedTrainCount: owned,
                from: .fourCar,
                to: .eightCar,
                costPence: cost
            ) = $0 else { return false }
            return id == primaryID && owned == 4 && cost == option.capitalQuote.rollingStockPence
        })
        #expect(option.automaticChanges.contains {
            guard case let .trackCapacity(
                lineID: id,
                lineNumber: 1,
                corridorID: _,
                segmentName: _,
                from: .singleTrack,
                to: .doubleTrack,
                costPence: cost
            ) = $0 else { return false }
            return id == primaryID && cost == option.capitalQuote.trackAndInfrastructurePence
        })

        #expect(session.joinThroughService(
            primaryLineID: primaryID,
            withLineID: candidateID
        ))
        let joined = try #require(session.lines.first)
        #expect(joined.serviceFrequency == .quarterHourly)
        #expect(joined.servicePattern == .local)
        #expect(joined.formation == .eightCar)
        #expect(joined.trackCapacity == .doubleTrack)
        #expect(session.corridors.allSatisfy { $0.trackCapacity == .doubleTrack })
        #expect(
            session.financeLedger.lifetimeRollingStockSpendPence
                - ledgerBeforeJoin.lifetimeRollingStockSpendPence
                == option.capitalQuote.rollingStockPence
        )
        #expect(
            session.financeLedger.lifetimeConstructionSpendPence
                - ledgerBeforeJoin.lifetimeConstructionSpendPence
                == option.capitalQuote.constructionPence
        )
    }

    @Test("Cached topology still respects transient build-phase eligibility")
    func availabilityCacheRespectsPhase() async throws {
        let session = makeSession()
        await buildLine(in: session, from: purley, to: eastCroydon)
        await buildLine(in: session, from: eastCroydon, to: horley)
        let primaryID = session.lines[0].id
        let revision = session.persistenceRevision

        #expect(session.throughServiceAvailability(forLineID: primaryID).options.count == 1)
        session.startBuilding()
        #expect(session.persistenceRevision == revision)
        #expect(session.throughServiceAvailability(forLineID: primaryID).options.isEmpty)
        session.cancelBuild()
        #expect(session.persistenceRevision == revision)
        #expect(session.throughServiceAvailability(forLineID: primaryID).options.count == 1)
    }

    @Test("An unaffordable Career reconciliation leaves services, corridors and ledger unchanged")
    func careerInsufficientFundsIsAtomic() async throws {
        let session = makeSession(
            stations: [purley, eastCroydon, horley, redhill],
            capitalEconomy: lowCashCapitalEconomy,
            trainOperations: lowCostTrainOperations,
            gameMode: .career,
            indicativeCostPerKilometre: 0
        )
        await buildLine(in: session, from: purley, to: eastCroydon)
        await buildLine(in: session, from: eastCroydon, to: horley)
        await buildLine(in: session, from: horley, to: redhill)
        let primaryID = session.lines[0].id
        let firstCandidateID = session.lines[1].id
        let finalCandidateID = session.lines[2].id
        #expect(session.upgradeTrackCapacity(forLineID: finalCandidateID))
        #expect(session.financeLedger.cashBalancePence == 50)
        #expect(session.joinThroughService(
            primaryLineID: primaryID,
            withLineID: firstCandidateID
        ))

        let option = try #require(
            session.throughServiceOptions(forLineID: primaryID).first {
                $0.candidateLineID == finalCandidateID
            }
        )
        #expect(option.primaryCorridorCount == 2)
        #expect(option.capitalQuote.trackAndInfrastructurePence == 200)
        #expect(option.capitalQuote.rollingStockPence == 0)
        #expect(!option.canAfford)
        #expect(option.fundingShortfallPence == 150)
        let before = session.makeSaveSnapshot()

        #expect(!session.joinThroughService(
            primaryLineID: primaryID,
            withLineID: finalCandidateID
        ))
        let after = session.makeSaveSnapshot()
        #expect(after.lines == before.lines)
        #expect(after.corridors == before.corridors)
        #expect(after.financialState == before.financialState)
    }

    @Test("An affordable Career reconciliation charges exactly the quoted investment")
    func careerAutomaticReconciliationChargesExactQuote() async throws {
        let session = makeSession(
            gameMode: .career,
            indicativeCostPerKilometre: 0
        )
        await buildLine(
            in: session,
            from: purley,
            to: eastCroydon,
            formation: .fourCar
        )
        await buildLine(
            in: session,
            from: eastCroydon,
            to: horley,
            formation: .eightCar
        )
        let primaryID = session.lines[0].id
        let candidateID = session.lines[1].id
        #expect(session.upgradeTrackCapacity(forLineID: candidateID))

        let option = try #require(session.throughServiceOptions(forLineID: primaryID).first)
        #expect(option.canAfford)
        #expect(option.capitalQuote.rollingStockPence > 0)
        #expect(option.capitalQuote.trackAndInfrastructurePence > 0)
        let ledgerBeforeJoin = session.financeLedger
        let networkValueBeforeJoin = session.financeSnapshot.networkValuePence

        #expect(session.joinThroughService(
            primaryLineID: primaryID,
            withLineID: candidateID
        ))
        #expect(
            ledgerBeforeJoin.cashBalancePence - session.financeLedger.cashBalancePence
                == option.capitalQuote.totalPence
        )
        #expect(
            session.financeLedger.lifetimeRollingStockSpendPence
                - ledgerBeforeJoin.lifetimeRollingStockSpendPence
                == option.capitalQuote.rollingStockPence
        )
        #expect(
            session.financeLedger.lifetimeConstructionSpendPence
                - ledgerBeforeJoin.lifetimeConstructionSpendPence
                == option.capitalQuote.constructionPence
        )
        #expect(
            session.financeSnapshot.networkValuePence - networkValueBeforeJoin
                == option.capitalQuote.totalPence
        )
    }

    @Test("Confirmation discards a stale zero-cost preview and requotes current assets")
    func confirmationRevalidatesQuote() async throws {
        let session = makeSession(stations: [purley, eastCroydon, horley, redhill])
        await buildLine(
            in: session,
            from: purley,
            to: eastCroydon,
            formation: .fourCar
        )
        await buildLine(
            in: session,
            from: eastCroydon,
            to: horley,
            formation: .fourCar
        )
        await buildLine(
            in: session,
            from: horley,
            to: redhill,
            formation: .fourCar
        )
        let primaryID = session.lines[0].id
        let firstCandidateID = session.lines[1].id
        let finalCandidateID = session.lines[2].id
        #expect(session.joinThroughService(
            primaryLineID: primaryID,
            withLineID: firstCandidateID
        ))
        let staleOption = try #require(
            session.throughServiceOptions(forLineID: primaryID).first {
                $0.candidateLineID == finalCandidateID
            }
        )
        #expect(staleOption.primaryCorridorCount == 2)
        #expect(staleOption.capitalQuote == .zero)

        #expect(session.extendFormation(forLineID: finalCandidateID))
        #expect(session.extendFormation(forLineID: finalCandidateID))
        let ledgerBeforeJoin = session.financeLedger
        #expect(session.joinThroughService(
            primaryLineID: staleOption.primaryLineID,
            withLineID: staleOption.candidateLineID
        ))

        let joined = try #require(session.lines.first)
        #expect(joined.formation == .eightCar)
        #expect(
            session.financeLedger.lifetimeRollingStockSpendPence
                > ledgerBeforeJoin.lifetimeRollingStockSpendPence
        )
    }

    @Test("A stronger primary fleet and corridor are retained without any asset downgrade")
    func strongerPrimaryAssetsAreRetained() async throws {
        let session = makeSession()
        await buildLine(
            in: session,
            from: purley,
            to: eastCroydon,
            formation: .tenCar
        )
        await buildLine(
            in: session,
            from: eastCroydon,
            to: horley,
            formation: .twoCar
        )
        let primaryID = session.lines[0].id
        let candidateID = session.lines[1].id
        #expect(session.upgradeTrackCapacity(forLineID: primaryID))

        let option = try #require(session.throughServiceOptions(forLineID: primaryID).first)
        #expect(option.formation == .tenCar)
        #expect(option.trackCapacity == .passingLoop)
        #expect(option.automaticChanges.contains {
            guard case let .formation(
                lineID: id,
                lineNumber: _,
                ownedTrainCount: _,
                from: oldFormation,
                to: newFormation,
                costPence: cost
            ) = $0 else { return false }
            return id == candidateID
                && oldFormation == .twoCar
                && newFormation == .tenCar
                && cost > 0
        })
        #expect(option.automaticChanges.contains {
            guard case let .trackCapacity(
                lineID: id,
                lineNumber: _,
                corridorID: _,
                segmentName: _,
                from: oldCapacity,
                to: newCapacity,
                costPence: cost
            ) = $0 else { return false }
            return id == candidateID
                && oldCapacity == .singleTrack
                && newCapacity == .passingLoop
                && cost > 0
        })

        #expect(session.joinThroughService(
            primaryLineID: primaryID,
            withLineID: candidateID
        ))
        #expect(session.lines[0].formation == .tenCar)
        #expect(session.lines[0].trackCapacity == .passingLoop)
        #expect(session.corridors.allSatisfy { $0.trackCapacity == .passingLoop })
    }

    @Test("A joined service extends to three corridors and expands untouched fleet presets")
    func joinedServiceExtendsAcrossThreeCorridors() async throws {
        let session = makeSession(stations: [purley, eastCroydon, horley, redhill])
        await buildLine(in: session, from: purley, to: eastCroydon)
        await buildLine(in: session, from: eastCroydon, to: horley)
        await buildLine(in: session, from: horley, to: redhill)

        let primaryID = session.lines[0].id
        let firstCandidateID = session.lines[1].id
        let finalCandidateID = session.lines[2].id
        let originalCorridorIDs = session.lines.map(\.corridorID)
        let retainedTrainIDs = session.lines[0].trains.map(\.id)
        let discardedTrainIDs = Set(
            session.lines[1].trains.map(\.id) + session.lines[2].trains.map(\.id)
        )
        #expect(session.joinThroughService(
            primaryLineID: primaryID,
            withLineID: firstCandidateID
        ))

        let extensionOption = try #require(
            session.throughServiceOptions(forLineID: primaryID).first {
                $0.candidateLineID == finalCandidateID
            }
        )
        #expect(extensionOption.primaryCorridorCount == 2)
        #expect(extensionOption.candidateCorridorCount == 1)
        #expect(extensionOption.resultingCorridorCount == 3)
        #expect(extensionOption.stationCRSs == ["PUR", "ECR", "HOR", "RDH"])
        #expect(!extensionOption.preservesPrimaryCustomServicePlans)
        #expect(extensionOption.resultingOwnedTrainCount == 6)

        #expect(session.joinThroughService(
            primaryLineID: primaryID,
            withLineID: finalCandidateID
        ))

        let joined = try #require(session.lines.first)
        #expect(session.lines.count == 1)
        #expect(session.corridors.count == 3)
        #expect(joined.id == primaryID)
        #expect(joined.corridorIDs == originalCorridorIDs)
        #expect(joined.stationCRSs == ["PUR", "ECR", "HOR", "RDH"])
        #expect(joined.origin.crs == "PUR")
        #expect(joined.destination.crs == "RDH")
        #expect(joined.ownedTrainCount == 6)
        #expect(joined.trains.map(\.id) == retainedTrainIDs)
        #expect(discardedTrainIDs.isDisjoint(with: joined.trains.map(\.id)))
        #expect(joined.trainServicePlans == TrainServicePlan.legacyDefaults(
            servicePattern: joined.servicePattern,
            serviceStationCRSs: joined.stationCRSs
        ))
        #expect(joined.trains.allSatisfy {
            $0.distanceAlongRoute.isFinite
                && $0.distanceAlongRoute >= 0
                && $0.distanceAlongRoute <= joined.route.totalLength
        })
        #expect(session.publicBetaFacts.completedLineCount == 3)
    }

    @Test("Extending at the origin reverses the complete retained corridor chain")
    func multiCorridorExtensionAtOriginReversesWholeChain() async throws {
        let session = makeSession(stations: [purley, eastCroydon, horley, redhill])
        await buildLine(in: session, from: eastCroydon, to: horley)
        await buildLine(in: session, from: horley, to: redhill)
        await buildLine(in: session, from: purley, to: eastCroydon)

        let primaryID = session.lines[0].id
        let middleCorridorID = session.lines[0].corridorID
        let outerCorridorID = session.lines[1].corridorID
        let candidateID = session.lines[2].id
        let candidateCorridorID = session.lines[2].corridorID
        #expect(session.joinThroughService(
            primaryLineID: primaryID,
            withLineID: session.lines[1].id
        ))
        let retainedTrains = try #require(
            session.lines.first { $0.id == primaryID }
        ).trains

        let option = try #require(
            session.throughServiceOptions(forLineID: primaryID).first {
                $0.candidateLineID == candidateID
            }
        )
        #expect(option.stationCRSs == ["RDH", "HOR", "ECR", "PUR"])
        #expect(session.joinThroughService(
            primaryLineID: primaryID,
            withLineID: candidateID
        ))

        let joined = try #require(session.lines.first)
        #expect(joined.corridorIDs == [
            outerCorridorID,
            middleCorridorID,
            candidateCorridorID,
        ])
        #expect(joined.stationCRSs == ["RDH", "HOR", "ECR", "PUR"])
        #expect(joined.trains.map(\.id) == retainedTrains.map(\.id))
        for oldTrain in retainedTrains {
            let newTrain = try #require(joined.trains.first { $0.id == oldTrain.id })
            #expect(newTrain.direction != oldTrain.direction)
            #expect(newTrain.distanceAlongRoute.isFinite)
            #expect((0...joined.route.totalLength).contains(newTrain.distanceAlongRoute))
        }
    }

    @Test("A custom primary timetable survives another through-service extension")
    func customPrimaryPlansSurviveExtension() async throws {
        let session = makeSession(stations: [purley, eastCroydon, horley, redhill])
        await buildLine(in: session, from: purley, to: eastCroydon)
        await buildLine(in: session, from: eastCroydon, to: horley)
        await buildLine(in: session, from: horley, to: redhill)
        let primaryID = session.lines[0].id
        #expect(session.joinThroughService(
            primaryLineID: primaryID,
            withLineID: session.lines[1].id
        ))
        let joined = try #require(session.lines.first { $0.id == primaryID })
        #expect(session.setTrainServicePlan(
            TrainServicePlan(
                slotIndex: 0,
                role: .local,
                stationCRSs: ["PUR", "ECR"]
            ),
            forTrainID: joined.trains[0].id
        ))
        #expect(session.setTrainServicePlan(
            TrainServicePlan(
                slotIndex: 1,
                role: .express,
                stationCRSs: ["ECR", "HOR"]
            ),
            forTrainID: joined.trains[1].id
        ))
        let customPlans = try #require(
            session.lines.first { $0.id == primaryID }
        ).trainServicePlans
        let financeBefore = session.financeLedger
        let candidateID = try #require(session.lines.first { $0.id != primaryID }).id

        let option = try #require(
            session.throughServiceOptions(forLineID: primaryID).first {
                $0.candidateLineID == candidateID
            }
        )
        #expect(option.preservesPrimaryCustomServicePlans)
        #expect(session.joinThroughService(
            primaryLineID: primaryID,
            withLineID: candidateID
        ))

        let extended = try #require(session.lines.first)
        #expect(extended.stationCRSs == ["PUR", "ECR", "HOR", "RDH"])
        #expect(extended.trainServicePlans == customPlans)
        #expect(session.financeLedger == financeBefore)
    }

    @Test("Two existing through services combine into one durable four-corridor chain")
    func throughServicesCombineAndPersist() async throws {
        let catalog = [purley, eastCroydon, horley, redhill, reigate]
        let session = makeSession(stations: catalog)
        await buildLine(in: session, from: purley, to: eastCroydon)
        await buildLine(in: session, from: eastCroydon, to: horley)
        await buildLine(in: session, from: horley, to: redhill)
        await buildLine(in: session, from: redhill, to: reigate)

        let sourceLines = session.lines
        let expectedCorridorIDs = sourceLines.map(\.corridorID)
        let leftID = sourceLines[0].id
        let rightID = sourceLines[2].id
        let retainedTrainIDs = sourceLines[0].trains.map(\.id)
        let discardedTrainIDs = Set(
            sourceLines[1].trains.map(\.id)
                + sourceLines[2].trains.map(\.id)
                + sourceLines[3].trains.map(\.id)
        )

        #expect(session.joinThroughService(
            primaryLineID: leftID,
            withLineID: sourceLines[1].id
        ))
        #expect(session.joinThroughService(
            primaryLineID: rightID,
            withLineID: sourceLines[3].id
        ))
        let option = try #require(
            session.throughServiceOptions(forLineID: leftID).first {
                $0.candidateLineID == rightID
            }
        )
        #expect(option.primaryCorridorCount == 2)
        #expect(option.candidateCorridorCount == 2)
        #expect(option.resultingCorridorCount == 4)
        #expect(option.stationCRSs == ["PUR", "ECR", "HOR", "RDH", "REI"])
        #expect(option.resultingOwnedTrainCount == 8)
        #expect(option.activeTrainCount == 2)
        #expect(session.joinThroughService(primaryLineID: leftID, withLineID: rightID))

        let combined = try #require(session.lines.first)
        #expect(combined.corridorIDs == expectedCorridorIDs)
        #expect(combined.stationCRSs == ["PUR", "ECR", "HOR", "RDH", "REI"])
        #expect(combined.trains.map(\.id) == retainedTrainIDs)
        #expect(discardedTrainIDs.isDisjoint(with: combined.trains.map(\.id)))
        #expect(combined.ownedTrainCount == 8)
        #expect(session.corridors.count == 4)
        #expect(session.publicBetaFacts.completedLineCount == 4)

        let saveURL = temporarySaveURL()
        defer { try? FileManager.default.removeItem(at: saveURL.deletingLastPathComponent()) }
        let store = GameSaveStore(fileURL: saveURL)
        try await store.save(session.makeSaveSnapshot())
        let loaded = try #require(try await store.load())
        #expect(loaded.lines[0].corridorIDs == expectedCorridorIDs)

        let restored = makeSession(stations: catalog)
        try await restored.restore(from: loaded)
        let restoredLine = try #require(restored.lines.first)
        #expect(restoredLine.id == leftID)
        #expect(restoredLine.corridorIDs == expectedCorridorIDs)
        #expect(restoredLine.stationCRSs == ["PUR", "ECR", "HOR", "RDH", "REI"])
        #expect(restoredLine.ownedTrainCount == 8)
        #expect(restoredLine.trains.map(\.id) == retainedTrainIDs)
        #expect(restoredLine.route.stationCoordinateIndices.count == 5)
        #expect(restoredLine.trains.allSatisfy {
            $0.distanceAlongRoute.isFinite
                && (0...restoredLine.route.totalLength).contains($0.distanceAlongRoute)
        })
    }

    @Test("A chained join quotes and charges every weak corridor and fleet exactly once")
    func chainedJoinReconcilesEveryAssetExactlyOnce() async throws {
        let capitalEconomy = testCapitalEconomy(startingCashPence: 1_000_000)
        let trainOperations = lowCostTrainOperations
        let session = makeSession(
            stations: [purley, eastCroydon, horley, redhill, reigate],
            capitalEconomy: capitalEconomy,
            trainOperations: trainOperations,
            gameMode: .career,
            indicativeCostPerKilometre: 0
        )
        await buildLine(
            in: session,
            from: purley,
            to: eastCroydon,
            formation: .fourCar
        )
        await buildLine(
            in: session,
            from: eastCroydon,
            to: horley,
            formation: .fourCar
        )
        await buildLine(
            in: session,
            from: horley,
            to: redhill,
            formation: .eightCar
        )
        await buildLine(
            in: session,
            from: redhill,
            to: reigate,
            formation: .eightCar
        )
        let sourceLines = session.lines
        let leftID = sourceLines[0].id
        let rightID = sourceLines[2].id
        for lineID in [sourceLines[2].id, sourceLines[3].id] {
            #expect(session.upgradeTrackCapacity(forLineID: lineID))
            #expect(session.upgradeTrackCapacity(forLineID: lineID))
        }
        #expect(session.joinThroughService(
            primaryLineID: leftID,
            withLineID: sourceLines[1].id
        ))
        #expect(session.joinThroughService(
            primaryLineID: rightID,
            withLineID: sourceLines[3].id
        ))

        let weakCorridorIDs = Set(
            try #require(session.lines.first { $0.id == leftID }).corridorIDs
        )
        let expectedTrackCostPerCorridor = try #require(
            trainOperations.upgradeCostPence(
                from: .singleTrack,
                constructionCostPounds: 0
            )
        ) + (trainOperations.upgradeCostPence(
            from: .passingLoop,
            constructionCostPounds: 0
        ) ?? 0)
        let fourToSix = try #require(capitalEconomy.quoteForFormationExtension(
            ownedTrainCount: 4,
            currentFormation: .fourCar
        ))
        let sixToEight = try #require(capitalEconomy.quoteForFormationExtension(
            ownedTrainCount: 4,
            currentFormation: .sixCar
        ))
        let expectedRollingStockCost = fourToSix.totalCostPence
            + sixToEight.totalCostPence

        let option = try #require(
            session.throughServiceOptions(forLineID: leftID).first {
                $0.candidateLineID == rightID
            }
        )
        #expect(option.formation == .eightCar)
        #expect(option.trackCapacity == .doubleTrack)
        #expect(
            option.capitalQuote.trackAndInfrastructurePence
                == expectedTrackCostPerCorridor * 2
        )
        #expect(option.capitalQuote.rollingStockPence == expectedRollingStockCost)
        let trackChanges = option.automaticChanges.compactMap { change -> (
            corridorID: UUID,
            segmentName: String,
            cost: Int64
        )? in
            guard case let .trackCapacity(
                lineID: id,
                lineNumber: _,
                corridorID: corridorID,
                segmentName: segmentName,
                from: .singleTrack,
                to: .doubleTrack,
                costPence: cost
            ) = change, id == leftID else { return nil }
            return (corridorID, segmentName, cost)
        }
        #expect(trackChanges.count == 2)
        #expect(Set(trackChanges.map { $0.corridorID }) == weakCorridorIDs)
        #expect(trackChanges.allSatisfy {
            !$0.segmentName.isEmpty && $0.cost == expectedTrackCostPerCorridor
        })
        #expect(option.automaticChanges.filter { change in
            guard case let .formation(
                lineID: id,
                lineNumber: _,
                ownedTrainCount: 4,
                from: .fourCar,
                to: .eightCar,
                costPence: cost
            ) = change else { return false }
            return id == leftID && cost == expectedRollingStockCost
        }.count == 1)

        let ledgerBefore = session.financeLedger
        #expect(session.joinThroughService(primaryLineID: leftID, withLineID: rightID))
        let combined = try #require(session.lines.first)
        #expect(combined.formation == .eightCar)
        #expect(combined.trackCapacity == .doubleTrack)
        #expect(combined.ownedTrainCount == 8)
        #expect(session.corridors.allSatisfy { $0.trackCapacity == .doubleTrack })
        #expect(
            ledgerBefore.cashBalancePence - session.financeLedger.cashBalancePence
                == option.capitalQuote.totalPence
        )
        #expect(
            session.financeLedger.lifetimeConstructionSpendPence
                - ledgerBefore.lifetimeConstructionSpendPence
                == option.capitalQuote.trackAndInfrastructurePence
        )
        #expect(
            session.financeLedger.lifetimeRollingStockSpendPence
                - ledgerBefore.lifetimeRollingStockSpendPence
                == option.capitalQuote.rollingStockPence
        )
    }

    @Test("Incomplete construction and high-speed infrastructure remain structural blockers")
    func nonEconomicStructuralBlockersRemainExplicit() async throws {
        let clock = M15ManualClock()
        let incomplete = makeSession(
            clock: clock,
            constructionDuration: 1
        )
        incomplete.startBuilding()
        incomplete.selectStation(purley)
        incomplete.selectStation(eastCroydon)
        await incomplete.waitForRouteCalculation()
        incomplete.confirmPreview()
        #expect(incomplete.phase == .constructing)
        clock.advance(by: 1)
        #expect(incomplete.phase == .operating)
        let completedID = try #require(incomplete.lines.first?.id)

        incomplete.startBuilding()
        incomplete.selectStation(eastCroydon)
        incomplete.selectStation(horley)
        await incomplete.waitForRouteCalculation()
        incomplete.confirmPreview()
        #expect(incomplete.phase == .constructing)
        #expect(incomplete.throughServiceIncompatibilities(
            forLineID: completedID
        ).contains { $0.reasons.contains(.incompleteConstruction) })

        let mixedClass = makeSession()
        await buildLine(
            in: mixedClass,
            from: purley,
            to: eastCroydon,
            railwayClass: .highSpeed
        )
        await buildLine(in: mixedClass, from: eastCroydon, to: horley)
        let highSpeedID = mixedClass.lines[0].id
        #expect(mixedClass.throughServiceOptions(forLineID: highSpeedID).isEmpty)
        #expect(mixedClass.throughServiceIncompatibilities(
            forLineID: highSpeedID
        ).contains { $0.reasons.contains(.conventionalServicesOnly) })
    }

    @Test("Overlapping, looping and duplicate outer routes remain blocked")
    func overlappingAndDuplicateRoutesRemainBlocked() async throws {
        let loop = makeSession()
        await buildLine(in: loop, from: purley, to: eastCroydon)
        await buildLine(in: loop, from: eastCroydon, to: horley)
        let loopPrimaryID = loop.lines[0].id
        #expect(loop.joinThroughService(
            primaryLineID: loopPrimaryID,
            withLineID: loop.lines[1].id
        ))
        await buildLine(in: loop, from: horley, to: eastCroydon)
        let overlapID = try #require(loop.lines.first { $0.id != loopPrimaryID }).id
        #expect(loop.throughServiceOptions(forLineID: loopPrimaryID).isEmpty)
        #expect(loop.throughServiceIncompatibilities(
            forLineID: loopPrimaryID
        ).contains {
            $0.candidateLineID == overlapID
                && $0.reasons.contains(.overlappingOrBranchedRoute)
        })

        let duplicate = makeSession()
        await buildLine(in: duplicate, from: purley, to: eastCroydon)
        await buildLine(in: duplicate, from: eastCroydon, to: horley)
        await buildLine(in: duplicate, from: purley, to: horley)
        let firstID = duplicate.lines[0].id
        let secondID = duplicate.lines[1].id
        #expect(duplicate.throughServiceOptions(forLineID: firstID).allSatisfy {
            $0.candidateLineID != secondID
        })
        #expect(duplicate.throughServiceIncompatibilities(
            forLineID: firstID
        ).contains {
            $0.candidateLineID == secondID
                && $0.reasons.contains(.overlappingOrBranchedRoute)
        })
    }

    @Test("The configured calling-point bound still blocks an oversized chain")
    func chainedJoinRespectsCallingPointBound() async throws {
        let session = makeSession(
            stations: [purley, eastCroydon, horley, redhill, reigate],
            maximumServiceCallCount: 3
        )
        await buildLine(in: session, from: purley, to: eastCroydon)
        await buildLine(in: session, from: eastCroydon, to: horley)
        await buildLine(in: session, from: horley, to: redhill)
        await buildLine(in: session, from: redhill, to: reigate)
        let source = session.lines
        #expect(session.joinThroughService(
            primaryLineID: source[0].id,
            withLineID: source[1].id
        ))
        #expect(session.joinThroughService(
            primaryLineID: source[2].id,
            withLineID: source[3].id
        ))

        #expect(session.throughServiceOptions(forLineID: source[0].id).isEmpty)
        #expect(session.throughServiceIncompatibilities(
            forLineID: source[0].id
        ).contains {
            $0.candidateLineID == source[2].id
                && $0.reasons.contains(.serviceLimitExceeded)
        })
    }

    @Test("The durable owned-fleet bound cannot be bypassed by repeated joins")
    func chainedJoinRespectsOwnedFleetBound() async throws {
        let stations = (0...13).map { index in
            Station(
                crs: String(format: "S%02d", index),
                name: "Station \(index)",
                latitude: 51 + Double(index) * 0.001,
                longitude: -0.1
            )
        }
        let session = makeSession(
            stations: stations,
            indicativeCostPerKilometre: 0,
            maximumServiceCallCount: 16
        )
        await buildLine(in: session, from: stations[0], to: stations[1])
        let primaryID = try #require(session.lines.first?.id)
        session.setServiceFrequency(.quarterHourly, forLineID: primaryID)

        for segmentIndex in 1...12 {
            await buildLine(
                in: session,
                from: stations[segmentIndex],
                to: stations[segmentIndex + 1]
            )
            let candidateID = try #require(session.lines.first {
                $0.id != primaryID
            }).id
            session.setServiceFrequency(.quarterHourly, forLineID: candidateID)
            if segmentIndex < 12 {
                #expect(session.joinThroughService(
                    primaryLineID: primaryID,
                    withLineID: candidateID
                ))
            } else {
                #expect(session.throughServiceOptions(forLineID: primaryID).isEmpty)
                #expect(session.throughServiceIncompatibilities(
                    forLineID: primaryID
                ).contains {
                    $0.candidateLineID == candidateID
                        && $0.reasons.contains(.serviceLimitExceeded)
                })
                #expect(!session.joinThroughService(
                    primaryLineID: primaryID,
                    withLineID: candidateID
                ))
            }
        }

        let bounded = try #require(session.lines.first { $0.id == primaryID })
        #expect(bounded.ownedTrainCount == GameSaveSnapshot.maximumOwnedTrainCountPerService)
        #expect(bounded.corridorIDs.count == 12)
        #expect(session.lines.count == 2)
    }

    @Test("A retained train reaches and dwells at the joined corridor junction")
    func trainCallsAtJoinedJunction() async throws {
        let clock = M15ManualClock()
        let session = makeSession(clock: clock)
        await buildLine(in: session, from: purley, to: eastCroydon)
        await buildLine(in: session, from: eastCroydon, to: horley)
        let primaryID = session.lines[0].id
        #expect(session.joinThroughService(
            primaryLineID: primaryID,
            withLineID: session.lines[1].id
        ))
        let joined = try #require(session.lines.first)
        let junctionDistance = joined.route.cumulativeDistances[
            joined.route.stationCoordinateIndices[1]
        ]

        var reachedJunction = false
        for _ in 0..<2_000 where !reachedJunction {
            clock.advance(by: 0.25)
            reachedJunction = session.lines[0].trains.contains {
                $0.dwellRemaining > 0
                    && abs($0.distanceAlongRoute - junctionDistance) < 0.001
            }
        }
        #expect(reachedJunction)
    }

    @Test("One-corridor stop and track edits stay synchronized with the physical asset")
    func oneCorridorEditsSynchronizeAsset() async throws {
        let midway = Station(
            crs: "CDS",
            name: "Coulsdon South",
            latitude: (purley.latitude + eastCroydon.latitude) / 2,
            longitude: (purley.longitude + eastCroydon.longitude) / 2
        )
        let session = makeSession(stations: [purley, midway, eastCroydon])
        await buildLine(in: session, from: purley, to: eastCroydon)
        let lineID = try #require(session.lines.first?.id)

        session.beginEditingStops(forLineID: lineID)
        await session.waitForLineStopUpdate()
        let discovered = try #require(session.editableIntermediateStations.first {
            $0.crs == midway.crs
        })
        session.addIntermediateStation(discovered, toLineID: lineID)
        await session.waitForLineStopUpdate()

        #expect(session.lines[0].corridorStationCRSs == ["PUR", "CDS", "ECR"])
        #expect(session.corridors[0].stationCRSs == ["PUR", "CDS", "ECR"])
        #expect(session.upgradeTrackCapacity(forLineID: lineID))
        #expect(session.lines[0].trackCapacity == .passingLoop)
        #expect(session.corridors[0].trackCapacity == .passingLoop)
    }

    @Test("Merged spare fleets and corridor topology survive save-store and session restore")
    func persistenceRoundTrip() async throws {
        let sourceClock = M15ManualClock()
        let source = makeSession(clock: sourceClock)
        await buildLine(in: source, from: purley, to: eastCroydon)
        await buildLine(in: source, from: eastCroydon, to: horley)
        let primaryID = source.lines[0].id
        let candidateID = source.lines[1].id
        source.setServiceFrequency(.quarterHourly, forLineID: primaryID)
        source.setServiceFrequency(.quarterHourly, forLineID: candidateID)
        #expect(source.throughServiceOptions(forLineID: primaryID).first?.resultingOwnedTrainCount == 8)
        #expect(source.joinThroughService(primaryLineID: primaryID, withLineID: candidateID))
        sourceClock.advance(by: 5)
        let sourceLine = try #require(source.lines.first)
        #expect(sourceLine.ownedTrainCount == 8)

        let saveURL = temporarySaveURL()
        defer { try? FileManager.default.removeItem(at: saveURL.deletingLastPathComponent()) }
        let store = GameSaveStore(fileURL: saveURL)
        try await store.save(source.makeSaveSnapshot())
        let loaded = try #require(try await store.load())

        let restored = makeSession()
        try await restored.restore(from: loaded)
        let restoredLine = try #require(restored.lines.first)
        #expect(restored.corridors.count == 2)
        #expect(restoredLine.id == primaryID)
        #expect(restoredLine.corridorIDs == sourceLine.corridorIDs)
        #expect(restoredLine.stationCRSs == ["PUR", "ECR", "HOR"])
        #expect(restoredLine.ownedTrainCount == 8)
        #expect(restoredLine.trains.map(\.id) == sourceLine.trains.map(\.id))
        #expect(zip(restoredLine.trains, sourceLine.trains).allSatisfy { restoredTrain, sourceTrain in
            abs(
                restoredTrain.distanceAlongRoute / restoredLine.route.totalLength
                    - sourceTrain.distanceAlongRoute / sourceLine.route.totalLength
            ) < 0.000_000_001
                && restoredTrain.direction == sourceTrain.direction
                && abs(restoredTrain.dwellRemaining - sourceTrain.dwellRemaining) < 0.000_000_001
        })
        #expect(restored.financeLedger == source.financeLedger)

        let savedAgain = restored.makeSaveSnapshot()
        #expect(savedAgain.corridors.map(\.id) == loaded.corridors.map(\.id))
        #expect(savedAgain.lines.first?.corridorIDs == loaded.lines.first?.corridorIDs)
        #expect(savedAgain.lines.first?.ownedTrainCount == 8)
    }

    private static let purley = Station(
        crs: "PUR",
        name: "Purley",
        latitude: 51.3376,
        longitude: -0.1140
    )
    private static let eastCroydon = Station(
        crs: "ECR",
        name: "East Croydon",
        latitude: 51.3753,
        longitude: -0.0923
    )
    private static let horley = Station(
        crs: "HOR",
        name: "Horley",
        latitude: 51.1688,
        longitude: -0.1610
    )
    private static let redhill = Station(
        crs: "RDH",
        name: "Redhill",
        latitude: 51.2402,
        longitude: -0.1659
    )
    private static let reigate = Station(
        crs: "REI",
        name: "Reigate",
        latitude: 51.2419,
        longitude: -0.2038
    )

    private var purley: Station { Self.purley }
    private var eastCroydon: Station { Self.eastCroydon }
    private var horley: Station { Self.horley }
    private var redhill: Station { Self.redhill }
    private var reigate: Station { Self.reigate }

    private func makeSession(
        stations: [Station]? = nil,
        clock: M15ManualClock? = nil,
        capitalEconomy: CapitalEconomy = CapitalEconomy(),
        trainOperations: TrainOperations = TrainOperations(),
        gameMode: GameMode = .zen,
        indicativeCostPerKilometre: Int64 = 1_500_000,
        constructionDuration: TimeInterval = 0,
        maximumServiceCallCount: Int = 16
    ) -> GameSession {
        let catalog = stations ?? [purley, eastCroydon, horley]
        let resolvedClock = clock ?? M15ManualClock()
        return GameSession(
            stations: catalog,
            routingProvider: M15RoutingProvider(stations: catalog),
            stationCapacitySimulation: StationCapacitySimulation(
                configuration: StationCapacityConfiguration(
                    trainCallsPerPlatformPerHour: 1_000_000
                )
            ),
            capitalEconomy: capitalEconomy,
            trainOperations: trainOperations,
            gameMode: gameMode,
            clock: resolvedClock,
            configuration: GameConfiguration(
                maximumLineCount: 12,
                constructionDuration: constructionDuration,
                trainSpeedMetresPerSecond: 45,
                terminalDwellDuration: 2,
                indicativeCostPerKilometre: indicativeCostPerKilometre,
                maximumServiceCallCount: maximumServiceCallCount
            )
        )
    }

    private var lowCashCapitalEconomy: CapitalEconomy {
        CapitalEconomy(configuration: CapitalEconomyConfiguration(
            startingCashPence: 150,
            stationConstructionCostPence: 0,
            rollingStockUnitCostPence: 0,
            loanPrincipalPence: 0,
            earlyRepaymentPence: 0,
            loanAnnualInterestBasisPoints: 0,
            loanTermOperatingDays: 1,
            maximumConcurrentLoans: 0,
            insolvencyGraceOperatingDays: 7,
            lowCashThresholdPence: 0,
            stationValuePenceByLevel: [
                .halt: 0,
                .localStation: 0,
                .townStation: 0,
                .majorStation: 0,
                .interchange: 0,
                .terminus: 0,
            ]
        ))
    }

    private var lowCostTrainOperations: TrainOperations {
        TrainOperations(configuration: TrainOperationsConfiguration(
            localSpeedMultiplier: 0.82,
            expressSpeedMultiplier: 1.24,
            constrainedMixedExpressSpeedMultiplier: 0.86,
            localIntermediateDwellDuration: 3,
            passingLoopBaseCostPence: 100,
            doubleTrackConstructionCostBasisPoints: 0
        ))
    }

    private func testCapitalEconomy(startingCashPence: Int64) -> CapitalEconomy {
        CapitalEconomy(configuration: CapitalEconomyConfiguration(
            startingCashPence: startingCashPence,
            stationConstructionCostPence: 0,
            rollingStockUnitCostPence: 600,
            loanPrincipalPence: 0,
            earlyRepaymentPence: 0,
            loanAnnualInterestBasisPoints: 0,
            loanTermOperatingDays: 1,
            maximumConcurrentLoans: 0,
            insolvencyGraceOperatingDays: 7,
            lowCashThresholdPence: 0,
            stationValuePenceByLevel: [
                .halt: 0,
                .localStation: 0,
                .townStation: 0,
                .majorStation: 0,
                .interchange: 0,
                .terminus: 0,
            ]
        ))
    }

    private func buildLine(
        in session: GameSession,
        from origin: Station,
        to destination: Station,
        formation: RollingStockFormation = .legacyBaseline,
        railwayClass: RailwayClass = .conventional
    ) async {
        session.startBuilding()
        session.selectStation(origin)
        session.selectStation(destination)
        await session.waitForRouteCalculation()
        #expect(session.phase == .preview)
        session.setPreviewRailwayClass(railwayClass)
        session.setPreviewFormation(formation)
        session.confirmPreview()
        #expect(session.phase == .operating)
    }

    private static func coordinate(_ index: Int) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 51, longitude: Double(index) * 0.01)
    }

    private static var shiftedJunctionCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 51.000_01, longitude: 0.010_01)
    }

    private func coordinate(_ index: Int) -> CLLocationCoordinate2D {
        Self.coordinate(index)
    }

    private var shiftedJunctionCoordinate: CLLocationCoordinate2D {
        Self.shiftedJunctionCoordinate
    }

    private func temporarySaveURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TrainTrackTycoon-M15-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("save.json", isDirectory: false)
    }
}

private nonisolated struct M15RoutingProvider: RailwayRouteProviding {
    let coordinatesByCRS: [String: CLLocationCoordinate2D]

    init(stations: [Station]) {
        coordinatesByCRS = Dictionary(
            uniqueKeysWithValues: stations.map { ($0.crs, $0.coordinate) }
        )
    }

    func route(forStationCRSs stationCRSs: [String]) async throws -> ServiceRailwayRoute {
        let coordinates = try stationCRSs.map { crs in
            guard let coordinate = coordinatesByCRS[crs] else {
                throw M15RoutingError.missingStation(crs)
            }
            return coordinate
        }
        guard coordinates.count >= 2 else { throw M15RoutingError.tooFewStations }
        return ServiceRailwayRoute(
            coordinates: coordinates,
            stationCoordinateIndices: Array(coordinates.indices)
        )
    }
}

private nonisolated enum M15RoutingError: Error {
    case missingStation(String)
    case tooFewStations
}

@MainActor
private final class M15ManualClock: SimulationClock {
    private var tick: (@MainActor (TimeInterval) -> Void)?

    func start(tick: @escaping @MainActor (TimeInterval) -> Void) {
        self.tick = tick
    }

    func stop() { tick = nil }
    func setSuspended(_ isSuspended: Bool) {}

    func advance(by delta: TimeInterval) {
        tick?(delta)
    }
}
