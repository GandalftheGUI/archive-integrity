import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appState.volumes.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "externaldrive.badge.questionmark")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                    Text("No archives monitored")
                        .foregroundStyle(.secondary)
                    Text("Add one from Settings…")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
            } else {
                VStack(spacing: 0) {
                    ForEach(appState.volumes) { volume in
                        VolumeRow(volume: volume)
                    }
                }
                .padding(.vertical, 4)

                Divider().padding(.vertical, 2)
            }

            MenuToggleRow(
                title: "Launch at Login",
                icon: "play.circle",
                isOn: Binding(
                    get: { appState.launchAtLoginEnabled },
                    set: { appState.launchAtLoginEnabled = $0 }
                )
            )

            Divider().padding(.vertical, 2)

            MenuActionRow(title: "Settings…", icon: "gearshape") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }

            Divider().padding(.vertical, 2)

            MenuActionRow(title: "Quit", icon: "power") {
                NSApp.terminate(nil)
            }
            .padding(.bottom, 4)
        }
        .padding(.vertical, 4)
        .frame(minWidth: 220, idealWidth: 240)
    }
}

private struct MenuToggleRow: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool

    @State private var isHovering = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(title)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .onHover { isHovering = $0 }
        .padding(.horizontal, 6)
    }
}

private struct MenuActionRow: View {
    let title: String
    let icon: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .onHover { isHovering = $0 }
        .padding(.horizontal, 6)
    }
}
