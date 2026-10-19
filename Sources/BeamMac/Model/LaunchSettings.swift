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

  /// WineD3D stays available from the terminal for debugging; in the app it
  /// would only be a slower way to the same picture.
  static var choices: [Backend] { [.dxmt, .d3dmetal] }
}

/// Who scales the image up to the panel's pixels. The values match the
/// `--upscaler` modes of bin/beamng.
enum Upscaler: String, CaseIterable, Identifiable {
  case game
  case metalFX = "metalfx"
  case off

  var id: String { rawValue }

  var title: String {
    switch self {
    case .game: "BeamNG"
    case .metalFX: "MetalFX"
    case .off: "Aus"
    }
  }

  var caption: String {
    switch self {
    case .game: "Menüs und Schrift in voller Auflösung, nur die 3D-Welt wird hochgerechnet. Schärfstes Bild."
    case .metalFX: "Das ganze Bild wird hochgerechnet, auch die Schrift. Etwas weicher, aber am sparsamsten."
    case .off: "Alles in voller Auflösung. Braucht viel GPU-Leistung."
    }
  }

  /// The game sees the screen in pixels unless DXMT's MetalFX does the scaling.
  var rendersInPixels: Bool { self != .metalFX }
}

extension NSScreen {
  /// Wine's primary monitor is the display with the menu bar. NSScreen.main
  /// follows BeamMac's own window instead, which may sit on another display.
  static var gameScreen: NSScreen? { screens.first }
}

@MainActor
@Observable
final class LaunchSettings {
  var backend: Backend { didSet { save() } }
  var metalHUD: Bool { didSet { save() } }
  var upscaler: Upscaler { didSet { save() } }
  var frameLimit: Int { didSet { save() } }

  static let frameLimits = [0, 30, 60, 120]

  /// DXMT multiplies the game's resolution by this factor. The game renders at
  /// the screen size in points, so the backing scale lands on the panel's pixels.
  static var upscale: Double { Double(NSScreen.gameScreen?.backingScaleFactor ?? 2) }

  private let defaults = UserDefaults.standard

  init() {
    let savedBackend = Backend(rawValue: defaults.string(forKey: "backend") ?? "") ?? .dxmt
    backend = Backend.choices.contains(savedBackend) ? savedBackend : .dxmt
    metalHUD = defaults.bool(forKey: "metalHUD")
    if let saved = Upscaler(rawValue: defaults.string(forKey: "upscaler") ?? "") {
      upscaler = saved
    } else {
      // Before the choice existed, MetalFX was a switch; off meant native.
      upscaler = defaults.object(forKey: "metalFX") as? Bool == false ? .off : .metalFX
    }
    frameLimit = defaults.object(forKey: "frameLimit") as? Int ?? 60
  }

  var arguments: [String] {
    var args = [backend.flag]
    if metalHUD { args.append("--hud") }
    args += ["--upscaler", upscaler.rawValue]
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
    defaults.set(upscaler.rawValue, forKey: "upscaler")
    defaults.set(frameLimit, forKey: "frameLimit")
  }
}
