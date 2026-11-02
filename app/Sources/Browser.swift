import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FileItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64?        // nil for folders
    let modified: Date?
    let created: Date?
    let kind: String
    // Pre-formatted once when the folder is read, so scrolling never re-formats.
    let sizeText: String
    let dateText: String

    var id: URL { url }
    var sortSize: Int64 { size ?? -1 }
    var sortDate: Date { modified ?? .distantPast }

    /// Generic icon by type, cached. Asking the drive for each file's own icon is a
    /// network round trip per row with FUSE-T, which makes big folders stutter.
    @MainActor var icon: NSImage {
        let key = isDirectory ? (url.pathExtension.lowercased() == "app" ? "app" : "/") : url.pathExtension.lowercased()
        if let cached = IconCache.icons[key] { return cached }
        let type: UTType = isDirectory ? (key == "app" ? .applicationBundle : .folder)
                                       : (UTType(filenameExtension: key) ?? .data)
        let image = NSWorkspace.shared.icon(for: type)
        IconCache.icons[key] = image
        return image
    }

    static func == (a: FileItem, b: FileItem) -> Bool { a.url == b.url && a.modified == b.modified && a.size == b.size }
    func hash(into h: inout Hasher) { h.combine(url) }
}

@MainActor private enum IconCache { static var icons: [String: NSImage] = [:] }

/// Folder navigation and file operations for one mounted drive.
@MainActor
final class Browser: ObservableObject {
    let root: URL
    let writable: Bool

    @Published private(set) var current: URL
    @Published private(set) var items: [FileItem] = [] { didSet { updateVisible() } }
    /// Filtered + sorted rows. Stored, not computed: the table reads it on every redraw.
    @Published private(set) var visibleItems: [FileItem] = []
    @Published private(set) var loading = false
    @Published var selection: Set<FileItem.ID> = []
    @Published var sortOrder = [KeyPathComparator(\FileItem.name, comparator: .localizedStandard)] { didSet { updateVisible() } }
    @Published var search = "" { didSet { if search != oldValue { updateVisible() } } }
    @Published var showHidden = false { didSet { reload() } }
    @Published var busyMessage: String?
    @Published var error: String?

    private var backStack: [URL] = []
    private var forwardStack: [URL] = []

    /// Files Windows or macOS keep at the root that a beginner never needs to see.
    nonisolated private static let systemNames: Set<String> = ["$RECYCLE.BIN", "System Volume Information", ".Spotlight-V100", ".fseventsd", ".Trashes"]

    init(root: URL, writable: Bool) {
        self.root = root
        self.writable = writable
        self.current = root
        reload()
    }

