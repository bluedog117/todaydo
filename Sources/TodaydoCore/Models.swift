import Foundation


public struct Session: Identifiable, Hashable, Codable {
    public var id: Int64
    public var startTs: Int64
    public var endTs: Int64
    
    public var source: String
    public var bundleId: String?
    public var appName: String?
    public var domain: String?
    public var categoryId: Int64
    public var projectId: Int64?
    public var label: String?
    public var viaMedia: Bool
    public var edited: Bool

    public init(id: Int64 = 0, startTs: Int64, endTs: Int64, source: String = "auto",
                bundleId: String? = nil, appName: String? = nil, domain: String? = nil,
                categoryId: Int64 = 5, projectId: Int64? = nil, label: String? = nil,
                viaMedia: Bool = false, edited: Bool = false) {
        self.id = id; self.startTs = startTs; self.endTs = endTs; self.source = source
        self.bundleId = bundleId; self.appName = appName; self.domain = domain
        self.categoryId = categoryId; self.projectId = projectId; self.label = label
        self.viaMedia = viaMedia; self.edited = edited
    }

    public var duration: Int64 { max(0, endTs - startTs) }
    public var isAway: Bool { source != "auto" }

    
    public var key: String {
        if let d = domain, !d.isEmpty { return "d:" + d }
        if let b = bundleId, !b.isEmpty { return "a:" + b }
        return "l:" + (label ?? "Offline activity")
    }

    public var displayName: String {
        if let d = domain, !d.isEmpty { return d }
        if let n = appName, !n.isEmpty { return n }
        return label ?? "Offline activity"
    }
}

public struct Category: Identifiable, Hashable {
    public var id: Int64
    public var name: String
    public var color: String
    public init(id: Int64, name: String, color: String) {
        self.id = id; self.name = name; self.color = color
    }
}

public struct Project: Identifiable, Hashable {
    public var id: Int64
    public var name: String
    public var color: String
    public var syncCalendar: Bool
    public var minMinutes: Int
    public init(id: Int64, name: String, color: String, syncCalendar: Bool, minMinutes: Int) {
        self.id = id; self.name = name; self.color = color
        self.syncCalendar = syncCalendar; self.minMinutes = minMinutes
    }
}

public struct ProjectRule: Identifiable, Hashable {
    public var id: Int64
    public var projectId: Int64
    public var matchType: String // app / domain
    public var matchValue: String
}

public struct CategoryRule: Identifiable, Hashable {
    public var id: Int64
    public var matchType: String // app / domain
    public var matchValue: String
    
    public var weekdayMask: Int
    
    public var startMin: Int
    public var endMin: Int
    public var categoryId: Int64
    public var priority: Int
    public init(id: Int64 = 0, matchType: String, matchValue: String, weekdayMask: Int = 0,
                startMin: Int = -1, endMin: Int = -1, categoryId: Int64, priority: Int = 0) {
        self.id = id; self.matchType = matchType; self.matchValue = matchValue
        self.weekdayMask = weekdayMask; self.startMin = startMin; self.endMin = endMin
        self.categoryId = categoryId; self.priority = priority
    }
}

public struct AppRow: Hashable {
    public var bundleId: String
    public var name: String
    public var categoryId: Int64
    public var excluded: Bool
}

public struct DomainRow: Hashable {
    public var host: String
    public var categoryId: Int64
    public var excluded: Bool
}

public struct CalendarSyncRow: Hashable {
    public var id: Int64
    public var projectId: Int64
    public var startTs: Int64
    public var endTs: Int64
    public var eventId: String
}
