import Foundation
import EventKit
import TodaydoCore



@MainActor
final class CalendarSync: ObservableObject {
    @Published var statusText = "Disabled"
    @Published var authorized = false

    private let store = EKEventStore()
    unowned let model: AppModel
    private let calKey = "todaydo.calendarId"

    init(model: AppModel) { self.model = model }

    func requestAccess() async -> Bool {
        do {
            let ok = try await store.requestFullAccessToEvents()
            authorized = ok
            statusText = ok ? "Authorized" : "Not authorized (Go to System Settings → Privacy & Security → Calendar to allow access)"
            return ok
        } catch {
            statusText = "Permission request failed: \(error.localizedDescription)"
            return false
        }
    }

    private func todaydoCalendar() -> EKCalendar? {
        if let id = UserDefaults.standard.string(forKey: calKey), let c = store.calendar(withIdentifier: id) { return c }
        if let c = store.calendars(for: .event).first(where: { $0.title == "todaydo" }) {
            UserDefaults.standard.set(c.calendarIdentifier, forKey: calKey)
            return c
        }
        let c = EKCalendar(for: .event, eventStore: store)
        c.title = "todaydo"
        c.cgColor = CGColor(red: 0.31, green: 0.49, blue: 1, alpha: 1)
        let sources = [store.defaultCalendarForNewEvents?.source].compactMap { $0 }
            + store.sources.filter { $0.sourceType == .local }
        for src in sources {
            c.source = src
            if (try? store.saveCalendar(c, commit: true)) != nil {
                UserDefaults.standard.set(c.calendarIdentifier, forKey: calKey)
                return c
            }
        }
        return nil
    }

    struct Block { var projectId: Int64; var start: Int64; var end: Int64 }

    func sync() {
        guard model.settings.calendarSync else { return }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            statusText = "Not authorized"
            return
        }
        guard let cal = todaydoCalendar() else { statusText = "Could not create “todaydo”Calendar"; return }
        let db = model.db
        let now = Date()
        let from = model.dc.addDays(-2, to: model.dc.dayStart(containing: now)).ts
        let projects = db.projects().filter(\.syncCalendar)
        let byId = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        let sessions = db.sessions(from: from, to: now.ts).filter { $0.projectId != nil && byId[$0.projectId!] != nil }

        
        var blocks: [Block] = []
        for pid in Set(sessions.compactMap(\.projectId)) {
            var cur: Block?
            for s in sessions.filter({ $0.projectId == pid }).sorted(by: { $0.startTs < $1.startTs }) {
                if var c = cur, s.startTs - c.end < 600 { c.end = max(c.end, s.endTs); cur = c }
                else { if let c = cur { blocks.append(c) }; cur = Block(projectId: pid, start: s.startTs, end: s.endTs) }
            }
            if let c = cur { blocks.append(c) }
        }
        
        let ready = blocks.filter { b in
            guard let p = byId[b.projectId] else { return false }
            return b.end <= now.ts - 600 && b.end - b.start >= Int64(p.minMinutes * 60)
        }

        var existing = db.calendarSyncRows().filter { $0.startTs >= from }
        var created = 0
        for b in ready {
            if let i = existing.firstIndex(where: { $0.projectId == b.projectId && abs($0.startTs - b.start) < 60 }) {
                let row = existing.remove(at: i)
                if row.endTs != b.end, let ev = store.event(withIdentifier: row.eventId) {
                    ev.endDate = Date(timeIntervalSince1970: Double(b.end))
                    try? store.save(ev, span: .thisEvent, commit: false)
                    db.updateCalendarSync(id: row.id, end: b.end)
                }
            } else {
                let ev = EKEvent(eventStore: store)
                ev.calendar = cal
                ev.title = byId[b.projectId]?.name ?? "Project"
                ev.notes = "Recorded by “todaydo”Automatic"
                ev.startDate = Date(timeIntervalSince1970: Double(b.start))
                ev.endDate = Date(timeIntervalSince1970: Double(b.end))
                if (try? store.save(ev, span: .thisEvent, commit: false)) != nil, let id = ev.eventIdentifier {
                    db.addCalendarSync(projectId: b.projectId, start: b.start, end: b.end, eventId: id)
                    created += 1
                }
            }
        }
        
        for row in existing {
            if let ev = store.event(withIdentifier: row.eventId) { try? store.remove(ev, span: .thisEvent, commit: false) }
            db.deleteCalendarSync(id: row.id)
        }
        try? store.commit()
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "HH:mm"
        statusText = "Last synced \(f.string(from: now)), saved \(created) records"
    }

    
    func clearAll() {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        for row in model.db.calendarSyncRows() {
            if let ev = store.event(withIdentifier: row.eventId) { try? store.remove(ev, span: .thisEvent, commit: false) }
            model.db.deleteCalendarSync(id: row.id)
        }
        try? store.commit()
        statusText = "Removed"
    }
}
