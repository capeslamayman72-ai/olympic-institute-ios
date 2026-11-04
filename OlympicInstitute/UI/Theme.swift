import SwiftUI

/// Brand colours from the website's design.css.
enum Brand {
    static let navy = Color(hex: 0x00367C)
    static let navyDeep = Color(hex: 0x002355)
    static let navyLit = Color(hex: 0x0A4F9E)
    static let cyan = Color(hex: 0x30BEF0)
    static let turquoise = Color(hex: 0x00B4AC)
    static let darkPage = Color(hex: 0x04182F)
    static let whatsapp = Color(hex: 0x25D366)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

/// The site's tokens for its dark theme (the default) and light theme.
struct Palette {
    let page: Color
    let elevated: Color
    let band: Color
    let card: Color
    let glass: Color
    let line: Color
    let lineStrong: Color
    let text: Color
    let textSoft: Color
    let muted: Color
    let cyanText: Color
    let turqText: Color
    let chip: Color
    let sale: Color
    let buttonFill: LinearGradient
    let buttonText: Color
    let heroVeil: LinearGradient
    let radiusSm: CGFloat
    let radiusMd: CGFloat
    let radiusLg: CGFloat
    let isDark: Bool

    static let dark = Palette(
        page: Brand.darkPage,
        elevated: Color(hex: 0x082441),
        band: Color(hex: 0x06203C),
        card: Color(hex: 0x16283E),
        glass: Color(hex: 0x0F2238),
        line: Color(hex: 0x1D2F44),
        lineStrong: Color(hex: 0x314254),
        text: Color(hex: 0xEAF4FB),
        textSoft: Color(hex: 0xB8D0E4),
        muted: Color(hex: 0x8FA9C2),
        cyanText: Color(hex: 0x6FD3F7),
        turqText: Color(hex: 0x2AD0C6),
        chip: Color(hex: 0x04182F, alpha: 0.93),
        sale: Color(hex: 0xE2614F),
        buttonFill: LinearGradient(colors: [Brand.cyan, Brand.cyan], startPoint: .leading, endPoint: .trailing),
        buttonText: Brand.darkPage,
        heroVeil: LinearGradient(colors: [Color(hex: 0x04182F, alpha: 0.8), Color(hex: 0x04182F, alpha: 0.9), Brand.darkPage], startPoint: .top, endPoint: .bottom),
        radiusSm: 10, radiusMd: 16, radiusLg: 20,
        isDark: true
    )

    static let light = Palette(
        page: Color(hex: 0xF2F7FB),
        elevated: .white,
        band: .white,
        card: .white,
        glass: Color(hex: 0xEAF1F7),
        line: Color(hex: 0xDBE4EF),
        lineStrong: Color(hex: 0xC2D0E2),
        text: Color(hex: 0x0B2545),
        textSoft: Color(hex: 0x2C4A6E),
        muted: Color(hex: 0x4A6786),
        cyanText: Color(hex: 0x0B6788),
        turqText: Color(hex: 0x00706A),
        chip: Color.white.opacity(0.95),
        sale: Color(hex: 0xC0392B),
        buttonFill: LinearGradient(colors: [Brand.navy, Brand.navyLit], startPoint: .leading, endPoint: .trailing),
        buttonText: .white,
        heroVeil: LinearGradient(colors: [Color(hex: 0xF2F7FB, alpha: 0.9), Color(hex: 0xF2F7FB, alpha: 0.95), Color(hex: 0xF2F7FB)], startPoint: .top, endPoint: .bottom),
        radiusSm: 8, radiusMd: 12, radiusLg: 16,
        isDark: false
    )
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.dark
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// Headings in Cairo, body text in Tajawal, as on the site.
enum AppFont {
    static func head(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        let name: String
        switch weight {
        case .heavy, .black: name = "Cairo-ExtraBold"
        case .semibold: name = "Cairo-SemiBold"
        case .regular, .medium, .light, .thin, .ultraLight: name = "Cairo-Regular"
        default: name = "Cairo-Bold"
        }
        return .custom(name, size: size)
    }

    static func body(_ size: CGFloat = 16, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black, .semibold: name = "Tajawal-Bold"
        case .medium: name = "Tajawal-Medium"
        default: name = "Tajawal-Regular"
        }
        return .custom(name, size: size)
    }
}

enum Lang: String { case ar, en }

/// In-app text is written in both languages where it is used.
enum L {
    static var lang: Lang {
        Lang(rawValue: UserDefaults.standard.string(forKey: "lang") ?? "ar") ?? .ar
    }

    static func t(_ ar: String, _ en: String) -> String { lang == .ar ? ar : en }
}

/// The phone/tablet split the layouts follow (Material's 600 / 840 point breakpoints).
enum WidthClass {
    case phone, tablet, wide

    init(_ width: CGFloat) {
        if width >= 840 { self = .wide } else if width >= 600 { self = .tablet } else { self = .phone }
    }
}
