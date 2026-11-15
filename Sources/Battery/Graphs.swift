import Charts
import Design
import SwiftUI

/// The charger's watts, second by second over the last two minutes.
struct LiveTrace: View {
    var trace: [Point]
    var now: Date
    var limit: Double?

    var body: some View {
        let top = max((trace.compactMap(\.watts).max() ?? 10) * 1.25, (limit ?? 0) * 1.15, 5)
        Chart {
            ForEach(trace, id: \.date) { point in
                AreaMark(x: .value("Time", point.date), yStart: .value("Floor", 0), yEnd: .value("Watts", point.watts ?? 0),
                         series: .value("Series", "fill"))
                    .foregroundStyle(LinearGradient(colors: [Ink.charge.opacity(0.28), Ink.charge.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", point.date), y: .value("Watts", point.watts ?? 0), series: .value("Series", "line"))
                    .foregroundStyle(Ink.charge)
                    .lineStyle(StrokeStyle(lineWidth: 1.6))
                    .interpolationMethod(.monotone)
            }
            if let limit {
                RuleMark(y: .value("Charger", limit))
                    .foregroundStyle(Ink.faint)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .bottom, alignment: .trailing, spacing: 3) {
                        Text("\(Int(limit)) W charger").font(.small).foregroundStyle(Ink.faint)
                    }
            }
        }
        .chartXScale(domain: now.addingTimeInterval(-120)...now)
        .chartYScale(domain: 0...top)
        .chartXAxis {
            AxisMarks(values: [now.addingTimeInterval(-120), now.addingTimeInterval(-60), now]) { value in
                let ago = value.as(Date.self).map { Int(now.timeIntervalSince($0).rounded()) } ?? 0
                AxisValueLabel(anchor: ago == 0 ? .topTrailing : ago >= 120 ? .topLeading : .top) {
                    Text(ago == 0 ? "now" : "\(ago / 60) min ago").font(.small).foregroundStyle(Ink.faint)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Ink.line)
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0) W").font(.small).foregroundStyle(Ink.faint) }
            }
        }
        .animation(nil, value: trace.count)
    }
}

/// One charge as a row: when and on what, its level from and to on a 0–100 track, its peak and how long it took.
struct ChargeRow: View {
    var session: ChargeSession
    var now: Date
    var width: Width
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.35, bounce: 0.12)) { open.toggle() }
            } label: {
                row.contentShape(.rect)
            }
            .buttonStyle(.plain)
            if open {
                SessionCurve(session: session)
                    .frame(height: 120)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Divided()
        }
    }

    private var row: some View {
        let stacked = width != .wide
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 20))
        return layout {
            HStack(spacing: 8) {
                if session.ongoing { Circle().fill(Ink.charge).frame(width: 7, height: 7) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 16)).foregroundStyle(session.ongoing ? Ink.charge : Ink.primary).lineLimit(1)
                    Text(Format.charger(session.adapterName, watts: session.adapterWatts, wireless: session.wireless))
                        .font(.label).foregroundStyle(Ink.secondary)
                }
                Spacer(minLength: 0)
                if stacked { chevron }
            }
            .frame(width: stacked ? nil : 200, alignment: .leading)

            HStack(spacing: 20) {
                column("Level", value: "\(Int(session.from))→\(Int(session.to))%") {
                    RangeTrack(from: session.from, to: session.to)
                }
                column("Peak", value: session.peakWatts.map { "\(Format.watts($0)) W" } ?? "–") {
                    SegmentBar(value: min((session.peakWatts ?? 0) / max(session.adapterWatts ?? 30, 5), 1), segments: 1,
                               color: Ink.charge, height: 4)
                }
                column("Time", value: Format.duration(session.duration)) {
                    HeldTrack(total: session.duration, held: session.held)
                }
                .frame(maxWidth: stacked ? .infinity : 150)
            }
            if !stacked { chevron }
        }
        .padding(.vertical, 16)
    }

    private var chevron: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Ink.faint)
            .rotationEffect(.degrees(open ? 180 : 0))
    }

    private var title: String {
        let day = Format.day(session.start, now: now)
        let hour = Calendar.current.component(.hour, from: session.start)
        if session.ongoing { return "Now\u{00A0}· since \(Format.time(session.start))" }
        if day == "Yesterday" && hour >= 20 { return "Last night\u{00A0}· \(Format.time(session.start))" }
        return "\(day)\u{00A0}· \(Format.time(session.start))"
    }

    private func column<Track: View>(_ label: String, value: String, @ViewBuilder track: () -> Track) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(label).font(.small).foregroundStyle(Ink.secondary).lineLimit(1)
                Spacer(minLength: 4)
                Text(value).font(.system(size: 13).monospacedDigit()).foregroundStyle(Ink.primary).lineLimit(1)
            }
            track()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Where a charge started and ended on the 0–100 scale.
