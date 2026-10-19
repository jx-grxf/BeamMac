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
    case .off: "Kein Hochskalieren. BeamNG rendert in Punkten, macOS streckt das Bild auf das Display."
    }
  }

  /// The game sees the screen in pixels unless DXMT's MetalFX does the scaling.
  var rendersInPixels: Bool { self != .metalFX }

  /// The BeamNG mode waits for Retina per game and a temporal upscaler under
  /// DXMT; until then it rendered the world at a quarter of the pixels.
  static var choices: [Upscaler] { [.metalFX, .off] }
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
  var lowLatency: Bool { didSet { save() } }
  /// Off starts the game the way Wine alone would, so the pack can be measured.
  var gamePack: Bool { didSet { save() } }

  // 40 fps is a third of a 120 Hz panel: every frame stays up for exactly three
  // refreshes, where an uncapped 45-50 fps alternates two and three.
  static let frameLimits = [0, 30, 40, 60, 120]

  /// The highest limit that divides the panel's refresh rate and that a
  /// CPU-bound BeamNG under Rosetta holds with traffic.
  static var steadyFrameLimit: Int { GameSettings.refreshRate % 40 == 0 ? 40 : 30 }

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
    lowLatency = defaults.object(forKey: "lowLatency") as? Bool ?? true
    gamePack = defaults.object(forKey: "gamePack") as? Bool ?? true
    if !Upscaler.choices.contains(upscaler) { upscaler = .metalFX }
  }

  var arguments: [String] {
    var args = [backend.flag]
    if metalHUD { args.append("--hud") }
    if gamePack {
      args += ["--upscaler", upscaler.rawValue]
    } else {
      args.append("--stock")
    }
    return args
  }

  func writeDXMTConfig(to url: URL) throws {
    var lines = ["# Von BeamMac geschrieben. Änderungen in der App vornehmen."]
    lines.append("dxgi.handleAltTab = True")
    if gamePack {
      if frameLimit > 0 { lines.append("d3d11.preferredMaxFrameRate = \(frameLimit)") }
      lines.append("d3d11.metalSpatialUpscaleFactor = \(String(format: "%.2f", Self.upscale))")
      // DXMT lets the CPU run up to three frames ahead. One would make the game
      // thread wait for DXMT's encoder thread and the GPU every frame, which
      // costs frames while BeamNG is CPU-bound; two keeps them overlapping.
      if lowLatency { lines.append("dxgi.maxFrameLatency = 2") }
    }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
  }

  private func save() {
    defaults.set(backend.rawValue, forKey: "backend")
    defaults.set(metalHUD, forKey: "metalHUD")
    defaults.set(upscaler.rawValue, forKey: "upscaler")
    defaults.set(frameLimit, forKey: "frameLimit")
    defaults.set(lowLatency, forKey: "lowLatency")
    defaults.set(gamePack, forKey: "gamePack")
  }
}
