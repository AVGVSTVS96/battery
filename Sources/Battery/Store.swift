import Foundation

/// Saved readings, one JSON line each, a file a month in Application Support. The files stay readable while the phone
/// is locked after its first unlock, so a charge recorded overnight is kept.
nonisolated final class Store: @unchecked Sendable {
    static let shared = Store()

    private let queue = DispatchQueue(label: "com.shahidy.battery.store", qos: .utility)
    let folder: URL

    init(folder: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.folder = folder ?? base.appending(path: "samples", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    }

    func append(_ samples: [Sample]) {
        guard !samples.isEmpty else { return }
        queue.async { [folder] in
            for (month, group) in Dictionary(grouping: samples, by: { Self.month($0.t) }) {
                let url = folder.appending(path: "\(month).jsonl")
                var data = Data()
                for sample in group {
                    guard let line = try? Sample.encoder.encode(sample) else { continue }
                    data.append(line)
                    data.append(0x0A)
                }
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                } else {
                    try? data.write(to: url, options: [.completeFileProtectionUntilFirstUserAuthentication])
                }
            }
        }
    }

    /// Every reading since a date, oldest first.
    func load(since: Date) async -> [Sample] {
        await withCheckedContinuation { continuation in
            queue.async { [folder] in
                let first = Self.month(since)
                let files = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path())) ?? [])
                    .filter { $0.hasSuffix(".jsonl") && String($0.dropLast(6)) >= first }
                    .sorted()
                var samples: [Sample] = []
                for file in files {
                    guard let data = try? Data(contentsOf: folder.appending(path: file)) else { continue }
                    for line in data.split(separator: 0x0A) {
                        if let sample = try? Sample.decoder.decode(Sample.self, from: line), sample.t >= since {
                            samples.append(sample)
                        }
                    }
                }
                samples.sort { $0.t < $1.t }
                continuation.resume(returning: samples)
            }
        }
    }

    private static func month(_ date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }
}
