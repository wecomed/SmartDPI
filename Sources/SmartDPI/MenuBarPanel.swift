import AppKit
import SwiftUI
import SmartDPICore

private typealias MenuViewState<Value> = SwiftUI.State<Value>

struct MenuBarPanel: View {
    @ObservedObject var store: DisplayStore
    var openMainWindow: () -> Void
    private let maximumHeight: CGFloat?
    @MenuViewState private var showsDisplayDetails: Bool
    @MenuViewState private var availablePanelHeight: CGFloat?

    init(store: DisplayStore, initiallyShowsDisplayDetails: Bool = false, maximumHeight: CGFloat? = nil,
         openMainWindow: @escaping () -> Void) {
        self.store = store
        self.openMainWindow = openMainWindow
        self.maximumHeight = maximumHeight
        _showsDisplayDetails = MenuViewState(initialValue: initiallyShowsDisplayDetails)
    }

    static func preferredHeight(for store: DisplayStore) -> CGFloat {
        // The popover must keep its size when a new mode changes the list or feedback.
        600
    }

    private var panelHeight: CGFloat {
        let preferred = Self.preferredHeight(for: store)
        return min(preferred, availablePanelHeight ?? preferred, maximumHeight ?? preferred)
    }

    private func cacheAvailableHeight() {
        if let maximumHeight {
            availablePanelHeight = maximumHeight
            return
        }
        // Read the screen once per opening, so display changes do not resize an open panel.
        let preferred = Self.preferredHeight(for: store)
        let available = (NSApp.keyWindow?.screen ?? NSScreen.main)?.visibleFrame.height ?? (preferred + 48)
        availablePanelHeight = max(300, available - 48)
    }

    private var controlsLocked: Bool { store.busy || store.recoveryPending }

    private var displaySelection: Binding<UInt32?> {
        Binding(get: { store.selectedDisplayID }, set: { id in
            guard let id, !controlsLocked, !store.activeVirtual else { return }
            store.selectDisplay(id: id)
        })
    }

