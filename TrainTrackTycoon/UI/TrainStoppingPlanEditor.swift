import Foundation
import SwiftUI

/// A station the player can use when composing a train-specific stopping plan.
///
/// The UI accepts labelled tuples at its integration boundary, while this value gives policy and
/// tests a deterministic, equatable representation. CRS codes are normalised by the policy before
/// they are compared.
nonisolated struct TrainStoppingPlanStation: Identifiable, Equatable, Sendable {
    let crs: String
    let name: String

    var id: String { crs }
}

/// Editable state kept separate from `TrainServicePlan` so temporarily invalid terminal choices
/// can be shown and corrected without mutating the live service.
nonisolated struct TrainStoppingPlanDraft: Equatable, Sendable {
    let slotIndex: Int
    var role: TrainServiceRole
    var startCRS: String
    var endCRS: String
    var expressCallCRSs: Set<String>
}

nonisolated enum TrainStoppingPlanValidation: Equatable, Sendable {
    case valid
    case notEnoughStations
    case unavailableTerminal
    case matchingTerminals
    case tooManyCalls(maximum: Int)

    var message: String? {
        switch self {
        case .valid:
            nil
        case .notEnoughStations:
            "This railway needs at least two available stations."
        case .unavailableTerminal:
            "Choose two terminals on this railway."
        case .matchingTerminals:
            "Start and other terminal must be different stations."
        case .tooManyCalls(let maximum):
            "Choose no more than \(maximum) calls for this train."
        }
    }
}

nonisolated struct TrainStoppingPlanSummaryCopy: Equatable, Sendable {
    let title: String
    let route: String
    let callCount: String
    let accessibilityValue: String
}

