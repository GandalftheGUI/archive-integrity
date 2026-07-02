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
                        SidebarVolumeRow(volume: volume)
                            .tag(volume.id)
                            .padding(.vertical, 3)
                    }
                }
                .listStyle(.sidebar)

                Divider()

                HStack(spacing: 0) {
                    Button { showingAddVolume = true } label: {
                        Image(systemName: "plus")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Divider().frame(height: 14)

                    Button {
                        if let id = selection {
                            appState.removeVolume(id: id)
                            selection = nil
                        }
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(selection == nil)

                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .frame(minWidth: 190, idealWidth: 220, maxWidth: 260)

            // Right: detail panel
            Group {
                if let volume = selectedVolume {
                    VolumeDetailView(volume: volume)
                } else {
                    ContentUnavailableView(
                        "No Archive Selected",
                        systemImage: "externaldrive.badge.questionmark",
                        description: Text("Choose an archive on the left, or add a new one to start monitoring it.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 400)
        }
        .frame(minWidth: 660, minHeight: 420)
        .sheet(isPresented: $showingAddVolume) {
            AddVolumeView().environment(appState)
        }
        .onAppear { adoptPendingSelection() }
        .onChange(of: appState.pendingSettingsSelection) { _, _ in adoptPendingSelection() }
    }

    private func adoptPendingSelection() {
        guard let pending = appState.pendingSettingsSelection else { return }
        selection = pending
        appState.pendingSettingsSelection = nil
    }
}

// MARK: - Sidebar row

private struct SidebarVolumeRow: View {
    let volume: MonitoredVolume

    var body: some View {
        HStack(spacing: 10) {
            VolumeStatusIcon(status: volume.overallStatus)

            VStack(alignment: .leading, spacing: 1) {
                Text(volume.displayName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                subtitle
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if let deep = volume.lastDeepCheck {
            Text("\(deep.date.formatted(.relative(presentation: .named)))")
        } else if volume.lastQuickCheck != nil {
            Text("Quick check only")
        } else {
            Text("Never checked")
        }
    }
}

// MARK: - Detail panel

struct VolumeDetailView: View {
    let volume: MonitoredVolume
    @Environment(AppState.self) var appState
    @State private var isEditingName = false
    @State private var editedName = ""
    @FocusState private var nameFieldFocused: Bool

    private var isChecking: Bool { appState.activeChecks[volume.id] != nil }

    private func renameVolume(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = appState.volumes.firstIndex(where: { $0.id == volume.id }) else { return }
        appState.volumes[idx].displayName = trimmed
        appState.save()
    }

    private var concurrencyBinding: Binding<Int> {
        Binding(
            get: { appState.volumes.first(where: { $0.id == volume.id })?.concurrency ?? 1 },
            set: { newValue in
                if let idx = appState.volumes.firstIndex(where: { $0.id == volume.id }) {
                    appState.volumes[idx].concurrency = newValue
                    appState.save()
                }
            }
        )
    }

    private var deepCheckIntervalBinding: Binding<Int> {
        Binding(
            get: { appState.volumes.first(where: { $0.id == volume.id })?.deepCheckIntervalDays ?? 30 },
            set: { newValue in
                if let idx = appState.volumes.firstIndex(where: { $0.id == volume.id }) {
                    appState.volumes[idx].deepCheckIntervalDays = newValue
                    appState.save()
                }
            }
        )
    }

    private var nextDeepCheckText: String {
        guard let last = volume.lastDeepCheck else { return "Runs after the first deep check completes" }
        let next = last.date.addingTimeInterval(Double(volume.deepCheckIntervalDays) * 86_400)
        return next <= Date()
            ? "Due on next mount"
            : "Next due \(next.formatted(date: .abbreviated, time: .omitted))"
    }

    private var scheduledHourBinding: Binding<Int> {
        Binding(
            get: { appState.volumes.first(where: { $0.id == volume.id })?.effectiveScheduledHour ?? MonitoredVolume.defaultScheduledHour },
            set: { newValue in
                if let idx = appState.volumes.firstIndex(where: { $0.id == volume.id }) {
                    appState.volumes[idx].scheduledHour = newValue
                    appState.save()
                }
            }
        )
    }

    private func hourLabel(_ hour: Int) -> String {
        let period = hour < 12 ? "AM" : "PM"
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        return "\(displayHour):00 \(period)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                header

                SectionCard(title: "Paths", icon: "folder") {
                    VStack(alignment: .leading, spacing: 10) {
                        pathRow("Archive", volume.archivePath, icon: "externaldrive")
                        pathRow("Manifest", volume.manifestPath, icon: "doc.text")
                        if let uuid = volume.volumeUUID {
                            pathRow("Volume UUID", uuid, icon: "number")
                        }
                    }
                }

                SectionCard(title: "Deep Check Settings", icon: "slider.horizontal.3") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Stepper(value: concurrencyBinding, in: 1...64) {
                                Text("\(volume.concurrency) file\(volume.concurrency == 1 ? "" : "s") at a time")
                                    .fontWeight(.medium)
                            }
                            .fixedSize()

                            Text(volume.concurrency == 1 ? "Sequential — safe for HDDs" : "Parallel — best for SSDs")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()
                        }

                        Divider()

                        HStack(spacing: 12) {
                            Stepper(value: deepCheckIntervalBinding, in: 1...365) {
                                Text("Deep check every \(volume.deepCheckIntervalDays) day\(volume.deepCheckIntervalDays == 1 ? "" : "s")")
                                    .fontWeight(.medium)
                            }
                            .fixedSize()

                            Text(nextDeepCheckText)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()
                        }

                        HStack(spacing: 12) {
                            Text("Scheduled for")
                                .fontWeight(.medium)

                            Picker("", selection: scheduledHourBinding) {
                                ForEach(0..<24, id: \.self) { hour in
                                    Text(hourLabel(hour)).tag(hour)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()

                            Spacer()
                        }

                        Text("Runs automatically when the archive is mounted, if the interval has passed, and once daily at the scheduled hour if it stays mounted. A quick check always runs on mount.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                SectionCard(title: "Last Checks", icon: "clock.arrow.circlepath") {
                    HStack(spacing: 12) {
                        CheckStatTile(label: "Quick", record: volume.lastQuickCheck)
                        CheckStatTile(label: "Deep", record: volume.lastDeepCheck)
                    }
                }

                if let issues = volume.lastQuickCheck?.issues, !issues.isEmpty {
                    SectionCard(title: "Quick Check Issues", icon: "exclamationmark.triangle", tint: .orange) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(issues, id: \.self) { issue in
                                issueRow(issue: issue, volumeID: volume.id)
                            }
                        }
                    }
                }

                if let issues = volume.lastDeepCheck?.issues, !issues.isEmpty {
                    let problems = issues.filter { !$0.hasPrefix("NEW:") }
                    let newTag   = issues.first(where: { $0.hasPrefix("NEW:") })

                    if let tag = newTag, let count = Int(tag.dropFirst(4)) {
                        Label("\(count) new file(s) added to manifest", systemImage: "plus.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.teal)
                    }

                    if !problems.isEmpty {
                        SectionCard(title: "Issues", icon: "exclamationmark.triangle", tint: .red) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(problems, id: \.self) { issue in
                                    issueRow(issue: issue, volumeID: volume.id)
                                }
                            }
                        }
                    }
                }

                actions
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(statusTint.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(statusTint)
            }

            VStack(alignment: .leading, spacing: 3) {
                if isEditingName {
                    TextField("Name", text: $editedName)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .textFieldStyle(.plain)
                        .focused($nameFieldFocused)
                        .onSubmit {
                            renameVolume(to: editedName)
                            isEditingName = false
                        }
                } else {
                    HStack(spacing: 6) {
                        Text(volume.displayName)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Button {
                            editedName = volume.displayName
                            isEditingName = true
                            nameFieldFocused = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                StatusBadge(status: volume.overallStatus)
            }

            Spacer()
        }
        .onChange(of: nameFieldFocused) { _, focused in
            guard isEditingName, !focused else { return }
            renameVolume(to: editedName)
            isEditingName = false
        }
    }

    private var statusTint: Color {
        switch volume.overallStatus {
        case .clean:   return .green
        case .failed:  return .red
        case .unknown: return .secondary
        }
    }

    private var actions: some View {
        Group {
            if let progress = appState.activeChecks[volume.id] {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(progress.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Cancel", role: .cancel) { appState.cancelCheck(volumeID: volume.id) }
                        .font(.caption)
                }
                .padding(12)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            } else {
                HStack(spacing: 10) {
                    Button {
                        appState.runCheck(volumeID: volume.id, mode: .quick)
                    } label: {
                        Label("Quick Check", systemImage: "bolt.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        appState.runCheck(volumeID: volume.id, mode: .deep)
                    } label: {
                        Label("Deep Check", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private func issueRow(issue: String, volumeID: UUID) -> some View {
        let isModified = issue.hasPrefix("MODIFIED")
        let isMissing  = issue.hasPrefix("MISSING")
        let path: String? = {
            if isModified, let r = issue.range(of: "MODIFIED: ") { return String(issue[r.upperBound...]) }
            if isMissing,  let r = issue.range(of: "MISSING: ")  { return String(issue[r.upperBound...]) }
            return nil
        }()
        let type: IssueFixButton.IssueType? = isModified ? .modified : isMissing ? .missing : nil

        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isModified ? "pencil.circle.fill" : "questionmark.circle.fill")
                .font(.caption)
                .foregroundStyle(isModified ? .red : .orange)

            Text(issue)
                .font(.caption)
                .foregroundStyle(isModified ? .red : .orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            if let path, let type {
                IssueFixButton(type: type, path: path, volumeID: volumeID)
            }
        }
    }

    private func pathRow(_ label: String, _ value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }
}

// MARK: - Reusable pieces

private struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    var tint: Color = .secondary
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(tint == .secondary ? .primary : tint)

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary.opacity(0.6), lineWidth: 1)
        )
    }
}

private struct StatusBadge: View {
    let status: MonitoredVolume.Status

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
    }

    private var text: String {
        switch status {
        case .clean:   return "Clean"
        case .failed:  return "Issues Found"
        case .unknown: return "Not Checked"
        }
    }

    private var symbol: String {
        switch status {
        case .clean:   return "checkmark.circle.fill"
        case .failed:  return "exclamationmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    private var tint: Color {
        switch status {
        case .clean:   return .green
        case .failed:  return .red
        case .unknown: return .secondary
        }
    }
}

private struct CheckStatTile: View {
    let label: String
    let record: MonitoredVolume.CheckRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let r = record {
                Label(outcomeText(r.outcome), systemImage: outcomeIcon(r.outcome))
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(outcomeColor(r.outcome))

                Text(statLine(for: r))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Label("Never", systemImage: "minus.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(" ")
                    .font(.caption2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func statLine(for record: MonitoredVolume.CheckRecord) -> String {
        var parts = ["\(record.date.formatted(date: .abbreviated, time: .shortened))", "\(record.fileCount) files"]
        if let durationText = durationText(record.duration) {
            parts.append(durationText)
        }
        return parts.joined(separator: " · ")
    }

    private func durationText(_ duration: TimeInterval?) -> String? {
        guard let duration, duration > 0 else { return nil }
        if duration < 60 {
            return String(format: "%.1fs", duration)
        }
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes < 60 {
            return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes)m"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes > 0 ? "\(hours)h \(remainingMinutes)m" : "\(hours)h"
    }

    private func outcomeText(_ outcome: MonitoredVolume.CheckRecord.Outcome) -> String {
        switch outcome {
        case .clean:     return "Clean"
        case .failed:    return "Failed"
        case .uncovered: return "New files"
        }
    }

    private func outcomeIcon(_ outcome: MonitoredVolume.CheckRecord.Outcome) -> String {
        switch outcome {
        case .clean:     return "checkmark.circle.fill"
        case .failed:    return "xmark.circle.fill"
        case .uncovered: return "plus.circle.fill"
        }
    }

    private func outcomeColor(_ outcome: MonitoredVolume.CheckRecord.Outcome) -> Color {
        switch outcome {
        case .clean:     return .green
        case .failed:    return .red
        case .uncovered: return .orange
        }
    }
}

// MARK: - Fix popover

private struct IssueFixButton: View {
    enum IssueType {
        case modified, missing

        var headline: String {
            switch self {
            case .modified: return "This file's content has changed since it was last verified."
            case .missing:  return "This file is no longer on disk."
            }
        }

        var intentionalLabel: String {
            switch self {
            case .modified: return "If the change was intentional"
            case .missing:  return "If it was intentionally deleted"
            }
        }

        var unintentionalAdvice: String {
            switch self {
            case .modified: return "If the change was not intentional, restore the original from a backup, then run a deep check to verify it."
            case .missing:  return "If it was accidentally deleted, restore the file from a backup, then run a deep check to verify it."
            }
        }
    }

    let type: IssueType
    let path: String
    let volumeID: UUID
    @Environment(AppState.self) var appState
    @State private var showPopover = false
    @State private var showRebuildWarning = false

    var body: some View {
        Button {
            showPopover = true
        } label: {
            Label("Fix…", systemImage: "wrench.and.screwdriver")
        }
        .font(.caption)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .popover(isPresented: $showPopover, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(type.headline)
                        .font(.callout)
                        .fontWeight(.medium)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text(type.intentionalLabel + ":")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Rebuild manifest…") {
                            showPopover = false
                            showRebuildWarning = true
                        }
                        .foregroundStyle(.red)
                    }

                    Divider()

                    Text(type.unintentionalAdvice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(width: 280)
            }
            .alert("Rebuild manifest?", isPresented: $showRebuildWarning) {
                Button("Rebuild", role: .destructive) {
                    appState.rebuildManifest(volumeID: volumeID)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes the current manifest and re-baselines from the current state of your files — including any that may be modified or corrupted. Only do this if you are certain your archive is intact.\n\nRun a deep check after rebuilding to create the new baseline.")
            }
    }
}
