import Foundation


public final class Classifier {
    private var appCat: [String: Int64] = [:]
    private var domainCat: [String: Int64] = [:]
    private var rules: [CategoryRule] = []
    private var excludedApps: Set<String> = []
    private var excludedDomains: Set<String> = []
    private var projectRules: [ProjectRule] = []

    public init(db: Database) { reload(db) }

    public func reload(_ db: Database) {
        appCat = [:]; excludedApps = []
        for a in db.apps() {
            appCat[a.bundleId] = a.categoryId
            if a.excluded { excludedApps.insert(a.bundleId) }
        }
        domainCat = [:]; excludedDomains = []
        for d in db.domains() {
            domainCat[d.host] = d.categoryId
            if d.excluded { excludedDomains.insert(d.host) }
        }
        rules = db.categoryRules()
        projectRules = db.projectRules()
    }

    public static func defaultCategory(bundleId: String) -> Int64 {
        Defaults.appCategories[bundleId] ?? Defaults.other
    }

    
    public static func hostCandidates(_ host: String) -> [String] {
        var parts = host.lowercased().split(separator: ".").map(String.init)
        var out: [String] = []
        while parts.count >= 2 {
            out.append(parts.joined(separator: "."))
            parts.removeFirst()
        }
        if out.isEmpty { out = [host.lowercased()] }
        return out
    }

    public func isExcluded(bundleId: String?, domain: String?) -> Bool {
        if let b = bundleId, excludedApps.contains(b) { return true }
        if let d = domain {
            for h in Classifier.hostCandidates(d) where excludedDomains.contains(h) { return true }
        }
        return false
    }

    public func classify(bundleId: String?, domain: String?, date: Date, calendar: Calendar = .current) -> Int64 {
        let comps = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let weekdayBit = 1 << ((comps.weekday ?? 1) - 1)
        let minute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)

        for r in rules {
            let hit: Bool
            if r.matchType == "domain" {
                hit = domain.map { Classifier.hostCandidates($0).contains(r.matchValue.lowercased()) } ?? false
            } else {
                hit = (bundleId == r.matchValue)
            }
            guard hit else { continue }
            if r.weekdayMask != 0 && (r.weekdayMask & weekdayBit) == 0 { continue }
            if r.startMin >= 0 && r.endMin >= 0 {
                let inRange = r.startMin <= r.endMin
                    ? (minute >= r.startMin && minute < r.endMin)
                    : (minute >= r.startMin || minute < r.endMin)
                if !inRange { continue }
            }
            return r.categoryId
        }
        if let d = domain {
            for h in Classifier.hostCandidates(d) {
                if let c = domainCat[h] { return c }
            }
            for h in Classifier.hostCandidates(d) {
                if let c = Defaults.domainCategories[h] { return c }
            }
        }
        if let b = bundleId, let c = appCat[b] { return c }
        if let b = bundleId { return Classifier.defaultCategory(bundleId: b) }
        return Defaults.other
    }

    public func projectId(bundleId: String?, domain: String?) -> Int64? {
        for r in projectRules {
            if r.matchType == "domain" {
                if let d = domain, Classifier.hostCandidates(d).contains(r.matchValue.lowercased()) { return r.projectId }
            } else if let b = bundleId, b == r.matchValue {
                return r.projectId
            }
        }
        return nil
    }
}