struct RangeTrack: View {
    var from: Double
    var to: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.track)
                Capsule().fill(Ink.charge)
                    .frame(width: max(geo.size.width * (to - from) / 100, 4))
                    .offset(x: geo.size.width * from / 100)
            }
        }
        .frame(height: 4)
    }
}

/// How long a charge took against a 12-hour track, the part spent held striped.
struct HeldTrack: View {
    var total: TimeInterval
    var held: TimeInterval

    var body: some View {
        GeometryReader { geo in
            let length = geo.size.width * min(total / (12 * 3600), 1)
            let heldShare = total > 0 ? min(held / total, 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.track)
                HStack(spacing: 2) {
                    Capsule().fill(Ink.primary.opacity(0.75)).frame(width: max(length * (1 - heldShare), 4))
                    if heldShare > 0.02 {
                        Hatch(spacing: 3.5).stroke(Ink.amber, lineWidth: 1).clipShape(Capsule())
                            .frame(width: length * heldShare)
                    }
                }
            }
        }
        .frame(height: 4)
    }
}

/// A finished charge opened up: its level climbing and the watts it took.
struct SessionCurve: View {
    var session: ChargeSession

    var body: some View {
        let top = max(session.curve.compactMap(\.watts).max() ?? 10, 5) * 1.15
        Chart {
            ForEach(session.curve, id: \.date) { point in
                AreaMark(x: .value("Time", point.date), yStart: .value("Floor", 0),
                         yEnd: .value("Watts", (point.watts ?? 0) / top * 100), series: .value("Series", "watts"))
                    .foregroundStyle(Ink.charge.opacity(0.22))
            }
            ForEach(session.curve, id: \.date) { point in
                LineMark(x: .value("Time", point.date), y: .value("Level", point.percent), series: .value("Series", "level"))
                    .foregroundStyle(Ink.primary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Ink.line)
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%").font(.small).foregroundStyle(Ink.faint) }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) { Text(Format.time(date)).font(.small).foregroundStyle(Ink.faint) }
                }
            }
        }
    }
}

/// Percent used each day, with the percent charged beside it.
struct DayBars: View {
    var days: [Day]
    var now: Date

    var body: some View {
        let top = max(days.map { max($0.used, $0.charged) }.max() ?? 50, 50) * 1.1
        Chart {
            ForEach(days) { day in
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Used", day.used), width: .ratio(0.8))
                    .foregroundStyle(Ink.brand)
                    .position(by: .value("Kind", "Used"))
                    .clipShape(.rect(cornerRadius: 3))
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Charged", day.charged), width: .ratio(0.8))
                    .foregroundStyle(Ink.charge.opacity(0.85))
                    .position(by: .value("Kind", "Charged"))
                    .clipShape(.rect(cornerRadius: 3))
            }
            let average = days.dropLast().map(\.used).filter { $0 > 0 }
            if !average.isEmpty {
                RuleMark(y: .value("Average", average.reduce(0, +) / Double(average.count)))
                    .foregroundStyle(Ink.faint)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYScale(domain: 0...top)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Ink.line)
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%").font(.small).foregroundStyle(Ink.faint) }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisValueLabel(centered: true) {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(.dateTime.weekday(.narrow))).font(.small)
                            .foregroundStyle(Calendar.current.isDate(date, inSameDayAs: now) ? Ink.primary : Ink.faint)
                    }
                }
            }
        }
    }
}

