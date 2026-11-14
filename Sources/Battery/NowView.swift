import SwiftUI

/// The battery right now: what it's doing in one sentence, the four figures that matter, today's level with the
/// forecast ahead, the charger live, and the last few charges.
struct NowView: View {
    @Environment(Monitor.self) private var monitor
    var width: Width

    var body: some View {
        let analysis = monitor.analysis
        let reading = monitor.live
        let forecast = reading.flatMap { analysis.timeToFull(from: $0) ?? analysis.timeLeft(from: $0) }

        VStack(alignment: .leading, spacing: 28) {
            if let reading {
                Headline(reading: reading, forecast: forecast, analysis: analysis, now: monitor.now, width: width)
                Figures(reading: reading, forecast: forecast, analysis: analysis, health: monitor.health.last, width: width)
            }
            if width == .wide {
                HStack(alignment: .top, spacing: 32) {
                    today(forecast).frame(maxWidth: .infinity)
                    side(reading).frame(width: 330)
                }
            } else {
                today(forecast)
                side(reading)
            }
            charges
        }
    }

    private func today(_ forecast: Forecast?) -> some View {
        Block(title: "Today", note: forecast.map { $0.target > 0 ? "and the charge ahead" : "and the hours ahead" }) {
            LevelChart(samples: monitor.samples, forecast: forecast, spread: monitor.analysis.drainSpread,
                       now: monitor.now, past: 18 * 3600, height: width == .narrow ? 200 : 250)
            HStack(spacing: 16) {
                Key(name: "Level") { Capsule().fill(Ink.primary).frame(height: 2) }
                Key(name: "Charging") { RoundedRectangle(cornerRadius: 2).fill(Ink.charge.opacity(0.25)) }
                Key(name: "Held") { Hatch(spacing: 3).stroke(Ink.amber, lineWidth: 1).clipShape(.rect(cornerRadius: 2)) }
                Key(name: "Forecast") {
                    Capsule().stroke(style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        .foregroundStyle(forecast.map { $0.target > 0 ? Ink.charge : Ink.brand } ?? Ink.brand).frame(height: 1)
                }
            }
        }
    }

    @ViewBuilder
    private func side(_ reading: Reading?) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            if let reading, reading.state == .charging, !monitor.trace.isEmpty {
                Block(title: "Live", note: "charger watts, last 2 min") {
                    LiveTrace(trace: monitor.trace, now: monitor.now, limit: reading.adapterWatts)
                        .frame(height: width == .narrow ? 130 : 150)
                }
            }
            if let reading {
                Block(title: "Right now") { Details(reading: reading, analysis: monitor.analysis, now: monitor.now) }
            }
        }
    }

    @ViewBuilder
    private var charges: some View {
        let recent = monitor.analysis.sessions.suffix(4).reversed()
        if !recent.isEmpty {
            Block(title: "Recent charges", note: "tap one for its curve") {
                VStack(spacing: 0) {
                    Divided()
                    ForEach(Array(recent)) { ChargeRow(session: $0, now: monitor.now, width: width) }
                }
            }
        }
    }
}

