import AppKit
import Combine
import CoreGraphics
import SmartDPICore
import VirtualDisplayBridge

@MainActor final class DisplayStore: ObservableObject {
    @Published var displays: [DisplayInfo] = []
    @Published var selectedDisplayID: UInt32?
    @Published var selectedResolutionID: String? { didSet { reconcileRefreshRate() } }
    @Published var selectedRefreshRate: Double?
    @Published var menuRefreshRate: Double?
    @Published var selectedPresetID = "1920x1080"
    @Published var useVirtual = false { didSet { selectedRefreshRate = nil; reconcileMenuRefreshRate() } }
    @Published var showAllModes = false { didSet { reconcileModeSelection() } }
    @Published var busy = false
    @Published var pendingSeconds: Int?
    @Published var status: String?
    @Published var error: String?
    @Published var activeVirtual = false
    @Published var recoveryPending = false
    @Published private var virtualModeSnapshot: DisplayMode?
    let isDemo: Bool

    private var virtualDisplay: SDVirtualDisplay?
    private var virtualTarget: UInt32?
    private var virtualBaseline: DisplaySnapshot?
    private var virtualExpectedPreset: HiDPIPreset?
    private var virtualExpectedRate: Double?
    private var virtualPhysicalDisplay: DisplayInfo?
    private var originalMode: (display: UInt32, vendor: UInt32, product: UInt32, mode: CGDisplayMode)?
    private var undoMode: (display: UInt32, vendor: UInt32, product: UInt32, mode: CGDisplayMode)?
    private var applyingMode: DisplayMode?
    private var applyingOptions: [DisplayOption]?
    private var trialExpectedMode: DisplayMode?
    private var watchdog: TrialWatchdog?
    private var operationGeneration = 0
    private var optionsSnapshot: (display: DisplayInfo, includesVirtual: Bool, options: [DisplayOption])?
    // The Objective-C classes are fixed for the lifetime of this process.
    private let virtualAPIAvailable = SDVirtualDisplay.available

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
    }

    private var physicalDisplay: DisplayInfo? {
        if selectedDisplayID == virtualTarget { return virtualPhysicalDisplay ?? selectedDisplay }
        return selectedDisplay
    }

    var displayOptions: [DisplayOption] {
        if busy, let applyingOptions { return applyingOptions }
        guard let display = physicalDisplay else { return [] }
        if let cached = optionsSnapshot, cached.display == display,
           cached.includesVirtual == isVirtualAvailable { return cached.options }
        let options = DisplayOption.choices(for: display, includeVirtual: isVirtualAvailable)
        // Include the complete snapshot: rates, native geometry and built-in/mirror state
        // can change without the display ID or resolution count changing.
        optionsSnapshot = (display, isVirtualAvailable, options)
        return options
    }

    var currentOption: DisplayOption? { displayOptions.first(where: isCurrentOption) }
    var unifiedRefreshRates: [Double] { currentOption?.refreshRates ?? [] }

    func isCurrentOption(_ option: DisplayOption) -> Bool {
        guard let mode = currentMode else { return false }
        return option.width == mode.width && option.height == mode.height && option.isHiDPI == mode.isHiDPI
    }

    func optionRefreshRate(_ option: DisplayOption) -> Double? {
        if !option.requiresVirtual {
            let rate = option.nativeMode(requestedRate: menuRefreshRate, currentRate: currentMode?.refreshRate)?.refreshRate
            return rate.flatMap { $0 > 0 ? $0 : nil }
        }
        for preferred in [menuRefreshRate, currentMode?.refreshRate].compactMap({ $0 }) {
            if let rate = option.refreshRates.first(where: { abs($0 - preferred) <= 0.01 }) { return rate }
        }
        return option.refreshRates.max()
    }

    func optionUnavailableReason(_ option: DisplayOption) -> String? {
        if isDemo { return "演示模式不会更改显示设置。" }
        if busy { return "正在调整显示设置…" }
        if recoveryPending { return "请先重试恢复显示设置。" }
        guard let display = selectedDisplay, displayOptions.contains(where: { $0.id == option.id }) else {
            return "显示器或此分辨率已不可用，请刷新列表。"
        }
        let ownMirror = activeVirtual && selectedDisplayID == virtualTarget && display.mirrorSource == virtualDisplay?.displayID
        if display.isInMirrorSet && !ownMirror { return "请先在系统显示设置中解除此显示器的镜像。" }
        if option.requiresVirtual && (!isVirtualAvailable || display.isBuiltin) { return "此显示器暂不支持这个 HiDPI 尺寸。" }
        if option.requiresVirtual && optionRefreshRate(option) == nil { return "系统尚未报告此显示器的可用刷新率。" }
        return nil
    }

    func canApplyOption(_ option: DisplayOption) -> Bool {
        guard optionUnavailableReason(option) == nil else { return false }
        if option.requiresVirtual {
            return !isCurrentOption(option) || optionRefreshRate(option).map { abs($0 - (currentMode?.refreshRate ?? 0)) > 0.01 } == true
        }
        guard let wanted = option.nativeMode(requestedRate: menuRefreshRate, currentRate: currentMode?.refreshRate) else { return false }
        return activeVirtual || currentMode.map { !wanted.matchesConfiguration(of: $0) } ?? true
    }

    func applyOption(id: String, expectedDisplayID: UInt32? = nil) async {
        guard expectedDisplayID == nil || expectedDisplayID == selectedDisplayID,
              let option = displayOptions.first(where: { $0.id == id }), canApplyOption(option),
              let display = physicalDisplay else { return }
        // Capture the requested mode before unmirroring changes the OS mode list.
        let wanted = option.nativeMode(requestedRate: menuRefreshRate, currentRate: currentMode?.refreshRate)
        let rate = optionRefreshRate(option)
        await performChange(on: display, nativeMode: wanted,
                            preset: option.requiresVirtual ? option.preset : nil, rate: rate)
        if let requested = menuRefreshRate, !unifiedRefreshRates.contains(where: { abs($0 - requested) <= 0.01 }) {
            menuRefreshRate = nil
        }
    }

    func setRefreshRate(_ rate: Double?, expectedDisplayID: UInt32? = nil) async {
        guard expectedDisplayID == nil || expectedDisplayID == selectedDisplayID,
              !isDemo, !busy, !recoveryPending, let option = currentOption,
              optionUnavailableReason(option) == nil else { return }
        if let rate, !option.refreshRates.contains(where: { abs($0 - rate) <= 0.01 }) { return }
        menuRefreshRate = rate
        await applyOption(id: option.id, expectedDisplayID: selectedDisplayID)
    }

    var canUndo: Bool {
        !isDemo && !busy && !recoveryPending &&
            (activeVirtual || (undoMode != nil && undoMode?.display == selectedDisplayID))
    }

    func undoLastChange() {
        guard canUndo else { return }
        if activeVirtual { revertChanges(); return }
        originalMode = undoMode
        undoMode = nil
        revertChanges()
    }

    var selectedDisplay: DisplayInfo? { displays.first { $0.id == selectedDisplayID } }
    var availableModes: [DisplayMode] {
        ModePolicy.sortedModes(selectedDisplay?.modes ?? [], hiDPIOnly: !showAllModes)
    }
    var resolutionChoices: [ResolutionChoice] {
        ModePolicy.resolutionChoices(modes: selectedDisplay?.modes ?? [], hiDPIOnly: !showAllModes)
    }
    var menuResolutionChoices: [ResolutionChoice] {
        ModePolicy.resolutionChoices(modes: selectedDisplay?.modes ?? [], hiDPIOnly: false)
    }
    var menuRefreshRates: [Double] {
        if useVirtual { return refreshRates }
        return ModePolicy.uniqueRates(menuResolutionChoices.flatMap(\.refreshRates)).sorted(by: >)
    }
    var menuPresetRefreshRate: Double? {
        guard let display = virtualPhysicalDisplay ?? selectedDisplay else { return nil }
        if let requested = menuRefreshRate,
           let rate = ModePolicy.virtualRefreshRates(for: display).first(where: { abs($0 - requested) < 0.01 }) {
            return rate
        }
        return ModePolicy.preferredVirtualRefreshRate(for: display)
    }
    private var menuSelectionLocked: Bool {
        busy || pendingSeconds != nil || activeVirtual || recoveryPending
    }

    func menuMode(for choice: ResolutionChoice) -> DisplayMode? {
        guard let offered = menuResolutionChoices.first(where: { $0.id == choice.id }) else { return nil }
        let rate = menuRefreshRate.flatMap { requested in
            offered.refreshRates.first { abs($0 - requested) < 0.01 }
        }
        return ModePolicy.resolveMode(choice: offered, requestedRate: rate,
                                      currentRate: currentMode?.refreshRate)
    }

    func canApplyMenuResolution(id: String) -> Bool {
        guard !isDemo, !menuSelectionLocked, let display = selectedDisplay, !display.isInMirrorSet,
              let choice = menuResolutionChoices.first(where: { $0.id == id }),
              let wanted = menuMode(for: choice) else { return false }
        return currentMode.map { !wanted.matchesConfiguration(of: $0) } ?? true
    }

    @discardableResult func selectMenuResolution(id: String, expectedDisplayID: UInt32? = nil) -> Bool {
        guard expectedDisplayID == nil || expectedDisplayID == selectedDisplayID,
              !menuSelectionLocked,
              let choice = menuResolutionChoices.first(where: { $0.id == id }) else { return false }
        let requestedRate = menuRefreshRate
        if useVirtual { useVirtual = false }
        // The compact panel includes ordinary modes so users can also leave HiDPI.
        if !choice.isHiDPI { showAllModes = true }
        selectedResolutionID = choice.id
        // Source/filter reconciliation can reset the preference. Retain it only when this row offers it.
        selectedRefreshRate = requestedRate.flatMap { requested in
            choice.refreshRates.first { abs($0 - requested) < 0.01 }
        }
        return true
    }

    func applyMenuResolution(id: String, expectedDisplayID: UInt32? = nil) async {
        guard expectedDisplayID == nil || expectedDisplayID == selectedDisplayID,
              canApplyMenuResolution(id: id), selectMenuResolution(id: id, expectedDisplayID: expectedDisplayID) else { return }
        await applySelection()
    }

    func canApplyMenuPreset(id: String) -> Bool {
        guard !isDemo, !menuSelectionLocked, let display = selectedDisplay,
              isVirtualAvailable, ModePolicy.supportsVirtualTarget(display, managedSource: virtualDisplay?.displayID),
              presets.contains(where: { $0.id == id }) else { return false }
        return ModePolicy.preferredVirtualRefreshRate(for: virtualPhysicalDisplay ?? display) != nil
    }

    @discardableResult func selectMenuPreset(id: String, expectedDisplayID: UInt32? = nil) -> Bool {
        guard expectedDisplayID == nil || expectedDisplayID == selectedDisplayID,
              !menuSelectionLocked, presets.contains(where: { $0.id == id }) else { return false }
        let requestedRate = menuRefreshRate
        if !useVirtual { useVirtual = true }
        selectedPresetID = id
        selectedRefreshRate = requestedRate.flatMap { requested in
            refreshRates.first { abs($0 - requested) < 0.01 }
        }
        return true
    }

    func applyMenuPreset(id: String, expectedDisplayID: UInt32? = nil) async {
        guard expectedDisplayID == nil || expectedDisplayID == selectedDisplayID,
              canApplyMenuPreset(id: id), selectMenuPreset(id: id, expectedDisplayID: expectedDisplayID) else { return }
        await applySelection()
    }
    var selectedResolution: ResolutionChoice? { resolutionChoices.first { $0.id == selectedResolutionID } }
    var selectedMode: DisplayMode? {
        guard let choice = selectedResolution else { return nil }
        return ModePolicy.resolveMode(choice: choice, requestedRate: selectedRefreshRate,
                                      currentRate: selectedDisplay?.currentMode?.refreshRate)
    }
    var selectedModeID: String? { selectedMode?.id }
    var presets: [HiDPIPreset] {
        guard let display = selectedDisplay else { return [] }
        return ModePolicy.presets(for: virtualPhysicalDisplay ?? display)
    }
    var selectedPreset: HiDPIPreset? { presets.first { $0.id == selectedPresetID } }
    var refreshRates: [Double] {
        if useVirtual {
            guard let display = virtualPhysicalDisplay ?? selectedDisplay else { return [] }
            return ModePolicy.virtualRefreshRates(for: display).sorted(by: >)
        }
        return selectedResolution?.refreshRates ?? []
    }
    var effectiveRefreshRate: Double? {
        if useVirtual {
            if let requested = selectedRefreshRate {
                return refreshRates.first { abs($0 - requested) < 0.01 }
            }
            guard let display = virtualPhysicalDisplay ?? selectedDisplay else { return nil }
            return ModePolicy.preferredVirtualRefreshRate(for: display)
        }
        guard let mode = selectedMode, mode.refreshRate > 0 else { return nil }
        return mode.refreshRate
    }
    var refreshNote: String? {
        if useVirtual {
            guard effectiveRefreshRate != nil else { return "系统未报告可用刷新率，暂不能创建兼容模式。请刷新设备或尝试另一连接方式。" }
            return "候选刷新率来自这台显示器的系统模式。兼容模式会验证虚拟桌面频率；镜像后的物理输出频率仍由 macOS 与连接决定。"
        }
        guard let mode = selectedMode else { return nil }
        if selectedRefreshRate != nil {
            return "所选桌面尺寸将使用 \(mode.refreshLabel)。更换尺寸时会重新匹配可用刷新率。"
        }
        if selectedRefreshRate == nil, let current = selectedDisplay?.currentMode?.refreshRate,
           current > 0, mode.refreshRate > 0, abs(mode.refreshRate - current) >= 0.01 {
            return "此缩放没有当前的 \(ModePolicy.refreshLabel(current)) 选项，自动选择该缩放可用的 \(mode.refreshLabel)。"
        }
        return "自动优先保持当前刷新率；若此缩放不支持，则选择该缩放可用的最高刷新率。"
    }
    var currentMode: DisplayMode? {
        if busy, let applyingMode { return applyingMode }
        if activeVirtual, selectedDisplayID == virtualTarget { return virtualModeSnapshot }
        return selectedDisplay?.currentMode
    }
    var isHiDPIEnabled: Bool {
        return currentMode?.isHiDPI == true
    }
    var canEnableHiDPI: Bool {
        guard !isDemo, !busy, !recoveryPending, pendingSeconds == nil, !activeVirtual,
              !isHiDPIEnabled, let display = selectedDisplay, !display.isInMirrorSet else { return false }
        let virtualPossible = !display.isBuiltin && isVirtualAvailable &&
            selectedPreset != nil && ModePolicy.preferredVirtualRefreshRate(for: display) != nil
        return useVirtual ? virtualPossible : recommendedNativeChoice != nil || virtualPossible
    }
    private var comfortableWidth: Double {
        let width = selectedDisplay?.nativeWidth ?? selectedDisplay?.currentMode?.width ?? 1920
        return Double(width) * (width >= 3840 ? 2.0 / 3.0 : 0.75)
    }
    private var recommendedNativeChoice: ResolutionChoice? {
        let choices = ModePolicy.resolutionChoices(modes: selectedDisplay?.modes ?? [], hiDPIOnly: true)
        let display = selectedDisplay
        let ratio = Double(display?.nativeHeight ?? display?.currentMode?.height ?? 1080) /
            Double(max(1, display?.nativeWidth ?? display?.currentMode?.width ?? 1920))
        return choices.filter { abs(Double($0.height) / Double($0.width) - ratio) < 0.02 }.min {
            abs(Double($0.width) - comfortableWidth) < abs(Double($1.width) - comfortableWidth)
        }
    }
    var isVirtualAvailable: Bool { virtualAPIAvailable }
    var canApply: Bool {
        guard !isDemo, !busy, !recoveryPending, pendingSeconds == nil, !activeVirtual, let display = selectedDisplay else { return false }
        if useVirtual {
            return isVirtualAvailable && ModePolicy.supportsVirtualTarget(display, managedSource: virtualDisplay?.displayID) &&
                selectedPreset != nil && effectiveRefreshRate != nil
        }
        guard !display.isInMirrorSet, let selected = selectedMode else { return false }
        return selectedDisplay?.currentMode.map { !selected.matchesConfiguration(of: $0) } ?? true
    }

    init(isDemo: Bool = false) {
        self.isDemo = isDemo
        if isDemo {
            let current = DisplayMode(modeID: 1, width: 2560, height: 1440, pixelWidth: 2560, pixelHeight: 1440, refreshRate: 75, isNative: true)
            let modes = [current,
                DisplayMode(modeID: 5, width: 2560, height: 1440, pixelWidth: 2560, pixelHeight: 1440, refreshRate: 60, isNative: true),
                DisplayMode(modeID: 2, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60),
                DisplayMode(modeID: 6, width: 2048, height: 1152, pixelWidth: 4096, pixelHeight: 2304, refreshRate: 60),
                DisplayMode(modeID: 3, width: 1600, height: 900, pixelWidth: 3200, pixelHeight: 1800, refreshRate: 60),
                DisplayMode(modeID: 4, width: 1280, height: 720, pixelWidth: 2560, pixelHeight: 1440, refreshRate: 60)]
            displays = [DisplayInfo(id: 99, name: "Redmi 2K · 演示", isBuiltin: false, isMain: true,
                                    vendor: 0, product: 0, mirrorSource: 0, currentMode: current, modes: modes)]
            selectDisplay(id: 99)
        } else { refresh() }
    }

    func selectDisplay(id: UInt32) {
        guard !busy, pendingSeconds == nil, !activeVirtual, !recoveryPending else { return }
        selectedDisplayID = id
        selectedResolutionID = nil
        selectedRefreshRate = nil
        menuRefreshRate = nil
        reconcileModeSelection()
        selectedPresetID = presets.min { abs(Double($0.width) - comfortableWidth) < abs(Double($1.width) - comfortableWidth) }?.id ?? ""
    }

    private func reconcileModeSelection() {
        if !resolutionChoices.contains(where: { $0.id == selectedResolutionID }) {
            selectedResolutionID = resolutionChoices.first(where: { choice in
                choice.modes.contains { candidate in
                    selectedDisplay?.currentMode.map { candidate.matchesConfiguration(of: $0) } == true
                }
            })?.id ?? recommendedNativeChoice?.id ?? resolutionChoices.first?.id
        }
        if !presets.contains(where: { $0.id == selectedPresetID }) {
            selectedPresetID = presets.min { abs(Double($0.width) - comfortableWidth) < abs(Double($1.width) - comfortableWidth) }?.id ?? ""
        }
        reconcileRefreshRate()
        reconcileMenuRefreshRate()
    }

    private func reconcileRefreshRate() {
        if let rate = selectedRefreshRate, !refreshRates.contains(where: { abs($0 - rate) < 0.01 }) {
            selectedRefreshRate = nil
        }
    }

    private func reconcileMenuRefreshRate() {
        if let requested = menuRefreshRate, !menuRefreshRates.contains(where: { abs($0 - requested) < 0.01 }) {
            menuRefreshRate = nil
        }
    }

    func enableHiDPI() async {
        guard canEnableHiDPI else { return }
        if useVirtual {
            // Keep the compatibility size and rate the user has already selected.
        } else if selectedResolution?.isHiDPI == true {
            // Keep an explicitly selected system HiDPI combination.
        } else if let choice = recommendedNativeChoice {
            useVirtual = false
            selectedRefreshRate = nil
            selectedResolutionID = choice.id
        } else {
            useVirtual = true
            selectedPresetID = presets.min { abs(Double($0.width) - comfortableWidth) < abs(Double($1.width) - comfortableWidth) }?.id ?? ""
        }
        await applySelection()
    }

    func refresh() { _ = refreshSnapshot(whileApplying: false) }

    /// Mirroring needs prompt liveness checks, but not a full enumeration of every mode.
    /// Display callbacks and the slow fallback still refresh the complete snapshot.
    func checkVirtualHealth() {
        guard !isDemo, !busy, activeVirtual else { return }
        guard let mode = readValidVirtualMode() else {
            revertChanges()
            error = "虚拟屏幕镜像或 HiDPI 模式已被系统改变，已停止虚拟屏幕。"
            return
        }
        if virtualModeSnapshot != mode { refresh() }
    }

    private func updateVirtualModeSnapshot(_ mode: DisplayMode?) {
        if virtualModeSnapshot != mode { virtualModeSnapshot = mode }
    }

    private func refreshSnapshot(whileApplying: Bool) -> Bool {
        guard !isDemo, !busy || whileApplying else { return false }
        do {
            var updated = try DisplayBackend.displays(excluding: virtualDisplay?.displayID)
            if let physical = virtualPhysicalDisplay, let index = updated.firstIndex(where: { $0.id == physical.id }) {
                let live = updated[index]
                updated[index] = DisplayInfo(id: live.id, name: physical.name, isBuiltin: live.isBuiltin,
                    isMain: live.isMain, vendor: live.vendor, product: live.product, mirrorSource: live.mirrorSource,
                    currentMode: live.currentMode, modes: physical.modes, isInMirrorSet: live.isInMirrorSet,
                    nativeWidth: physical.nativeWidth, nativeHeight: physical.nativeHeight,
                    nativeSizeIsEstimated: physical.nativeSizeIsEstimated)
            }
            if let target = virtualTarget, !updated.contains(where: { $0.id == target }) {
                // Never leave a headless virtual desktop after the cable is removed.
                revertChanges()
                status = "显示器已断开，已停止虚拟 HiDPI。"
                return false
            }
            if activeVirtual {
                guard let mode = readValidVirtualMode() else {
                    revertChanges()
                    error = "虚拟屏幕镜像或 HiDPI 模式已被系统改变，已停止虚拟屏幕。"
                    return false
                }
                updateVirtualModeSnapshot(mode)
            }
            // Publish only the complete snapshot, retaining monitor order across mirror changes.
            let previousOrder = Dictionary(uniqueKeysWithValues: displays.enumerated().map { ($0.element.id, $0.offset) })
            updated.sort {
                let lhs = previousOrder[$0.id] ?? Int.max
                let rhs = previousOrder[$1.id] ?? Int.max
                return lhs == rhs ? $0.id < $1.id : lhs < rhs
            }
            if updated != displays { displays = updated }
            if !displays.contains(where: { $0.id == selectedDisplayID }) {
                if pendingSeconds != nil { revertChanges(); return false }
                if let next = displays.first(where: { !$0.isBuiltin })?.id ?? displays.first?.id {
                    selectDisplay(id: next)
                } else {
                    selectedDisplayID = nil
                    selectedResolutionID = nil
                    selectedRefreshRate = nil
                    selectedPresetID = ""
                }
            }
            reconcileModeSelection()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func applySelection() async {
        guard canApply, let display = selectedDisplay else { return }
        await performChange(on: display, nativeMode: useVirtual ? nil : selectedMode,
                            preset: useVirtual ? selectedPreset : nil, rate: effectiveRefreshRate)
    }

    private func performChange(on display: DisplayInfo, nativeMode wanted: DisplayMode?,
                               preset: HiDPIPreset?, rate: Double?) async {
        guard !isDemo, !busy, !recoveryPending, wanted != nil || preset != nil else { return }
        applyingMode = currentMode
        applyingOptions = displayOptions
        error = nil
        status = "正在调整显示设置…"
        busy = true
        operationGeneration += 1
        let generation = operationGeneration
        do {
            if virtualDisplay != nil {
                try tearDownVirtualForChange()
                for _ in 0..<16 {
                    try await Task.sleep(nanoseconds: 125_000_000)
                    guard generation == operationGeneration, !Task.isCancelled else { throw CancellationError() }
                    if CGDisplayIsOnline(display.id) != 0 && CGDisplayIsInMirrorSet(display.id) == 0,
                       virtualBaseline?.isRestored != false { break }
                }
                guard CGDisplayIsOnline(display.id) != 0, CGDisplayIsInMirrorSet(display.id) == 0,
                      virtualBaseline?.isRestored != false else {
                    throw DisplayFailure(message: "显示器尚未结束镜像，请稍后重新选择分辨率。")
                }
                virtualBaseline = nil
            }
            guard CGDisplayVendorNumber(display.id) == display.vendor,
                  CGDisplayModelNumber(display.id) == display.product else {
                throw DisplayFailure(message: "显示器连接已变化，请刷新后重试。")
            }
            if let preset {
                guard let rate else { throw DisplayFailure(message: "未读到可用刷新率。") }
                try await startVirtual(preset: preset, rate: rate, target: display, generation: generation)
            } else {
                guard let wanted,
                      let mode = DisplayBackend.modes(for: display.id).first(where: {
                          $0.isUsableForDesktopGUI() && DisplayBackend.describe($0).matchesConfiguration(of: wanted)
                      }),
                      let original = CGDisplayCopyDisplayMode(display.id) else {
                    throw DisplayFailure(message: "显示模式已变化，请刷新后重试。")
                }
                originalMode = (display.id, display.vendor, display.product, original)
                trialExpectedMode = wanted
                watchdog = try TrialWatchdog(display: display.id, originalMode: original)
                try DisplayBackend.setMode(mode, on: display.id)
                guard DisplayBackend.currentMatches(wanted, on: display.id) else {
                    throw DisplayFailure(message: "系统没有应用所选的显示模式，已请求恢复原设置。")
                }
                // Allow WindowServer's reconfiguration events to settle before publishing the UI.
                try await Task.sleep(nanoseconds: 250_000_000)
                guard generation == operationGeneration, !Task.isCancelled else { throw CancellationError() }
                guard DisplayBackend.currentMatches(wanted, on: display.id) else {
                    throw DisplayFailure(message: "显示模式未能保持，请重试或选择其他尺寸。")
                }
            }
            guard generation == operationGeneration else { return }
            // Verified changes are committed automatically. There is no timed user confirmation.
            watchdog?.commit()
            watchdog = nil
            undoMode = originalMode
            originalMode = nil
            trialExpectedMode = nil
            pendingSeconds = nil
            let refreshed = refreshSnapshot(whileApplying: true)
            guard generation == operationGeneration else { return }
            applyingMode = nil
            applyingOptions = nil
            busy = false
            status = refreshed ? (activeVirtual ? "已生效。此 HiDPI 尺寸需要保持 SmartDPI 运行。" : "已生效。") :
                "设置已应用，暂未读到最新显示状态，请刷新。"
        } catch {
            guard generation == operationGeneration else { return }
            revertChanges()
            self.error = error.localizedDescription + (recoveryPending ? " 请点击“重试恢复”。" : " 已恢复原设置。")
        }
    }

    /// Keep the same operation and published list while changing an owned virtual desktop.
    private func tearDownVirtualForChange() throws {
        virtualDisplay?.invalidate()
        virtualDisplay = nil
        if let baseline = virtualBaseline { try baseline.restore() }
        virtualTarget = nil
        virtualExpectedPreset = nil
        virtualExpectedRate = nil
        virtualPhysicalDisplay = nil
        updateVirtualModeSnapshot(nil)
        activeVirtual = false
    }

    private func startVirtual(preset: HiDPIPreset, rate: Double, target: DisplayInfo, generation: Int) async throws {
        virtualBaseline = try DisplaySnapshot.capture()
        virtualPhysicalDisplay = target
        // Keep identity stable per target and requested size, without storing a hardware serial.
        let serial = ((target.vendor &* 31) ^ target.product ^ target.id ^ UInt32(preset.width &* 4096 &+ preset.height) ^ UInt32((rate * 100).rounded())) | 1
        let virtual = try SDVirtualDisplay(logicalWidth: UInt(preset.width), height: UInt(preset.height),
                                          refreshRate: rate, serial: serial)
        virtualDisplay = virtual
        virtualTarget = target.id
        virtualExpectedPreset = preset
        virtualExpectedRate = rate
        var wanted: CGDisplayMode?
        // WindowServer publishes virtual display modes asynchronously.
        for _ in 0..<24 {
            guard generation == operationGeneration, !Task.isCancelled else { throw CancellationError() }
            guard CGDisplayIsOnline(target.id) != 0 else { throw DisplayFailure(message: "显示器已断开。") }
            wanted = DisplayBackend.modes(for: virtual.displayID).first {
                $0.width == preset.width && $0.height == preset.height &&
                $0.pixelWidth == preset.width * 2 && $0.pixelHeight == preset.height * 2 &&
                abs($0.refreshRate - rate) < 0.01
            }
            if wanted != nil { break }
            try await Task.sleep(nanoseconds: 125_000_000)
        }
        guard let wanted else {
            throw DisplayFailure(message: "macOS 未提供此尺寸下 \(ModePolicy.refreshLabel(rate)) 的 2× HiDPI 模式。请尝试其他可用刷新率或更低的缩放尺寸。")
        }
        try DisplayBackend.configure(option: .forAppOnly) { config in
            try DisplayBackend.check(CGConfigureDisplayWithDisplayMode(config, virtual.displayID, wanted, nil), "设置虚拟 HiDPI")
            try DisplayBackend.check(CGConfigureDisplayMirrorOfDisplay(config, target.id, virtual.displayID), "建立显示器镜像")
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        guard generation == operationGeneration, !Task.isCancelled else { throw CancellationError() }
        guard CGDisplayMirrorsDisplay(target.id) == virtual.displayID else {
            throw DisplayFailure(message: "系统未建立虚拟屏幕镜像，已请求恢复原设置。")
        }
        // A mirror master may report no mode; its physical follower then describes the group.
        let actual = CGDisplayCopyDisplayMode(virtual.displayID) ?? CGDisplayCopyDisplayMode(target.id)
        guard let actual, actual.width == preset.width, actual.height == preset.height,
              actual.pixelWidth == preset.width * 2, actual.pixelHeight == preset.height * 2,
              abs(actual.refreshRate - rate) < 0.01 else {
            throw DisplayFailure(message: "镜像没有运行在请求的 HiDPI 尺寸与刷新率，已请求恢复原设置。")
        }
        updateVirtualModeSnapshot(DisplayBackend.describe(actual))
        activeVirtual = true
    }

    private func readValidVirtualMode() -> DisplayMode? {
        guard let virtual = virtualDisplay, let target = virtualTarget, let preset = virtualExpectedPreset, let rate = virtualExpectedRate,
              virtual.displayID != 0, CGDisplayIsOnline(target) != 0,
              CGDisplayMirrorsDisplay(target) == virtual.displayID,
              let mode = CGDisplayCopyDisplayMode(virtual.displayID) ?? CGDisplayCopyDisplayMode(target),
              mode.width == preset.width && mode.height == preset.height &&
            mode.pixelWidth == preset.width * 2 && mode.pixelHeight == preset.height * 2 &&
            abs(mode.refreshRate - rate) < 0.01 else { return nil }
        return DisplayBackend.describe(mode)
    }

    func revertChanges() {
        guard !isDemo else { return }
        operationGeneration += 1
        pendingSeconds = nil
        busy = false
        applyingMode = nil
        applyingOptions = nil
        var restoreError: Error?
        if let original = originalMode {
            if CGDisplayIsOnline(original.display) != 0,
               CGDisplayVendorNumber(original.display) == original.vendor,
               CGDisplayModelNumber(original.display) == original.product {
                do {
                    try DisplayBackend.setMode(original.mode, on: original.display)
                    guard DisplayBackend.currentMatches(DisplayBackend.describe(original.mode), on: original.display) else {
                        throw DisplayFailure(message: "系统尚未恢复到之前的模式。")
                    }
                    originalMode = nil
                } catch { restoreError = error }
            } else { originalMode = nil }
        }
        if restoreError == nil { watchdog?.commit() } else { watchdog?.restore() }
        watchdog = nil
        trialExpectedMode = nil
        if let virtual = virtualDisplay {
            // Remove the temporary source even when a restore transaction fails.
            virtual.invalidate()
            virtualDisplay = nil
        }
        if let baseline = virtualBaseline {
            do {
                try baseline.restore()
                guard baseline.isRestored else { throw DisplayFailure(message: "系统尚未恢复完整的显示配置。") }
                virtualBaseline = nil
            } catch { restoreError = error }
        }
        virtualTarget = nil
        virtualExpectedPreset = nil
        virtualExpectedRate = nil
        virtualPhysicalDisplay = nil
        updateVirtualModeSnapshot(nil)
        activeVirtual = false
        recoveryPending = originalMode != nil || virtualBaseline != nil
        if let restoreError {
            status = nil
            error = "恢复显示配置时遇到问题：\(restoreError.localizedDescription) 请关闭全屏应用后点击“重试恢复”。"
        } else { error = nil; status = "已恢复原显示设置。" }
        refresh()
    }

    func stopVirtual() { guard activeVirtual else { return }; revertChanges() }

    func shutdown() {
        if busy || pendingSeconds != nil || virtualDisplay != nil || recoveryPending { revertChanges() }
    }

    func openSystemSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!)
    }

    func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "SmartDPI-diagnostics.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            struct Report: Encodable {
                let appVersion: String
                let architecture: String
                let buildSDK: String
                let operatingSystem: String
                let virtualAPIAvailable: Bool
                let demo: Bool
                let displays: [DisplayInfo]
            }
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
            let report = Report(appVersion: version, architecture: RuntimeCompatibility.architectureLabel,
                                buildSDK: Bundle.main.object(forInfoDictionaryKey: "DTSDKName") as? String ?? "未报告",
                                operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                                virtualAPIAvailable: isVirtualAvailable, demo: isDemo, displays: displays)
            try encoder.encode(report).write(to: url, options: .atomic)
            status = "诊断信息已导出（包含显示模式，不含显示器序列号）。"
        } catch { self.error = error.localizedDescription }
    }

    func diagnosticsJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(displays)
    }
}
