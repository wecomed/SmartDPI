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
                .disabled(store.isDemo || store.busy)
            Button("重试") { store.retryAutomaticRestore() }
                .disabled(!store.canRetryAutomaticRestore)
                .help("重新读取模式并尝试恢复保存的 HiDPI，不改变系统连接方式。")
            }
            Text(store.automaticRestoreDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(store.automaticRestoreDescription)
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .frame(height: 54)
    }
}
