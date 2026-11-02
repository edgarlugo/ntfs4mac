import Foundation

/// Runs the bundled `ntfs4mac` script. The app never talks to ntfs-3g directly:
/// the CLI is the single source of truth, so the app and Terminal behave the same.
enum CLI {
    struct Result {
        let status: Int32
        let output: String
        var ok: Bool { status == 0 }
    }

    static var script: URL { Bundle.main.url(forResource: "ntfs4mac", withExtension: nil)! }
    static var askpass: URL { Bundle.main.url(forResource: "askpass", withExtension: nil)! }

    /// `onLine` streams output as it arrives (used for the install log).
    static func run(_ args: [String], onLine: (@Sendable (String) -> Void)? = nil) async -> Result {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path] + args

            var env = ProcessInfo.processInfo.environment
            // sudo -A asks for the password through a native macOS dialog.
            env["SUDO_ASKPASS"] = askpass.path
            env["NTFS4MAC_PROMPT"] = String(localized: "ntfs4mac needs your Mac password to change how the drive is mounted.")
            env["NTFS4MAC_OK"] = String(localized: "OK")
            env["NTFS4MAC_CANCEL"] = String(localized: "Cancel")
            if let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
                env["NTFS4MAC_ICON"] = icon.path
            }
            process.environment = env

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            let buffer = OutputBuffer()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                buffer.append(text)
                if let onLine { text.split(separator: "\n").forEach { onLine(String($0)) } }
            }
            process.terminationHandler = { p in
                pipe.fileHandleForReading.readabilityHandler = nil
                let rest = pipe.fileHandleForReading.readDataToEndOfFile()
                if let text = String(data: rest, encoding: .utf8), !text.isEmpty {
                    buffer.append(text)
                    if let onLine { text.split(separator: "\n").forEach { onLine(String($0)) } }
                }
                continuation.resume(returning: Result(status: p.terminationStatus, output: buffer.text))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: Result(status: -1, output: error.localizedDescription))
            }
        }
    }
}

private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""
    func append(_ s: String) { lock.lock(); storage += s; lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return storage }
}
