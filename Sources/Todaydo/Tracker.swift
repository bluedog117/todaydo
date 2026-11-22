import AppKit
import IOKit.pwr_mgt
import CoreGraphics
import TodaydoCore


struct ActivityContext {
    var now: Date
    var isActive: Bool
    var continuousSeconds: TimeInterval
    var bundleId: String?
    var domain: String?
    var name: String
    var categoryId: Int64
    var categorySince: Date?
    var keySince: Date?
    var key: String
}


@MainActor
final class Tracker: ObservableObject {
    enum Status: Equatable { case recording, idle, systemPaused, manualPaused, excluded }

    @Published var status: Status = .idle
    @Published var currentName = ""
    @Published var currentCategoryId: Int64 = 5
    @Published var pausedUntil: Date?
    @Published var browserDenied = false

    unowned let model: AppModel
    private let browser = BrowserReader()

    private struct Live {
        var id: Int64
        var key: String
        var start: Int64
        var end: Int64
        var bundle: String?
        var domain: String?
        var name: String
        var cat: Int64
        var viaMedia: Bool
    }

    private var live: Live?
    private var lastEnded: Live?
    private var lastActivityAt: Date?
    private var inactiveSince: Date?
    private var continuousSince: Date?
    private var categorySince: Date?
    private var keySince: Date?
    private var lastCat: Int64 = -1
    private var lastKey = ""
    private var locked = false, asleep = false, screenOff = false
    private var timer: Timer?
    private var knownApps: Set<String> = []
    private var tickCount = 0

