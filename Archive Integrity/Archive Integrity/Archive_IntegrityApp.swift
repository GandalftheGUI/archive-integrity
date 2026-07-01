import SwiftUI

@main
struct Archive_IntegrityApp: App {
    @State private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
                .onAppear { appState.start() }
        } label: {
            Image(systemName: appState.menuBarIcon)
                .onAppear {
                    NotificationDelegate.shared.onTapVolume = { volumeID in
                        appState.pendingSettingsSelection = volumeID
                        openWindow(id: "settings")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView()
                .environment(appState)
        }
        .windowResizability(.contentSize)
    }
}