/// BROADCOM's lead: one sentence with the figure that matters in colour, and a quieter line under it.
struct Headline: View {
    var reading: Reading
    var forecast: Forecast?
    var analysis: Analysis
    var now: Date
    var width: Width

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sentence
                .font(.system(size: width == .narrow ? 30 : 38, weight: .regular))
                .tracking(-0.6)
                .foregroundStyle(Ink.primary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.system(size: 15))
                .foregroundStyle(Ink.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sentence: Text {
        let percent = Text("\(Int(reading.percent))%")
        switch reading.state {
        case .charging:
            let watts = (reading.inputWatts ?? reading.batteryWatts).map { Text("\(Format.watts($0)) W").foregroundStyle(Ink.charge) }
            let lead = watts.map { Text("Charging at \($0)") } ?? Text("Charging \(percent.foregroundStyle(Ink.charge))")
            guard let forecast else { return lead }
            let when = Text(Format.time(forecast.date)).foregroundStyle(Ink.brand)
            let target = forecast.target < 100 ? "\(Int(forecast.target))% by" : "full by"
            return Text("\(lead) \(Text("· \(target)").foregroundStyle(Ink.secondary)) \(when)")
        case .held:
            return Text("Held at \(percent.foregroundStyle(Ink.amber)) \(Text("· on the charger").foregroundStyle(Ink.secondary))")
        case .full:
            return Text("Full \(Text("· on the charger").foregroundStyle(Ink.secondary))")
        case .battery:
            let lead = percent.foregroundStyle(Ink.levelAccent(reading.percent))
            guard let forecast else { return Text("\(lead) on battery") }
            return Text("\(lead) lasts until \(Text(Format.when(forecast.date, now: now)).foregroundStyle(Ink.brand))")
        }
    }

    private var detail: String {
        switch reading.state {
        case .charging:
            var parts = [Format.charger(reading.adapterName, watts: reading.adapterWatts, wireless: reading.wireless)]
            if let forecast { parts.append("\(Format.duration(forecast.date.timeIntervalSince(reading.date))) to go") }
            if let session = analysis.sessions.last, session.ongoing { parts.append("plugged in at \(Format.time(session.start))") }
            return parts.joined(separator: " · ")
        case .held:
            return "Optimized Charging or the charge limit is holding it there"
        case .full:
            return analysis.sessions.last.map { "On the charger since \(Format.time($0.start))" } ?? "Nothing more to add"
        case .battery:
            guard let forecast else { return "Leave it running a while to learn how it drains" }
            let range = "most likely between \(Format.time(forecast.early)) and \(Format.time(forecast.late))"
            guard let low = forecast.low else { return range.prefix(1).uppercased() + range.dropFirst() }
            return "20% around \(Format.when(low, now: now)) · \(range)"
        }
    }
}

/// The four figures in a row, or two by two on the narrow screen.
struct Figures: View {
    var reading: Reading
    var forecast: Forecast?
    var analysis: Analysis
    var health: HealthRecord?
    var width: Width

