import Charts
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
        let ahead = forecast.map { min($0.date, now.addingTimeInterval(max(past * 0.6, 4 * 3600))) } ?? now
        let end = max(ahead, now.addingTimeInterval(past * 0.08))
        let path = (forecast?.path ?? []).filter { $0.date <= end }
        let charging = forecast.map { $0.target > 0 } ?? false
        let tint = charging ? Ink.charge : Ink.brand
        let spans = spans(since: start)

        Chart {
            ForEach(spans) { span in
                RectangleMark(xStart: .value("From", span.start), xEnd: .value("To", span.end),
                              yStart: .value("Low", 0), yEnd: .value("High", 100))
                    .foregroundStyle(span.held ? Ink.amber.opacity(0.10) : Ink.charge.opacity(0.10))
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
            if let forecast, forecast.date <= end, let last = path.last {
                PointMark(x: .value("Done", forecast.date), y: .value("Level", last.percent))
                    .foregroundStyle(tint)
                    .symbolSize(36)
                    .annotation(position: forecast.target > 0 ? .bottom : .top, alignment: .trailing, spacing: 6) {
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
        return spans
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
