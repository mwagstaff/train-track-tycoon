import Foundation
import Observation

/// Cross-game preferences and progression. This deliberately lives outside the saved-game
/// slot so starting a new railway never erases tutorial choices or earned progress.
nonisolated struct PlayerProfile: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let defaultDifficultyID = "standard"

    var schemaVersion: Int
    var hasCompletedTutorial: Bool
    var isSoundEnabled: Bool
    var areWorldEffectsEnabled: Bool
    var isWeatherEnabled: Bool
    var unlockedAchievementIDs: [String]
    var completedScenarioIDs: [String]
    var preferredDifficultyID: String
    var activeScenarioID: String?

    static let defaults = PlayerProfile(
        schemaVersion: currentSchemaVersion,
        hasCompletedTutorial: false,
        isSoundEnabled: false,
        areWorldEffectsEnabled: true,
        isWeatherEnabled: true,
        unlockedAchievementIDs: [],
        completedScenarioIDs: [],
        preferredDifficultyID: defaultDifficultyID,
        activeScenarioID: nil
    )

    init(
        schemaVersion: Int = currentSchemaVersion,
        hasCompletedTutorial: Bool = false,
        isSoundEnabled: Bool = false,
        areWorldEffectsEnabled: Bool = true,
        isWeatherEnabled: Bool = true,
        unlockedAchievementIDs: [String] = [],
        completedScenarioIDs: [String] = [],
        preferredDifficultyID: String = defaultDifficultyID,
        activeScenarioID: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.hasCompletedTutorial = hasCompletedTutorial
        self.isSoundEnabled = isSoundEnabled
        self.areWorldEffectsEnabled = areWorldEffectsEnabled
        self.isWeatherEnabled = isWeatherEnabled
        self.unlockedAchievementIDs = unlockedAchievementIDs
        self.completedScenarioIDs = completedScenarioIDs
        self.preferredDifficultyID = preferredDifficultyID
        self.activeScenarioID = activeScenarioID
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case hasCompletedTutorial
        case isSoundEnabled
        case areWorldEffectsEnabled
        case isWeatherEnabled
        case unlockedAchievementIDs
        case completedScenarioIDs
        case preferredDifficultyID
        case activeScenarioID
    }

    /// Defaults on missing fields make schema-one profiles tolerant of partial beta builds.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        hasCompletedTutorial = try values.decodeIfPresent(
            Bool.self,
            forKey: .hasCompletedTutorial
        ) ?? false
        isSoundEnabled = try values.decodeIfPresent(Bool.self, forKey: .isSoundEnabled) ?? false
        areWorldEffectsEnabled = try values.decodeIfPresent(
            Bool.self,
            forKey: .areWorldEffectsEnabled
        ) ?? true
        isWeatherEnabled = try values.decodeIfPresent(
            Bool.self,
            forKey: .isWeatherEnabled
        ) ?? true
        unlockedAchievementIDs = try values.decodeIfPresent(
            [String].self,
            forKey: .unlockedAchievementIDs
        ) ?? []
        completedScenarioIDs = try values.decodeIfPresent(
            [String].self,
            forKey: .completedScenarioIDs
        ) ?? []
        preferredDifficultyID = try values.decodeIfPresent(
            String.self,
            forKey: .preferredDifficultyID
        ) ?? Self.defaultDifficultyID
        activeScenarioID = try values.decodeIfPresent(String.self, forKey: .activeScenarioID)
    }
}

@MainActor
@Observable
final class PlayerProfileStore {
    nonisolated static let defaultStorageKey = "com.traintracktycoon.player-profile"
    nonisolated static let maximumStoredIDs = 256
    nonisolated static let maximumIDLength = 96

    private let defaults: UserDefaults
    private let storageKey: String

    private(set) var profile: PlayerProfile

    var hasCompletedTutorial: Bool { profile.hasCompletedTutorial }
    var isSoundEnabled: Bool { profile.isSoundEnabled }
    var areWorldEffectsEnabled: Bool { profile.areWorldEffectsEnabled }
    var isWeatherEnabled: Bool { profile.isWeatherEnabled }
    var unlockedAchievementIDs: [String] { profile.unlockedAchievementIDs }
    var completedScenarioIDs: [String] { profile.completedScenarioIDs }
    var preferredDifficultyID: String { profile.preferredDifficultyID }
    var activeScenarioID: String? { profile.activeScenarioID }

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = PlayerProfileStore.defaultStorageKey
    ) {
        self.defaults = defaults
        self.storageKey = storageKey

        let loadedProfile: PlayerProfile?
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(PlayerProfile.self, from: data),
           decoded.schemaVersion <= PlayerProfile.currentSchemaVersion,
           decoded.schemaVersion > 0 {
            loadedProfile = decoded
        } else {
            loadedProfile = nil
        }

        profile = Self.normalized(loadedProfile ?? .defaults)

        // Replace damaged, partial, or old data with one normalized blob. A single UserDefaults
        // value prevents readers from observing a half-updated collection of preferences.
        persist()
    }

    func setTutorialCompleted(_ isCompleted: Bool) {
        mutate { $0.hasCompletedTutorial = isCompleted }
    }

    func setSoundEnabled(_ isEnabled: Bool) {
        mutate { $0.isSoundEnabled = isEnabled }
    }

    func setWorldEffectsEnabled(_ isEnabled: Bool) {
        mutate { $0.areWorldEffectsEnabled = isEnabled }
    }

    func setWeatherEnabled(_ isEnabled: Bool) {
        mutate { $0.isWeatherEnabled = isEnabled }
    }

    func unlockAchievement(id: String) {
        mutate { $0.unlockedAchievementIDs.append(id) }
    }

    func markScenarioCompleted(id: String) {
        mutate { $0.completedScenarioIDs.append(id) }
    }

    func setPreferredDifficulty(id: String) {
        mutate { $0.preferredDifficultyID = id }
    }

    func setActiveScenario(id: String?) {
        mutate { $0.activeScenarioID = id }
    }

    func clearActiveScenario() {
        setActiveScenario(id: nil)
    }

    private func mutate(_ update: (inout PlayerProfile) -> Void) {
        var updated = profile
        update(&updated)
        profile = Self.normalized(updated)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private nonisolated static func normalized(_ profile: PlayerProfile) -> PlayerProfile {
        var result = profile
        result.schemaVersion = PlayerProfile.currentSchemaVersion
        result.unlockedAchievementIDs = normalizedIDs(profile.unlockedAchievementIDs)
        result.completedScenarioIDs = normalizedIDs(profile.completedScenarioIDs)
        result.preferredDifficultyID = normalizedID(profile.preferredDifficultyID)
            ?? PlayerProfile.defaultDifficultyID
        result.activeScenarioID = profile.activeScenarioID.flatMap(normalizedID)
        return result
    }

    private nonisolated static func normalizedIDs(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        result.reserveCapacity(min(values.count, maximumStoredIDs))

        for value in values {
            guard let normalized = normalizedID(value), seen.insert(normalized).inserted else {
                continue
            }
            result.append(normalized)
            if result.count == maximumStoredIDs { break }
        }
        return result.sorted()
    }

    private nonisolated static func normalizedID(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumIDLength))
    }
}
