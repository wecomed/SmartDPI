import Testing
@testable import SmartDPI
import SmartDPICore

struct UnifiedSelectionTests {
    @MainActor @Test func demoImmediateActionsDoNotMutateSelectionOrStartConfirmation() async throws {
        let store = makeStore()
        let target = try #require(store.displayOptions.first { $0.width == 1920 && $0.isHiDPI })
        let draft = try #require(store.menuResolutionChoices.first { $0.width == 1600 })
        store.useVirtual = true
        store.selectedResolutionID = draft.id
        store.selectedPresetID = "1600x900"
        store.selectedRefreshRate = 60
        store.menuRefreshRate = 75
        store.status = "Existing feedback"
        let current = store.currentMode

        await store.applyOption(id: target.id, expectedDisplayID: 10)
        await store.setRefreshRate(60, expectedDisplayID: 10)
        await store.setRefreshRate(nil, expectedDisplayID: 10)

        #expect(store.selectedResolutionID == draft.id)
        #expect(store.selectedPresetID == "1600x900")
        #expect(store.selectedRefreshRate == 60)
        #expect(store.menuRefreshRate == 75)
        #expect(store.useVirtual)
        #expect(store.currentMode == current)
        #expect(store.status == "Existing feedback")
        #expect(store.error == nil)
        #expect(store.pendingSeconds == nil)
        #expect(!store.busy)
        #expect(!store.activeVirtual)
        #expect(!store.canApplyOption(target))
        #expect(!store.canUndo)
    }

    @MainActor @Test func delayedClickFromPreviousMonitorCannotChangeNewMonitorSelection() async throws {
        let store = makeStore()
        let original = try #require(store.selectedDisplay)
        let target = try #require(store.displayOptions.first { $0.width == 1920 && $0.isHiDPI })
        store.displays.append(display(id: 20, current: original.currentMode, modes: original.modes))
        store.selectDisplay(id: 20)
        store.menuRefreshRate = 75
        let draft = store.selectedResolutionID
        let preset = store.selectedPresetID
        let current = store.currentMode

        await store.applyOption(id: target.id, expectedDisplayID: original.id)
        await store.setRefreshRate(60, expectedDisplayID: original.id)

        #expect(store.selectedDisplayID == 20)
        #expect(store.selectedResolutionID == draft)
        #expect(store.selectedPresetID == preset)
        #expect(store.menuRefreshRate == 75)
        #expect(store.currentMode == current)
        #expect(store.pendingSeconds == nil)
        #expect(!store.busy)
        #expect(!store.activeVirtual)
    }

    @MainActor @Test func lockedDemoActionsPreserveBusyAndRecoveryState() async throws {
        // Demo stores ensure this guard coverage never reaches display hardware.
        for recovering in [false, true] {
            let store = makeStore()
            let target = try #require(store.displayOptions.first { $0.width == 1920 && $0.isHiDPI })
            store.menuRefreshRate = 75
            store.busy = !recovering
            store.recoveryPending = recovering
            let draft = store.selectedResolutionID
            let current = store.currentMode

            await store.applyOption(id: target.id, expectedDisplayID: 10)
            await store.applyOption(id: "removed-option", expectedDisplayID: 10)
            await store.setRefreshRate(60, expectedDisplayID: 10)

            #expect(!store.canApplyOption(target))
            #expect(store.selectedResolutionID == draft)
            #expect(store.menuRefreshRate == 75)
            #expect(store.currentMode == current)
            #expect(store.busy == !recovering)
            #expect(store.recoveryPending == recovering)
            #expect(store.pendingSeconds == nil)
            #expect(!store.activeVirtual)
            #expect(!store.canUndo)
        }
    }

    @MainActor @Test func currentCheckUsesActualDesktopAndHiDPIStateInsteadOfLegacyDraft() throws {
        let store = makeStore()
        let originalCurrent = try #require(store.currentOption)
        let hiDPI = try #require(store.displayOptions.first { $0.width == 1920 && $0.isHiDPI })
        let ordinary = try #require(store.displayOptions.first { $0.width == 1920 && !$0.isHiDPI })
        let draft = try #require(store.menuResolutionChoices.first { $0.width == 1920 && $0.isHiDPI })
        store.selectedResolutionID = draft.id
        store.selectedRefreshRate = 60
        store.useVirtual = true
        store.selectedPresetID = "1920x1080"

        #expect(store.isCurrentOption(originalCurrent))
        #expect(!store.isCurrentOption(hiDPI))
        #expect(store.currentOption?.id == originalCurrent.id)

        let original = try #require(store.selectedDisplay)
        let actualOrdinary = try #require(original.modes.first { $0.width == 1920 && !$0.isHiDPI })
        store.displays = [display(id: original.id, current: actualOrdinary, modes: original.modes)]

        #expect(store.isCurrentOption(ordinary))
        #expect(!store.isCurrentOption(hiDPI))
        #expect(!store.isCurrentOption(originalCurrent))
        #expect(store.currentOption?.id == ordinary.id)
    }

