import Foundation

/// Where the phone's power comes from at a moment.
nonisolated enum PowerState: String, Codable, Sendable {
    case battery, charging, full
    /// Plugged in below full with nothing going into the battery: Optimized Charging or the charge limit.
    case held

    var pluggedIn: Bool { self != .battery }
}

/// One saved reading. Short keys keep months of them small on disk.
nonisolated struct Sample: Codable, Hashable, Sendable {
    var t: Date
    /// Battery level, 0 to 100.
    var p: Double
    var s: PowerState
    /// Watts coming in from the charger.
    var w: Double?
    /// Watts going into the battery.
    var b: Double?
    /// Charger voltage and current.
    var v: Double?
    var a: Double?
    /// Battery and hottest chip temperature, °C.
    var tb: Double?
    var tc: Double?
    /// The charger's advertised watts and what powerd calls it ("pd charger", "magsafe chg").
    var aw: Double?
    var an: String?
    /// Low Power Mode.
    var lp: Bool?
    /// ProcessInfo.ThermalState's raw value.
    var th: Int?

    var date: Date { t }
    var percent: Double { p }
    var state: PowerState { s }
}

nonisolated extension Sample {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
