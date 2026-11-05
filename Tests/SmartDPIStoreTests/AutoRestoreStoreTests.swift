import Foundation
import Testing
@testable import SmartDPI
import SmartDPICore

@Suite struct AutoRestoreStoreTests {
    @MainActor @Test func temporary900pIsReportedAsIncompleteWithoutReplacingKnownPanelOrPreference() throws {
        let (preferences, suite) = try isolatedPreferences()
        defer { preferences.removePersistentDomain(forName: suite) }
        let data = try JSONEncoder().encode([profile().persistentID: profile()])
        preferences.set(data, forKey: "savedHiDPI.v1")
        let store = DisplayStore(preferences: preferences)
        let partial = DisplayMode(modeID: 18, width: 1600, height: 900,
            pixelWidth: 1600, pixelHeight: 900, refreshRate: 60, isNative: true)
        let display = DisplayInfo(id: 4_000_000_001, name: "Degraded fixture", isBuiltin: false,
            isMain: false, vendor: 1, product: 2, mirrorSource: 0, currentMode: partial, modes: [partial],
            persistentID: profile().persistentID)
        store.displays = [display]
        store.selectDisplay(id: display.id)

        #expect(store.panelResolutionDescription == "已记录面板 2560 × 1440")
        #expect(store.displayRecognitionWarning?.contains("识别不完整") == true)
        #expect(store.currentMode?.title == "1600 × 900")
        #expect(!store.isHiDPIEnabled)
        #expect(store.selectedDisplay?.nativeWidth == 1600)
        #expect(preferences.data(forKey: "savedHiDPI.v1") == data)

        installTemporary720p(on: store)
        #expect(store.displayRecognitionWarning == nil)
        #expect(store.panelResolutionDescription == "系统报告 2560 × 1440")
        #expect(preferences.data(forKey: "savedHiDPI.v1") == data)
    }

    @MainActor @Test func unknownPanelDoesNotClaimThatSystemModesArePhysicalHardwareFacts() throws {
        let (preferences, suite) = try isolatedPreferences()
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = DisplayStore(preferences: preferences)
        installTemporary720p(on: store)
        #expect(store.panelResolutionDescription == "系统报告 2560 × 1440")
        #expect(store.displayRecognitionWarning == nil)
    }

    @MainActor @Test func automaticRestoreDefaultsOnAndExplicitOptOutPersists() throws {
        let (preferences, suite) = try isolatedPreferences()
        defer { preferences.removePersistentDomain(forName: suite) }
        let initial = DisplayStore(preferences: preferences)
        #expect(initial.autoRestoreHiDPI)
        initial.setAutoRestoreHiDPI(false)
        let reopened = DisplayStore(preferences: preferences)
        #expect(!reopened.autoRestoreHiDPI)
        #expect(reopened.automaticRestoreDescription.contains("已关闭"))
    }