    private let alwaysExcluded: Set<String> = [
        "com.apple.loginwindow", "com.apple.ScreenSaver.Engine", "com.apple.screensaver",
    ]
    private let defaultExcludedOnFirstSight: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.agilebits.onepassword-osx",
        "com.apple.keychainaccess", "com.apple.Passwords", "com.bitwarden.desktop",
    ]

    init(model: AppModel) { self.model = model }

    var continuousSeconds: TimeInterval {
        guard let c = continuousSince else { return 0 }
        return Date().timeIntervalSince(c)
    }

    var isPaused: Bool { status == .manualPaused }

    
    func resetContinuous() { continuousSince = Date() }

    

    func start() {
        knownApps = Set(model.db.apps().map(\.bundleId))
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.appActivated(app) }
        }
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setInactive { $0.asleep = true } }
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setActive { $0.asleep = false } }
        }
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setInactive { $0.screenOff = true } }
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setActive { $0.screenOff = false } }
        }
        let dn = DistributedNotificationCenter.default()
        dn.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setInactive { $0.locked = true } }
        }
        dn.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setActive { $0.locked = false } }
        }

        let t = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 3
        RunLoop.main.add(t, forMode: .common)
        timer = t
        evaluate(appSwitched: true)
    }

    func stop() {
        endCurrent(at: Date())
        timer?.invalidate()
    }

    

    private var systemInactive: Bool { locked || asleep || screenOff }

    private func setInactive(_ change: (Tracker) -> Void) {
        change(self)
        let now = Date()
        if live != nil { lastActivityAt = now }   
        endCurrent(at: now)
        if status != .manualPaused { status = .systemPaused }
        if inactiveSince == nil { inactiveSince = now }
    }

    private func setActive(_ change: (Tracker) -> Void) {
        change(self)
        if !systemInactive {
            if status == .systemPaused { status = .idle }
            evaluate(appSwitched: false)
        }
    }

    private func appActivated(_ app: NSRunningApplication?) {
        if app?.bundleIdentifier != Bundle.main.bundleIdentifier, status != .manualPaused, !systemInactive {
            model.db.incrementSwitch(at: Date())
        }
        evaluate(appSwitched: true)
    }

    private func tick() {
        tickCount += 1
        evaluate(appSwitched: false)
        if tickCount % 3 == 0 { model.bump() }
        model.reminders.tick(context())
    }

    func context() -> ActivityContext {
        ActivityContext(now: Date(), isActive: status == .recording, continuousSeconds: continuousSeconds,
                        bundleId: live?.bundle, domain: live?.domain, name: currentName,
                        categoryId: currentCategoryId, categorySince: categorySince, keySince: keySince,
                        key: live?.key ?? "")
    }

    

    func pause(minutes: Int?) {
        endCurrent(at: Date())
        lastEnded = nil
        status = .manualPaused
        pausedUntil = minutes.map { Date().addingTimeInterval(Double($0) * 60) }
        lastActivityAt = nil
        inactiveSince = nil
        continuousSince = nil
        currentName = ""
        model.bump()
    }

    func pauseUntilTomorrow() {
        let end = model.dc.nextDayStart(after: model.dc.dayStart(containing: Date()))
        pause(minutes: max(1, Int(end.timeIntervalSinceNow / 60)))
    }

    func resume() {
        guard status == .manualPaused else { return }
        pausedUntil = nil
        status = .idle
        lastActivityAt = nil
        evaluate(appSwitched: true)
        model.bump()
    }

    
    func commitBoundary() {
        endCurrent(at: Date())
        lastEnded = nil
    }

    

    private func idleSeconds() -> Double {
        let any = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
    }

    
    private func hasMedia(pid: pid_t) -> Bool {
        var ref: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&ref) == kIOReturnSuccess,
              let dict = ref?.takeRetainedValue() as NSDictionary?,
              let arr = dict[NSNumber(value: pid)] as? [[String: Any]] else { return false }
        for a in arr {
            let type = a["AssertType"] as? String ?? ""
            let name = (a["AssertName"] as? String ?? "").lowercased()
            if type == "PreventUserIdleDisplaySleep" || type == "NoDisplaySleepAssertion" { return true }
            if type == "PreventUserIdleSystemSleep" && (name.contains("audio") || name.contains("playing")) { return true }
        }
        return false
    }

    private func evaluate(appSwitched: Bool) {
        let now = Date()
        if status == .manualPaused {
            if let u = pausedUntil, now >= u { resume() }
            return
        }
        guard !systemInactive else { return }
        guard let app = NSWorkspace.shared.frontmostApplication else { return }

        let settings = model.settings
        let bundle = app.bundleIdentifier
        let idle = idleSeconds()
        let media = hasMedia(pid: app.processIdentifier)
        let threshold = Double(settings.idleMinutes * 60)
        let active = idle < threshold || media

        
        if !active {
            if live != nil {
                let lastInput = now.addingTimeInterval(-idle)
                endCurrent(at: lastInput)
                lastActivityAt = lastInput
                inactiveSince = lastInput
            } else if inactiveSince == nil {
                inactiveSince = now
            }
            status = .idle
            return
        }

        
        if let ia = inactiveSince {
            if now.timeIntervalSince(ia) >= Double(settings.stand.restMin * 60) { continuousSince = now }
            inactiveSince = nil
        }
        if continuousSince == nil { continuousSince = now }

        
        let isOwn = bundle == Bundle.main.bundleIdentifier
        if isOwn || (bundle.map { alwaysExcluded.contains($0) } ?? false) || model.classifier.isExcluded(bundleId: bundle, domain: nil) {
            endCurrent(at: now)
            lastEnded = nil
            lastActivityAt = now
            status = .excluded
            currentName = ""
            return
        }

        
        var domain: String?
        if settings.browserDomains, BrowserReader.isBrowser(bundle), let b = bundle {
            switch browser.read(bundleId: b) {
            case .domain(let d): domain = d
            case .denied: browserDenied = true
            case .none, .failed: break
            }
            if !browser.deniedBundles.isEmpty != browserDenied { browserDenied = !browser.deniedBundles.isEmpty }
        }
        if let d = domain, model.classifier.isExcluded(bundleId: nil, domain: d) {
            endCurrent(at: now)
            lastEnded = nil
            lastActivityAt = now
            status = .excluded
            currentName = ""
            return
        }

        let name = app.localizedName ?? bundle ?? "Unknown app"
        let key = (domain.map { "d:" + $0 } ?? "a:" + (bundle ?? name))

        if var l = live, l.key == key {
            
            l.end = max(l.end, now.ts)
            if media && !l.viaMedia { l.viaMedia = true; model.db.updateViaMedia(id: l.id, value: true) }
            live = l
            model.db.updateEnd(id: l.id, end: l.end)
        } else {
            let wasIdle = (live == nil)
            endCurrent(at: now)
            
            var startDate = now
            if !appSwitched {
                let inputTime = (media && idle >= threshold) ? now : now.addingTimeInterval(-idle)
                startDate = max(inputTime, lastActivityAt ?? now)
            }
            
            if wasIdle, let la = lastActivityAt, settings.awayEnabled {
                let gap = startDate.timeIntervalSince(la)
                let sameDay = model.dc.dayStart(containing: la) == model.dc.dayStart(containing: startDate)
                if gap >= Double(settings.awayMinMinutes * 60), gap <= Double(settings.awayMaxHours * 3600), sameDay {
                    model.presentAway(from: la, to: startDate)
                }
            }
            beginSession(bundle: bundle, name: name, domain: domain, key: key, start: startDate, now: now, media: media)
        }

        lastActivityAt = now
        status = .recording
        currentName = domain ?? name
        if let l = live {
            currentCategoryId = l.cat
            if l.cat != lastCat { lastCat = l.cat; categorySince = now }
            if l.key != lastKey { lastKey = l.key; keySince = now }
        }
    }

    private func beginSession(bundle: String?, name: String, domain: String?, key: String, start: Date, now: Date, media: Bool) {
        
        if let le = lastEnded, le.key == key, start.ts - le.end <= 30, model.db.session(id: le.id) != nil {
            var l = le
            l.end = max(now.ts, le.end)
            live = l
            model.db.updateEnd(id: l.id, end: l.end)
            lastEnded = nil
            return
        }
        if let b = bundle, !knownApps.contains(b) {
            knownApps.insert(b)
            model.db.registerApp(bundleId: b, name: name, defaultCategory: Classifier.defaultCategory(bundleId: b))
            if defaultExcludedOnFirstSight.contains(b) { try? model.db.setApp(bundleId: b, excluded: true) }
            model.classifier.reload(model.db)
        }
        let cat = model.classifier.classify(bundleId: bundle, domain: domain, date: start, calendar: model.dc.calendar)
        let pid = model.classifier.projectId(bundleId: bundle, domain: domain)
        let startTs = start.ts
        let endTs = max(now.ts, startTs)
        let s = Session(startTs: startTs, endTs: endTs, source: "auto", bundleId: bundle, appName: name,
                        domain: domain, categoryId: cat, projectId: pid, viaMedia: media)
        if let id = try? model.db.insertSession(s) {
            live = Live(id: id, key: key, start: startTs, end: endTs, bundle: bundle, domain: domain,
                        name: name, cat: cat, viaMedia: media)
        }
    }

    
    private func endCurrent(at date: Date) {
        guard var l = live else { return }
        l.end = max(l.start, date.ts)
        if l.end - l.start < 5 {
            model.db.deleteSession(id: l.id)
        } else {
            model.db.updateEnd(id: l.id, end: l.end)
            lastEnded = l
        }
        live = nil
    }
}
