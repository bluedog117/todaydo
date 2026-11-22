import Foundation


public struct DayCalendar {
    public var dayStartHour: Int
    public var calendar: Calendar

    public init(dayStartHour: Int = 4, calendar: Calendar = .current) {
        self.dayStartHour = dayStartHour
        var c = calendar
        c.firstWeekday = 2   
        self.calendar = c
    }

    
    public func dayStart(containing date: Date) -> Date {
        let shifted = date.addingTimeInterval(-Double(dayStartHour) * 3600)
        let sod = calendar.startOfDay(for: shifted)
        return calendar.date(byAdding: .hour, value: dayStartHour, to: sod) ?? sod
    }

    public func nextDayStart(after dayStart: Date) -> Date {
        let sod = calendar.startOfDay(for: dayStart.addingTimeInterval(-Double(dayStartHour) * 3600))
        let next = calendar.date(byAdding: .day, value: 1, to: sod) ?? sod
        return calendar.date(byAdding: .hour, value: dayStartHour, to: next) ?? next
    }

    public func addDays(_ n: Int, to dayStart: Date) -> Date {
        let sod = calendar.startOfDay(for: dayStart.addingTimeInterval(-Double(dayStartHour) * 3600))
        let d = calendar.date(byAdding: .day, value: n, to: sod) ?? sod
        return calendar.date(byAdding: .hour, value: dayStartHour, to: d) ?? d
    }

    public func dayRange(containing date: Date) -> (start: Date, end: Date) {
        let s = dayStart(containing: date)
        return (s, nextDayStart(after: s))
    }

    
    public func dayKey(_ dayStart: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: dayStart.addingTimeInterval(-Double(dayStartHour) * 3600))
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    
    public func isoWeekday(_ dayStart: Date) -> Int {
        let wd = calendar.component(.weekday, from: dayStart.addingTimeInterval(-Double(dayStartHour) * 3600))
        return wd == 1 ? 7 : wd - 1
    }

    
    public func isWeekend(_ dayStart: Date, dayTypes: [String: String] = [:]) -> Bool {
        if let t = dayTypes[dayKey(dayStart)] { return t == "weekend" }
        return isoWeekday(dayStart) >= 6
    }

    public func weekStart(containing date: Date) -> Date {
        let d = dayStart(containing: date)
        return addDays(-(isoWeekday(d) - 1), to: d)
    }

    public func monthStart(containing date: Date) -> Date {
        let d = dayStart(containing: date)
        let c = calendar.dateComponents([.year, .month], from: d.addingTimeInterval(-Double(dayStartHour) * 3600))
        let first = calendar.date(from: c) ?? d
        return calendar.date(byAdding: .hour, value: dayStartHour, to: first) ?? first
    }

    public func addMonths(_ n: Int, to monthStart: Date) -> Date {
        let sod = calendar.startOfDay(for: monthStart.addingTimeInterval(-Double(dayStartHour) * 3600))
        let d = calendar.date(byAdding: .month, value: n, to: sod) ?? sod
        return calendar.date(byAdding: .hour, value: dayStartHour, to: d) ?? d
    }
}

public struct RankItem: Identifiable, Hashable {
    public var id: String { key }
    public var key: String
    public var name: String
    public var bundleId: String?
    public var domain: String?
    public var categoryId: Int64
    public var seconds: Int64
}

public struct FocusSegment: Hashable {
    public var start: Int64
    public var end: Int64
    public var categoryId: Int64
    public var duration: Int64 { end - start }
}

public enum Stats {
    public static func ts(_ d: Date) -> Int64 { Int64(d.timeIntervalSince1970) }

    
    public static func clipped(_ sessions: [Session], from: Int64, to: Int64) -> [Session] {
        sessions.compactMap { s in
            let a = max(s.startTs, from), b = min(s.endTs, to)
            guard b > a else { return nil }
            var c = s; c.startTs = a; c.endTs = b
            return c
        }
    }

    public static func total(_ sessions: [Session]) -> Int64 { sessions.reduce(0) { $0 + $1.duration } }

    public static func byCategory(_ sessions: [Session]) -> [Int64: Int64] {
        var d: [Int64: Int64] = [:]
        for s in sessions { d[s.categoryId, default: 0] += s.duration }
        return d
    }

    public static func rank(_ sessions: [Session]) -> [RankItem] {
        struct Acc { var name: String; var bundle: String?; var domain: String?; var cats: [Int64: Int64] = [:]; var secs: Int64 = 0 }
        var m: [String: Acc] = [:]
        for s in sessions {
            var a = m[s.key] ?? Acc(name: s.displayName, bundle: s.bundleId, domain: s.domain)
            a.secs += s.duration
            a.cats[s.categoryId, default: 0] += s.duration
            m[s.key] = a
        }
        return m.map { k, a in
            RankItem(key: k, name: a.name, bundleId: a.bundle, domain: a.domain,
                     categoryId: a.cats.max { $0.value < $1.value }?.key ?? 5, seconds: a.secs)
        }.sorted { $0.seconds > $1.seconds }
    }

    
    public static func perDay(_ sessions: [Session], days: [Date], dc: DayCalendar) -> [[Int64: Int64]] {
        days.map { d in
            let from = ts(d), to = ts(dc.nextDayStart(after: d))
            return byCategory(clipped(sessions, from: from, to: to))
        }
    }

    
    public static func focusSegments(_ sessions: [Session], gap: Int64 = 120) -> [FocusSegment] {
        var out: [FocusSegment] = []
        for s in sessions.sorted(by: { $0.startTs < $1.startTs }) where s.duration > 0 {
            if var last = out.last, last.categoryId == s.categoryId, s.startTs - last.end <= gap {
                last.end = max(last.end, s.endTs)
                out[out.count - 1] = last
            } else {
                out.append(FocusSegment(start: s.startTs, end: s.endTs, categoryId: s.categoryId))
            }
        }
        return out
    }

    
    public static func fragmentation(_ sessions: [Session], threshold: Int64 = 120) -> Double {
        let autos = sessions.filter { !$0.isAway }
        guard !autos.isEmpty else { return 0 }
        return Double(autos.filter { $0.duration < threshold }.count) / Double(autos.count)
    }

    public static func formatDuration(_ seconds: Int64, compact: Bool = false) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60
        if h > 0 { return compact ? "\(h)h\(m)m" : "\(h) hours \(m) min" }
        if m > 0 { return compact ? "\(m)m" : "\(m) min" }
        return compact ? "\(s)s" : "\(s) sec"
    }
}
