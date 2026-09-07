import SwiftUI

/// Progressive disclosure for adding paid, durable station calls to an operating line.
/// Existing calls are deliberately read-only in this milestone.
struct BuiltLineStopsSection: View {
    let line: BuiltLine
    let stationCatalog: [Station]
    let availableIntermediateStations: [Station]
    let maximumStopCount: Int
    let isEditing: Bool
    let isUpdating: Bool
    let gameMode: GameMode
    let beginEditing: () -> Void
    let addStation: (Station) -> Void
    let finishEditing: () -> Void
    let additionCostPence: (Station) -> Int64?
    let canAfford: (Station) -> Bool
    var editingUnavailableReason: String? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var pendingAddition: PendingStopAddition?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            Text(currentStationNames.joined(separator: "  →  "))
                .font(.caption.weight(.semibold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Current calling points in route order")
                .accessibilityValue(currentStationNames.joined(separator: ", then "))

            if let editingUnavailableReason {
                Label(editingUnavailableReason, systemImage: "link")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
            }

            if isEditing {
                Divider()
                availableStops
            }
        }
        .padding(11)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .confirmationDialog(
            pendingAddition?.copy.title ?? "Add this station permanently?",
            isPresented: isConfirmingAddition,
            titleVisibility: .visible,
            presenting: pendingAddition
        ) { pendingAddition in
            Button(pendingAddition.copy.actionTitle, role: .destructive) {
                confirmAddition(pendingAddition)
            }
            .disabled(
                isUpdating
                    || (gameMode == .career && !canAfford(pendingAddition.station))
            )

            Button("Cancel", role: .cancel) {
                self.pendingAddition = nil
            }
        } message: { pendingAddition in
            Text(pendingAddition.copy.message)
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 9) {
                headerIdentity
                Spacer(minLength: 4)
                updatingIndicator
                if editingUnavailableReason == nil {
                    editButton
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    headerIdentity
                    Spacer(minLength: 4)
                    updatingIndicator
                }
                if editingUnavailableReason == nil {
                    editButton
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var headerIdentity: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text("Calling points")
                    .font(.caption.weight(.bold))
                Text("\(currentStationNames.count) current stops")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "signpost.right.and.left.fill")
                .foregroundStyle(TycoonTheme.panelAccent)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var updatingIndicator: some View {
        if isUpdating {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Updating station calls")
        }
    }

    private var editButton: some View {
        Button {
            if isEditing {
                finishEditing()
            } else {
                beginEditing()
            }
        } label: {
            Label(
                isEditing ? "Done" : "Edit stops",
                systemImage: isEditing ? "checkmark" : "plus.circle"
            )
            .font(.caption.weight(.bold))
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .disabled(isUpdating)
        .accessibilityHint(
            isEditing
                ? "Finishes editing this service"
                : "Finds eligible intermediate stations that can be added to this service"
        )
    }

    @ViewBuilder
    private var availableStops: some View {
        if currentStationNames.count >= effectiveMaximumStopCount {
            Label(
                "This service has the maximum \(effectiveMaximumStopCount) calling points.",
                systemImage: "checkmark.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else if isUpdating && availableIntermediateStations.isEmpty {
            HStack(spacing: 9) {
                ProgressView()
                    .controlSize(.small)
                Text("Finding stations along this corridor…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
        } else if availableIntermediateStations.isEmpty {
            Label(
                "No additional eligible intermediate stations were found along this corridor.",
                systemImage: "checkmark.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Label {
                    Text(additionDisclosure)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(TycoonTheme.construction)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)

                Text("AVAILABLE ALONG THIS CORRIDOR")
                    .font(.caption2.weight(.black))
                    .tracking(0.55)
                    .foregroundStyle(.secondary)

                ForEach(availableIntermediateStations) { station in
                    stationAdditionRow(station)
                }
            }
        }
    }

    private func stationAdditionRow(_ station: Station) -> some View {
        let price = additionCostPence(station)
        let affordable = gameMode != .career || canAfford(station)

        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(TycoonTheme.panelAccent.opacity(0.14))
                Image(systemName: "mappin.and.ellipse")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TycoonTheme.panelAccent)
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                Text(price.map(formattedPence) ?? "Price unavailable")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(affordable ? Color.secondary : TycoonTheme.construction)
            }

            Spacer(minLength: 4)

            Button("Add") {
                requestAddition(of: station, price: price, affordable: affordable)
            }
            .font(.caption.weight(.bold))
            .buttonStyle(.bordered)
            .frame(minWidth: 58, minHeight: 44)
            .disabled(isUpdating || price == nil || !affordable)
            .accessibilityLabel("Add \(station.name)")
            .accessibilityValue(price.map(formattedPence) ?? "Price unavailable")
            .accessibilityHint(additionAccessibilityHint(station, price: price, affordable: affordable))
        }
        .padding(.leading, 7)
        .padding(.trailing, 3)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 11))
    }

