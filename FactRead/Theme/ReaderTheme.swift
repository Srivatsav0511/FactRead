import SwiftUI

enum ReaderThemeMode: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum ReaderTheme {
    static let horizontalMargin: CGFloat = 26
    static let topPadding: CGFloat = 20
    static let bottomPadding: CGFloat = 34

    static func palette(for mode: ReaderThemeMode, typographyStyle: ReaderTypographyStyle = .original) -> Palette {
        switch typographyStyle {
        case .original:
            return mode == .dark
                ? Palette(
                    pageBackground: Color(hex: "151311"),
                    pageGradientTop: Color(hex: "151311"),
                    pageGradientBottom: Color(hex: "171412"),
                    inkPrimary: Color(hex: "ECE5D9"),
                    inkSecondary: Color(hex: "AEA595"),
                    markerTint: Color(hex: "5D523C"),
                    separator: Color(hex: "2C2823"),
                    shadow: Color.black.opacity(0.32),
                    warmOverlay: Color(hex: "D8A76A").opacity(0.08),
                    isDark: true
                )
                : Palette(
                    pageBackground: Color(hex: "F4EFE4"),
                    pageGradientTop: Color(hex: "F4EFE4"),
                    pageGradientBottom: Color(hex: "F2ECE0"),
                    inkPrimary: Color(hex: "201D18"),
                    inkSecondary: Color(hex: "6C6558"),
                    markerTint: Color(hex: "E4CF99"),
                    separator: Color(hex: "D8CEBE"),
                    shadow: Color.black.opacity(0.14),
                    warmOverlay: Color(hex: "FFF6E3").opacity(0.08),
                    isDark: false
                )
        case .quiet:
            return mode == .dark
                ? Palette(
                    pageBackground: Color(hex: "121417"),
                    pageGradientTop: Color(hex: "14171B"),
                    pageGradientBottom: Color(hex: "0E1114"),
                    inkPrimary: Color(hex: "E6EAF0"),
                    inkSecondary: Color(hex: "A7AFBC"),
                    markerTint: Color(hex: "5A6677"),
                    separator: Color(hex: "2A303B"),
                    shadow: Color.black.opacity(0.40),
                    warmOverlay: Color(hex: "8EA5C5").opacity(0.06),
                    isDark: true
                )
                : Palette(
                    pageBackground: Color(hex: "EEF2F7"),
                    pageGradientTop: Color(hex: "F2F5FA"),
                    pageGradientBottom: Color(hex: "E9EEF5"),
                    inkPrimary: Color(hex: "1F2633"),
                    inkSecondary: Color(hex: "5A667A"),
                    markerTint: Color(hex: "B9C7DB"),
                    separator: Color(hex: "D1DAE8"),
                    shadow: Color.black.opacity(0.14),
                    warmOverlay: Color(hex: "FFFFFF").opacity(0.10),
                    isDark: false
                )
        case .paper:
            return mode == .dark
                ? Palette(
                    pageBackground: Color(hex: "1B1F27"),
                    pageGradientTop: Color(hex: "1D222B"),
                    pageGradientBottom: Color(hex: "161A21"),
                    inkPrimary: Color(hex: "D7DEEA"),
                    inkSecondary: Color(hex: "A8B3C4"),
                    markerTint: Color(hex: "5A6780"),
                    separator: Color(hex: "303849"),
                    shadow: Color.black.opacity(0.40),
                    warmOverlay: Color(hex: "9CB3D8").opacity(0.06),
                    isDark: true
                )
                : Palette(
                    pageBackground: Color(hex: "EAF0F7"),
                    pageGradientTop: Color(hex: "EEF3F9"),
                    pageGradientBottom: Color(hex: "E3EAF3"),
                    inkPrimary: Color(hex: "202733"),
                    inkSecondary: Color(hex: "5D6879"),
                    markerTint: Color(hex: "B7C3D8"),
                    separator: Color(hex: "CCD6E4"),
                    shadow: Color.black.opacity(0.16),
                    warmOverlay: Color(hex: "FFFFFF").opacity(0.14),
                    isDark: false
                )
        case .bold:
            return mode == .dark
                ? Palette(
                    pageBackground: Color(hex: "050507"),
                    pageGradientTop: Color(hex: "050507"),
                    pageGradientBottom: Color(hex: "090A0E"),
                    inkPrimary: Color(hex: "FFFFFF"),
                    inkSecondary: Color(hex: "D0D3DA"),
                    markerTint: Color(hex: "8A94A8"),
                    separator: Color(hex: "1F2330"),
                    shadow: Color.black.opacity(0.48),
                    warmOverlay: Color(hex: "FFFFFF").opacity(0.03),
                    isDark: true
                )
                : Palette(
                    pageBackground: Color(hex: "FFFFFF"),
                    pageGradientTop: Color(hex: "FFFFFF"),
                    pageGradientBottom: Color(hex: "F6F8FB"),
                    inkPrimary: Color(hex: "11141A"),
                    inkSecondary: Color(hex: "495062"),
                    markerTint: Color(hex: "B3BCCF"),
                    separator: Color(hex: "D7DDE8"),
                    shadow: Color.black.opacity(0.13),
                    warmOverlay: Color(hex: "FFFFFF").opacity(0.08),
                    isDark: false
                )
        case .calm:
            return mode == .dark
                ? Palette(
                    pageBackground: Color(hex: "4B4135"),
                    pageGradientTop: Color(hex: "53483B"),
                    pageGradientBottom: Color(hex: "433A2F"),
                    inkPrimary: Color(hex: "E9DFC9"),
                    inkSecondary: Color(hex: "CDBEA3"),
                    markerTint: Color(hex: "8B755B"),
                    separator: Color(hex: "665847"),
                    shadow: Color.black.opacity(0.38),
                    warmOverlay: Color(hex: "D2B389").opacity(0.08),
                    isDark: true
                )
                : Palette(
                    pageBackground: Color(hex: "D7C0A1"),
                    pageGradientTop: Color(hex: "DCC7AA"),
                    pageGradientBottom: Color(hex: "CFB594"),
                    inkPrimary: Color(hex: "3E2F21"),
                    inkSecondary: Color(hex: "6B5844"),
                    markerTint: Color(hex: "A68A6A"),
                    separator: Color(hex: "BFA98D"),
                    shadow: Color.black.opacity(0.20),
                    warmOverlay: Color(hex: "F6E6CF").opacity(0.12),
                    isDark: false
                )
        case .focus:
            return mode == .dark
                ? Palette(
                    pageBackground: Color(hex: "2A1F16"),
                    pageGradientTop: Color(hex: "2F2419"),
                    pageGradientBottom: Color(hex: "241A12"),
                    inkPrimary: Color(hex: "EFE3CF"),
                    inkSecondary: Color(hex: "C9B79D"),
                    markerTint: Color(hex: "8C7253"),
                    separator: Color(hex: "433225"),
                    shadow: Color.black.opacity(0.42),
                    warmOverlay: Color(hex: "D2A975").opacity(0.09),
                    isDark: true
                )
                : Palette(
                    pageBackground: Color(hex: "F3F2E7"),
                    pageGradientTop: Color(hex: "F7F6EC"),
                    pageGradientBottom: Color(hex: "ECE9D9"),
                    inkPrimary: Color(hex: "201F14"),
                    inkSecondary: Color(hex: "5F5A44"),
                    markerTint: Color(hex: "C8BC90"),
                    separator: Color(hex: "DBD3B8"),
                    shadow: Color.black.opacity(0.15),
                    warmOverlay: Color(hex: "FFF4CC").opacity(0.09),
                    isDark: false
                )
        }
    }

    struct Palette {
        let pageBackground: Color
        let pageGradientTop: Color
        let pageGradientBottom: Color
        let inkPrimary: Color
        let inkSecondary: Color
        let markerTint: Color
        let separator: Color
        let shadow: Color
        let warmOverlay: Color
        let isDark: Bool
    }
}
