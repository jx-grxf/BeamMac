import AppKit

// Usage: swift script/generate_icon.swift <output.png>
// Draws the crash-test marker on a graphite tile at 1024 px.

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let context = NSGraphicsContext.current!.cgContext

let yellow = CGColor(red: 0.98, green: 0.80, blue: 0.10, alpha: 1)
let black = CGColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1)

// Apple's macOS icon grid: 824 pt tile centred in 1024 with a 185 pt corner radius.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
context.addPath(tilePath)
context.clip()
let gradient = CGGradient(
  colorsSpace: CGColorSpaceCreateDeviceRGB(),
  colors: [CGColor(gray: 0.22, alpha: 1), CGColor(gray: 0.11, alpha: 1)] as CFArray,
  locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
context.resetClip()

let center = CGPoint(x: size / 2, y: size / 2)
let radius: CGFloat = 270
context.setFillColor(yellow)
context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
context.setFillColor(black)
for start in [CGFloat.pi / 2, CGFloat.pi * 1.5] {
  context.move(to: center)
  context.addArc(center: center, radius: radius, startAngle: start - .pi / 2, endAngle: start, clockwise: false)
  context.closePath()
  context.fillPath()
}
context.setStrokeColor(black)
context.setLineWidth(18)
context.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))

image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
