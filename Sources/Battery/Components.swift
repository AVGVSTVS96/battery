import Design
import SwiftUI

/// A track in segments, filled up to `value` and striped from there to `projected`, like BROADCOM's limit bars.
struct SegmentBar: View {
    var value: Double
    var projected: Double?
    var segments = 5
    var color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 3
            let width = (geo.size.width - gap * CGFloat(segments - 1)) / CGFloat(segments)
            HStack(spacing: gap) {
                ForEach(0..<segments, id: \.self) { i in
                    let start = Double(i) / Double(segments), end = Double(i + 1) / Double(segments)
                    let fill = clamp((value - start) / (end - start))
                    let ahead = projected.map { clamp(($0 - start) / (end - start)) } ?? 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(Ink.track)
                        if ahead > fill {
                            Hatch(spacing: 4)
                                .stroke(color.opacity(0.7), lineWidth: 1.2)
                                .frame(width: width * ahead)
                                .clipShape(Capsule())
                        }
                        Capsule().fill(color).frame(width: fill > 0 ? max(width * fill, height) : 0)
                    }
                    .frame(width: width)
                }
            }
        }
        .frame(height: height)
        .animation(.smooth(duration: 0.5), value: value)
    }

    private func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
}

/// One of the headline figures: a label, a big light number, a bar and a line under it.
struct Stat<Bar: View>: View {
    var label: String
    var value: String
    var unit: String
    var color: Color
    var caption: String
    @ViewBuilder var bar: Bar
    @Environment(\.figureSize) private var size

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.label).foregroundStyle(Ink.primary).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.figure(size))
                    .tracking(-0.8)
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                Text(unit).font(.label).foregroundStyle(Ink.secondary)
            }
            .lineLimit(1)
            bar
            // One line where it fits, else a line per part; never as wide as the cell has to be.
            ViewThatFits(in: .horizontal) {
                Text(caption).lineLimit(1)
                Text(caption.components(separatedBy: "\u{00A0}· ").joined(separator: "\n")).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.label).foregroundStyle(Ink.secondary)
            .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension EnvironmentValues {
    @Entry var figureSize: CGFloat = 40
}

/// Headline figures in a row between hairlines: four across at full size, smaller if only that fits, else two by two.
struct FigureRow<Content: View>: View {
    var width: Width
    @ViewBuilder var content: Content

    var body: some View {
        Group(subviews: content) { cells in
            VStack(spacing: 0) {
                Divided()
                if width == .narrow {
                    grid(cells)
                } else {
                    ViewThatFits(in: .horizontal) {
                        row(cells).environment(\.figureSize, width.figure)
                        row(cells).environment(\.figureSize, 30)
                        grid(cells)
                    }
                }
                Divided()
            }
        }
    }

    private func row(_ cells: SubviewsCollection) -> some View {
        EqualRow {
            ForEach(cells.indices, id: \.self) { i in cell(cells[i], trailing: i < cells.count - 1) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func grid(_ cells: SubviewsCollection) -> some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(Array(stride(from: 0, to: cells.count, by: 2)), id: \.self) { start in
                if start > 0 { GridRow { Divided().gridCellColumns(2) } }
                GridRow {
                    cell(cells[start], trailing: true)
                    if start + 1 < cells.count { cell(cells[start + 1], trailing: false) }
                }
            }
        }
        .environment(\.figureSize, 36)
    }

    private func cell(_ content: Subview, trailing: Bool) -> some View {
        HStack(spacing: 0) {
            content.padding(.vertical, 22).padding(.horizontal, width == .wide ? 22 : 14)
            if trailing { Divided(vertical: true) }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Cells in equal shares of the width. Its ideal width is the widest cell's times the count, so `ViewThatFits` passes
/// over it as soon as any one cell would be cut off in its share.
struct EqualRow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let count = CGFloat(max(subviews.count, 1))
        let width = proposal.width ?? (subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0) * count
        let height = subviews.map { $0.sizeThatFits(.init(width: width / count, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let share = bounds.width / CGFloat(max(subviews.count, 1))
        for (i, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + share * CGFloat(i), y: bounds.minY),
                          proposal: .init(width: share, height: bounds.height))
        }
    }
}

/// A titled block: a small heading with an optional note after it, wrapping as one line of text, then its content.
struct Block<Content: View>: View {
    var title: String
    var note: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading.fixedSize(horizontal: false, vertical: true)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heading: Text {
        let title = Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(Ink.primary)
        guard let note else { return title }
        return Text("\(title)  \(Text(note).font(.label).foregroundStyle(Ink.secondary))")
    }
}

/// BROADCOM's card: white or near-black, a hairline border and generous corners.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Ink.card, in: .rect(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Ink.line, lineWidth: 1))
    }
}

/// A legend entry: a swatch and its name.
struct Key<Swatch: View>: View {
    var name: String
    @ViewBuilder var swatch: Swatch

    var body: some View {
        HStack(spacing: 6) {
            swatch.frame(width: 14, height: 8)
            Text(name).font(.small).foregroundStyle(Ink.secondary)
        }
    }
}

/// How wide the screen is, which decides the layout: never whether the Duo is folded.
enum Width {
    case narrow, medium, wide

    init(_ width: CGFloat) {
        self = width >= 820 ? .wide : width >= 560 ? .medium : .narrow
    }

    /// Figures a little smaller where four share a narrower row.
    var figure: CGFloat { self == .wide ? 40 : 36 }

    var margin: CGFloat { self == .narrow ? 20 : 28 }
}

struct Divided: View {
    var vertical = false

    var body: some View {
        Rectangle().fill(Ink.line).frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}