/// Pure, deterministic rules shared by the editor, compact summary, and session integration.
nonisolated enum TrainStoppingPlanPolicy {
    static let defaultMaximumCallCount = 16

    static func stations(
        from values: [(crs: String, name: String)]
    ) -> [TrainStoppingPlanStation] {
        normalisedStations(
            values.map { TrainStoppingPlanStation(crs: $0.crs, name: $0.name) }
        )
    }

    static func normalisedStations(
        _ stations: [TrainStoppingPlanStation]
    ) -> [TrainStoppingPlanStation] {
        var seen = Set<String>()
        return stations.compactMap { station in
            let crs = normalisedCRS(station.crs)
            guard !crs.isEmpty, seen.insert(crs).inserted else { return nil }
            let trimmedName = station.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return TrainStoppingPlanStation(
                crs: crs,
                name: trimmedName.isEmpty ? crs : trimmedName
            )
        }
    }

    static func makeDraft(
        plan: TrainServicePlan,
        availableStations: [TrainStoppingPlanStation]
    ) -> TrainStoppingPlanDraft {
        let stations = normalisedStations(availableStations)
        let stationCRSs = Set(stations.map(\.crs))
        let planCRSs = uniqueCRSs(plan.stationCRSs)

        let proposedStart = planCRSs.first.flatMap { stationCRSs.contains($0) ? $0 : nil }
        let startCRS = proposedStart ?? stations.first?.crs ?? ""
        let proposedEnd = planCRSs.last.flatMap {
            stationCRSs.contains($0) && $0 != startCRS ? $0 : nil
        }
        let endCRS = proposedEnd
            ?? stations.reversed().first(where: { $0.crs != startCRS })?.crs
            ?? ""

        let expressCalls: Set<String>
        if plan.role == .express, planCRSs.count > 2 {
            expressCalls = Set(planCRSs.dropFirst().dropLast()).intersection(stationCRSs)
        } else {
            expressCalls = []
        }

        return TrainStoppingPlanDraft(
            slotIndex: plan.slotIndex,
            role: plan.role,
            startCRS: startCRS,
            endCRS: endCRS,
            expressCallCRSs: expressCalls
        )
    }

    static func orderedSpan(
        for draft: TrainStoppingPlanDraft,
        availableStations: [TrainStoppingPlanStation]
    ) -> [TrainStoppingPlanStation] {
        let stations = normalisedStations(availableStations)
        let startCRS = normalisedCRS(draft.startCRS)
        let endCRS = normalisedCRS(draft.endCRS)
        guard startCRS != endCRS,
              let startIndex = stations.firstIndex(where: { $0.crs == startCRS }),
              let endIndex = stations.firstIndex(where: { $0.crs == endCRS }) else {
            return []
        }

        if startIndex < endIndex {
            return Array(stations[startIndex...endIndex])
        }
        return Array(stations[endIndex...startIndex].reversed())
    }

    static func callingStations(
        for draft: TrainStoppingPlanDraft,
        availableStations: [TrainStoppingPlanStation]
    ) -> [TrainStoppingPlanStation] {
        let span = orderedSpan(for: draft, availableStations: availableStations)
        guard draft.role == .express, span.count > 2 else { return span }

        let expressCalls = Set(draft.expressCallCRSs.map(normalisedCRS))
        return span.enumerated().compactMap { index, station in
            let isTerminal = index == span.startIndex || index == span.index(before: span.endIndex)
            return isTerminal || expressCalls.contains(station.crs) ? station : nil
        }
    }

    static func validation(
        for draft: TrainStoppingPlanDraft,
        availableStations: [TrainStoppingPlanStation],
        maximumCallCount: Int = defaultMaximumCallCount
    ) -> TrainStoppingPlanValidation {
        let stations = normalisedStations(availableStations)
        guard stations.count >= 2 else { return .notEnoughStations }

        let startCRS = normalisedCRS(draft.startCRS)
        let endCRS = normalisedCRS(draft.endCRS)
        guard stations.contains(where: { $0.crs == startCRS }),
              stations.contains(where: { $0.crs == endCRS }) else {
            return .unavailableTerminal
        }
        guard startCRS != endCRS else { return .matchingTerminals }

        let calls = callingStations(for: draft, availableStations: stations)
        let effectiveMaximum = effectiveMaximumCallCount(maximumCallCount)
        guard calls.count <= effectiveMaximum else {
            return .tooManyCalls(maximum: effectiveMaximum)
        }
        return .valid
    }

    static func plan(
        from draft: TrainStoppingPlanDraft,
        availableStations: [TrainStoppingPlanStation],
        maximumCallCount: Int = defaultMaximumCallCount
    ) -> TrainServicePlan? {
        guard validation(
            for: draft,
            availableStations: availableStations,
            maximumCallCount: maximumCallCount
        ) == .valid else {
            return nil
        }
        return TrainServicePlan(
            slotIndex: draft.slotIndex,
            role: draft.role,
            stationCRSs: callingStations(
                for: draft,
                availableStations: availableStations
            ).map(\.crs)
        )
    }

    static func canSave(
        draft: TrainStoppingPlanDraft,
        replacing plan: TrainServicePlan,
        availableStations: [TrainStoppingPlanStation],
        maximumCallCount: Int = defaultMaximumCallCount
    ) -> Bool {
        guard let candidate = self.plan(
            from: draft,
            availableStations: availableStations,
            maximumCallCount: maximumCallCount
        ) else {
            return false
        }
        return candidate != normalisedPlan(plan)
    }

    static func settingRole(
        _ role: TrainServiceRole,
        in draft: TrainStoppingPlanDraft
    ) -> TrainStoppingPlanDraft {
        var updated = draft
        // Preserve an Express selection while Local temporarily overrides it. This makes an
        // accidental role tap reversible; drafts created from an existing Local plan still begin
        // with terminal-only Express service because they have no hidden Express calls.
        updated.role = role
        return updated
    }

    static func togglingExpressCall(
        _ crs: String,
        in draft: TrainStoppingPlanDraft,
        availableStations: [TrainStoppingPlanStation],
        maximumCallCount: Int = defaultMaximumCallCount
    ) -> TrainStoppingPlanDraft {
        guard draft.role == .express else { return draft }

        let normalised = normalisedCRS(crs)
        let span = orderedSpan(for: draft, availableStations: availableStations)
        guard span.count > 2,
              span.dropFirst().dropLast().contains(where: { $0.crs == normalised }) else {
            return draft
        }

        var updated = draft
        if updated.expressCallCRSs.contains(normalised) {
            updated.expressCallCRSs.remove(normalised)
        } else if callingStations(for: draft, availableStations: availableStations).count
            < effectiveMaximumCallCount(maximumCallCount) {
            updated.expressCallCRSs.insert(normalised)
        }
        return updated
    }

    static func summary(
        plan: TrainServicePlan,
        trainNumber: Int,
        availableStations: [TrainStoppingPlanStation]
    ) -> TrainStoppingPlanSummaryCopy {
        let stations = normalisedStations(availableStations)
        let namesByCRS = Dictionary(uniqueKeysWithValues: stations.map { ($0.crs, $0.name) })
        let calls = uniqueCRSs(plan.stationCRSs)
        let start = calls.first.map { namesByCRS[$0] ?? $0 } ?? "No terminal"
        let end = calls.last.map { namesByCRS[$0] ?? $0 } ?? "No terminal"
        let route = calls.count > 1 ? "\(start) ↔ \(end)" : start
        let callCount = calls.count == 1 ? "1 call" : "\(calls.count) calls"
        let title = "Train \(max(trainNumber, 1)) · \(plan.role.name)"
        return TrainStoppingPlanSummaryCopy(
            title: title,
            route: route,
            callCount: callCount,
            accessibilityValue: "\(plan.role.name) service between \(start) and \(end), \(callCount)"
        )
    }

    static func isExpressCall(
        _ station: TrainStoppingPlanStation,
        in draft: TrainStoppingPlanDraft
    ) -> Bool {
        draft.expressCallCRSs.contains(normalisedCRS(station.crs))
    }

    static func normalisedCRS(_ crs: String) -> String {
        crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func uniqueCRSs(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let crs = normalisedCRS(value)
            return !crs.isEmpty && seen.insert(crs).inserted ? crs : nil
        }
    }

    private static func normalisedPlan(_ plan: TrainServicePlan) -> TrainServicePlan {
        TrainServicePlan(
            slotIndex: plan.slotIndex,
            role: plan.role,
            stationCRSs: uniqueCRSs(plan.stationCRSs)
        )
    }

    private static func effectiveMaximumCallCount(_ requested: Int) -> Int {
        min(max(requested, 2), defaultMaximumCallCount)
    }
}

