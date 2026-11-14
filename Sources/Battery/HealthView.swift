import Design
import SwiftUI
import UniformTypeIdentifiers

/// Battery health from Analytics files you share, what the charges taught the app, and how it keeps recording.
struct HealthView: View {
    @Environment(Monitor.self) private var monitor
    var width: Width
    @State private var importing = false
    @State private var note: String?

    var body: some View {
        @Bindable var monitor = monitor
        let latest = monitor.health.last
        VStack(alignment: .leading, spacing: 32) {
            headline(latest)
            figures(latest)
            if monitor.health.count > 1 {
                Block(title: "Maximum capacity", note: "from each Analytics file you shared") {
                    HealthTrend(records: monitor.health).frame(height: 170)
                }
            }
            if width == .narrow {
                VStack(alignment: .leading, spacing: 32) { share; recording(monitor) }
            } else {
                HStack(alignment: .top, spacing: 24) { share; recording(monitor) }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .text, .json]) { result in
            if case .success(let url) = result { report(monitor.importAnalytics(at: url)) }
        }
        .onOpenURL { url in
            if url.isFileURL { report(monitor.importAnalytics(at: url)) }
        }
    }

    private func headline(_ latest: HealthRecord?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let latest, let capacity = latest.maximumCapacity {
                    Text("Battery health \(Text("\(Int(capacity))%").foregroundStyle(capacity < 80 ? Ink.bad : Ink.charge)) \(Text(latest.cycles.map { "· \($0) cycles" } ?? "").foregroundStyle(Ink.secondary))")
                } else {
                    Text("Battery health \(Text("· share an Analytics file").foregroundStyle(Ink.secondary))")
                }
            }
            .font(.system(size: width == .narrow ? 30 : 38))
            .tracking(-0.6)
            .foregroundStyle(Ink.primary)
            .fixedSize(horizontal: false, vertical: true)
            Text(latest.map { "From the Analytics file of \($0.date.formatted(.dateTime.month(.wide).day()))" }
                 ?? "iOS writes health and cycles only there")
                .font(.system(size: 15)).foregroundStyle(Ink.secondary)
        }
    }

    private func figures(_ latest: HealthRecord?) -> some View {
        let analysis = monitor.analysis
        let hottest = analysis.sessions.filter { monitor.now.timeIntervalSince($0.start) < 7 * 86400 }.compactMap(\.hottest).max()
        let first = monitor.health.first
        return VStack(spacing: 0) {
            Divided()
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                let cells: [AnyView] = [
                    AnyView(Stat(label: "Holds", value: latest?.rawMaxCapacity.map { "\(Int($0))" } ?? "–", unit: "mAh",
                                 color: Ink.primary,
                                 caption: latest?.designCapacity.map { "of \(Int($0)) mAh new" } ?? "Needs an Analytics file") {
                        SegmentBar(value: (latest?.rawMaxCapacity ?? 0) / max(latest?.designCapacity ?? 1, 1), segments: 5,
                                   color: Ink.charge)
                    }),
                    AnyView(Stat(label: "Cycles", value: latest?.cycles.map(String.init) ?? "–", unit: "",
                                 color: Ink.primary,
                                 caption: first.flatMap { f in latest?.cycles.flatMap { l in f.cycles.map { "+\(l - $0) since \(f.date.formatted(.dateTime.month(.abbreviated).day()))" } } } ?? "Apple rates 1,000") {
                        SegmentBar(value: Double(latest?.cycles ?? 0) / 1000, segments: 5, color: Ink.primary.opacity(0.7))
                    }),
                    AnyView(Stat(label: "Learned", value: analysis.capacity.map { String(format: "%.1f", $0) } ?? "–", unit: "Wh",
                                 color: Ink.violet, caption: "From the energy charges put in") {
                        SegmentBar(value: (analysis.capacity ?? 0) / 25, segments: 5, color: Ink.violet)
                    }),
                    AnyView(Stat(label: "Hottest charge", value: hottest.map { String(format: "%.1f", $0) } ?? "–", unit: "°C",
                                 color: hottest.map(Ink.temperature) ?? Ink.primary, caption: "This week · ages it past 38°") {
                        SegmentBar(value: ((hottest ?? 20) - 20) / 25, segments: 5,
                                   color: hottest.map { $0 >= 38 ? Ink.temperature($0) : Ink.primary.opacity(0.7) } ?? Ink.track)
                    }),
                ]
                let columns = width == .narrow ? 2 : 4
                ForEach(0..<(cells.count / columns), id: \.self) { row in
                    if row > 0 { GridRow { Divided().gridCellColumns(columns) } }
                    GridRow {
                        ForEach(0..<columns, id: \.self) { column in
                            HStack(spacing: 0) {
                                cells[row * columns + column].padding(.vertical, 22).padding(.horizontal, width == .narrow ? 14 : 22)
                                if column < columns - 1 { Divided(vertical: true) }
                            }
                        }
                    }
                }
            }
            Divided()
        }
    }

    private var share: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Share an Analytics file").font(.system(size: 15, weight: .medium)).foregroundStyle(Ink.primary)
                VStack(alignment: .leading, spacing: 8) {
                    step(1, "Settings › Privacy & Security › Analytics & Improvements › Analytics Data")
                    step(2, "Open the newest Analytics file")
                    step(3, "Share it to battery, or copy its text")
                }
                if let note { Text(note).font(.label).foregroundStyle(Ink.charge).transition(.opacity) }
                HStack(spacing: 10) {
                    Button("Paste", systemImage: "doc.on.clipboard") {
                        report(UIPasteboard.general.string.flatMap { monitor.importAnalytics($0) })
                    }
                    Button("Choose File", systemImage: "folder") { importing = true }
                }
                .buttonStyle(.glass)
                .controlSize(.regular)
            }
        }
    }

    private func recording(_ monitor: Monitor) -> some View {
        @Bindable var monitor = monitor
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $monitor.keepsRecording) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Record every charge").font(.system(size: 15, weight: .medium)).foregroundStyle(Ink.primary)
                        Text("Keeps running while plugged in, and stops at the unplug").font(.label).foregroundStyle(Ink.secondary)
                    }
                }
                .tint(Ink.charge)
                Divided()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fill the gaps with Shortcuts").font(.system(size: 15, weight: .medium)).foregroundStyle(Ink.primary)
                    Text("Automation › Charger › Is Connected and Is Disconnected › Record Battery › Run Immediately")
                        .font(.label).foregroundStyle(Ink.secondary)
                }
                Button("Open Shortcuts", systemImage: "arrow.up.forward.app") {
                    UIApplication.shared.open(URL(string: "shortcuts://")!)
                }
                .buttonStyle(.glass)
                Text("\(monitor.samples.count.formatted()) readings saved")
                    .font(.small).foregroundStyle(Ink.faint)
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)").font(.small.weight(.semibold)).foregroundStyle(Ink.secondary)
                .frame(width: 18, height: 18).background(Ink.track, in: .circle)
            Text(text).font(.label).foregroundStyle(Ink.primary)
        }
    }

    private func report(_ record: HealthRecord?) {
        withAnimation(.snappy) {
            note = record.map { r in
                "Added \(r.date.formatted(.dateTime.month(.abbreviated).day()))" + (r.maximumCapacity.map { ": \(Int($0))%" } ?? "")
            } ?? "No battery health in that file"
        }
    }
}
