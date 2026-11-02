import SwiftUI

@main
struct NTFS4MacApp: App {
    @StateObject private var store = DriveStore()

    var body: some Scene {
        Window("ntfs4mac", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 560, idealWidth: 1000, minHeight: 400, idealHeight: 640)
        }
        .defaultSize(width: 1000, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        // Quick access from the menu bar, even with the window closed.
        MenuBarExtra {
            MenuBarContent().environmentObject(store)
        } label: {
            Image(systemName: "externaldrive.fill")
        }
    }
}
