import Testing
@testable import SmartDPI
import SmartDPICore

struct DisplayStoreTests {
    @MainActor @Test
    func changingResolutionClearsUnsupportedManualRefreshRate() throws {
        let native75 = mode(1, width: 2560, height: 1440, rate: 75, native: true)
        let native60 = mode(2, width: 2560, height: 1440, rate: 60, native: true)
        let hiDPI60 = mode(3, width: 1920, height: 1080, rate: 60, hiDPI: true)
        let display = fixture(id: 100, current: native75, modes: [native75, native60, hiDPI60])
        let store = DisplayStore(isDemo: true)
        store.displays = [display]
        store.showAllModes = true
        store.selectDisplay(id: display.id)
        let native = try #require(store.resolutionChoices.first { $0.isNative })
        let hiDPI = try #require(store.resolutionChoices.first { $0.isHiDPI })

        store.selectedResolutionID = native.id
        store.selectedRefreshRate = 75
        #expect(store.effectiveRefreshRate == 75)

        store.selectedResolutionID = hiDPI.id

        #expect(store.selectedRefreshRate == nil)
        #expect(store.refreshRates == [60])
        #expect(store.effectiveRefreshRate == 60)
        #expect(store.selectedMode?.id == hiDPI60.id)
        #expect(store.refreshNote?.contains("75 Hz") == true)
    }

    @MainActor @Test
    func automaticRatePreserves5994AndExplicit60SelectsItsOwnMode() throws {
        let native = mode(10, width: 2560, height: 1440, rate: 59.94, native: true)
        let hiDPI5994 = mode(11, width: 1920, height: 1080, rate: 59.94, hiDPI: true)
        let hiDPI60 = mode(12, width: 1920, height: 1080, rate: 60, hiDPI: true)
        let display = fixture(id: 110, current: native, modes: [native, hiDPI5994, hiDPI60])
        let store = DisplayStore(isDemo: true)
        store.displays = [display]
        store.selectDisplay(id: display.id)
        let choice = try #require(store.resolutionChoices.first { $0.isHiDPI })
        store.selectedResolutionID = choice.id

        #expect(Set(store.refreshRates) == Set([59.94, 60]))
        #expect(store.selectedRefreshRate == nil)
        #expect(store.selectedMode?.id == hiDPI5994.id)
        #expect(store.effectiveRefreshRate == 59.94)

        store.selectedRefreshRate = 60
        #expect(store.selectedMode?.id == hiDPI60.id)
        #expect(store.effectiveRefreshRate == 60)

        store.selectedRefreshRate = nil
        #expect(store.selectedMode?.id == hiDPI5994.id)
        #expect(store.effectiveRefreshRate == 59.94)
    }

    @MainActor @Test
    func compatibilityRatesUseObservedPanelTimings() {
        let native75 = mode(20, width: 2560, height: 1440, rate: 75, native: true)
        let native120 = mode(21, width: 2560, height: 1440, rate: 120, native: true)
        let hiDPI60 = mode(22, width: 1920, height: 1080, rate: 60, hiDPI: true)
        let display = fixture(id: 120, current: native75, modes: [native75, native120, hiDPI60])
        let store = DisplayStore(isDemo: true)
        store.displays = [display]
        store.selectDisplay(id: display.id)
        store.useVirtual = true

        #expect(store.refreshRates == [120, 75])
        #expect(!store.refreshRates.contains(60))
        #expect(store.selectedRefreshRate == nil)
        #expect(store.effectiveRefreshRate == 75)

        store.selectedRefreshRate = 120
        #expect(store.effectiveRefreshRate == 120)
        store.selectedRefreshRate = nil
        #expect(store.effectiveRefreshRate == 75)
    }

