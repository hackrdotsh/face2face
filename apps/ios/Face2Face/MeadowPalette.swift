import SwiftUI

enum MeadowPalette {
    static let ink = color(0x34394D)
    static let secondaryInk = color(0x636779)
    static let errorInk = color(0xA33345)
    static let paper = color(0xFFFDF8)
    static let field = color(0xF4F2EE)
    static let fieldBorder = color(0xD8D6D1)
    static let accent = color(0xEDC4F0)
    static let accentShadow = color(0xC99ECD)
    static let grass = color(0xDCECDD)
    static let grassDetail = color(0xB4D4BB)
    static let path = color(0xFCF1D9)
    static let pathEdge = color(0xE9DEC8)
    static let tree = color(0x91BCA6)
    static let treeLight = color(0xB1D3AE)
    static let treeShade = color(0x6E9C88)
    static let trunk = color(0x9D897C)
    static let flower = color(0xF2B9CA)
    static let flowerCenter = color(0xFFF5C4)

    private static func color(_ hex: UInt32) -> Color {
        Color(
            .sRGB, red: Double((hex >> 16) & 255) / 255,
            green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}
