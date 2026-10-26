import Testing
@testable import SmartDPI
import SmartDPICore

struct MenuQuickApplyTests {
    @MainActor @Test func eachRowUsesActualRefreshInsteadOfAnotherRowsDraft() throws {
        let store = makeStore()
        let small = try #require(store.menuResolutionChoices.first { $0.width == 1600 })
        let fullHD = try #require(store.menuResolutionChoices.first { $0.width == 1920 })
        store.selectMenuResolution(id: small.id)
        #expect(store.selectedMode?.refreshRate == 60)
        #expect(store.currentMode?.refreshRate == 75)
        #expect(store.menuMode(for: fullHD)?.refreshRate == 75)

        store.menuRefreshRate = 75
        let preview = try #require(store.menuMode(for: small))
        store.selectMenuResolution(id: small.id)
        #expect(store.selectedRefreshRate == nil)
        #expect(store.menuRefreshRate == 75)
        #expect(store.selectedMode?.matchesConfiguration(of: preview) == true)
    }

    @MainActor @Test func sourceSwitchPreservesSupportedFractionalRefreshPreference() throws {
        let store = makeStore()
        let fullHD = try #require(store.menuResolutionChoices.first { $0.width == 1920 })
        store.useVirtual = true
        store.menuRefreshRate = 59.94
        let preview = try #require(store.menuMode(for: fullHD))
        #expect(preview.refreshRate == 59.94)
        store.selectMenuResolution(id: fullHD.id)
        #expect(!store.useVirtual)
        #expect(store.selectedRefreshRate == 59.94)
        #expect(store.selectedMode?.matchesConfiguration(of: preview) == true)

        store.menuRefreshRate = 60
        #expect(store.menuMode(for: fullHD)?.refreshRate == 60)
    }

    @MainActor @Test func revealingOrdinaryModesDoesNotLoseTheirSupportedRate() throws {
        let store = makeStore()
        let small = try #require(store.menuResolutionChoices.first { $0.width == 1600 })
        let native = try #require(store.menuResolutionChoices.first { !$0.isHiDPI })
        store.selectMenuResolution(id: small.id)
        store.menuRefreshRate = 75
        let preview = try #require(store.menuMode(for: native))
        store.selectMenuResolution(id: native.id)
        #expect(store.showAllModes)
        #expect(store.selectedRefreshRate == 75)
        #expect(store.selectedMode?.matchesConfiguration(of: preview) == true)
    }

    @MainActor @Test func staleDisplayClickCannotSelectIdenticalGeometryOnAnotherScreen() throws {
        let store = makeStore()
        let original = try #require(store.selectedDisplay)
        let native = try #require(store.menuResolutionChoices.first { !$0.isHiDPI })
        let capturedDisplayID = original.id
        store.displays.append(DisplayInfo(id: 20, name: "Second display", isBuiltin: false,
            isMain: false, vendor: 2, product: 2, mirrorSource: 0,
            currentMode: original.currentMode, modes: original.modes))
        store.selectDisplay(id: 20)
        let draft = store.selectedResolutionID
        let preset = try #require(store.presets.first)
        #expect(!store.selectMenuResolution(id: native.id, expectedDisplayID: capturedDisplayID))
        #expect(!store.selectMenuPreset(id: preset.id, expectedDisplayID: capturedDisplayID))
        #expect(store.selectedResolutionID == draft)
        #expect(!store.showAllModes)
        #expect(!store.useVirtual)
    }

    @MainActor @Test func invalidAndLockedPresetClicksDoNotChangeTheDraft() throws {
        let store = makeStore()
        let preset = try #require(store.presets.first)
        let draft = store.selectedPresetID
        store.selectedRefreshRate = 75
        store.menuRefreshRate = 60
        #expect(!store.selectMenuPreset(id: "removed-preset"))
        store.pendingSeconds = 12
        #expect(!store.selectMenuPreset(id: preset.id))
        store.pendingSeconds = nil
        store.busy = true
        #expect(!store.selectMenuPreset(id: preset.id))
        store.busy = false
        store.activeVirtual = true
        #expect(!store.selectMenuPreset(id: preset.id))
        store.activeVirtual = false
        store.recoveryPending = true
        #expect(!store.selectMenuPreset(id: preset.id))
        #expect(store.selectedPresetID == draft)
        #expect(store.selectedRefreshRate == 75)
        #expect(store.menuRefreshRate == 60)
        #expect(!store.useVirtual)
    }

