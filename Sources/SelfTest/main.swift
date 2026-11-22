import Foundation
import TodaydoCore

var failures = 0
func check(_ cond: Bool, _ name: String, line: Int = #line) {
    if cond { print(" ✓ \(name)") } else { print(" ✗ \(name) (line \(line) line)"); failures += 1 }
}

func makeDB() -> Database { try! Database(path: ":memory:") }

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!

print("Logical day boundaries")
do {
    let dc = DayCalendar(dayStartHour: 4, calendar: cal)
    let t = cal.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 2))!
    check(dc.dayKey(dc.dayStart(containing: t)) == "2026-03-09", "Early morning 2 belongs to the previous day")
    let t2 = cal.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 4))!
    check(dc.dayKey(dc.dayStart(containing: t2)) == "2026-03-10", "4 starts a new day")
    let r = dc.dayRange(containing: t2)
    check(r.end.timeIntervalSince(r.start) == 86400, "One day 24 hours")
    let mon = cal.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12))!
    check(dc.isoWeekday(dc.dayStart(containing: mon)) == 1, "2026-03-09 is a Monday")
    check(dc.dayKey(dc.weekStart(containing: t2)) == "2026-03-09", "Week starts on Monday")
    check(!dc.isWeekend(dc.dayStart(containing: mon)), "Monday is not a weekend")
    check(dc.isWeekend(dc.dayStart(containing: mon), dayTypes: ["2026-03-09": "weekend"]), "Manually mark as a day off")
}

print("Classification priority")
do {
    let db = makeDB()
    db.registerApp(bundleId: "com.google.Chrome", name: "Chrome", defaultCategory: 5)
    try! db.addCategoryRule(CategoryRule(matchType: "app", matchValue: "com.tencent.xinWeChat",
                                         weekdayMask: 0b0111110, startMin: 540, endMin: 1080, categoryId: 1, priority: 1))
    let c = Classifier(db: db)
    let mon10 = cal.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 10))!
    let mon20 = cal.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 20))!
    let sat10 = cal.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 10))!
    check(c.classify(bundleId: "com.tencent.xinWeChat", domain: nil, date: mon10, calendar: cal) == 1, "Workday 9–18 WeChat → Work")
    check(c.classify(bundleId: "com.tencent.xinWeChat", domain: nil, date: mon20, calendar: cal) == 4, "WeChat in the evening → Social")
    check(c.classify(bundleId: "com.tencent.xinWeChat", domain: nil, date: sat10, calendar: cal) == 4, "WeChat on weekends → Social")
    check(c.classify(bundleId: "com.google.Chrome", domain: "www.bilibili.com", date: mon10, calendar: cal) == 3, "Subdomain match bilibili → Entertainment")
    check(c.classify(bundleId: "com.google.Chrome", domain: "github.com", date: mon10, calendar: cal) == 1, "github → Work")
    check(c.classify(bundleId: "com.google.Chrome", domain: "unknown.example", date: mon10, calendar: cal) == 5, "Unknown domain → Other")
    check(Classifier.hostCandidates("a.b.example.com") == ["a.b.example.com", "b.example.com", "example.com"], "Parent domain candidates")
}

print("Edit / Split / Undo")
do {
    let db = makeDB()
    try! db.insertSession(Session(startTs: 1000, endTs: 2000, bundleId: "a", appName: "A", categoryId: 5))
    try! db.applyEdit(from: 1200, to: 1500, action: .setCategory(3))
    var all = db.sessions(from: 0, to: 5000)
    check(all.count == 3, "Category edit splits into 3 segments")
    check(all[1].categoryId == 3 && all[1].edited, "Middle segment category=3 and marked edited")
    check(Stats.total(all) == 1000, "Total duration is unchanged")
    try! db.applyEdit(from: 1200, to: 1500, action: .delete)
    all = db.sessions(from: 0, to: 5000)
    check(all.count == 2 && Stats.total(all) == 700, "Delete the middle segment")
    try! db.undoLastEdit()
    try! db.undoLastEdit()
    all = db.sessions(from: 0, to: 5000)
    check(all.count == 1 && all[0].startTs == 1000 && all[0].endTs == 2000 && !all[0].edited, "Two undo operations restore the original session")
    try! db.splitSession(at: 1500)
    check(db.sessions(from: 0, to: 5000).count == 2, "Split session")
    try! db.undoLastEdit()
    check(db.sessions(from: 0, to: 5000).count == 1, "Undo split")
    _ = try! db.addManualSession(Session(startTs: 3000, endTs: 3600, source: "away", categoryId: 1, label: "Meeting"))
    check(db.sessions(from: 2500, to: 4000).count == 1, "Save offline activity")
    try! db.undoLastEdit()
    check(db.sessions(from: 2500, to: 4000).isEmpty, "Undo offline activity")
}

print("Statistics")
do {
    let s = [
        Session(startTs: 0, endTs: 600, bundleId: "a", appName: "A", categoryId: 1),
        Session(startTs: 650, endTs: 1200, bundleId: "b", appName: "B", categoryId: 1),
        Session(startTs: 1210, endTs: 1300, bundleId: "c", appName: "C", categoryId: 3),
        Session(startTs: 5000, endTs: 5030, bundleId: "a", appName: "A", categoryId: 1),
    ]
    let seg = Stats.focusSegments(s)
    check(seg.count == 3 && seg[0].duration == 1200, "Merge focus sessions (same category, Interval≤2 min)")
    check(Stats.rank(s).first?.key == "a:a", "Rank by total duration")
    check(abs(Stats.fragmentation(s) - 0.5) < 0.001, "Fragmentation ratio")
    check(Stats.clipped(s, from: 300, to: 700).map(\.duration) == [300, 50], "Clip to time range")
    check(Stats.formatDuration(3720) == "1 hours 2 min", "Duration formatting")
}

print("Backup / Restore")
do {
    let db = makeDB()
    try! db.insertSession(Session(startTs: 1, endTs: 100, bundleId: "a", appName: "A"))
    let tmp = NSTemporaryDirectory() + "todaydo-test-\(UUID().uuidString).sqlite"
    try! db.backup(to: tmp)
    try! db.run("DELETE FROM session")
    check(db.sessions(from: 0, to: 1000).isEmpty, "Cleared")
    try! db.restore(from: tmp)
    check(db.sessions(from: 0, to: 1000).count == 1, "Restore from snapshot")
    check(db.quickCheck(), "quick_check passed")
    let ro = try! Database(path: tmp, readOnly: true)
    check(ro.sessions(from: 0, to: 1000).count == 1, "Open backup read-only")
    try? FileManager.default.removeItem(atPath: tmp)
}

print(failures == 0 ? "\nAll checks passed ✅" : "\nFailed \(failures) checks ❌")
exit(failures == 0 ? 0 : 1)
