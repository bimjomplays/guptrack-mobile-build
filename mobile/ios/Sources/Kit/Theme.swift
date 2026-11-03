import SwiftUI

/// The website's Midnight theme as SwiftUI colours and type (design/iphone/kit/kit.css). The app uses the system
/// font (SF Pro) where the website uses Inter; sizes and weights follow the mockups.
enum Theme {
    // surfaces
    static let sheet = Color(hex: 0x0E0F12)        // every page's background
    static let page = Color.black
    static let panel = Color(hex: 0x1C1C1E)
    static let raised = Color(hex: 0x2C2C2E)
    /// hairlines between rows (no grey boxes)
    static let sep = Color(red: 84 / 255, green: 84 / 255, blue: 88 / 255).opacity(0.55)
    /// the grey of capsules: status pill, stepper, chips, tone buttons
    static let fill = Color(red: 118 / 255, green: 118 / 255, blue: 128 / 255).opacity(0.22)
    static let fillStrong = Color(red: 120 / 255, green: 120 / 255, blue: 128 / 255).opacity(0.36)
    static let track = Color(red: 120 / 255, green: 120 / 255, blue: 128 / 255).opacity(0.3)
    static let keyline = Color.white.opacity(0.08)

    // text
    static let ink = Color(hex: 0xF5F5F7)
    static let inkSoft = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.8)
    static let inkMuted = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.55)
    static let inkFaint = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.3)

    // accents
    static let brand = Color(hex: 0x0A84FF)
    static let brandSoft = Color(hex: 0x3D9BFF)
    static let star = Color(hex: 0xFFD60A)
    static let progress = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.8)
    static let danger = Color(hex: 0xFF453A)

    /// a status's colour (the dot in the pill, the profile's status bar)
    static func color(_ s: ListStatus) -> Color {
        switch s {
        case .current, .repeating: return Color(hex: 0x30D158)
        case .completed: return Color(hex: 0x0A84FF)
        case .hold: return Color(hex: 0xFFD60A)
        case .dropped: return Color(hex: 0xFF453A)
        case .planned: return Color(hex: 0x8E8E93)
        }
    }

    /// side padding of every page
    static let pad: CGFloat = 20
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// The type scale from the mockups (SF Pro at the website's sizes).
extension Font {
    /// a section's 22pt bold title ("Continue", "Upcoming")
    static let section = Font.system(size: 22, weight: .bold)
    /// a row's 16pt semibold title
    static let rowTitle = Font.system(size: 16, weight: .semibold)
    /// a 14pt caption under a title
    static let caption14 = Font.system(size: 14)
    /// a poster card's title under the art
    static let cardTitle = Font.system(size: 14, weight: .semibold)
    static let cardCaption = Font.system(size: 13)
}

extension View {
    /// the page background every screen sits on
    func pageBackground() -> some View {
        background(Theme.sheet.ignoresSafeArea())
    }

    /// numbers that line up (progress, counts, scores)
    func numbers() -> some View { monospacedDigit() }
}
