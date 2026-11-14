import Foundation

/// One time on the charger.
nonisolated struct ChargeSession: Identifiable, Sendable, Hashable {
    var id: Date { start }
    var start: Date
    var end: Date
    var from: Double
    var to: Double
    var peakWatts: Double?
    var averageWatts: Double?
    /// Energy that went into the battery.
    var energy: Double?
    var adapterName: String?
    var adapterWatts: Double?
    var wireless: Bool
    var hottest: Double?
    /// Time plugged in with nothing going in.
    var held: TimeInterval
    var ongoing: Bool
    /// Level and charger watts through the session, for its sparkline.
    var curve: [Point]

    var duration: TimeInterval { end.timeIntervalSince(start) }
    var gained: Double { max(to - from, 0) }
}

nonisolated struct Point: Sendable, Hashable {
    var date: Date
    var percent: Double
    var watts: Double?
}

/// Percent used on battery and gained on the charger in one day.
nonisolated struct Day: Identifiable, Sendable, Hashable {
    var id: Date { date }
    var date: Date
    var used: Double
    var charged: Double
    var hoursOnBattery: Double
}

/// A run of time unplugged and how fast it drained.
nonisolated struct Drain: Sendable, Hashable {
    var start: Date
    var end: Date
    var from: Double
    var to: Double
    var hours: Double { end.timeIntervalSince(start) / 3600 }
    var rate: Double { hours > 0 ? max(from - to, 0) / hours : 0 }
}

/// A prediction: when the level reaches its target, the likely range around it, and the path it takes there.
nonisolated struct Forecast: Sendable, Hashable {
    var target: Double
    var date: Date
    var early: Date
    var late: Date
    var path: [Point]
    /// For time left: when it reaches 20%.
    var low: Date?
}

