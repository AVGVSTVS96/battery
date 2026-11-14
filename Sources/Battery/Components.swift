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
    var size: CGFloat = 40
    @ViewBuilder var bar: Bar

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.label).foregroundStyle(Ink.primary)
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
            Text(caption).font(.label).foregroundStyle(Ink.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A titled block: a small heading with an optional note beside it, then its content.
struct Block<Content: View>: View {
    var title: String
    var note: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) { heading; noteText }
                VStack(alignment: .leading, spacing: 3) { heading; noteText }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Block {
    private var heading: some View {
        Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(Ink.primary).fixedSize()
    }

    @ViewBuilder
    private var noteText: some View {
        if let note { Text(note).font(.label).foregroundStyle(Ink.secondary).fixedSize() }
    }
}

/// BROADCOM's card: white or near-black, a hairline border and generous corners.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
