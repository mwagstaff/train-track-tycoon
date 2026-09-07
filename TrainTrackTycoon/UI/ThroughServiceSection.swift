import Foundation
import SwiftUI

/// Map-first, progressive disclosure for combining adjacent completed services.
///
/// The session revalidates compatibility when the player confirms. This view therefore treats an
/// option as descriptive copy, never as authority to mutate a stale network.
struct ThroughServiceSection: View {
    let line: BuiltLine
    let options: [ThroughServiceOption]
    let incompatibilities: [ThroughServiceIncompatibility]
    let gameMode: GameMode
    let join: (ThroughServiceOption) -> Bool
    var openFinances: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var pendingOption: ThroughServiceOption?
    @State private var mergeFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header

            if !line.isConstructed {
                unavailableSummary(
                    title: "Available after construction",
                    message: "Finish this line before joining it to an adjacent service."
                )
            } else {
                if line.corridorIDs.count > 1 {
                    joinedServiceSummary
                }

                if options.isEmpty, !incompatibilities.isEmpty {
                    incompatibilitySummary
                } else if options.isEmpty {
                    unavailableSummary(
                        title: isExtensionContext
                            ? "No connected service to add"
                            : "No compatible service yet",
                        message: isExtensionContext
                            ? "A service must share one outer terminal and form one continuous route."
                            : "Build another completed conventional service sharing exactly one end station. Any operating or asset differences will be proposed automatically."
                    )
                } else {
                    Text(optionGuidance)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(options) { option in
                        optionRow(option)
                    }
                }
            }

