import Testing
@testable import SmartDPI
import SmartDPICore

struct MenuSelectionTests {
    @MainActor @Test func menuCanSelectOrdinaryModeWhileMainWindowFiltersHiDPI() throws {
        let (store, native, _) = makeStore(currentHiDPI: false)
        #expect(!store.showAllModes)
        let onlyHiDPI = store.resolutionChoices.allSatisfy { $0.isHiDPI }
        #expect(onlyHiDPI)
        let ordinary = try #require(store.menuResolutionChoices.first { !$0.isHiDPI })

        store.selectMenuResolution(id: ordinary.id)

        #expect(store.showAllModes)
        #expect(store.selectedMode?.matchesConfiguration(of: native) == true)
        #expect(store.effectiveRefreshRate == 75)
        #expect(!store.isHiDPIEnabled)
    }

    @MainActor @Test func renderingPreviewDoesNotChangeActualHiDPIIndicator() throws {
        let (store, _, hiDPI) = makeStore(currentHiDPI: true)
        let ordinary = try #require(store.menuResolutionChoices.first { !$0.isHiDPI })
        store.selectedRefreshRate = 60

        store.selectMenuResolution(id: ordinary.id)

        #expect(store.selectedRefreshRate == nil)
        #expect(store.selectedMode?.pixelWidth == 2560)
        #expect(store.currentMode?.matchesConfiguration(of: hiDPI) == true)
        #expect(store.currentMode?.pixelWidth == 3840)
        #expect(store.isHiDPIEnabled)
        #expect(!store.canApply) // A demo preview never mutates the display.
    }

    @MainActor @Test func invalidAndLockedMenuSelectionsKeepTheExistingDraft() throws {
        let (store, _, _) = makeStore(currentHiDPI: false)
        let ordinary = try #require(store.menuResolutionChoices.first { !$0.isHiDPI })
        let original = store.selectedResolutionID
        store.selectMenuResolution(id: "unavailable")
        #expect(store.selectedResolutionID == original)
        store.pendingSeconds = 10
        store.selectMenuResolution(id: ordinary.id)
        #expect(store.selectedResolutionID == original)
        #expect(!store.showAllModes)
        store.pendingSeconds = nil
        store.busy = true
        store.selectMenuResolution(id: ordinary.id)
        #expect(store.selectedResolutionID == original)
        store.busy = false
        store.recoveryPending = true
        store.selectMenuResolution(id: ordinary.id)
        #expect(store.selectedResolutionID == original)
    }

    @MainActor private func makeStore(currentHiDPI: Bool) -> (DisplayStore, DisplayMode, DisplayMode) {
        let native = DisplayMode(modeID: 1, width: 2560, height: 1440, pixelWidth: 2560,
                                 pixelHeight: 1440, refreshRate: 75, isNative: true)
        let hiDPI = DisplayMode(modeID: 2, width: 1920, height: 1080, pixelWidth: 3840,
                               pixelHeight: 2160, refreshRate: 60)
        let store = DisplayStore(isDemo: true)
        store.displays = [DisplayInfo(id: 10, name: "Menu test display", isBuiltin: false,
            isMain: true, vendor: 1, product: 1, mirrorSource: 0,
            currentMode: currentHiDPI ? hiDPI : native, modes: [native, hiDPI])]
        store.selectDisplay(id: 10)
        return (store, native, hiDPI)
    }
}
