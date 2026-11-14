import Foundation

/// Battery health from one day's Analytics file (Settings › Privacy & Security › Analytics & Improvements › Analytics
/// Data › Analytics-<date>), the only place iOS writes it where you can reach it.
nonisolated struct HealthRecord: Codable, Hashable, Sendable, Identifiable {
    var id: Date { date }
    var date: Date
    /// What Settings › Battery shows as Maximum Capacity.
    var maximumCapacity: Double?
    var cycles: Int?
    /// mAh the battery holds now, and held new.
    var rawMaxCapacity: Double?
    var designCapacity: Double?
    /// The day's highest and lowest level.
    var dailyMax: Double?
    var dailyMin: Double?

    /// Reads the `last_value_…` keys battery health is logged under. Nil when the text has none.
    static func parse(_ text: String) -> HealthRecord? {
        func value(_ key: String) -> Double? {
            guard let range = text.range(of: "\"\(key)\":") else { return nil }
            let rest = text[range.upperBound...].drop { $0 == " " || $0 == "\"" }
            return Double(rest.prefix { $0.isNumber || $0 == "." || $0 == "-" })
        }
        var record = HealthRecord(date: date(in: text) ?? .now)
        record.maximumCapacity = value("last_value_MaximumCapacityPercent")
        record.cycles = value("last_value_CycleCount").map { Int($0) }
        record.rawMaxCapacity = value("last_value_AppleRawMaxCapacity") ?? value("last_value_NominalChargeCapacity")
        record.designCapacity = value("last_value_MaximumFCC") ?? value("last_value_DesignCapacity")
        record.dailyMax = value("last_value_DailyMaxSoc") ?? value("DailyMaxSoc")
        record.dailyMin = value("last_value_DailyMinSoc") ?? value("DailyMinSoc")
        if record.maximumCapacity == nil, let raw = record.rawMaxCapacity, let design = record.designCapacity, design > 0 {
            record.maximumCapacity = (raw / design * 100).rounded()
        }
        return record.maximumCapacity == nil && record.cycles == nil ? nil : record
    }

    /// The file's own date: its header's "timestamp", or the first yyyy-MM-dd in it.
    private static func date(in text: String) -> Date? {
        let head = String(text.prefix(4000))
        guard let match = head.firstMatch(of: /(\d{4})-(\d{2})-(\d{2})/) else { return nil }
        return DateComponents(calendar: .current, year: Int(match.1), month: Int(match.2), day: Int(match.3), hour: 12).date
    }

    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "health.json")
    }

    static func load() -> [HealthRecord] {
        (try? Data(contentsOf: url)).flatMap { try? Sample.decoder.decode([HealthRecord].self, from: $0) } ?? []
    }

    static func save(_ records: [HealthRecord]) {
        try? Sample.encoder.encode(records).write(to: url, options: .atomic)
    }
}
