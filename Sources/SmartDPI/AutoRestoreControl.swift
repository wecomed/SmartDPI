import SwiftUI

struct AutoRestoreControl: View {
    @ObservedObject var store: DisplayStore

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Toggle("重新连接后恢复 HiDPI", isOn: Binding(
                    get: { store.autoRestoreHiDPI }, set: { store.setAutoRestoreHiDPI($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .fixedSize()
                    .disabled(store.isDemo || store.busy)
                Button("重试") { store.retryAutomaticRestore() }
                    .disabled(!store.canRetryAutomaticRestore)
                    .help("重新读取模式并尝试恢复保存的 HiDPI；如果系统仍未识别完整模式，请在系统显示设置中检测显示器。")
                Spacer(minLength: 0)
            }
            Text(store.automaticRestoreDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(store.automaticRestoreDescription)
            Text(store.displayRecognitionWarning ?? " ")
                .font(.caption2)
                .foregroundStyle(.orange)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26, alignment: .topLeading)
                .help(store.displayRecognitionWarning ?? "")
                .accessibilityHidden(store.displayRecognitionWarning == nil)
        }
        .font(.caption)
        .padding(.horizontal, 16)
        // Reserve warning space even while recognition is healthy, so a reconnect
        // does not move the resolution rows beneath the pointer.
        .frame(height: 80)
    }
}
