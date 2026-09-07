import SwiftUI

/// A compact, progressively disclosed editor for the stations a new service will call at.
/// The surrounding bottom-controls viewport owns scrolling and keeps map gestures available
/// everywhere outside its bounded portrait panel.
struct PreviewCallingPointsSection: View {
    let origin: Station
    let destination: Station
    let intermediateStations: [Station]
    let selectedStationCRSs: [String]
    let maximumStopCount: Int
    let isUpdatingRoute: Bool
    @Binding var isExpanded: Bool
    let toggleIntermediateStation: (Station) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            selectedRouteSummary

            if isExpanded, !intermediateStations.isEmpty {
                Divider()

                VStack(spacing: 0) {
                    stationRow(origin, kind: .origin)

                    ForEach(intermediateStations) { station in
                        stationRow(station, kind: .intermediate)
                    }

                    stationRow(destination, kind: .destination)
                }

                Text(instructionCopy)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if intermediateStations.isEmpty {
                Label(
                    "No intermediate catalogue stations were found along this corridor.",
                    systemImage: "arrow.right"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(11)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 13))
        .accessibilityElement(children: .contain)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isExpanded)
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 9) {
                headerIdentity
                Spacer(minLength: 4)
                updatingIndicator
                editButton
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    headerIdentity
                    Spacer(minLength: 4)
                    updatingIndicator
                }
                editButton
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var headerIdentity: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text("Calling points")
                    .font(.caption.weight(.bold))
                Text(selectedStopCountLabel)
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
        if isUpdatingRoute {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Updating route")
        }
    }

    @ViewBuilder
    private var editButton: some View {
        if !intermediateStations.isEmpty {
            Button {
                isExpanded.toggle()
            } label: {
                Label(
                    isExpanded ? "Done" : "Edit stops",
                    systemImage: isExpanded ? "checkmark" : "slider.horizontal.3"
                )
                .font(.caption.weight(.bold))
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .accessibilityHint(
                isExpanded
                    ? "Collapses the list of stations"
                    : "Shows intermediate stations in route order"
            )
        }
    }

    private var selectedRouteSummary: some View {
        Text(selectedStations.map(\.name).joined(separator: "  →  "))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Selected calling points in route order")
            .accessibilityValue(selectedStations.map(\.name).joined(separator: ", then "))
    }

    @ViewBuilder
    private func stationRow(_ station: Station, kind: CallingPointKind) -> some View {
        switch kind {
        case .intermediate:
            Button {
                toggleIntermediateStation(station)
            } label: {
                stationRowContent(station, kind: kind)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(isUpdatingRoute || isUnselectedAtLimit(station))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(station.name)
            .accessibilityValue(
                isSelected(station)
                    ? "Selected as stop \(selectedOrdinal(for: station) ?? 0) of \(selectedStations.count)"
                    : "Not selected"
            )
            .accessibilityHint(
                isUpdatingRoute
                    ? "Wait while the route updates"
                    : isUnselectedAtLimit(station)
                        ? "Remove another call before selecting this station"
                    : isSelected(station)
                        ? "Removes this station call"
                        : "Adds this station call"
            )
            .accessibilityAddTraits(isSelected(station) ? .isSelected : [])
        case .origin, .destination:
            stationRowContent(station, kind: kind)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(station.name)
                .accessibilityValue(kind == .origin ? "Starting station, always selected" : "Destination, always selected")
        }
    }

    private func stationRowContent(_ station: Station, kind: CallingPointKind) -> some View {
        HStack(spacing: 10) {
            routeMarker(for: station, kind: kind)

            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                    .font(.subheadline.weight(kind == .intermediate ? .semibold : .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)

                Text(detailLabel(for: station, kind: kind))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if kind == .intermediate {
                Image(systemName: isSelected(station) ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(
                        isSelected(station) ? TycoonTheme.panelAccent : Color.secondary
                    )
                    .accessibilityHidden(true)
            } else {
                Text("FIXED")
                    .font(.caption2.weight(.black))
                    .tracking(0.45)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .background(
            kind == .intermediate && isSelected(station)
                ? TycoonTheme.panelAccent.opacity(0.10)
                : Color.clear,
            in: .rect(cornerRadius: 11, style: .continuous)
        )
    }

    private func routeMarker(for station: Station, kind: CallingPointKind) -> some View {
        ZStack {
            Capsule()
                .fill(TycoonTheme.panelAccent.opacity(0.28))
                .frame(width: 3, height: 54)

            Circle()
                .fill(isSelected(station) || kind != .intermediate ? TycoonTheme.panelAccent : Color.secondary)
                .frame(width: 27, height: 27)

            if let ordinal = selectedOrdinal(for: station) {
                Text(ordinal.formatted())
                    .font(.caption2.weight(.black).monospacedDigit())
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "minus")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 32, height: 54)
        .accessibilityHidden(true)
    }

    private var selectedStopCountLabel: String {
        let count = selectedStations.count
        return "\(count) of \(effectiveMaximumStopCount) stops selected"
    }

    private var effectiveMaximumStopCount: Int { max(maximumStopCount, 2) }

    private var instructionCopy: String {
        if selectedStations.count >= effectiveMaximumStopCount {
            return "This service has the \(effectiveMaximumStopCount)-stop limit. Remove a selected stop to choose another."
        }
        if corridorStations.count > effectiveMaximumStopCount {
            return "Choose up to \(effectiveMaximumStopCount - 2) intermediate stops. Local trains call; express trains pass through. The route updates automatically."
        }
        return "Tap a station to add or remove it. Local trains call at selected stations; express trains pass them. The route updates automatically."
    }

    private var corridorStations: [Station] {
        [origin] + intermediateStations + [destination]
    }

    private var selectedStationSet: Set<String> {
        Set(selectedStationCRSs.map(Self.normalizedCRS))
            .union([Self.normalizedCRS(origin.crs), Self.normalizedCRS(destination.crs)])
    }

    private var selectedStations: [Station] {
        corridorStations.filter(isSelected)
    }

    private func isSelected(_ station: Station) -> Bool {
        selectedStationSet.contains(Self.normalizedCRS(station.crs))
    }

    private func isUnselectedAtLimit(_ station: Station) -> Bool {
        !isSelected(station) && selectedStations.count >= effectiveMaximumStopCount
    }

    private func selectedOrdinal(for station: Station) -> Int? {
        selectedStations.firstIndex {
            Self.normalizedCRS($0.crs) == Self.normalizedCRS(station.crs)
        }.map { $0 + 1 }
    }

    private func detailLabel(for station: Station, kind: CallingPointKind) -> String {
        switch kind {
        case .origin:
            "Start"
        case .destination:
            "Destination"
        case .intermediate:
            if let ordinal = selectedOrdinal(for: station) {
                "Stop \(ordinal) of \(selectedStations.count)"
            } else {
                "Pass without stopping"
            }
        }
    }

    nonisolated private static func normalizedCRS(_ crs: String) -> String {
        crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private enum CallingPointKind: Equatable {
        case origin
        case intermediate
        case destination
    }
}

#Preview("Calling points") {
    PreviewCallingPointsSection(
        origin: Station(
            crs: "VIC",
            name: "London Victoria",
            latitude: 51.4952,
            longitude: -0.1441
        ),
        destination: Station(
            crs: "KTH",
            name: "Kent House",
            latitude: 51.4122,
            longitude: -0.0452
        ),
        intermediateStations: [
            Station(crs: "BRX", name: "Brixton", latitude: 51.4627, longitude: -0.1145),
            Station(crs: "HNH", name: "Herne Hill", latitude: 51.4533, longitude: -0.1025),
        ],
        selectedStationCRSs: ["VIC", "BRX", "KTH"],
        maximumStopCount: 16,
        isUpdatingRoute: false,
        isExpanded: .constant(true),
        toggleIntermediateStation: { _ in }
    )
    .padding()
}
