import SwiftUI
import UIKit

enum MeadowPalette {
    static let ink = color(0x34394D, dark: 0xE8ECF5)
    static let secondaryInk = color(0x636779, dark: 0xB1BCC9)
    static let errorInk = color(0xA33345, dark: 0xFFAFB6)
    static let paper = color(0xFFFDF8, dark: 0x172333)
    static let field = color(0xF4F2EE, dark: 0x243347)
    static let fieldBorder = color(0xD8D6D1, dark: 0x415167)
    static let thumb = color(0xFFFDF8, dark: 0x415167)
    static let accent = color(0xEDC4F0, dark: 0xBBA8EB)
    static let accentInk = color(0x34394D, dark: 0x1D2334)
    static let accentShadow = color(0xC99ECD, dark: 0x76619D)
    static let shadow = color(0x34394D, dark: 0x000000)
    static let glassEdge = color(0xFFFFFF, dark: 0x9CB4C7)
    static let grass = color(0xDCECDD, dark: 0x101E28)
    static let grassDetail = color(0xB4D4BB, dark: 0x294342)
    static let path = color(0xFCF1D9, dark: 0x34424E)
    static let pathEdge = color(0xE9DEC8, dark: 0x4B5665)
    static let tree = color(0x91BCA6, dark: 0x294B4B)
    static let treeLight = color(0xB1D3AE, dark: 0x3A625A)
    static let treeShade = color(0x6E9C88, dark: 0x183A3B)
    static let treeHighlight = color(0xFFFDF8, dark: 0xC5E3CF)
    static let trunk = color(0x9D897C, dark: 0x756760)
    static let flower = color(0xF2B9CA, dark: 0xBC85A8)
    static let flowerCenter = color(0xFFF5C4, dark: 0xF1D79E)
    static let playerCoat = color(0xA899CE, dark: 0xB3A0D6)
    static let playerBackpack = color(0x8071AB, dark: 0x7D6DA3)
    static let passerCoats = [
        color(0xF2B9CA, dark: 0xCE9EBA), color(0xEBC58E, dark: 0xD3B17D),
        color(0x99BECB, dark: 0x86B1BF),
    ]
    static let walkerSkins = [color(0xE0A685), color(0xB87D60), color(0xF0C7A7)]
    static let walkerHair = color(0x67524E)
    static let characterInk = color(0x34394D)
    static let greeting = color(0xA899CE, dark: 0xCAB7EF)
    static let firefly = color(0xFFE7A3)
    static let waterShore = color(0xA9D9E6, dark: 0x2E4B5E)
    static let waterDeep = color(0x7FBFD6, dark: 0x1E3646)
    static let interiorGlow = color(0xFBE7C0, dark: 0xC5A06B)
    static let waterFoam = color(0xFFFDF8, dark: 0xB2D8DF)
    static let cafeRoof = color(0x85ADA2, dark: 0x527D77)
    static let boardCork = color(0xD9B991, dark: 0x806A56)

    private static func color(_ light: UInt32, dark: UInt32? = nil) -> Color {
        Color(
            uiColor: UIColor { traits in
                let hex = traits.userInterfaceStyle == .dark ? dark ?? light : light
                return UIColor(
                    red: CGFloat((hex >> 16) & 255) / 255,
                    green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
            })
    }
}