    private var currentStationNames: [String] {
        let stationsByCRS = Dictionary(
            stationCatalog.map { (Self.normalizedCRS($0.crs), $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        let names = line.stationCRSs.map {
            stationsByCRS[Self.normalizedCRS($0)] ?? Self.normalizedCRS($0)
        }
        return names.isEmpty ? [line.origin.name, line.destination.name] : names
    }

    private var effectiveMaximumStopCount: Int { max(maximumStopCount, 2) }

    private var isConfirmingAddition: Binding<Bool> {
        Binding(
            get: { pendingAddition != nil },
            set: { isPresented in
                if !isPresented {
                    pendingAddition = nil
                }
            }
        )
    }

    private var additionDisclosure: String {
        if line.servicePattern == .express {
            return "Adding a stop is permanent. The current all-express timetable will pass it until the service switches to Local or Balanced. Removing stops arrives later."
        }
        return "Adding a stop permanently adds it to local trains on this service. Removing stops arrives in a later milestone."
    }

    private func formattedPence(_ pence: Int64) -> String {
        StopAdditionConfirmationCopy.formattedPence(pence)
    }

    private func requestAddition(
        of station: Station,
        price: Int64?,
        affordable: Bool
    ) {
        guard !isUpdating, affordable, let price else { return }
        pendingAddition = PendingStopAddition(
            station: station,
            copy: StopAdditionConfirmationCopy(station: station, costPence: price)
        )
    }

    private func confirmAddition(_ pendingAddition: PendingStopAddition) {
        guard
            !isUpdating,
            gameMode != .career || canAfford(pendingAddition.station)
        else {
            self.pendingAddition = nil
            return
        }

        self.pendingAddition = nil
        addStation(pendingAddition.station)
    }

    private func additionAccessibilityHint(
        _ station: Station,
        price: Int64?,
        affordable: Bool
    ) -> String {
        if isUpdating { return "Wait while the service updates" }
        if price == nil { return "A construction price is not available" }
        if !affordable { return "Requires more available cash" }
        return "Opens a confirmation before paying to permanently add this station call"
    }

    nonisolated private static func normalizedCRS(_ crs: String) -> String {
        crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

private struct PendingStopAddition {
    let station: Station
    let copy: StopAdditionConfirmationCopy
}

struct StopAdditionConfirmationCopy: Equatable {
    let title: String
    let actionTitle: String
    let message: String

    init(station: Station, costPence: Int64) {
        let price = Self.formattedPence(costPence)
        title = "Add \(station.name) permanently?"
        actionTitle = "Add for \(price)"
        message = "\(price) will be charged immediately to add \(station.name) as a permanent calling point. Removing stops arrives in a later milestone."
    }

    static func formattedPence(_ pence: Int64) -> String {
        (Double(pence) / 100).formatted(
            .currency(code: "GBP").precision(.fractionLength(0))
        )
    }
}
