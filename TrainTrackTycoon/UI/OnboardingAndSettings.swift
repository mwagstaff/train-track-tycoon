import SwiftUI

struct OnboardingOverlay: View {
    let profile: PlayerProfileStore
    let onDismiss: () -> Void
    let onBuildLine: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AccessibilityFocusState private var isStepFocused: Bool
    @State private var step = 0

    private let steps = OnboardingStep.all

    var body: some View {
        ZStack {
            Color.black.opacity(reduceTransparency ? 0.82 : 0.55)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                HStack {
                    Text("QUICK START")
                        .font(.caption.weight(.bold))
                        .tracking(1.3)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Skip") {
                        finishTutorial(shouldBuild: false)
                    }
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityHint("Closes the guide. You can replay it from Settings.")
                }

                ScrollView {
                    VStack(spacing: 24) {
                        ZStack {
                            Circle()
                                .fill(TycoonTheme.railGreen.opacity(0.14))
                                .frame(width: 112, height: 112)

                            Image(systemName: steps[step].symbol)
                                .font(.system(size: 46, weight: .semibold))
                                .foregroundStyle(TycoonTheme.panelAccent)
                        }
                        .accessibilityHidden(true)

                        VStack(spacing: 10) {
                            Text(steps[step].title)
                                .font(.title2.weight(.bold))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.primary)

                            Text(steps[step].detail)
                                .font(.body)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityFocused($isStepFocused)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                }

                VStack(spacing: 16) {
                    HStack(spacing: 8) {
                        ForEach(steps.indices, id: \.self) { index in
                            Capsule()
                                .fill(index == step ? TycoonTheme.panelAccent : .secondary.opacity(0.24))
                                .frame(width: index == step ? 28 : 8, height: 8)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Step \(step + 1) of \(steps.count)")

                    Button {
                        advance()
                    } label: {
                        Label(
                            step == steps.count - 1 ? "Build a line" : "Continue",
                            systemImage: step == steps.count - 1 ? "plus" : "arrow.right"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .foregroundStyle(.white)
                        .background(TycoonTheme.railGreen, in: .rect(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(
                        step == steps.count - 1
                            ? "Closes the guide and opens the line builder."
                            : "Shows the next quick-start step."
                    )
                }
            }
            .padding(24)
            .frame(maxWidth: 430, maxHeight: 570)
            .background(
                reduceTransparency ? AnyShapeStyle(TycoonTheme.opaquePanel) : AnyShapeStyle(.regularMaterial),
                in: .rect(cornerRadius: 30, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(.white.opacity(reduceTransparency ? 0.18 : 0.42), lineWidth: 1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) {
            finishTutorial(shouldBuild: false)
        }
        .onAppear {
            isStepFocused = true
        }
    }

    private func advance() {
        guard step < steps.count - 1 else {
            finishTutorial(shouldBuild: true)
            return
        }

        isStepFocused = false
        if reduceMotion {
            step += 1
        } else {
            withAnimation(.easeInOut(duration: 0.22)) {
                step += 1
            }
        }
        Task { @MainActor in
            await Task.yield()
            isStepFocused = true
        }
    }

    private func finishTutorial(shouldBuild: Bool) {
        profile.setTutorialCompleted(true)
        onDismiss()
        if shouldBuild { onBuildLine() }
    }
}

private struct OnboardingStep: Sendable {
    let symbol: String
    let title: String
    let detail: String

    static let all = [
        OnboardingStep(
            symbol: "map.fill",
            title: "Your railway starts here",
            detail: "Move and zoom the map to explore Britain. Your first goal is simple: connect two stations."
        ),
        OnboardingStep(
            symbol: "pause.fill",
            title: "You control the pace",
            detail: "Pause whenever you want to plan. Change the speed once trains are running and watch each operating day unfold."
        ),
        OnboardingStep(
            symbol: "point.topleft.down.to.point.bottomright.curvepath.fill",
            title: "Build, then watch it come alive",
            detail: "Choose two stations, review the route, and confirm construction. Trains begin running when the line is ready."
        ),
    ]
}

struct PublicBetaSettingsOverlay: View {
    let profile: PlayerProfileStore
    let onDismiss: () -> Void
    let onShowTutorial: () -> Void
    let onShowAchievements: () -> Void
    let onShowScenarios: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack {
            Color.black.opacity(reduceTransparency ? 0.78 : 0.48)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 18) {
                        betaNotice
                        experienceSection
                        progressSection
                        helpSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                }
            }
            .frame(maxWidth: 520, maxHeight: 760)
            .background(
                reduceTransparency ? AnyShapeStyle(TycoonTheme.opaquePanel) : AnyShapeStyle(.regularMaterial),
                in: .rect(cornerRadius: 30, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(.white.opacity(reduceTransparency ? 0.18 : 0.38), lineWidth: 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onDismiss)
    }

    private var header: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Spacer()
                        Button("Done", action: onDismiss)
                            .font(.body.weight(.semibold))
                            .frame(minWidth: 52, minHeight: 44)
                    }
                    Text("Settings")
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("TrainTrack Tycoon")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 12) {
                    RailwayGlyph()

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Settings")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("TrainTrack Tycoon")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Done", action: onDismiss)
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 52, minHeight: 44)
                }
            }
        }
        .padding(20)
    }

    private var betaNotice: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Public beta")
                        .font(.headline)
                    Text("Features and balance may change. Your feedback helps shape the railway.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Public beta")
                            .font(.headline)
                        Text("Features and balance may change. Your feedback helps shape the railway.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "testtube.2")
                        .foregroundStyle(TycoonTheme.panelAccent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(TycoonTheme.railGreen.opacity(0.10), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private var experienceSection: some View {
        SettingsSection(title: "Experience") {
            SettingsToggleRow(
                symbol: "speaker.wave.2.fill",
                title: "Sound",
                detail: "Railway sound effects. Off by default.",
                isOn: Binding(
                    get: { profile.isSoundEnabled },
                    set: profile.setSoundEnabled
                )
            )

            Divider()

            SettingsToggleRow(
                symbol: "sparkles",
                title: "World effects",
                detail: "In-game clock and day/night atmosphere.",
                isOn: Binding(
                    get: { profile.areWorldEffectsEnabled },
                    set: profile.setWorldEffectsEnabled
                )
            )

            Divider()

            SettingsToggleRow(
                symbol: "cloud.rain.fill",
                title: "Weather",
                detail: profile.areWorldEffectsEnabled
                    ? "Show the current condition and cosmetic map weather."
                    : "Turn on world effects to see weather.",
                isOn: Binding(
                    get: { profile.isWeatherEnabled },
                    set: profile.setWeatherEnabled
                )
            )
            .disabled(!profile.areWorldEffectsEnabled)
        }
    }

    private var progressSection: some View {
        SettingsSection(title: "Progress") {
            SettingsActionRow(
                symbol: "trophy.fill",
                title: "Achievements",
                detail: "\(profile.unlockedAchievementIDs.count) unlocked",
                action: onShowAchievements
            )

            Divider()

            SettingsActionRow(
                symbol: "flag.checkered",
                title: "Scenarios",
                detail: "\(profile.completedScenarioIDs.count) complete",
                action: onShowScenarios
            )
        }
    }

    private var helpSection: some View {
        SettingsSection(title: "Help") {
            SettingsActionRow(
                symbol: "graduationcap.fill",
                title: "Replay quick start",
                detail: "Three short steps, then build a line.",
                action: onShowTutorial
            )
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 16)
            .background(.background.opacity(0.58), in: .rect(cornerRadius: 18))
        }
    }
}

private struct SettingsToggleRow: View {
    let symbol: String
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            SettingsRowLabel(symbol: symbol, title: title, detail: detail)
        }
        .tint(TycoonTheme.railGreen)
        .frame(minHeight: 66)
    }
}

private struct SettingsActionRow: View {
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SettingsRowLabel(symbol: symbol, title: title, detail: detail)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens \(title.lowercased()).")
    }
}

private struct SettingsRowLabel: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(TycoonTheme.railGreen)
                .frame(width: 26)
        }
    }
}

#Preview("Onboarding") {
    OnboardingOverlay(
        profile: PlayerProfileStore(),
        onDismiss: {},
        onBuildLine: {}
    )
}

#Preview("Settings") {
    PublicBetaSettingsOverlay(
        profile: PlayerProfileStore(),
        onDismiss: {},
        onShowTutorial: {},
        onShowAchievements: {},
        onShowScenarios: {}
    )
}
