import SwiftUI
import AppKit
import Combine
import CoreGraphics
import Darwin
import SmartDPICore

@main struct SmartDPILauncher {
    @MainActor static func main() {
        signal(SIGPIPE, SIG_IGN)
        if TrialWatchdog.runIfRequested() { return }
        if let flag = CommandLine.arguments.firstIndex(of: "--render-icon"),
           CommandLine.arguments.indices.contains(flag + 1) {
            do { try AppIconRenderer.write(to: CommandLine.arguments[flag + 1]) }
            catch { FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8)); exit(1) }
            return
        }
        if let flag = CommandLine.arguments.firstIndex(of: "--render-preview"),
           CommandLine.arguments.indices.contains(flag + 1) {
            renderPreview(to: CommandLine.arguments[flag + 1])
            return
        }
        if CommandLine.arguments.contains("--diagnostics") {
            let store = DisplayStore()
            do {
                let data = try store.diagnosticsJSON()
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            } catch {
                FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
                exit(1)
            }
            return
        }
        SmartDPIApplication.main()
    }

    @MainActor private static func renderPreview(to path: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let store = DisplayStore(isDemo: true)
        if let flag = CommandLine.arguments.firstIndex(of: "--preview-displays"),
           CommandLine.arguments.indices.contains(flag + 1) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
                store.displays = try JSONDecoder().decode([DisplayInfo].self, from: data)
                if let display = store.displays.first { store.selectDisplay(id: display.id) }
                else { store.selectedDisplayID = nil }
            } catch {
                FileHandle.standardError.write(Data("无法读取预览显示数据：\(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
        if CommandLine.arguments.contains("--virtual-preview") { store.useVirtual = true }
        if CommandLine.arguments.contains("--empty-preview") { store.displays = []; store.selectedDisplayID = nil }
        if CommandLine.arguments.contains("--missing-hidpi-preview"), let display = store.displays.first {
            store.displays = [DisplayInfo(id: display.id, name: display.name, isBuiltin: false, isMain: true,
                vendor: display.vendor, product: display.product, mirrorSource: 0, currentMode: display.currentMode,
                modes: display.modes.filter { !$0.isHiDPI })]
            store.selectDisplay(id: display.id)
        }
        if CommandLine.arguments.contains("--hidpi-preview") || CommandLine.arguments.contains("--virtual-preview"), let display = store.displays.first,
           let mode = display.modes.first(where: { $0.isHiDPI }) {
            store.displays = [DisplayInfo(id: display.id, name: display.name, isBuiltin: false, isMain: true,
                vendor: display.vendor, product: display.product, mirrorSource: 0, currentMode: mode,
                modes: display.modes)]
        }
        if CommandLine.arguments.contains("--virtual-preview") { store.activeVirtual = true }
        if CommandLine.arguments.contains("--unknown-preview"), let display = store.displays.first {
            store.displays = [DisplayInfo(id: display.id, name: display.name, isBuiltin: false, isMain: true,
                vendor: display.vendor, product: display.product, mirrorSource: 0, currentMode: nil,
                modes: display.modes)]
        }
        if CommandLine.arguments.contains("--mirror-preview"), let display = store.displays.first {
            store.displays = [DisplayInfo(id: display.id, name: display.name, isBuiltin: false, isMain: true,
                vendor: display.vendor, product: display.product, mirrorSource: 1000,
                currentMode: display.currentMode, modes: display.modes, isInMirrorSet: true)]
        }
        if CommandLine.arguments.contains("--recovery-preview") {
            store.recoveryPending = true
            store.error = "恢复显示配置时遇到问题，请关闭全屏应用后点击“重试恢复”。"
        }
        if CommandLine.arguments.contains("--busy-preview") { store.busy = true }
        if CommandLine.arguments.contains("--rate-preview") { store.menuRefreshRate = 75 }
        let dark = CommandLine.arguments.contains("--dark-preview")
        app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let menu = CommandLine.arguments.contains("--menu-preview")
        let compact = CommandLine.arguments.contains("--compact-preview")
        let menuHeight = min(MenuBarPanel.preferredHeight(for: store), compact ? 420 : 620)
        let size = menu ? CGSize(width: 390, height: menuHeight) :
            (compact ? CGSize(width: 640, height: 440) : CGSize(width: 1080, height: 820))
        let root: AnyView = menu ? AnyView(MenuBarPanel(store: store,
            initiallyShowsDisplayDetails: CommandLine.arguments.contains("--details-preview"),
            maximumHeight: compact ? 420 : nil, openMainWindow: {})) :
            AnyView(ContentView(store: store))
        let content = root.frame(width: size.width, height: size.height)
            .environment(\.colorScheme, dark ? .dark : .light)
        let view = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        // Allow SwiftUI's initial layout to settle, with no display configuration calls.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            FileHandle.standardError.write(Data("无法渲染界面预览。\n".utf8)); exit(1)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        do {
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw DisplayFailure(message: "无法生成 PNG。")
            }
            try png.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch { FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8)); exit(1) }
        window.close()
    }
}

