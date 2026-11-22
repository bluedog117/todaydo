import SwiftUI
import AppKit
import TodaydoCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var tracker = AppModel.shared.tracker
    @ObservedObject var calendar = AppModel.shared.calendar
    @ObservedObject var backup = AppModel.shared.backup
    @State private var snapshots: [SnapshotInfo] = []
    @State private var tagsText = ""
    @State private var restoreTarget: SnapshotInfo?
    @AppStorage(UIScale.key) private var uiScale = 1.0

    var body: some View {
        Form {
            generalSection
            awaySection
            browserSection
            remindersSection
            calendarSection
            backupSection
            dataSection
        }
        .formStyle(.grouped)
        .onAppear {
            snapshots = model.backup.snapshots()
            tagsText = model.settings.awayTags.joined(separator: ", ")
            model.refreshDevices()
        }
        .confirmationDialog("Replace current data with \(restoreTarget?.url.lastPathComponent ?? "")?", isPresented: Binding(get: { restoreTarget != nil }, set: { if !$0 { restoreTarget = nil } })) {
            Button("Restore", role: .destructive) { if let t = restoreTarget { model.backup.restore(t) } }
        } message: { Text("The snapshot will replace the current database. This cannot be undone.") }
    }

    
    var generalSection: some View {
        Section("General") {
            HStack(spacing: 10) {
                Text("Interface scale")
                Image(systemName: "textformat.size.smaller").foregroundStyle(.secondary)
                Slider(value: $uiScale, in: UIScale.range, step: 0.05)
                Image(systemName: "textformat.size.larger").foregroundStyle(.secondary)
                Text("\(Int((uiScale * 100).rounded()))%").monospacedDigit().frame(width: 48, alignment: .trailing)
                Button("Reset") { uiScale = 1.0 }.disabled(abs(uiScale - 1) < 0.01)
            }
            Picker("Day starts at", selection: $model.settings.dayStartHour) {
                ForEach(0..<9) { Text(String(format: "%02d:00%@", $0, $0 == 4 ? " (Default)" : "")).tag($0) }
            }
            Stepper("Idle threshold: \(model.settings.idleMinutes) min without keyboard or mouse input (with no foreground media playing)", value: $model.settings.idleMinutes, in: 1...30)
            Toggle("Launch at login", isOn: $model.settings.launchAtLogin)
        }
    }

    var awaySection: some View {
        Section("Offline activity prompts") {
            Toggle("Ask about offline activity when I return", isOn: $model.settings.awayEnabled)
            if model.settings.awayEnabled {
                Stepper("Away for at least \(model.settings.awayMinMinutes) min before asking", value: $model.settings.awayMinMinutes, in: 3...120)
                Stepper("More than \(model.settings.awayMaxHours) hours is treated as sleep/end of work, do not ask", value: $model.settings.awayMaxHours, in: 1...12)
                TextField("Quick labels (comma-separated)", text: $tagsText)
                    .onSubmit { model.settings.awayTags = tagsText.split(whereSeparator: { ",, ".contains($0) }).map(String.init) }
            }
        }
    }

    var browserSection: some View {
        Section("Browser domains") {
            Toggle("Record the active browser tab's domain (domains only, not full URLs; Incognito windows are not recorded)", isOn: $model.settings.browserDomains)
            Text("Supports Safari, Chrome, Edge, Brave, and Arc. Firefox is tracked at app level. macOS requests Automation permission on first use.")
                .font(.caption).foregroundStyle(.secondary)
            if tracker.browserDenied {
                Label("Some browsers lack Automation permission. Only app activity is being tracked.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Button("Open System Settings → Automation") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                }
            }
        }
    }

    
    var remindersSection: some View {
        Group {
            Section("Reminders: General") {
                Stepper("Active hours: \(model.settings.reminderStartHour):00 – \(model.settings.reminderEndHour):00", value: $model.settings.reminderStartHour, in: 0...12)
                Stepper("Ends at \(model.settings.reminderEndHour):00", value: $model.settings.reminderEndHour, in: 13...24)
                Text("System notifications follow macOS Focus and Do Not Disturb. Actions include Snooze for 10 minutes and Mute for today.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Stand reminders") {
                Toggle("Remind me to stand after continuous use", isOn: $model.settings.stand.enabled)
                if model.settings.stand.enabled {
                    Stepper("Remind after \(model.settings.stand.intervalMin) minutes of continuous use", value: $model.settings.stand.intervalMin, in: 15...180, step: 5)
                    Stepper("Count \(model.settings.stand.restMin) minutes away as a break", value: $model.settings.stand.restMin, in: 1...30)
                }
            }
            Section("Pomodoro and focus reminders") {
                Stepper("Default focus duration: \(model.settings.focus.workMin) min", value: $model.settings.focus.workMin, in: 5...120, step: 5)
                Stepper("Short break duration: \(model.settings.focus.restMin) min", value: $model.settings.focus.restMin, in: 1...30)
                Stepper("Long break duration: \(model.settings.focus.longRestMin) min (Every \(model.settings.focus.longRestEvery) pomodoros)", value: $model.settings.focus.longRestMin, in: 5...60, step: 5)
                Stepper("Every \(model.settings.focus.longRestEvery) pomodoros before a long break", value: $model.settings.focus.longRestEvery, in: 2...10)
                HStack {
                    Picker("Pomodoro alert sound (System sounds)", selection: $model.settings.focus.soundName) {
                        ForEach(FocusRule.systemSounds, id: \.id) { s in
                            Text(s.label).tag(s.id)
                        }
                    }
                    Button("Preview") {
                        Notifier.playSystemSound(model.settings.focus.soundName)
                    }
                }
                Divider()
                Toggle("Automatically start a pomodoro in focus categories", isOn: $model.settings.focus.enabled)
                if model.settings.focus.enabled {
                    CategoryMultiPicker(title: "Trigger categories", selection: $model.settings.focus.categoryIds)
                    CategoryMultiPicker(title: "Distraction categories", selection: $model.settings.focus.distractIds)
                    Stepper("For \(model.settings.focus.triggerMin) min before auto-start", value: $model.settings.focus.triggerMin, in: 1...15)
                }
            }
            Section("Limit reminders") {
                ForEach($model.settings.limits) { $l in
                    HStack {
                        Picker("", selection: Binding(get: { l.kind == "category" ? l.key : "" }, set: { k in
                            if !k.isEmpty { l.kind = "category"; l.key = k; l.name = model.catName(Int64(k) ?? 5) }
                        })) {
                            Text("Custom").tag("")
                            ForEach(model.categories) { Text("Category · \($0.name)").tag("\($0.id)") }
                        }.labelsHidden().frame(width: 150)
                        if l.kind != "category" {
                            TextField("App Bundle ID / Domain", text: $l.key).onChange(of: l.key) { l.name = l.key }
                        }
                        Stepper("Daily \(l.minutes) min", value: $l.minutes, in: 10...720, step: 10)
                        Button(role: .destructive) { model.settings.limits.removeAll { $0.id == l.id } } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                    }
                }
                HStack {
                    Button("Add category limit") { model.settings.limits.append(LimitRule()) }
                    Button("Add website/App Limit") { model.settings.limits.append(LimitRule(kind: "domain", key: "bilibili.com", name: "bilibili.com", minutes: 60)) }
                }
            }
            Section("Goal reminders") {
                ForEach($model.settings.goals) { $g in
                    HStack {
                        Picker("", selection: $g.categoryId) { ForEach(model.categories) { Text($0.name).tag($0.id) } }.labelsHidden().frame(width: 90)
                            .onChange(of: g.categoryId) { g.name = model.catName(g.categoryId) }
                        Stepper("Goal \(g.minutes) min", value: $g.minutes, in: 10...720, step: 10)
                        Stepper("\(g.atHour):00 before", value: $g.atHour, in: 8...23)
                        Button(role: .destructive) { model.settings.goals.removeAll { $0.id == g.id } } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                    }
                }
                Button("Add goal") { model.settings.goals.append(GoalRule(categoryId: 2, name: model.catName(2))) }
            }
            Section("Time awareness (Keep track of passing time)") {
                Toggle("Periodic time and activity reminders", isOn: $model.settings.aware.enabled)
                Picker("Interval", selection: $model.settings.aware.everyMin) {
                    Text("15 min").tag(15); Text("30 min").tag(30); Text("60 min").tag(60)
                }.pickerStyle(.segmented)
                Toggle("Use a non-activating corner panel (otherwise use system notifications)", isOn: $model.settings.aware.floating)
                Picker("Remind during continuous use of one app", selection: $model.settings.aware.appEveryMin) {
                    Text("Off").tag(0); Text("20 min").tag(20); Text("30 min").tag(30); Text("45 min").tag(45); Text("60 min").tag(60)
                }
            }
            Section("Daily summary / Weekly review") {
                Toggle("Daily summary", isOn: $model.settings.summary.dailyEnabled)
                if model.settings.summary.dailyEnabled { Stepper("Notify at \(model.settings.summary.dailyHour):00", value: $model.settings.summary.dailyHour, in: 18...24) }
                Toggle("Send last week's review every Monday", isOn: $model.settings.summary.weeklyEnabled)
                if model.settings.summary.weeklyEnabled { Stepper("Notify at \(model.settings.summary.weeklyHour):00", value: $model.settings.summary.weeklyHour, in: 6...14) }
                Button("Preview daily summary") {
                    let (t, b) = SummaryBuilder.daily(model: model, dayStart: model.dc.dayStart(containing: Date()), now: Date())
                    Notifier.send(title: t, body: b)
                }
            }
        }
    }

    
    var calendarSection: some View {
        Section("System Calendar") {
            Toggle("Sync project activity to the todaydo calendar", isOn: $model.settings.calendarSync)
            Text(calendar.statusText).font(.caption).foregroundStyle(.secondary)
            Text("Create projects and assignment rules in Rules and projects. Same-project sessions less than 10 minutes apart are merged and saved 10 minutes after ending.").font(.caption).foregroundStyle(.secondary)
            if model.settings.calendarSync { Button("Sync now") { model.calendar.sync() } }
        }
    }

    
    var backupSection: some View {
        Section("Backup and restore") {
            Text("Records are stored locally in ~/Library/Application Support/todaydo/.").font(.caption).foregroundStyle(.secondary)
            ForEach(snapshots) { s in
                HStack {
                    Image(systemName: "externaldrive")
                    Text(s.url.lastPathComponent)
                    Text(s.date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore…") { restoreTarget = s }
                }
            }
            HStack {
                Button("Create snapshot now") { model.backup.dailySnapshot(); snapshots = model.backup.snapshots() }
                Button("Show in Finder") { NSWorkspace.shared.open(BackupService.supportDir) }
                Stepper("Keep \(model.settings.snapshotKeep) days", value: $model.settings.snapshotKeep, in: 3...60)
            }
            Divider()
            Toggle("Back up to iCloud Drive (multiple Mac share the folder to view other devices)", isOn: $model.settings.icloudBackup)
                .disabled(!BackupService.icloudAvailable)
            if !BackupService.icloudAvailable { Text("Not detected: iCloud Drive. ").font(.caption).foregroundStyle(.secondary) }
            if model.settings.icloudBackup {
                HStack {
                    Button("Back up now") { model.backup.icloudBackup() }
                    if let d = backup.lastICloudBackup { Text("Last: \(d.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if !model.devices.isEmpty {
                ForEach(model.devices) { d in
                    HStack {
                        Image(systemName: "laptopcomputer")
                        Text(d.name)
                        Text(d.lastBackup.map { "Backed up \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "").foregroundStyle(.secondary).font(.caption)
                        Spacer()
                        Button(model.viewDeviceId == d.id ? "Back to this Mac" : "View") { model.selectDevice(model.viewDeviceId == d.id ? nil : d.id) }
                    }
                }
            }
            if !backup.message.isEmpty { Text(backup.message).font(.caption).foregroundStyle(.secondary) }
        }
    }

    
    var dataSection: some View {
        Section("Data") {
            Button("Export all records as CSV…") { exportCSV() }
            Text("Full URLs, window titles, and keyboard input are never recorded. ").font(.caption).foregroundStyle(.secondary)
        }
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "todaydo-records.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let all = model.db.sessions(from: 0, to: Int64.max / 2)
        let f = ISO8601DateFormatter()
        func esc(_ s: String?) -> String { "\"" + (s ?? "").replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var out = "Start,End,Seconds,Source,App,Domain,Category,Project,Label\n"
        for s in all {
            out += [f.string(from: Date(timeIntervalSince1970: Double(s.startTs))), f.string(from: Date(timeIntervalSince1970: Double(s.endTs))),
                    "\(s.duration)", s.source, esc(s.appName), esc(s.domain), esc(model.catName(s.categoryId)),
                    esc(model.projectName(s.projectId)), esc(s.label)].joined(separator: ",") + "\n"
        }
        do { try out.write(to: url, atomically: true, encoding: .utf8); model.flash = "Exported \(all.count) records" }
        catch { model.flash = "Export failed: \(error.localizedDescription)" }
    }
}

struct CategoryMultiPicker: View {
    @EnvironmentObject var model: AppModel
    var title: String
    @Binding var selection: [Int64]

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            ForEach(model.categories) { c in
                Toggle(c.name, isOn: Binding(get: { selection.contains(c.id) }, set: { on in
                    if on { if !selection.contains(c.id) { selection.append(c.id) } } else { selection.removeAll { $0 == c.id } }
                })).toggleStyle(.button).tint(Color(hex: c.color))
            }
        }
    }
}
