import Charts
import SwiftUI

enum PublicBetaHubSection: String, CaseIterable, Identifiable {
    case achievements
    case scenarios
    case statistics

    var id: Self { self }

    var title: String {
        switch self {
        case .achievements: "Achievements"
        case .scenarios: "Scenarios"
        case .statistics: "Statistics"
        }
    }
}

enum PublicBetaStatisticsSection: String, CaseIterable, Identifiable {
    case overview
    case population

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .population: "Population"
        }
    }
}

struct PublicBetaProgressOverlay: View {
    @Bindable var session: GameSession
    let profile: PlayerProfileStore
    let onDismiss: () -> Void
    let onStartScenario: (PublicBetaScenarioDefinition) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var section: PublicBetaHubSection
    @State private var statisticsSection: PublicBetaStatisticsSection = .overview
    @State private var pendingScenario: PublicBetaScenarioDefinition?

    init(
        session: GameSession,
        profile: PlayerProfileStore,
        initialSection: PublicBetaHubSection = .achievements,
        onDismiss: @escaping () -> Void,
        onStartScenario: @escaping (PublicBetaScenarioDefinition) -> Void
    ) {
        self.session = session
        self.profile = profile
        self.onDismiss = onDismiss
        self.onStartScenario = onStartScenario
        _section = State(initialValue: initialSection)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(reduceTransparency ? 0.80 : 0.50)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                header

                if !dynamicTypeSize.isAccessibilitySize {
                    sectionControl
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if dynamicTypeSize.isAccessibilitySize {
                            sectionControl
                                .padding(.bottom, 14)
                        }

                        Group {
                            switch section {
                            case .achievements:
                                achievementsContent
                            case .scenarios:
                                scenariosContent
                            case .statistics:
                                statisticsContent
                            }
                        }
                        .padding(.horizontal, 18)
                    }
                    .padding(.vertical, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxWidth: 520, maxHeight: 790)
            .background(
                reduceTransparency
                    ? AnyShapeStyle(TycoonTheme.opaquePanel)
                    : AnyShapeStyle(.regularMaterial),
                in: .rect(cornerRadius: 28, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(reduceTransparency ? 0.18 : 0.38), lineWidth: 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onDismiss)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: section)
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
                    Text("Railway progress")
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Public beta goals and network history")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "trophy.fill")
                        .font(.title2)
                        .foregroundStyle(TycoonTheme.construction)
                        .frame(width: 40, height: 40)
                        .background(TycoonTheme.construction.opacity(0.12), in: .circle)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Railway progress")
                            .font(.title2.weight(.bold))
                        Text("Public beta goals and network history")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 4)

