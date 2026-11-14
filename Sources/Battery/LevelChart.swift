import Charts
import Design
import SwiftUI

/// The battery's level over a stretch of time, charges shaded under it, and, from now, the forecast as a dashed line
/// inside the band it will likely fall in.
struct LevelChart: View {
    var samples: [Sample]
    var forecast: Forecast?
    var spread: (low: Double, high: Double)
    var now: Date
    var past: TimeInterval
    var height: CGFloat = 220

    private struct Span: Identifiable {
        var id: Date { start }
        var start: Date
        var end: Date
        var held: Bool
    }

    var body: some View {
        let start = now.addingTimeInterval(-past)
        let history = Analysis.thin(points(since: start), to: 360)
        let ahead = forecast.map { min($0.date, now.addingTimeInterval(2 * 86400)) } ?? now
        let path = (forecast?.path ?? []).filter { $0.date <= ahead }
        let end = max(ahead.addingTimeInterval(ahead.timeIntervalSince(start) * 0.1), now.addingTimeInterval(past * 0.04))
        let charging = forecast.map { $0.target > 0 } ?? false
        let tint = charging ? Ink.charge : Ink.brand
        let spans = spans(since: start)

        VStack(alignment: .leading, spacing: 12) {
            chart(start: start, end: end, ahead: ahead, history: history, path: path, spans: spans, charging: charging, tint: tint)
            HStack(spacing: 16) {
                Key(name: "Level") { Capsule().fill(Ink.primary).frame(height: 2) }
                if spans.contains(where: { !$0.held }) {
                    Key(name: "Charging") { RoundedRectangle(cornerRadius: 2).fill(Ink.charge.opacity(0.14)) }
                }
                if spans.contains(where: \.held) {
                    Key(name: "Held") { Hatch(spacing: 3).stroke(Ink.amber, lineWidth: 1).clipShape(.rect(cornerRadius: 2)) }
                }
                if !path.isEmpty {
                    Key(name: "Forecast") {
                        Capsule().stroke(style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])).foregroundStyle(tint).frame(height: 1)
                    }
                }
            }
        }
    }

    private func chart(start: Date, end: Date, ahead: Date, history: [Point], path: [Point], spans: [Span], charging: Bool,
                       tint: Color) -> some View {
        Chart {
            ForEach(spans) { span in
                RectangleMark(xStart: .value("From", span.start), xEnd: .value("To", span.end),
                              yStart: .value("Low", 0), yEnd: .value("High", 100))
                    .foregroundStyle(span.held ? Ink.amber.opacity(0.10) : Ink.charge.opacity(0.14))
            }
            ForEach(history, id: \.date) { point in
                AreaMark(x: .value("Time", point.date), yStart: .value("Floor", 0), yEnd: .value("Level", point.percent),
                         series: .value("Series", "history"))
                    .foregroundStyle(LinearGradient(colors: [Ink.primary.opacity(0.10), Ink.primary.opacity(0.01)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.linear)
            }
            ForEach(history, id: \.date) { point in
                LineMark(x: .value("Time", point.date), y: .value("Level", point.percent), series: .value("Series", "history"))
                    .foregroundStyle(Ink.primary)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            }
            if let first = path.first {
                ForEach(path, id: \.date) { point in
                    let band = band(point, from: first.percent, charging: charging)
                    AreaMark(x: .value("Time", point.date), yStart: .value("Early", band.0), yEnd: .value("Late", band.1),
                             series: .value("Series", "band"))
                        .foregroundStyle(tint.opacity(0.16))
                }
                ForEach(path, id: \.date) { point in
                    LineMark(x: .value("Time", point.date), y: .value("Level", point.percent), series: .value("Series", "forecast"))
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [4, 4]))
                }
            }
            RuleMark(x: .value("Now", now))
                .foregroundStyle(Ink.faint)
                .lineStyle(StrokeStyle(lineWidth: 1))
            if let last = history.last {
                PointMark(x: .value("Now", now), y: .value("Level", last.percent))
                    .foregroundStyle(charging ? Ink.charge : Ink.primary)
                    .symbolSize(44)
            }
            if let forecast, forecast.date <= ahead, let last = path.last {
                PointMark(x: .value("Done", forecast.date), y: .value("Level", last.percent))
                    .foregroundStyle(tint)
                    .symbolSize(36)
                    .annotation(position: forecast.target > 0 ? .bottomTrailing : .topTrailing, spacing: 4) {
                        Text(Format.time(forecast.date)).font(.small.weight(.medium)).foregroundStyle(tint)
                    }
            }
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Ink.line)
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%").font(.small).foregroundStyle(Ink.faint) }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: past > 3 * 86400 ? .day : .hour, count: past > 3 * 86400 ? 1 : past > 12 * 3600 ? 6 : 3)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(past > 3 * 86400 ? date.formatted(.dateTime.weekday(.narrow)) : date.formatted(.dateTime.hour()))
                            .font(.small).foregroundStyle(Ink.faint)
                    }
                }
            }
        }
        .chartBackground { proxy in
            GeometryReader { geo in
                if let plot = proxy.plotFrame.map({ geo[$0] }) {
                    ForEach(spans.filter(\.held)) { span in
                        if let x0 = proxy.position(forX: span.start), let x1 = proxy.position(forX: span.end) {
                            Hatch(spacing: 5)
                                .stroke(Ink.amber.opacity(0.45), lineWidth: 1)
                                .frame(width: max(x1 - x0, 1), height: plot.height)
                                .clipped()
                                .offset(x: plot.minX + x0, y: plot.minY)
                        }
                    }
                }
            }
        }
        .frame(height: height)
    }

    private func points(since start: Date) -> [Point] {
        var points = samples.drop { $0.t < start }.map { Point(date: $0.t, percent: $0.p) }
        if let before = samples.last(where: { $0.t < start }) { points.insert(Point(date: start, percent: before.p), at: 0) }
        if let last = points.last, last.date < now { points.append(Point(date: now, percent: last.percent)) }
        return points
    }

    /// Spans on the charger, merged where readings sit close together, with Optimized Charging's holds split out.
    private func spans(since start: Date) -> [Span] {
        var spans: [Span] = []
        let window = samples.drop { $0.t < start.addingTimeInterval(-3600) }
        for (a, b) in zip(window, window.dropFirst()) where a.s.pluggedIn && b.t.timeIntervalSince(a.t) < 3 * 3600 {
            let held = a.s == .held
            let from = max(a.t, start)
            guard b.t > from else { continue }
            if let last = spans.last, last.held == held, from.timeIntervalSince(last.end) < 180 {
                spans[spans.count - 1].end = b.t
            } else {
                spans.append(Span(start: from, end: b.t, held: held))
            }
        }
        return Self.absorbBlips(spans)
    }

    /// A few minutes of charging inside a hold is the phone topping itself up, not a charge of its own.
    private static func absorbBlips(_ spans: [Span]) -> [Span] {
        var spans = spans
        for i in spans.indices.dropFirst().dropLast() where !spans[i].held && spans[i - 1].held && spans[i + 1].held
            && spans[i].end.timeIntervalSince(spans[i].start) < 900 {
            spans[i].held = true
        }
        return spans.reduce(into: []) { merged, span in
            if let last = merged.last, last.held == span.held, span.start.timeIntervalSince(last.end) < 600 {
                merged[merged.count - 1].end = span.end
            } else {
                merged.append(span)
            }
        }
    }

    /// The likely range at a point of the forecast: the change so far, scaled by how fast or slow it usually runs.
    private func band(_ point: Point, from start: Double, charging: Bool) -> (Double, Double) {
        let change = point.percent - start
        if charging {
            let target = forecast?.target ?? 100
            return (start + change / 1.2, min(start + change / 0.85, target))
        }
        return (max(start + change * spread.high, 0), start + change * spread.low)
    }
}
