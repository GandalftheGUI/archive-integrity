import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appState.volumes.isEmpty {
                Text("No volumes monitored")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                ForEach(appState.volumes) { volume in
                    VolumeRow(volume: volume)
                }
                Divider().padding(.vertical, 4)
            }

            Button("Settings…") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)
            .padding(.horizontal, 4)

            Divider().padding(.vertical, 4)

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .frame(minWidth: 300)
    }
}
