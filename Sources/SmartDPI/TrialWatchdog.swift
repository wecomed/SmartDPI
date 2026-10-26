import Foundation
import CoreGraphics
import Darwin

/// Restores an interrupted native change if the app stalls before verification.
/// Successful changes commit immediately; there is no user confirmation timer.
final class TrialWatchdog {
    private let process: Process
    private let input: Pipe

    init(display: UInt32, originalMode: CGDisplayMode) throws {
        process = Process()
        input = Pipe()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = ["--trial-watchdog", String(display), String(originalMode.ioDisplayModeID),
                             String(CGDisplayVendorNumber(display)), String(CGDisplayModelNumber(display))]
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Only the child may hold the read end; EOF must arrive when this process exits.
        try? input.fileHandleForReading.close()
    }

    func commit() { send("commit\n"); close() }
    func restore() { close() }

    private func send(_ text: String) { try? input.fileHandleForWriting.write(contentsOf: Data(text.utf8)) }
    private func close() { try? input.fileHandleForWriting.close() }
    deinit { close() }

    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard args.count > 1, args[1] == "--trial-watchdog" else { return false }
        guard args.count == 6, let display = UInt32(args[2]), let modeID = Int32(args[3]),
              let vendor = UInt32(args[4]), let product = UInt32(args[5]) else { return true }
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        var buffer = ""
        while ProcessInfo.processInfo.systemUptime < deadline {
            var fd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN | POLLHUP), revents: 0)
            let result = poll(&fd, 1, 100)
            if result < 0 { if errno == EINTR { continue }; break }
            if result > 0 {
                var bytes = [UInt8](repeating: 0, count: 128)
                let count = read(STDIN_FILENO, &bytes, bytes.count)
                if count <= 0 { break }
                buffer += String(decoding: bytes.prefix(count), as: UTF8.self)
                if buffer.contains("commit\n") { return true }

            }
        }
        if CGDisplayIsOnline(display) != 0,
           CGDisplayVendorNumber(display) == vendor, CGDisplayModelNumber(display) == product,
           let original = DisplayBackend.modes(for: display).first(where: { $0.ioDisplayModeID == modeID }) {
            try? DisplayBackend.setMode(original, on: display)
        }
        return true
    }
}
