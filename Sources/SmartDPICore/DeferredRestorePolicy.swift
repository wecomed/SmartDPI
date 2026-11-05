/// Remembers an unfinished restore after its short, bounded attempt has ended.
/// Callers feed readiness from fresh display capabilities, not the current
/// desktop size. This policy never polls or changes a display configuration.
public struct DeferredRestorePolicy: Sendable {
    private var readiness: [String: Bool] = [:]

    public init() {}

    public var waitingKeys: Set<String> { Set(readiness.keys) }

    /// Starts a new waiting episode. A still-ready failed configuration must
    /// not be retried on every refresh; capabilities must change first.
    public mutating func markWaiting(_ key: String, isReady: Bool) {
        guard !key.isEmpty else { return }
        readiness[key] = isReady
    }

    /// Requeues once when missing capabilities return, even if the monitor's
    /// connection ID never changed. The caller still applies its normal
    /// settling checks and bounded retry budget before changing any mode.
    public mutating func observe(_ key: String, isReady: Bool) -> Bool {
        guard let wasReady = readiness[key] else { return false }
        if !wasReady && isReady {
            readiness.removeValue(forKey: key)
            return true
        }
        readiness[key] = isReady
        return false
    }

    public mutating func remove(_ key: String) {
        readiness.removeValue(forKey: key)
    }

    /// Manual cancellation, choosing another mode, or disabling automatic
    /// restore must also discard deferred work, so late events cannot win.
    public mutating func removeAll() {
        readiness.removeAll()
    }
}
