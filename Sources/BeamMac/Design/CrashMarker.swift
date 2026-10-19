import SwiftUI

/// The quartered target painted on crash-test dummies and test cars.
struct CrashMarker: View {
  var size: CGFloat = 40

  var body: some View {
    Canvas { context, canvasSize in
      let rect = CGRect(origin: .zero, size: canvasSize).insetBy(dx: 1, dy: 1)
      let center = CGPoint(x: rect.midX, y: rect.midY)
      let radius = rect.width / 2

      context.fill(Path(ellipseIn: rect), with: .color(Theme.crashYellow))
      for start in [0.0, 180.0] {
        var wedge = Path()
        wedge.move(to: center)
        wedge.addArc(
          center: center, radius: radius,
          startAngle: .degrees(start - 90), endAngle: .degrees(start), clockwise: false)
        wedge.closeSubpath()
        context.fill(wedge, with: .color(Theme.crashBlack))
      }
      context.stroke(Path(ellipseIn: rect), with: .color(Theme.crashBlack), lineWidth: max(1, size / 22))
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}
