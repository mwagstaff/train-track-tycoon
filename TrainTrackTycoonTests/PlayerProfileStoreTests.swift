import Foundation
import Testing
@testable import TrainTrackTycoon

@Suite("Player profile store", .serialized)
@MainActor
struct PlayerProfileStoreTests {
    @Test("Defaults are beta-safe and persist as one versioned value")
    func defaultProfile() throws {
        let fixture = makeFixture()
        defer { fixture.remove() }

        let store = PlayerProfileStore(defaults: fixture.defaults, storageKey: fixture.key)

        #expect(!store.hasCompletedTutorial)
        #expect(!store.isSoundEnabled)
        #expect(store.areWorldEffectsEnabled)
        #expect(store.isWeatherEnabled)
        #expect(store.preferredDifficultyID == "standard")
        #expect(store.activeScenarioID == nil)

        let data = try #require(fixture.defaults.data(forKey: fixture.key))
        let saved = try JSONDecoder().decode(PlayerProfile.self, from: data)
        #expect(saved == store.profile)
        #expect(saved.schemaVersion == PlayerProfile.currentSchemaVersion)
    }

    @Test("Every mutation is immediately visible to a fresh owner")
    func immediatePersistence() {
        let fixture = makeFixture()
        defer { fixture.remove() }

        let store = PlayerProfileStore(defaults: fixture.defaults, storageKey: fixture.key)
        store.setTutorialCompleted(true)
        store.setSoundEnabled(true)
        store.setWorldEffectsEnabled(false)
        store.setWeatherEnabled(false)
        store.unlockAchievement(id: "network.first-line")
        store.markScenarioCompleted(id: "scenario.south-coast")
        store.setPreferredDifficulty(id: "challenging")
        store.setActiveScenario(id: "scenario.city-link")

        let reloaded = PlayerProfileStore(defaults: fixture.defaults, storageKey: fixture.key)
        #expect(reloaded.hasCompletedTutorial)
        #expect(reloaded.isSoundEnabled)
        #expect(!reloaded.areWorldEffectsEnabled)
        #expect(!reloaded.isWeatherEnabled)
        #expect(reloaded.unlockedAchievementIDs == ["network.first-line"])
        #expect(reloaded.completedScenarioIDs == ["scenario.south-coast"])
        #expect(reloaded.preferredDifficultyID == "challenging")
        #expect(reloaded.activeScenarioID == "scenario.city-link")
    }

    @Test("Identifiers are normalized, deduplicated, bounded, and stable")
    func identifierNormalization() {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let store = PlayerProfileStore(defaults: fixture.defaults, storageKey: fixture.key)

        store.unlockAchievement(id: "  NETWORK.First-Line  ")
        store.unlockAchievement(id: "network.first-line")
        store.unlockAchievement(id: "   ")
        store.markScenarioCompleted(id: " ZETA ")
        store.markScenarioCompleted(id: "alpha")
        store.markScenarioCompleted(id: "ALPHA")
        store.setPreferredDifficulty(id: "   ")
        store.setActiveScenario(id: " CITY.LINK ")

        #expect(store.unlockedAchievementIDs == ["network.first-line"])
        #expect(store.completedScenarioIDs == ["alpha", "zeta"])
        #expect(store.preferredDifficultyID == PlayerProfile.defaultDifficultyID)
        #expect(store.activeScenarioID == "city.link")
    }

    @Test("Identifier storage has hard collection and length limits")
    func identifierBounds() {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let store = PlayerProfileStore(defaults: fixture.defaults, storageKey: fixture.key)

        for index in 0..<(PlayerProfileStore.maximumStoredIDs + 20) {
            store.unlockAchievement(id: "achievement.\(index)")
        }
        store.setActiveScenario(id: String(repeating: "x", count: 200))

        #expect(store.unlockedAchievementIDs.count == PlayerProfileStore.maximumStoredIDs)
        #expect(store.activeScenarioID?.count == PlayerProfileStore.maximumIDLength)
    }

    @Test("Corrupt and future data fall back without escaping the bad payload")
    func corruptFallback() throws {
        for data in [
            Data("not-json".utf8),
            try JSONEncoder().encode(PlayerProfile(schemaVersion: 999, isSoundEnabled: true)),
        ] {
            let fixture = makeFixture()
            defer { fixture.remove() }
            fixture.defaults.set(data, forKey: fixture.key)

            let store = PlayerProfileStore(defaults: fixture.defaults, storageKey: fixture.key)

            #expect(store.profile == .defaults)
            let repairedData = try #require(fixture.defaults.data(forKey: fixture.key))
            #expect(try JSONDecoder().decode(PlayerProfile.self, from: repairedData) == .defaults)
        }
    }

    @Test("Profile progress is independent of saved-game lifecycle")
    func crossGameProgressRemains() {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let store = PlayerProfileStore(defaults: fixture.defaults, storageKey: fixture.key)
        store.setTutorialCompleted(true)
        store.unlockAchievement(id: "career.profitable")
        store.markScenarioCompleted(id: "scenario.city-link")

        // A new-game flow has no profile reset API. Recreating its owner preserves progress.
        let afterNewGame = PlayerProfileStore(
            defaults: fixture.defaults,
            storageKey: fixture.key
        )
        #expect(afterNewGame.hasCompletedTutorial)
        #expect(afterNewGame.unlockedAchievementIDs == ["career.profitable"])
        #expect(afterNewGame.completedScenarioIDs == ["scenario.city-link"])
    }

    private func makeFixture() -> Fixture {
        let suiteName = "PlayerProfileStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return Fixture(suiteName: suiteName, defaults: defaults, key: "profile")
    }

    private struct Fixture {
        let suiteName: String
        let defaults: UserDefaults
        let key: String

        func remove() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}
