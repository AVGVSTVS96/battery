import DeviceActivity
import Design
import FamilyControls
import SwiftUI

/// Screen time beside the battery: the report extension draws it, once Screen Time lets battery in.
struct ScreenTimeBlock: View {
    var now: Date
    @State private var allowed = Demo.isOn || ScreenTimeBlock.isAllowed
    @State private var contentWidth: CGFloat = 0
    @State private var failure: String?

    var body: some View {
        Block(title: "Screen time", note: "the last seven days") {
            if allowed {
                report
                    .frame(height: ScreenTimeView.height(for: contentWidth))
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
            } else {
                ask
            }
        }
    }

    @ViewBuilder
    private var report: some View {
        if Demo.isOn {
            ScreenTimeView(Demo.screenTime)
        } else {
            let calendar = Calendar.current
            let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
            DeviceActivityReport(.init(ScreenTime.context),
                                 filter: DeviceActivityFilter(segment: .hourly(during: DateInterval(start: start, end: now)),
                                                              users: .all, devices: .init([.iPhone])))
        }
    }

    private var ask: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("See screen time next to the drain").font(.system(size: 15, weight: .medium)).foregroundStyle(Ink.primary)
                Text("Screen Time shows its numbers inside battery, and battery never reads or keeps them")
                    .font(.label).foregroundStyle(Ink.secondary)
                if let failure { Text(failure).font(.label).foregroundStyle(Ink.bad) }
                Button("Allow Screen Time", systemImage: "hourglass") {
                    Task {
                        do {
                            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                        } catch {
                            failure = error.localizedDescription
                        }
                        withAnimation(.snappy) { allowed = Self.isAllowed }
                    }
                }
                .buttonStyle(.glass)
            }
        }
    }

    private static var isAllowed: Bool {
        AuthorizationCenter.shared.authorizationStatus == .approved
    }
}

extension Demo {
    /// A week of screen time like the demo battery's, for screenshots: the simulator has no Screen Time.
    static var screenTime: ScreenTime {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let hours: [Double] = [14, 3, 0, 0, 0, 0, 6, 21, 33, 27] + Array(repeating: 0, count: 14)
        let past: [(Double, Int)] = [(4.3, 92), (3.7, 81), (5.2, 104), (4.6, 88), (3.9, 77), (6.1, 118)]
        var days = past.enumerated().map { i, day in
            ScreenTime.Day(start: calendar.date(byAdding: .day, value: i - 6, to: today) ?? today, total: day.0 * 3600,
                           pickups: day.1, firstPickup: calendar.date(bySettingHour: 6, minute: 40 + i * 3, second: 0, of: today))
        }
        days.append(.init(start: today, total: hours.reduce(0, +) * 60, pickups: 31,
                          firstPickup: calendar.date(bySettingHour: 6, minute: 48, second: 0, of: today)))
        let apps: [(String, Double, Int)] = [("Safari", 6.4, 96), ("Messages", 5.1, 182), ("Telegram", 4.2, 141),
                                             ("X", 3.6, 88), ("YouTube", 2.9, 23), ("Maps", 1.2, 19)]
        return ScreenTime(days: days, hours: hours.map { $0 * 60 },
                          apps: apps.map { .init(name: $0.0, total: $0.1 * 3600, pickups: $0.2) }, now: now)
    }
}
