import BackgroundTasks
import SwiftUI
import UIKit

/// The live reading, the saved history and what's worked out from it. Reads every second on screen; in the
/// background it runs only while the phone is plugged in, every ten seconds, and stops at the unplug, so the app costs
/// nothing on battery. A plug-in while it's closed reaches it through a Shortcuts automation running Record Battery,
/// or iOS's next background task that waits for power (`ChargeTask`).
@Observable
final class Monitor {
    private(set) var live: Reading?
    private(set) var samples: [Sample] = []
    private(set) var analysis = Analysis([])
    private(set) var health: [HealthRecord] = []
    /// Charger watts over the last two minutes on screen, for the live trace.
    private(set) var trace: [Point] = []
    var keepsRecording: Bool {
        didSet {
            UserDefaults.standard.set(keepsRecording, forKey: "keepsRecording")
            followPower()
        }
    }
    let keepalive = Keepalive()
    let isDemo: Bool

    private let reader = Reader()
    private let store: Store
    private var loop: Task<Void, Never>?
    private var active = false
    private var lastSaved: Sample?

    init(store: Store = .shared) {
        self.store = store
        keepsRecording = UserDefaults.standard.object(forKey: "keepsRecording") as? Bool ?? true
        isDemo = Demo.isOn
        UIDevice.current.isBatteryMonitoringEnabled = true
        if isDemo {
            samples = Demo.samples
            live = Demo.reading
            trace = Demo.trace
            health = Demo.health
            analysis = Analysis(samples, now: Demo.now)
        } else {
            health = HealthRecord.load()
            Task { await loadHistory() }
            NotificationCenter.default.addObserver(forName: UIDevice.batteryStateDidChangeNotification, object: nil,
                                                   queue: .main) { [weak self] _ in
                Task { await self?.tick() }
            }
        }
    }

    var now: Date { isDemo ? Demo.now : .now }

    private func loadHistory() async {
        let loaded = await store.load(since: .now.addingTimeInterval(-42 * 86400))
        samples = loaded + samples.filter { $0.t > (loaded.last?.t ?? .distantPast) }
        lastSaved = samples.last
        await reanalyze()
    }

    private func reanalyze() async {
        let samples = samples
        analysis = await Task.detached(priority: .utility) { Analysis(samples) }.value
    }

    // MARK: Running

    func setActive(_ active: Bool) {
        guard !isDemo else { return }
        self.active = active
        Log.note(active ? "on screen" : "off screen")
        restartLoop()
        if !active {
            BackgroundRefresh.schedule()
            ChargeTask.schedule()
        }
    }

    /// Records a charge for as long as iOS lets a background task that waited for power run, or until the keepalive
    /// takes over or the phone is unplugged.
    func record(_ task: BGProcessingTask) async {
        Log.note("charge task")
        let work = Task {
            var force = true
            while !Task.isCancelled {
                let reading = await tick(force: force)
                force = false
                if !reading.state.pluggedIn || keepalive.isRunning { break }
                try? await Task.sleep(for: .seconds(10))
            }
        }
        task.expirationHandler = {
            Log.note("charge task expired")
            work.cancel()
        }
        await work.value
        Log.note("charge task done, \(live?.state.rawValue ?? "?"), keepalive \(keepalive.isRunning)")
        ChargeTask.schedule()
        task.setTaskCompleted(success: true)
    }

    private func restartLoop() {
        loop?.cancel()
        let interval: Duration = active ? .seconds(1) : .seconds(10)
        guard active || keepalive.isRunning else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Takes one reading and saves it when it adds something: a new level or state, or every minute on the charger.
    @discardableResult
    func tick(force: Bool = false) async -> Reading {
        let reading = await reader.read(Self.publicPower(), temperatureEvery: active ? 5 : 60)
        live = reading
        if active, let watts = reading.inputWatts ?? reading.batteryWatts, reading.state.pluggedIn {
            trace.append(Point(date: reading.date, percent: reading.percent, watts: watts))
            trace.removeAll { reading.date.timeIntervalSince($0.date) > 120 }
        } else if !reading.state.pluggedIn {
            trace.removeAll()
        }
        let sample = reading.sample
        let quiet = reading.state.pluggedIn ? 60.0 : 900.0
        if force || lastSaved.map({ $0.s != sample.s || $0.p != sample.p || sample.t.timeIntervalSince($0.t) >= quiet }) ?? true {
            save(sample)
        }
        followPower()
        return reading
    }

    private func save(_ sample: Sample) {
        store.append([sample])
        let changed = lastSaved?.s != sample.s || lastSaved?.p != sample.p
        lastSaved = sample
        samples.append(sample)
        if changed || analysis.samples.count < 2 { Task { await reanalyze() } }
    }

    /// Keeps the app awake in the background while it's plugged in, and lets it sleep the moment it's not.
    private func followPower() {
        let plugged = live?.state.pluggedIn ?? false
        if keepsRecording && plugged {
            if !keepalive.isRunning {
                keepalive.start()
                if keepalive.isRunning { Log.note("plugged in, keepalive started") }
                if !active { restartLoop() }
            }
        } else if keepalive.isRunning {
            keepalive.stop()
            ChargeTask.schedule()
            Log.note("unplugged, keepalive stopped")
            if !active { loop?.cancel() }
        }
    }

    private static func publicPower() -> PublicPower {
        let device = UIDevice.current
        return PublicPower(percent: device.batteryLevel >= 0 ? Double(device.batteryLevel * 100).rounded() : nil,
                           pluggedIn: device.batteryState == .charging || device.batteryState == .full,
                           charging: device.batteryState == .charging, full: device.batteryState == .full,
                           lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                           thermal: ProcessInfo.processInfo.thermalState.rawValue)
    }

    // MARK: Health

    func importAnalytics(_ text: String) -> HealthRecord? {
        guard let record = HealthRecord.parse(text) else { return nil }
        health.removeAll { Calendar.current.isDate($0.date, inSameDayAs: record.date) }
        health.append(record)
        health.sort { $0.date < $1.date }
        HealthRecord.save(health)
        return record
    }

    func importAnalytics(at url: URL) -> HealthRecord? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return importAnalytics(String(decoding: data, as: UTF8.self))
    }
}

/// A background task iOS runs only while the phone is on power, so a charge that starts with the app closed still
/// gets recorded. iOS picks when, usually soon after the screen goes off on the charger.
enum ChargeTask {
    static let identifier = "com.shahidy.battery.charge"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            guard let task = task as? BGProcessingTask else { return task.setTaskCompleted(success: false) }
            MainActor.assumeIsolated { Task { await Monitor.shared.record(task) } }
        }
    }

    static func schedule() {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresExternalPower = true
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// An occasional wake-up from iOS while unplugged, which records one reading. iOS picks when, and it costs about nothing.
enum BackgroundRefresh {
    static let identifier = "com.shahidy.battery.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = .now.addingTimeInterval(45 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
