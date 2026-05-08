//
//  Colors.swift
//  KazumiTV
//
//  Color extensions for theme colors
//

import SwiftUI

extension Color {
    static let kzBackground = Color(hex: "0B100C")
    static let kzSurface = Color(hex: "101710")
    static let kzSurfaceContainer = Color(hex: "171E17")
    static let kzSurfaceContainerLow = Color(hex: "111811")
    static let kzPrimary = Color(hex: "4CAF50")
    static let kzPrimaryContainer = Color(hex: "1B4F22")
    static let kzOnPrimaryContainer = Color(hex: "D7F7D5")
    static let kzText = Color(hex: "E8ECE6")
    static let kzTextSecondary = Color(hex: "B9C3B6")
    static let kzCardBackground = Color(hex: "151C15")
    static let kzFocusFill = Color.white.opacity(0.10)
    static let kzFocusGlow = Color.white.opacity(0.18)

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