    @MainActor @Test func compatibilityPresetPreservesAnAvailableRate() throws {
        let store = makeStore()
        let preset = try #require(store.presets.first)
        store.menuRefreshRate = 75
        #expect(store.selectMenuPreset(id: preset.id))
        #expect(store.useVirtual)
        #expect(store.selectedPresetID == preset.id)
        #expect(store.effectiveRefreshRate == 75)
    }

    @MainActor @Test func quickApplyInDemoNeverChangesSelectionOrStartsATrial() async throws {
        let store = makeStore()
        let native = try #require(store.menuResolutionChoices.first { !$0.isHiDPI })
        let preset = try #require(store.presets.first)
        let draft = store.selectedResolutionID
        await store.applyMenuResolution(id: native.id, expectedDisplayID: store.selectedDisplayID)
        await store.applyMenuPreset(id: preset.id, expectedDisplayID: store.selectedDisplayID)
        #expect(store.selectedResolutionID == draft)
        #expect(!store.useVirtual)
        #expect(store.pendingSeconds == nil)
        #expect(!store.busy)
        #expect(!store.activeVirtual)
    }

    @MainActor @Test func recoveryBlocksDisplaySelectionAndManualRateGetsAccurateHelp() {
        let store = makeStore()
        store.selectedRefreshRate = 60
        #expect(store.refreshNote?.contains("60 Hz") == true)
        #expect(store.refreshNote?.contains("自动优先") == false)
        store.recoveryPending = true
        store.selectDisplay(id: 20)
        #expect(store.selectedDisplayID == 10)
    }

    @MainActor @Test func mainWindowDraftCannotResetMenuRefreshPreference() throws {
        let store = makeStore()
        let small = try #require(store.menuResolutionChoices.first { $0.width == 1600 })
        let fullHD = try #require(store.menuResolutionChoices.first { $0.width == 1920 })
        store.menuRefreshRate = 75
        store.selectedResolutionID = small.id
        store.selectedRefreshRate = 60
        store.showAllModes = true // Triggers the same reconciliation used by refresh.
        #expect(store.selectedMode?.refreshRate == 60)
        #expect(store.menuRefreshRate == 75)
        #expect(store.menuMode(for: fullHD)?.refreshRate == 75)
        #expect(store.currentMode?.refreshRate == 75)
    }

    @MainActor @Test func compatibilityPreviewAndSelectionUseTheMenuPreference() throws {
        let store = makeStore()
        let preset = try #require(store.presets.first)
        store.useVirtual = true
        store.selectedRefreshRate = 75
        store.menuRefreshRate = 60
        #expect(store.menuPresetRefreshRate == 60)
        store.selectMenuPreset(id: preset.id)
        #expect(store.effectiveRefreshRate == 60)
        #expect(store.currentMode?.refreshRate == 75)
    }

    @MainActor private func makeStore() -> DisplayStore {
        let native = DisplayMode(modeID: 1, width: 2560, height: 1440, pixelWidth: 2560,
                                 pixelHeight: 1440, refreshRate: 75, isNative: true)
        let modes = [native,
            DisplayMode(modeID: 6, width: 2560, height: 1440, pixelWidth: 2560, pixelHeight: 1440, refreshRate: 60, isNative: true),
            DisplayMode(modeID: 2, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 59.94),
            DisplayMode(modeID: 3, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60),
            DisplayMode(modeID: 4, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 75),
            DisplayMode(modeID: 5, width: 1600, height: 900, pixelWidth: 3200, pixelHeight: 1800, refreshRate: 60)]
        let store = DisplayStore(isDemo: true)
        store.displays = [DisplayInfo(id: 10, name: "Quick mode test display", isBuiltin: false,
            isMain: true, vendor: 1, product: 1, mirrorSource: 0, currentMode: native, modes: modes)]
        store.selectDisplay(id: 10)
        return store
    }
}
