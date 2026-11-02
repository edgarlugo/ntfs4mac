import AppKit
import Quartz
import SwiftUI
import UniformTypeIdentifiers

/// Finder-like file browser for a mounted drive: path bar, file table, Quick Look preview and details.
struct BrowserView: View {
    @EnvironmentObject var store: DriveStore
    @StateObject private var browser: Browser
    let drive: Drive

    @State private var showInspector = true
    @State private var renaming: FileItem?
    @State private var newName = ""
    @State private var confirmDelete: [FileItem] = []
    @State private var dropTargeted = false

    init(drive: Drive, root: URL) {
        self.drive = drive
        _browser = StateObject(wrappedValue: Browser(root: root, writable: drive.state == .readWrite))
    }

    private var selected: [FileItem] { browser.selectedItems }

    var body: some View {
        VStack(spacing: 0) {
            DriveBar(drive: drive)
            Divider()
            navigationBar
            Divider()
            HSplitView {
                fileTable
                    .frame(minWidth: 380)
                if showInspector {
                    Inspector(item: selected.count == 1 ? selected.first : nil, count: selected.count)
                        .frame(minWidth: 240, idealWidth: 280, maxWidth: 420)
                }
            }
            statusBar
        }
        .navigationTitle(drive.name)
        .searchable(text: $browser.search, placement: .toolbar, prompt: Text("Search this folder"))
        .toolbar { toolbarItems }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") { if let item = renaming { browser.rename(item, to: newName) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { !confirmDelete.isEmpty }, set: { if !$0 { confirmDelete = [] } })) {
            Button("Delete", role: .destructive) { browser.delete(confirmDelete); confirmDelete = [] }
        } message: {
            Text("Files on this drive can't be moved to the Trash. This can't be undone.")
        }
        .onChange(of: store.notice) { _ in browser.reload() }
    }

    private var deleteTitle: String {
        confirmDelete.count == 1
            ? String(localized: "Delete “\(confirmDelete[0].name)”?")
            : String(localized: "Delete \(confirmDelete.count) items?")
    }

    // MARK: Pieces

    private var navigationBar: some View {
        HStack(spacing: 6) {
            Button { browser.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!browser.canGoBack).help("Back")
            Button { browser.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!browser.canGoForward).help("Forward")
            Button { browser.goUp() } label: { Image(systemName: "arrow.turn.left.up") }
                .disabled(!browser.canGoUp).help("Enclosing folder")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(browser.pathComponents.enumerated()), id: \.element) { index, url in
                        if index > 0 { Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary) }
                        Button {
                            browser.navigate(to: url)
                        } label: {
                            Label(index == 0 ? drive.name : url.lastPathComponent,
                                  systemImage: index == 0 ? "externaldrive.fill" : "folder.fill")
                                .lineLimit(1)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private var fileTable: some View {
        Table(of: FileItem.self, selection: $browser.selection, sortOrder: $browser.sortOrder) {
            TableColumn("Name", value: \.name, comparator: .localizedStandard) { item in
                HStack(spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                        .resizable().frame(width: 18, height: 18)
                    Text(item.name).lineLimit(1)
                }
            }
            .width(min: 180, ideal: 280)
            TableColumn("Date Modified", value: \.sortDate) { item in
                Text(item.modified.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "--")
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 150)
            TableColumn("Size", value: \.sortSize) { item in
                Text(item.sizeText).foregroundStyle(.secondary).monospacedDigit()
            }
            .width(min: 60, ideal: 80)
            TableColumn("Kind", value: \.kind) { item in
                Text(item.kind).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 80, ideal: 130)
        } rows: {
            ForEach(browser.visibleItems) { item in
                TableRow(item).itemProvider { NSItemProvider(object: item.url as NSURL) }
            }
        }
        .contextMenu(forSelectionType: FileItem.ID.self) { ids in
            contextMenu(for: browser.items.filter { ids.contains($0.id) })
        } primaryAction: { ids in
            browser.open(ids)
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard browser.writable else { return false }
            loadURLs(providers) { browser.importFiles($0) }
            return true
        }
        .overlay {
            if dropTargeted && browser.writable {
                RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 3).padding(2)
            } else if browser.loading && browser.items.isEmpty {
                ProgressView()
            } else if !browser.loading && browser.visibleItems.isEmpty {
                Text(browser.search.isEmpty ? "This folder is empty" : "No results").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func contextMenu(for items: [FileItem]) -> some View {
        if items.isEmpty {
            if browser.writable {
                Button("New Folder") { browser.newFolder() }
                Button("Paste") { browser.paste() }.disabled(!browser.pasteboardHasFiles)
                Divider()
            }
            Button("Show in Finder") { browser.revealInFinder([]) }
        } else {
            Button("Open") { browser.open(Set(items.map(\.id))) }
            Button("Show in Finder") { browser.revealInFinder(items) }
            Divider()
            Button("Copy") { browser.copyToPasteboard(items) }
            Button("Copy to…") { chooseExportFolder(items) }
            if browser.writable {
                if items.count == 1, let item = items.first {
                    Button("Rename…") { newName = item.name; renaming = item }
                }
                Divider()
                Button("Delete…", role: .destructive) { confirmDelete = items }
            }
        }
    }

    @ToolbarContentBuilder private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup {
            if browser.writable {
                Button { browser.newFolder() } label: { Label("New Folder", systemImage: "folder.badge.plus") }
                    .help("New Folder")
                Button { chooseImportFiles() } label: { Label("Add Files", systemImage: "square.and.arrow.down") }
                    .help("Copy files from your Mac into this folder")
                Button { confirmDelete = selected } label: { Label("Delete", systemImage: "trash") }
                    .disabled(selected.isEmpty).help("Delete")
            }
            Button { chooseExportFolder(selected) } label: { Label("Copy to Mac", systemImage: "square.and.arrow.up") }
                .disabled(selected.isEmpty).help("Copy the selection to a folder on your Mac")
            Toggle(isOn: $browser.showHidden) { Label("Hidden Files", systemImage: "eye") }
                .help("Show hidden and system files")
            Toggle(isOn: $showInspector) { Label("Preview", systemImage: "sidebar.right") }
                .help("Show preview and details")
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if let message = browser.busyMessage {
                ProgressView().controlSize(.small)
                Text(message)
            } else if let error = browser.error {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error).lineLimit(1)
            } else {
                Text(statusText)
            }
            Spacer()
            if !browser.writable {
                Label("Read-only", systemImage: "lock.fill").foregroundStyle(.orange)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(.bar)
    }

    private var statusText: String {
        let total = browser.visibleItems.count
        let free = drive.capacity.map { ByteCountFormatter.string(fromByteCount: $0.available, countStyle: .file) } ?? "--"
        return selected.isEmpty
            ? String(localized: "\(total) items, \(free) available")
            : String(localized: "\(selected.count) of \(total) selected, \(free) available")
    }

    // MARK: Panels

    private func chooseImportFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = String(localized: "Copy Here")
        panel.message = String(localized: "Choose files or folders to copy to \(drive.name)")
        if panel.runModal() == .OK { browser.importFiles(panel.urls) }
    }

    private func chooseExportFolder(_ items: [FileItem]) {
        guard !items.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Copy Here")
        panel.message = String(localized: "Choose where to copy \(items.count) item(s) on your Mac")
        if panel.runModal() == .OK, let folder = panel.url { browser.exportFiles(items, to: folder) }
    }

    private func loadURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(urls) }
    }
}