                    Button("Done", action: onDismiss)
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 52, minHeight: 44)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var sectionControl: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 6) {
                ForEach(PublicBetaHubSection.allCases) { item in
                    sectionButton(item)
                }
            }
            .padding(.horizontal, 18)
        } else {
            Picker("Progress section", selection: $section) {
                ForEach(PublicBetaHubSection.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 18)
        }
    }

    private func sectionButton(_ item: PublicBetaHubSection) -> some View {
        Button {
            section = item
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        if section == item {
                            Label("Selected", systemImage: "checkmark")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack {
                        Text(item.title)
                            .font(.headline)
                        Spacer()
                        if section == item {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                section == item
                    ? TycoonTheme.railGreen.opacity(0.15)
                    : Color.secondary.opacity(0.07),
                in: .rect(cornerRadius: 12)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(section == item ? .isSelected : [])
    }

    private var achievementsContent: some View {
        let evaluation = PublicBetaAchievementCatalogue.publicBeta.evaluate(
            facts: session.publicBetaFacts,
            previouslyUnlocked: unlockedAchievementIDs
        )

        return VStack(alignment: .leading, spacing: 12) {
            progressSummary(
                title: "\(evaluation.unlockedIDs.count) of \(evaluation.statuses.count) unlocked",
                detail: "Achievements stay unlocked when you start another railway.",
                symbol: "medal.fill"
            )

            ForEach(evaluation.statuses, id: \.definition.id) { status in
                achievementRow(status)
            }
        }
    }

    private func achievementRow(_ status: PublicBetaAchievementStatus) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 3) {
                    Label(
                        status.definition.title,
                        systemImage: status.isUnlocked ? "checkmark.seal.fill" : "lock.circle"
                    )
                    .font(.headline)
                    .foregroundStyle(status.isUnlocked ? TycoonTheme.panelAccent : .primary)
                    Text(status.definition.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(status.isUnlocked ? "DONE" : formatted(status.progress))
                        .font(.caption2.weight(.black).monospacedDigit())
                        .foregroundStyle(status.isUnlocked ? TycoonTheme.panelAccent : .secondary)
                }
            } else {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: status.isUnlocked ? "checkmark.seal.fill" : "lock.circle")
                        .font(.title3)
                        .foregroundStyle(status.isUnlocked ? TycoonTheme.railGreenBright : .secondary)
                        .frame(width: 28)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(status.definition.title)
                            .font(.headline)
                        Text(status.definition.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)

                    Text(status.isUnlocked ? "DONE" : formatted(status.progress))
                        .font(.caption2.weight(.black).monospacedDigit())
                        .foregroundStyle(status.isUnlocked ? TycoonTheme.panelAccent : .secondary)
                }
            }

            ProgressView(value: status.isUnlocked ? 1 : status.progress.fractionComplete)
                .tint(status.isUnlocked ? TycoonTheme.panelAccent : TycoonTheme.construction)
                .accessibilityLabel("Achievement progress")
                .accessibilityValue(status.isUnlocked ? "Completed" : formatted(status.progress))
        }
        .padding(14)
        .background(Color.secondary.opacity(0.075), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var scenariosContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let pendingScenario {
                scenarioConfirmation(pendingScenario)
            } else {
                if let activeScenarioID,
                   let evaluation = PublicBetaScenarioCatalogue.publicBeta.evaluate(
                       scenarioID: activeScenarioID,
                       facts: session.publicBetaFacts
                   ) {
                    progressSummary(
                        title: evaluation.isComplete
                            ? "Scenario complete"
                            : "Active: \(evaluation.scenario.title)",
                        detail: "\(evaluation.completedObjectiveCount) of \(evaluation.objectives.count) objectives complete",
                        symbol: evaluation.isComplete ? "flag.checkered.circle.fill" : "flag.fill"
                    )
                } else {
                    progressSummary(
                        title: "Choose a challenge",
                        detail: "Starting a scenario begins a fresh railway in its recommended mode.",
                        symbol: "flag.checkered"
                    )
                }

                ForEach(PublicBetaScenarioCatalogue.publicBeta.scenarios) { scenario in
                    scenarioCard(scenario)
                }
            }
        }
    }

    private func scenarioCard(_ scenario: PublicBetaScenarioDefinition) -> some View {
        let evaluation = PublicBetaScenarioCatalogue.publicBeta.evaluate(
            scenarioID: scenario.id,
            facts: session.publicBetaFacts
        )
        let isActive = activeScenarioID == scenario.id
        let isComplete = completedScenarioIDs.contains(scenario.id)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isComplete ? "checkmark.flag.fill" : "flag.fill")
                    .font(.title3)
                    .foregroundStyle(isComplete ? TycoonTheme.railGreenBright : TycoonTheme.construction)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(scenario.title)
                            .font(.headline)
                        if isActive {
                            Text("ACTIVE")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(TycoonTheme.railGreen, in: .capsule)
                        }
                    }
                    Text(scenario.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(
                        "Recommended: \(scenario.recommendedMode.title)",
                        systemImage: scenario.recommendedMode == .career
                            ? "sterlingsign.circle"
                            : "infinity.circle"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }

            if isActive, let evaluation {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(evaluation.objectives, id: \.definition.id) { objective in
                        scenarioObjectiveRow(objective)
                    }
                }
            } else if isComplete {
                Label("Completed in an earlier run", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TycoonTheme.panelAccent)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(scenario.objectives) { objective in
                        Label(objective.title, systemImage: "circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if isActive {
                Button("Leave scenario") {
                    profile.clearActiveScenario()
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.bordered)
            } else {
                Button {
                    pendingScenario = scenario
                } label: {
                    Label(isComplete ? "Play again" : "Start scenario", systemImage: "play.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(TycoonTheme.railGreen)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.075), in: .rect(cornerRadius: 16))
    }

    private func scenarioConfirmation(_ scenario: PublicBetaScenarioDefinition) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(TycoonTheme.construction)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Start \(scenario.title)?")
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(
                    "This replaces the current railway and starts a new \(scenario.recommendedMode.title) game. Earned achievements stay unlocked."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 9) {
                Button {
                    onStartScenario(scenario)
                } label: {
                    Text("Start scenario")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(TycoonTheme.railGreen)

                Button("Keep current railway") {
                    pendingScenario = nil
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .background(TycoonTheme.construction.opacity(0.09), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }

    private var statisticsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            statisticsSectionControl

            switch statisticsSection {
            case .overview:
                statisticsOverviewContent
            case .population:
                populationStatisticsContent
            }
        }
    }

    @ViewBuilder
    private var statisticsSectionControl: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 6) {
                ForEach(PublicBetaStatisticsSection.allCases) { item in
                    Button {
                        statisticsSection = item
                    } label: {
                        HStack {
                            Image(
                                systemName: statisticsSection == item
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                            Text(item.title)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(TycoonTheme.railGreen)
                    .accessibilityAddTraits(
                        statisticsSection == item ? .isSelected : []
                    )
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Statistics section")
        } else {
            Picker("Statistics section", selection: $statisticsSection) {
                ForEach(PublicBetaStatisticsSection.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var statisticsOverviewContent: some View {
        let statistics = session.publicBetaHistory.statistics

        return VStack(alignment: .leading, spacing: 12) {
            progressSummary(
                title: statistics.recordedDayCount == 0
                    ? "No operating days recorded yet"
                    : "\(statistics.recordedDayCount) operating days recorded",
                detail: "A bounded 120-day history is saved with this railway.",
                symbol: "chart.xyaxis.line"
            )

            LazyVGrid(columns: statisticColumns, spacing: 10) {
                statisticTile(
                    title: "Peak passengers",
                    value: formattedCount(statistics.peakPassengersPerDay),
                    symbol: "person.2.fill"
                )
                statisticTile(
                    title: "Average happiness",
                    value: formattedBasisPoints(statistics.averageHappinessBasisPoints),
                    symbol: "heart.fill"
                )
                statisticTile(
                    title: "Profitable days",
                    value: "\(statistics.profitableDayCount)",
                    symbol: "sterlingsign.circle.fill"
                )
                statisticTile(
                    title: "Operating result",
                    value: formattedPence(statistics.cumulativeOperatingResultPence),
                    symbol: "plusminus.circle.fill"
                )
                statisticTile(
                    title: "Latest network value",
                    value: formattedPence(statistics.latestNetworkValuePence),
                    symbol: "building.columns.fill"
                )
                statisticTile(
                    title: "Latest prestige",
                    value: "\(statistics.latestPrestigeScore) / 100",
                    symbol: "bolt.shield.fill"
                )
            }

            if let latest = session.publicBetaHistory.latestRecord {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LATEST OPERATING DAY")
                        .font(.caption2.weight(.black))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text("Day \(latest.operatingDay)")
                        .font(.headline)
                    Text(
                        "\(formattedCount(latest.facts.passengersPerDay)) passengers · "
                            + "\(formattedBasisPoints(latest.facts.globalHappinessBasisPoints)) happiness · "
                            + "\(formattedPence(latest.operatingResultPence)) result"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.075), in: .rect(cornerRadius: 16))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var populationStatisticsContent: some View {
        let points = PopulationUIPresentation.historyPoints(
            from: session.publicBetaHistory.records
        )

        return VStack(alignment: .leading, spacing: 12) {
            PopulationSummaryPanel(
                population: session.networkPopulation,
                latestChange: session.latestNetworkPopulationChange
            )

            PopulationTrendPanel(points: points)

            if !points.isEmpty {
                PopulationRecentHistoryPanel(points: Array(points.suffix(5)))
            }
        }
    }

    private func progressSummary(title: String, detail: String, symbol: String) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.headline)
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: symbol)
                        .foregroundStyle(TycoonTheme.panelAccent)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TycoonTheme.railGreen.opacity(0.10), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private func statisticTile(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol)
                .foregroundStyle(TycoonTheme.panelAccent)
                .accessibilityHidden(true)
            if dynamicTypeSize.isAccessibilitySize {
                Text(value)
                    .font(.headline.monospacedDigit())
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(value)
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 106, alignment: .leading)
        .background(Color.secondary.opacity(0.075), in: .rect(cornerRadius: 15))
        .accessibilityElement(children: .combine)
    }

    private var unlockedAchievementIDs: Set<PublicBetaAchievementID> {
        Set(profile.unlockedAchievementIDs.compactMap(achievementID(from:)))
    }

    private var statisticColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }

    @ViewBuilder
    private func scenarioObjectiveRow(
        _ objective: PublicBetaScenarioObjectiveProgress
    ) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text(objective.definition.title)
                        .font(.caption)
                } icon: {
                    Image(
                        systemName: objective.progress.isComplete
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                    .foregroundStyle(
                        objective.progress.isComplete ? TycoonTheme.panelAccent : .secondary
                    )
                }
                Text(formatted(objective.progress))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.leading, 28)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(
                    systemName: objective.progress.isComplete
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .foregroundStyle(
                    objective.progress.isComplete ? TycoonTheme.panelAccent : .secondary
                )
                .accessibilityHidden(true)
                Text(objective.definition.title)
                    .font(.caption)
                Spacer(minLength: 4)
                Text(formatted(objective.progress))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var completedScenarioIDs: Set<PublicBetaScenarioID> {
        Set(profile.completedScenarioIDs.compactMap(scenarioID(from:)))
    }

    private var activeScenarioID: PublicBetaScenarioID? {
        profile.activeScenarioID.flatMap(scenarioID(from:))
    }

    private func achievementID(from storedID: String) -> PublicBetaAchievementID? {
        PublicBetaAchievementID.allCases.first {
            $0.rawValue.caseInsensitiveCompare(storedID) == .orderedSame
        }
    }

    private func scenarioID(from storedID: String) -> PublicBetaScenarioID? {
        PublicBetaScenarioID.allCases.first {
            $0.rawValue.caseInsensitiveCompare(storedID) == .orderedSame
        }
    }

    private func formatted(_ progress: PublicBetaGoalProgress) -> String {
        switch progress.metric {
        case .globalHappinessBasisPoints:
            "\(formattedBasisPoints(Int(progress.currentValue))) / \(formattedBasisPoints(Int(progress.targetValue)))"
        case .networkValuePence:
            "\(formattedPence(progress.currentValue)) / \(formattedPence(progress.targetValue))"
        case .passengersPerDay:
            "\(formattedCount(progress.currentValue)) / \(formattedCount(progress.targetValue))"
        default:
            "\(progress.currentValue.formatted()) / \(progress.targetValue.formatted())"
        }
    }

    private func formattedCount(_ value: Int64) -> String {
        value.formatted(.number.notation(.compactName))
    }

    private func formattedBasisPoints(_ value: Int) -> String {
        (Double(value) / 100).formatted(.number.precision(.fractionLength(0))) + "%"
    }

    private func formattedPence(_ pence: Int64) -> String {
        (Double(pence) / 100).formatted(
            .currency(code: "GBP").notation(.compactName).precision(.fractionLength(0))
        )
    }
}

nonisolated struct PopulationHistoryPoint: Identifiable, Equatable, Sendable {
    let operatingDay: UInt64
    let population: Int64
    let change: Int64

    var id: UInt64 { operatingDay }
}

nonisolated enum PopulationTrendDirection: Equatable, Sendable {
    case growing
    case declining
    case steady
    case unavailable
}

nonisolated enum PopulationUIPresentation {
    static let maximumHistoryCount = 120

    static func historyPoints(
        from records: [PublicBetaDailyNetworkRecord]
    ) -> [PopulationHistoryPoint] {
        records
            // Schema 1–8 history has no population measurement and migrates with zero as an
            // explicit "unknown" sentinel. Do not turn those legacy days into a false collapse
            // and huge first-day jump on the population chart.
            .filter { $0.totalNetworkPopulation > 0 }
            .suffix(maximumHistoryCount)
            .map { record in
                PopulationHistoryPoint(
                    operatingDay: record.operatingDay,
                    population: record.totalNetworkPopulation,
                    change: record.latestPopulationChange
                )
            }
    }

    static func compactPopulation(_ population: Int64) -> String {
        max(population, 0).formatted(.number.notation(.compactName))
    }

    static func fullPopulation(_ population: Int64) -> String {
        max(population, 0).formatted(.number)
    }

    static func compactChange(_ change: Int64) -> String {
        guard change != 0 else { return "No change" }
        let magnitude = change == .min ? Int64.max : abs(change)
        return (change > 0 ? "+" : "−")
            + magnitude.formatted(.number.notation(.compactName))
    }

    static func changeDescription(_ change: Int64) -> String {
        guard change != 0 else { return "No change on the latest operating day" }
        let magnitude = change == .min ? Int64.max : abs(change)
        return change > 0
            ? "Increased by \(magnitude.formatted(.number)) on the latest operating day"
            : "Decreased by \(magnitude.formatted(.number)) on the latest operating day"
    }

    static func changeSymbol(_ change: Int64) -> String {
        if change > 0 { return "arrow.up.right" }
        if change < 0 { return "arrow.down.right" }
        return "arrow.right"
    }

    static func demandMultiplier(_ multiplier: Double) -> String {
        let normalized = multiplier.isFinite && multiplier > 0 ? multiplier : 1
        return normalized.formatted(
            .number.precision(.fractionLength(2))
        ) + "×"
    }

    static func trendDirection(_ points: [PopulationHistoryPoint]) -> PopulationTrendDirection {
        guard let first = points.first, let last = points.last, points.count > 1 else {
            return .unavailable
        }
        if last.population > first.population { return .growing }
        if last.population < first.population { return .declining }
        return .steady
    }

    static func trendSummary(_ points: [PopulationHistoryPoint]) -> String {
        guard let first = points.first, let last = points.last else {
            return "Population history begins after the first operating day."
        }
        guard points.count > 1 else {
            return "One operating day of population history recorded."
        }

        let difference = last.population - first.population
        if difference > 0 {
            return "Up \(difference.formatted(.number)) across \(points.count) recorded days."
        }
        if difference < 0 {
            let magnitude = difference == .min ? Int64.max : abs(difference)
            return "Down \(magnitude.formatted(.number)) across \(points.count) recorded days."
        }
        return "No net change across \(points.count) recorded days."
    }

    static func chartDomain(_ points: [PopulationHistoryPoint]) -> ClosedRange<Int64> {
        guard let minimum = points.map(\.population).min(),
              let maximum = points.map(\.population).max() else {
            return 0...1
        }
        let span = max(maximum - minimum, 1)
        let padding = max(span / 8, 1)
        return max(minimum - padding, 0)...max(maximum + padding, 1)
    }
}

struct PopulationSummaryPanel: View {
    let population: Int64
    let latestChange: Int64

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Synthetic gameplay population", systemImage: "house.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(TycoonTheme.panelAccent)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        populationValue
                        changeLabel
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        populationValue
                        Spacer(minLength: 4)
                        changeLabel
                    }
                }
            }

            Text(
                "A synthetic planning measure shaped by railway accessibility, "
                    + "not a real-world population estimate."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TycoonTheme.railGreen.opacity(0.10), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Synthetic gameplay population")
        .accessibilityValue(
            "\(PopulationUIPresentation.fullPopulation(population)). "
                + PopulationUIPresentation.changeDescription(latestChange)
        )
    }

    private var populationValue: some View {
        Text(PopulationUIPresentation.fullPopulation(population))
            .font(.title2.weight(.black).monospacedDigit())
            .minimumScaleFactor(0.72)
    }

    private var changeLabel: some View {
        Label(
            PopulationUIPresentation.compactChange(latestChange),
            systemImage: PopulationUIPresentation.changeSymbol(latestChange)
        )
        .font(.caption.weight(.bold).monospacedDigit())
        .foregroundStyle(latestChange < 0 ? Color.orange : TycoonTheme.panelAccent)
    }
}

struct PopulationTrendPanel: View {
    let points: [PopulationHistoryPoint]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Population trend", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.subheadline.weight(.bold))
                Spacer(minLength: 4)
                Text("\(points.count) of 120 days")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if points.isEmpty {
                Text(PopulationUIPresentation.trendSummary(points))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
            } else {
                Chart(points) { point in
                    LineMark(
                        x: .value("Operating day", point.operatingDay),
                        y: .value("Synthetic population", point.population)
                    )
                    .foregroundStyle(TycoonTheme.panelAccent)
                    .interpolationMethod(.monotone)

                    AreaMark(
                        x: .value("Operating day", point.operatingDay),
                        yStart: .value(
                            "Chart baseline",
                            PopulationUIPresentation.chartDomain(points).lowerBound
                        ),
                        yEnd: .value("Synthetic population", point.population)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [
                                TycoonTheme.panelAccent.opacity(0.20),
                                TycoonTheme.panelAccent.opacity(0.02),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    if point.id == points.last?.id {
                        PointMark(
                            x: .value("Operating day", point.operatingDay),
                            y: .value("Synthetic population", point.population)
                        )
                        .foregroundStyle(TycoonTheme.panelAccent)
                        .symbolSize(42)
                    }
                }
                .chartYScale(domain: PopulationUIPresentation.chartDomain(points))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(Color.secondary.opacity(0.12))
                        AxisValueLabel {
                            if let day = value.as(UInt64.self) {
                                Text("Day \(day)")
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(Color.secondary.opacity(0.16))
                        AxisValueLabel {
                            if let population = value.as(Int64.self) {
                                Text(PopulationUIPresentation.compactPopulation(population))
                            }
                        }
                    }
                }
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 190 : 150)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Synthetic gameplay population trend")
                .accessibilityValue(PopulationUIPresentation.trendSummary(points))

                Text(PopulationUIPresentation.trendSummary(points))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.075), in: .rect(cornerRadius: 16))
    }
}

struct PopulationRecentHistoryPanel: View {
    let points: [PopulationHistoryPoint]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENT OPERATING DAYS")
                .font(.caption2.weight(.black))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            ForEach(points.reversed()) { point in
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Day \(point.operatingDay)")
                                .font(.caption.weight(.bold))
                            Text(
                                "\(PopulationUIPresentation.fullPopulation(point.population)) "
                                    + "synthetic population · "
                                    + PopulationUIPresentation.compactChange(point.change)
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Day \(point.operatingDay)")
                                .font(.caption.weight(.bold))
                            Spacer(minLength: 4)
                            Text(PopulationUIPresentation.fullPopulation(point.population))
                                .font(.caption.weight(.semibold).monospacedDigit())
                            Label(
                                PopulationUIPresentation.compactChange(point.change),
                                systemImage: PopulationUIPresentation.changeSymbol(point.change)
                            )
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Operating day \(point.operatingDay)")
                .accessibilityValue(
                    "\(PopulationUIPresentation.fullPopulation(point.population)) synthetic "
                        + "gameplay population. "
                        + PopulationUIPresentation.changeDescription(point.change)
                )

                if point.id != points.first?.id {
                    Divider()
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.075), in: .rect(cornerRadius: 16))
    }
}

struct AchievementUnlockedBanner: View {
    let achievement: PublicBetaAchievementDefinition
    let dismiss: () -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "trophy.fill")
                .font(.title2)
                .foregroundStyle(TycoonTheme.construction)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("ACHIEVEMENT UNLOCKED")
                    .font(.caption2.weight(.black))
                    .tracking(0.6)
                    .foregroundStyle(TycoonTheme.panelAccent)
                Text(achievement.title)
                    .font(.subheadline.weight(.bold))
                Text(achievement.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss achievement")
        }
        .padding(.leading, 14)
        .padding(.trailing, 5)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .railPanel(cornerRadius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Achievement unlocked. \(achievement.title). \(achievement.summary)")
        .task(id: achievement.id) {
            guard !voiceOverEnabled else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }
}

struct ScenarioCompletedBanner: View {
    let scenario: PublicBetaScenarioDefinition
    let dismiss: () -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "flag.checkered.circle.fill")
                .font(.title2)
                .foregroundStyle(TycoonTheme.construction)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("SCENARIO COMPLETE")
                    .font(.caption2.weight(.black))
                    .tracking(0.6)
                    .foregroundStyle(TycoonTheme.panelAccent)
                Text(scenario.title)
                    .font(.subheadline.weight(.bold))
                Text("All objectives completed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss scenario completion")
        }
        .padding(.leading, 14)
        .padding(.trailing, 5)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .railPanel(cornerRadius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scenario complete. \(scenario.title). All objectives completed.")
        .task(id: scenario.id) {
            guard !voiceOverEnabled else { return }
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }
}