    @MainActor @Test func reenablingKeepsSaved1080pInsteadOfLearningTransient720p() throws {
        let (preferences, suite) = try isolatedPreferences()
        defer { preferences.removePersistentDomain(forName: suite) }
        let saved = profile()
        preferences.set(try JSONEncoder().encode([saved.persistentID: saved]), forKey: "savedHiDPI.v1")
        preferences.set(false, forKey: "autoRestoreHiDPI")
        let store = DisplayStore(preferences: preferences)
        installTemporary720p(on: store)

        store.setAutoRestoreHiDPI(true)

        let stored = try JSONDecoder().decode([String: SavedHiDPISetting].self,
                                             from: #require(preferences.data(forKey: "savedHiDPI.v1")))
        #expect(stored[saved.persistentID] == saved)
        #expect(store.automaticRestoreDescription.contains("1920 × 1080"))
        #expect(!store.busy && !store.activeVirtual)
    }

    @MainActor @Test func enablingDuringAnUnfinishedChangeDoesNotSaveItsDisplayedMode() throws {
        let (preferences, suite) = try isolatedPreferences()
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(false, forKey: "autoRestoreHiDPI")
        let store = DisplayStore(preferences: preferences)
        installTemporary720p(on: store)
        store.busy = true

        store.setAutoRestoreHiDPI(true)

        #expect(preferences.data(forKey: "savedHiDPI.v1") == nil)
        #expect(store.automaticRestoreDescription.contains("选择一次"))
        store.busy = false
    }

    @MainActor @Test func readingSavedSettingsDoesNotReplaceThemWithCurrent720p() throws {
        let (preferences, suite) = try isolatedPreferences()
        defer { preferences.removePersistentDomain(forName: suite) }
        let data = try JSONEncoder().encode([profile().persistentID: profile()])
        preferences.set(data, forKey: "savedHiDPI.v1")

        let store = DisplayStore(preferences: preferences)
        installTemporary720p(on: store)

        #expect(store.currentMode?.width == 1280)
        #expect(store.automaticRestoreDescription.contains("1920 × 1080"))
        #expect(preferences.data(forKey: "savedHiDPI.v1") == data)
        #expect(!store.busy && !store.activeVirtual && !store.recoveryPending)
    }

    @MainActor @Test func mismatchedPersistentIdentityCannotLoadAnotherDisplaysPreference() throws {
        let (preferences, suite) = try isolatedPreferences()
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(try JSONEncoder().encode([profile().persistentID: profile(key: "other-screen")]),
                        forKey: "savedHiDPI.v1")
        let store = DisplayStore(preferences: preferences)
        installTemporary720p(on: store)

        #expect(store.automaticRestoreDescription.contains("选择一次"))
        #expect(!store.automaticRestoreDescription.contains("1920 × 1080"))
    }

    @MainActor @Test func demoWakeReconnectAndPreferenceActionsCannotTouchRealSettings() throws {
        let (preferences, suite) = try isolatedPreferences()
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(false, forKey: "autoRestoreHiDPI")
        let data = try JSONEncoder().encode([profile().persistentID: profile()])
        preferences.set(data, forKey: "savedHiDPI.v1")
        let store = DisplayStore(isDemo: true, preferences: preferences)
        let before = store.displays

        store.setAutoRestoreHiDPI(true)
        store.startAutomaticRestore()
        store.displaysWillSleep()
        store.displaysDidWake()
        store.displayConnectionChanged(id: 99, removed: true)

        #expect(!store.autoRestoreHiDPI)
        #expect(!preferences.bool(forKey: "autoRestoreHiDPI"))
        #expect(preferences.data(forKey: "savedHiDPI.v1") == data)
        #expect(store.displays == before)
        #expect(!store.busy && !store.activeVirtual && !store.recoveryPending)
    }

    private func isolatedPreferences() throws -> (UserDefaults, String) {
        let suite = "SmartDPI.AutoRestoreTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    private func profile(key: String = "test-physical-screen") -> SavedHiDPISetting {
        SavedHiDPISetting(persistentID: key, width: 1920, height: 1080,
                          refreshRate: nil, nativeWidth: 2560, nativeHeight: 1440)
    }

    @MainActor private func installTemporary720p(on store: DisplayStore) {
        let native = DisplayMode(modeID: 1, width: 2560, height: 1440,
                                 pixelWidth: 2560, pixelHeight: 1440, refreshRate: 75, isNative: true)
        let small = DisplayMode(modeID: 2, width: 1280, height: 720,
                                pixelWidth: 2560, pixelHeight: 1440, refreshRate: 75)
        // A synthetic ID is never used for a display operation. No test opts the
        // non-demo store into its GUI-only automatic scheduler.
        let display = DisplayInfo(id: 4_000_000_001, name: "Reconnect fixture", isBuiltin: false,
                                  isMain: false, vendor: 1, product: 2, mirrorSource: 0,
                                  currentMode: small, modes: [native, small], nativeWidth: 2560,
                                  nativeHeight: 1440, nativeSizeIsEstimated: false,
                                  persistentID: profile().persistentID)
        store.displays = [display]
        store.selectDisplay(id: display.id)
    }
}