            if mergeFailed {
                Label(
                    "The network or price changed. Review the updated proposal before trying again.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TycoonTheme.panelWarning)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(11)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .sheet(item: $pendingOption) { option in
            ThroughServiceReviewSheet(
                option: option,
                orderedStationNames: orderedStationNames(for: option),
                gameMode: gameMode,
                cancel: { pendingOption = nil },
                confirm: { confirmMerge(option) },
                openFinances: {
                    pendingOption = nil
                    openFinances()
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(isExtensionContext ? "Extend service" : "Join service")
                    .font(.caption.weight(.bold))
                Text(
                    isExtensionContext
                        ? "Add another connected service"
                        : "Combine compatible routes"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: isExtensionContext ? "link.circle.fill" : "link.badge.plus")
                .foregroundStyle(TycoonTheme.panelAccent)
        }
        .accessibilityElement(children: .combine)
    }

    private var joinedServiceSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(line.origin.name)  →  \(line.destination.name)")
                .font(.caption.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("\(corridorCountLabel(line.corridorIDs.count)) operate as one service. Every corridor remains separately owned.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Through service from \(line.origin.name) to \(line.destination.name)")
        .accessibilityValue("\(line.corridorIDs.count) joined corridors")
    }

    private var isExtensionContext: Bool {
        line.corridorIDs.count > 1
            || options.contains { isExtension($0) }
    }

    private var optionGuidance: String {
        if isExtensionContext {
            return "Add a completed service at an outer terminal. Any timetable, train or track changes are shown before you confirm."
        }
        return "Run one service across existing corridors. Any timetable, train or track changes are shown before you confirm."
    }

    private func unavailableSummary(title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var incompatibilitySummary: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(
                isExtensionContext
                    ? "This service cannot be extended here"
                    : "This service cannot be joined yet",
                systemImage: "exclamationmark.triangle.fill"
            )
                .font(.caption.weight(.semibold))
                .foregroundStyle(TycoonTheme.panelWarning)

            ForEach(incompatibilities) { incompatibility in
                let copy = ThroughServiceIncompatibilityCopy(
                    incompatibility: incompatibility
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(copy.title)
                        .font(.caption.weight(.semibold))
                    Text(copy.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 10))
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private func optionRow(_ option: ThroughServiceOption) -> some View {
        let identity = optionIdentity(option)
        let action = joinButton(option)

        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 7) {
                    identity
                    action
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        identity
                        Spacer(minLength: 4)
                        action
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        identity
                        action
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 11))
    }

    private func optionIdentity(_ option: ThroughServiceOption) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(option.originName)  →  \(option.destinationName)")
                .font(.subheadline.weight(.semibold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
            Text("via \(option.junctionName) · add Line \(option.candidateLineNumber)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(
                "\(corridorCountLabel(option.resultingCorridorCount)) · "
                    + "\(callCountLabel(option.stationCRSs.count)) · "
                    + "\(option.frequency.name)"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            automaticChanges(for: option)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(isExtension(option) ? "Extend" : "Join") Line \(option.primaryLineNumber) with Line \(option.candidateLineNumber) as a service from \(option.originName) to \(option.destinationName) via \(option.junctionName)"
        )
        .accessibilityValue(
            optionAccessibilityValue(option)
        )
    }

    private func joinButton(_ option: ThroughServiceOption) -> some View {
        Button {
            mergeFailed = false
            pendingOption = option
        } label: {
            Text(optionActionTitle(option))
                .font(.caption.weight(.bold))
                .frame(minWidth: 92, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(
            option.canAfford
                ? "\(isExtension(option) ? "Extend" : "Join") with Line \(option.candidateLineNumber)"
                : "Review funding to \(isExtension(option) ? "extend" : "join") with Line \(option.candidateLineNumber)"
        )
        .accessibilityHint(joinAccessibilityHint(option))
    }

    private func automaticChanges(for option: ThroughServiceOption) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: option.automaticChanges.isEmpty
                ? "checkmark.circle.fill"
                : "arrow.triangle.2.circlepath")
                .foregroundStyle(option.canAfford
                    ? TycoonTheme.panelAccent
                    : TycoonTheme.panelWarning)
                .accessibilityHidden(true)
            Text(compactChangeSummary(option))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(option.canAfford ? Color.secondary : TycoonTheme.panelWarning)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 3)
        .accessibilityElement(children: .combine)
    }

    private func optionActionTitle(_ option: ThroughServiceOption) -> String {
        if !option.canAfford {
            return "Review funding"
        }
        if isExtension(option) {
            return option.automaticChanges.isEmpty ? "Extend service" : "Review & extend"
        }
        return option.automaticChanges.isEmpty ? "Join service" : "Review & join"
    }

    private func compactChangeSummary(_ option: ThroughServiceOption) -> String {
        let changeCount = option.automaticChanges.count
        let changes = changeCount == 0
            ? "Ready to \(isExtension(option) ? "extend" : "join")"
            : "\(changeCount) automatic change\(changeCount == 1 ? "" : "s")"
        return "\(changes) · \(investmentSummary(option))"
    }

    private func confirmMerge(_ option: ThroughServiceOption) {
        pendingOption = nil
        mergeFailed = !join(option)
    }

    private func investmentSummary(_ option: ThroughServiceOption) -> String {
        let total = ThroughServiceConfirmationCopy.formattedPence(
            option.capitalQuote.totalPence
        )
        if option.capitalQuote.totalPence == 0 {
            return "No purchase required"
        }
        if gameMode == .zen {
            return "\(total) investment · unlimited Zen budget"
        }
        if option.canAfford {
            return "\(total) automatic investment"
        }
        return "\(total) investment · needs "
            + "\(ThroughServiceConfirmationCopy.formattedPence(option.fundingShortfallPence)) more cash"
    }

    private func joinAccessibilityHint(_ option: ThroughServiceOption) -> String {
        if !option.canAfford {
            return "Opens the automatic change quote. "
                + "\(ThroughServiceConfirmationCopy.formattedPence(option.fundingShortfallPence)) more available cash is required before \(isExtension(option) ? "extending" : "joining")"
        }
        if option.automaticChanges.isEmpty {
            return "Opens a confirmation explaining which service closes and what remains owned"
        }
        return "Opens a confirmation listing every automatic change, its cost, which service closes and what is retained"
    }

    private func optionAccessibilityValue(_ option: ThroughServiceOption) -> String {
        var parts = [
            "Calls at \(orderedStationNames(for: option).joined(separator: ", then "))",
            "\(corridorCountLabel(option.resultingCorridorCount))",
            "\(option.frequency.name), \(option.servicePattern.name), \(option.formation.carriageCount) car trains, \(option.trackCapacity.name)",
        ]
        if !option.automaticChanges.isEmpty {
            parts.append(
                "Automatic changes: " + option.automaticChanges.map {
                    ThroughServiceAutomaticChangeCopy(change: $0).summary
                }.joined(separator: ". ")
            )
            parts.append(investmentSummary(option))
        }
        return parts.joined(separator: ". ")
    }

    private func isExtension(_ option: ThroughServiceOption) -> Bool {
        option.primaryCorridorCount > 1 || option.candidateCorridorCount > 1
    }

    private func corridorCountLabel(_ count: Int) -> String {
        "\(count) retained corridor\(count == 1 ? "" : "s")"
    }

    private func callCountLabel(_ count: Int) -> String {
        "\(count) calling point\(count == 1 ? "" : "s")"
    }

    private func orderedStationNames(for option: ThroughServiceOption) -> [String] {
        guard option.stationNames.count == option.stationCRSs.count,
              option.stationNames.allSatisfy({ !$0.isEmpty }) else {
            return option.stationCRSs
        }
        return option.stationNames
    }
}

/// A long-form, scrollable review surface for an irreversible join or extension. A dialog is too
/// small once asset reconciliation needs to explain several changes and their individual prices.
struct ThroughServiceReviewSheet: View {
    let option: ThroughServiceOption
    let orderedStationNames: [String]
    let gameMode: GameMode
    let cancel: () -> Void
    let confirm: () -> Void
    var openFinances: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    resultingServiceCard
                    changesCard
                    investmentCard
                    consequencesCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }

            Divider()
            actionBar
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: "link.badge.plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(TycoonTheme.panelAccent)
                .frame(width: 36, height: 36)
                .background(TycoonTheme.panelAccent.opacity(0.12), in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(isExtension ? "Extend service?" : "Join services?")
                    .font(.headline)
                Text("\(option.originName) → \(option.destinationName) via \(option.junctionName)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var resultingServiceCard: some View {
        reviewCard(title: "Resulting service", systemImage: "train.side.front.car") {
            Text(
                "\(option.frequency.name) · \(option.servicePattern.name) · "
                    + "\(option.formation.carriageCount)-car · \(option.trackCapacity.name)"
            )
            .font(.subheadline.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)

            Text(
                "\(option.resultingCorridorCount) retained corridor"
                    + "\(option.resultingCorridorCount == 1 ? "" : "s") · "
                    + "\(resolvedStationNames.count) calling point"
                    + "\(resolvedStationNames.count == 1 ? "" : "s")"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Text("Calling points")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(resolvedStationNames.joined(separator: " → "))
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var changesCard: some View {
        reviewCard(title: "Automatic changes", systemImage: "arrow.triangle.2.circlepath") {
            if option.automaticChanges.isEmpty {
                Label("Both services already match", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TycoonTheme.panelAccent)
            } else {
                ForEach(option.automaticChanges.indices, id: \.self) { index in
                    let summary = ThroughServiceAutomaticChangeCopy(
                        change: option.automaticChanges[index]
                    ).summary
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(TycoonTheme.panelAccent)
                            .accessibilityHidden(true)
                        Text(summary)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var investmentCard: some View {
        reviewCard(title: "Investment", systemImage: "sterlingsign.circle.fill") {
            Text(investmentStatus)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(option.canAfford ? Color.primary : TycoonTheme.panelWarning)
                .fixedSize(horizontal: false, vertical: true)

            if option.capitalQuote.trackAndInfrastructurePence > 0 {
                investmentLine(
                    "Track and infrastructure",
                    pence: option.capitalQuote.trackAndInfrastructurePence
                )
            }
            if option.capitalQuote.rollingStockPence > 0 {
                investmentLine(
                    "Rolling stock",
                    pence: option.capitalQuote.rollingStockPence
                )
            }

            if !option.canAfford, gameMode == .career {
                Text("Open Network finances to arrange a loan, then review this proposal again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var consequencesCard: some View {
        reviewCard(title: "What will happen", systemImage: "point.3.connected.trianglepath.dotted") {
            consequence(
                "Line \(option.primaryLineNumber) keeps its identity, colour, timetable and active trains. All \(option.resultingCorridorCount) physical corridors remain owned and become one continuous service."
            )
            consequence(
                "Line \(option.candidateLineNumber) closes as a separate service, along with its timetable and train plans. Its purchased fleet (\(candidateFleetLabel)) remains owned as part of the combined fleet."
            )
            consequence(primaryPlanConsequence)
            consequence(
                "The joined service owns \(option.resultingOwnedTrainCount) trainsets: \(option.activeTrainCount) active and \(spareLabel)."
            )

            Label(
                "This \(isExtension ? "extension" : "merge") cannot be undone",
                systemImage: "exclamationmark.triangle.fill"
            )
                .font(.caption.weight(.bold))
                .foregroundStyle(TycoonTheme.panelWarning)
                .padding(.top, 2)
                .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        if option.canAfford {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 8) {
                        confirmButton
                        cancelButton
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            cancelButton
                            confirmButton
                        }
                        VStack(spacing: 8) {
                            confirmButton
                            cancelButton
                        }
                    }
                }
            }
            .padding(12)
        } else {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 8) {
                        openFinancesButton
                        notNowButton
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            notNowButton
                            openFinancesButton
                        }
                        VStack(spacing: 8) {
                            openFinancesButton
                            notNowButton
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    private var cancelButton: some View {
        Button("Cancel", action: cancel)
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .buttonStyle(.bordered)
            .accessibilityHint("Leave both services unchanged")
    }

    private var confirmButton: some View {
        Button(confirmationCopy.actionTitle, action: confirm)
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .buttonStyle(.borderedProminent)
            .tint(TycoonTheme.railGreen)
            .accessibilityHint(
                "Apply the listed changes and permanently "
                    + "\(isExtension ? "extend" : "combine") the services"
            )
    }

    private var notNowButton: some View {
        Button("Not now", action: cancel)
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .buttonStyle(.bordered)
            .accessibilityHint("Return to the service controls without changing the railway")
    }

    private var openFinancesButton: some View {
        Button("Open Network finances", action: openFinances)
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .buttonStyle(.borderedProminent)
            .tint(TycoonTheme.railGreen)
            .accessibilityHint("Open finance controls to arrange the funding needed for this service")
    }

    private func reviewCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(TycoonTheme.panelAccent)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    private func investmentLine(_ label: String, pence: Int64) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer(minLength: 12)
            Text(ThroughServiceConfirmationCopy.formattedPence(pence))
                .fontWeight(.semibold)
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }

    private func consequence(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(TycoonTheme.panelAccent)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var confirmationCopy: ThroughServiceConfirmationCopy {
        ThroughServiceConfirmationCopy(
            option: option,
            orderedStationNames: resolvedStationNames,
            gameMode: gameMode
        )
    }

    private var resolvedStationNames: [String] {
        guard orderedStationNames.count == option.stationCRSs.count,
              orderedStationNames.allSatisfy({ !$0.isEmpty }) else {
            return option.stationCRSs
        }
        return orderedStationNames
    }

    private var investmentStatus: String {
        let total = ThroughServiceConfirmationCopy.formattedPence(
            option.capitalQuote.totalPence
        )
        if option.capitalQuote.totalPence == 0 {
            return "No purchase required"
        }
        if gameMode == .zen {
            return "\(total) recorded against the unlimited Zen budget"
        }
        if option.canAfford {
            return isExtension
                ? "\(total) charged when you extend the service"
                : "\(total) charged when the services join"
        }
        let shortfall = ThroughServiceConfirmationCopy.formattedPence(
            option.fundingShortfallPence
        )
        return "\(total) required · \(shortfall) more cash needed"
    }

    private var candidateFleetLabel: String {
        option.candidateOwnedTrainCount == 1
            ? "1 trainset"
            : "\(option.candidateOwnedTrainCount) trainsets"
    }

    private var spareLabel: String {
        let count = max(option.resultingOwnedTrainCount - option.activeTrainCount, 0)
        return count == 1 ? "1 spare" : "\(count) spares"
    }

    private var isExtension: Bool {
        option.primaryCorridorCount > 1 || option.candidateCorridorCount > 1
    }

    private var primaryPlanConsequence: String {
        if option.preservesPrimaryCustomServicePlans {
            return "Line \(option.primaryLineNumber)'s four custom train plans keep their existing terminals and calls. Use Edit plan afterwards to send those trains over the added corridors."
        }
        return "Line \(option.primaryLineNumber)'s four train plans extend across the resulting route using its \(option.servicePattern.name) fleet preset."
    }
}

nonisolated struct ThroughServiceConfirmationCopy: Equatable, Sendable {
    let title: String
    let actionTitle: String
    let message: String

    init(
        option: ThroughServiceOption,
        orderedStationNames: [String] = [],
        gameMode: GameMode = .zen
    ) {
        let candidateFleetLabel = Self.trainsetLabel(option.candidateOwnedTrainCount)
        let candidateFleetVerb = option.candidateOwnedTrainCount == 1 ? "stays" : "stay"
        let spareCount = max(option.resultingOwnedTrainCount - option.activeTrainCount, 0)
        let spareLabel = spareCount == 1 ? "1 spare" : "\(spareCount) spares"
        let isExtension = option.primaryCorridorCount > 1
            || option.candidateCorridorCount > 1
        let callNames = orderedStationNames.isEmpty
            ? option.stationCRSs
            : orderedStationNames
        let callingPoints = callNames.joined(separator: " → ")
        let total = Self.formattedPence(option.capitalQuote.totalPence)
        let changes = option.automaticChanges.map {
            "• " + ThroughServiceAutomaticChangeCopy(change: $0).summary
        }
        let changesParagraph: String
        if changes.isEmpty {
            changesParagraph = "No automatic service or asset changes are needed."
        } else {
            changesParagraph = "Automatic changes:\n" + changes.joined(separator: "\n")
        }
        let investmentParagraph: String
        if option.capitalQuote.totalPence == 0 {
            investmentParagraph = option.automaticChanges.isEmpty
                ? "No construction, station or rolling-stock purchase is made, and no cash is charged."
                : "These timetable changes cost nothing; no cash is charged."
        } else if gameMode == .zen {
            investmentParagraph = "Automatic investment: \(total). The Zen budget is unlimited; this amount will be added to lifetime capital spending."
        } else if option.canAfford {
            investmentParagraph = isExtension
                ? "Automatic investment: \(total), charged immediately when you extend the service."
                : "Automatic investment: \(total), charged immediately when the services join."
        } else {
            investmentParagraph = "Automatic investment: \(total). You need \(Self.formattedPence(option.fundingShortfallPence)) more cash. Arrange a loan before \(isExtension ? "extending" : "joining")."
        }

        title = "\(isExtension ? "Extend" : "Join") as \(option.originName) – \(option.destinationName)?"
        if option.automaticChanges.isEmpty {
            actionTitle = isExtension ? "Extend service" : "Merge services"
        } else if gameMode == .career, option.capitalQuote.totalPence > 0 {
            actionTitle = "Upgrade & \(isExtension ? "extend" : "join") for \(total)"
        } else {
            actionTitle = "Apply changes & \(isExtension ? "extend" : "join")"
        }
        let corridorLabel = option.resultingCorridorCount == 1
            ? "1 retained corridor"
            : "\(option.resultingCorridorCount) retained corridors"
        let planParagraph: String
        if option.preservesPrimaryCustomServicePlans {
            planParagraph = "Line \(option.primaryLineNumber)'s four custom train plans keep their existing terminals and calls. Use Edit plan afterwards to send those trains over the added corridors."
        } else {
            planParagraph = "Line \(option.primaryLineNumber)'s four train plans will use its \(option.servicePattern.name) fleet preset across the full resulting route."
        }
        message = "Resulting service: \(option.frequency.name), \(option.servicePattern.name), \(option.formation.carriageCount)-car trains, \(option.trackCapacity.name), \(corridorLabel).\nCalling points: \(callingPoints).\n\n\(changesParagraph)\n\n\(investmentParagraph)\n\nLine \(option.primaryLineNumber) will run through \(option.junctionName) over all \(option.resultingCorridorCount) retained physical corridors. Line \(option.candidateLineNumber) will close as a separate service, along with its timetable and train plans, but its \(candidateFleetLabel) \(candidateFleetVerb) owned. \(planParagraph) Line \(option.primaryLineNumber) will have \(option.resultingOwnedTrainCount) trainsets: \(option.activeTrainCount) active and \(spareLabel). This \(isExtension ? "extension" : "merge") cannot be undone."
    }

    private static func trainsetLabel(_ count: Int) -> String {
        count == 1 ? "1 trainset" : "\(count) trainsets"
    }

    static func formattedPence(_ pence: Int64) -> String {
        (Double(max(pence, 0)) / 100).formatted(
            .currency(code: "GBP").precision(.fractionLength(0))
        )
    }
}

nonisolated struct ThroughServiceAutomaticChangeCopy: Equatable, Sendable {
    let summary: String

    init(change: ThroughServiceAutomaticChange) {
        switch change {
        case let .serviceFrequency(_, lineNumber, from, to):
            summary = "Line \(lineNumber) timetable: \(from.name) → \(to.name) · no cost"
        case let .servicePattern(_, lineNumber, from, to):
            summary = "Line \(lineNumber) stopping pattern: \(from.name) → \(to.name) · no cost"
        case let .formation(_, lineNumber, ownedTrainCount, from, to, costPence):
            let trainsets = ownedTrainCount == 1 ? "1 trainset" : "\(ownedTrainCount) trainsets"
            summary = "Line \(lineNumber) fleet: \(trainsets), \(from.carriageCount) → \(to.carriageCount) cars · \(ThroughServiceConfirmationCopy.formattedPence(costPence))"
        case let .trackCapacity(_, lineNumber, _, segmentName, from, to, costPence):
            summary = "Line \(lineNumber), \(segmentName): \(from.name) → \(to.name) · \(ThroughServiceConfirmationCopy.formattedPence(costPence))"
        }
    }
}

nonisolated struct ThroughServiceIncompatibilityCopy: Equatable, Sendable {
    let title: String
    let message: String

    init(incompatibility: ThroughServiceIncompatibility) {
        title = "Line \(incompatibility.candidateLineNumber) via \(incompatibility.junctionName)"
        message = incompatibility.reasons.map(Self.message(for:)).joined(separator: " ")
    }

    private static func message(
        for reason: ThroughServiceIncompatibilityReason
    ) -> String {
        switch reason {
        case .incompleteConstruction:
            "Finish construction before joining these services."
        case .conventionalServicesOnly:
            "Both services must be conventional railways."
        case .alreadyJoinedService:
            "This saved through service cannot be extended until its route is refreshed."
        case .overlappingOrBranchedRoute:
            "These services overlap or would create a branch or loop. Choose services that meet at one outer terminal."
        case .serviceLimitExceeded:
            "The resulting service would exceed the current route or fleet limit."
        case .frequencyMismatch:
            "Match the timetable frequency."
        case .servicePatternMismatch:
            "Match the Local, Balanced or Express stopping pattern."
        case .formationMismatch:
            "Match the train length."
        case .trackCapacityMismatch:
            "Match the track capacity."
        case .unavailable:
            "This adjacent pair cannot be joined with the current network layout."
        }
    }
}
