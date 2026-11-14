import SwiftUI

/// BROADCOM's palette, light and dark: neutral greys, an orange brand, and green, amber and red for good, full and bad.
enum Ink {
    static let background = pair(0xFAFAFA, 0x0D0D0D)
    static let card = pair(0xFFFFFF, 0x161616)
    static let primary = pair(0x0F0F0F, 0xF2F2F2)
    static let secondary = pair(0x636363, 0x989898)
    static let faint = pair(0x8F8F8F, 0x696969)
    static let line = pair(0xE1E1E1, 0x262626)
    static let track = pair(0xE4E4E4, 0x262626)
    static let brand = pair(0xDE6200, 0xF68C36)
    static let charge = pair(0x1C8742, 0x3FC168)
    static let amber = pair(0xEB9500, 0xF0B135)
    static let amberInk = pair(0xA56300, 0xF0B135)
    static let bad = pair(0xDA4339, 0xF9786A)
    static let violet = pair(0x6D49F4, 0x9586FF)
    static let pink = pair(0xBE47B8, 0xE57FDD)

    /// The colour a battery level reads in: red when low, amber when getting there, the text colour otherwise.
    static func level(_ percent: Double) -> Color {
        percent <= 20 ? bad : percent <= 35 ? amber : primary
    }

    /// The same, with the brand colour standing in for an ordinary level.
    static func levelAccent(_ percent: Double) -> Color {
        percent <= 20 ? bad : percent <= 35 ? amber : brand
    }

    static func temperature(_ celsius: Double) -> Color {
        celsius >= 42 ? bad : celsius >= 38 ? amber : primary
    }

    private static func pair(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Font {
    /// The big light numbers BROADCOM leads with.
    static func figure(_ size: CGFloat) -> Font { .system(size: size, weight: .light).monospacedDigit() }
    static let label = Font.system(size: 13)
    static let small = Font.system(size: 12)
}

/// Diagonal stripes, BROADCOM's mark for a span that's held or used up.
nonisolated struct Hatch: Shape {
    var spacing: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}