    @MainActor @Test func eachOptionResolvesActualAndSupportedRefreshWithoutUsingLegacyDraft() throws {
        let store = makeStore()
        let fullHD = try #require(store.displayOptions.first { $0.width == 1920 && $0.isHiDPI })
        let smaller = try #require(store.displayOptions.first { $0.width == 1600 && $0.isHiDPI })
        let native = try #require(store.currentOption)
        let smallDraft = try #require(store.menuResolutionChoices.first { $0.width == 1600 })
        store.selectedResolutionID = smallDraft.id
        store.selectedRefreshRate = 60

        #expect(store.currentMode?.refreshRate == 75)
        #expect(store.optionRefreshRate(fullHD) == 75)
        #expect(store.optionRefreshRate(smaller) == 60)

        store.menuRefreshRate = 59.94
        #expect(store.optionRefreshRate(fullHD) == 59.94)
        #expect(store.optionRefreshRate(native) == 75)
        #expect(store.optionRefreshRate(smaller) == 60)

        store.menuRefreshRate = 60
        #expect(store.optionRefreshRate(fullHD) == 60)
        #expect(store.optionRefreshRate(native) == 60)

        store.menuRefreshRate = 144
        #expect(store.optionRefreshRate(fullHD) == 75)
        #expect(store.optionRefreshRate(smaller) == 60)
    }

    @MainActor @Test func refreshPickerUsesOnlyActualCurrentOptionRates() throws {
        let store = makeStore()
        let fullHDDraft = try #require(store.menuResolutionChoices.first { $0.width == 1920 && $0.isHiDPI })
        store.selectedResolutionID = fullHDDraft.id
        store.menuRefreshRate = 59.94
        #expect(store.unifiedRefreshRates == [75, 60])
        #expect(!store.unifiedRefreshRates.contains(59.94))

        let original = try #require(store.selectedDisplay)
        let actualSmall = try #require(original.modes.first { $0.width == 1600 })
        store.displays = [display(id: original.id, current: actualSmall, modes: original.modes)]
        #expect(store.unifiedRefreshRates == [60])

        store.displays = [display(id: original.id, current: nil, modes: original.modes)]
        #expect(store.currentOption == nil)
        #expect(store.unifiedRefreshRates.isEmpty)
    }

    @MainActor @Test func unifiedListIsIndependentOfLegacySourceAndVisibilityFilters() {
        let store = makeStore()
        let initial = store.displayOptions
        let initialIDs = initial.map(\.id)
        #expect(initial.contains { $0.isHiDPI })
        #expect(initial.contains { !$0.isHiDPI })

        for allModes in [true, false] {
            for virtual in [true, false] {
                store.showAllModes = allModes
                store.useVirtual = virtual
                #expect(store.displayOptions == initial)
                #expect(store.displayOptions.map(\.id) == initialIDs)
            }
        }
    }

    @MainActor private func makeStore() -> DisplayStore {
        let native = mode(1, width: 2560, height: 1440, rate: 75, native: true)
        let modes = [native,
            mode(2, width: 2560, height: 1440, rate: 60, native: true),
            mode(3, width: 1920, height: 1080, rate: 59.94, hiDPI: true),
            mode(4, width: 1920, height: 1080, rate: 60, hiDPI: true),
            mode(5, width: 1920, height: 1080, rate: 75, hiDPI: true),
            mode(6, width: 1600, height: 900, rate: 60, hiDPI: true),
            mode(7, width: 1920, height: 1080, rate: 60)]
        let store = DisplayStore(isDemo: true)
        store.displays = [display(id: 10, current: native, modes: modes)]
        store.selectDisplay(id: 10)
        return store
    }

    private func mode(_ id: UInt32, width: Int, height: Int, rate: Double,
                      hiDPI: Bool = false, native: Bool = false) -> DisplayMode {
        DisplayMode(modeID: id, width: width, height: height,
                    pixelWidth: width * (hiDPI ? 2 : 1), pixelHeight: height * (hiDPI ? 2 : 1),
                    refreshRate: rate, isNative: native)
    }

    private func display(id: UInt32, current: DisplayMode?, modes: [DisplayMode]) -> DisplayInfo {
        DisplayInfo(id: id, name: "Unified test display \(id)", isBuiltin: false,
                    isMain: id == 10, vendor: 1, product: id, mirrorSource: 0,
                    currentMode: current, modes: modes)
    }
}
