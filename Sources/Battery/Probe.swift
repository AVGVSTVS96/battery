import CoreLocation
import Foundation
import notify
import UIKit

/// Everything each power source says right now, written to Application Support/probe.json so it can be read off the
/// phone with devicectl.
enum Probe {
    static func write() {
        var out: [String: Any] = ["date": Date().description]
        let device = UIDevice.current
        out["uidevice"] = ["level": device.batteryLevel, "state": device.batteryState.rawValue]
        out["app"] = ["state": UIApplication.shared.applicationState.rawValue,
                      "refresh": UIApplication.shared.backgroundRefreshStatus.rawValue,
                      "location": CLLocationManager().authorizationStatus.rawValue]
        if let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) {
            if let f = dlsym(iokit, "IOPSGetPercentRemaining") {
                typealias Fn = @convention(c) (UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Bool>, UnsafeMutablePointer<Bool>) -> Int32
                var p: Int32 = -1, c = false, full = false
                let r = unsafeBitCast(f, to: Fn.self)(&p, &c, &full)
                out["IOPSGetPercentRemaining"] = ["return": r, "percent": p, "charging": c, "full": full]
            } else {
                out["IOPSGetPercentRemaining"] = "missing"
            }
        }
        let powerd = PowerD()
        out["powerd.battery"] = (powerd?.battery() ?? [:]).mapValues { "\($0)" }
        out["powerd.adapter"] = (powerd?.adapter() ?? [:]).mapValues { "\($0)" }
        var notes: [String: String] = [:]
        for name in ["com.apple.system.powersources", "com.apple.system.powersources.percent",
                     "com.apple.system.powersources.source", "com.apple.system.powersources.timeremaining",
                     "com.apple.system.powersources.criticallevel", "com.apple.system.batterystatus"] {
            var token: Int32 = 0
            guard notify_register_check(name, &token) == NOTIFY_STATUS_OK else { notes[name] = "refused"; continue }
            var state: UInt64 = 0
            let status = notify_get_state(token, &state)
            notes[name] = status == NOTIFY_STATUS_OK ? String(state, radix: 16) : "status \(status)"
            notify_cancel(token)
        }
        out["notify"] = notes
        do {
            out["hid.power"] = Dictionary(Monitor.shared.reader.allPower().map { ($0.name + " u\($0.usage)", $0.value.map { "\($0)" } ?? "nil") },
                                          uniquingKeysWith: { a, _ in a })
        }
        let url = Store.shared.folder.deletingLastPathComponent().appending(path: "probe.json")
        if let data = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
    }
}

/// What woke the app and what the keepalive did, one timestamped line each in Application Support/log.txt, so
/// background recording can be checked off the phone. Keeps the newest 2,000 lines.
nonisolated enum Log {
    private static let queue = DispatchQueue(label: "com.shahidy.battery.log", qos: .utility)
    private static let url = Store.shared.folder.deletingLastPathComponent().appending(path: "log.txt")

    static func note(_ text: String) {
        let line = "\(Date().formatted(.iso8601)) \(text)\n"
        queue.async {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url, options: [.completeFileProtectionUntilFirstUserAuthentication])
            }
        }
    }

    static func trim() {
        queue.async {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            guard lines.count > 2000 else { return }
            try? (lines.suffix(2000).joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
