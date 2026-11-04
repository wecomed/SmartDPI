import AppKit
import CoreGraphics
import ColorSync
import CryptoKit
import SmartDPICore

struct DisplayFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum DisplayBackend {
    static func persistentID(for id: UInt32) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
              let value = CFUUIDCreateString(nil, uuid) else { return nil }
        return SHA256.hash(data: Data((value as String).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func isAwake(_ id: UInt32) -> Bool {
        CGDisplayIsOnline(id) != 0 && CGDisplayIsAsleep(id) == 0
    }

    static func check(_ result: CGError, _ operation: String) throws {
        guard result == .success else {
            throw DisplayFailure(message: "\(operation)失败（CoreGraphics \(result.rawValue)）。请尝试其他模式或连接方式。")
        }
    }

    static func onlineIDs() throws -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        try check(CGGetOnlineDisplayList(0, nil, &count), "读取显示器")
        guard count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        try check(CGGetOnlineDisplayList(count, &ids, &count), "读取显示器")
        return Array(ids.prefix(Int(count)))
    }

    static func modes(for id: UInt32) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        return CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] ?? []
    }

    static func describe(_ mode: CGDisplayMode) -> DisplayMode {
        DisplayMode(modeID: UInt32(bitPattern: mode.ioDisplayModeID), width: mode.width,
                    height: mode.height, pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight,
                    refreshRate: mode.refreshRate, usable: mode.isUsableForDesktopGUI(),
                    isNative: mode.ioFlags & 0x02000000 != 0)
    }

    @MainActor static func displays(excluding managedID: UInt32?) throws -> [DisplayInfo] {
        let names = Dictionary(NSScreen.screens.compactMap { screen -> (UInt32, String)? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return nil }
            return (id, screen.localizedName)
        }, uniquingKeysWith: { first, _ in first })
        return try onlineIDs().filter { $0 != managedID }.map { id in
            DisplayInfo(id: id, name: names[id] ?? "外接显示器 \(id)",
                        isBuiltin: CGDisplayIsBuiltin(id) != 0, isMain: CGDisplayIsMain(id) != 0,
                        vendor: CGDisplayVendorNumber(id), product: CGDisplayModelNumber(id),
                        mirrorSource: CGDisplayMirrorsDisplay(id),
                        currentMode: CGDisplayCopyDisplayMode(id).map(describe),
                        modes: modes(for: id).map(describe), isInMirrorSet: CGDisplayIsInMirrorSet(id) != 0,
                        persistentID: persistentID(for: id))
        }.sorted { $0.isMain && !$1.isMain }
    }

    static func configure(option: CGConfigureOption = .forSession, _ body: (CGDisplayConfigRef) throws -> Void) throws {
        var config: CGDisplayConfigRef?
        try check(CGBeginDisplayConfiguration(&config), "开始配置")
        guard let config else { throw DisplayFailure(message: "系统未能创建显示配置。") }
        do { try body(config) } catch {
            CGCancelDisplayConfiguration(config)
            throw error
        }
        // Session changes do not overwrite the user's saved boot configuration.
        try check(CGCompleteDisplayConfiguration(config, option), "应用显示配置")
    }

    static func setMode(_ mode: CGDisplayMode, on id: UInt32) throws {
        try configure { try check(CGConfigureDisplayWithDisplayMode($0, id, mode, nil), "切换分辨率") }
    }

    static func currentMatches(_ expected: DisplayMode, on id: UInt32) -> Bool {
        guard let current = CGDisplayCopyDisplayMode(id) else { return false }
        return current.width == expected.width && current.height == expected.height &&
            current.pixelWidth == expected.pixelWidth && current.pixelHeight == expected.pixelHeight &&
            (expected.refreshRate == 0 || abs(current.refreshRate - expected.refreshRate) < 0.01)
    }
}

/// Value snapshots survive a disconnect; CoreGraphics mode objects and numeric IDs do not.
struct DisplaySnapshot {
    struct Entry {
        let id: UInt32
        let vendor: UInt32
        let product: UInt32
        let persistentID: String?
        let mode: DisplayMode?
        let source: UInt32
        let origin: CGPoint
    }

    struct State {
        let id: UInt32
        let vendor: UInt32
        let product: UInt32
        let persistentID: String?
        let mode: DisplayMode?
        let source: UInt32
        let origin: CGPoint
        let isAwake: Bool
    }

