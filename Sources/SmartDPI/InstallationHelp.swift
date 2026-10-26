import AppKit

@MainActor enum InstallationHelp {
    static func open() {
        if let guide = Bundle.main.url(forResource: "INSTALLATION", withExtension: "html") {
            NSWorkspace.shared.open(guide)
        } else if let project = URL(string: "https://github.com/wecomed/SmartDPI#下载与安装") {
            NSWorkspace.shared.open(project)
        }
    }
}
