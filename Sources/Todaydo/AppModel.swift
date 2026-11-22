import SwiftUI
import AppKit
import ServiceManagement
import UserNotifications
import TodaydoCore

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let db: Database
    let classifier: Classifier

    @Published var settings: Settings {
        didSet { if settings != oldValue { settingsChanged(oldValue) } }
    }
    @Published var dataVersion = 0
    @Published var categories: [TodaydoCore.Category] = []
    @Published var projects: [Project] = []
    @Published var devices: [DeviceInfo] = []
    @Published var viewDeviceId: String? = nil
    @Published var integrityIssue = false
    @Published var menuTitle = ""
    @Published var flash: String?
    @Published var page: Page = .today
    @Published var todayDate = Date()

    enum Page: String, CaseIterable, Identifiable {
        case today = "Today", week = "This week", month = "Month", trend = "Trends", focus = "Focus", manage = "Rules and projects", settings = "Settings"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .today: return "sun.max"
            case .week: return "calendar"
            case .month: return "calendar.badge.clock"
            case .trend: return "chart.line.uptrend.xyaxis"
            case .focus: return "scope"
            case .manage: return "slider.horizontal.3"
            case .settings: return "gearshape"
            }
        }
    }

    func jumpToDay(_ d: Date) {
        todayDate = d
        page = .today
    }

    private(set) var remoteDB: Database?
    var openWindowAction: (() -> Void)?

    lazy var tracker = Tracker(model: self)
    lazy var reminders = ReminderEngine(model: self)
    lazy var calendar = CalendarSync(model: self)
    lazy var backup = BackupService(model: self)

    var dc: DayCalendar { DayCalendar(dayStartHour: settings.dayStartHour) }

    
    var viewDB: Database { remoteDB ?? db }
    var viewingRemote: Bool { remoteDB != nil }

    private init() {
        let path = BackupService.supportDir.appendingPathComponent("todaydo.sqlite").path
        do {
            db = try Database(path: path)
        } catch {
            let a = NSAlert()
            a.messageText = "Could not open database"
            a.informativeText = "\(error)"
            a.runModal()
            exit(1)
        }
        classifier = Classifier(db: db)
        settings = Settings.load()
        reloadMeta()
    }

    func reloadMeta() {
        categories = db.categories()
        projects = db.projects()
        bump()
    }

    func bump() {
        dataVersion &+= 1
        refreshMenuTitle()
    }

    func refreshMenuTitle() {
        if tracker.status == .manualPaused {
            menuTitle = "Paused"
        } else if let p = reminders.pomodoro {
            let secs = Int(p.remainingSeconds().rounded())
            let mm = secs / 60
            let ss = secs % 60
            let icon = p.phase == .work ? "🍅" : "☕️"
            let pauseTag = p.isPaused ? "⏸ " : ""
            menuTitle = String(format: "%@ %@%02d:%02d", icon, pauseTag, mm, ss)
        } else {
            menuTitle = ""
        }
    }

    

    func start() {
        integrityIssue = !db.quickCheck()
        Notifier.setup()
        tracker.start()
        backup.dailySnapshot()
        refreshDevices()
        let t = Timer(timeInterval: 600, repeats: true) { _ in
            MainActor.assumeIsolated { AppModel.shared.periodic() }
        }
        t.tolerance = 60
        RunLoop.main.add(t, forMode: .common)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { AppModel.shared.periodic() }
    }

    func periodic() {
        backup.dailySnapshot()
        calendar.sync()
        if settings.icloudBackup {
            let today = dc.dayKey(dc.dayStart(containing: Date()))
            if UserDefaults.standard.string(forKey: "todaydo.lastICloud") != today {
                backup.icloudBackup()
                UserDefaults.standard.set(today, forKey: "todaydo.lastICloud")
            }
        }
    }

    func terminate() {
        tracker.stop()
        if settings.icloudBackup { backup.icloudBackup() }
    }

    

    private func settingsChanged(_ old: Settings) {
        settings.save()
        if settings.launchAtLogin != old.launchAtLogin {
            do {
                if settings.launchAtLogin { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch { flash = "Could not configure launch at login: \(error.localizedDescription)" }
        }
        if settings.calendarSync != old.calendarSync {
            if settings.calendarSync {
                Task {
                    if await calendar.requestAccess() { calendar.sync() } else { settings.calendarSync = false }
                }
            } else {
                calendar.clearAll()
            }
        }
        if settings.icloudBackup && !old.icloudBackup { backup.icloudBackup(); refreshDevices() }
        if settings.dayStartHour != old.dayStartHour { bump() }
    }

    

    func catName(_ id: Int64) -> String { categories.first { $0.id == id }?.name ?? "Other" }
    func catColor(_ id: Int64) -> Color { Color(hex: categories.first { $0.id == id }?.color ?? "#9AA3B2") }
    func projectName(_ id: Int64?) -> String? { id.flatMap { i in projects.first { $0.id == i }?.name } }

    func refreshDevices() {
        devices = BackupService.icloudAvailable ? backup.otherDevices() : []
        if let id = viewDeviceId, !devices.contains(where: { $0.id == id }) { selectDevice(nil) }
    }

    func selectDevice(_ id: String?) {
        viewDeviceId = id
        if let id, let d = devices.first(where: { $0.id == id }), d.ready {
            remoteDB = try? Database(path: d.path, readOnly: true)
            if remoteDB == nil { viewDeviceId = nil }
        } else {
            remoteDB = nil
            if id != nil { flash = "This device's backup has not finished downloading, Please try again later"; viewDeviceId = nil }
        }
        bump()
    }

    
    func afterEdit() {
        reloadMeta()
        calendar.sync()
    }

    func reclassify() {
        tracker.commitBoundary()
        classifier.reload(db)
        try? db.reclassifyAll(using: classifier, calendar: dc.calendar)
        afterEdit()
    }

    func edit(from: Int64, to: Int64, _ action: EditAction) {
        tracker.commitBoundary()
        do { try db.applyEdit(from: from, to: to, action: action) } catch { flash = "Edit failed: \(error)" }
        afterEdit()
    }

    func undo() {
        tracker.commitBoundary()
        if let op = try? db.undoLastEdit() { flash = "Undone: \(op)" }
        afterEdit()
    }

    func openMain() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { $0.title == "todaydo" && $0.canBecomeMain }) {
            w.makeKeyAndOrderFront(nil)
        } else {
            openWindowAction?()
        }
    }

    

    func presentAway(from: Date, to: Date) {
        FloatingPanel.show(id: "away", duration: 30) {
            AwayPromptView(from: from, to: to)
                .environmentObject(AppModel.shared)
        }
    }

    func saveAway(from: Date, to: Date, label: String, categoryId: Int64, projectId: Int64?) {
        let s = Session(startTs: from.ts, endTs: to.ts, source: "away", categoryId: categoryId,
                        projectId: projectId, label: label, edited: true)
        _ = try? db.addManualSession(s)
        FloatingPanel.close(id: "away")
        afterEdit()
    }
}



final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Notifier.available { UNUserNotificationCenter.current().delegate = self }
        Task { @MainActor in
            AppModel.shared.start()
            if !UserDefaults.standard.bool(forKey: "todaydo.launchedBefore") {
                UserDefaults.standard.set(true, forKey: "todaydo.launchedBefore")
                try? await Task.sleep(nanoseconds: 800_000_000)
                AppModel.shared.openMain()
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated { AppModel.shared.terminate() }
        return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in AppModel.shared.openMain() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let rule = response.notification.request.content.userInfo["ruleId"] as? String
        let action = response.actionIdentifier
        await MainActor.run {
            let m = AppModel.shared
            switch action {
            case "snooze": if let r = rule { m.reminders.snooze(r) }
            case "mute": if let r = rule { m.reminders.muteToday(r) }
            case "stood": m.reminders.stood()
            default: m.openMain()
            }
        }
    }
}
