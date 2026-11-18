import Foundation

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
