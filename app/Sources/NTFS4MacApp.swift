import SwiftUI

@main
struct NTFS4MacApp: App {
    @StateObject private var store = DriveStore()

    var body: some Scene {
        Window("ntfs4mac", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 720, minHeight: 460)
        }
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
