import SwiftUI
import Charts
import AppKit
import TodaydoCore




struct UIScaled<Content: View>: View {
    var scale: Double
    @ViewBuilder var content: Content

    var body: some View {
        if abs(scale - 1) < 0.01 {
            content
        } else {
            GeometryReader { g in
                content
                    .frame(width: g.size.width / scale, height: g.size.height / scale)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
            }
        }
    }
}

enum UIScale {
    static let key = "todaydo.uiScale"
    static let range: ClosedRange<Double> = 0.8...1.5
}



struct Card<Content: View>: View {
    var title: String?
    var trailing: AnyView?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.trailing = trailing; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title != nil || trailing != nil {
                HStack {
                    if let t = title { Text(t).font(.headline) }
                    Spacer()
                    trailing
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct StatTile: View {
    var title: String
    var value: String
    var sub: String?
    var color: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(color).minimumScaleFactor(0.6).lineLimit(1)
            if let s = sub { Text(s).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }
}

@MainActor
enum IconCache {
    private static var cache: [String: NSImage] = [:]
    static func icon(bundleId: String) -> NSImage? {
        if let i = cache[bundleId] { return i }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 32, height: 32)
        cache[bundleId] = img
        return img
    }
}

struct ItemIcon: View {
    var bundleId: String?
    var domain: String?
    var color: Color
    var size: CGFloat = 22

    var body: some View {
        Group {
            if domain != nil {
                Image(systemName: "globe").resizable().scaledToFit().padding(3).foregroundStyle(.white)
                    .background(color, in: RoundedRectangle(cornerRadius: size * 0.25))
            } else if let b = bundleId, let img = IconCache.icon(bundleId: b) {
                Image(nsImage: img).resizable().scaledToFit()
            } else {
                Image(systemName: "figure.walk").resizable().scaledToFit().padding(4).foregroundStyle(.white)
                    .background(color, in: RoundedRectangle(cornerRadius: size * 0.25))
            }
        }
        .frame(width: size, height: size)
    }
}

struct RankRow: View {
    @EnvironmentObject var model: AppModel
    var item: RankItem
    var maxSeconds: Int64

    var body: some View {
        HStack(spacing: 10) {
            ItemIcon(bundleId: item.bundleId, domain: item.domain, color: model.catColor(item.categoryId))
            Text(item.name).lineLimit(1).frame(width: 120, alignment: .leading)
            GeometryReader { g in
                Capsule().fill(model.catColor(item.categoryId).gradient)
                    .frame(width: max(4, g.size.width * CGFloat(item.seconds) / CGFloat(max(1, maxSeconds))), height: 8)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 16)
            Text(Stats.formatDuration(item.seconds, compact: true)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
    }
}

struct CategoryDonut: View {
    @EnvironmentObject var model: AppModel
    var byCategory: [Int64: Int64]

    var body: some View {
        let items = byCategory.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        let total = items.reduce(Int64(0)) { $0 + $1.value }
        HStack(spacing: 20) {
            Chart(items, id: \.key) { it in
                SectorMark(angle: .value("Duration", it.value), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .cornerRadius(4)
                    .foregroundStyle(model.catColor(it.key))
            }
            .frame(width: 150, height: 150)
            .overlay {
                VStack(spacing: 0) {
                    Text(Stats.formatDuration(total, compact: true)).font(.title3.bold().monospacedDigit())
                    Text("Total").font(.caption2).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.key) { it in
                    HStack(spacing: 6) {
                        Circle().fill(model.catColor(it.key)).frame(width: 9, height: 9)
                        Text(model.catName(it.key))
                        Spacer(minLength: 12)
                        Text("\(Int(Double(it.value) / Double(max(1, total)) * 100))%").foregroundStyle(.secondary).monospacedDigit()
                        Text(Stats.formatDuration(it.value, compact: true)).monospacedDigit().frame(width: 60, alignment: .trailing)
                    }
                    .font(.callout)
                }
                if items.isEmpty { Text("No data yet").foregroundStyle(.secondary) }
            }
        }
    }
}

enum DayFilter: String, CaseIterable, Identifiable {
    case all = "All", workday = "Workdays only", weekend = "Weekends only"
    var id: String { rawValue }
}

struct DayFilterPicker: View {
    @Binding var filter: DayFilter
    var body: some View {
        Picker("", selection: $filter) {
            ForEach(DayFilter.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 220)
    }
}

extension DayFilter {
    func matches(_ dayStart: Date, dc: DayCalendar, types: [String: String]) -> Bool {
        switch self {
        case .all: return true
        case .workday: return !dc.isWeekend(dayStart, dayTypes: types)
        case .weekend: return dc.isWeekend(dayStart, dayTypes: types)
        }
    }
}

struct DateNav: View {
    var title: String
    var onPrev: () -> Void
    var onNext: () -> Void
    var onToday: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPrev) { Image(systemName: "chevron.left") }
            Text(title).font(.title2.bold()).frame(minWidth: 150)
            Button(action: onNext) { Image(systemName: "chevron.right") }
            Button("Today", action: onToday)
        }
        .buttonStyle(.bordered)
    }
}



struct TimelineStrip: View {
    @EnvironmentObject var model: AppModel
    var sessions: [Session]
    var dayStart: Date
    var dayEnd: Date
    var editable: Bool
    var onSelect: (Int64, Int64) -> Void

    @State private var dragFrom: CGFloat?
    @State private var dragTo: CGFloat?

    private let stripH: CGFloat = 52

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let t0 = Double(dayStart.ts), span = Double(dayEnd.ts - dayStart.ts)
            Canvas { ctx, size in
                let bg = Path(roundedRect: CGRect(x: 0, y: 0, width: size.width, height: stripH), cornerRadius: 10)
                ctx.fill(bg, with: .color(.primary.opacity(0.06)))
                
                for i in 0...24 {
                    let x = size.width * CGFloat(i) / 24
                    var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: stripH))
                    ctx.stroke(p, with: .color(.primary.opacity(i % 3 == 0 ? 0.12 : 0.05)), lineWidth: 0.5)
                    if i % 3 == 0 && i < 24 {
                        let h = (model.settings.dayStartHour + i) % 24
                        ctx.draw(Text(String(format: "%02d", h)).font(.caption2).foregroundStyle(.secondary),
                                 at: CGPoint(x: x + 2, y: stripH + 10), anchor: .leading)
                    }
                }
                ctx.clip(to: bg)
                for s in sessions {
                    let x = size.width * CGFloat((Double(s.startTs) - t0) / span)
                    let ww = max(1, size.width * CGFloat(Double(s.duration) / span))
                    let r = CGRect(x: x, y: 4, width: ww, height: stripH - 8)
                    let c = model.catColor(s.categoryId)
                    if s.isAway {
                        ctx.fill(Path(r), with: .color(c.opacity(0.3)))
                        var hatch = Path()
                        var hx = r.minX - r.height
                        while hx < r.maxX {
                            hatch.move(to: CGPoint(x: hx, y: r.maxY)); hatch.addLine(to: CGPoint(x: hx + r.height, y: r.minY))
                            hx += 6
                        }
                        var c2 = ctx
                        c2.clip(to: Path(r))
                        c2.stroke(hatch, with: .color(c), lineWidth: 1)
                    } else {
                        ctx.fill(Path(r), with: .color(c))
                    }
                }
                if let a = dragFrom, let b = dragTo {
                    let r = CGRect(x: min(a, b), y: 0, width: abs(b - a), height: stripH)
                    ctx.fill(Path(r), with: .color(.accentColor.opacity(0.25)))
                    ctx.stroke(Path(r), with: .color(.accentColor), lineWidth: 1.5)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { v in
                        guard editable else { return }
                        dragFrom = min(max(0, v.startLocation.x), w)
                        dragTo = min(max(0, v.location.x), w)
                    }
                    .onEnded { v in
                        guard editable, let a = dragFrom, let b = dragTo else { return }
                        dragFrom = nil; dragTo = nil
                        let lo = Int64(t0 + span * Double(min(a, b) / w))
                        let hi = Int64(t0 + span * Double(max(a, b) / w))
                        if hi - lo >= 60 { onSelect(lo, hi) }
                    }
            )
        }
        .frame(height: stripH + 20)
    }
}



