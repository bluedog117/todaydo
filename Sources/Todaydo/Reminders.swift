import Foundation
import TodaydoCore



@MainActor
final class ReminderEngine: ObservableObject {
    enum Phase: Equatable { case work, rest, longRest }
    struct Pomodoro: Equatable {
        var phase: Phase
        var start: Date
        var end: Date
        var auto: Bool
        var task: String = ""
        var pausedRemaining: TimeInterval? = nil

        var isPaused: Bool { pausedRemaining != nil }
        var totalSeconds: TimeInterval { max(1, end.timeIntervalSince(start)) }

        func remainingSeconds(at now: Date = Date()) -> TimeInterval {
            if let r = pausedRemaining { return max(0, r) }
            return max(0, end.timeIntervalSince(now))
        }
    }

    @Published var pomodoro: Pomodoro?
    @Published var todayPomodoros: Int = 0
    @Published var pomodoroTick: Int = 0

    unowned let model: AppModel
    private var snoozedUntil: [String: Date] = [:]
    private var mutedDay: [String: String] = [:]
    private var lastFired: [String: Date] = [:]
    private var firedKeys: Set<String> = []
    private var lastMinute: Int64 = 0
    private var secTimer: Timer?
    private let started = Date()
    private let defaults = UserDefaults.standard

    init(model: AppModel) {
        self.model = model
        mutedDay = (defaults.dictionary(forKey: "todaydo.mutedDay") as? [String: String]) ?? [:]
        reloadTodayCount()
    }

    private func reloadTodayCount() {
        let dayKey = model.dc.dayKey(model.dc.dayStart(containing: Date()))
        if defaults.string(forKey: "todaydo.pomodoroDay") == dayKey {
            todayPomodoros = defaults.integer(forKey: "todaydo.pomodoroCount")
        } else {
            todayPomodoros = 0
            defaults.set(dayKey, forKey: "todaydo.pomodoroDay")
            defaults.set(0, forKey: "todaydo.pomodoroCount")
        }
    }

    private func incrementTodayCount() {
        reloadTodayCount()
        todayPomodoros += 1
        defaults.set(todayPomodoros, forKey: "todaydo.pomodoroCount")
    }

