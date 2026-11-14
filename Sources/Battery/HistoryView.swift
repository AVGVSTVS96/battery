import Design
import SwiftUI

/// The past: the level over a day, a week or four, use and charge per day, when you charge, how drain runs through
/// the day, and every charge.
struct HistoryView: View {
    @Environment(Monitor.self) private var monitor
    var width: Width
    @State private var range = Range.allCases.first { $0.rawValue.lowercased().hasPrefix(Demo.range ?? "week") } ?? .week

    enum Range: String, CaseIterable, Identifiable {
        case day = "Day", week = "Week", month = "4 Weeks"
        var id: Self { self }
        var seconds: TimeInterval {
            switch self {
            case .day: 86400
            case .week: 7 * 86400
            case .month: 28 * 86400
            }
        }
    }

    var body: some View {
        let analysis = monitor.analysis
        VStack(alignment: .leading, spacing: 32) {
            headline(analysis)
            Card {
                Block(title: "Level") {
                    Picker("Range", selection: $range) {
                        ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                    LevelChart(samples: monitor.samples, forecast: nil, spread: analysis.drainSpread, now: monitor.now,
                               past: range.seconds, height: width == .narrow ? 200 : 240)
                        .animation(.smooth(duration: 0.35), value: range)
                }
            }
            pair {
                Block(title: "Use per day", note: perDay(analysis).map { "two weeks\u{00A0}· average \($0)%" } ?? "two weeks") {
                    DayBars(days: analysis.days, now: monitor.now).frame(height: 170)
                    HStack(spacing: 16) {
                        Key(name: "Used") { RoundedRectangle(cornerRadius: 2).fill(Ink.brand) }
                        Key(name: "Charged") { RoundedRectangle(cornerRadius: 2).fill(Ink.charge) }
                    }
                }
            } second: {
                Block(title: "When you charge", note: "last four weeks") {
                    HabitGrid(habits: analysis.habits, now: monitor.now)
                }
            }
            pair {
                Block(title: "Drain by hour", note: "what time left is worked out from") {
                    HourProfile(rates: analysis.drainByHour, seen: analysis.drainHoursSeen, now: monitor.now).frame(height: 150)
                }
            } second: {
                Block(title: "Charge speed", note: "minutes per percent, by level") {
                    ChargeSpeed(minutes: analysis.chargeMinutes).frame(height: 150)
                }
            }
            ScreenTimeBlock(now: monitor.now)
            Block(title: "Charges", note: analysis.sessions.first.map {
                "\(analysis.sessions.count) since \($0.start.formatted(.dateTime.month(.abbreviated).day()))"
            }) {
                VStack(spacing: 0) {
                    Divided()
                    ForEach(analysis.sessions.reversed().prefix(30)) { ChargeRow(session: $0, now: monitor.now, width: width) }
                }
            }
        }
    }

    @ViewBuilder
    private func pair(@ViewBuilder _ first: () -> some View, @ViewBuilder second: () -> some View) -> some View {
        if width == .narrow {
            VStack(alignment: .leading, spacing: 32) { first(); second() }
        } else {
            HStack(alignment: .top, spacing: 32) { first(); second() }
        }
    }

    private func perDay(_ analysis: Analysis) -> Int? {
        let used = analysis.days.dropLast().map(\.used).filter { $0 > 0 }
        return used.isEmpty ? nil : Int((used.reduce(0, +) / Double(used.count)).rounded())
    }

    private func headline(_ analysis: Analysis) -> some View {
        let perDay = perDay(analysis)
        let week = analysis.sessions.filter { monitor.now.timeIntervalSince($0.start) < 7 * 86400 }.count
        let lasts = 100 / analysis.averageDrain
        return VStack(alignment: .leading, spacing: 8) {
            Text("A full charge lasts about \(Text(Format.glue("\(Int(lasts.rounded())) h")).foregroundStyle(Ink.brand))\u{00A0}\(Text(Format.glue("· \(week) charges this week")).foregroundStyle(Ink.secondary))")
                .font(.system(size: width == .narrow ? 30 : 38))
                .tracking(-0.6)
                .foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let perDay {
                Text("You use \(perDay)% a day on average, \(String(format: "%.1f", analysis.averageDrain))% an hour off the charger")
                    .font(.system(size: 15)).foregroundStyle(Ink.secondary)
            }
        }
    }
}

/// Minutes each percent takes on the charger, by level: flat while it charges fast, rising where it tapers.
struct ChargeSpeed: View {
    var minutes: [Double?]

    var body: some View {
        let known = minutes.compactMap { $0 }
        let top = max(known.max() ?? 3, 1) * 1.1
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<20, id: \.self) { band in
                    let value = minutes[band]
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        if let value {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(band >= 16 ? Ink.amber : Ink.charge)
                                .frame(height: max((geo.size.height - 18) * value / top, 2))
                        } else {
                            RoundedRectangle(cornerRadius: 2).fill(Ink.track).frame(height: 2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: geo.size.height - 18)
            .overlay(alignment: .topLeading) {
                if let fast = known.first {
                    Text(String(format: "%.1f min a percent at the start", fast)).font(.small).foregroundStyle(Ink.secondary)
                        .offset(y: -2)
                }
            }
            HStack {
                Text("0%"); Spacer(); Text("50%"); Spacer(); Text("100%")
            }
            .font(.small).foregroundStyle(Ink.faint)
            .offset(y: geo.size.height - 14)
        }
    }
}
