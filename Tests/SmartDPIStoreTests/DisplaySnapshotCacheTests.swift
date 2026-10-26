import Testing
@testable import SmartDPI
import SmartDPICore

struct DisplaySnapshotCacheTests {
    @MainActor @Test func sameMonitorAndModeCountCanReportDifferentRefreshRates() throws {
        let store = DisplayStore(isDemo: true)
        let firstMode = mode(id: 1, rate: 75)
        store.displays = [display(id: 10, current: firstMode, modes: [firstMode])]
        store.selectDisplay(id: 10)
        #expect(store.currentOption?.refreshRates == [75])

        // A cable or timing change can retain the CG display/mode IDs and array count.
        let updatedMode = mode(id: 1, rate: 60)
        store.displays = [display(id: 10, current: updatedMode, modes: [updatedMode])]
        let updated = try #require(store.currentOption)
        #expect(updated.refreshRates == [60])
        #expect(store.optionRefreshRate(updated) == 60)
        #expect(store.unifiedRefreshRates == [60])
    }

    @MainActor @Test func currentModeChangesAreIncludedEvenWhenEnumeratedModesAreUnchanged() throws {
        let store = DisplayStore(isDemo: true)
        let native = mode(id: 1, rate: 75)
        store.displays = [display(id: 10, current: native, modes: [native], builtin: true)]
        store.selectDisplay(id: 10)
        #expect(store.displayOptions.count == 1)

        let current = DisplayMode(modeID: 2, width: 1920, height: 1080,
                                  pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60)
        store.displays = [display(id: 10, current: current, modes: [native], builtin: true)]
        let option = try #require(store.currentOption)
        #expect(option.width == 1920)
        #expect(option.isHiDPI)
        #expect(!option.requiresVirtual)
        #expect(store.displayOptions.count == 2)
    }

    @MainActor @Test func switchingMonitorsCannotReusePreviousMonitorOptions() throws {
        let store = DisplayStore(isDemo: true)
        let externalMode = mode(id: 1, rate: 75)
        let internalMode = DisplayMode(modeID: 1, width: 1512, height: 982,
                                       pixelWidth: 3024, pixelHeight: 1964, refreshRate: 120)
        store.displays = [display(id: 10, current: externalMode, modes: [externalMode]),
                          display(id: 20, current: internalMode, modes: [internalMode], builtin: true)]
        store.selectDisplay(id: 10)
        #expect(store.currentOption?.width == 2560)
        store.selectDisplay(id: 20)
        let option = try #require(store.currentOption)
        #expect(option.width == 1512)
        #expect(option.refreshRates == [120])
        #expect(store.displayOptions.count == 1)
        #expect(!option.requiresVirtual)

        store.displays = []
        #expect(store.displayOptions.isEmpty)
        #expect(store.currentMode == nil)
    }

    @MainActor @Test func demoHealthChecksNeverProbeOrRecoverRealDisplays() {
        let store = DisplayStore(isDemo: true)
        store.activeVirtual = true
        store.status = "Preview status"
        let snapshot = store.displays
        store.checkVirtualHealth()
        #expect(store.activeVirtual)
        #expect(store.status == "Preview status")
        #expect(store.error == nil)
        #expect(store.displays == snapshot)
        #expect(!store.recoveryPending)
    }

    private func mode(id: UInt32, rate: Double) -> DisplayMode {
        DisplayMode(modeID: id, width: 2560, height: 1440,
                    pixelWidth: 2560, pixelHeight: 1440, refreshRate: rate, isNative: true)
    }

    private func display(id: UInt32, current: DisplayMode?, modes: [DisplayMode],
                         builtin: Bool = false) -> DisplayInfo {
        DisplayInfo(id: id, name: "Cache test \(id)", isBuiltin: builtin,
                    isMain: id == 10, vendor: 1, product: id, mirrorSource: 0,
                    currentMode: current, modes: modes)
    }
}