    private func ensureSecTimer() {
        guard secTimer == nil else { return }
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.secondTick() }
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        secTimer = t
    }

    private func stopSecTimerIfIdle() {
        if pomodoro == nil {
            secTimer?.invalidate()
            secTimer = nil
        }
    }

    

    func snooze(_ ruleId: String, minutes: Int = 10) {
        snoozedUntil[ruleId] = Date().addingTimeInterval(Double(minutes) * 60)
    }

    func muteToday(_ ruleId: String) {
        mutedDay[ruleId] = model.dc.dayKey(model.dc.dayStart(containing: Date()))
        defaults.set(mutedDay, forKey: "todaydo.mutedDay")
    }

    func stood() {
        model.tracker.resetContinuous()
    }

    func startPomodoro(minutes: Int? = nil, task: String = "", auto: Bool = false) {
        reloadTodayCount()
        let f = model.settings.focus
        let mins = minutes ?? f.workMin
        let now = Date()
        pomodoro = Pomodoro(phase: .work, start: now, end: now.addingTimeInterval(Double(mins) * 60), auto: auto, task: task)
        ensureSecTimer()
        Notifier.playSystemSound(f.soundName)
        model.refreshMenuTitle()
    }

    func startBreak(long: Bool = false, auto: Bool = false, task: String = "") {
        let f = model.settings.focus
        let mins = long ? f.longRestMin : f.restMin
        let now = Date()
        pomodoro = Pomodoro(phase: long ? .longRest : .rest, start: now, end: now.addingTimeInterval(Double(mins) * 60), auto: auto, task: task)
        ensureSecTimer()
        model.refreshMenuTitle()
    }

    func togglePausePomodoro() {
        guard var p = pomodoro else { return }
        let now = Date()
        if let rem = p.pausedRemaining {
            let total = p.totalSeconds
            p.end = now.addingTimeInterval(rem)
            p.start = p.end.addingTimeInterval(-total)
            p.pausedRemaining = nil
        } else {
            p.pausedRemaining = max(1, p.end.timeIntervalSince(now))
        }
        pomodoro = p
        model.refreshMenuTitle()
    }

    func skipPomodoroPhase() {
        guard let p = pomodoro else { return }
        completePhase(p, now: Date(), skipped: true)
    }

    func addPomodoroMinutes(_ mins: Int) {
        guard var p = pomodoro else { return }
        let delta = Double(mins * 60)
        if let rem = p.pausedRemaining {
            p.pausedRemaining = max(60, rem + delta)
        } else {
            p.end = p.end.addingTimeInterval(delta)
        }
        pomodoro = p
        model.refreshMenuTitle()
    }

    func stopPomodoro() {
        pomodoro = nil
        stopSecTimerIfIdle()
        model.refreshMenuTitle()
    }

    private func secondTick() {
        guard let p = pomodoro else { stopSecTimerIfIdle(); return }
        pomodoroTick &+= 1
        let now = Date()
        if !p.isPaused && now >= p.end {
            completePhase(p, now: now, skipped: false)
        } else {
            model.refreshMenuTitle()
        }
    }

    private func completePhase(_ p: Pomodoro, now: Date, skipped: Bool) {
        let s = model.settings
        Notifier.playSystemSound(s.focus.soundName)
        if p.phase == .work {
            if !skipped { incrementTodayCount() }
            let every = max(2, s.focus.longRestEvery)
            let isLong = (!skipped && todayPomodoros > 0 && todayPomodoros % every == 0)
            let restMins = isLong ? s.focus.longRestMin : s.focus.restMin
            pomodoro = Pomodoro(phase: isLong ? .longRest : .rest, start: now, end: now.addingTimeInterval(Double(restMins) * 60), auto: p.auto, task: p.task)
            let title = isLong ? "Completed \(todayPomodoros) pomodoros 🍅 Starting a long break" : "Focus complete 🍅"
            let body = (p.task.isEmpty ? "" : "“\(p.task)” is complete, ") + "Break \(restMins) min break. "
            Notifier.send(title: title, body: body)
            FloatingPanel.show(id: "toast-pomodoro", duration: 6) {
                ToastView(title: title, message: body, icon: "cup.and.saucer.fill")
            }
        } else {
            pomodoro = nil
            stopSecTimerIfIdle()
            let title = "Break finished"
            let body = "Completed today: \(todayPomodoros) pomodoros, Ready for another focus session??"
            Notifier.send(title: title, body: body)
            FloatingPanel.show(id: "toast-pomodoro", duration: 6) {
                ToastView(title: title, message: body, icon: "timer")
            }
        }
        model.refreshMenuTitle()
    }

    

    private func allowed(_ rule: String, now: Date, cooldown: TimeInterval, ignoreHours: Bool = false) -> Bool {
        if let u = snoozedUntil[rule], u > now { return false }
        if let m = mutedDay[rule], m == model.dc.dayKey(model.dc.dayStart(containing: now)) { return false }
        if let l = lastFired[rule], now.timeIntervalSince(l) < cooldown { return false }
        if !ignoreHours {
            let h = Calendar.current.component(.hour, from: now)
            let s = model.settings
            if h < s.reminderStartHour || h >= s.reminderEndHour { return false }
        }
        return true
    }

    private func fire(_ rule: String, now: Date, cooldown: TimeInterval, title: String, body: String,
                      category: String = "REMINDER", floating: Bool = false) {
        guard allowed(rule, now: now, cooldown: cooldown) else { return }
        lastFired[rule] = now
        if floating {
            FloatingPanel.show(id: "toast-" + rule, duration: 8) { ToastView(title: title, message: body) }
        } else {
            Notifier.send(title: title, body: body, ruleId: rule, category: category)
        }
    }

    func tick(_ ctx: ActivityContext) {
        let now = ctx.now
        let minute = Int64(now.timeIntervalSince1970 / 60)
        guard minute != lastMinute else { return }
        lastMinute = minute
        let s = model.settings

        
        if let p = pomodoro, !p.isPaused, now >= p.end {
            completePhase(p, now: now, skipped: false)
        }
        if s.focus.enabled, pomodoro == nil, ctx.isActive,
           s.focus.categoryIds.contains(ctx.categoryId),
           let since = ctx.categorySince, now.timeIntervalSince(since) >= Double(s.focus.triggerMin * 60) {
            startPomodoro(minutes: s.focus.workMin, task: ctx.name, auto: true)
            Notifier.send(title: "Focus started 🍅", body: "Automatically started \(s.focus.workMin) min focus session. ")
        }
        if let p = pomodoro, !p.isPaused, p.phase == .work, ctx.isActive, s.focus.distractIds.contains(ctx.categoryId) {
            Notifier.playSystemSound(s.focus.soundName)
            fire("focus-distract", now: now, cooldown: 300, title: "Distracted??",
                 body: "Pomodoro remaining: \(max(1, Int(p.remainingSeconds(at: now) / 60))) min, You are using “\(ctx.name)”. ")
        }

        
        if s.stand.enabled, ctx.isActive, ctx.continuousSeconds >= Double(s.stand.intervalMin * 60) {
            fire("stand", now: now, cooldown: 600, title: "Time to stand up",
                 body: "You have used your computer for \(Int(ctx.continuousSeconds / 60)) min. ", category: "STAND")
        }

        
        if s.aware.enabled, ctx.isActive {
            let ref = lastFired["aware"] ?? started
            if now.timeIntervalSince(ref) >= Double(s.aware.everyMin * 60) {
                let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "HH:mm"
                fire("aware", now: now, cooldown: 0, title: "It is now \(f.string(from: now))",
                     body: "Currently using “\(ctx.name)”, Used continuously for \(Int(ctx.continuousSeconds / 60)) min. ", floating: s.aware.floating)
            }
        }
        if s.aware.appEveryMin > 0, ctx.isActive, let since = ctx.keySince {
            let n = Int(now.timeIntervalSince(since) / 60)
            let step = s.aware.appEveryMin
            if n >= step {
                fire("aware-app", now: now, cooldown: Double(step * 60), title: "“\(ctx.name)”Continuous: \(n) min",
                     body: "Check the time, Time to switch activities??", floating: s.aware.floating)
            }
        }

        
        if !s.limits.isEmpty || !s.goals.isEmpty {
            let r = model.dc.dayRange(containing: now)
            let today = Stats.clipped(model.db.sessions(from: r.start.ts, to: r.end.ts), from: r.start.ts, to: min(r.end.ts, now.ts))
            let dayKey = model.dc.dayKey(r.start)
            let byCat = Stats.byCategory(today)

            for l in s.limits {
                let used: Int64
                switch l.kind {
                case "category": used = byCat[Int64(l.key) ?? -1] ?? 0
                case "app": used = today.filter { $0.bundleId == l.key }.reduce(0) { $0 + $1.duration }
                default: used = today.filter { $0.domain == l.key }.reduce(0) { $0 + $1.duration }
                }
                let limit = Int64(l.minutes * 60)
                let id = l.id.uuidString
                if used >= limit {
                    let k = "limit100-\(id)-\(dayKey)"
                    if !firedKeys.contains(k) {
                        firedKeys.insert(k)
                        Notifier.send(title: "Daily limit reached", body: "“\(l.name)” used today \(Stats.formatDuration(used)), More than \(l.minutes) min limit. ", ruleId: "limit-" + id)
                    }
                } else if Double(used) >= Double(limit) * 0.8 {
                    let k = "limit80-\(id)-\(dayKey)"
                    if !firedKeys.contains(k) {
                        firedKeys.insert(k)
                        Notifier.send(title: "Approaching daily limit", body: "“\(l.name)”Used \(Stats.formatDuration(used)), approximately remaining: \(Stats.formatDuration(limit - used)). ", ruleId: "limit-" + id)
                    }
                }
            }
            let hour = Calendar.current.component(.hour, from: now)
            for g in s.goals where hour >= g.atHour && hour < g.atHour + 3 {
                let k = "goal-\(g.id.uuidString)-\(dayKey)"
                guard !firedKeys.contains(k) else { continue }
                firedKeys.insert(k)
                let done = byCat[g.categoryId] ?? 0
                if done < Int64(g.minutes * 60) {
                    Notifier.send(title: "Daily goal not yet reached", body: "“\(g.name)”Goal \(g.minutes) min, currently \(Stats.formatDuration(done)). ", ruleId: "goal-" + g.id.uuidString)
                }
            }
        }

        
        let hour = Calendar.current.component(.hour, from: now)
        let todayStart = model.dc.dayStart(containing: now)
        if s.summary.dailyEnabled, hour >= s.summary.dailyHour {
            let k = model.dc.dayKey(todayStart)
            if defaults.string(forKey: "todaydo.lastDaily") != k {
                defaults.set(k, forKey: "todaydo.lastDaily")
                let (t, b) = SummaryBuilder.daily(model: model, dayStart: todayStart, now: now)
                Notifier.send(title: t, body: b)
            }
        }
        if s.summary.weeklyEnabled, model.dc.isoWeekday(todayStart) == 1, hour >= s.summary.weeklyHour {
            let k = model.dc.dayKey(todayStart)
            if defaults.string(forKey: "todaydo.lastWeekly") != k {
                defaults.set(k, forKey: "todaydo.lastWeekly")
                let (t, b) = SummaryBuilder.weekly(model: model, thisWeekStart: model.dc.weekStart(containing: now))
                Notifier.send(title: t, body: b)
            }
        }
    }
}



