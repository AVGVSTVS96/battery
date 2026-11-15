import Charts
import SwiftUI

/// A week of screen time as iOS hands it to the report extension, the only place the numbers exist.
nonisolated public struct ScreenTime: Sendable {
    /// The report's name, which the app asks for and the extension answers to.
    public static let context = "usage"

    public struct Day: Sendable, Identifiable {
        public var start: Date
        public var total: TimeInterval
        public var pickups: Int
        public var firstPickup: Date?
        public var id: Date { start }

        public init(start: Date, total: TimeInterval, pickups: Int, firstPickup: Date?) {
            self.start = start
            self.total = total
            self.pickups = pickups
            self.firstPickup = firstPickup
        }
    }

    public struct App: Sendable, Identifiable {
        public var name: String
        public var total: TimeInterval
        public var pickups: Int
        public var id: String { name }

        public init(name: String, total: TimeInterval, pickups: Int) {
            self.name = name
            self.total = total
            self.pickups = pickups
        }
    }

    /// The last seven days, oldest first, today last.
    public var days: [Day]
    /// Seconds of use in each hour of today.
    public var hours: [TimeInterval]
    /// This week's most used apps, most first.
    public var apps: [App]
    public var now: Date

    public init(days: [Day], hours: [TimeInterval], apps: [App], now: Date) {
        self.days = days
        self.hours = hours
        self.apps = apps
        self.now = now
    }

    /// "3 h 52 m", "48 m".
    public static func text(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes < 60 ? "\(minutes) m" : "\(minutes / 60) h \(minutes % 60) m"
    }
}