struct AwayPromptView: View {
    @EnvironmentObject var model: AppModel
    var from: Date
    var to: Date
    @State private var text = ""
    @State private var cat: Int64 = 5

    private let tagCategory: [String: Int64] = ["Meeting": 1, "Reading": 2]

    var body: some View {
        let mins = Int(to.timeIntervalSince(from) / 60)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "figure.walk.motion").foregroundStyle(.tint)
                Text("\(clockString(from.ts))–\(clockString(to.ts)) Away for \(mins) min").font(.headline)
                Spacer()
                Button { FloatingPanel.close(id: "away") } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Text("What were you doing??").font(.subheadline).foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(model.settings.awayTags, id: \.self) { tag in
                    Button(tag) { model.saveAway(from: from, to: to, label: tag, categoryId: tagCategory[tag] ?? 5, projectId: nil) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                ForEach(model.projects.prefix(4)) { p in
                    Button { model.saveAway(from: from, to: to, label: p.name, categoryId: 1, projectId: p.id) } label: {
                        Label(p.name, systemImage: "folder")
                    }
                    .buttonStyle(.bordered).controlSize(.small).tint(Color(hex: p.color))
                }
            }
            HStack {
                TextField("Or enter an activity…", text: $text).textFieldStyle(.roundedBorder)
                    .onSubmit { if !text.isEmpty { model.saveAway(from: from, to: to, label: text, categoryId: cat, projectId: nil) } }
                Picker("", selection: $cat) {
                    ForEach(model.categories) { Text($0.name).tag($0.id) }
                }
                .labelsHidden().frame(width: 70)
            }
            HStack {
                Spacer()
                Button("Dismiss") { FloatingPanel.close(id: "away") }.controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
        .padding(6)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}
