import SwiftUI
import UIKit

// MARK: - Dynamic semantic colors (Light/Dark aware)
extension Color {
  private static func dynamic(lightHex: String, darkHex: String) -> Color {
    Color(
      UIColor { trait in
        let hex = trait.userInterfaceStyle == .dark ? darkHex : lightHex
        return UIColor(hex: hex)
      })
  }

  // Semantic colors
  static var background: Color { dynamic(lightHex: "FAFAF8", darkHex: "0A0A0B") }
  static var surface: Color { dynamic(lightHex: "FFFFFF", darkHex: "1A1A1C") }
  static var textPrimary: Color { dynamic(lightHex: "1A1A1A", darkHex: "F5F5F5") }
  static var textSecondary: Color { dynamic(lightHex: "6B6B6B", darkHex: "A3A3A3") }
  static var accentBlue: Color { dynamic(lightHex: "0066CC", darkHex: "0A84FF") }
  static var aiPurple: Color { dynamic(lightHex: "7C3AED", darkHex: "A78BFA") }
  static var successGold: Color { dynamic(lightHex: "F59E0B", darkHex: "FCD34D") }
  static var danger: Color { dynamic(lightHex: "DC2626", darkHex: "F87171") }
  static var treeLines: Color { dynamic(lightHex: "E5E5E3", darkHex: "2D2D30") }
}

// Allow shorthand usage like `.background(.background)` and `.foregroundStyle(.textPrimary)`
extension ShapeStyle where Self == Color {
  static var background: Color { Color.background }
  static var surface: Color { Color.surface }
  static var textPrimary: Color { Color.textPrimary }
  static var textSecondary: Color { Color.textSecondary }
  static var accentBlue: Color { Color.accentBlue }
  static var aiPurple: Color { Color.aiPurple }
  static var successGold: Color { Color.successGold }
  static var danger: Color { Color.danger }
  static var treeLines: Color { Color.treeLines }
}

// MARK: - UIColor Extension for Hex Support (used for dynamic colors)
extension UIColor {
  convenience init(hex: String) {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)
    let a: UInt64
    let r: UInt64
    let g: UInt64
    let b: UInt64
    switch hex.count {
    case 3:  // RGB (12-bit)
      (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
    case 6:  // RGB (24-bit)
      (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
    case 8:  // ARGB (32-bit)
      (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
    default:
      (a, r, g, b) = (255, 0, 0, 0)
    }

    self.init(
      red: CGFloat(Double(r) / 255),
      green: CGFloat(Double(g) / 255),
      blue: CGFloat(Double(b) / 255),
      alpha: CGFloat(Double(a) / 255)
    )
  }
}