/// Everything worked out from saved readings. Pure, so the simulator's made-up readings run through the same code.
nonisolated struct Analysis: Sendable {
    var samples: [Sample]
    var sessions: [ChargeSession] = []
    var drains: [Drain] = []
    var days: [Day] = []
    /// Minutes plugged in, by weekday (0 Sunday) and hour, over the last four weeks.
    var habits: [[Double]] = Array(repeating: Array(repeating: 0, count: 24), count: 7)
    /// Percent an hour drained at each hour of the day.
    var drainByHour: [Double] = Array(repeating: 0, count: 24)
    /// Hours on battery each hour of the day has seen, weighted to the last ten days or so.
    var drainHoursSeen: [Double] = Array(repeating: 0, count: 24)
    var averageDrain = 5.0
    /// How much faster or slower than usual drains run: the 20th and 80th percentiles.
    var drainSpread = (low: 0.75, high: 1.3)
    /// Minutes a percent takes on the charger, in 5% bands.
    var chargeMinutes: [Double?] = Array(repeating: nil, count: 20)
    /// What a full battery holds, learned from charges, in watt-hours.
    var capacity: Double?
    /// The level charges stop at, when it's under 100: the charge limit.
    var chargeLimit: Double?

    init(_ samples: [Sample], now: Date = .now) {
        self.samples = samples
        guard samples.count > 1 else { return }
        let calendar = Calendar.current
        buildSessions(now: now)
        buildDays(calendar: calendar, now: now)
        buildHabits(calendar: calendar, now: now)
        buildDrainProfile(calendar: calendar, now: now)
        buildChargeProfile(now: now)
        chargeLimit = Self.limit(sessions)
    }

    // MARK: Sessions

    private mutating func buildSessions(now: Date) {
        var runStart = 0
        func close(_ end: Int) {
            let run = samples[runStart...end]
            guard let first = run.first, let last = run.last else { return }
            if first.s.pluggedIn {
                let watts = run.compactMap(\.w).filter { $0 > 0.5 }
                var energy = 0.0, held = 0.0
                for (a, b) in zip(run, run.dropFirst()) where b.t.timeIntervalSince(a.t) < 1800 {
                    let dt = b.t.timeIntervalSince(a.t)
                    if let w = a.b { energy += w * dt / 3600 }
                    if a.s == .held { held += dt }
                }
                let peak = Self.peak(watts)
                sessions.append(ChargeSession(
                    start: first.t, end: last.t, from: first.p, to: run.map(\.p).max() ?? last.p,
                    peakWatts: peak, averageWatts: watts.isEmpty ? nil : watts.reduce(0, +) / Double(watts.count),
                    energy: energy > 0.05 ? energy : nil,
                    adapterName: run.compactMap(\.an).last, adapterWatts: run.compactMap(\.aw).max(),
                    wireless: run.contains { $0.an == "magsafe chg" || $0.an == "baseline arcas" },
                    hottest: run.compactMap(\.tb).max(), held: held,
                    ongoing: end == samples.count - 1 && now.timeIntervalSince(last.t) < 900,
                    curve: Self.thin(run.map { Point(date: $0.t, percent: $0.p, watts: $0.w) }, to: 120)))
            } else if last.t > first.t {
                drains.append(Drain(start: first.t, end: last.t, from: first.p, to: last.p))
            }
        }
        for i in 1..<samples.count {
            let a = samples[i - 1], b = samples[i]
            // A rise while unplugged means a charge happened that no reading saw.
            let unseenCharge = !a.s.pluggedIn && !b.s.pluggedIn && b.p > a.p + 2
            if a.s.pluggedIn != b.s.pluggedIn || unseenCharge {
                close(i - 1)
                runStart = i
            }
        }
        close(samples.count - 1)
    }

    /// The median of the three highest readings, so a one-second spike isn't the peak.
    private static func peak(_ watts: [Double]) -> Double? {
        let top = watts.sorted(by: >).prefix(3)
        return top.isEmpty ? nil : top[top.index(top.startIndex, offsetBy: top.count / 2)]
    }

    static func thin(_ points: [Point], to count: Int) -> [Point] {
        guard points.count > count else { return points }
        let step = Double(points.count - 1) / Double(count - 1)
        return (0..<count).map { points[Int((Double($0) * step).rounded())] }
    }

    private static func limit(_ sessions: [ChargeSession]) -> Double? {
        let tops = sessions.suffix(8).filter { !$0.ongoing && $0.duration > 3600 }.map(\.to)
        guard tops.count >= 2 else { return nil }
        let counts = Dictionary(grouping: tops.filter { [80, 85, 90, 95].contains($0) }, by: { $0 }).mapValues(\.count)
        guard let (level, count) = counts.max(by: { $0.value < $1.value }), count * 2 >= tops.count else { return nil }
        return level
    }

    // MARK: Days and habits

    private mutating func buildDays(calendar: Calendar, now: Date) {
        var byDay: [Date: Day] = [:]
        for (a, b) in zip(samples, samples.dropFirst()) {
            let day = calendar.startOfDay(for: b.t)
            var entry = byDay[day] ?? Day(date: day, used: 0, charged: 0, hoursOnBattery: 0)
            if b.p < a.p { entry.used += a.p - b.p } else { entry.charged += b.p - a.p }
            if !a.s.pluggedIn, b.t.timeIntervalSince(a.t) < 12 * 3600 { entry.hoursOnBattery += b.t.timeIntervalSince(a.t) / 3600 }
            byDay[day] = entry
        }
        let today = calendar.startOfDay(for: now)
        days = (0..<14).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { byDay[$0] ?? Day(date: $0, used: 0, charged: 0, hoursOnBattery: 0) }
        }
    }

    private mutating func buildHabits(calendar: Calendar, now: Date) {
        let since = now.addingTimeInterval(-28 * 86400)
        for (a, b) in zip(samples, samples.dropFirst()) where a.s.pluggedIn && a.t >= since {
            var t = a.t
            let end = min(b.t, a.t.addingTimeInterval(2 * 3600))
            while t < end {
                let next = min(end, calendar.dateInterval(of: .hour, for: t)?.end ?? end)
                let parts = calendar.dateComponents([.weekday, .hour], from: t)
                habits[(parts.weekday ?? 1) - 1][parts.hour ?? 0] += next.timeIntervalSince(t) / 60
                t = next
            }
        }
    }

    // MARK: Drain

    private mutating func buildDrainProfile(calendar: Calendar, now: Date) {
        var drop = Array(repeating: 0.0, count: 24), hours = Array(repeating: 0.0, count: 24)
        var totalDrop = 0.0, totalHours = 0.0
        for (a, b) in zip(samples, samples.dropFirst()) where !a.s.pluggedIn && !b.s.pluggedIn && b.p <= a.p {
            let span = b.t.timeIntervalSince(a.t)
            guard span > 0, span < 12 * 3600 else { continue }
            let weight = exp(-now.timeIntervalSince(b.t) / (10 * 86400))
            let rate = (a.p - b.p) / span
            var t = a.t
            while t < b.t {
                let next = min(b.t, calendar.dateInterval(of: .hour, for: t)?.end ?? b.t)
                let hour = calendar.component(.hour, from: t)
                let seconds = next.timeIntervalSince(t)
                drop[hour] += rate * seconds * weight
                hours[hour] += seconds / 3600 * weight
                t = next
            }
            totalDrop += (a.p - b.p) * weight
            totalHours += span / 3600 * weight
        }
        if totalHours > 2 { averageDrain = max(totalDrop / totalHours, 0.3) }
        // Each hour leans on the overall rate until it has a couple of hours of its own.
        drainByHour = (0..<24).map { (drop[$0] + 1.5 * averageDrain) / (hours[$0] + 1.5) }
        drainHoursSeen = hours

        let ratios = drains.filter { $0.hours > 0.75 && $0.from - $0.to >= 3 }.suffix(30).map { drain in
            drain.rate / max(expectedRate(from: drain.start, to: drain.end, calendar: calendar), 0.1)
        }.sorted()
        if ratios.count >= 4 {
            drainSpread = (min(ratios[ratios.count / 5], 0.95), max(ratios[ratios.count * 4 / 5], 1.05))
        }
    }

    private func expectedRate(from start: Date, to end: Date, calendar: Calendar) -> Double {
        var t = start, total = 0.0
        while t < end {
            let next = min(end, t.addingTimeInterval(600))
            total += drainByHour[calendar.component(.hour, from: t)] * next.timeIntervalSince(t) / 3600
            t = next
        }
        return total / max(end.timeIntervalSince(start) / 3600, 0.01)
    }

    /// When the battery runs out at the usual rate for each hour, nudged toward how this stretch off the charger is going.
    func timeLeft(from reading: Reading) -> Forecast? {
        guard !reading.state.pluggedIn, reading.percent > 0 else { return nil }
        let calendar = Calendar.current
        var factor = 1.0
        if let current = drains.last, current.end.timeIntervalSince(reading.date) > -600,
           current.hours > 0.75, current.from - current.to >= 3 {
            let usual = expectedRate(from: current.start, to: current.end, calendar: calendar)
            factor = min(max(sqrt(current.rate / max(usual, 0.1)), 0.6), 1.7)
        }
        func run(_ scale: Double, keepPath: Bool) -> (end: Date, low: Date?, path: [Point]) {
            var t = reading.date, p = reading.percent, low: Date?
            var path = keepPath ? [Point(date: t, percent: p)] : []
            while p > 0, t.timeIntervalSince(reading.date) < 72 * 3600 {
                let rate = drainByHour[calendar.component(.hour, from: t)] * factor * scale
                let next = t.addingTimeInterval(300)
                let nextP = max(p - rate / 12, 0)
                if low == nil, p > 20, nextP <= 20 { low = next }
                t = next
                p = nextP
                if keepPath, Int(t.timeIntervalSince(reading.date)) % 1800 == 0 || p == 0 { path.append(Point(date: t, percent: p)) }
            }
            return (t, low, path)
        }
        let likely = run(1, keepPath: true)
        return Forecast(target: 0, date: likely.end, early: run(drainSpread.high, keepPath: false).end,
                        late: run(drainSpread.low, keepPath: false).end, path: likely.path, low: likely.low)
    }

    // MARK: Charge

    private mutating func buildChargeProfile(now: Date) {
        var minutes = Array(repeating: 0.0, count: 20), percents = Array(repeating: 0.0, count: 20)
        var energy = 0.0, gained = 0.0
        for (a, b) in zip(samples, samples.dropFirst()) where a.s == .charging && b.s == .charging && b.p >= a.p {
            let span = b.t.timeIntervalSince(a.t)
            guard span > 0, span < 1800 else { continue }
            let weight = exp(-now.timeIntervalSince(b.t) / (21 * 86400))
            let band = min(Int(a.p) / 5, 19)
            minutes[band] += span / 60 * weight
            percents[band] += (b.p - a.p) * weight
            if let w = a.b, w > 0 {
                energy += w * span / 3600
                gained += b.p - a.p
            }
        }
        chargeMinutes = (0..<20).map { percents[$0] >= 3 ? minutes[$0] / percents[$0] : nil }
        if gained >= 30 { capacity = energy / gained * 100 }
    }

    /// Minutes a percent takes in each band before any charge is recorded: steady to 80%, then tapering.
    private static func defaultMinutes(band: Int) -> Double {
        band < 16 ? 1.0 : 1.0 + Double(band - 15) * 0.55
    }

    /// When the battery is full (or at the charge limit), from how this phone charged before at each level and how
    /// fast this charge is going now.
    func timeToFull(from reading: Reading) -> Forecast? {
        guard reading.state == .charging else { return nil }
        let target = chargeLimit.flatMap { $0 > reading.percent ? $0 : nil } ?? 100
        guard reading.percent < target else { return nil }
        func shape(_ band: Int) -> Double { chargeMinutes[band] ?? Self.defaultMinutes(band: band) * (chargeMinutes.compactMap { $0 }.first ?? 1) }

        // How fast this charge runs against the usual, from the last 15 minutes of it.
        var factor = 1.0
        let recent = samples.reversed().prefix { $0.s == .charging && reading.date.timeIntervalSince($0.t) < 900 }
        if let newest = recent.first, let oldest = recent.last, newest.p - oldest.p >= 2 {
            let measured = newest.t.timeIntervalSince(oldest.t) / 60 / (newest.p - oldest.p)
            factor = min(max(measured / shape(min(Int(oldest.p) / 5, 19)), 0.4), 3)
        } else if let watts = reading.batteryWatts, watts > 0.5, let capacity {
            let measured = capacity / 100 / watts * 60
            factor = min(max(measured / shape(min(Int(reading.percent) / 5, 19)), 0.4), 3)
        }
        func run(_ scale: Double) -> (end: Date, path: [Point]) {
            var t = reading.date, path = [Point(date: t, percent: reading.percent)]
            var p = reading.percent
            while p < target {
                let step = min(1, target - p)
                t = t.addingTimeInterval(shape(min(Int(p) / 5, 19)) * factor * scale * 60 * step)
                p += step
                path.append(Point(date: t, percent: p))
            }
            return (t, path)
        }
        let likely = run(1)
        var date = likely.end
        if let powerd = reading.powerdMinutesToFull, target == 100 { date = reading.date.addingTimeInterval(powerd * 60) }
        return Forecast(target: target, date: date, early: run(0.85).end, late: run(1.2).end, path: likely.path)
    }
}
