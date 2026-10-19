import SwiftUI

enum Theme {
  static let s1: CGFloat = 4
  static let s2: CGFloat = 8
  static let s3: CGFloat = 12
  static let s4: CGFloat = 16
  static let s5: CGFloat = 20
  static let s6: CGFloat = 28

  static let cardRadius: CGFloat = 14
  static let rowRadius: CGFloat = 11
  // Matches the corner of a large bordered macOS button next to it.
  static let buttonRadius: CGFloat = 7

  // Crash-test marker yellow. Only for the brand mark and the one Drive button;
  // text on it is black because white on this yellow stays under 2:1.
  static let crashYellow = Color(red: 0.98, green: 0.80, blue: 0.10)
  static let crashBlack = Color(red: 0.08, green: 0.08, blue: 0.08)

  static let hoverFill = AnyShapeStyle(.primary.opacity(0.06))

  static let hover = Animation.snappy(duration: 0.16)
  static let expand = Animation.snappy(duration: 0.22)
}

extension View {
  @ViewBuilder
  func glassCard(cornerRadius: CGFloat = Theme.cardRadius) -> some View {
    if #available(macOS 26.0, *) {
      self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    } else {
      self
        .background(.regularMaterial, in: .rect(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(.white.opacity(0.07), lineWidth: 1)
        )
    }
  }
}