struct SmartDPIApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = DisplayStore(isDemo: CommandLine.arguments.contains("--demo"))
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("SmartDPI", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 640, minHeight: 440)
                .onAppear { delegate.connect(store) }
        }
        .defaultSize(width: 920, height: 660)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("显示器") {
                Button("刷新显示器") { store.refresh() }.keyboardShortcut("r")
                Button("恢复原设置") {
                    if store.recoveryPending { store.revertChanges() } else { store.undoLastChange() }
                }
                .disabled(!store.canUndo && !store.recoveryPending)
                Button("导出诊断信息…") { store.exportDiagnostics() }
            }
        }

        MenuBarExtra {
            MenuBarPanel(store: store) {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .onAppear {
                delegate.connect(store)
                store.refresh()
            }
        } label: {
            Image(systemName: "display")
                .accessibilityLabel("SmartDPI")
                .help("SmartDPI \(store.appVersion) · \(store.selectedDisplay?.name ?? "未连接显示器") · \(store.currentMode == nil ? "状态未报告" : store.isHiDPIEnabled ? "HiDPI 已开启" : "HiDPI 未开启")")
                .onAppear { delegate.connect(store) }
        }
        .menuBarExtraStyle(.window)
    }
}

private func displayReconfigured(_ id: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags,
                                 _ context: UnsafeMutableRawPointer?) {
    guard !flags.contains(.beginConfigurationFlag), let context else { return }
    let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
    Task { @MainActor in delegate.scheduleRefresh() }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var store: DisplayStore?
    private var connected = false
    private var refreshTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var virtualHealthTimer: Timer?
    private var virtualStateObserver: AnyCancellable?
    private var observers: [NSObjectProtocol] = []

    func connect(_ store: DisplayStore) {
        self.store = store
        guard !connected else { return }
        connected = true
        CGDisplayRegisterReconfigurationCallback(displayReconfigured, Unmanaged.passUnretained(self).toOpaque())
        for notification in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: notification,
                object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        // Stop temporary mirroring before sleep; reconnect is always manual.
                        if self?.store?.busy == true || self?.store?.activeVirtual == true || self?.store?.pendingSeconds != nil {
                            self?.store?.revertChanges()
                        }
                    }
                })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleRefresh() }
            })
        // CoreGraphics callbacks handle changes promptly. This is only a fallback
        // for a missed notification, avoiding mode enumeration twenty times a minute.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.store?.refresh() }
        }
        pollTimer?.tolerance = 5
        virtualStateObserver = store.$activeVirtual.removeDuplicates().sink { [weak self] active in
            self?.monitorVirtualDisplay(active)
        }
    }

    private func monitorVirtualDisplay(_ active: Bool) {
        virtualHealthTimer?.invalidate()
        virtualHealthTimer = nil
        guard active else { return }
        // Only an owned mirror needs frequent supervision. This checks its current
        // mode and relationship without rebuilding all physical mode lists.
        virtualHealthTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.store?.checkVirtualHealth() }
        }
        virtualHealthTimer?.tolerance = 0.5
    }

    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.store?.refresh()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        store?.shutdown()
        pollTimer?.invalidate()
        virtualHealthTimer?.invalidate()
        virtualStateObserver?.cancel()
        refreshTask?.cancel()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        if connected {
            CGDisplayRemoveReconfigurationCallback(displayReconfigured, Unmanaged.passUnretained(self).toOpaque())
        }
    }
}