// MARK: - Drive bar (compact header above the browser)

struct DriveBar: View {
    @EnvironmentObject var store: DriveStore
    let drive: Drive

    var body: some View {
        HStack(spacing: 12) {
            if let path = drive.mountPoint {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 34, height: 34)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(drive.name).font(.headline)
                    StateBadge(state: drive.state)
                }
                if let cap = drive.capacity {
                    HStack(spacing: 8) {
                        ProgressView(value: Double(cap.total - cap.available), total: Double(cap.total))
                            .frame(width: 140)
                        Text("\(ByteCountFormatter.string(fromByteCount: cap.available, countStyle: .file)) available of \(ByteCountFormatter.string(fromByteCount: cap.total, countStyle: .file))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            let busy = store.busy.contains(drive.id)
            if drive.state == .readOnly {
                Button { store.enableWriting(drive) } label: {
                    ActionLabel(title: "Enable writing", systemImage: "pencil.and.outline", busy: busy)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Menu {
                    Button("Remove hidden macOS files (._*)") { store.clean(drive) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Button { store.eject(drive) } label: {
                    ActionLabel(title: "Eject safely", systemImage: "eject", busy: busy)
                }
            }
        }
        .disabled(store.busy.contains(drive.id))
        .padding(.horizontal, 14).padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if let message = store.error ?? store.notice {
                Banner(text: message, style: store.error != nil ? .error : .success)
                    .padding(8)
                    .offset(y: 56)
                    .onTapGesture { store.error = nil; store.notice = nil }
            }
        }
        .zIndex(1)
    }
}

// MARK: - Inspector: Quick Look preview + details

struct Inspector: View {
    let item: FileItem?
    let count: Int

    var body: some View {
        VStack(spacing: 0) {
            if let item {
                QuickLookPreview(url: item.url)
                    .frame(minHeight: 200, maxHeight: .infinity)
                Divider()
                details(item)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: count > 1 ? "doc.on.doc" : "eye")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(count > 1 ? "\(count) items selected" : "Select a file to preview it")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func details(_ item: FileItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.name).font(.headline).lineLimit(3).textSelection(.enabled)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                row("Kind", item.kind)
                if let size = item.size {
                    row("Size", ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                        + " (" + size.formatted() + " " + String(localized: "bytes") + ")")
                }
                if let d = item.created { row("Created", d.formatted(date: .long, time: .shortened)) }
                if let d = item.modified { row("Modified", d.formatted(date: .long, time: .shortened)) }
                row("Where", item.url.deletingLastPathComponent().path)
            }
            .font(.callout)
            HStack {
                Button("Open") { NSWorkspace.shared.open(item.url) }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled).lineLimit(3)
        }
    }
}

/// Native Quick Look: images, video, audio, PDF, text, Office documents…
struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = true
        view.shouldCloseWithWindow = false
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) as URL? != url { view.previewItem = url as NSURL }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.close()
    }
}
