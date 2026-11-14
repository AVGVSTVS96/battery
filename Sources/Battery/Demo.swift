import Foundation

/// Three weeks of made-up readings for simulator screenshots, behind `-demo charging` or `-demo battery`. The simulator
/// has no battery to read, and a fixed history makes two runs of one build draw the same pixels.
enum Demo {
    static let scene: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let at = arguments.firstIndex(of: "-demo"), arguments.indices.contains(at + 1) else { return nil }
        return arguments[at + 1]
    }()
    static var isOn: Bool { scene != nil }
    /// `-page history` opens on that page.
    static let page: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let at = arguments.firstIndex(of: "-page"), arguments.indices.contains(at + 1) else { return nil }
        return arguments[at + 1]
    }()
    static var charging: Bool { scene != "battery" }

    /// 9:41 on Saturday, November 14, 2026, the status bar's time.
    static let now = DateComponents(calendar: .current, year: 2026, month: 11, day: 14, hour: 9, minute: 41).date!

    static let reading: Reading = {
        let last = samples.last
        guard charging, let last else {
            return Reading(date: now, percent: last?.p ?? 81, state: .battery, batteryTemp: 30.4, chipTemp: 36.2)
        }
        return Reading(date: now, percent: last.p, state: .charging, inputWatts: last.w, batteryWatts: last.b, volts: 9.02,
                       amps: (last.w ?? 0) / 9.02, batteryTemp: last.tb, chipTemp: last.tc, adapterWatts: 30, adapterName: "pd charger")
    }()

    static let trace: [Point] = charging ? (0..<120).map { i in
        let t = now.addingTimeInterval(Double(i - 119))
        let wave = sin(Double(i) / 7) * 0.35 + sin(Double(i) / 2.3) * 0.18
        return Point(date: t, percent: reading.percent, watts: (reading.inputWatts ?? 15) + wave + (i > 84 && i < 92 ? -1.4 : 0))
    } : []

    static let health: [HealthRecord] = (0..<7).map { i in
        let date = Calendar.current.date(byAdding: .day, value: -(6 - i) * 9, to: now)!
        return HealthRecord(date: date, maximumCapacity: [96, 96, 95, 95, 95, 94, 94][i], cycles: 168 + i * 8,
                            rawMaxCapacity: [4802, 4790, 4771, 4760, 4744, 4731, 4718][i], designCapacity: 5003)
    }

    /// `-offset 760` opens the page scrolled down that far.
    static let offset: CGFloat = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let at = arguments.firstIndex(of: "-offset"), arguments.indices.contains(at + 1) else { return 0 }
        return CGFloat(Double(arguments[at + 1]) ?? 0)
    }()

    static let samples: [Sample] = {
        var maker = Maker()
        return maker.make()
    }()

    /// Lives a made-up three weeks minute by minute: nights on a 20 W charger with Optimized Charging holding at 80%,
    /// a MagSafe top-up now and then, and days that drain fastest in the evening.
    private struct Maker {
        var seed: UInt64 = 0x2545F4914F6CDD1D
        var samples: [Sample] = []
        let capacity = 18.6

        mutating func random() -> Double {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Double(seed % 10_000) / 10_000
        }

        func drain(_ hour: Int) -> Double {
            switch hour {
            case 0..<7: 0.5
            case 7..<9: 4.2
            case 9..<12: 3.4
            case 12..<14: 4.6
            case 14..<18: 3.6
            case 18..<23: 5.4
            default: 2.4
            }
        }

        /// Charger watts at a level on a charger of `limit` watts: steady to about half, tapering to a trickle at full.
        func watts(_ percent: Double, limit: Double) -> Double {
            let peak = min(limit * 0.68, 20.5)
            if percent < 50 { return peak }
            if percent < 80 { return peak - (percent - 50) / 30 * (peak - 11) }
            return max(11 - (percent - 80) / 20 * 9, 1.6)
        }

        mutating func make() -> [Sample] {
            let calendar = Calendar.current
            let end = Demo.now
            let today = calendar.startOfDay(for: end)
            var t = calendar.date(byAdding: .day, value: -21, to: today)!.addingTimeInterval(7.5 * 3600)
            var p = 100.0
            var lastSaved = Date.distantPast
            var dayFactor = 1.0, factorDay = Date.distantPast

            func save(_ s: Sample) {
                samples.append(s)
                lastSaved = s.t
            }

            while t < end {
                let hour = calendar.component(.hour, from: t)
                let day = calendar.startOfDay(for: t)
                let isToday = day == today
                let nightPlug = calendar.date(bySettingHour: 23, minute: Int(random() * 50), second: 0, of: day)!
                // In the charging story last night's charge was missed, so the morning starts low.
                let skipNight = Demo.charging && calendar.isDate(t, inSameDayAs: today.addingTimeInterval(-3600))
                let middayTopUp = random() < 0.35 && hour == 13 && !isToday && !skipNight
                let morningCharge = isToday && Demo.charging && t >= today.addingTimeInterval(9 * 3600)

                if morningCharge || middayTopUp || (t >= nightPlug && !skipNight && p < 70) {
                    let magsafe = middayTopUp && random() < 0.6
                    let limit = morningCharge ? 30.0 : magsafe ? 15 : 20
                    let name = magsafe ? "magsafe chg" : "pd charger"
                    let night = !morningCharge && !middayTopUp
                    let unplugAt = morningCharge ? end
                        : middayTopUp ? t.addingTimeInterval(Double(25 + Int(random() * 25)) * 60)
                        : calendar.date(bySettingHour: 7, minute: 5 + Int(random() * 40), second: 0, of: day.addingTimeInterval(86400 + 3600))!
                    let finishBy = unplugAt.addingTimeInterval(-50 * 60)
                    var temp = 29.0 + random() * 2
                    while t < unplugAt && t < end {
                        let holding = night && p >= 80 && t < finishBy.addingTimeInterval(-Double(100 - p) * 2.4 * 60)
                        var state: PowerState = p >= 100 ? .full : holding ? .held : .charging
                        var w: Double? = nil, b: Double? = nil
                        if state == .charging {
                            let input = watts(p, limit: limit) * (magsafe ? 0.62 : 1) * (0.97 + random() * 0.06)
                            w = input
                            b = input * 0.88
                            p = min(p + b! / capacity * 100 / 60, 100)
                            temp = min(temp + (input > 12 ? 0.09 : -0.03), magsafe ? 37.5 : 35.5)
                        } else {
                            if state == .full { w = 0.9 }
                            temp = max(temp - 0.05, 27.5)
                        }
                        if p >= 100 && state == .charging { state = .full }
                        let rounded = p.rounded(.down)
                        if t.timeIntervalSince(lastSaved) >= 60 || samples.last?.p != rounded || samples.last?.s != state {
                            save(Sample(t: t, p: rounded, s: state, w: w.map { ($0 * 100).rounded() / 100 },
                                        b: b.map { ($0 * 100).rounded() / 100 }, v: w.map { _ in magsafe ? 14.1 : 9.0 },
                                        a: w.map { $0 / (magsafe ? 14.1 : 9.0) }, tb: (temp * 10).rounded() / 10,
                                        tc: ((temp + 6 + random() * 3) * 10).rounded() / 10, aw: limit, an: name))
                        }
                        t.addTimeInterval(60)
                    }
                    if t >= end { break }
                    save(Sample(t: t, p: p.rounded(.down), s: .battery, tb: (temp * 10).rounded() / 10))
                    continue
                }

                if day != factorDay {
                    factorDay = day
                    dayFactor = 0.7 + random() * 0.7
                }
                let rate = drain(hour) * dayFactor * (0.8 + random() * 0.4) * (calendar.component(.weekday, from: t) == 7 ? 1.15 : 1)
                let step = Double(10 + Int(random() * 25)) * 60
                p = max(p - rate * step / 3600, 3)
                t.addTimeInterval(step)
                if t >= end { break }
                if random() < 0.55 || p.rounded(.down) <= 20 {
                    save(Sample(t: t, p: p.rounded(.down), s: .battery, tb: ((29 + random() * 3) * 10).rounded() / 10,
                                lp: p < 20 ? true : nil))
                }
            }
            return samples
        }
    }
}
