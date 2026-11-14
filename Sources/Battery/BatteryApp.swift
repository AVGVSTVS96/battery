import BackgroundTasks
import SwiftUI

@main
struct BatteryApp: App {
    @State private var monitor = Monitor.shared
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            Root()
                .environment(monitor)
                .onChange(of: phase, initial: true) { _, phase in monitor.setActive(phase == .active) }
                .onAppear { Hangar.running() }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await MainActor.run { BackgroundRefresh.schedule() }
            _ = await Monitor.shared.tick(force: true)
        }
    }
}

extension Monitor {
    static let shared = Monitor()
}

/// The three pages in the system tab bar. Each lays itself out by the width it's given, the same folded or open.
struct Root: View {
    @State private var tab = Page(rawValue: Demo.page ?? "") ?? .now

    enum Page: String { case now, history, health }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Now", systemImage: "bolt.fill", value: Page.now) { page { NowView(width: $0) } }
            Tab("History", systemImage: "chart.xyaxis.line", value: Page.history) { page { HistoryView(width: $0) } }
            Tab("Health", systemImage: "heart.text.square", value: Page.health) { page { HealthView(width: $0) } }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Ink.primary)
    }

    private func page(@ViewBuilder _ content: @escaping (Width) -> some View) -> some View {
        Screen(content: content)
    }
}

/// A page: scrolling, its margins and width cap, laid out by the width it gets.
struct Screen<Content: View>: View {
    @ViewBuilder var content: (Width) -> Content
    @State private var position = ScrollPosition(y: Demo.offset)

    var body: some View {
        GeometryReader { geo in
            let width = Width(geo.size.width)
            ScrollView {
                content(width)
                    .padding(.horizontal, width.margin)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                    .frame(maxWidth: 1200)
                    .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollPosition($position)
        }
        .background(Ink.background.ignoresSafeArea())
    }
}

/// Tells hangar's server which build runs, so hangar shows it as up to date even when opened from the Home Screen.
enum Hangar {
    static func running() {
        guard !Demo.isOn, let base = Bundle.main.object(forInfoDictionaryKey: "HangarURL") as? String,
              let url = URL(string: base + "/running"),
              let build = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["id": Bundle.main.bundleIdentifier ?? "", "build": build])
        URLSession.shared.dataTask(with: request).resume()
    }
}
