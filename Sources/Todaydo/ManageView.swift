import SwiftUI
import TodaydoCore

struct ManageView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case apps = "Apps", domains = "Websites", rules = "Time-based rules", projects = "Projects", cats = "Categories", days = "Workday/Day off"
        var id: String { rawValue }
    }
    @State private var tab: Tab = .apps

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) { ForEach(Tab.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().padding(16)
            Divider()
            Group {
                switch tab {
                case .apps: AppsTab()
                case .domains: DomainsTab()
                case .rules: RulesTab()
                case .projects: ProjectsTab()
                case .cats: CategoriesTab()
                case .days: DayTypesTab()
                }
            }
        }
    }
}



struct AppsTab: View {
    @EnvironmentObject var model: AppModel
    @State private var apps: [AppRow] = []
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text("Choose a category for each app. Excluded apps are not tracked while in the foreground. Password managers are excluded by default.")
                .font(.callout).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.top, 12)
            TextField("Search App", text: $search).textFieldStyle(.roundedBorder).padding(.horizontal, 16)
            List {
                ForEach(apps.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.bundleId.localizedCaseInsensitiveContains(search) }, id: \.bundleId) { a in
                    HStack {
                        ItemIcon(bundleId: a.bundleId, domain: nil, color: model.catColor(a.categoryId))
                        VStack(alignment: .leading) {
                            Text(a.name)
                            Text(a.bundleId).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: Binding(get: { a.categoryId }, set: { c in
                            try? model.db.setApp(bundleId: a.bundleId, categoryId: c); model.reclassify(); load()
                        })) { ForEach(model.categories) { Text($0.name).tag($0.id) } }
                        .labelsHidden().frame(width: 90)
                        Toggle("Exclude", isOn: Binding(get: { a.excluded }, set: { e in
                            try? model.db.setApp(bundleId: a.bundleId, excluded: e); model.classifier.reload(model.db); load()
                        }))
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    func load() { apps = model.db.apps() }
}



struct DomainsTab: View {
    @EnvironmentObject var model: AppModel
    @State private var seen: [(host: String, secs: Int64)] = []
    @State private var overrides: [DomainRow] = []
    @State private var newHost = ""
    @State private var newCat: Int64 = 1

    var body: some View {
        List {
            Section("Add domain override") {
                HStack {
                    TextField("e.g. notion.so", text: $newHost).textFieldStyle(.roundedBorder)
                    Picker("", selection: $newCat) { ForEach(model.categories) { Text($0.name).tag($0.id) } }.labelsHidden().frame(width: 90)
                    Button("Add") {
                        let h = newHost.lowercased().trimmingCharacters(in: .whitespaces)
                        guard !h.isEmpty else { return }
                        try? model.db.setDomain(host: h, categoryId: newCat); newHost = ""
                        model.reclassify(); load()
                    }
                }
            }
            Section("Websites in the last 30 days (domains only)") {
                ForEach(seen, id: \.host) { d in
                    let ov = overrides.first { $0.host == d.host }
                    let current = model.classifier.classify(bundleId: nil, domain: d.host, date: Date())
                    HStack {
                        Image(systemName: "globe").foregroundStyle(model.catColor(current))
                        Text(d.host)
                        Spacer()
                        Text(Stats.formatDuration(d.secs, compact: true)).foregroundStyle(.secondary).monospacedDigit()
                        Picker("", selection: Binding(get: { ov?.categoryId ?? current }, set: { c in
                            try? model.db.setDomain(host: d.host, categoryId: c, excluded: ov?.excluded ?? false); model.reclassify(); load()
                        })) { ForEach(model.categories) { Text($0.name).tag($0.id) } }
                        .labelsHidden().frame(width: 90)
                        Toggle("Exclude", isOn: Binding(get: { ov?.excluded ?? false }, set: { e in
                            try? model.db.setDomain(host: d.host, categoryId: ov?.categoryId ?? current, excluded: e)
                            model.classifier.reload(model.db); load()
                        }))
                    }
                }
                if seen.isEmpty { Text("No website activity yet. Enable browser domain tracking in Settings and grant Automation permission.").foregroundStyle(.secondary) }
            }
            if !overrides.isEmpty {
                Section("My overrides") {
                    ForEach(overrides, id: \.host) { o in
                        HStack {
                            Text(o.host); Spacer()
                            Text(model.catName(o.categoryId)).foregroundStyle(.secondary)
                            if o.excluded { Text("Excluded").font(.caption).foregroundStyle(.orange) }
                            Button(role: .destructive) { try? model.db.deleteDomain(host: o.host); model.reclassify(); load() } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    func load() {
        overrides = model.db.domains()
        let from = Date().addingTimeInterval(-30 * 86400).ts
        let rows = model.db.sessions(from: from, to: Date().ts).filter { $0.domain != nil }
        var m: [String: Int64] = [:]
        for s in rows { m[s.domain!, default: 0] += s.duration }
        seen = m.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }.prefix(60).map { (host: $0.0, secs: $0.1) }
    }
}



struct RulesTab: View {
    @EnvironmentObject var model: AppModel
    @State private var rules: [CategoryRule] = []
    @State private var apps: [AppRow] = []
    @State private var type = "app"
    @State private var appId = ""
    @State private var host = ""
    @State private var days: Set<Int> = []
    @State private var allDay = false
    @State private var startH = 9
    @State private var endH = 18
    @State private var cat: Int64 = 1
    private let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        List {
            Section("New rule: Same App / Classify websites differently by time of day") {
                Picker("Target", selection: $type) { Text("App").tag("app"); Text("Websites").tag("domain") }.pickerStyle(.segmented).frame(width: 180)
                if type == "app" {
                    Picker("App", selection: $appId) { ForEach(apps, id: \.bundleId) { Text($0.name).tag($0.bundleId) } }
                } else {
                    TextField("Domain, e.g. bilibili.com", text: $host)
                }
                HStack {
                    Text("Weekday")
                    ForEach(0..<7, id: \.self) { i in
                        let wd = (i + 1) % 7   
                        Toggle(names[wd], isOn: Binding(get: { days.contains(wd) }, set: { if $0 { days.insert(wd) } else { days.remove(wd) } })).toggleStyle(.button)
                    }
                    Text(" (None = Daily)").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Toggle("All day", isOn: $allDay)
                    if !allDay {
                        Stepper("From \(startH):00", value: $startH, in: 0...23)
                        Stepper(" to \(endH):00", value: $endH, in: 0...24)
                    }
                }
                HStack {
                    Picker("Assign to", selection: $cat) { ForEach(model.categories) { Text($0.name).tag($0.id) } }.frame(width: 160)
                    Button("Add rule") { add() }.disabled(type == "app" ? appId.isEmpty : host.isEmpty)
                }
            }
            Section("Existing rules (Overrides default categories)") {
                ForEach(rules) { r in
                    HStack {
                        Text(r.matchType == "app" ? (apps.first { $0.bundleId == r.matchValue }?.name ?? r.matchValue) : r.matchValue)
                        Text(describe(r)).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("→ " + model.catName(r.categoryId)).foregroundStyle(model.catColor(r.categoryId))
                        Button(role: .destructive) { try? model.db.deleteCategoryRule(r.id); model.reclassify(); load() } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                    }
                }
                if rules.isEmpty { Text("No rules yet").foregroundStyle(.secondary) }
            }
        }
        .onAppear(perform: load)
    }

    func describe(_ r: CategoryRule) -> String {
        var parts: [String] = []
        if r.weekdayMask != 0 { parts.append("Week " + (0..<7).filter { r.weekdayMask & (1 << $0) != 0 }.map { names[$0] }.joined()) }
        if r.startMin >= 0 { parts.append(String(format: "%02d:%02d–%02d:%02d", r.startMin / 60, r.startMin % 60, r.endMin / 60, r.endMin % 60)) }
        return parts.isEmpty ? "Every day, all day" : parts.joined(separator: " ")
    }

    func add() {
        let mask = days.reduce(0) { $0 | (1 << $1) }
        let r = CategoryRule(matchType: type, matchValue: type == "app" ? appId : host.lowercased(), weekdayMask: mask,
                             startMin: allDay ? -1 : startH * 60, endMin: allDay ? -1 : endH * 60, categoryId: cat, priority: 1)
        try? model.db.addCategoryRule(r)
        host = ""
        model.reclassify(); load()
    }

    func load() {
        rules = model.db.categoryRules()
        apps = model.db.apps()
        if appId.isEmpty { appId = apps.first?.bundleId ?? "" }
    }
}



struct ProjectsTab: View {
    @EnvironmentObject var model: AppModel
    @State private var rules: [ProjectRule] = []
    @State private var apps: [AppRow] = []
    @State private var name = ""
    @State private var colorHex = "#7B61FF"
    @State private var ruleProject: Int64 = 0
    @State private var ruleType = "app"
    @State private var ruleApp = ""
    @State private var ruleHost = ""

    var body: some View {
        List {
            Section("New project") {
                HStack {
                    TextField("Project name", text: $name).textFieldStyle(.roundedBorder)
                    ColorPicker("", selection: Binding(get: { Color(hex: colorHex) }, set: { colorHex = $0.hexString })).labelsHidden()
                    Button("Add") {
                        guard !name.isEmpty else { return }
                        try? model.db.addProject(name: name, color: colorHex); name = ""
                        model.reloadMeta(); load()
                    }
                }
            }
            Section("Project (On“Save to Calendar” after, Project activity appears in Calendar automatically“todaydo”in)") {
                ForEach(model.projects) { p in
                    HStack {
                        Circle().fill(Color(hex: p.color)).frame(width: 10, height: 10)
                        Text(p.name)
                        Spacer()
                        Toggle("Save to Calendar", isOn: Binding(get: { p.syncCalendar }, set: { v in
                            var q = p; q.syncCalendar = v; try? model.db.updateProject(q); model.reloadMeta(); model.calendar.sync()
                        }))
                        Stepper("Minimum \(p.minMinutes) min", value: Binding(get: { p.minMinutes }, set: { v in
                            var q = p; q.minMinutes = v; try? model.db.updateProject(q); model.reloadMeta()
                        }), in: 5...120, step: 5).frame(width: 150)
                        Button(role: .destructive) { try? model.db.deleteProject(p.id); model.reloadMeta(); load() } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                    }
                }
                if model.projects.isEmpty { Text("No projects yet").foregroundStyle(.secondary) }
            }
            Section("Assignment rules: When using an App / website is automatically assigned to a project") {
                HStack {
                    Picker("Project", selection: $ruleProject) { ForEach(model.projects) { Text($0.name).tag($0.id) } }.frame(width: 180)
                    Picker("", selection: $ruleType) { Text("App").tag("app"); Text("Websites").tag("domain") }.pickerStyle(.segmented).frame(width: 130).labelsHidden()
                    if ruleType == "app" {
                        Picker("", selection: $ruleApp) { ForEach(apps, id: \.bundleId) { Text($0.name).tag($0.bundleId) } }.labelsHidden()
                    } else {
                        TextField("Domain", text: $ruleHost).textFieldStyle(.roundedBorder)
                    }
                    Button("Add") {
                        let v = ruleType == "app" ? ruleApp : ruleHost.lowercased()
                        guard ruleProject != 0, !v.isEmpty else { return }
                        try? model.db.addProjectRule(projectId: ruleProject, matchType: ruleType, matchValue: v)
                        ruleHost = ""; model.reclassify(); load()
                    }
                }
                ForEach(rules) { r in
                    HStack {
                        Text(model.projectName(r.projectId) ?? "?").bold()
                        Text(r.matchType == "app" ? (apps.first { $0.bundleId == r.matchValue }?.name ?? r.matchValue) : r.matchValue).foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive) { try? model.db.deleteProjectRule(r.id); model.reclassify(); load() } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    func load() {
        rules = model.db.projectRules()
        apps = model.db.apps()
        if ruleApp.isEmpty { ruleApp = apps.first?.bundleId ?? "" }
        if ruleProject == 0 || !model.projects.contains(where: { $0.id == ruleProject }) { ruleProject = model.projects.first?.id ?? 0 }
    }
}

extension Color {
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return String(format: "#%02X%02X%02X", Int(ns.redComponent * 255), Int(ns.greenComponent * 255), Int(ns.blueComponent * 255))
    }
}



struct CategoriesTab: View {
    @EnvironmentObject var model: AppModel
    @State private var name = ""
    @State private var colorHex = "#8E5CF7"

    var body: some View {
        List {
            Section("Category ( before 5 are built in, Rename and change colors)") {
                ForEach(model.categories) { c in
                    HStack {
                        ColorPicker("", selection: Binding(get: { Color(hex: c.color) }, set: { n in
                            try? model.db.upsertCategory(Category(id: c.id, name: c.name, color: n.hexString)); model.reloadMeta()
                        })).labelsHidden()
                        TextField("", text: Binding(get: { c.name }, set: { n in
                            try? model.db.upsertCategory(Category(id: c.id, name: n, color: c.color)); model.reloadMeta()
                        })).textFieldStyle(.roundedBorder)
                        if c.id > 5 {
                            Button(role: .destructive) { try? model.db.deleteCategory(c.id); model.reloadMeta() } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Section("Add category") {
                HStack {
                    TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                    ColorPicker("", selection: Binding(get: { Color(hex: colorHex) }, set: { colorHex = $0.hexString })).labelsHidden()
                    Button("Add") {
                        guard !name.isEmpty else { return }
                        try? model.db.addCategory(name: name, color: colorHex); name = ""; model.reloadMeta()
                    }
                }
            }
        }
    }
}



struct DayTypesTab: View {
    @EnvironmentObject var model: AppModel
    @State private var date = Date()
    @State private var types: [String: String] = [:]

    var body: some View {
        List {
            Section("Override special dates (Workday override, Holidays), Affects“Workday/Weekend”Statistics filter") {
                HStack {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Button("Mark as workday") { set("workday") }
                    Button("Mark as day off") { set("weekend") }
                }
            }
            Section("Marked dates") {
                ForEach(types.sorted { $0.key > $1.key }, id: \.key) { k, v in
                    HStack {
                        Text(k); Text(v == "workday" ? "Workday" : "Day off").foregroundStyle(.secondary); Spacer()
                        Button(role: .destructive) { try? model.db.setDayType(date: k, type: nil); load() } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                    }
                }
                if types.isEmpty { Text("None yet").foregroundStyle(.secondary) }
            }
        }
        .onAppear(perform: load)
    }

    func set(_ t: String) {
        let key = model.dc.dayKey(model.dc.dayStart(containing: date.addingTimeInterval(12 * 3600)))
        try? model.db.setDayType(date: key, type: t); load(); model.bump()
    }

    func load() { types = model.db.dayTypes() }
}
