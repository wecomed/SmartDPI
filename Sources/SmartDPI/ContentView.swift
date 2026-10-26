import SwiftUI
import SmartDPICore

// Some CLT distributions omit the SDK 27 State macro plugin.
private typealias ViewState<Value> = SwiftUI.State<Value>

struct ContentView: View {
    @ObservedObject var store: DisplayStore
    @ViewState private var showDisplayDetails = false
    @ViewState private var showHiDPIHelp = false

    private var controlsLocked: Bool { store.busy || store.recoveryPending }

    private var displaySelection: Binding<UInt32?> {
        Binding(get: { store.selectedDisplayID }, set: { id in
            guard let id, !controlsLocked, !store.activeVirtual else { return }
            store.selectDisplay(id: id)
        })
    }

    private var refreshSelection: Binding<Double?> {
        Binding(get: { store.menuRefreshRate }, set: { rate in
            let displayID = store.selectedDisplayID
            Task { await store.setRefreshRate(rate, expectedDisplayID: displayID) }
        })
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 250)
        } detail: {
            detail
                .navigationTitle(store.selectedDisplay?.name ?? "SmartDPI")
                .toolbar {
                    ToolbarItemGroup(placement: .automatic) {
                        Button { store.refresh() } label: {
                            Label("刷新显示器", systemImage: "arrow.clockwise")
                        }
                        .disabled(controlsLocked || store.isDemo)
                        .help("重新读取已连接的显示器与可用分辨率")
                        Menu {
                            Button { store.openSystemSettings() } label: {
                                Label("系统显示设置", systemImage: "slider.horizontal.3")
                            }
                            Button { store.exportDiagnostics() } label: {
                                Label("导出诊断信息", systemImage: "square.and.arrow.up")
                            }
                            Divider()
                            Button { InstallationHelp.open() } label: {
                                Label("安装与首次使用指南", systemImage: "book")
                            }
                        } label: {
                            Label("更多操作", systemImage: "ellipsis.circle")
                        }
                        .help("显示设置、诊断与安装指南")
                    }
                }
        }
        .frame(minWidth: 640, minHeight: 440)
        .transaction { $0.animation = nil }
    }

    private var sidebar: some View {
        List(selection: displaySelection) {
            Section("显示器") {
                ForEach(store.displays) { display in
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(display.name).lineLimit(2)
                            Text(display.isMain ? "主显示器" : display.isBuiltin ? "内建显示器" : "外接显示器")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } icon: {
                        Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                    }
                    .tag(display.id)
                }
                if store.displays.isEmpty {
                    Text("未检测到显示器").foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .disabled(controlsLocked || store.activeVirtual)
        .navigationTitle("SmartDPI")
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SmartDPI \(store.appVersion)")
                    .font(.caption.weight(.medium))
                    .textSelection(.enabled)
                Text("也可以从菜单栏直接调整。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var detail: some View {
        VStack(spacing: 0) {
            if let display = store.selectedDisplay {
                displaySummary(display)
                Divider()
                resolutionHeader
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if store.displayOptions.isEmpty { noOptions }
                        ForEach(store.displayOptions) { option in
                            resolutionRow(option)
                            Divider().padding(.leading, 36)
                        }
                        displayDetails(display)
                            .padding(.top, 18)
                            .padding(.bottom, 20)
                    }
                    .padding(.horizontal, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func displaySummary(_ display: DisplayInfo) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("看起来像 \(store.currentMode?.title ?? "读取中…")")
                    .font(.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                currentHiDPIBadge
            }
            Text("物理面板 \(nativeSizeLabel(display))  ·  当前 \(store.currentMode?.refreshLabel ?? "刷新率未报告")\(store.activeVirtual ? " · 系统镜像" : "")")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(height: 76)
    }

    private var currentHiDPIBadge: some View {
        Label(
            store.currentMode == nil ? "HiDPI 未知" : store.isHiDPIEnabled ? "HiDPI 开" : "HiDPI 关",
            systemImage: store.currentMode == nil ? "questionmark.circle" : store.isHiDPIEnabled ? "checkmark.circle.fill" : "circle"
        )
        .font(.caption.weight(.medium))
        .foregroundStyle(store.isHiDPIEnabled ? Color.green : Color.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(store.isHiDPIEnabled ? Color.green.opacity(0.10) : Color.secondary.opacity(0.08), in: Capsule())
        .fixedSize()
    }

    private var resolutionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("选择分辨率").font(.headline)
                Spacer(minLength: 8)
                Picker("刷新率", selection: refreshSelection) {
                    Text("自动").tag(Optional<Double>.none)
                    ForEach(store.unifiedRefreshRates, id: \.self) { rate in
                        Text(ModePolicy.refreshLabel(rate)).tag(Optional(rate))
                    }
                }
                .frame(width: 174)
                .disabled(controlsLocked || store.isDemo || store.currentOption == nil)
                .help("更改后立即应用。自动优先保持当前刷新率；所选分辨率不支持时会匹配可用刷新率。")
            }
            Text("点击立即生效。数值越小，文字越大；HiDPI 开启后更细腻。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .frame(height: 76)
    }

    private func resolutionRow(_ option: DisplayOption) -> some View {
        let current = store.isCurrentOption(option)
        let unavailableReason = store.optionUnavailableReason(option)
        let refreshLabel = store.optionRefreshRate(option).map(ModePolicy.refreshLabel) ?? "系统协商"
        return Button {
            let displayID = store.selectedDisplayID
            Task { await store.applyOption(id: option.id, expectedDisplayID: displayID) }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: current ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(current ? Color.accentColor : Color.secondary.opacity(0.6))
                    .font(.system(size: 17))
                    .frame(width: 20)
                Text(option.title)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(option.isHiDPI ? "HiDPI 开" : "HiDPI 关")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(option.isHiDPI ? Color.primary : Color.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .frame(width: 72)
                    .background(option.isHiDPI ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06), in: Capsule())
                Text(refreshLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 66, alignment: .trailing)
                Image(systemName: unavailableReason == nil ? "chevron.right" : "info.circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)
                    .opacity(current && unavailableReason == nil ? 0 : 1)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .contentShape(Rectangle())
            .background(current ? Color.accentColor.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!store.canApplyOption(option))
        .help(unavailableReason ?? "\(option.title)，HiDPI \(option.isHiDPI ? "开" : "关")，\(refreshLabel)。点击立即应用。" + (option.requiresVirtual ? "此尺寸由 SmartDPI 补充，使用时需保持软件运行；实际可用性以应用结果为准。" : ""))
        .accessibilityLabel("\(option.title)，HiDPI \(option.isHiDPI ? "开启" : "关闭")，\(current ? "当前，" : "")\(refreshLabel)")
        .accessibilityHint(unavailableReason ?? "立即应用这个分辨率")
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    private func displayDetails(_ display: DisplayInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            DisclosureGroup("显示详情", isExpanded: $showDisplayDetails) {
                VStack(alignment: .leading, spacing: 10) {
                    if let mode = store.currentMode {
                        LabeledContent("内部渲染尺寸", value: "\(mode.pixelWidth) × \(mode.pixelHeight)")
                        LabeledContent("渲染比例", value: mode.scaleLabel)
                    }
                    Text("内部渲染尺寸用于绘制更细腻的文字，桌面大小由“看起来像”决定，显示器的物理像素不变。")
                    if display.nativeSizeIsEstimated { Text("面板尺寸根据系统报告的模式推算。") }
                    if store.activeVirtual {
                        LabeledContent("显示方式", value: "虚拟屏幕 → 系统镜像")
                        Text("系统显示设置中出现的 SmartDPI HiDPI 是虚拟桌面，macOS 将它映射到你的物理屏幕。请保持 SmartDPI 运行，退出会恢复之前的显示设置。")
                        LabeledContent("物理输出刷新率", value: "未取得独立读数")
                    }
                    Text("渲染尺寸越大、刷新率越高，图形系统需要处理的像素就越多。相关开销分布在 GPU、WindowServer 和各应用中，不能只看 SmartDPI 的进程占用。")
                    LabeledContent("运行架构", value: RuntimeCompatibility.architectureLabel)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
            }
            DisclosureGroup("相同分辨率，HiDPI 开和关有什么区别？", isExpanded: $showHiDPIHelp) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("两者的文字和窗口大小相同。HiDPI 开启后，macOS 会用更多像素绘制内容，再映射到屏幕，文字通常更细腻。")
                    Text("例如，2K 屏幕选择“1920 × 1080 · HiDPI 开”，就会获得 1080p 的界面大小，面板仍是 2560 × 1440。")
                    Text("列表已经合并系统模式与 SmartDPI 补充的 HiDPI 选项。部分选项需要保持 SmartDPI 运行；可用分辨率和刷新率由当前屏幕、连接方式与系统决定。")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Group {
                if store.busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: store.error != nil || store.recoveryPending ? "exclamationmark.triangle" : "info.circle")
                        .foregroundStyle(store.error != nil || store.recoveryPending ? Color.orange : Color.secondary)
                }
            }
            .frame(width: 18, height: 18)
            Text(feedbackText)
                .font(.caption)
                .foregroundStyle(store.error != nil ? Color.orange : Color.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(feedbackText)
            if store.recoveryPending {
                Button("重试恢复") { store.revertChanges() }
                    .disabled(store.busy || store.isDemo)
                    .modifier(NativeActionAppearance())
                    .frame(width: 92)
            } else {
                Button("恢复原设置") { store.undoLastChange() }
                    .disabled(!store.canUndo || store.busy || store.isDemo)
                    .modifier(NativeActionAppearance())
                    .help("恢复到这次调整之前的显示设置")
                    .frame(width: 92)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .background(.bar)
    }

    private var feedbackText: String {
        if store.busy { return "正在调整显示设置…" }
        if let error = store.error { return error }
        if store.recoveryPending { return "显示设置尚未完全恢复，请重试恢复。" }
        if store.isDemo { return "演示模式：仅预览界面，不会更改显示设置。" }
        if let status = store.status { return status }
        if store.selectedDisplay?.isInMirrorSet == true && !store.activeVirtual {
            return "当前正在镜像。请先在系统显示设置中解除镜像，再调整分辨率。"
        }
        if store.activeVirtual { return "HiDPI 正在运行，请保持 SmartDPI 开启。可直接选择其他分辨率。" }
        return "更改立即生效；需要恢复时，点击“恢复原设置”。"
    }

    private var noOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("尚未取得可用分辨率", systemImage: "text.magnifyingglass").font(.headline)
            Text("请刷新显示器，或在系统显示设置中检查连接。").foregroundStyle(.secondary)
        }
        .padding(.vertical, 24)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "display")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("连接显示器，调整文字大小").font(.title2.weight(.semibold))
            Text("连接并开启屏幕后，刷新显示器列表。\nSmartDPI 会列出可选择的分辨率与 HiDPI 选项。")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("刷新显示器") { store.refresh() }
                .buttonStyle(.borderedProminent)
                .disabled(controlsLocked || store.isDemo)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func nativeSizeLabel(_ display: DisplayInfo) -> String {
        guard let width = display.nativeWidth, let height = display.nativeHeight else { return "系统未报告" }
        return "\(width) × \(height)\(display.nativeSizeIsEstimated ? "（估计）" : "")"
    }
}
