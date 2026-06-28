import SwiftUI
import AppKit

struct AddVolumeView: View {
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var archivePath = ""
    @State private var manifestPath = ""
    @State private var volumeUUID: String? = nil
    @State private var deepCheckDays = 30

    private var canAdd: Bool {
        !displayName.isEmpty && !archivePath.isEmpty && !manifestPath.isEmpty
    }

    var body: some View {
        Form {
            Section("Archive Directory") {
                HStack {
                    TextField("Display name", text: $displayName)
                    Button("Browse…") { pickArchive() }
                }
                if !archivePath.isEmpty {
                    Text(archivePath)
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let uuid = volumeUUID {
                    Text("Volume UUID: \(uuid)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            Section("Manifest File") {
                HStack {
                    TextField("Path to .b3manifest", text: $manifestPath)
                    Button("Browse…") { pickManifest() }
                }
                Text("Create a baseline first with: sentinel baseline \"\(archivePath)\"")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Schedule") {
                Stepper(
                    "Deep check every \(deepCheckDays) day\(deepCheckDays == 1 ? "" : "s")",
                    value: $deepCheckDays, in: 1...365
                )
                Text("A quick file-count check runs on every mount.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 320)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    appState.addVolume(MonitoredVolume(
                        displayName: displayName,
                        archivePath: archivePath,
                        manifestPath: manifestPath,
                        volumeUUID: volumeUUID,
                        deepCheckIntervalDays: deepCheckDays
                    ))
                    dismiss()
                }
                .disabled(!canAdd)
            }
        }
    }

    private func pickArchive() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the archive directory to monitor"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        archivePath = url.path
        if displayName.isEmpty { displayName = url.lastPathComponent }
        if manifestPath.isEmpty {
            manifestPath = Self.defaultManifestPath(for: url.lastPathComponent)
        }
        volumeUUID = (try? url.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString
    }

    private static func defaultManifestPath(for archiveName: String) -> String {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Archive Integrity/manifests")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(archiveName + ".b3manifest").path
    }

    private func pickManifest() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose the .b3manifest file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        manifestPath = url.path
    }
}
