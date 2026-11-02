import AppKit
import SwiftUI

// MARK: - Window

struct ContentView: View {
    @EnvironmentObject var store: DriveStore

    var body: some View {
        Group {
            if let setup = store.setup, !setup.ready {
                SetupView(setup: setup)
            } else if store.setup == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NavigationSplitView {
                    Sidebar()
                        .navigationSplitViewColumnWidth(min: 200, ideal: 230)
                } detail: {
                    if let drive = store.selectedDrive {
                        DriveDetail(drive: drive)
                    } else {
                        EmptyState()
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button { Task { await store.refresh() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh")
            }
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject var store: DriveStore

    var body: some View {
        List(selection: $store.selection) {
            Section("NTFS Drives") {
                ForEach(store.drives) { drive in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(drive.name).lineLimit(1)
                            Text(drive.state.title).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "externaldrive.fill").foregroundStyle(drive.state.color)
                    }
                    .tag(drive.id)
                    .contextMenu { DriveMenu(drive: drive) }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if store.drives.isEmpty {
                Text("No NTFS drives").foregroundStyle(.secondary)
            }
        }
    }
}

struct EmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text("Plug in an NTFS drive").font(.title2.weight(.semibold))
            Text("Drives formatted on Windows will appear here automatically.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Drive detail

struct DriveDetail: View {
    @EnvironmentObject var store: DriveStore
    let drive: Drive

    private var busy: Bool { store.busy.contains(drive.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let cap = drive.capacity { CapacityBar(available: cap.available, total: cap.total) }
                StateExplanation(state: drive.state)
                actions
                if let error = store.error { Banner(text: error, style: .error) }
                if let notice = store.notice { Banner(text: notice, style: .success) }
                Spacer(minLength: 0)
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(drive.name)
    }

    private var header: some View {
        HStack(spacing: 18) {
            Image(nsImage: driveIcon)
                .resizable()
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text(drive.name).font(.title.weight(.semibold))
                HStack(spacing: 8) {
                    StateBadge(state: drive.state)
                    Text(verbatim: "NTFS · \(drive.id)").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var driveIcon: NSImage {
        if let path = drive.mountPoint { return NSWorkspace.shared.icon(forFile: path) }
        return NSImage(systemSymbolName: "externaldrive.fill", accessibilityDescription: nil) ?? NSImage()
    }

    @ViewBuilder private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch drive.state {
            case .readOnly, .unmounted:
                Button { store.enableWriting(drive) } label: {
                    ActionLabel(title: "Enable writing", systemImage: "pencil.and.outline", busy: busy)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                HStack {
                    if drive.state == .readOnly {
                        Button("Open in Finder") { store.openInFinder(drive) }
                    } else {
                        Button("Open read-only") { store.enableWriting(drive, readOnly: true) }
                    }
                }
                .disabled(busy)
            case .readWrite:
                HStack(spacing: 10) {
                    Button { store.openInFinder(drive) } label: {
                        ActionLabel(title: "Open in Finder", systemImage: "folder", busy: false)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Button { store.eject(drive) } label: {
                        ActionLabel(title: "Eject safely", systemImage: "eject", busy: busy)
                    }
                    .controlSize(.large)
                }
                Button("Remove hidden macOS files (._*)") { store.clean(drive) }
                    .disabled(busy)
                    .help("macOS leaves small ._ files when it copies to this drive. They are harmless, but Windows shows them.")
            }
        }
        .disabled(busy)
    }
}

struct DriveMenu: View {
    @EnvironmentObject var store: DriveStore
    let drive: Drive

    var body: some View {
        switch drive.state {
        case .readOnly, .unmounted:
            Button("Enable writing") { store.enableWriting(drive) }
            if drive.state == .readOnly { Button("Open in Finder") { store.openInFinder(drive) } }
        case .readWrite:
            Button("Open in Finder") { store.openInFinder(drive) }
            Button("Eject safely") { store.eject(drive) }
            Divider()
            Button("Remove hidden macOS files (._*)") { store.clean(drive) }
        }
    }
}

// MARK: - Pieces

extension Drive.State {
    var title: LocalizedStringKey {
        switch self {
        case .readWrite: "Read & write"
        case .readOnly: "Read-only"
        case .unmounted: "Not mounted"
        }
    }
    var color: Color {
        switch self {
        case .readWrite: .green
        case .readOnly: .orange
        case .unmounted: .secondary
        }
    }
}

struct StateBadge: View {
    let state: Drive.State
    var body: some View {
        Text(state.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(state.color.opacity(0.15), in: Capsule())
            .foregroundStyle(state.color)
    }
}

struct StateExplanation: View {
    let state: Drive.State
    var body: some View {
        Group {
            switch state {
            case .readOnly:
                Text("macOS can only read this drive. Press **Enable writing** to copy, edit and delete files on it.")
            case .unmounted:
                Text("This drive is connected but not open. Press **Enable writing** to use it.")
            case .readWrite:
                Text("You can use this drive like any other. Press **Eject safely** before unplugging it so every change is saved.")
            }
        }
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct CapacityBar: View {
    let available: Int64
    let total: Int64
    var body: some View {
        let f = ByteCountFormatter()
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: Double(total - available), total: Double(total))
            Text("\(f.string(fromByteCount: available)) available of \(f.string(fromByteCount: total))")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct ActionLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    let busy: Bool
    var body: some View {
        HStack(spacing: 6) {
            if busy { ProgressView().controlSize(.small) } else { Image(systemName: systemImage) }
            Text(title)
        }
        .frame(minWidth: 150)
    }
}

struct Banner: View {
    enum Style { case error, success }
    let text: String
    let style: Style
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: style == .error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(style == .error ? .orange : .green)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background((style == .error ? Color.orange : Color.green).opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Setup

struct SetupView: View {
    @EnvironmentObject var store: DriveStore
    let setup: Setup

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Set up ntfs4mac").font(.title.weight(.semibold))
                    Text("One-time setup to let your Mac write to NTFS drives. No restart, no security changes.")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Requirement(done: setup.brew, title: "Homebrew", detail: "Package manager used to install the pieces.") {
                    Button("Get Homebrew") { NSWorkspace.shared.open(URL(string: "https://brew.sh")!) }
                }
                Requirement(done: setup.clt, title: "Command Line Tools", detail: "Apple's free compiler tools.") {
                    Button("Install") { store.installCommandLineTools() }
                }
                Requirement(done: setup.fuset, title: "FUSE-T", detail: "Lets drivers run without a kernel extension.") { EmptyView() }
                Requirement(done: setup.ntfs3g, title: "ntfs-3g", detail: "The open-source NTFS driver, built for your Mac.") { EmptyView() }
            }
            .padding(14)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))

            if setup.macfuse {
                Banner(text: String(localized: "macFUSE is installed. ntfs4mac doesn't need it; you can remove it with: brew uninstall --cask macfuse"), style: .error)
            }

            HStack {
                Button {
                    store.install()
                } label: {
                    ActionLabel(title: "Install", systemImage: "arrow.down.circle", busy: store.installing)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!setup.brew || !setup.clt || store.installing)
                if !setup.brew || !setup.clt {
                    Text("Install Homebrew and the Command Line Tools first.").foregroundStyle(.secondary)
                } else if store.installing {
                    Text("This takes a few minutes. macOS will ask for your password.").foregroundStyle(.secondary)
                }
            }

            if let error = store.error { Banner(text: error, style: .error) }

            if !store.installLog.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(store.installLog.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .id("bottom")
                    }
                    .frame(minHeight: 120)
                    .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    .onChange(of: store.installLog.count) { _ in proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct Requirement<Action: View>: View {
    let done: Bool
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !done { action() }
        }
    }
}

// MARK: - Menu bar

struct MenuBarContent: View {
    @EnvironmentObject var store: DriveStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if store.drives.isEmpty {
            Text("No NTFS drives")
        }
        ForEach(store.drives) { drive in
            Menu {
                DriveMenu(drive: drive)
            } label: {
                Text("\(drive.name) — \(Text(drive.state.title))")
            }
        }
        Divider()
        Button("Open ntfs4mac…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
