import Foundation
import SQLite3

public struct DBError: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct Row {
    let stmt: OpaquePointer
    public func int(_ i: Int32) -> Int64 { sqlite3_column_int64(stmt, i) }
    public func double(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
    public func isNull(_ i: Int32) -> Bool { sqlite3_column_type(stmt, i) == SQLITE_NULL }
    public func text(_ i: Int32) -> String? {
        guard !isNull(i), let c = sqlite3_column_text(stmt, i) else { return nil }
        return String(cString: c)
    }
    public func optInt(_ i: Int32) -> Int64? { isNull(i) ? nil : int(i) }
}


public final class Database {
    public let path: String
    public let readOnly: Bool
    var handle: OpaquePointer?

    public init(path: String, readOnly: Bool = false) throws {
        self.path = path
        self.readOnly = readOnly
        var flags: Int32 = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        var target = path
        if readOnly {
            flags |= SQLITE_OPEN_URI
            let enc = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
            target = "file:" + enc + "?immutable=1"
        }
        guard sqlite3_open_v2(target, &handle, flags, nil) == SQLITE_OK else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open database"
            throw DBError(message: msg)
        }
        sqlite3_busy_timeout(handle, 3000)
        if !readOnly {
            try exec("PRAGMA journal_mode=WAL")
            try exec("PRAGMA synchronous=NORMAL")
            try migrate()
        }
    }

    deinit { sqlite3_close(handle) }

    

