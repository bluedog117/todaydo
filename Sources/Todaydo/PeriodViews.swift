import SwiftUI
import Charts
import TodaydoCore



struct WeekView: View {
    @EnvironmentObject var model: AppModel
    @State private var weekStart = Date()
    @State private var filter: DayFilter = .all
    @State private var sessions: [Session] = []

    struct Bar: Identifiable { var id = UUID(); var day: String; var dayDate: Date; var cat: String; var hours: Double }

    var dc: DayCalendar { model.dc }
    var start: Date { dc.weekStart(containing: weekStart) }

    var body: some View {
        let types = model.viewDB.dayTypes()
        let days = (0..<7).map { dc.addDays($0, to: start) }.filter { filter.matches($0, dc: dc, types: types) }
        let end = dc.addDays(7, to: start)
        let wk = Stats.clipped(sessions, from: start.ts, to: end.ts).filter { s in
            filter == .all || days.contains { Stats.clipped([s], from: $0.ts, to: dc.nextDayStart(after: $0).ts).count > 0 }
        }
        let prevStart = dc.addDays(-7, to: start)
        let prev = Stats.clipped(sessions, from: prevStart.ts, to: start.ts)
        let total = Stats.total(wk)
        let prevTotal = Stats.total(prev)
        let perDay = Stats.perDay(sessions, days: days, dc: dc)
        let bars: [Bar] = zip(days, perDay).flatMap { d, m in
            m.map { Bar(day: weekdayLabel(d), dayDate: d, cat: model.catName($0.key), hours: Double($0.value) / 3600) }
        }
        let rank = Stats.rank(wk)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    DateNav(title: rangeTitle(start, dc.addDays(6, to: start)),
                            onPrev: { weekStart = dc.addDays(-7, to: start) },
                            onNext: { weekStart = dc.addDays(7, to: start) },
                            onToday: { weekStart = Date() })
                    Spacer()
                    DayFilterPicker(filter: $filter)
                }
                HStack(spacing: 12) {
                    StatTile(title: "This week total", value: Stats.formatDuration(total, compact: true),
                             sub: prevTotal > 0 ? "Compared with last week: \(total >= prevTotal ? "+" : "-")\(Stats.formatDuration(abs(total - prevTotal), compact: true))" : nil)
                    StatTile(title: "Daily average", value: Stats.formatDuration(days.isEmpty ? 0 : total / Int64(days.count), compact: true), color: .green)
                    StatTile(title: "Most active day", value: perDay.enumerated().max { $0.element.values.reduce(0, +) < $1.element.values.reduce(0, +) }
                        .map { weekdayLabel(days[$0.offset]) } ?? "—", sub: nil, color: .orange)
                }
                Card("Daily duration (By category)") {
                    Chart(bars) { b in
                        BarMark(x: .value("Sun", b.day), y: .value(" hours", b.hours), width: .ratio(0.6))
                            .foregroundStyle(by: .value("Category", b.cat))
                            .cornerRadius(3)
                    }
                    .chartForegroundStyleScale(domain: model.categories.map(\.name), range: model.categories.map { Color(hex: $0.color) })
                    .chartXScale(domain: days.map(weekdayLabel))
                    .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d))h") } } } }
                    .frame(height: 240)
                }
                HStack(alignment: .top, spacing: 16) {
                    Card("Category breakdown") { CategoryDonut(byCategory: Stats.byCategory(wk)) }
                    Card("This week Top") {
                        VStack(spacing: 8) {
                            ForEach(rank.prefix(8)) { RankRow(item: $0, maxSeconds: rank.first?.seconds ?? 1) }
                            if rank.isEmpty { Text("No data yet").foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            .padding(20)
        }
        .onAppear(perform: load)
        .onChange(of: model.dataVersion) { load() }
        .onChange(of: weekStart) { load() }
    }

    func load() {
        let s = start
        sessions = model.viewDB.sessions(from: dc.addDays(-7, to: s).ts, to: dc.addDays(7, to: s).ts)
    }

    func weekdayLabel(_ d: Date) -> String {
        "Week " + ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][dc.isoWeekday(d) - 1]
    }
}

func rangeTitle(_ a: Date, _ b: Date) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "M.d"
    return "\(f.string(from: a.addingTimeInterval(4 * 3600 + 1))) – \(f.string(from: b.addingTimeInterval(4 * 3600 + 1)))"
}



