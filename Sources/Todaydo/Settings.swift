import Foundation
import SwiftUI



struct StandRule: Codable, Equatable {
    var enabled = true
    var intervalMin = 45
    var restMin = 5
}

struct FocusRule: Codable, Equatable {
    var enabled = false
    var categoryIds: [Int64] = [1]
    var triggerMin = 2
    var workMin = 25
    var restMin = 5
    var longRestMin = 15
    var longRestEvery = 4
    var soundName = "Glass"
    var distractIds: [Int64] = [3]

    static let systemSounds: [(id: String, label: String)] = [
        ("Glass", "Glass (Clear glass)"),
        ("Ping", "Ping (Bell)"),
        ("Hero", "Hero (Hero)"),
        ("Purr", "Purr (Soft)"),
        ("Pop", "Pop (Pop)"),
        ("Basso", "Basso (Deep)"),
        ("Blow", "Blow (Blow)"),
        ("Bottle", "Bottle (Bottle)"),
        ("Frog", "Frog (Frog)"),
        ("Funk", "Funk (Rhythm)"),
        ("Morse", "Morse (Morse)"),
        ("Sosumi", "Sosumi (Classic)"),
        ("Submarine", "Submarine (Submarine)"),
        ("Tink", "Tink (Tink)"),
        ("__beep__", "System default sound"),
        ("__mute__", "Mute")
    ]
}

struct LimitRule: Codable, Equatable, Identifiable {
    var id = UUID()
    var kind = "category" // category / app / domain
    var key = "3"                  
    var name = "Entertainment"
    var minutes = 120
}

struct GoalRule: Codable, Equatable, Identifiable {
    var id = UUID()
    var categoryId: Int64 = 2
    var name = "Learning"
    var minutes = 120
    var atHour = 18
}

struct AwareRule: Codable, Equatable {
    var enabled = false
    var everyMin = 30
    var floating = true
    var appEveryMin = 0            
}

struct SummaryRule: Codable, Equatable {
    var dailyEnabled = true
    var dailyHour = 22
    var weeklyEnabled = true
    var weeklyHour = 9
}

struct Settings: Codable, Equatable {
    var dayStartHour = 4
    var idleMinutes = 3
    var awayEnabled = true
    var awayMinMinutes = 10
    var awayMaxHours = 4
    var browserDomains = true
    var snapshotKeep = 7
    var icloudBackup = false
    var calendarSync = false
    var launchAtLogin = false
    var reminderStartHour = 8
    var reminderEndHour = 23
    var stand = StandRule()
    var focus = FocusRule()
    var limits: [LimitRule] = []
    var goals: [GoalRule] = []
    var aware = AwareRule()
    var summary = SummaryRule()
    var awayTags = ["Meeting", "Reading", "Exercise", "Meal", "Break"]

    static let key = "todaydo.settings.v1"

    static func load() -> Settings {
        guard let d = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(Settings.self, from: d) else { return Settings() }
        return s
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Settings.key) }
    }
}



extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255, opacity: 1)
    }
}

extension Date {
    var ts: Int64 { Int64(timeIntervalSince1970) }
}

func clockString(_ ts: Int64) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "HH:mm"
    return f.string(from: Date(timeIntervalSince1970: Double(ts)))
}