    public func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
            let m = err.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(err)
            throw DBError(message: "\(m) — \(sql.prefix(80))")
        }
    }

    private func prepare(_ sql: String, _ args: [Any?]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
            throw DBError(message: String(cString: sqlite3_errmsg(handle)) + " — " + String(sql.prefix(80)))
        }
        for (i, a) in args.enumerated() {
            let idx = Int32(i + 1)
            switch a {
            case nil: sqlite3_bind_null(s, idx)
            case let v as Int: sqlite3_bind_int64(s, idx, Int64(v))
            case let v as Int64: sqlite3_bind_int64(s, idx, v)
            case let v as Bool: sqlite3_bind_int64(s, idx, v ? 1 : 0)
            case let v as Double: sqlite3_bind_double(s, idx, v)
            case let v as String: sqlite3_bind_text(s, idx, v, -1, SQLITE_TRANSIENT)
            default: sqlite3_bind_null(s, idx)
            }
        }
        return s
    }

    public func query<T>(_ sql: String, _ args: [Any?] = [], _ map: (Row) -> T) -> [T] {
        guard let s = try? prepare(sql, args) else { return [] }
        defer { sqlite3_finalize(s) }
        var out: [T] = []
        while sqlite3_step(s) == SQLITE_ROW { out.append(map(Row(stmt: s))) }
        return out
    }

    @discardableResult
    public func run(_ sql: String, _ args: [Any?] = []) throws -> Int {
        let s = try prepare(sql, args)
        defer { sqlite3_finalize(s) }
        let rc = sqlite3_step(s)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw DBError(message: String(cString: sqlite3_errmsg(handle)))
        }
        return Int(sqlite3_changes(handle))
    }

    public var lastInsertId: Int64 { sqlite3_last_insert_rowid(handle) }

    public func transaction(_ body: () throws -> Void) throws {
        try exec("BEGIN IMMEDIATE")
        do { try body(); try exec("COMMIT") } catch { try? exec("ROLLBACK"); throw error }
    }

    

    private func migrate() throws {
        let version = query("PRAGMA user_version") { $0.int(0) }.first ?? 0
        if version >= 1 { return }
        try exec("""
        CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE IF NOT EXISTS category(id INTEGER PRIMARY KEY, name TEXT NOT NULL, color TEXT NOT NULL, sort INTEGER DEFAULT 0);
        CREATE TABLE IF NOT EXISTS app(bundle_id TEXT PRIMARY KEY, name TEXT, category_id INTEGER NOT NULL, excluded INTEGER DEFAULT 0);
        CREATE TABLE IF NOT EXISTS domain(host TEXT PRIMARY KEY, category_id INTEGER NOT NULL, excluded INTEGER DEFAULT 0);
        CREATE TABLE IF NOT EXISTS category_rule(id INTEGER PRIMARY KEY AUTOINCREMENT, match_type TEXT NOT NULL, match_value TEXT NOT NULL,
            weekday_mask INTEGER DEFAULT 0, start_min INTEGER DEFAULT -1, end_min INTEGER DEFAULT -1, category_id INTEGER NOT NULL, priority INTEGER DEFAULT 0);
        CREATE TABLE IF NOT EXISTS project(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, color TEXT NOT NULL, sync_calendar INTEGER DEFAULT 0, min_minutes INTEGER DEFAULT 15);
        CREATE TABLE IF NOT EXISTS project_rule(id INTEGER PRIMARY KEY AUTOINCREMENT, project_id INTEGER NOT NULL, match_type TEXT NOT NULL, match_value TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS session(id INTEGER PRIMARY KEY AUTOINCREMENT, start_ts INTEGER NOT NULL, end_ts INTEGER NOT NULL,
            source TEXT NOT NULL DEFAULT 'auto', bundle_id TEXT, app_name TEXT, domain TEXT, category_id INTEGER NOT NULL DEFAULT 5,
            project_id INTEGER, label TEXT, via_media INTEGER DEFAULT 0, edited INTEGER DEFAULT 0);
        CREATE INDEX IF NOT EXISTS idx_session_start ON session(start_ts);
        CREATE INDEX IF NOT EXISTS idx_session_end ON session(end_ts);
        CREATE INDEX IF NOT EXISTS idx_session_bundle ON session(bundle_id, start_ts);
        CREATE INDEX IF NOT EXISTS idx_session_domain ON session(domain, start_ts);
        CREATE TABLE IF NOT EXISTS calendar_sync(id INTEGER PRIMARY KEY AUTOINCREMENT, project_id INTEGER NOT NULL, start_ts INTEGER NOT NULL, end_ts INTEGER NOT NULL, ek_event_id TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS switch_stat(hour_ts INTEGER PRIMARY KEY, count INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS day_type(date TEXT PRIMARY KEY, type TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS edit_log(id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER NOT NULL, op TEXT NOT NULL, span_start INTEGER NOT NULL, span_end INTEGER NOT NULL, before_json TEXT NOT NULL);
        """)
        for (i, c) in Defaults.categories.enumerated() {
            try run("INSERT OR IGNORE INTO category(id,name,color,sort) VALUES(?,?,?,?)", [c.id, c.name, c.color, i])
        }
        if meta("device_id") == nil {
            setMeta("device_id", UUID().uuidString)
            setMeta("device_name", Host.current().localizedName ?? "My Mac")
        }
        try exec("PRAGMA user_version=1")
    }

    // MARK: - Meta

    public func meta(_ key: String) -> String? {
        query("SELECT value FROM meta WHERE key=?", [key]) { $0.text(0) }.first ?? nil
    }

    public func setMeta(_ key: String, _ value: String) {
        _ = try? run("INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [key, value])
    }

    public var deviceId: String { meta("device_id") ?? "unknown" }
    public var deviceName: String { meta("device_name") ?? "Unnamed device" }

    

    public func categories() -> [Category] {
        query("SELECT id,name,color FROM category ORDER BY sort,id") { Category(id: $0.int(0), name: $0.text(1) ?? "", color: $0.text(2) ?? "#999999") }
    }

    public func upsertCategory(_ c: Category) throws {
        try run("INSERT INTO category(id,name,color,sort) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name, color=excluded.color",
                [c.id, c.name, c.color, c.id])
    }

    public func addCategory(name: String, color: String) throws {
        let next = (query("SELECT MAX(id) FROM category") { $0.int(0) }.first ?? 5) + 1
        try upsertCategory(Category(id: next, name: name, color: color))
    }

    public func deleteCategory(_ id: Int64) throws {
        guard id > 5 else { return }
        try run("UPDATE session SET category_id=5 WHERE category_id=?", [id])
        try run("UPDATE app SET category_id=5 WHERE category_id=?", [id])
        try run("UPDATE domain SET category_id=5 WHERE category_id=?", [id])
        try run("DELETE FROM category_rule WHERE category_id=?", [id])
        try run("DELETE FROM category WHERE id=?", [id])
    }

    public func apps() -> [AppRow] {
        query("SELECT bundle_id,name,category_id,excluded FROM app ORDER BY name COLLATE NOCASE") {
            AppRow(bundleId: $0.text(0) ?? "", name: $0.text(1) ?? "", categoryId: $0.int(2), excluded: $0.int(3) != 0)
        }
    }

    public func registerApp(bundleId: String, name: String, defaultCategory: Int64) {
        _ = try? run("INSERT OR IGNORE INTO app(bundle_id,name,category_id,excluded) VALUES(?,?,?,0)", [bundleId, name, defaultCategory])
    }

    public func setApp(bundleId: String, categoryId: Int64? = nil, excluded: Bool? = nil) throws {
        if let c = categoryId { try run("UPDATE app SET category_id=? WHERE bundle_id=?", [c, bundleId]) }
        if let e = excluded { try run("UPDATE app SET excluded=? WHERE bundle_id=?", [e, bundleId]) }
    }

    public func domains() -> [DomainRow] {
        query("SELECT host,category_id,excluded FROM domain ORDER BY host") {
            DomainRow(host: $0.text(0) ?? "", categoryId: $0.int(1), excluded: $0.int(2) != 0)
        }
    }

    public func setDomain(host: String, categoryId: Int64, excluded: Bool = false) throws {
        try run("INSERT INTO domain(host,category_id,excluded) VALUES(?,?,?) ON CONFLICT(host) DO UPDATE SET category_id=excluded.category_id, excluded=excluded.excluded",
                [host, categoryId, excluded])
    }

    public func deleteDomain(host: String) throws { try run("DELETE FROM domain WHERE host=?", [host]) }

    

    public func categoryRules() -> [CategoryRule] {
        query("SELECT id,match_type,match_value,weekday_mask,start_min,end_min,category_id,priority FROM category_rule ORDER BY priority DESC,id") {
            CategoryRule(id: $0.int(0), matchType: $0.text(1) ?? "app", matchValue: $0.text(2) ?? "",
                         weekdayMask: Int($0.int(3)), startMin: Int($0.int(4)), endMin: Int($0.int(5)),
                         categoryId: $0.int(6), priority: Int($0.int(7)))
        }
    }

    public func addCategoryRule(_ r: CategoryRule) throws {
        try run("INSERT INTO category_rule(match_type,match_value,weekday_mask,start_min,end_min,category_id,priority) VALUES(?,?,?,?,?,?,?)",
                [r.matchType, r.matchValue, r.weekdayMask, r.startMin, r.endMin, r.categoryId, r.priority])
    }

    public func deleteCategoryRule(_ id: Int64) throws { try run("DELETE FROM category_rule WHERE id=?", [id]) }

    

    public func projects() -> [Project] {
        query("SELECT id,name,color,sync_calendar,min_minutes FROM project ORDER BY id") {
            Project(id: $0.int(0), name: $0.text(1) ?? "", color: $0.text(2) ?? "#888888", syncCalendar: $0.int(3) != 0, minMinutes: Int($0.int(4)))
        }
    }

    public func addProject(name: String, color: String) throws {
        try run("INSERT INTO project(name,color,sync_calendar,min_minutes) VALUES(?,?,1,15)", [name, color])
    }

    public func updateProject(_ p: Project) throws {
        try run("UPDATE project SET name=?, color=?, sync_calendar=?, min_minutes=? WHERE id=?", [p.name, p.color, p.syncCalendar, p.minMinutes, p.id])
    }

    public func deleteProject(_ id: Int64) throws {
        try run("UPDATE session SET project_id=NULL WHERE project_id=?", [id])
        try run("DELETE FROM project_rule WHERE project_id=?", [id])
        try run("DELETE FROM project WHERE id=?", [id])
    }

    public func projectRules() -> [ProjectRule] {
        query("SELECT id,project_id,match_type,match_value FROM project_rule ORDER BY id") {
            ProjectRule(id: $0.int(0), projectId: $0.int(1), matchType: $0.text(2) ?? "app", matchValue: $0.text(3) ?? "")
        }
    }

    public func addProjectRule(projectId: Int64, matchType: String, matchValue: String) throws {
        try run("INSERT INTO project_rule(project_id,match_type,match_value) VALUES(?,?,?)", [projectId, matchType, matchValue])
    }

    public func deleteProjectRule(_ id: Int64) throws { try run("DELETE FROM project_rule WHERE id=?", [id]) }

    

    static let sessionCols = "id,start_ts,end_ts,source,bundle_id,app_name,domain,category_id,project_id,label,via_media,edited"

    static func mapSession(_ r: Row) -> Session {
        Session(id: r.int(0), startTs: r.int(1), endTs: r.int(2), source: r.text(3) ?? "auto",
                bundleId: r.text(4), appName: r.text(5), domain: r.text(6), categoryId: r.int(7),
                projectId: r.optInt(8), label: r.text(9), viaMedia: r.int(10) != 0, edited: r.int(11) != 0)
    }

    
    public func sessions(from: Int64, to: Int64) -> [Session] {
        query("SELECT \(Database.sessionCols) FROM session WHERE end_ts>? AND start_ts<? ORDER BY start_ts", [from, to], Database.mapSession)
    }

    public func session(id: Int64) -> Session? {
        query("SELECT \(Database.sessionCols) FROM session WHERE id=?", [id], Database.mapSession).first
    }

    @discardableResult
    public func insertSession(_ s: Session, keepId: Bool = false) throws -> Int64 {
        if keepId {
            try run("INSERT INTO session(id,start_ts,end_ts,source,bundle_id,app_name,domain,category_id,project_id,label,via_media,edited) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
                    [s.id, s.startTs, s.endTs, s.source, s.bundleId, s.appName, s.domain, s.categoryId, s.projectId, s.label, s.viaMedia, s.edited])
            return s.id
        }
        try run("INSERT INTO session(start_ts,end_ts,source,bundle_id,app_name,domain,category_id,project_id,label,via_media,edited) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                [s.startTs, s.endTs, s.source, s.bundleId, s.appName, s.domain, s.categoryId, s.projectId, s.label, s.viaMedia, s.edited])
        return lastInsertId
    }

    public func updateEnd(id: Int64, end: Int64) {
        _ = try? run("UPDATE session SET end_ts=? WHERE id=?", [end, id])
    }

    public func updateViaMedia(id: Int64, value: Bool) {
        _ = try? run("UPDATE session SET via_media=? WHERE id=?", [value, id])
    }

    public func deleteSession(id: Int64) { _ = try? run("DELETE FROM session WHERE id=?", [id]) }

    public func updateSessionFields(_ s: Session) throws {
        try run("UPDATE session SET start_ts=?,end_ts=?,source=?,bundle_id=?,app_name=?,domain=?,category_id=?,project_id=?,label=?,via_media=?,edited=? WHERE id=?",
                [s.startTs, s.endTs, s.source, s.bundleId, s.appName, s.domain, s.categoryId, s.projectId, s.label, s.viaMedia, s.edited, s.id])
    }

    public func latestSession() -> Session? {
        query("SELECT \(Database.sessionCols) FROM session ORDER BY end_ts DESC LIMIT 1", [], Database.mapSession).first
    }

    public func earliestTs() -> Int64? {
        query("SELECT MIN(start_ts) FROM session") { $0.optInt(0) }.first ?? nil
    }

    
    public func reclassifyAll(using c: Classifier, calendar: Calendar = .current) throws {
        let all = query("SELECT \(Database.sessionCols) FROM session WHERE edited=0 AND source='auto'", [], Database.mapSession)
        try transaction {
            for s in all {
                let cat = c.classify(bundleId: s.bundleId, domain: s.domain, date: Date(timeIntervalSince1970: Double(s.startTs)), calendar: calendar)
                let pid = c.projectId(bundleId: s.bundleId, domain: s.domain)
                if cat != s.categoryId || pid != s.projectId {
                    try run("UPDATE session SET category_id=?, project_id=? WHERE id=?", [cat, pid, s.id])
                }
            }
        }
    }

    

    public func incrementSwitch(at date: Date) {
        let hour = Int64(date.timeIntervalSince1970) / 3600 * 3600
        _ = try? run("INSERT INTO switch_stat(hour_ts,count) VALUES(?,1) ON CONFLICT(hour_ts) DO UPDATE SET count=count+1", [hour])
    }

    public func switchStats(from: Int64, to: Int64) -> [(hour: Int64, count: Int)] {
        query("SELECT hour_ts,count FROM switch_stat WHERE hour_ts>=? AND hour_ts<? ORDER BY hour_ts", [from, to]) { ($0.int(0), Int($0.int(1))) }
    }

    public func dayTypes() -> [String: String] {
        var d: [String: String] = [:]
        for (k, v) in query("SELECT date,type FROM day_type", [], { ($0.text(0) ?? "", $0.text(1) ?? "") }) { d[k] = v }
        return d
    }

    public func setDayType(date: String, type: String?) throws {
        if let t = type {
            try run("INSERT INTO day_type(date,type) VALUES(?,?) ON CONFLICT(date) DO UPDATE SET type=excluded.type", [date, t])
        } else {
            try run("DELETE FROM day_type WHERE date=?", [date])
        }
    }

    

    public func calendarSyncRows() -> [CalendarSyncRow] {
        query("SELECT id,project_id,start_ts,end_ts,ek_event_id FROM calendar_sync") {
            CalendarSyncRow(id: $0.int(0), projectId: $0.int(1), startTs: $0.int(2), endTs: $0.int(3), eventId: $0.text(4) ?? "")
        }
    }

    public func addCalendarSync(projectId: Int64, start: Int64, end: Int64, eventId: String) {
        _ = try? run("INSERT INTO calendar_sync(project_id,start_ts,end_ts,ek_event_id) VALUES(?,?,?,?)", [projectId, start, end, eventId])
    }

    public func updateCalendarSync(id: Int64, end: Int64) {
        _ = try? run("UPDATE calendar_sync SET end_ts=? WHERE id=?", [end, id])
    }

    public func deleteCalendarSync(id: Int64) { _ = try? run("DELETE FROM calendar_sync WHERE id=?", [id]) }

    

    
    public func backup(to destPath: String) throws {
        try? FileManager.default.removeItem(atPath: destPath)
        var dest: OpaquePointer?
        guard sqlite3_open(destPath, &dest) == SQLITE_OK else { throw DBError(message: "Could not create backup file") }
        defer { sqlite3_close(dest) }
        guard let b = sqlite3_backup_init(dest, "main", handle, "main") else {
            throw DBError(message: String(cString: sqlite3_errmsg(dest)))
        }
        sqlite3_backup_step(b, -1)
        sqlite3_backup_finish(b)
        sqlite3_exec(dest, "PRAGMA journal_mode=DELETE", nil, nil, nil)
    }

    
    public func restore(from srcPath: String) throws {
        var src: OpaquePointer?
        guard sqlite3_open_v2(srcPath, &src, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw DBError(message: "Could not read snapshot") }
        defer { sqlite3_close(src) }
        guard let b = sqlite3_backup_init(handle, "main", src, "main") else {
            throw DBError(message: String(cString: sqlite3_errmsg(handle)))
        }
        sqlite3_backup_step(b, -1)
        let rc = sqlite3_backup_finish(b)
        guard rc == SQLITE_OK else { throw DBError(message: "Restore failed: (\(rc))") }
    }

    public func quickCheck() -> Bool {
        (query("PRAGMA quick_check") { $0.text(0) }.first ?? nil) == "ok"
    }
}
