import Testing
@testable import SmartDPICore

@Suite struct DeferredRestorePolicyTests {
    @Test func temporary900pReportWaitsUntilKnownPanelModesReturn() {
        var policy = DeferredRestorePolicy()
        let saved = setting()
        let partial = monitor(nativeWidth: 1600, nativeHeight: 900, rate: 60)
        let restored = monitor()
        #expect(partial.id == restored.id)
        #expect(!ready(saved, on: partial))

        policy.markWaiting(saved.persistentID, isReady: ready(saved, on: partial))
        for _ in 0..<20 {
            #expect(policy.observe(saved.persistentID, isReady: ready(saved, on: partial)) == false)
        }
        #expect(policy.waitingKeys == [saved.persistentID])
        #expect(policy.observe(saved.persistentID, isReady: ready(saved, on: restored)) == true)
        #expect(policy.waitingKeys.isEmpty)
        #expect(policy.observe(saved.persistentID, isReady: true) == false)
    }

    @Test func modesArrivingAfterTimeoutCanStartOneFreshSettledAttemptWithoutNewConnectionID() {
        let saved = setting()
        let partial = monitor(nativeWidth: 1600, nativeHeight: 900, rate: 60)
        let restored = monitor()
        var attempt = AutoHiDPIAttempt(startedAt: 0)
        #expect(attempt.observe(setting: saved, displays: [partial], awakeDisplayIDs: [partial.id],
                                includeVirtual: false, now: 30) == .exhausted)
        #expect(attempt.attempts == 0)
        var deferred = DeferredRestorePolicy()
        deferred.markWaiting(saved.persistentID, isReady: ready(saved, on: partial))

        #expect(deferred.observe(saved.persistentID, isReady: ready(saved, on: restored)) == true)
        attempt = AutoHiDPIAttempt(startedAt: 120)
        #expect(attempt.observe(setting: saved, displays: [restored], awakeDisplayIDs: [restored.id],
                                includeVirtual: false, now: 120) == .waiting)
        #expect(attempt.observe(setting: saved, displays: [restored], awakeDisplayIDs: [restored.id],
                                includeVirtual: false, now: 121) ==
            .apply(displayID: restored.id, optionID: saved.optionID, refreshRate: nil))
        #expect(deferred.observe(saved.persistentID, isReady: true) == false)
    }

    @Test func failedButUnchangedReadyCapabilitiesDoNotCreateAnInfiniteRetryLoop() {
        var policy = DeferredRestorePolicy()
        policy.markWaiting("screen", isReady: true)
        for _ in 0..<100 {
            #expect(policy.observe("screen", isReady: true) == false)
        }
        #expect(policy.waitingKeys == ["screen"])
        #expect(policy.observe("screen", isReady: false) == false)
        #expect(policy.observe("screen", isReady: true) == true)
        #expect(policy.observe("screen", isReady: true) == false)
    }

    @Test func manualCancellationWinsOverLateCapabilityArrivalForEveryDisplay() {
        var policy = DeferredRestorePolicy()
        policy.markWaiting("first", isReady: false)
        policy.markWaiting("second", isReady: false)
        policy.removeAll()

        #expect(policy.waitingKeys.isEmpty)
        #expect(policy.observe("first", isReady: true) == false)
        #expect(policy.observe("second", isReady: true) == false)
    }

    @Test func successfulOrRemovedDisplayDoesNotEraseAnotherDisplaysPendingRecovery() {
        var policy = DeferredRestorePolicy()
        policy.markWaiting("first", isReady: false)
        policy.markWaiting("second", isReady: false)
        policy.remove("first")

        #expect(policy.observe("first", isReady: true) == false)
        #expect(policy.observe("unrelated", isReady: true) == false)
        #expect(policy.waitingKeys == ["second"])
        #expect(policy.observe("second", isReady: true) == true)
    }

    @Test func explicitRefreshRateMustReturnBeforeDeferredRestoreCanResume() {
        let saved = setting(rate: 75)
        let lowRate = monitor(rate: 60)
        var policy = DeferredRestorePolicy()
        #expect(!ready(saved, on: lowRate))
        policy.markWaiting(saved.persistentID, isReady: ready(saved, on: lowRate))
        #expect(policy.observe(saved.persistentID, isReady: ready(saved, on: lowRate)) == false)
        #expect(policy.observe(saved.persistentID, isReady: ready(saved, on: monitor(rate: 75))) == true)
    }

    @Test func newExplicitWaitingEpisodeCanResumeAgainButEmptyIdentityCannotBeQueued() {
        var policy = DeferredRestorePolicy()
        policy.markWaiting("", isReady: false)
        #expect(policy.waitingKeys.isEmpty)
        #expect(policy.observe("", isReady: true) == false)
        policy.markWaiting("screen", isReady: false)
        #expect(policy.observe("screen", isReady: true) == true)
        policy.markWaiting("screen", isReady: false)
        #expect(policy.observe("screen", isReady: true) == true)
        #expect(policy.observe("screen", isReady: true) == false)
    }

    private func ready(_ saved: SavedHiDPISetting, on monitor: DisplayInfo) -> Bool {
        AutoHiDPIPolicy.option(for: saved, on: monitor, includeVirtual: false) != nil
    }

    private func setting(rate: Double? = nil) -> SavedHiDPISetting {
        SavedHiDPISetting(persistentID: "physical-screen", width: 1920, height: 1080,
                          refreshRate: rate, nativeWidth: 2560, nativeHeight: 1440)
    }

    private func monitor(nativeWidth: Int = 2560, nativeHeight: Int = 1440,
                         rate: Double = 75) -> DisplayInfo {
        let native = DisplayMode(modeID: 1, width: nativeWidth, height: nativeHeight,
                                 pixelWidth: nativeWidth, pixelHeight: nativeHeight,
                                 refreshRate: rate, isNative: true)
        let hiDPI = DisplayMode(modeID: 2, width: 1920, height: 1080,
                                pixelWidth: 3840, pixelHeight: 2160, refreshRate: rate)
        return DisplayInfo(id: 42, name: "Reconnect fixture", isBuiltin: false, isMain: false,
                           vendor: 1, product: 2, mirrorSource: 0, currentMode: native,
                           modes: [native, hiDPI], nativeWidth: nativeWidth, nativeHeight: nativeHeight,
                           nativeSizeIsEstimated: false, persistentID: "physical-screen")
    }
}