    let entries: [Entry]

    static func states() throws -> [State] {
        try DisplayBackend.onlineIDs().map { id in
            State(id: id, vendor: CGDisplayVendorNumber(id), product: CGDisplayModelNumber(id),
                  persistentID: DisplayBackend.persistentID(for: id),
                  mode: CGDisplayCopyDisplayMode(id).map(DisplayBackend.describe),
                  source: CGDisplayMirrorsDisplay(id), origin: CGDisplayBounds(id).origin,
                  isAwake: DisplayBackend.isAwake(id))
        }
    }

    /// Never identify a returning monitor by model alone or a possibly reused display ID.
    static func resolve(_ entry: Entry, in states: [State]) -> State? {
        guard let identity = entry.persistentID, !identity.isEmpty else { return nil }
        let matches = states.filter {
            $0.persistentID == identity && $0.vendor == entry.vendor && $0.product == entry.product
        }
        return matches.count == 1 ? matches.first : nil
    }

    static func matches(_ expected: DisplayMode, _ current: DisplayMode) -> Bool {
        expected.width == current.width && expected.height == current.height &&
            expected.pixelWidth == current.pixelWidth && expected.pixelHeight == current.pixelHeight &&
            (expected.refreshRate == 0 || abs(current.refreshRate - expected.refreshRate) < 0.01)
    }

    /// Match geometry and timing against freshly enumerated modes, not yesterday's mode ID.
    static func matchingMode(_ expected: DisplayMode, in modes: [DisplayMode]) -> DisplayMode? {
        modes.first { $0.usable && matches(expected, $0) }
    }

    static func canRestoreMirror(currentSource: UInt32, expectedSource: UInt32, ownedSource: UInt32?) -> Bool {
        currentSource == 0 || currentSource == expectedSource || currentSource == ownedSource
    }

    func expectedSource(for entry: Entry, in states: [State]) -> UInt32? {
        guard entry.source != 0 else { return 0 }
        guard let source = entries.first(where: { $0.id == entry.source }) else { return nil }
        return Self.resolve(source, in: states)?.id
    }

    private func restored(_ entry: Entry, current: State, source: UInt32) -> Bool {
        guard current.isAwake, current.source == source else { return false }
        if let expected = entry.mode {
            guard let mode = current.mode, Self.matches(expected, mode) else { return false }
        }
        return source != 0 || current.origin == entry.origin
    }

    func isRestored(in states: [State]) -> Bool {
        entries.allSatisfy { entry in
            guard let current = Self.resolve(entry, in: states),
                  let source = expectedSource(for: entry, in: states) else { return false }
            return restored(entry, current: current, source: source)
        }
    }

    var isRestored: Bool {
        guard let current = try? Self.states() else { return false }
        return isRestored(in: current)
    }

    func hasDisconnectedDisplays(in states: [State]) -> Bool {
        entries.contains { Self.resolve($0, in: states) == nil }
    }

    var hasDisconnectedDisplays: Bool {
        guard let current = try? Self.states() else { return true }
        return hasDisconnectedDisplays(in: current)
    }

    func hasUnavailableDisplays(in states: [State]) -> Bool {
        entries.contains { Self.resolve($0, in: states)?.isAwake != true }
    }

    var hasUnavailableDisplays: Bool {
        guard let current = try? Self.states() else { return true }
        return hasUnavailableDisplays(in: current)
    }

    /// Read-only readiness check: partial wake-up mode lists must not consume a restore attempt.
    func hasAvailableModes(in states: [State], modesForDisplay: (UInt32) -> [DisplayMode]) -> Bool {
        entries.allSatisfy { entry in
            guard let screen = Self.resolve(entry, in: states), screen.isAwake,
                  let source = expectedSource(for: entry, in: states) else { return false }
            if restored(entry, current: screen, source: source) { return true }
            guard let expected = entry.mode else { return true }
            return Self.matchingMode(expected, in: modesForDisplay(screen.id)) != nil
        }
    }

    var hasAvailableModes: Bool {
        guard let current = try? Self.states() else { return false }
        return hasAvailableModes(in: current) { id in
            DisplayBackend.modes(for: id).map(DisplayBackend.describe)
        }
    }

