import DeviceActivity
import Design
import ExtensionKit
import SwiftUI

/// battery's Screen Time report. iOS runs it, hands it the week's activity and shows what it draws inside the app;
/// nothing it reads ever leaves it.
@main
struct Report: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        Usage { ScreenTimeView($0) }
    }
}

nonisolated struct Usage: DeviceActivityReportScene {
    let context = DeviceActivityReport.Context(ScreenTime.context)
    let content: (ScreenTime) -> ScreenTimeView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> ScreenTime {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let starts = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        var totals: [Date: TimeInterval] = [:], pickups: [Date: Int] = [:], first: [Date: Date] = [:]
        var hours = Array(repeating: TimeInterval(0), count: 24)
        var apps: [String: ScreenTime.App] = [:]

        for await device in data {
            for await segment in device.activitySegments {
                let start = segment.dateInterval.start
                let day = calendar.startOfDay(for: start)
                totals[day, default: 0] += segment.totalActivityDuration
                pickups[day, default: 0] += segment.totalPickupsWithoutApplicationActivity
                if let pickup = segment.firstPickup, pickup < first[day] ?? .distantFuture { first[day] = pickup }
                if day == today { hours[calendar.component(.hour, from: start)] += segment.totalActivityDuration }
                for await category in segment.categories {
                    for await activity in category.applications {
                        let name = activity.application.localizedDisplayName ?? "Other"
                        apps[name, default: .init(name: name, total: 0, pickups: 0)].total += activity.totalActivityDuration
                        apps[name, default: .init(name: name, total: 0, pickups: 0)].pickups += activity.numberOfPickups
                        pickups[day, default: 0] += activity.numberOfPickups
                    }
                }
            }
        }

        return ScreenTime(
            days: starts.map { .init(start: $0, total: totals[$0] ?? 0, pickups: pickups[$0] ?? 0, firstPickup: first[$0]) },
            hours: hours,
            apps: apps.values.sorted { $0.total > $1.total },
            now: now
        )
    }
}
