import AppKit
import Foundation
import Observation

enum Backend: String, CaseIterable, Identifiable {
  case dxmt
  case d3dmetal
  case wined3d

  var id: String { rawValue }

  var title: String {
    switch self {
    case .dxmt: "DXMT"
    case .d3dmetal: "D3DMetal"
    case .wined3d: "WineD3D"
    }
  }

  var caption: String {
    switch self {
    case .dxmt: "Direct3D 11 direkt auf Metal, mit MetalFX-Hochskalierung und Metal-Frame-Pacing."
    case .d3dmetal: "Apples Übersetzung aus dem Game Porting Toolkit. Gut zum Vergleichen."
    case .wined3d: "Wines OpenGL-Weg. Deutlich langsamer, nur zur Fehlersuche."
    }
  }

  var flag: String { "--\(rawValue)" }
}

@MainActor
@Observable
final class LaunchSettings {
  var backend: Backend { didSet { save() } }
  var metalHUD: Bool { didSet { save() } }
  var metalFX: Bool { didSet { save() } }
  var frameLimit: Int { didSet { save() } }

  static let frameLimits = [0, 30, 60, 120]

  /// DXMT multiplies the game's resolution by this factor. The game renders at
  /// the screen size in points, so the backing scale lands on the panel's pixels.
  static var upscale: Double { Double(NSScreen.main?.backingScaleFactor ?? 2) }

  private let defaults = UserDefaults.standard

  init() {
    backend = Backend(rawValue: defaults.string(forKey: "backend") ?? "") ?? .dxmt
    metalHUD = defaults.bool(forKey: "metalHUD")
    metalFX = defaults.object(forKey: "metalFX") as? Bool ?? true
    frameLimit = defaults.object(forKey: "frameLimit") as? Int ?? 60
  }

  var arguments: [String] {
    var args = [backend.flag]
    if metalHUD { args.append("--hud") }
    if !metalFX { args.append("--no-metalfx") }
    return args
  }

  func writeDXMTConfig(to url: URL) throws {
    var lines = ["# Von BeamMac geschrieben. Änderungen in der App vornehmen."]
    if frameLimit > 0 { lines.append("d3d11.preferredMaxFrameRate = \(frameLimit)") }
    lines.append("d3d11.metalSpatialUpscaleFactor = \(String(format: "%.2f", Self.upscale))")
    lines.append("dxgi.handleAltTab = True")
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
  }

  private func save() {
    defaults.set(backend.rawValue, forKey: "backend")
    defaults.set(metalHUD, forKey: "metalHUD")
    defaults.set(metalFX, forKey: "metalFX")
    defaults.set(frameLimit, forKey: "frameLimit")
  }
}
