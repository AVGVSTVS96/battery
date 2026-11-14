import Foundation

enum Format {
    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    /// "10:24 AM" today, "Sun 7:10 AM" within the week, else "Nov 3".
    static func when(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return time(date) }
        if abs(date.timeIntervalSince(now)) < 6 * 86400 { return date.formatted(.dateTime.weekday(.abbreviated).hour().minute()) }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "Today", "Yesterday", "Thursday", "Nov 3".
    static func day(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        if now.timeIntervalSince(date) < 6 * 86400 { return date.formatted(.dateTime.weekday(.wide)) }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "43 min", "2 h 10 min", "9 h".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(max(minutes, 1)) min" }
        let h = minutes / 60, m = minutes % 60
        if h >= 10 || m == 0 { return "\(h) h" }
        return "\(h) h \(m) min"
    }

    static func watts(_ watts: Double) -> String {
        watts >= 10 ? String(format: "%.1f", watts) : String(format: "%.2f", watts)
    }

    static func degrees(_ celsius: Double) -> String { String(format: "%.1f°", celsius) }

    /// What powerd calls a charger, in words.
    static func charger(_ name: String?, watts: Double?, wireless: Bool) -> String {
        let kind = switch name {
        case "magsafe chg": "MagSafe"
        case "baseline arcas": "Qi pad"
        case "pd charger", "usb type-c": "USB-C"
        case "usb charger": "USB"
        default: wireless ? "Wireless" : "Charger"
        }
        guard let watts, watts > 0 else { return kind }
        return "\(Int(watts.rounded())) W \(kind)"
    }
}
