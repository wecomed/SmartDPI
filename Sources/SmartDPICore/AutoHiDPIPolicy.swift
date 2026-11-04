import Foundation

/// The user's last verified HiDPI choice for one physical display. A nil rate
/// means automatic matching; do not replace it with a transient observed rate.
public struct SavedHiDPISetting: Codable, Equatable, Sendable {
    public let persistentID: String
    public let width: Int
    public let height: Int
    public let refreshRate: Double?
    public let nativeWidth: Int
    public let nativeHeight: Int

    public init(persistentID: String, width: Int, height: Int, refreshRate: Double?,
                nativeWidth: Int, nativeHeight: Int) {
        self.persistentID = persistentID
        self.width = width
        self.height = height
        self.refreshRate = refreshRate
        self.nativeWidth = nativeWidth
        self.nativeHeight = nativeHeight
    }

    public var optionID: String { "\(width)x\(height)-hidpi" }

    public var isValid: Bool {
        !persistentID.isEmpty && width >= 640 && height >= 480 &&
        width <= 7680 && height <= 7680 && nativeWidth > 0 && nativeHeight > 0 &&
        refreshRate.map { $0.isFinite && $0 > 0 && $0 <= 1000 } != false
    }
}

public enum AutoHiDPIPolicy {
    /// Require the complete known panel geometry before considering a restored
    /// option. A temporary 720p mode list must not become a new saved preference.
    public static func option(for setting: SavedHiDPISetting, on display: DisplayInfo,
                              includeVirtual: Bool) -> DisplayOption? {
        guard setting.isValid, display.persistentID == setting.persistentID,
              !display.isBuiltin, !display.isInMirrorSet,
              display.nativeWidth == setting.nativeWidth,
              display.nativeHeight == setting.nativeHeight,
              display.currentMode?.usable == true,
              display.modes.contains(where: {
                  $0.usable && $0.pixelWidth == setting.nativeWidth &&
                  $0.pixelHeight == setting.nativeHeight &&
                  $0.refreshRate.isFinite && $0.refreshRate > 0
              }),
              let option = DisplayOption.choices(for: display, includeVirtual: includeVirtual)
                .first(where: { $0.id == setting.optionID }),
              !option.refreshRates.isEmpty else { return nil }
        if let requested = setting.refreshRate,
           !option.refreshRates.contains(where: { abs($0 - requested) <= 0.01 }) {
            return nil
        }
        return option
    }

    public static func isAlreadyApplied(_ setting: SavedHiDPISetting, on display: DisplayInfo) -> Bool {
        guard display.persistentID == setting.persistentID, let mode = display.currentMode,
              mode.usable, mode.isHiDPI, mode.width == setting.width, mode.height == setting.height else {
            return false
        }
        return setting.refreshRate.map { abs($0 - mode.refreshRate) <= 0.01 } ?? true
    }
}

public enum AutoHiDPIAction: Equatable, Sendable {
    case waiting
    case apply(displayID: UInt32, optionID: String, refreshRate: Double?)
    case finished
    case exhausted
}

/// One explicitly scheduled reconnect/wake/startup episode. This policy does
/// not schedule itself again after success, manual cancellation or exhaustion.
public struct AutoHiDPIAttempt: Sendable {
    public private(set) var attempts = 0
    public private(set) var isFinished = false
    public private(set) var isExhausted = false
    private let startedAt: TimeInterval
    private let maxAttempts: Int
    private let timeout: TimeInterval
    private let settlingInterval: TimeInterval
    private var stableSnapshot: DisplayInfo?
    private var stableSince: TimeInterval?
    private var inFlight = false
    private var retryAfter: TimeInterval

    public init(startedAt: TimeInterval, maxAttempts: Int = 3,
                timeout: TimeInterval = 30, settlingInterval: TimeInterval = 0.8) {
        self.startedAt = startedAt
        self.maxAttempts = max(1, maxAttempts)
        self.timeout = max(1, timeout)
        self.settlingInterval = max(0.1, settlingInterval)
        retryAfter = startedAt
    }

    public mutating func observe(setting: SavedHiDPISetting, displays: [DisplayInfo],
                                 awakeDisplayIDs: Set<UInt32>, includeVirtual: Bool,
                                 now: TimeInterval, blocked: Bool = false) -> AutoHiDPIAction {
        if isFinished { return .finished }
        if isExhausted { return .exhausted }
        if inFlight { return .waiting }
        guard now - startedAt < timeout, attempts < maxAttempts, setting.isValid else {
            isExhausted = true
            clearStability()
            return .exhausted
        }
        let matches = displays.filter { $0.persistentID == setting.persistentID }
        guard !blocked, now >= retryAfter, matches.count == 1,
              let display = matches.first, awakeDisplayIDs.contains(display.id),
              AutoHiDPIPolicy.option(for: setting, on: display, includeVirtual: includeVirtual) != nil else {
            clearStability()
            return .waiting
        }
        if stableSnapshot != display {
            stableSnapshot = display
            stableSince = now
            return .waiting
        }
        guard let stableSince, now - stableSince >= settlingInterval else { return .waiting }
        if AutoHiDPIPolicy.isAlreadyApplied(setting, on: display) {
            isFinished = true
            clearStability()
            return .finished
        }
        attempts += 1
        inFlight = true
        clearStability()
        return .apply(displayID: display.id, optionID: setting.optionID, refreshRate: setting.refreshRate)
    }

    /// Call only after the display operation has completed and its actual mode
    /// has been checked. Failed attempts wait before another stable observation.
    public mutating func complete(success: Bool, now: TimeInterval) {
        guard inFlight, !isFinished, !isExhausted else { return }
        inFlight = false
        clearStability()
        if success { isFinished = true }
        else if attempts >= maxAttempts || now - startedAt >= timeout { isExhausted = true }
        else { retryAfter = now + max(1, settlingInterval) }
    }

    public mutating func cancel() {
        isFinished = true
        inFlight = false
        clearStability()
    }

    private mutating func clearStability() {
        stableSnapshot = nil
        stableSince = nil
    }
}