/// Screen time in BROADCOM's style: today's figures, the week by day, today by hour and the apps that took it. The
/// app draws it from demo data; on the phone the report extension draws it, since only the extension sees the data.
nonisolated public struct ScreenTimeView: View {
    public var screenTime: ScreenTime

    public init(_ screenTime: ScreenTime) { self.screenTime = screenTime }

    /// The height the view needs at a width, which the app sets, since a report can't size itself to its content.
    public static func height(for width: CGFloat) -> CGFloat {
        switch Tier(width) {
        case .wide: 400
        case .medium: 528
        case .narrow: 910
        }
    }

    /// The page's own three layouts, by the width the report gets.
    enum Tier {
        case narrow, medium, wide

        init(_ width: CGFloat) { self = width >= 800 ? .wide : width >= 500 ? .medium : .narrow }
    }

    public var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 30) {
                switch Tier(geo.size.width) {
                case .wide:
                    HStack(alignment: .top, spacing: 32) {
                        figures(stacked: true).frame(width: min(geo.size.width * 0.24, 230))
                        part("This week", note: "per day") { week }
                        part("Today", note: "by hour") { today }
                    }
                    part("Most used", note: "this week") { apps(columns: 3) }
                case .medium:
                    figures(stacked: false)
                    HStack(alignment: .top, spacing: 32) {
                        part("This week", note: "per day") { week }
                        part("Today", note: "by hour") { today }
                    }
                    part("Most used", note: "this week") { apps(columns: 2) }
                case .narrow:
                    figures(stacked: false)
                    part("This week", note: "per day") { week }
                    part("Today", note: "by hour") { today }
                    part("Most used", note: "this week") { apps(columns: 1) }
                }
            }
        }
        .background(Ink.background)
    }

    private var todayTotal: ScreenTime.Day? { screenTime.days.last }

    private var average: TimeInterval? {
        let past = screenTime.days.dropLast().map(\.total).filter { $0 > 0 }
        return past.isEmpty ? nil : past.reduce(0, +) / Double(past.count)
    }

    private func figures(stacked: Bool) -> some View {
        let today = todayTotal
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout(alignment: .top, spacing: 0))
        return layout {
            figure("Screen on today", seconds: today?.total ?? 0,
                   caption: average.map { "\(ScreenTime.text($0)) a day this week" } ?? "Today so far")
            Rectangle().fill(Ink.line)
                .frame(width: stacked ? nil : 1, height: stacked ? 1 : nil)
                .padding(stacked ? .vertical : .horizontal, 18)
            VStack(alignment: .leading, spacing: 10) {
                Text("Pickups").font(.label).foregroundStyle(Ink.primary)
                Text("\(today?.pickups ?? 0)").font(.figure(40)).tracking(-0.8).foregroundStyle(Ink.primary)
                Text(today?.firstPickup.map { "First at \($0.formatted(.dateTime.hour().minute()))" } ?? "None yet")
                    .font(.label).foregroundStyle(Ink.secondary).lineLimit(1).minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func figure(_ label: String, seconds: TimeInterval, caption: String) -> some View {
        let minutes = Int((seconds / 60).rounded())
        return VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.label).foregroundStyle(Ink.primary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if minutes >= 60 {
                    Text("\(minutes / 60)").font(.figure(40)).tracking(-0.8).foregroundStyle(Ink.violet)
                    Text("h").font(.label).foregroundStyle(Ink.secondary).padding(.trailing, 6)
                }
                Text("\(minutes % 60)").font(.figure(40)).tracking(-0.8).foregroundStyle(Ink.violet)
                Text("m").font(.label).foregroundStyle(Ink.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(caption).font(.label).foregroundStyle(Ink.secondary).lineLimit(1).minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func part(_ title: String, note: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(Ink.primary)
                Text(note).font(.label).foregroundStyle(Ink.secondary).lineLimit(1)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var week: some View {
        let calendar = Calendar.current
        let top = max(screenTime.days.map(\.total).max() ?? 0, 3600) / 3600 * 1.15
        return Chart {
            ForEach(screenTime.days) { day in
                BarMark(x: .value("Day", day.start, unit: .day), y: .value("Hours", day.total / 3600), width: .ratio(0.55))
                    .foregroundStyle(calendar.isDate(day.start, inSameDayAs: screenTime.now) ? Ink.violet : Ink.violet.opacity(0.35))
                    .clipShape(.rect(cornerRadius: 3))
            }
            if let average {
                RuleMark(y: .value("Average", average / 3600))
                    .foregroundStyle(Ink.faint)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYScale(domain: 0...top)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Ink.line)
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0) h").font(.small).foregroundStyle(Ink.faint) }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisValueLabel(centered: true) {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(.dateTime.weekday(.narrow))).font(.small)
                            .foregroundStyle(calendar.isDate(date, inSameDayAs: screenTime.now) ? Ink.primary : Ink.faint)
                    }
                }
            }
        }
        .frame(height: 170)
    }

    private var today: some View {
        let hour = Calendar.current.component(.hour, from: screenTime.now)
        return Chart {
            ForEach(0..<24, id: \.self) { h in
                let minutes = (h < screenTime.hours.count ? screenTime.hours[h] : 0) / 60
                if minutes > 0 {
                    RectangleMark(xStart: .value("From", Double(h) - 0.35), xEnd: .value("To", Double(h) + 0.35),
                                  yStart: .value("Floor", 0), yEnd: .value("Minutes", minutes))
                        .foregroundStyle(h == hour ? Ink.violet : Ink.primary.opacity(0.22))
                        .clipShape(.rect(cornerRadius: 2))
                }
            }
        }
        .chartXScale(domain: -0.5...23.5)
        .chartYScale(domain: 0...min(max((screenTime.hours.max() ?? 0) / 60 * 1.15, 10), 60))
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18]) { value in
                AxisValueLabel(anchor: .top) {
                    if let h = value.as(Int.self),
                       let date = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: screenTime.now) {
                        Text(date.formatted(.dateTime.hour())).font(.small).foregroundStyle(Ink.faint)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Ink.line)
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0) m").font(.small).foregroundStyle(Ink.faint) }
            }
        }
        .frame(height: 170)
    }

    private func apps(columns: Int) -> some View {
        let shown = Array(screenTime.apps.prefix(6))
        let top = max(shown.first?.total ?? 1, 1)
        let rows = (shown.count + columns - 1) / columns
        return Grid(horizontalSpacing: 32, verticalSpacing: 0) {
            ForEach(0..<rows, id: \.self) { row in
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = column * rows + row
                        if index < shown.count {
                            appRow(shown[index], share: shown[index].total / top)
                        } else {
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        }
                    }
                }
            }
        }
    }

    private func appRow(_ app: ScreenTime.App, share: Double) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(app.name).font(.label).foregroundStyle(Ink.primary).lineLimit(1)
                Spacer(minLength: 8)
                Text("\(app.pickups) pickups").font(.small).foregroundStyle(Ink.faint).lineLimit(1)
                Text(ScreenTime.text(app.total)).font(.label.monospacedDigit()).foregroundStyle(Ink.primary)
                    .lineLimit(1).frame(minWidth: 62, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.track)
                    Capsule().fill(Ink.violet).frame(width: max(geo.size.width * share, 4))
                }
            }
            .frame(height: 5)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.line).frame(height: 1) }
    }
}