struct MonthView: View {
    @EnvironmentObject var model: AppModel
    @State private var monthStart = Date()
    @State private var filter: DayFilter = .all
    @State private var sessions: [Session] = []

    var dc: DayCalendar { model.dc }
    var first: Date { dc.monthStart(containing: monthStart) }

    var body: some View {
        let types = model.viewDB.dayTypes()
        let next = dc.addMonths(1, to: first)
        let nDays = Int((next.timeIntervalSince(first) / 86400).rounded())
        let days = (0..<nDays).map { dc.addDays($0, to: first) }
        let per = days.map { d in Stats.total(Stats.clipped(sessions, from: d.ts, to: dc.nextDayStart(after: d).ts)) }
        let counted = zip(days, per).filter { filter.matches($0.0, dc: dc, types: types) }
        let maxV = max(1, per.max() ?? 1)
        let month = Stats.clipped(sessions, from: first.ts, to: next.ts)
        let rank = Stats.rank(month)
        let offset = dc.isoWeekday(first) - 1
        let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        let title: String = {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MMMM yyyy"
            return f.string(from: first.addingTimeInterval(Double(model.settings.dayStartHour) * 3600 + 1))
        }()

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    DateNav(title: title,
                            onPrev: { monthStart = dc.addMonths(-1, to: first) },
                            onNext: { monthStart = dc.addMonths(1, to: first) },
                            onToday: { monthStart = Date() })
                    Spacer()
                    DayFilterPicker(filter: $filter)
                }
                HStack(spacing: 12) {
                    let sum = counted.reduce(Int64(0)) { $0 + $1.1 }
                    let active = counted.filter { $0.1 > 0 }.count
                    StatTile(title: "This month total", value: Stats.formatDuration(sum, compact: true))
                    StatTile(title: "Active days", value: "\(active) days", color: .green)
                    StatTile(title: "Average per active day", value: Stats.formatDuration(active == 0 ? 0 : sum / Int64(active), compact: true), color: .orange)
                }
                Card("Calendar heatmap (Click a day to view)") {
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
                        }
                        LazyVGrid(columns: cols, spacing: 6) {
                            ForEach(0..<(offset + nDays), id: \.self) { i in
                                if i < offset {
                                    Color.clear.frame(height: 62)
                                } else {
                                    let idx = i - offset
                                    let v = per[idx]
                                    let dim = !filter.matches(days[idx], dc: dc, types: types)
                                    let dayNum = Calendar.current.component(.day, from: days[idx].addingTimeInterval(Double(model.settings.dayStartHour) * 3600 + 1))
                                    VStack(spacing: 2) {
                                        Text("\(dayNum)").font(.caption.bold())
                                        Text(v > 0 ? Stats.formatDuration(v, compact: true) : "").font(.caption2)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 62)
                                    .foregroundStyle(v > maxV / 2 ? .white : .primary)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(v == 0 ? Color.primary.opacity(0.05) : Color.accentColor.opacity(0.15 + 0.85 * Double(v) / Double(maxV)))
                                    )
                                    .opacity(dim ? 0.25 : 1)
                                    .contentShape(Rectangle())
                                    .onTapGesture { model.jumpToDay(days[idx]) }
                                }
                            }
                        }
                    }
                }
                HStack(alignment: .top, spacing: 16) {
                    Card("Category breakdown") { CategoryDonut(byCategory: Stats.byCategory(month)) }
                    Card("This month Top") {
                        VStack(spacing: 8) {
                            ForEach(rank.prefix(8)) { RankRow(item: $0, maxSeconds: rank.first?.seconds ?? 1) }
                            if rank.isEmpty { Text("No data yet").foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            .padding(20)
        }
        .onAppear(perform: load)
        .onChange(of: model.dataVersion) { load() }
        .onChange(of: monthStart) { load() }
    }

    func load() {
        let f = first
        sessions = model.viewDB.sessions(from: f.ts, to: dc.addMonths(1, to: f).ts)
    }
}



struct TrendView: View {
    @EnvironmentObject var model: AppModel
    @State private var rangeDays = 30
    @State private var series = "all"
    @State private var filter: DayFilter = .all
    @State private var sessions: [Session] = []

    struct Point: Identifiable { var id: Date { day }; var day: Date; var hours: Double }
    struct TimePoint: Identifiable { var id = UUID(); var day: Date; var kind: String; var hour: Double }

    var dc: DayCalendar { model.dc }

    var body: some View {
        let types = model.viewDB.dayTypes()
        let today = dc.dayStart(containing: Date())
        let days = (0..<rangeDays).map { dc.addDays(-(rangeDays - 1) + $0, to: today) }.filter { filter.matches($0, dc: dc, types: types) }
        let rankAll = Stats.rank(sessions)
        let options = rankAll.prefix(8)

        let points: [Point] = days.map { d in
            let clip = Stats.clipped(sessions, from: d.ts, to: dc.nextDayStart(after: d).ts).filter { s in
                if series == "all" { return true }
                if series.hasPrefix("c:") { return "c:\(s.categoryId)" == series }
                return s.key == series
            }
            return Point(day: d, hours: Double(Stats.total(clip)) / 3600)
        }
        let timePoints: [TimePoint] = days.flatMap { d -> [TimePoint] in
            let clip = Stats.clipped(sessions, from: d.ts, to: dc.nextDayStart(after: d).ts).filter { !$0.isAway }
            guard let a = clip.map(\.startTs).min(), let b = clip.map(\.endTs).max() else { return [] }
            let base = Double(model.settings.dayStartHour)
            return [TimePoint(day: d, kind: "First activity", hour: base + Double(a - d.ts) / 3600),
                    TimePoint(day: d, kind: "Last activity", hour: base + Double(b - d.ts) / 3600)]
        }
        let nonZero = points.filter { $0.hours > 0 }
        let avg = nonZero.isEmpty ? 0 : nonZero.map(\.hours).reduce(0, +) / Double(nonZero.count)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Picker("Range", selection: $rangeDays) {
                        Text("30 days").tag(30); Text("90 days").tag(90); Text("365 days").tag(365)
                    }
                    .pickerStyle(.segmented).frame(width: 220)
                    Picker("Target", selection: $series) {
                        Text("All").tag("all")
                        Divider()
                        ForEach(model.categories) { Text("Category · \($0.name)").tag("c:\($0.id)") }
                        Divider()
                        ForEach(Array(options)) { Text($0.name).tag($0.key) }
                    }
                    .frame(width: 220)
                    Spacer()
                    DayFilterPicker(filter: $filter)
                }
                HStack(spacing: 12) {
                    StatTile(title: "Selected total", value: Stats.formatDuration(Int64(points.map(\.hours).reduce(0, +) * 3600), compact: true))
                    StatTile(title: "Average per active day", value: String(format: "%.1f hours", avg), color: .green)
                    StatTile(title: "Peak day", value: String(format: "%.1f hours", points.map(\.hours).max() ?? 0), color: .orange)
                }
                Card("Activity duration trends") {
                    Chart(points) { p in
                        AreaMark(x: .value("Date", p.day, unit: .day), y: .value(" hours", p.hours))
                            .foregroundStyle(LinearGradient(colors: [.accentColor.opacity(0.35), .accentColor.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Date", p.day, unit: .day), y: .value(" hours", p.hours))
                            .foregroundStyle(Color.accentColor).interpolationMethod(.monotone)
                        if avg > 0 {
                            RuleMark(y: .value("Average", avg)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(.secondary)
                        }
                    }
                    .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d))h") } } } }
                    .frame(height: 240)
                }
                Card("Daily rhythm: Earliest / Last activity time") {
                    Chart(timePoints) { p in
                        PointMark(x: .value("Date", p.day, unit: .day), y: .value("Time", p.hour))
                            .foregroundStyle(by: .value("Type", p.kind)).symbolSize(24)
                    }
                    .chartYScale(domain: Double(model.settings.dayStartHour)...Double(model.settings.dayStartHour + 24))
                    .chartYAxis {
                        AxisMarks(values: .stride(by: 4)) { v in
                            AxisGridLine()
                            AxisValueLabel { if let d = v.as(Double.self) { Text(String(format: "%02d:00", Int(d) % 24)) } }
                        }
                    }
                    .frame(height: 220)
                }
            }
            .padding(20)
        }
        .onAppear(perform: load)
        .onChange(of: model.dataVersion) { load() }
        .onChange(of: rangeDays) { load() }
    }

    func load() {
        let today = dc.dayStart(containing: Date())
        let from = dc.addDays(-(rangeDays - 1), to: today)
        sessions = model.viewDB.sessions(from: from.ts, to: dc.nextDayStart(after: today).ts)
    }
}