/// When the phone is on the charger: weekdays down, hours across, darker for more of the hour plugged in.
struct HabitGrid: View {
    var habits: [[Double]]
    var now: Date

    var body: some View {
        let weeks = 4.0
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let today = Calendar.current.component(.weekday, from: now) - 1
        VStack(alignment: .leading, spacing: 5) {
            grid(symbols: symbols, today: today, weeks: weeks)
            HStack(spacing: 0) {
                ForEach([0, 6, 12, 18], id: \.self) { hour in
                    Text(hourLabel(hour)).font(.system(size: 10)).foregroundStyle(Ink.faint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.leading, 17)
        }
    }

    private func grid(symbols: [String], today: Int, weeks: Double) -> some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            ForEach(0..<7, id: \.self) { day in
                GridRow {
                    Text(symbols[day]).font(.small).foregroundStyle(day == today ? Ink.primary : Ink.faint).frame(width: 14)
                    ForEach(0..<24, id: \.self) { hour in
                        let share = min(habits[day][hour] / (60 * weeks), 1)
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(share < 0.04 ? Ink.track : Ink.charge.opacity(0.18 + share * 0.82))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: now)?.formatted(.dateTime.hour()) ?? ""
    }
}

/// How fast the battery usually drains at each hour of the day: the model behind time left. Hours it has barely seen
/// off the charger show faint, since their rate is mostly the overall average.
struct HourProfile: View {
    var rates: [Double]
    var seen: [Double]
    var now: Date

    var body: some View {
        let hour = Calendar.current.component(.hour, from: now)
        Chart {
            ForEach(0..<24, id: \.self) { h in
                if rates[h] > 0 {
                    RectangleMark(xStart: .value("From", Double(h) - 0.35), xEnd: .value("To", Double(h) + 0.35),
                                  yStart: .value("Floor", 0), yEnd: .value("Rate", rates[h]))
                        .foregroundStyle(h == hour ? Ink.brand : seen[h] < 0.5 ? Ink.track : Ink.primary.opacity(0.22))
                        .clipShape(.rect(cornerRadius: 2))
                }
            }
        }
        .chartXScale(domain: -0.5...23.5)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18]) { value in
                AxisValueLabel(anchor: .top) {
                    if let h = value.as(Int.self),
                       let date = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: now) {
                        Text(date.formatted(.dateTime.hour())).font(.small).foregroundStyle(Ink.faint)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Ink.line)
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%").font(.small).foregroundStyle(Ink.faint) }
            }
        }
    }
}

/// Maximum capacity from each Analytics file shared.
struct HealthTrend: View {
    var records: [HealthRecord]

    var body: some View {
        let values = records.compactMap(\.maximumCapacity)
        let low = max((values.min() ?? 80) - 3, 0), high = min((values.max() ?? 100) + 2, 101)
        Chart {
            ForEach(records.filter { $0.maximumCapacity != nil }) { record in
                LineMark(x: .value("Date", record.date), y: .value("Capacity", record.maximumCapacity ?? 0))
                    .foregroundStyle(Ink.charge)
                    .lineStyle(StrokeStyle(lineWidth: 1.6))
                PointMark(x: .value("Date", record.date), y: .value("Capacity", record.maximumCapacity ?? 0))
                    .foregroundStyle(Ink.charge)
                    .symbolSize(28)
            }
        }
        .chartYScale(domain: low...high)
        .chartXScale(range: .plotDimension(startPadding: 14, endPadding: 14))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Ink.line)
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%").font(.small).foregroundStyle(Ink.faint) }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(.dateTime.month(.abbreviated).day())).font(.small).foregroundStyle(Ink.faint)
                    }
                }
            }
        }
    }
}