    private func updateVisible() {
        let filtered = search.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(search) }
        visibleItems = filtered.sorted(using: sortOrder)
    }

    var selectedItems: [FileItem] {
        selection.isEmpty ? [] : items.filter { selection.contains($0.id) }
    }
    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var canGoUp: Bool { current.standardizedFileURL != root.standardizedFileURL }

    /// Root → current, for the path bar.
    var pathComponents: [URL] {
        var urls: [URL] = []
        var u = current.standardizedFileURL
        let r = root.standardizedFileURL
        while u.path.count >= r.path.count {
            urls.insert(u, at: 0)
            if u == r { break }
            u = u.deletingLastPathComponent()
        }
        return urls
    }

    // MARK: Navigation

    func reload() {
        let folder = current, showHidden = showHidden
        loading = true
        Task.detached(priority: .userInitiated) {
            let result = Result { try Browser.list(folder, showHidden: showHidden) }
            await MainActor.run {
                guard folder == self.current else { return }
                self.loading = false
                switch result {
                case .success(let list):
                    if list != self.items { self.items = list }
                    let ids = Set(list.map(\.id))
                    if !self.selection.isSubset(of: ids) { self.selection.formIntersection(ids) }
                case .failure(let e):
                    self.items = []
                    self.error = e.localizedDescription
                }
            }
        }
    }

    nonisolated private static func list(_ folder: URL, showHidden: Bool) throws -> [FileItem] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
                                      .creationDateKey, .localizedTypeDescriptionKey]
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys,
            options: showHidden ? [] : [.skipsHiddenFiles])
        return urls.compactMap { url in
            let name = url.lastPathComponent
            if !showHidden && (systemNames.contains(name) || name.hasPrefix("._")) { return nil }
            let v = try? url.resourceValues(forKeys: Set(keys))
            let dir = v?.isDirectory ?? false
            let size: Int64? = dir ? nil : Int64(v?.fileSize ?? 0)
            let modified = v?.contentModificationDate
            // NFS (FUSE-T) has no creation date and reports 1 Jan 1970; treat that as unknown.
            let created = v?.creationDate.flatMap { $0.timeIntervalSince1970 > 86_400 ? $0 : nil }
            return FileItem(url: url, name: name, isDirectory: dir, size: size,
                            modified: modified, created: created,
                            kind: v?.localizedTypeDescription ?? "",
                            sizeText: size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "--",
                            dateText: modified.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "--")
        }
    }

    func navigate(to url: URL, record: Bool = true) {
        guard url != current else { return }
        if record { backStack.append(current); forwardStack.removeAll() }
        current = url
        selection = []
        search = ""
        items = []   // show the spinner instead of the previous folder while the new one loads
        reload()
    }

    func goBack() { guard let u = backStack.popLast() else { return }; forwardStack.append(current); navigate(to: u, record: false) }
    func goForward() { guard let u = forwardStack.popLast() else { return }; backStack.append(current); navigate(to: u, record: false) }
    func goUp() { if canGoUp { navigate(to: current.deletingLastPathComponent()) } }

    /// Double-click: enter folders, open files with their default app.
    func open(_ ids: Set<FileItem.ID>) {
        let chosen = items.filter { ids.contains($0.id) }
        if chosen.count == 1, let only = chosen.first, only.isDirectory {
            navigate(to: only.url)
        } else {
            chosen.forEach { NSWorkspace.shared.open($0.url) }
        }
    }

    func revealInFinder(_ items: [FileItem]) {
        NSWorkspace.shared.activateFileViewerSelecting(items.isEmpty ? [current] : items.map(\.url))
    }

    // MARK: File operations

    func newFolder() {
        let base = String(localized: "untitled folder")
        let url = uniqueURL(in: current, name: base)
        run(String(localized: "Creating folder…")) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        } then: { self.selection = [url] }
    }

    func rename(_ item: FileItem, to newName: String) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != item.name else { return }
        let target = item.url.deletingLastPathComponent().appendingPathComponent(name)
        run(String(localized: "Renaming…")) {
            try FileManager.default.moveItem(at: item.url, to: target)
        } then: { self.selection = [target] }
    }

    func delete(_ items: [FileItem]) {
        let urls = items.map(\.url)
        run(String(localized: "Deleting…")) {
            for url in urls { try FileManager.default.removeItem(at: url) }
        }
    }

    /// Copies files from anywhere on the Mac into the current folder.
    func importFiles(_ urls: [URL], into folder: URL? = nil) {
        let dest = folder ?? current
        let sources = urls.filter { $0.standardizedFileURL.deletingLastPathComponent() != dest.standardizedFileURL }
        guard !sources.isEmpty else { return }
        run(String(localized: "Copying \(sources.count) item(s)…")) {
            for src in sources {
                try FileManager.default.copyItem(at: src, to: self.uniqueURL(in: dest, name: src.lastPathComponent))
            }
        }
    }

    func exportFiles(_ items: [FileItem], to folder: URL) {
        let sources = items.map(\.url)
        run(String(localized: "Copying \(sources.count) item(s)…")) {
            for src in sources {
                try FileManager.default.copyItem(at: src, to: self.uniqueURL(in: folder, name: src.lastPathComponent))
            }
        } then: { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
    }

    func copyToPasteboard(_ items: [FileItem]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(items.map { $0.url as NSURL })
    }

    var pasteboardHasFiles: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    func paste() {
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        importFiles(urls)
    }

    /// "photo.jpg" → "photo 2.jpg" when the name is taken, like Finder.
    nonisolated func uniqueURL(in folder: URL, name: String) -> URL {
        var url = folder.appendingPathComponent(name)
        let ext = url.pathExtension
        let stem = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)")
            n += 1
        }
        return url
    }

    /// Runs file work off the main thread, shows progress, reports errors, then reloads.
    private func run(_ message: String, _ work: @escaping @Sendable () throws -> Void, then done: (() -> Void)? = nil) {
        busyMessage = message
        error = nil
        Task.detached(priority: .userInitiated) {
            let failure: Error? = { do { try work(); return nil } catch { return error } }()
            await MainActor.run {
                self.busyMessage = nil
                if let failure { self.error = failure.localizedDescription } else { done?() }
                self.reload()
            }
        }
    }
}
