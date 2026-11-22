import SwiftUI
import Charts
import TodaydoCore

struct TodayView: View {
    @EnvironmentObject var model: AppModel
    @State private var sessions: [Session] = []
    @State private var switches = 0
    @State private var range: SelRange?
    @State private var editing: Session?
    @State private var showAdd = false

    struct SelRange: Identifiable { let id = UUID(); var from: Int64; var to: Int64 }

    var dc: DayCalendar { model.dc }
    var day: (start: Date, end: Date) { dc.dayRange(containing: model.todayDate) }

    var body: some View {
        let from = day.start.ts, to = day.end.ts
        let clipped = Stats.clipped(sessions, from: from, to: min(to, max(Date().ts, from)))
        let total = Stats.total(clipped)
        let segs = Stats.focusSegments(clipped)
        let longest = segs.max { $0.duration < $1.duration }
        let avgFocus = segs.isEmpty ? 0 : Stats.total(clipped) / Int64(segs.count)
        let frag = Stats.fragmentation(clipped)
        let rank = Stats.rank(clipped)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    DateNav(title: titleText,
                            onPrev: { model.todayDate = dc.addDays(-1, to: day.start) },
                            onNext: { model.todayDate = dc.addDays(1, to: day.start) },
                            onToday: { model.todayDate = Date() })
                    Spacer()
                    if !model.viewingRemote {
                        Button { showAdd = true } label: { Label("Add activity", systemImage: "plus") }
                        Button { model.undo() } label: { Label(model.db.lastEditName.map { "Undo\($0)" } ?? "Undo", systemImage: "arrow.uturn.backward") }
                            .keyboardShortcut("z", modifiers: .command)
                            .disabled(!model.db.canUndo)
                    }
                }

                HStack(spacing: 12) {
                    StatTile(title: "Total time", value: Stats.formatDuration(total, compact: true), sub: "including offline activity: \(Stats.formatDuration(Stats.total(clipped.filter { $0.isAway }), compact: true))")
                    StatTile(title: "Longest focus", value: longest.map { Stats.formatDuration($0.duration, compact: true) } ?? "—",
                             sub: longest.map { "\(clockString($0.start))–\(clockString($0.end)) · \(model.catName($0.categoryId))" },
                             color: .green)
                    StatTile(title: "App Switches", value: "\(switches) times", sub: "Average focus \(Stats.formatDuration(avgFocus, compact: true))", color: .orange)
                    StatTile(title: "Fragmentation", value: "\(Int(frag * 100))%", sub: "Shorter than 2 min session share", color: .pink)
                }

                Card("Timeline", trailing: AnyView(Text(model.viewingRemote ? "Read-only" : "Drag to select and edit / Offline activity").font(.caption).foregroundStyle(.secondary))) {
                    TimelineStrip(sessions: clipped, dayStart: day.start, dayEnd: day.end, editable: !model.viewingRemote) { lo, hi in
                        range = SelRange(from: lo, to: hi)
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    Card("Category breakdown") { CategoryDonut(byCategory: Stats.byCategory(clipped)) }
                    Card("App / Website ranking") {
                        VStack(spacing: 8) {
                            ForEach(rank.prefix(8)) { RankRow(item: $0, maxSeconds: rank.first?.seconds ?? 1) }
                            if rank.isEmpty { Text("No data yet").foregroundStyle(.secondary) }
                        }
                    }
                }

                Card("Activity details (\(clipped.count))") {
                    VStack(spacing: 0) {
                        ForEach(clipped.reversed()) { s in
                            HStack(spacing: 10) {
                                Text("\(clockString(s.startTs))–\(clockString(s.endTs))").font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
                                ItemIcon(bundleId: s.bundleId, domain: s.domain, color: model.catColor(s.categoryId), size: 18)
                                Text(s.displayName).lineLimit(1)
                                if s.isAway { Text(s.source == "away" ? "Offline activity" : "Manual").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1).background(.quaternary, in: Capsule()) }
                                if let p = model.projectName(s.projectId) { Label(p, systemImage: "folder").font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Circle().fill(model.catColor(s.categoryId)).frame(width: 8, height: 8)
                                Text(model.catName(s.categoryId)).font(.caption).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
                                Text(Stats.formatDuration(s.duration, compact: true)).font(.callout.monospacedDigit()).frame(width: 60, alignment: .trailing)
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                            .onTapGesture { if !model.viewingRemote { editing = model.db.session(id: s.id) ?? s } }
                            Divider()
                        }
                        if clipped.isEmpty { Text("No activity on this day").foregroundStyle(.secondary).padding(.vertical, 8) }
                    }
                }
            }
            .padding(20)
        }
        .onAppear(perform: load)
        .onChange(of: model.dataVersion) { load() }
        .onChange(of: model.todayDate) { load() }
        .sheet(item: $range) { r in RangeEditSheet(from: r.from, to: r.to) }
        .sheet(item: $editing) { s in SessionEditSheet(session: s) }
        .sheet(isPresented: $showAdd) {
            RangeEditSheet(from: max(day.start.ts, min(Date().ts, day.end.ts) - 3600), to: min(Date().ts, day.end.ts), forceAdd: true)
        }
    }

    var titleText: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d, EEEE"
        return f.string(from: day.start.addingTimeInterval(Double(model.settings.dayStartHour) * 3600 + 1))
    }

    func load() {
        let d = day
        sessions = model.viewDB.sessions(from: d.start.ts, to: d.end.ts)
        switches = model.viewDB.switchStats(from: d.start.ts / 3600 * 3600, to: d.end.ts).reduce(0) { $0 + $1.count }
    }
}