    var body: some View {
        VStack(spacing: 0) {
            Divided()
            if width == .narrow {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow { cell(level, trailing: true); cell(power, trailing: false) }
                    GridRow { Divided().gridCellColumns(2) }
                    GridRow { cell(heat, trailing: true); cell(healthStat, trailing: false) }
                }
            } else {
                HStack(spacing: 0) {
                    cell(level, trailing: true)
                    cell(power, trailing: true)
                    cell(heat, trailing: true)
                    cell(healthStat, trailing: false)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            Divided()
        }
    }

    private func cell(_ content: some View, trailing: Bool) -> some View {
        HStack(spacing: 0) {
            content.padding(.vertical, 22).padding(.horizontal, width == .narrow ? 14 : 22)
            if trailing { Divided(vertical: true) }
        }
        .frame(maxHeight: .infinity)
    }

    private var level: some View {
        let charging = reading.state.pluggedIn
        return Stat(label: "Level", value: "\(Int(reading.percent))", unit: "%",
                    color: charging ? Ink.charge : Ink.level(reading.percent),
                    caption: levelCaption) {
            SegmentBar(value: reading.percent / 100, projected: forecast.flatMap { $0.target > 0 ? $0.target / 100 : nil },
                       color: charging ? Ink.charge : Ink.levelAccent(reading.percent))
        }
    }

    private var levelCaption: String {
        guard let forecast else { return reading.state == .held ? "Held below full" : reading.state == .full ? "Full" : "Learning" }
        if forecast.target > 0 { return "\(forecast.target < 100 ? "\(Int(forecast.target))%" : "Full") at \(Format.time(forecast.date))" }
        return forecast.low.map { "20% at \(Format.time($0))" } ?? "Empty at \(Format.time(forecast.date))"
    }

    @ViewBuilder
    private var power: some View {
        if reading.state.pluggedIn {
            let watts = reading.inputWatts ?? reading.batteryWatts ?? 0
            Stat(label: "Charger", value: Format.watts(watts), unit: "W", color: Ink.charge,
                 caption: reading.batteryWatts.map { "\(Format.watts($0)) W into the battery" } ?? "No current in") {
                SegmentBar(value: watts / max(reading.adapterWatts ?? 30, 5), segments: 4, color: Ink.charge)
            }
        } else {
            let hour = Calendar.current.component(.hour, from: reading.date)
            let usual = analysis.drainByHour[hour]
            let current = analysis.drains.last.flatMap { $0.hours > 0.5 ? $0.rate : nil } ?? usual
            Stat(label: "Drain", value: String(format: "%.1f", current), unit: "% an hour", color: Ink.brand,
                 caption: "Usual at this hour: \(String(format: "%.1f", usual))%") {
                SegmentBar(value: current / 16, projected: usual / 16, segments: 4, color: Ink.brand)
            }
        }
    }

    private var heat: some View {
        let battery = reading.batteryTemp
        return Stat(label: "Battery heat", value: battery.map { String(format: "%.1f", $0) } ?? "–", unit: "°C",
                    color: battery.map(Ink.temperature) ?? Ink.primary,
                    caption: reading.chipTemp.map { "Chip \(Format.degrees($0)) · \(thermal)" } ?? thermal.capitalized) {
            SegmentBar(value: ((battery ?? 20) - 20) / 25, segments: 5,
                       color: battery.map { $0 >= 38 ? Ink.temperature($0) : Ink.primary.opacity(0.7) } ?? Ink.track)
        }
    }

    private var thermal: String {
        ["nominal", "fair", "serious", "critical"][min(max(reading.thermal, 0), 3)]
    }

    private var healthStat: some View {
        Stat(label: "Health", value: health?.maximumCapacity.map { "\(Int($0))" } ?? "–", unit: "%",
             color: (health?.maximumCapacity ?? 100) < 80 ? Ink.bad : Ink.primary,
             caption: health.map { record in
                 [record.cycles.map { "\($0) cycles" }, Optional(record.date.formatted(.dateTime.month(.abbreviated).day()))]
                     .compactMap { $0 }.joined(separator: " · ")
             } ?? "Share Analytics in Health") {
            SegmentBar(value: (health?.maximumCapacity ?? 0) / 100, segments: 5, color: Ink.primary.opacity(0.7))
        }
    }
}

/// The figures under the figures, as label and value rows.
struct Details: View {
    var reading: Reading
    var analysis: Analysis
    var now: Date

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows, id: \.0) { row in
                HStack {
                    Text(row.0).foregroundStyle(Ink.secondary)
                    Spacer()
                    Text(row.1).foregroundStyle(Ink.primary).monospacedDigit()
                }
                .font(.system(size: 14))
                .padding(.vertical, 10)
                Divided()
            }
        }
    }

    private var rows: [(String, String)] {
        var rows: [(String, String)] = []
        if reading.state.pluggedIn {
            rows.append(("Charger", Format.charger(reading.adapterName, watts: reading.adapterWatts, wireless: reading.wireless)))
            if let v = reading.volts, let a = reading.amps { rows.append(("Input", String(format: "%.2f V × %.2f A", v, a))) }
            if let b = reading.batteryWatts { rows.append(("Into the battery", "\(Format.watts(b)) W")) }
            if let session = analysis.sessions.last, session.ongoing {
                rows.append(("This charge", "+\(Int(max(reading.percent - session.from, 0)))% in \(Format.duration(now.timeIntervalSince(session.start)))"))
            }
        } else if let drain = analysis.drains.last {
            rows.append(("Unplugged", "\(Format.when(drain.start, now: now)) at \(Int(drain.from))%"))
            rows.append(("Used since", "\(Int(max(drain.from - reading.percent, 0)))% in \(Format.duration(now.timeIntervalSince(drain.start)))"))
        }
        if let capacity = analysis.capacity { rows.append(("Holds", String(format: "%.1f Wh, learned", capacity))) }
        if let chip = reading.chipTemp { rows.append(("Chip", Format.degrees(chip))) }
        rows.append(("Low Power Mode", reading.lowPower ? "On" : "Off"))
        return rows
    }
}
