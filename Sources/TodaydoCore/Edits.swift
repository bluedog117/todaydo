import Foundation

public enum EditAction {
    case delete
    case setCategory(Int64)
    case setProject(Int64?)
    case setLabel(String?)
}

extension Database {
    

    
    private func logged(op: String, lo: Int64, hi: Int64, _ body: () throws -> Void) throws {
        let before = sessions(from: lo, to: hi).filter { $0.startTs >= lo && $0.endTs <= hi }
        let json = (try? JSONEncoder().encode(before)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        try transaction {
            try body()
            try run("INSERT INTO edit_log(ts,op,span_start,span_end,before_json) VALUES(?,?,?,?,?)",
                    [Int64(Date().timeIntervalSince1970), op, lo, hi, json])
            try run("DELETE FROM edit_log WHERE id NOT IN (SELECT id FROM edit_log ORDER BY id DESC LIMIT 50)")
        }
    }

    private func splitRow(at ts: Int64) throws {
        let hit = query("SELECT \(Database.sessionCols) FROM session WHERE start_ts<? AND end_ts>?", [ts, ts], Database.mapSession)
        for s in hit {
            try run("UPDATE session SET end_ts=? WHERE id=?", [ts, s.id])
            var n = s
            n.startTs = ts
            try insertSession(n)
        }
    }

    
    public func applyEdit(from: Int64, to: Int64, action: EditAction) throws {
        let affected = sessions(from: from, to: to)
        guard !affected.isEmpty, to > from else { return }
        let lo = min(from, affected.map(\.startTs).min() ?? from)
        let hi = max(to, affected.map(\.endTs).max() ?? to)
        let opName: String
        switch action {
        case .delete: opName = "Delete"
        case .setCategory: opName = "Change category"
        case .setProject: opName = "Assign project"
        case .setLabel: opName = "Add label"
        }
        try logged(op: opName, lo: lo, hi: hi) {
            try splitRow(at: from)
            try splitRow(at: to)
            let inside = sessions(from: from, to: to).filter { $0.startTs >= from && $0.endTs <= to }
            for s in inside {
                switch action {
                case .delete:
                    try run("DELETE FROM session WHERE id=?", [s.id])
                case .setCategory(let c):
                    try run("UPDATE session SET category_id=?, edited=1 WHERE id=?", [c, s.id])
                case .setProject(let p):
                    try run("UPDATE session SET project_id=?, edited=1 WHERE id=?", [p, s.id])
                case .setLabel(let l):
                    try run("UPDATE session SET label=?, edited=1 WHERE id=?", [l, s.id])
                }
            }
        }
    }

    
    public func splitSession(at ts: Int64) throws {
        let hit = query("SELECT \(Database.sessionCols) FROM session WHERE start_ts<? AND end_ts>?", [ts, ts], Database.mapSession)
        guard let s = hit.first else { return }
        try logged(op: "Split", lo: s.startTs, hi: s.endTs) { try splitRow(at: ts) }
    }

    
    @discardableResult
    public func addManualSession(_ s: Session) throws -> Int64 {
        var newId: Int64 = 0
        try logged(op: "Add activity", lo: s.startTs, hi: s.endTs) { newId = try insertSession(s) }
        return newId
    }

    public var canUndo: Bool { (query("SELECT COUNT(*) FROM edit_log") { $0.int(0) }.first ?? 0) > 0 }

    public var lastEditName: String? {
        query("SELECT op FROM edit_log ORDER BY id DESC LIMIT 1") { $0.text(0) }.first ?? nil
    }

    
    @discardableResult
    public func undoLastEdit() throws -> String? {
        let logs = query("SELECT id,op,span_start,span_end,before_json FROM edit_log ORDER BY id DESC LIMIT 1") {
            ($0.int(0), $0.text(1) ?? "", $0.int(2), $0.int(3), $0.text(4) ?? "[]")
        }
        guard let log = logs.first else { return nil }
        let rows = (try? JSONDecoder().decode([Session].self, from: Data(log.4.utf8))) ?? []
        try transaction {
            try run("DELETE FROM session WHERE start_ts>=? AND end_ts<=?", [log.2, log.3])
            for r in rows { try insertSession(r, keepId: true) }
            try run("DELETE FROM edit_log WHERE id=?", [log.0])
        }
        return log.1
    }
}