@MainActor
enum SummaryBuilder {
    static func catName(_ model: AppModel, _ id: Int64) -> String {
        model.categories.first { $0.id == id }?.name ?? "Other"
    }

    static func daily(model: AppModel, dayStart: Date, now: Date) -> (String, String) {
        let dc = model.dc
        let end = dc.nextDayStart(after: dayStart)
        let day = Stats.clipped(model.db.sessions(from: dayStart.ts, to: end.ts), from: dayStart.ts, to: end.ts)
        let total = Stats.total(day)
        let cats = Stats.byCategory(day).sorted { $0.value > $1.value }.prefix(3)
            .map { "\(catName(model, $0.key)) \(Stats.formatDuration($0.value, compact: true))" }.joined(separator: " · ")
        let longest = Stats.focusSegments(day).max { $0.duration < $1.duration }

        
        var sum: Int64 = 0
        var n: Int64 = 0
        for i in 1...7 {
            let ds = dc.addDays(-i, to: dayStart)
            let de = dc.nextDayStart(after: ds)
            let t = Stats.total(Stats.clipped(model.db.sessions(from: ds.ts, to: de.ts), from: ds.ts, to: de.ts))
            if t > 0 { sum += t; n += 1 }
        }
        var lines = ["Today: \(Stats.formatDuration(total))" + (cats.isEmpty ? "" : ": \(cats)")]
        if let l = longest, l.duration >= 600 {
            lines.append("Longest focus \(Stats.formatDuration(l.duration, compact: true)) (\(clockString(l.start))–\(clockString(l.end)), \(catName(model, l.categoryId)))")
        }
        if n > 0 {
            let diff = total - sum / n
            lines.append("Compared with the last 7 day average\(diff >= 0 ? "more" : "less") \(Stats.formatDuration(abs(diff)))")
        }
        let byCat = Stats.byCategory(day)
        for g in model.settings.goals {
            let done = byCat[g.categoryId] ?? 0
            lines.append("Goal“\(g.name)”\(Stats.formatDuration(done))/\(g.minutes) min \(done >= Int64(g.minutes * 60) ? "✓" : "")")
        }
        return ("Daily summary", lines.joined(separator: "\n"))
    }

