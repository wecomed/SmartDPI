import CoreGraphics
import Foundation
import SmartDPICore
import Testing
@testable import SmartDPI

struct DisplaySnapshotRecoveryTests {
    private let original = DisplayMode(modeID: 37, width: 2560, height: 1440,
                                       pixelWidth: 2560, pixelHeight: 1440, refreshRate: 75)

    private func entry(id: UInt32 = 2, identity: String? = "monitor-a", source: UInt32 = 0) -> DisplaySnapshot.Entry {
        .init(id: id, vendor: 123, product: 456, persistentID: identity,
              mode: original, source: source, origin: .zero)
    }

    private func state(id: UInt32 = 2, identity: String? = "monitor-a", mode: DisplayMode? = nil,
                       source: UInt32 = 0, awake: Bool = true) -> DisplaySnapshot.State {
        .init(id: id, vendor: 123, product: 456, persistentID: identity,
              mode: mode ?? original, source: source, origin: .zero, isAwake: awake)
    }

    @Test func disconnectedTargetCannotBeReportedRestored() {
        let snapshot = DisplaySnapshot(entries: [entry()])
        #expect(!snapshot.isRestored(in: []))
        #expect(snapshot.hasDisconnectedDisplays(in: []))
        #expect(snapshot.hasUnavailableDisplays(in: []))
    }

    @Test func stableIdentitySurvivesDisplayIDChange() {
        let snapshot = DisplaySnapshot(entries: [entry()])
        let returned = state(id: 18)
        #expect(DisplaySnapshot.resolve(entry(), in: [returned])?.id == 18)
        #expect(snapshot.isRestored(in: [returned]))
        #expect(!snapshot.hasDisconnectedDisplays(in: [returned]))
    }

    @Test func reusedIDOnSameModelCannotMatchAnotherMonitor() {
        let snapshot = DisplaySnapshot(entries: [entry()])
        let other = state(identity: "monitor-b")
        #expect(DisplaySnapshot.resolve(entry(), in: [other]) == nil)
        #expect(!snapshot.isRestored(in: [other]))
    }

    @Test func missingOrDuplicateIdentityDoesNotGuess() {
        #expect(DisplaySnapshot.resolve(entry(identity: nil), in: [state(identity: nil)]) == nil)
        #expect(DisplaySnapshot.resolve(entry(), in: [state(), state(id: 3)]) == nil)
    }

    @Test func sleepingDisplayKeepsRecoveryPendingEvenAtOriginalMode() {
        let snapshot = DisplaySnapshot(entries: [entry()])
        let sleeping = state(awake: false)
        #expect(!snapshot.isRestored(in: [sleeping]))
        #expect(!snapshot.hasDisconnectedDisplays(in: [sleeping]))
        #expect(snapshot.hasUnavailableDisplays(in: [sleeping]))
    }

    @Test func returningAt720pDoesNotSatisfyNativeBaseline() {
        let low = DisplayMode(modeID: 14, width: 1280, height: 720,
                              pixelWidth: 2560, pixelHeight: 1440, refreshRate: 75)
        let snapshot = DisplaySnapshot(entries: [entry()])
        #expect(!snapshot.isRestored(in: [state(id: 18, mode: low)]))
    }

    @Test func modeIsResolvedByFreshGeometryAndTimingNotStaleID() {
        let wrong = DisplayMode(modeID: 37, width: 1280, height: 720,
                                pixelWidth: 1280, pixelHeight: 720, refreshRate: 75)
        let rateMismatch = DisplayMode(modeID: 200, width: 2560, height: 1440,
                                       pixelWidth: 2560, pixelHeight: 1440, refreshRate: 60)
        let fresh = DisplayMode(modeID: 201, width: 2560, height: 1440,
                                pixelWidth: 2560, pixelHeight: 1440, refreshRate: 75)
        #expect(DisplaySnapshot.matchingMode(original, in: [wrong, rateMismatch, fresh]) == fresh)
        #expect(DisplaySnapshot.matchingMode(original, in: [wrong, rateMismatch]) == nil)
    }

    @Test func foreignMirrorSourceIDsAreResolvedByIdentity() {
        let snapshot = DisplaySnapshot(entries: [entry(), entry(id: 3, identity: "monitor-b", source: 2)])
        #expect(snapshot.isRestored(in: [state(id: 20), state(id: 21, identity: "monitor-b", source: 20)]))
        #expect(!snapshot.isRestored(in: [state(id: 21, identity: "monitor-b", source: 2)]))
    }

    @Test func recoveryCanOnlyRemoveItsOwnMirrorAndCannotBreakForeignMirror() {
        #expect(DisplaySnapshot.canRestoreMirror(currentSource: 0, expectedSource: 0, ownedSource: 22))
        #expect(DisplaySnapshot.canRestoreMirror(currentSource: 22, expectedSource: 0, ownedSource: 22))
        #expect(DisplaySnapshot.canRestoreMirror(currentSource: 80, expectedSource: 80, ownedSource: nil))
        #expect(!DisplaySnapshot.canRestoreMirror(currentSource: 80, expectedSource: 0, ownedSource: 22))
        #expect(!DisplaySnapshot.canRestoreMirror(currentSource: 22, expectedSource: 0, ownedSource: nil))
    }

    @Test func partialWakeModeListWaitsForBaselineModeAndUsesReturnedID() {
        let snapshot = DisplaySnapshot(entries: [entry()])
        let low = DisplayMode(modeID: 14, width: 1280, height: 720,
                              pixelWidth: 1280, pixelHeight: 720, refreshRate: 75)
        let returned = state(id: 18, mode: low)
        var queried: UInt32?
        #expect(!snapshot.hasAvailableModes(in: [returned], modesForDisplay: { id in
            queried = id
            return [low]
        }))
        #expect(queried == 18)
        #expect(snapshot.hasAvailableModes(in: [returned], modesForDisplay: { _ in [low, original] }))
    }

    @Test func restoredBaselineDoesNotNeedAnotherModeEnumeration() {
        let snapshot = DisplaySnapshot(entries: [entry()])
        var queried = false
        #expect(snapshot.hasAvailableModes(in: [state(id: 18)], modesForDisplay: { _ in
            queried = true
            return []
        }))
        #expect(!queried)
    }

    @Test func modeReadinessRejectsMissingSleepingAndAmbiguousDisplays() {
        let snapshot = DisplaySnapshot(entries: [entry()])
        #expect(!snapshot.hasAvailableModes(in: [], modesForDisplay: { _ in [original] }))
        #expect(!snapshot.hasAvailableModes(in: [state(awake: false)], modesForDisplay: { _ in [original] }))
        #expect(!snapshot.hasAvailableModes(in: [state(), state(id: 18)], modesForDisplay: { _ in [original] }))
    }

    @Test func legacyDiagnosticWithoutPersistentIdentityStillDecodes() throws {
        let json = #"{"id":2,"name":"Monitor","isBuiltin":false,"isMain":true,"vendor":123,"product":456,"mirrorSource":0,"isInMirrorSet":false,"modes":[],"nativeSizeIsEstimated":true}"#
        let display = try JSONDecoder().decode(DisplayInfo.self, from: Data(json.utf8))
        #expect(display.persistentID == nil)
    }
}
