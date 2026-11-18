import Foundation

/// Everything the phone says about power at one moment.
nonisolated struct Reading: Sendable, Equatable {
    var date: Date
    var percent: Double
    var state: PowerState
    var inputWatts: Double?
    var batteryWatts: Double?
    var volts: Double?
    var amps: Double?
    var batteryTemp: Double?
    var chipTemp: Double?
    var adapterWatts: Double?
    var adapterName: String?
    var wireless = false
    var lowPower = false
    var thermal = 0
    /// powerd's own time to full, in minutes, when it gives one.
    var powerdMinutesToFull: Double?

    var sample: Sample {
        Sample(t: date, p: percent, s: state, w: inputWatts.map(round2), b: batteryWatts.map(round2), v: volts.map(round2),
               a: amps.map(round2), tb: batteryTemp.map(round1), tc: chipTemp.map(round1), aw: adapterWatts, an: adapterName,
               lp: lowPower ? true : nil, th: thermal > 0 ? thermal : nil)
    }

    private func round1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
    private func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }
}

/// What the public API knows, read on the main thread and handed to `Reader` for when the private ones say nothing.
nonisolated struct PublicPower: Sendable {
    var percent: Double?
    var pluggedIn: Bool
    var charging: Bool
    var full: Bool
    var lowPower: Bool
    var thermal: Int
}

/// Reads powerd and the sensors on a queue of its own. Temperatures, the slowest, are read at most every few seconds.
nonisolated final class Reader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.shahidy.battery.reader", qos: .utility)
    private let powerd = PowerD()
    private let sensors = Sensors()
    private var lastTemperatures: (date: Date, battery: Double?, chip: Double?) = (.distantPast, nil, nil)
    private var lastRescan = Date.distantPast

    func allPower() -> [(name: String, usage: Int, value: Double?)] {
        queue.sync { sensors?.allPower() ?? [] }
    }

    func read(_ fallback: PublicPower, temperatureEvery: TimeInterval = 5) async -> Reading {
        await withCheckedContinuation { continuation in
            queue.async { [self] in continuation.resume(returning: readNow(fallback, temperatureEvery: temperatureEvery)) }
        }
    }

    private func readNow(_ fallback: PublicPower, temperatureEvery: TimeInterval) -> Reading {
        let now = Date()
        let battery = powerd?.battery()
        let percent = (battery?["Current Capacity"] as? NSNumber)?.doubleValue ?? fallback.percent ?? 0
        let external = (battery?["Power Source State"] as? String).map { $0 == "AC Power" } ?? fallback.pluggedIn
        let charging = (battery?["Is Charging"] as? NSNumber)?.boolValue ?? fallback.charging
        let charged = (battery?["Is Charged"] as? NSNumber)?.boolValue ?? fallback.full

        let state: PowerState = !external ? .battery
            : charging ? .charging
            : charged || percent >= 100 ? .full
            : .held
        var reading = Reading(date: now, percent: percent, state: state, lowPower: fallback.lowPower, thermal: fallback.thermal)
        if let minutes = (battery?["Time to Full Charge"] as? NSNumber)?.doubleValue, minutes > 0, minutes < 65535, charging {
            reading.powerdMinutesToFull = minutes
        }

        if let sensors {
            if now.timeIntervalSince(lastRescan) > 60 {
                sensors.rescan()
                lastRescan = now
            }
            let power = sensors.readPower()
            let batteryVolts = ["Charger VQ0l", "PMU VP0u"].lazy.compactMap { power[$0] }.first { (3.2...4.7).contains($0) }
            if let into = power["Charger IQ0B"], let batteryVolts, into > 0.02, external {
                reading.batteryWatts = into * batteryVolts
            }
            if let volts = power["Charger VQ0u"], let amps = power["Charger IQ0u"], volts > 3, external {
                reading.volts = volts
                reading.amps = max(amps, 0)
                reading.inputWatts = volts * max(amps, 0)
            } else if let coil = power["Charger VQ1u"], coil > 5, external {
                // No sensor measures wireless input current, so the battery's share stands in for it.
                reading.wireless = true
                reading.volts = coil
                reading.inputWatts = reading.batteryWatts
            }
            if now.timeIntervalSince(lastTemperatures.date) >= temperatureEvery {
                let t = sensors.readTemperatures()
                lastTemperatures = (now, t.battery, t.chip)
            }
            reading.batteryTemp = lastTemperatures.battery
            reading.chipTemp = lastTemperatures.chip
        }

        if external, let adapter = powerd?.adapter() {
            let watts = (adapter["Watts"] as? NSNumber)?.doubleValue
            if let watts, watts > 0 { reading.adapterWatts = watts }
            if let name = adapter["Description"] as? String, !name.isEmpty { reading.adapterName = name }
            if reading.adapterName == "magsafe chg" || reading.adapterName == "baseline arcas" { reading.wireless = true }
        }
        return reading
    }
}