struct RangeEditSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var from: Int64
    @State var to: Int64
    var forceAdd = false

    @State private var cat: Int64 = 1
    @State private var project: Int64 = 0
    @State private var label = ""

    private var hasSessions: Bool { !model.viewDB.sessions(from: from, to: to).isEmpty }
    private var fromDate: Binding<Date> { Binding(get: { Date(timeIntervalSince1970: Double(from)) }, set: { from = $0.ts }) }
    private var toDate: Binding<Date> { Binding(get: { Date(timeIntervalSince1970: Double(to)) }, set: { to = $0.ts }) }

    var body: some View {
        let adding = forceAdd || !hasSessions
        VStack(alignment: .leading, spacing: 14) {
            Text(adding ? "Add activity (Offline activity)" : "Edit selected time range").font(.title3.bold())
            HStack {
                DatePicker("Start", selection: fromDate, displayedComponents: [.hourAndMinute])
                DatePicker("End", selection: toDate, displayedComponents: [.hourAndMinute])
                Text(Stats.formatDuration(max(0, to - from))).foregroundStyle(.secondary)
            }
            Form {
                Picker("Category", selection: $cat) { ForEach(model.categories) { Text($0.name).tag($0.id) } }
                Picker("Project", selection: $project) {
                    Text("None").tag(Int64(0))
                    ForEach(model.projects) { Text($0.name).tag($0.id) }
                }
                TextField(adding ? "Activity (e.g.: Meeting)" : "Label (Optional)", text: $label)
            }
            .formStyle(.columns)

            HStack {
                if !adding {
                    Button(role: .destructive) { model.edit(from: from, to: to, .delete); dismiss() } label: { Label("Delete selection", systemImage: "trash") }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                if adding {
                    Button("Add") {
                        model.tracker.commitBoundary()
                        let s = Session(startTs: from, endTs: to, source: "manual", categoryId: cat,
                                        projectId: project == 0 ? nil : project, label: label.isEmpty ? "Manual activity" : label, edited: true)
                        _ = try? model.db.addManualSession(s)
                        model.afterEdit(); dismiss()
                    }
                    .keyboardShortcut(.defaultAction).disabled(to <= from)
                } else {
                    Button("Apply category") { model.edit(from: from, to: to, .setCategory(cat)); dismiss() }
                    Button("Assign project") { model.edit(from: from, to: to, .setProject(project == 0 ? nil : project)); dismiss() }
                    Button("Set label") { model.edit(from: from, to: to, .setLabel(label.isEmpty ? nil : label)); dismiss() }.disabled(label.isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear { cat = model.viewDB.sessions(from: from, to: to).first?.categoryId ?? 1 }
    }
}



struct SessionEditSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var session: Session
    @State private var cat: Int64 = 5
    @State private var project: Int64 = 0
    @State private var label = ""
    @State private var splitAt = Date()
    @State private var alwaysRule = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ItemIcon(bundleId: session.bundleId, domain: session.domain, color: model.catColor(session.categoryId), size: 28)
                VStack(alignment: .leading) {
                    Text(session.displayName).font(.title3.bold())
                    Text("\(clockString(session.startTs))–\(clockString(session.endTs)) · \(Stats.formatDuration(session.duration))").foregroundStyle(.secondary)
                }
            }
            Form {
                Picker("Category", selection: $cat) { ForEach(model.categories) { Text($0.name).tag($0.id) } }
                if session.bundleId != nil || session.domain != nil {
                    Toggle("Always “\(session.domain ?? session.appName ?? "")” always uses this category", isOn: $alwaysRule)
                }
                Picker("Project", selection: $project) {
                    Text("None").tag(Int64(0))
                    ForEach(model.projects) { Text($0.name).tag($0.id) }
                }
                TextField("Label", text: $label)
                HStack {
                    DatePicker("Split at", selection: $splitAt, in: Date(timeIntervalSince1970: Double(session.startTs + 1))...Date(timeIntervalSince1970: Double(max(session.startTs + 2, session.endTs - 1))), displayedComponents: [.hourAndMinute])
                    Button("Split") {
                        model.tracker.commitBoundary()
                        try? model.db.splitSession(at: splitAt.ts); model.afterEdit(); dismiss()
                    }
                }
            }
            .formStyle(.columns)
            HStack {
                Button(role: .destructive) { model.edit(from: session.startTs, to: session.endTs, .delete); dismiss() } label: { Label("Delete", systemImage: "trash") }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            cat = session.categoryId
            project = session.projectId ?? 0
            label = session.label ?? ""
            splitAt = Date(timeIntervalSince1970: Double((session.startTs + session.endTs) / 2))
        }
    }

    func save() {
        let (a, b) = (session.startTs, session.endTs)
        if cat != session.categoryId { model.edit(from: a, to: b, .setCategory(cat)) }
        if project != (session.projectId ?? 0) { model.edit(from: a, to: b, .setProject(project == 0 ? nil : project)) }
        if label != (session.label ?? "") { model.edit(from: a, to: b, .setLabel(label.isEmpty ? nil : label)) }
        if alwaysRule {
            if let d = session.domain { try? model.db.setDomain(host: d, categoryId: cat) }
            else if let bid = session.bundleId { try? model.db.setApp(bundleId: bid, categoryId: cat) }
            model.reclassify()
        }
        dismiss()
    }
}
