import SwiftUI
import AppKit
import Engine

struct AddVolumeView: View {
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var archivePath = ""
    @State private var manifestPath = ""
    @State private var volumeUUID: String? = nil
    @State private var deepCheckDays = MonitoredVolume.defaultDeepCheckIntervalDays
    @State private var scheduledHour = MonitoredVolume.defaultScheduledHour
    @State private var driveType: DriveType = .ssd
    @State private var showManifestInfo = false
    @State private var showAdvanced = false

    enum DriveType: String, CaseIterable, Identifiable {
        case ssd = "SSD"
        case hdd = "HDD"
        var id: String { rawValue }
        var concurrency: Int { self == .ssd ? 4 : 1 }
    }

    private var canAdd: Bool {
        !displayName.isEmpty && !archivePath.isEmpty && !manifestPath.isEmpty
    }

    private var manifestFileExists: Bool {
        !manifestPath.isEmpty && FileManager.default.fileExists(atPath: manifestPath)
    }

    private var existingManifestCount: Int? {
        guard manifestFileExists else { return nil }
        return try? Manifest(url: URL(fileURLWithPath: manifestPath)).count
    }

    /// True while the manifest path still matches the auto-generated default for the chosen archive —
    /// used to signal that this field is a sensible default the user doesn't need to touch.
    private var isDefaultManifestPath: Bool {
        guard !archivePath.isEmpty else { return false }
        let archiveName = URL(fileURLWithPath: archivePath).lastPathComponent
        return manifestPath == Self.defaultManifestURL(for: archiveName).path
    }

    var body: some View {
        Form {
            Section("Archive") {
                TextField("Display Name", text: $displayName)

                LabeledContent("Directory") {
                    HStack(spacing: 8) {
                        Text(archivePath.isEmpty ? "Not selected" : archivePath)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(archivePath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Browse…") { pickArchive() }
                    }
                }

                if let uuid = volumeUUID {
                    Text("Volume UUID: \(uuid)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            Section {
                Button {
                    withAnimation { showAdvanced.toggle() }
                } label: {
                    HStack {
                        Text(showAdvanced ? "Hide Advanced Settings" : "Show Advanced Settings")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(showAdvanced ? 90 : 0))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if showAdvanced {
                Section {
                    HStack {
                        TextField("Path to .b3manifest", text: $manifestPath)
                            .foregroundStyle(isDefaultManifestPath ? .secondary : .primary)
                        Button("Browse…") { pickManifest() }
                    }

                    if !manifestPath.isEmpty {
                        manifestStatusLabel
                            .font(.caption)
                    }
                } header: {
                    HStack(spacing: 4) {
                        Text("Manifest File")
                        Button {
                            showManifestInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .popover(isPresented: $showManifestInfo, arrowEdge: .trailing) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("What's a manifest?")
                                    .font(.callout)
                                    .fontWeight(.medium)
                                Text("A manifest records a BLAKE3 hash of every file in your archive. Archive Integrity compares your files against it to catch silent corruption (bit rot) and deleted files. If none exists yet at this path, running a Deep Check after adding creates one automatically.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(14)
                            .frame(width: 260)
                        }
                    }
                }

                Section("Deep Check Settings") {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Drive Type", selection: $driveType) {
                            ForEach(DriveType.allCases) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(driveType == .ssd
                             ? "Parallel hashing — best for SSDs."
                             : "Sequential hashing — safest for spinning HDDs.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Stepper(
                            "Deep check every \(deepCheckDays) day\(deepCheckDays == 1 ? "" : "s")",
                            value: $deepCheckDays, in: 1...365
                        )

                        HStack(spacing: 8) {
                            Text("Scheduled for")
                            Picker("", selection: $scheduledHour) {
                                ForEach(0..<24, id: \.self) { hour in
                                    Text(hourLabel(hour)).tag(hour)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }

                        Text("A quick file-count check runs on every mount, or once daily at the scheduled hour if the archive stays mounted.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460)
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
                        deepCheckIntervalDays: deepCheckDays,
                        concurrency: driveType.concurrency,
                        scheduledHour: scheduledHour
                    ))
                    dismiss()
                }
                .disabled(!canAdd)
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let period = hour < 12 ? "AM" : "PM"
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        return "\(displayHour):00 \(period)"
    }

    @ViewBuilder
    private var manifestStatusLabel: some View {
        switch (isDefaultManifestPath, manifestFileExists) {
        case (true, true):
            Label(
                "Default location — existing manifest found" + (existingManifestCount.map { " (\($0) files)" } ?? "") + ".",
                systemImage: "checkmark.circle"
            )
            .foregroundStyle(.green)
        case (true, false):
            Label(
                "Default location — you usually don't need to change this. Run a Deep Check after adding to create it.",
                systemImage: "checkmark.circle"
            )
            .foregroundStyle(.secondary)
        case (false, true):
            Label(
                "Existing manifest found" + (existingManifestCount.map { " — \($0) files" } ?? ""),
                systemImage: "checkmark.circle"
            )
            .foregroundStyle(.green)
        case (false, false):
            Label(
                "No manifest here yet — after adding, run a Deep Check to hash every file and create it.",
                systemImage: "info.circle"
            )
            .foregroundStyle(.secondary)
        }
    }

    private func pickArchive() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the archive directory to monitor"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Only follow the default if the user hasn't pointed the manifest somewhere custom.
        let shouldUpdateManifest = manifestPath.isEmpty || isDefaultManifestPath

        archivePath = url.path
        if displayName.isEmpty { displayName = url.lastPathComponent }
        if shouldUpdateManifest {
            let manifestURL = Self.defaultManifestURL(for: url.lastPathComponent)
            try? FileManager.default.createDirectory(
                at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            manifestPath = manifestURL.path
        }
        volumeUUID = (try? url.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString
    }

    private static func defaultManifestURL(for archiveName: String) -> URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Archive Integrity/manifests")
        return dir.appendingPathComponent(archiveName + ".b3manifest")
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
