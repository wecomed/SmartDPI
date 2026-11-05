import Foundation
import Testing
@testable import SmartDPICore

@Suite struct AutoHiDPIPolicyTests {
    @Test func requiresSeparatedStableSnapshotsAndUsesNewConnectionID() {
        var episode = AutoHiDPIAttempt(startedAt: 0)
        let display = monitor(id: 42)
        #expect(observe(&episode, display, at: 0) == .waiting)
        #expect(observe(&episode, display, at: 0.2) == .waiting)
        #expect(observe(&episode, display, at: 1) == .apply(displayID: 42, optionID: "1920x1080-hidpi", refreshRate: nil))
        #expect(observe(&episode, display, at: 2) == .waiting)
        episode.complete(success: true, now: 2)
        #expect(observe(&episode, display, at: 10) == .finished)
    }

    @Test func changedConnectionDuringSettlingRequiresFreshStableSnapshots() {
        var episode = AutoHiDPIAttempt(startedAt: 0)
        #expect(observe(&episode, monitor(id: 2), at: 0) == .waiting)
        #expect(observe(&episode, monitor(id: 42), at: 1) == .waiting)
        #expect(observe(&episode, monitor(id: 42), at: 2) == .apply(displayID: 42, optionID: "1920x1080-hidpi", refreshRate: nil))
    }

