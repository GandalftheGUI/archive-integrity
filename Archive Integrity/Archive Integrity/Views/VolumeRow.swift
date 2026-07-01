import SwiftUI

struct VolumeRow: View {
    let volume: MonitoredVolume
    @Environment(AppState.self) var appState
    @Environment(\.openWindow) private var openWindow
    @State private var isHovering = false

    private var progress: AppState.CheckProgress? { appState.activeChecks[volume.id] }
    private var isChecking: Bool { progress != nil }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                appState.pendingSettingsSelection = volume.id
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                HStack(spacing: 10) {
                    VolumeStatusIcon(status: volume.overallStatus, size: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(volume.displayName)
                            .fontWeight(.medium)

                        if let p = progress {
                            Text(p.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            statusLine
                        }
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(isHovering ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .onHover { isHovering = $0 }

            if isChecking {
                Button("Cancel") { appState.cancelCheck(volumeID: volume.id) }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            } else {
                Menu {
                    Button("Quick Check") { appState.runCheck(volumeID: volume.id, mode: .quick) }
                    Button("Deep Check")  { appState.runCheck(volumeID: volume.id, mode: .deep) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let deep = volume.lastDeepCheck {
            switch deep.outcome {
            case .clean:
                caption("Clean · \(deep.date.formatted(.relative(presentation: .named)))")
            case .failed:
                caption("\(deep.issues.count) issue(s) · \(deep.date.formatted(.relative(presentation: .named)))",
                        color: .red)
            case .uncovered:
                caption("New files · \(deep.date.formatted(.relative(presentation: .named)))",
                        color: .orange)
            }
        } else if let quick = volume.lastQuickCheck {
            caption("Quick \(quick.outcome == .clean ? "OK" : "failed") · \(quick.date.formatted(.relative(presentation: .named)))")
        } else {
            caption("Never checked")
        }
    }

    private func caption(_ text: String, color: Color = .secondary) -> some View {
        Text(text).font(.caption).foregroundStyle(color)
    }
}
