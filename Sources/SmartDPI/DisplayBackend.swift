import AppKit
import CoreGraphics
import SmartDPICore

struct DisplayFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum DisplayBackend {
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
                        modes: modes(for: id).map(describe), isInMirrorSet: CGDisplayIsInMirrorSet(id) != 0)
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

struct DisplaySnapshot {
    struct Entry {
        let id: UInt32
        let vendor: UInt32
        let product: UInt32
        let mode: CGDisplayMode?
        let source: UInt32
        let origin: CGPoint
    }
    let entries: [Entry]

    var isRestored: Bool {
        entries.allSatisfy { entry in
            guard CGDisplayIsOnline(entry.id) != 0,
                  CGDisplayVendorNumber(entry.id) == entry.vendor,
                  CGDisplayModelNumber(entry.id) == entry.product else { return true }
            guard CGDisplayMirrorsDisplay(entry.id) == entry.source else { return false }
            if let mode = entry.mode, !DisplayBackend.currentMatches(DisplayBackend.describe(mode), on: entry.id) {
                return false
            }
            return true
        }
    }

    static func capture() throws -> DisplaySnapshot {
        DisplaySnapshot(entries: try DisplayBackend.onlineIDs().map {
            Entry(id: $0, vendor: CGDisplayVendorNumber($0), product: CGDisplayModelNumber($0),
                  mode: CGDisplayCopyDisplayMode($0), source: CGDisplayMirrorsDisplay($0),
                  origin: CGDisplayBounds($0).origin)
        })
    }

    func restore() throws {
        let online = Set(try DisplayBackend.onlineIDs())
        let connected = entries.filter {
            online.contains($0.id) && CGDisplayVendorNumber($0.id) == $0.vendor && CGDisplayModelNumber($0.id) == $0.product
        }
        guard !connected.isEmpty else { return }
        try DisplayBackend.configure { config in
            // Break our mirror first, then restore the previous modes and arrangement.
            for entry in connected {
                try DisplayBackend.check(CGConfigureDisplayMirrorOfDisplay(config, entry.id, 0), "解除镜像")
            }
            for entry in connected {
                if let mode = entry.mode {
                    try DisplayBackend.check(CGConfigureDisplayWithDisplayMode(config, entry.id, mode, nil), "恢复分辨率")
                }
                if entry.source == 0 {
                    try DisplayBackend.check(CGConfigureDisplayOrigin(config, entry.id,
                        Int32(entry.origin.x), Int32(entry.origin.y)), "恢复排列")
                }
            }
            for entry in connected where entry.source != 0 && online.contains(entry.source) {
                try DisplayBackend.check(CGConfigureDisplayMirrorOfDisplay(config, entry.id, entry.source), "恢复镜像")
            }
        }
    }
}
