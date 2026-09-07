import SwiftUI

/// A map-first shortcut for adding a real catalogue station to infrastructure already beneath it.
/// Exact OSM anchoring, affordability, and atomic mutation remain owned by `GameSession`.
struct MapStationAdditionOverlay: View {
    let proposal: MapStationAdditionProposal
    let isLoading: Bool
    let confirm: (UUID) -> Void
    let cancel: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var isHeadingFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(reduceTransparency ? 0.76 : 0.52)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            ScrollView {
                VStack(spacing: 16) {
                    header

                    if isLoading {
                        loadingContent
                    } else if proposal.options.isEmpty {
                        unavailableContent
                    } else {
                        optionContent
                    }

                    Button("Cancel", action: cancel)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .buttonStyle(.bordered)
                }
                .padding(dynamicTypeSize.isAccessibilitySize ? 18 : 22)
            }
            .frame(maxWidth: 390)
            .frame(maxHeight: dynamicTypeSize.isAccessibilitySize ? 680 : 620)
            .scrollBounceBehavior(.basedOnSize)
            .background(
                reduceTransparency
                    ? AnyShapeStyle(TycoonTheme.opaquePanel)
                    : AnyShapeStyle(.regularMaterial),
                in: .rect(cornerRadius: 26, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(.white.opacity(reduceTransparency ? 0.18 : 0.38), lineWidth: 1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .accessibilityAction(.escape, cancel)
        .onAppear { isHeadingFocused = true }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "mappin.and.ellipse")
                .font(.title2.weight(.semibold))
                .foregroundStyle(TycoonTheme.panelAccent)
                .frame(width: 44, height: 44)
                .background(TycoonTheme.railGreen.opacity(0.16), in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("ADD A CALLING POINT")
                    .font(.caption2.weight(.black))
                    .tracking(0.7)
                    .foregroundStyle(TycoonTheme.panelAccent)
                Text(proposal.station.name)
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Choose the service that should call here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityFocused($isHeadingFocused)

            Spacer(minLength: 0)

            Button(action: cancel) {
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close add calling point")
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.large)
            Text("Checking the railway path…")
                .font(.headline)
            Text("Confirming that this station has a valid OSM anchor on the nearby line.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .padding(16)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private var unavailableContent: some View {
        VStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(TycoonTheme.construction)
                .accessibilityHidden(true)
            Text("This station cannot be added here")
                .font(.headline)
            Text(
                "No nearby conventional service has a valid direct railway anchor for "
                    + "\(proposal.station.name)."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private var optionContent: some View {
        VStack(spacing: 10) {
            ForEach(proposal.options) { option in
                optionButton(option)
            }
        }
    }

    private func optionButton(_ option: MapStationAdditionOption) -> some View {
        Button {
            confirm(option.lineID)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(option.lineNumber)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            TycoonTheme.lineColor(for: max(option.lineNumber - 1, 0)),
                            in: .circle
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.lineName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("\(option.servicePattern.name) service")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 4)

                    Text(formattedPence(option.costPence))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(option.isAffordable ? TycoonTheme.panelAccent : .secondary)
                }

                Text(option.resultingStationNames.joined(separator: "  →  "))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(serviceEffect(for: option.servicePattern))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !option.isAffordable {
                    Label("More funds are needed", systemImage: "sterlingsign.circle")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TycoonTheme.construction)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.09), in: .rect(cornerRadius: 17))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(
                        option.isAffordable
                            ? TycoonTheme.panelAccent.opacity(0.48)
                            : Color.secondary.opacity(0.22),
                        lineWidth: 1
                    )
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!option.isAffordable)
        .accessibilityLabel(
            "Add \(proposal.station.name) to line \(option.lineNumber), \(option.lineName)"
        )
        .accessibilityValue(
            "\(formattedPence(option.costPence)). "
                + option.resultingStationNames.joined(separator: ", then ")
        )
        .accessibilityHint(
            option.isAffordable
                ? "Adds the station and updates this service"
                : "Unavailable because more funds are needed"
        )
    }

    private func serviceEffect(for pattern: ServicePattern) -> String {
        switch pattern {
        case .local:
            "All local trains will call here."
        case .balanced:
            "Local trains will call here; express trains will pass through."
        case .express:
            "The station will be built, but current express trains will pass through until their stops are edited."
        }
    }

    private func formattedPence(_ pence: Int64) -> String {
        (Double(max(pence, 0)) / 100).formatted(
            .currency(code: "GBP").notation(.compactName).precision(.fractionLength(0))
        )
    }
}
