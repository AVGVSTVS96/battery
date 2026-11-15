import Charts
import SwiftUI

nonisolated extension View {
    /// Midnight, 6, noon and 6 under a chart of a day's 24 hours, each centred on its hour's bar. Swift Charts' own
    /// labels stayed a few points right of their ticks whatever the anchor.
    public func hourAxis(_ day: Date) -> some View {
        chartXAxis(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    if let plot = proxy.plotFrame.map({ geo[$0] }) {
                        ForEach([0, 6, 12, 18], id: \.self) { hour in
                            if let x = proxy.position(forX: Double(hour)),
                               let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day) {
                                Text(date.formatted(.dateTime.hour())).font(.small).foregroundStyle(Ink.faint)
                                    .fixedSize()
                                    .position(x: plot.minX + x, y: plot.maxY + 12)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 20)
    }
}