    @MainActor @Test
    func selectingAnotherDisplayReconcilesResolutionRateAndPreset() throws {
        let native2K = mode(30, width: 2560, height: 1440, rate: 75, native: true)
        let hiDPI2K = mode(31, width: 1920, height: 1080, rate: 60, hiDPI: true)
        let first = fixture(id: 130, current: native2K, modes: [native2K, hiDPI2K])
        let native4K = mode(32, width: 3840, height: 2160, rate: 120, native: true)
        let native4K60 = mode(33, width: 3840, height: 2160, rate: 60, native: true)
        let hiDPI4K = mode(34, width: 2560, height: 1440, rate: 60, hiDPI: true)
        let second = fixture(id: 131, current: native4K, modes: [native4K, native4K60, hiDPI4K])
        let store = DisplayStore(isDemo: true)
        store.displays = [first, second]
        store.showAllModes = true
        store.selectDisplay(id: first.id)
        let previousChoice = try #require(store.resolutionChoices.first { $0.isHiDPI })
        store.selectedResolutionID = previousChoice.id
        store.selectedRefreshRate = 60
        store.selectedPresetID = "1280x720"

        store.selectDisplay(id: second.id)

        #expect(store.selectedDisplayID == second.id)
        #expect(store.selectedResolutionID != previousChoice.id)
        #expect(store.selectedResolution?.width == 3840)
        #expect(store.selectedResolution?.height == 2160)
        #expect(store.selectedResolution?.isNative == true)
        #expect(store.selectedMode?.id == native4K.id)
        #expect(store.selectedRefreshRate == nil)
        #expect(store.effectiveRefreshRate == 120)
        #expect(store.selectedPresetID == "2560x1440")
        #expect(store.selectedPreset?.width == 2560)
    }

    @MainActor @Test
    func hiDPIStatusReflectsCurrentModeInsteadOfPreviewSelection() throws {
        let native = mode(40, width: 2560, height: 1440, rate: 75, native: true)
        let hiDPI = mode(41, width: 1920, height: 1080, rate: 60, hiDPI: true)
        let ordinaryDisplay = fixture(id: 140, current: native, modes: [native, hiDPI])
        let enabledDisplay = fixture(id: 141, current: hiDPI, modes: [native, hiDPI])
        let store = DisplayStore(isDemo: true)
        store.displays = [ordinaryDisplay, enabledDisplay]
        store.showAllModes = true
        store.selectDisplay(id: ordinaryDisplay.id)
        let hiDPIChoice = try #require(store.resolutionChoices.first { $0.isHiDPI })
        store.selectedResolutionID = hiDPIChoice.id

        #expect(store.selectedMode?.isHiDPI == true)
        #expect(!store.isHiDPIEnabled)

        store.selectDisplay(id: enabledDisplay.id)
        let ordinaryChoice = try #require(store.resolutionChoices.first { !$0.isHiDPI })
        store.selectedResolutionID = ordinaryChoice.id

        #expect(store.selectedMode?.isHiDPI == false)
        #expect(store.isHiDPIEnabled)
    }

    @MainActor @Test
    func demoDisablesNativeAndCompatibilityDisplayChanges() throws {
        let store = DisplayStore(isDemo: true)
        let hiDPI = try #require(store.resolutionChoices.first { $0.isHiDPI })
        store.selectedResolutionID = hiDPI.id

        #expect(store.isDemo)
        #expect(store.selectedMode?.isHiDPI == true)
        #expect(!store.isHiDPIEnabled)
        #expect(!store.canApply)
        #expect(!store.canEnableHiDPI)

        store.useVirtual = true
        #expect(store.selectedPreset != nil)
        #expect(store.effectiveRefreshRate != nil)
        #expect(!store.canApply)
        #expect(!store.canEnableHiDPI)
    }

    private func mode(_ id: UInt32, width: Int, height: Int, rate: Double,
                      hiDPI: Bool = false, native: Bool = false) -> DisplayMode {
        DisplayMode(modeID: id, width: width, height: height,
                    pixelWidth: width * (hiDPI ? 2 : 1),
                    pixelHeight: height * (hiDPI ? 2 : 1),
                    refreshRate: rate, isNative: native)
    }

    private func fixture(id: UInt32, current: DisplayMode, modes: [DisplayMode]) -> DisplayInfo {
        DisplayInfo(id: id, name: "Display \(id)", isBuiltin: false, isMain: true,
                    vendor: 1, product: id, mirrorSource: 0,
                    currentMode: current, modes: modes)
    }
}
