import AppIntents

/// Saves a reading from Shortcuts without opening the app. A personal automation on "Charger is connected" and "is
/// disconnected" running it fills in the charges and drains the app would otherwise miss while closed.
struct RecordBattery: AppIntent {
    static let title: LocalizedStringResource = "Record Battery"
    static let description = IntentDescription("Saves the battery's level and charger to battery's history.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        Log.note("Record Battery")
        let reading = await Monitor.shared.tick(force: true)
        let state = switch reading.state {
        case .battery: "on battery"
        case .charging: "charging"
        case .full: "full"
        case .held: "held"
        }
        return .result(dialog: "\(Int(reading.percent))%, \(state)")
    }
}

struct Shortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RecordBattery(), phrases: ["Record \(.applicationName)"],
                    shortTitle: "Record Battery", systemImageName: "battery.100percent.bolt")
    }
}