/// Compact, train-specific identity shown in the selected-train card before editing.
struct TrainStoppingPlanSummary: View {
    let plan: TrainServicePlan
    let trainNumber: Int
    let onEdit: () -> Void

    private let availableStations: [TrainStoppingPlanStation]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        availableStations: [(crs: String, name: String)],
        plan: TrainServicePlan,
        trainNumber: Int,
        onEdit: @escaping () -> Void
    ) {
        self.availableStations = TrainStoppingPlanPolicy.stations(from: availableStations)
        self.plan = plan
        self.trainNumber = trainNumber
        self.onEdit = onEdit
    }

    var body: some View {
        let copy = TrainStoppingPlanPolicy.summary(
            plan: plan,
            trainNumber: trainNumber,
            availableStations: availableStations
        )

        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    identity(copy)
                    editButton
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        identity(copy)
                        Spacer(minLength: 4)
                        editButton
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        identity(copy)
                        editButton
                    }
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 13))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Train \(max(trainNumber, 1)) stopping plan summary")
    }

    private func identity(_ copy: TrainStoppingPlanSummaryCopy) -> some View {
        HStack(alignment: .top, spacing: 9) {
            roleBadge

            VStack(alignment: .leading, spacing: 2) {
                Text(copy.title)
                    .font(.caption.weight(.bold))
                Text(copy.route)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(copy.callCount)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(copy.title)
        .accessibilityValue(copy.accessibilityValue)
    }

    private var roleBadge: some View {
        Text(plan.role.badge)
            .font(.caption.weight(.black))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(TycoonTheme.panelAccent, in: .circle)
            .accessibilityHidden(true)
    }

    private var editButton: some View {
        Button(action: onEdit) {
            Label("Edit plan", systemImage: "slider.horizontal.3")
                .font(.caption.weight(.bold))
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Edit Train \(max(trainNumber, 1)) stopping plan")
        .accessibilityHint("Choose terminals and station calls")
    }
}

/// An intrinsic-height editor intended to sit inside `BottomControlsViewport`.
///
/// It deliberately owns no `ScrollView`: the production viewport supplies the single bounded
/// scroll surface only when this content needs it, preserving map gestures above the panel.
struct TrainStoppingPlanEditor: View {
    let plan: TrainServicePlan
    let trainNumber: Int
    let maximumCallCount: Int
    let validationMessage: (TrainServicePlan) -> String?
    let onCancel: () -> Void
    let onSave: (TrainServicePlan) -> Void

    private let availableStations: [TrainStoppingPlanStation]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var draft: TrainStoppingPlanDraft

    init(
        availableStations: [(crs: String, name: String)],
        plan: TrainServicePlan,
        trainNumber: Int,
        maximumCallCount: Int = TrainStoppingPlanPolicy.defaultMaximumCallCount,
        validationMessage: @escaping (TrainServicePlan) -> String? = { _ in nil },
        onCancel: @escaping () -> Void,
        onSave: @escaping (TrainServicePlan) -> Void
    ) {
        let stations = TrainStoppingPlanPolicy.stations(from: availableStations)
        self.availableStations = stations
        self.plan = plan
        self.trainNumber = trainNumber
        self.maximumCallCount = min(
            max(maximumCallCount, 2),
            TrainStoppingPlanPolicy.defaultMaximumCallCount
        )
        self.validationMessage = validationMessage
        self.onCancel = onCancel
        self.onSave = onSave
        _draft = State(
            initialValue: TrainStoppingPlanPolicy.makeDraft(
                plan: plan,
                availableStations: stations
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            terminalControls
            roleControls
            callingPointControls
            validationStatus
            actionBar
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .railPanel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Train \(max(trainNumber, 1)) stopping plan editor")
        .onChange(of: plan) { _, updatedPlan in
            draft = TrainStoppingPlanPolicy.makeDraft(
                plan: updatedPlan,
                availableStations: availableStations
            )
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(draft.role.badge)
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(TycoonTheme.panelAccent, in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Train \(max(trainNumber, 1)) stopping plan")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Choose two terminals and the stations this train calls at. It runs both ways.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var terminalControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TERMINALS")
                .font(.caption2.weight(.black))
                .tracking(0.45)
                .foregroundStyle(.secondary)

            terminalPicker(
                title: "Start terminal",
                systemImage: "a.circle.fill",
                selection: Binding(
                    get: { draft.startCRS },
                    set: { draft.startCRS = $0 }
                )
            )
            terminalPicker(
                title: "Other terminal",
                systemImage: "b.circle.fill",
                selection: Binding(
                    get: { draft.endCRS },
                    set: { draft.endCRS = $0 }
                )
            )
        }
    }

    private func terminalPicker(
        title: String,
        systemImage: String,
        selection: Binding<String>
    ) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    terminalLabel(title: title, systemImage: systemImage)
                    terminalMenu(title: title, selection: selection)
                }
            } else {
                HStack(spacing: 9) {
                    terminalLabel(title: title, systemImage: systemImage)
                    Spacer(minLength: 4)
                    terminalMenu(title: title, selection: selection)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 11))
    }

    private func terminalLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    private func terminalMenu(
        title: String,
        selection: Binding<String>
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(availableStations) { station in
                Text(station.name).tag(station.crs)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(minHeight: 44)
        .accessibilityLabel(title)
        .accessibilityValue(stationName(for: selection.wrappedValue))
        .accessibilityHint("Choose a built station on this railway")
    }

    private var roleControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TRAIN TYPE")
                .font(.caption2.weight(.black))
                .tracking(0.45)
                .foregroundStyle(.secondary)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 8) {
                        roleButton(.local)
                        roleButton(.express)
                    }
                } else {
                    HStack(spacing: 8) {
                        roleButton(.local)
                        roleButton(.express)
                    }
                }
            }
        }
    }

    private func roleButton(_ role: TrainServiceRole) -> some View {
        let isSelected = draft.role == role
        return Button {
            draft = TrainStoppingPlanPolicy.settingRole(role, in: draft)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                VStack(alignment: .leading, spacing: 1) {
                    Text(role.name)
                        .font(.caption.weight(.bold))
                    Text(role == .local ? "Every station" : "Choose calls")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? TycoonTheme.panelAccent.opacity(0.13) : Color.secondary.opacity(0.06),
            in: .rect(cornerRadius: 11)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(
                    isSelected ? TycoonTheme.panelAccent.opacity(0.75) : Color.clear,
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(role.name) train")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(
            role == .local
                ? "Calls at every station between the terminals"
                : "Lets you choose intermediate station calls"
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var callingPointControls: some View {
        let span = TrainStoppingPlanPolicy.orderedSpan(
            for: draft,
            availableStations: availableStations
        )

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("CALLING POINTS")
                    .font(.caption2.weight(.black))
                    .tracking(0.45)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(callCountLabel)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if span.isEmpty {
                Label(
                    "Choose two different terminals to see their stations.",
                    systemImage: "arrow.left.and.right.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 44)
            } else {
                VStack(spacing: 0) {
                    ForEach(span.indices, id: \.self) { index in
                        let station = span[index]
                        callingPointRow(
                            station,
                            ordinal: index + 1,
                            isTerminal: index == 0 || index == span.count - 1
                        )
                    }
                }

                Text(callingPointHelp)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func callingPointRow(
        _ station: TrainStoppingPlanStation,
        ordinal: Int,
        isTerminal: Bool
    ) -> some View {
        let calls = isTerminal || draft.role == .local
            || TrainStoppingPlanPolicy.isExpressCall(station, in: draft)
        let selectable = draft.role == .express && !isTerminal
        let atLimit = !calls && resolvedCallingStations.count >= maximumCallCount
        let content = callingPointRowContent(
            station,
            ordinal: ordinal,
            calls: calls,
            isTerminal: isTerminal
        )

        if selectable {
            Button {
                draft = TrainStoppingPlanPolicy.togglingExpressCall(
                    station.crs,
                    in: draft,
                    availableStations: availableStations,
                    maximumCallCount: maximumCallCount
                )
            } label: {
                content.contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(atLimit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(station.name)
            .accessibilityValue(calls ? "Calls here" : "Passes without stopping")
            .accessibilityHint(
                atLimit
                    ? "Remove another call before choosing this station"
                    : calls ? "Removes this station call" : "Adds this station call"
            )
            .accessibilityAddTraits(calls ? .isSelected : [])
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(station.name)
                .accessibilityValue(
                    isTerminal
                        ? "Terminal, always called at"
                        : "Local call, always selected"
                )
        }
    }

    private func callingPointRowContent(
        _ station: TrainStoppingPlanStation,
        ordinal: Int,
        calls: Bool,
        isTerminal: Bool
    ) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Capsule()
                    .fill(TycoonTheme.panelAccent.opacity(0.25))
                    .frame(width: 3, height: 54)
                Circle()
                    .fill(calls ? TycoonTheme.panelAccent : Color.secondary)
                    .frame(width: 27, height: 27)
                Text(ordinal.formatted())
                    .font(.caption2.weight(.black).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 54)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                    .font(.subheadline.weight(isTerminal ? .bold : .semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(isTerminal ? "Terminal · always calls" : calls ? "Calls" : "Passes")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Image(systemName: calls ? "checkmark.circle.fill" : "circle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(calls ? TycoonTheme.panelAccent : Color.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .background(
            calls ? TycoonTheme.panelAccent.opacity(0.08) : Color.clear,
            in: .rect(cornerRadius: 11)
        )
    }

    @ViewBuilder
    private var validationStatus: some View {
        let validation = TrainStoppingPlanPolicy.validation(
            for: draft,
            availableStations: availableStations,
            maximumCallCount: maximumCallCount
        )

        if let message = validation.message {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TycoonTheme.panelWarning)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
        } else if let message = externalValidationMessage {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TycoonTheme.panelWarning)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
        } else if canSave {
            Label("Ready to save · \(callCountLabel)", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TycoonTheme.panelAccent)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
        } else {
            Text("No changes yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actionBar: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    saveButton
                    cancelButton
                }
            } else {
                HStack(spacing: 10) {
                    cancelButton
                    saveButton
                }
            }
        }
        .padding(.top, 2)
    }

    private var cancelButton: some View {
        Button("Cancel", action: onCancel)
            .font(.subheadline.weight(.bold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .buttonStyle(.bordered)
            .accessibilityHint("Discards changes to this train")
    }

    private var saveButton: some View {
        Button {
            guard let updatedPlan = TrainStoppingPlanPolicy.plan(
                from: draft,
                availableStations: availableStations,
                maximumCallCount: maximumCallCount
            ) else { return }
            onSave(updatedPlan)
        } label: {
            Text("Save plan")
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(TycoonTheme.railGreen)
        .disabled(!canSave)
        .accessibilityHint("Applies the new terminals and calling points to this train")
    }

    private var canSave: Bool {
        TrainStoppingPlanPolicy.canSave(
            draft: draft,
            replacing: plan,
            availableStations: availableStations,
            maximumCallCount: maximumCallCount
        ) && externalValidationMessage == nil
    }

    private var externalValidationMessage: String? {
        guard let candidate = TrainStoppingPlanPolicy.plan(
            from: draft,
            availableStations: availableStations,
            maximumCallCount: maximumCallCount
        ) else { return nil }
        return validationMessage(candidate)
    }

    private var resolvedCallingStations: [TrainStoppingPlanStation] {
        TrainStoppingPlanPolicy.callingStations(
            for: draft,
            availableStations: availableStations
        )
    }

    private var callCountLabel: String {
        let count = resolvedCallingStations.count
        return count == 1 ? "1 call" : "\(count) calls"
    }

    private var callingPointHelp: String {
        switch draft.role {
        case .local:
            "Local trains call at every station between their terminals."
        case .express:
            "Tap an intermediate station to switch between calling and passing. Terminals are always included."
        }
    }

    private func stationName(for crs: String) -> String {
        let normalised = TrainStoppingPlanPolicy.normalisedCRS(crs)
        return availableStations.first(where: { $0.crs == normalised })?.name ?? normalised
    }
}