    static func weekly(model: AppModel, thisWeekStart: Date) -> (String, String) {
        let dc = model.dc
        let lastStart = dc.addDays(-7, to: thisWeekStart)
        let prevStart = dc.addDays(-14, to: thisWeekStart)
        func week(_ start: Date) -> [Session] {
            let end = dc.addDays(7, to: start)
            return Stats.clipped(model.db.sessions(from: start.ts, to: end.ts), from: start.ts, to: end.ts)
        }
        let last = week(lastStart), prev = week(prevStart)
        let tl = Stats.total(last), tp = Stats.total(prev)
        var lines = ["Last week: \(Stats.formatDuration(tl))" + (tp > 0 ? ", compared with the previous week: \(tl >= tp ? "more" : "less") \(Stats.formatDuration(abs(tl - tp)))" : "")]
        let c1 = Stats.byCategory(last), c0 = Stats.byCategory(prev)
        let changes = c1.map { ($0.key, $0.value - (c0[$0.key] ?? 0)) }.sorted { abs($0.1) > abs($1.1) }.prefix(2)
        for (k, d) in changes where abs(d) >= 600 {
            lines.append("\(catName(model, k)) \(d >= 0 ? "increased by " : "decreased by ") \(Stats.formatDuration(abs(d), compact: true))")
        }
        let days = (0..<7).map { dc.addDays($0, to: lastStart) }
        let frag = days.map { d -> (Date, Double) in
            let e = dc.nextDayStart(after: d)
            return (d, Stats.fragmentation(Stats.clipped(last, from: d.ts, to: e.ts)))
        }.max { $0.1 < $1.1 }
        if let f = frag, f.1 > 0 {
            let wd = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][dc.isoWeekday(f.0) - 1]
            lines.append("Most fragmented day: Week \(wd) (\(Int(f.1 * 100))% of sessions shorter than 2 min)")
        }
        let types = model.db.dayTypes()
        let wk = days.filter { !dc.isWeekend($0, dayTypes: types) }, we = days.filter { dc.isWeekend($0, dayTypes: types) }
        func avg(_ ds: [Date]) -> Int64 {
            guard !ds.isEmpty else { return 0 }
            return ds.reduce(Int64(0)) { acc, d in acc + Stats.total(Stats.clipped(last, from: d.ts, to: dc.nextDayStart(after: d).ts)) } / Int64(ds.count)
        }
        lines.append("Workday average \(Stats.formatDuration(avg(wk), compact: true)), Weekend average \(Stats.formatDuration(avg(we), compact: true))")
        return ("Weekly review", lines.joined(separator: "\n"))
    }
}