    private var refreshSelection: Binding<Double?> {
        Binding(get: { store.menuRefreshRate }, set: { rate in
            guard !controlsLocked, !store.isDemo else { return }
            let displayID = store.selectedDisplayID
            Task { await store.setRefreshRate(rate, expectedDisplayID: displayID) }
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let display = store.selectedDisplay {
                currentStatus(display)
                Divider()
                selectionHeader
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(store.displayOptions) { option in
                            resolutionRow(option)
                        }
                        if store.displayOptions.isEmpty {
                            Text("暂未读取到可用分辨率，请刷新后重试。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 16)
                        }
                        displayDetails.padding(.top, 12)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            } else {
                emptyState
            }
            feedback
            footer
        }
        .frame(width: 390, height: panelHeight)
        .modifier(NativePanelBackground())
        .transaction { $0.animation = nil }
        .onAppear { cacheAvailableHeight() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "display").foregroundStyle(.secondary)
            Text("SmartDPI").font(.headline)
            Text("v\(store.appVersion)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            Button { store.refresh() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(controlsLocked || store.isDemo)
            .accessibilityLabel("重新读取显示器和可用分辨率")
            .help("重新读取显示器、当前状态与可用分辨率")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .frame(height: 42)
    }

    private func currentStatus(_ display: DisplayInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if store.displays.count > 1 {
                    Picker("显示器", selection: displaySelection) {
                        ForEach(store.displays) { candidate in
                            Text(candidate.name).tag(Optional(candidate.id))
                        }
                    }
                    .labelsHidden()
                    .disabled(controlsLocked || store.activeVirtual)
                } else {
                    Text(display.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .help(display.name)
                }
                Spacer(minLength: 0)
                statusBadge
            }
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("当前看起来像")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(store.currentMode?.title ?? "未报告")
                    .font(.body.weight(.semibold).monospacedDigit())
                Spacer(minLength: 0)
                Text(store.currentMode?.refreshLabel ?? "—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("\(display.nativeSizeIsEstimated ? "面板（估计）" : "物理面板") \(nativeSizeLabel(display))")
                Spacer(minLength: 4)
                if store.activeVirtual {
                    Label("系统镜像", systemImage: "rectangle.on.rectangle")
                        .help("当前尺寸通过虚拟屏幕镜像提供，系统显示设置中会出现 SmartDPI HiDPI。")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(height: 92, alignment: .top)
        .accessibilityElement(children: .contain)
    }

    private var statusBadge: some View {
        let reported = store.currentMode != nil
        let enabled = store.isHiDPIEnabled
        return Label(reported ? (enabled ? "HiDPI 开" : "HiDPI 关") : "状态未报告",
                     systemImage: reported ? (enabled ? "checkmark.circle.fill" : "circle") : "questionmark.circle")
            .font(.caption.weight(.medium))
            .foregroundStyle(reported && enabled ? Color.green : Color.secondary)
            .frame(width: 94, height: 25)
            .background(.quaternary, in: Capsule())
            .help("显示当前实际生效的 HiDPI 状态")
    }

    private var selectionHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("分辨率 · 看起来像").font(.callout.weight(.medium))
                Spacer(minLength: 10)
                Picker("刷新率", selection: refreshSelection) {
                    Text("自动").tag(Optional<Double>.none)
                    ForEach(store.unifiedRefreshRates, id: \.self) { rate in
                        Text(ModePolicy.refreshLabel(rate)).tag(Optional(rate))
                    }
                }
                .labelsHidden()
                .fixedSize()
                .disabled(controlsLocked || store.isDemo || store.unifiedRefreshRates.isEmpty)
                .help("更改后立即生效。自动优先保持当前刷新率；各分辨率可用的频率以行内显示为准。")
            }
            Text("点击立即生效。数值越小，文字和窗口越大。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 66)
    }

    private func resolutionRow(_ option: DisplayOption) -> some View {
        let current = store.isCurrentOption(option)
        let refresh = store.optionRefreshRate(option).map(ModePolicy.refreshLabel) ?? "未报告"
        return Button {
            let displayID = store.selectedDisplayID
            Task { await store.applyOption(id: option.id, expectedDisplayID: displayID) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: current ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(current ? Color.accentColor : Color.secondary.opacity(0.45))
                    .frame(width: 20)
                Text(option.title)
                    .font(.system(size: 14, weight: current ? .semibold : .medium).monospacedDigit())
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                Text(option.isHiDPI ? "HiDPI 开" : "HiDPI 关")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(option.isHiDPI ? Color.accentColor : Color.secondary)
                    .frame(width: 55, height: 22)
                    .background(option.isHiDPI ? Color.accentColor.opacity(0.09) : Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 4))
                Text(refresh)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 59, alignment: .trailing)
            }
            .padding(.horizontal, 9)
            .frame(height: 38)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(current ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!store.canApplyOption(option))
        .help(rowHelp(option, refresh: refresh))
        .accessibilityLabel("\(option.title)，HiDPI \(option.isHiDPI ? "开" : "关")，\(refresh)\(current ? "，当前桌面大小" : "")")
        .accessibilityHint("点击立即应用此分辨率")
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    private func rowHelp(_ option: DisplayOption, refresh: String) -> String {
        let message: String
        if let reason = store.optionUnavailableReason(option) {
            message = reason
        } else if store.isCurrentOption(option) {
            message = "当前桌面大小。HiDPI 开表示使用高清绘制；关表示普通绘制。"
        } else {
            message = "立即切换为看起来像 \(option.title)，HiDPI \(option.isHiDPI ? "开" : "关")，\(refresh)。"
        }
        return option.requiresVirtual
            ? message + " 此尺寸由 SmartDPI 补充，使用时需保持软件运行；实际可用性以应用结果为准。"
            : message
    }

    private var displayDetails: some View {
        DisclosureGroup("显示详情", isExpanded: $showsDisplayDetails) {
            VStack(alignment: .leading, spacing: 7) {
                metric("当前内部渲染尺寸", value: store.currentMode.map { "\($0.pixelWidth) × \($0.pixelHeight)" } ?? "未报告")
                metric("系统报告刷新率", value: store.currentMode?.refreshLabel ?? "未报告")
                Text("HiDPI 开：使用更多像素绘制文字和界面。列表中的尺寸表示桌面看起来的大小。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if store.activeVirtual {
                    metric("显示方式", value: "虚拟屏幕 → 系统镜像")
                    Text("系统显示设置中的 SmartDPI HiDPI 是当前桌面的绘制来源；macOS 把它映射到你的屏幕。使用期间请保持软件运行。")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("更高的渲染尺寸与刷新率会增加图形系统开销。SmartDPI 的进程内存不包含全部 GPU 与 WindowServer 用量。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
            .padding(.top, 7)
        }
        .font(.caption)
        .padding(.horizontal, 4)
    }

    private var feedback: some View {
        HStack(spacing: 8) {
            if store.busy {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: feedbackIcon)
                    .foregroundStyle(store.error == nil ? Color.secondary : Color.orange)
            }
            Text(feedbackText)
                .font(.caption)
                .foregroundStyle(store.error == nil ? Color.secondary : Color.orange)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(feedbackText)
            if store.recoveryPending, !store.busy {
                Button("重试恢复") { store.revertChanges() }
                    .controlSize(.small)
                    .disabled(store.isDemo)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(.bar)
        .accessibilityElement(children: .contain)
    }

    private var feedbackText: String {
        if store.busy { return "正在调整显示设置…" }
        if let error = store.error { return error }
        if store.recoveryPending { return "上次设置尚未恢复，请重试恢复。" }
        if store.isDemo { return "演示预览 · 不会更改实际显示设置" }
        if let status = store.status { return status }
        if store.selectedDisplay?.isInMirrorSet == true, !store.activeVirtual {
            return "当前为镜像显示，可在系统显示设置中调整。"
        }
        return "勾选表示当前尺寸。更改后可点“恢复原设置”返回。"
    }

    private var feedbackIcon: String {
        if store.error != nil || store.recoveryPending { return "exclamationmark.triangle" }
        if store.isDemo { return "eye" }
        return "info.circle"
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "display").font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
            Text("未检测到显示器").font(.headline)
            Text("连接并开启显示器后，刷新以读取可用分辨率。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("刷新显示器") { store.refresh() }
                .disabled(controlsLocked || store.isDemo)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                Button("打开主窗口", action: openMainWindow)
                Spacer(minLength: 0)
                Button {
                    store.undoLastChange()
                } label: {
                    Label("恢复原设置", systemImage: "arrow.uturn.backward")
                }
                .disabled(controlsLocked || store.isDemo || !store.canUndo)
                .modifier(NativeActionAppearance())
                .help("恢复更改前的显示设置")
                Menu {
                    Button("系统显示设置") { store.openSystemSettings() }
                    Button("导出诊断信息…") { store.exportDiagnostics() }
                    Divider()
                    Button("退出 SmartDPI") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("系统显示设置、诊断与退出")
            }
            .font(.caption)
            .buttonStyle(.borderless)
            .padding(.horizontal, 16)
            .frame(height: 40)
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).monospacedDigit()
        }
    }

    private func nativeSizeLabel(_ display: DisplayInfo) -> String {
        guard let width = display.nativeWidth, let height = display.nativeHeight else { return "未报告" }
        return "\(width) × \(height)"
    }
}
