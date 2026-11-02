import AppKit
import SwiftUI

struct Drive: Identifiable, Hashable {
    enum State: String { case readWrite = "read-write", readOnly = "read-only", unmounted }

    let id: String          // diskXsY
    let name: String
    let state: State
    let mountPoint: String? // nil when unmounted
    /// Free/total bytes, read once per refresh off the main thread (it is a round trip to the drive).
    var available: Int64? = nil
    var total: Int64? = nil

    var url: URL? { mountPoint.map { URL(fileURLWithPath: $0) } }

    var capacity: (available: Int64, total: Int64)? {
        guard let available, let total, total > 0 else { return nil }
        return (available, total)
    }

    nonisolated static func readCapacity(_ path: String) -> (Int64, Int64)? {
        guard let v = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey]),
              let free = v.volumeAvailableCapacity, let total = v.volumeTotalCapacity
        else { return nil }
        return (Int64(free), Int64(total))
    }
}

struct Setup: Equatable {
    var brew = false, clt = false, fuset = false, ntfs3g = false, macfuse = false
    var ready: Bool { fuset && ntfs3g }
}

@MainActor
final class DriveStore: ObservableObject {
    @Published var drives: [Drive] = []
    @Published var setup: Setup?
    @Published var selection: Drive.ID?
    @Published var busy: Set<Drive.ID> = []
    @Published var error: String?
    @Published var notice: String?

    @Published var installing = false
    @Published var installLog: [String] = []

    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.refresh() }
            })
        }
        // Plugging a drive in does not always post a mount notification; poll gently as a fallback.
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh(checkSetup: true) }
    }

    var selectedDrive: Drive? { drives.first { $0.id == selection } ?? drives.first }

    private var refreshing = false

    func refresh(checkSetup: Bool = false) async {
        // Mount notifications, the timer and user actions can all fire at once; one refresh is enough.
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        // The installation rarely changes: check it at launch, after installing, or while unfinished.
        if checkSetup || setup?.ready != true { await refreshSetup() }
        await refreshDrives()
    }

    private func refreshDrives() async {
        let list = await CLI.run(["list", "--porcelain"])
        let parsed: [Drive] = await Task.detached {
            list.output.split(separator: "\n").compactMap { line in
                let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard f.count == 4, let state = Drive.State(rawValue: f[2]) else { return nil }
                var d = Drive(id: f[0], name: f[1], state: state, mountPoint: f[3] == "-" ? nil : f[3])
                if let mp = d.mountPoint, let (free, total) = Drive.readCapacity(mp) {
                    d.available = free; d.total = total
                }
                return d
            }
        }.value
        if parsed != drives { drives = parsed }
        if selection == nil || !drives.contains(where: { $0.id == selection }) {
            selection = drives.first?.id
        }
    }

    private func refreshSetup() async {
        let doctor = await CLI.run(["doctor", "--porcelain"])
        var s = Setup()
        for line in doctor.output.split(separator: "\n") {
            let kv = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            let on = kv[1] == "1"
            switch kv[0] {
            case "brew": s.brew = on
            case "clt": s.clt = on
            case "fuset": s.fuset = on
            case "ntfs3g": s.ntfs3g = on
            case "macfuse": s.macfuse = on
            default: break
            }
        }
        if setup != s { setup = s }
    }

    // MARK: - Actions

    func enableWriting(_ drive: Drive, readOnly: Bool = false) {
        perform(drive, readOnly ? ["mount", "--ro", drive.id] : ["mount", drive.id],
                success: readOnly ? String(localized: "\(drive.name) is mounted read-only.")
                                  : String(localized: "\(drive.name) is ready: you can now copy, edit and delete files."))
    }

    func eject(_ drive: Drive) {
        perform(drive, ["unmount", drive.id],
                success: String(localized: "\(drive.name) was ejected. You can unplug it safely."))
    }

    func clean(_ drive: Drive) {
        guard let path = drive.mountPoint else { return }
        perform(drive, ["clean", path], success: String(localized: "Hidden macOS files removed from \(drive.name)."))
    }

    func openInFinder(_ drive: Drive) {
        guard let url = drive.url else { return }
        NSWorkspace.shared.open(url)
    }

    private func perform(_ drive: Drive, _ args: [String], success: String) {
        busy.insert(drive.id)
        error = nil; notice = nil
        Task {
            let result = await CLI.run(args)
            busy.remove(drive.id)
            if result.ok {
                notice = success
                // Success messages fade away on their own; errors stay until closed.
                Task {
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    if notice == success { withAnimation { notice = nil } }
                }
            } else {
                error = Self.friendlyError(result.output)
            }
            await refresh()
        }
    }

    static func friendlyError(_ output: String) -> String {
        let lower = output.lowercased()
        if lower.contains("hibernat") || lower.contains("unclean") || lower.contains("fast restart") {
            return String(localized: "Windows left this drive \"hibernated\" (Fast Startup), so writing to it could damage your files. Shut Windows down completely or turn off Fast Startup, then try again. Meanwhile you can open it read-only.")
        }
        if lower.contains("incorrect password") || lower.contains("no password was provided") || lower.contains("a password is required") {
            return String(localized: "The password was cancelled or incorrect.")
        }
        if lower.contains("busy") || lower.contains("close any app") {
            return String(localized: "The drive is in use. Close any app or Finder window that is using it and try again.")
        }
        // Last meaningful line from the CLI (they all start with ✘).
        let lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let message = lines.last { $0.hasPrefix("✘") }.map { String($0.dropFirst()).trimmingCharacters(in: .whitespaces) }
        return message ?? lines.last ?? String(localized: "Something went wrong.")
    }

    // MARK: - Install

    func install() {
        installing = true
        installLog = []
        error = nil
        Task {
            let result = await CLI.run(["install"]) { line in
                Task { @MainActor in self.installLog.append(line) }
            }
            installing = false
            if !result.ok { error = Self.friendlyError(result.output) }
            await refresh(checkSetup: true)
        }
    }

    func installCommandLineTools() {
        Task { _ = await runDetached("/usr/bin/xcode-select", ["--install"]) }
    }

    private func runDetached(_ path: String, _ args: [String]) async -> Int32 {
        await withCheckedContinuation { c in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            p.terminationHandler = { c.resume(returning: $0.terminationStatus) }
            do { try p.run() } catch { c.resume(returning: -1) }
        }
    }
}