    static func capture(displayID: UInt32? = nil) throws -> DisplaySnapshot {
        let current = try states()
        let selected = current.filter { displayID == nil || $0.id == displayID }
        if displayID != nil && selected.isEmpty {
            throw DisplayFailure(message: "显示器已断开，无法记录恢复设置。")
        }
        guard selected.allSatisfy({ screen in
            screen.persistentID != nil && screen.mode != nil && screen.isAwake &&
                current.filter({ $0.persistentID == screen.persistentID }).count == 1
        }) else {
            throw DisplayFailure(message: "未能识别显示器，暂不启用虚拟 HiDPI。请重新连接后重试。")
        }
        return DisplaySnapshot(entries: selected.map {
            Entry(id: $0.id, vendor: $0.vendor, product: $0.product, persistentID: $0.persistentID,
                  mode: $0.mode, source: $0.source, origin: $0.origin)
        })
    }

    func restore(ownedMirrorSource: UInt32? = nil) throws {
        let current = try Self.states()
        // An offline/asleep entry remains in this snapshot for the next reconnect attempt.
        // Already-restored screens are left alone rather than rewriting the whole desktop.
        let pending = entries.compactMap { entry -> (Entry, State, UInt32)? in
            guard let screen = Self.resolve(entry, in: current), screen.isAwake,
                  let source = expectedSource(for: entry, in: current),
                  !restored(entry, current: screen, source: source) else { return nil }
            return (entry, screen, source)
        }
        guard !pending.isEmpty else { return }
        guard pending.allSatisfy({ _, screen, source in
            Self.canRestoreMirror(currentSource: screen.source, expectedSource: source, ownedSource: ownedMirrorSource)
        }) else {
            throw DisplayFailure(message: "显示器已加入其他镜像，自动恢复已暂停。请先在系统设置中解除该镜像。")
        }

        let detach = pending.filter { $0.1.source != 0 && $0.1.source != $0.2 }
        if !detach.isEmpty {
            try DisplayBackend.configure { config in
                for (_, screen, _) in detach {
                    guard DisplayBackend.persistentID(for: screen.id) == screen.persistentID,
                          DisplayBackend.isAwake(screen.id),
                          CGDisplayMirrorsDisplay(screen.id) == screen.source else {
                        throw DisplayFailure(message: "显示器连接或镜像关系发生变化，已暂停恢复。")
                    }
                    try DisplayBackend.check(CGConfigureDisplayMirrorOfDisplay(config, screen.id, 0), "解除镜像")
                }
            }
        }

        // Resolve every mode before applying the transaction. If the monitor is still
        // negotiating its full mode list, preserve the baseline and retry after settling.
        let prepared = try pending.map { entry, screen, source -> (Entry, State, UInt32, CGDisplayMode?) in
            guard let expected = entry.mode else { return (entry, screen, source, nil) }
            let modes = DisplayBackend.modes(for: screen.id)
            guard let description = Self.matchingMode(expected, in: modes.map(DisplayBackend.describe)),
                  let fresh = modes.first(where: { DisplayBackend.describe($0) == description }) else {
                throw DisplayFailure(message: "显示器仍在重新连接，之前的分辨率暂未出现。已保留恢复设置。")
            }
            return (entry, screen, source, fresh)
        }
        try DisplayBackend.configure { config in
            for (entry, screen, source, mode) in prepared {
                guard DisplayBackend.persistentID(for: screen.id) == entry.persistentID,
                      DisplayBackend.isAwake(screen.id),
                      !(source == 0 && CGDisplayMirrorsDisplay(screen.id) == 0 && CGDisplayIsInMirrorSet(screen.id) != 0),
                      Self.canRestoreMirror(currentSource: CGDisplayMirrorsDisplay(screen.id),
                                            expectedSource: source, ownedSource: ownedMirrorSource) else {
                    throw DisplayFailure(message: "显示器连接或镜像关系发生变化，已暂停恢复。")
                }
                if let mode {
                    try DisplayBackend.check(CGConfigureDisplayWithDisplayMode(config, screen.id, mode, nil), "恢复分辨率")
                }
                if source == 0 {
                    try DisplayBackend.check(CGConfigureDisplayOrigin(config, screen.id,
                        Int32(entry.origin.x), Int32(entry.origin.y)), "恢复排列")
                }
            }
            for (_, screen, source, _) in prepared where source != 0 {
                try DisplayBackend.check(CGConfigureDisplayMirrorOfDisplay(config, screen.id, source), "恢复镜像")
            }
        }
    }
}