    @Test func sameModelDisplaysAreMatchedOnlyByPersistentIdentity() {
        var episode = AutoHiDPIAttempt(startedAt: 0)
        let intended = monitor(id: 42)
        let other = monitor(id: 2, key: "other-display")
        #expect(episode.observe(setting: setting(), displays: [other, intended], awakeDisplayIDs: [2, 42],
                                includeVirtual: true, now: 0) == .waiting)
        #expect(episode.observe(setting: setting(), displays: [other, intended], awakeDisplayIDs: [2, 42],
                                includeVirtual: true, now: 1) == .apply(displayID: 42, optionID: "1920x1080-hidpi", refreshRate: nil))
    }

    @Test func ambiguousIdentityNeverChoosesOneOfTwoDisplays() {
        var episode = AutoHiDPIAttempt(startedAt: 0)
        for time in [0.0, 1, 5] {
            #expect(episode.observe(setting: setting(), displays: [monitor(id: 2), monitor(id: 42)],
                                    awakeDisplayIDs: [2, 42], includeVirtual: true, now: time) == .waiting)
        }
        #expect(episode.attempts == 0)
    }

    @Test func temporary720pPanelReportCannotReplaceOrApplySavedChoice() {
        var episode = AutoHiDPIAttempt(startedAt: 0)
        let saved = setting()
        let partial = monitor(nativeWidth: 1280, nativeHeight: 720)
        #expect(AutoHiDPIPolicy.option(for: saved, on: partial, includeVirtual: true) == nil)
        #expect(observe(&episode, partial, at: 0) == .waiting)
        #expect(observe(&episode, partial, at: 5) == .waiting)
        #expect(saved.width == 1920 && saved.height == 1080 && saved.nativeWidth == 2560)
        let ready = monitor()
        #expect(observe(&episode, ready, at: 6) == .waiting)
        #expect(observe(&episode, ready, at: 7) == .apply(displayID: 2, optionID: saved.optionID, refreshRate: nil))
    }

    @Test func awake900pCapabilityLossIsAReconnectSignalEvenWithTheSameID() {
        let partial = monitor(nativeWidth: 1600, nativeHeight: 900)
        #expect(!AutoHiDPIPolicy.hasKnownPanelModes(for: setting(), on: partial))
        #expect(AutoHiDPIPolicy.shouldResumeAfterMirrorLoss(setting: setting(), display: partial, ownedSource: 100))
        #expect(AutoHiDPIPolicy.option(for: setting(), on: partial, includeVirtual: true) == nil)
    }

    @Test func intactCapabilitiesAfterAnExternalModeChangeDoNotForceTheSavedHiDPI() {
        let ready = monitor()
        #expect(AutoHiDPIPolicy.hasKnownPanelModes(for: setting(), on: ready))
        #expect(!AutoHiDPIPolicy.shouldResumeAfterMirrorLoss(setting: setting(), display: ready, ownedSource: 100))
    }

    @Test func degradedForeignMirrorIsNotTreatedAsOurReconnect() {
        let foreign = monitor(nativeWidth: 1600, nativeHeight: 900, mirrored: true)
        #expect(!AutoHiDPIPolicy.shouldResumeAfterMirrorLoss(setting: setting(), display: foreign, ownedSource: 200))
        #expect(AutoHiDPIPolicy.shouldResumeAfterMirrorLoss(setting: setting(), display: foreign, ownedSource: 100))
    }

    @Test func cachedNativeSizeCannotMakeMissingPhysicalModesReady() {
        let ready = monitor()
        let incomplete = DisplayInfo(id: ready.id, name: ready.name, isBuiltin: false, isMain: false,
            vendor: ready.vendor, product: ready.product, mirrorSource: 0, currentMode: ready.currentMode,
            modes: ready.modes.filter { $0.pixelWidth != 2560 }, nativeWidth: 2560, nativeHeight: 1440,
            nativeSizeIsEstimated: false, persistentID: ready.persistentID)
        #expect(!AutoHiDPIPolicy.hasKnownPanelModes(for: setting(), on: incomplete))
        #expect(AutoHiDPIPolicy.option(for: setting(), on: incomplete, includeVirtual: true) == nil)
    }

    @Test func unavailableDesiredSizeNeverFallsBackTo720pHiDPI() {
        var episode = AutoHiDPIAttempt(startedAt: 0)
        let display = monitor(includeRequested: false)
        #expect(episode.observe(setting: setting(), displays: [display], awakeDisplayIDs: [2],
                                includeVirtual: false, now: 0) == .waiting)
        #expect(episode.observe(setting: setting(), displays: [display], awakeDisplayIDs: [2],
                                includeVirtual: false, now: 2) == .waiting)
        #expect(episode.attempts == 0)
    }

    @Test func asleepMirroredAndBusySnapshotsDoNotTriggerChanges() {
        let display = monitor()
        var episode = AutoHiDPIAttempt(startedAt: 0)
        #expect(episode.observe(setting: setting(), displays: [display], awakeDisplayIDs: [],
                                includeVirtual: true, now: 0) == .waiting)
        #expect(observe(&episode, display, at: 1) == .waiting)
        #expect(episode.observe(setting: setting(), displays: [display], awakeDisplayIDs: [2],
                                includeVirtual: true, now: 2, blocked: true) == .waiting)
        #expect(observe(&episode, display, at: 3) == .waiting)
        #expect(observe(&episode, monitor(mirrored: true), at: 4) == .waiting)
        #expect(observe(&episode, display, at: 5) == .waiting)
        #expect(observe(&episode, display, at: 6) == .apply(displayID: 2, optionID: "1920x1080-hidpi", refreshRate: nil))
    }

    @Test func retryCountIsBoundedAndCannotRescheduleAfterExhaustion() {
        var episode = AutoHiDPIAttempt(startedAt: 0, maxAttempts: 2)
        let display = monitor()
        #expect(observe(&episode, display, at: 0) == .waiting)
        #expect(observe(&episode, display, at: 1) == .apply(displayID: 2, optionID: "1920x1080-hidpi", refreshRate: nil))
        episode.complete(success: false, now: 2)
        #expect(observe(&episode, display, at: 2.1) == .waiting)
        #expect(observe(&episode, display, at: 3) == .waiting)
        #expect(observe(&episode, display, at: 4) == .apply(displayID: 2, optionID: "1920x1080-hidpi", refreshRate: nil))
        episode.complete(success: false, now: 5)
        #expect(observe(&episode, display, at: 6) == .exhausted)
        #expect(episode.attempts == 2)
    }

    @Test func unavailableDeviceTimesOutWithoutInfinitePollingOrModeChanges() {
        var episode = AutoHiDPIAttempt(startedAt: 0)
        #expect(episode.observe(setting: setting(), displays: [], awakeDisplayIDs: [],
                                includeVirtual: true, now: 29) == .waiting)
        #expect(episode.observe(setting: setting(), displays: [], awakeDisplayIDs: [],
                                includeVirtual: true, now: 30) == .exhausted)
        #expect(episode.attempts == 0)
    }

    @Test func manualCancellationWinsOverLateSuccessfulCompletion() {
        var episode = AutoHiDPIAttempt(startedAt: 0)
        let display = monitor()
        _ = observe(&episode, display, at: 0)
        _ = observe(&episode, display, at: 1)
        episode.cancel()
        episode.complete(success: false, now: 2)
        #expect(observe(&episode, display, at: 3) == .finished)
        #expect(episode.attempts == 1)
    }

    @Test func alreadyAppliedModeFinishesWithoutAnotherConfiguration() {
        var episode = AutoHiDPIAttempt(startedAt: 0)
        let display = monitor(currentHiDPI: true)
        #expect(observe(&episode, display, at: 0) == .waiting)
        #expect(observe(&episode, display, at: 1) == .finished)
        #expect(episode.attempts == 0)
    }

    @Test func explicitRefreshMustBeAvailableWhileAutomaticCanAdapt() {
        let display = monitor(rate: 60)
        #expect(AutoHiDPIPolicy.option(for: setting(rate: 75), on: display, includeVirtual: true) == nil)
        #expect(AutoHiDPIPolicy.option(for: setting(), on: display, includeVirtual: true)?.refreshRates == [60])
    }

    @Test func preferencesRoundTripAndRejectInvalidDecodedValues() throws {
        let profile = setting(rate: 59.94)
        let data = try JSONEncoder().encode([profile])
        #expect(try JSONDecoder().decode([SavedHiDPISetting].self, from: data) == [profile])
        #expect(setting(rate: -1).isValid == false)
        #expect(setting(rate: .infinity).isValid == false)
        let invalid = SavedHiDPISetting(persistentID: "", width: 1920, height: 1080,
                                       refreshRate: nil, nativeWidth: 2560, nativeHeight: 1440)
        #expect(!invalid.isValid)
    }

    private func observe(_ episode: inout AutoHiDPIAttempt, _ display: DisplayInfo,
                         at time: TimeInterval) -> AutoHiDPIAction {
        episode.observe(setting: setting(), displays: [display], awakeDisplayIDs: [display.id],
                        includeVirtual: true, now: time)
    }

    private func setting(rate: Double? = nil) -> SavedHiDPISetting {
        SavedHiDPISetting(persistentID: "display-a", width: 1920, height: 1080,
                          refreshRate: rate, nativeWidth: 2560, nativeHeight: 1440)
    }

    private func monitor(id: UInt32 = 2, key: String = "display-a", nativeWidth: Int = 2560,
                         nativeHeight: Int = 1440, includeRequested: Bool = true,
                         rate: Double = 75, currentHiDPI: Bool = false, mirrored: Bool = false) -> DisplayInfo {
        let native = DisplayMode(modeID: 1, width: nativeWidth, height: nativeHeight,
                                 pixelWidth: nativeWidth, pixelHeight: nativeHeight, refreshRate: rate, isNative: true)
        let desired = DisplayMode(modeID: 2, width: 1920, height: 1080,
                                  pixelWidth: 3840, pixelHeight: 2160, refreshRate: rate)
        let small = DisplayMode(modeID: 3, width: 1280, height: 720,
                                pixelWidth: 2560, pixelHeight: 1440, refreshRate: rate)
        return DisplayInfo(id: id, name: "Same model", isBuiltin: false, isMain: false,
                           vendor: 10, product: 20, mirrorSource: mirrored ? 100 : 0,
                           currentMode: currentHiDPI ? desired : native,
                           modes: [native, small] + (includeRequested ? [desired] : []),
                           nativeWidth: nativeWidth, nativeHeight: nativeHeight,
                           nativeSizeIsEstimated: false, persistentID: key)
    }
}
