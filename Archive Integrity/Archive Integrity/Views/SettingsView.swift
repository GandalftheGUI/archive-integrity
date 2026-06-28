import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) var appState
    @State private var selection: UUID? = nil
    @State private var showingAddVolume = false

    private var selectedVolume: MonitoredVolume? {
        appState.volumes.first { $0.id == selection }
    }

    var body: some View {
        HSplitView {
            // Left: volume list
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(appState.volumes) { volume in
                        HStack(spacing: 8) {
                            statusIcon(for: volume)
                            Text(volume.displayName)
                                .lineLimit(1)
                        }
                        .tag(volume.id)
                        .padding(.vertical, 2)
                    }
                }

                Divider()

                HStack(spacing: 0) {
                    Button { showingAddVolume = true } label: {
                        Image(systemName: "plus").frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)

                    Divider().frame(height: 18)

                    Button {
                        if let id = selection {
                            appState.removeVolume(id: id)
                            selection = nil
                        }
                    } label: {
                        Image(systemName: "minus").frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(selection == nil)

                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            .frame(minWidth: 160, idealWidth: 180, maxWidth: 220)

            // Right: detail panel
            Group {
                if let volume = selectedVolume {
                    VolumeDetailView(volume: volume)
                } else {
                    Text("Select a volume")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 300)
        }
        .frame(minWidth: 520, minHeight: 300)
        .sheet(isPresented: $showingAddVolume) {
            AddVolumeView().environment(appState)
        }
    }

    @ViewBuilder
    private func statusIcon(for volume: MonitoredVolume) -> some View {
        switch volume.overallStatus {
        case .clean:   Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
        case .failed:  Image(systemName: "exclamationmark.shield.fill").foregroundStyle(.red)
        case .unknown: Image(systemName: "shield").foregroundStyle(.secondary)
        }
    }
}

struct VolumeDetailView: View {
    let volume: MonitoredVolume
    @Environment(AppState.self) var appState

    private var isChecking: Bool { appState.activeChecks[volume.id] != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Paths
                GroupBox("Paths") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                        row("Archive", volume.archivePath)
                        row("Manifest", volume.manifestPath)
                        if let uuid = volume.volumeUUID {
                            row("Volume UUID", uuid)
                        }
                    }
                    .padding(4)
                }

                // Check history
                GroupBox("Last Checks") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                        checkRow(label: "Quick", record: volume.lastQuickCheck)
                        checkRow(label: "Deep",  record: volume.lastDeepCheck)
                    }
                    .padding(4)
                }

                // Issues / info from last deep check
                if let issues = volume.lastDeepCheck?.issues, !issues.isEmpty {
                    let problems = issues.filter { !$0.hasPrefix("NEW:") }
                    let newTag   = issues.first(where: { $0.hasPrefix("NEW:") })

                    if let tag = newTag, let count = Int(tag.dropFirst(4)) {
                        Label("\(count) new file(s) added to manifest", systemImage: "plus.circle")
                            .font(.caption)
                            .foregroundStyle(.teal)
                    }

                    if !problems.isEmpty {
                        GroupBox("Issues") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(problems, id: \.self) { issue in
                                    Text(issue)
                                        .font(.caption)
                                        .foregroundStyle(issue.hasPrefix("CORRUPTED") ? .red : .orange)
                                }
                            }
                            .padding(4)
                        }
                    }
                }

                // Actions
                if let progress = appState.activeChecks[volume.id] {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(progress.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Cancel") { appState.cancelCheck(volumeID: volume.id) }
                            .font(.caption)
                    }
                } else {
                    HStack(spacing: 8) {
                        Button("Quick Check") { appState.runCheck(volumeID: volume.id, mode: .quick) }
                        Button("Deep Check")  { appState.runCheck(volumeID: volume.id, mode: .deep) }
                        Spacer()
                    }
                }

            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .gridColumnAlignment(.leading)
        }
    }

    @ViewBuilder
    private func checkRow(label: String, record: MonitoredVolume.CheckRecord?) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Group {
                if let r = record {
                    HStack(spacing: 6) {
                        outcomeLabel(r.outcome)
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(r.date.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text("\(r.fileCount) files")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Never").foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .gridColumnAlignment(.leading)
        }
    }

    @ViewBuilder
    private func outcomeLabel(_ outcome: MonitoredVolume.CheckRecord.Outcome) -> some View {
        switch outcome {
        case .clean:     Text("Clean").foregroundStyle(.green)
        case .failed:    Text("Failed").foregroundStyle(.red)
        case .uncovered: Text("New files").foregroundStyle(.orange)
        }
    }
}
