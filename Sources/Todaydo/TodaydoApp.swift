import SwiftUI
import TodaydoCore

@main
struct TodaydoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel.shared

    init() {
        UserDefaults.standard.register(defaults: ["AppleLanguages": ["en"], "AppleLocale": "en_US"])
    }

    var body: some Scene {
        MenuBarExtra {
            MenuPanel()
                .environmentObject(model)
                .environment(\.locale, Locale(identifier: "en_US"))
        } label: {
            MenuLabel()
                .environmentObject(model)
                .environment(\.locale, Locale(identifier: "en_US"))
        }
        .menuBarExtraStyle(.window)

        Window("todaydo", id: "main") {
            MainWindow()
                .environmentObject(model)
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1120, height: 780)
    }
}

struct MenuLabel: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var tracker = AppModel.shared.tracker
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: tracker.status == .manualPaused ? "pause.circle" : "sun.haze.fill")
            if !model.menuTitle.isEmpty { Text(model.menuTitle) }
        }
        .onAppear { model.openWindowAction = { openWindow(id: "main") } }
    }
}



struct MenuPanel: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var tracker = AppModel.shared.tracker
    @ObservedObject var reminders = AppModel.shared.reminders
    @Environment(\.openWindow) private var openWindow
    @State private var sessions: [Session] = []

    var body: some View {
        let total = Stats.total(sessions)
        let top = Stats.rank(sessions).prefix(3)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today").font(.caption).foregroundStyle(.secondary)
                    Text(Stats.formatDuration(total)).font(.system(size: 26, weight: .semibold, design: .rounded))
                }
                Spacer()
                statusBadge
            }

            if !top.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(top)) { RankRow(item: $0, maxSeconds: top.first?.seconds ?? 1) }
                }
            } else {
                Text("No activity recorded today").font(.callout).foregroundStyle(.secondary)
            }

            Divider()

            if let p = reminders.pomodoro {
                let _ = reminders.pomodoroTick
                let rem = Int(p.remainingSeconds().rounded())
                let phaseTitle = p.phase == .work ? "🍅 Focusing" : (p.phase == .longRest ? "☕️ Long break" : "☕️ On break")
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(phaseTitle + (p.isPaused ? " (Paused)" : ""))
                            .font(.subheadline.weight(.medium))
                        if !p.task.isEmpty {
                            Text("· \(p.task)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(String(format: "%02d:%02d", rem / 60, rem % 60))
                            .font(.headline.monospacedDigit())
                    }
                    HStack(spacing: 6) {
                        Button(p.isPaused ? "Resume" : "Pause") { reminders.togglePausePomodoro() }
                        Button("+5m") { reminders.addPomodoroMinutes(5) }
                        Button(p.phase == .work ? "Take a break" : "Skip") { reminders.skipPomodoroPhase() }
                        Spacer()
                        Button("End") { reminders.stopPomodoro() }
                    }
                    .controlSize(.small)
                }
            } else {
                HStack {
                    Button { reminders.startPomodoro() } label: {
                        Label("Start pomodoro (\(model.settings.focus.workMin)m)", systemImage: "timer")
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Menu {
                        ForEach([15, 25, 45, 60], id: \.self) { m in
                            Button("Focus \(m) min") { reminders.startPomodoro(minutes: m) }
                        }
                        Divider()
                        Button("Short break (\(model.settings.focus.restMin) min)") { reminders.startBreak(long: false) }
                        Button("Long break (\(model.settings.focus.longRestMin) min)") { reminders.startBreak(long: true) }
                    } label: {
                        Text("More ▾").font(.caption).foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                if reminders.todayPomodoros > 0 {
                    Text("Completed today: \(reminders.todayPomodoros) pomodoros 🍅")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if tracker.isPaused {
                Button { tracker.resume() } label: { Label("Resume tracking", systemImage: "play.circle") }.buttonStyle(.plain)
            } else {
                Menu {
                    Button("Pause 15 min") { tracker.pause(minutes: 15) }
                    Button("Pause 1 hours") { tracker.pause(minutes: 60) }
                    Button("Pause until tomorrow") { tracker.pauseUntilTomorrow() }
                    Button("Pause, Resume manually") { tracker.pause(minutes: nil) }
                } label: { Label("Pause tracking", systemImage: "pause.circle") }
                .menuStyle(.borderlessButton)
            }

            Divider()
            HStack {
                Button {
                    model.openWindowAction = { openWindow(id: "main") }
                    model.openMain()
                } label: { Label("Open todaydo", systemImage: "chart.bar.xaxis") }
                .buttonStyle(.plain)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 330)
        .onAppear(perform: load)
        .onChange(of: model.dataVersion) { load() }
    }

    @ViewBuilder var statusBadge: some View {
        switch tracker.status {
        case .recording:
            Label(tracker.currentName, systemImage: "record.circle").font(.caption).foregroundStyle(.green).lineLimit(1)
        case .idle: Label("Idle", systemImage: "moon.zzz").font(.caption).foregroundStyle(.secondary)
        case .systemPaused: Label("Screen locked/Sleep", systemImage: "lock").font(.caption).foregroundStyle(.secondary)
        case .manualPaused:
            Label(tracker.pausedUntil.map { "Pause until \(clockString($0.ts))" } ?? "Paused", systemImage: "pause.circle")
                .font(.caption).foregroundStyle(.orange)
        case .excluded: Label("Excluded", systemImage: "eye.slash").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func load() {
        let r = model.dc.dayRange(containing: Date())
        sessions = Stats.clipped(model.db.sessions(from: r.start.ts, to: r.end.ts), from: r.start.ts, to: r.end.ts)
    }
}



struct MainWindow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage(UIScale.key) private var uiScale = 1.0

    var body: some View {
        NavigationSplitView {
            UIScaled(scale: uiScale) {
                List(AppModel.Page.allCases, selection: Binding(get: { model.page }, set: { model.page = $0 ?? .today })) { p in
                    Label(p.rawValue, systemImage: p.icon).tag(p)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220 * uiScale, max: 300)
        } detail: {
            UIScaled(scale: uiScale) {
                VStack(spacing: 0) {
                    banners
                    Group {
                        switch model.page {
                        case .today: TodayView()
                        case .week: WeekView()
                        case .month: MonthView()
                        case .trend: TrendView()
                        case .focus: FocusView()
                        case .manage: ManageView()
                        case .settings: SettingsView()
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    if !model.devices.isEmpty {
                        Picker("Device", selection: Binding(get: { model.viewDeviceId ?? "" }, set: { model.selectDevice($0.isEmpty ? nil : $0) })) {
                            Text("This Mac").tag("")
                            ForEach(model.devices) { Text($0.name + ($0.ready ? "" : " (Downloading)")).tag($0.id) }
                        }
                        .frame(width: 160)
                    }
                }
            }
        }
        .onAppear { model.openWindowAction = { openWindow(id: "main") } }
    }

    @ViewBuilder var banners: some View {
        if model.integrityIssue {
            banner("Database integrity check failed. Restore a recent snapshot in Settings → Backup and restore.", color: .red)
        }
        if model.viewingRemote {
            banner("Viewing another Mac backup (read-only).", color: .blue)
        }
        if model.tracker.isPaused {
            banner("Tracking paused. ", color: .orange)
        }
        if let f = model.flash {
            banner(f, color: .gray).onTapGesture { model.flash = nil }
        }
    }

    func banner(_ text: String, color: Color) -> some View {
        Text(text).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(color.opacity(0.15))
    }
}