struct PomodoroCardView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var reminders = AppModel.shared.reminders
    @State private var taskInput = ""
    @State private var customMinutes = 25

    var body: some View {
        let _ = reminders.pomodoroTick
        let f = model.settings.focus
        Card("🍅 Pomodoro", trailing: AnyView(
            HStack(spacing: 10) {
                Text("Completed today \(reminders.todayPomodoros) pomodoros").font(.caption).foregroundStyle(.secondary)
                Menu {
                    ForEach(FocusRule.systemSounds, id: \.id) { s in
                        Button {
                            model.settings.focus.soundName = s.id
                            Notifier.playSystemSound(s.id)
                        } label: {
                            HStack {
                                Text(s.label)
                                if f.soundName == s.id { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    Label("Alert sound: \(f.soundName == "__mute__" ? "Mute" : (f.soundName == "__beep__" ? "Default" : f.soundName))", systemImage: "speaker.wave.2")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        )) {
            if let p = reminders.pomodoro {
                let rem = p.remainingSeconds()
                let total = p.totalSeconds
                let progress = min(1.0, max(0.0, 1.0 - rem / total))
                let remInt = Int(rem.rounded())
                let phaseColor: Color = p.phase == .work ? .red : .green
                let phaseLabel = p.phase == .work ? "Focusing" : (p.phase == .longRest ? "Long break" : "Short break")

                HStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .stroke(phaseColor.opacity(0.15), lineWidth: 10)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(phaseColor.gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 2) {
                            Text(String(format: "%02d:%02d", remInt / 60, remInt % 60))
                                .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                            Text(p.isPaused ? "Paused" : phaseLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 120, height: 120)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(p.phase == .work ? "Stay focused" : "Rest your eyes and shoulders")
                                .font(.title3.bold())
                            if p.auto {
                                Text("Automatic trigger")
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                        if !p.task.isEmpty {
                            Label(p.task, systemImage: "checkmark.circle")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 10) {
                            Button {
                                reminders.togglePausePomodoro()
                            } label: {
                                Label(p.isPaused ? "Resume" : "Pause", systemImage: p.isPaused ? "play.fill" : "pause.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(phaseColor)

                            Button("+5 min") { reminders.addPomodoroMinutes(5) }
                                .buttonStyle(.bordered)

                            Button(p.phase == .work ? "Finish and take a break" : "Skip break") {
                                reminders.skipPomodoroPhase()
                            }
                            .buttonStyle(.bordered)

                            Button(role: .destructive) {
                                reminders.stopPomodoro()
                            } label: {
                                Text("End")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        TextField("What will you focus on?? (Optional)", text: $taskInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 280)
                        Button {
                            reminders.startPomodoro(minutes: f.workMin, task: taskInput)
                        } label: {
                            Label("Start focus (\(f.workMin) min)", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)

                        ForEach([15, 25, 45, 60], id: \.self) { m in
                            if m != f.workMin {
                                Button("\(m) min") {
                                    reminders.startPomodoro(minutes: m, task: taskInput)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        Divider().frame(height: 18)
                        Button("Short break \(f.restMin)m") { reminders.startBreak(long: false, task: taskInput) }
                            .buttonStyle(.bordered)
                        Button("Long break \(f.longRestMin)m") { reminders.startBreak(long: true, task: taskInput) }
                            .buttonStyle(.bordered)
                    }
                    HStack(spacing: 16) {
                        Text("Default: Focus \(f.workMin) min · Short break \(f.restMin) min · Every \(f.longRestEvery) pomodoros per long break \(f.longRestMin) min (Available in “Settings” to adjust)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct FocusView: View {
    @EnvironmentObject var model: AppModel
    @State private var sessions: [Session] = []
    @State private var stats: [(hour: Int64, count: Int)] = []

    struct DayFocus: Identifiable { var id: Date { day }; var day: Date; var avgMin: Double; var frag: Double; var switches: Int }

    var dc: DayCalendar { model.dc }

    var body: some View {
        let today = dc.dayStart(containing: Date())
        let days = (0..<14).map { dc.addDays(-13 + $0, to: today) }
        let rows: [DayFocus] = days.map { d in
            let e = dc.nextDayStart(after: d)
            let clip = Stats.clipped(sessions, from: d.ts, to: e.ts)
            let segs = Stats.focusSegments(clip)
            let avg = segs.isEmpty ? 0 : Double(Stats.total(clip)) / Double(segs.count) / 60
            let sw = stats.filter { $0.hour >= d.ts && $0.hour < e.ts }.reduce(0) { $0 + $1.count }
            return DayFocus(day: d, avgMin: avg, frag: Stats.fragmentation(clip), switches: sw)
        }
        let todayRow = rows.last
        let todaySess = Stats.clipped(sessions, from: today.ts, to: dc.nextDayStart(after: today).ts)
        let longest = Stats.focusSegments(todaySess).max { $0.duration < $1.duration }

        
        let grid = heatGrid(today: today)
        let maxG = max(1, grid.flatMap { $0 }.max() ?? 1)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PomodoroCardView()
                HStack(spacing: 12) {
                    StatTile(title: "Switches today", value: "\(todayRow?.switches ?? 0) times", color: .orange)
                    StatTile(title: "Average focus ", value: String(format: "%.0f min", todayRow?.avgMin ?? 0), color: .green)
                    StatTile(title: "Longest focus", value: longest.map { Stats.formatDuration($0.duration, compact: true) } ?? "—",
                             sub: longest.map { "\(clockString($0.start))–\(clockString($0.end)) · \(model.catName($0.categoryId))" })
                    StatTile(title: "Fragmentation", value: "\(Int((todayRow?.frag ?? 0) * 100))%", sub: "Shorter than 2 min session share", color: .pink)
                }
                Card("When are you most distracted??", trailing: AnyView(Text("Last 4 Week , Average switches per hour").font(.caption).foregroundStyle(.secondary))) {
                    VStack(spacing: 4) {
                        HStack(spacing: 3) {
                            Text("").frame(width: 26)
                            ForEach(0..<24, id: \.self) { h in
                                Text(h % 3 == 0 ? "\(h)" : "").font(.system(size: 9)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                            }
                        }
                        ForEach(0..<7, id: \.self) { w in
                            HStack(spacing: 3) {
                                Text("Week " + ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][w]).font(.caption2).foregroundStyle(.secondary).frame(width: 26)
                                ForEach(0..<24, id: \.self) { h in
                                    let v = grid[w][h]
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(v == 0 ? Color.primary.opacity(0.05) : Color.orange.opacity(0.15 + 0.85 * v / maxG))
                                        .frame(height: 22)
                                        .help(String(format: "%.0f times/ hours", v))
                                }
                            }
                        }
                    }
                }
                HStack(alignment: .top, spacing: 16) {
                    Card("Average daily focus duration ( min)") {
                        Chart(rows) { r in
                            BarMark(x: .value("Date", r.day, unit: .day), y: .value(" min", r.avgMin)).foregroundStyle(Color.green.gradient).cornerRadius(3)
                        }.frame(height: 180)
                    }
                    Card("Daily App App switches") {
                        Chart(rows) { r in
                            BarMark(x: .value("Date", r.day, unit: .day), y: .value(" times", r.switches)).foregroundStyle(Color.orange.gradient).cornerRadius(3)
                        }.frame(height: 180)
                    }
                }
                Text("“focus session”: Adjacent, same category, gap no greater than 2 min are merged; Shorter than 5 second switches still count, without creating a record. ")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .onAppear(perform: load)
        .onChange(of: model.dataVersion) { load() }
    }

    
    func heatGrid(today: Date) -> [[Double]] {
        var grid = Array(repeating: Array(repeating: 0.0, count: 24), count: 7)
        var weekdayCount = Array(repeating: 0, count: 7)
        let cal = Calendar.current
        for i in 0..<28 {
            let d = dc.addDays(-i, to: today)
            weekdayCount[dc.isoWeekday(d) - 1] += 1
        }
        for s in stats {
            let date = Date(timeIntervalSince1970: Double(s.hour))
            let wd = dc.isoWeekday(dc.dayStart(containing: date)) - 1
            let h = cal.component(.hour, from: date)
            grid[wd][h] += Double(s.count)
        }
        for w in 0..<7 where weekdayCount[w] > 0 { for h in 0..<24 { grid[w][h] /= Double(weekdayCount[w]) } }
        return grid
    }

    func load() {
        let today = dc.dayStart(containing: Date())
        let from = dc.addDays(-27, to: today)
        let to = dc.nextDayStart(after: today)
        sessions = model.viewDB.sessions(from: from.ts, to: to.ts)
        stats = model.viewDB.switchStats(from: from.ts, to: to.ts)
    }
}
