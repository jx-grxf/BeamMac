import AppKit
import Foundation
import Observation

enum Profile: String, CaseIterable, Identifiable {
  case smooth
  case balanced
  case pretty
  case custom

  var id: String { rawValue }

  var title: String {
    switch self {
    case .smooth: "Flüssig"
    case .balanced: "Ausgewogen"
    case .pretty: "Schön"
    case .custom: "Eigene"
    }
  }

  var caption: String {
    switch self {
    case .smooth: "120 fps, niedrige Details, keine Effekte, kein Verkehr. Für die geringste Verzögerung."
    case .balanced: "60 fps, normale Details, Spiegel an, wenig Verkehr."
    case .pretty: "60 fps, hohe Details, alle Effekte, etwas Verkehr."
    case .custom: "Eigene Werte von der Seite Spiel."
    }
  }
}

/// BeamNG's own quality presets; the values behind them come from the game's
/// settingsPresets.json, so they follow game updates.
enum QualityLevel: String, CaseIterable, Identifiable {
  case lowest = "Lowest"
  case low = "Low"
  case normal = "Normal"
  case high = "High"
  case ultra = "Ultra"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .lowest: "Sehr niedrig"
    case .low: "Niedrig"
    case .normal: "Normal"
    case .high: "Hoch"
    case .ultra: "Ultra"
    }
  }
}

enum DisplayMode: String, CaseIterable, Identifiable {
  case borderless = "Borderless"
  case fullscreen = "Fullscreen"
  case window = "Window"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .borderless: "Randlos"
    case .fullscreen: "Vollbild"
    case .window: "Fenster"
    }
  }
}

/// Settings BeamMac owns inside BeamNG. They are written into the game's
/// settings.json right before each launch, because the game rewrites that file
/// when it quits.
@MainActor
@Observable
final class GameSettings {
  private(set) var profile: Profile { didSet { save() } }

  var quality: QualityLevel { didSet { changed() } }
  var displayMode: DisplayMode { didSet { changed() } }
  var ambientOcclusion: Bool { didSet { changed() } }
  var depthOfField: Bool { didSet { changed() } }
  var motionBlur: Bool { didSet { changed() } }
  var screenSpaceShadows: Bool { didSet { changed() } }
  var mirrors: Bool { didSet { changed() } }
  var reflections: Bool { didSet { changed() } }
  var grassDensity: Double { didSet { changed() } }
  var trafficOnLoad: Bool { didSet { changed() } }
  var trafficCars: Int { didSet { changed() } }
  var parkedCars: Int { didSet { changed() } }
  var wasdSteering: Bool { didSet { save() } }

  static let trafficRange = 1...20
  static let parkedRange = 0...16

  private var applying = false
  private let defaults = UserDefaults.standard

  init() {
    let d = UserDefaults.standard
    profile = Profile(rawValue: d.string(forKey: "game.profile") ?? "") ?? .balanced
    quality = QualityLevel(rawValue: d.string(forKey: "game.quality") ?? "") ?? .normal
    displayMode = DisplayMode(rawValue: d.string(forKey: "game.displayMode") ?? "") ?? .borderless
    ambientOcclusion = d.object(forKey: "game.ambientOcclusion") as? Bool ?? false
    depthOfField = d.object(forKey: "game.depthOfField") as? Bool ?? false
    motionBlur = d.object(forKey: "game.motionBlur") as? Bool ?? false
    screenSpaceShadows = d.object(forKey: "game.screenSpaceShadows") as? Bool ?? true
    mirrors = d.object(forKey: "game.mirrors") as? Bool ?? true
    reflections = d.object(forKey: "game.reflections") as? Bool ?? false
    grassDensity = d.object(forKey: "game.grassDensity") as? Double ?? 0.5
    trafficOnLoad = d.object(forKey: "game.trafficOnLoad") as? Bool ?? false
    trafficCars = d.object(forKey: "game.trafficCars") as? Int ?? 3
    parkedCars = d.object(forKey: "game.parkedCars") as? Int ?? 3
    wasdSteering = d.object(forKey: "game.wasdSteering") as? Bool ?? true
  }

  func apply(_ profile: Profile, launch: LaunchSettings) {
    guard profile != .custom else {
      self.profile = .custom
      return
    }
    applying = true
    defer { applying = false }
    switch profile {
    case .smooth:
      launch.frameLimit = 120
      quality = .low
      ambientOcclusion = false
      depthOfField = false
      motionBlur = false
      screenSpaceShadows = false
      mirrors = false
      reflections = false
      grassDensity = 0.25
      trafficOnLoad = false
      parkedCars = 0
    case .balanced:
      launch.frameLimit = 60
      quality = .normal
      ambientOcclusion = false
      depthOfField = false
      motionBlur = false
      screenSpaceShadows = true
      mirrors = true
      reflections = false
      grassDensity = 0.5
      trafficOnLoad = false
      trafficCars = 3
      parkedCars = 3
    case .pretty:
      launch.frameLimit = 60
      quality = .high
      ambientOcclusion = true
      depthOfField = true
      motionBlur = false
      screenSpaceShadows = true
      mirrors = true
      reflections = true
      grassDensity = 0.75
      trafficCars = 5
      parkedCars = 6
    case .custom:
      break
    }
    self.profile = profile
    save()
  }

  /// Call when a value outside this class that belongs to a profile changes.
  func markCustom() {
    guard !applying, profile != .custom else { return }
    profile = .custom
  }

  /// The resolution BeamNG has to use: the screen in points. Wine runs without
  /// Retina mode, and DXMT's MetalFX multiplies this by the backing scale.
  static var screenSize: (width: Int, height: Int) {
    guard let screen = NSScreen.main else { return (1920, 1080) }
    let frame = screen.frame
    return (Int(frame.width.rounded()), Int(frame.height.rounded()))
  }

  static var refreshRate: Int {
    max(60, NSScreen.main?.maximumFramesPerSecond ?? 60)
  }

  func write(to userFolder: URL, gameDirectory: URL, launch: LaunchSettings) throws {
    let settingsURL = userFolder.appending(path: "settings/settings.json")
    var values = (try? Self.readJSON(settingsURL)) ?? [:]

    let presetsURL = gameDirectory.appending(path: "lua/ge/extensions/core/settings/settingsPresets.json")
    if let presets = try? Self.readJSON(presetsURL), let preset = presets[quality.rawValue] as? [String: Any] {
      values.merge(preset) { _, new in new }
    }

    let size = Self.screenSize
    values["GraphicOverallQuality"] = "Custom"
    values["GraphicDisplayModes"] = displayMode.rawValue
    values["GraphicDisplayResolutions"] = "\(size.width) \(size.height)"
    values["GraphicDisplayRefreshRates"] = Self.refreshRate
    values["PostFXSSAOGeneralEnabled"] = ambientOcclusion
    values["PostFXDOFGeneralEnabled"] = depthOfField
    values["PostFXMotionBlurEnabled"] = motionBlur
    values["PostFXScreenSpaceShadowsEnabled"] = screenSpaceShadows
    values["GraphicDynMirrorsEnabled"] = mirrors
    values["GraphicDynReflectionEnabled"] = reflections
    values["GraphicGrassDensity"] = grassDensity
    // 0 means "pick by core count" in BeamNG, and Wine reports all 15 cores.
    values["trafficAmount"] = max(trafficCars, Self.trafficRange.lowerBound)
    values["trafficLoadForFreeroam"] = trafficOnLoad
    values["trafficParkedVehicles"] = parkedCars > 0
    values["trafficParkedAmount"] = max(parkedCars, 1)
    // DXMT paces frames through Metal; the game's own limiter and vsync only
    // add latency on top. Other backends fall back to the game's limiter.
    values["vsync"] = false
    let gameLimiter = launch.backend != .dxmt && launch.frameLimit > 0
    values["fpsLimitEnabled"] = gameLimiter
    if gameLimiter { values["fpsLimit"] = launch.frameLimit }

    try Self.writeJSON(values, to: settingsURL)
    try writeKeyboardMap(in: userFolder)
  }

  /// BeamNG drives with the arrow keys and moves the free camera with WASD.
  /// The diff adds WASD to driving and keeps every default binding.
  private func writeKeyboardMap(in userFolder: URL) throws {
    let url = userFolder.appending(path: "settings/inputmaps/keyboard.diff")
    guard wasdSteering else {
      if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
      return
    }
    let diff: [String: Any] = [
      "displayName": "Keyboard",
      "imagePack": "keyboard",
      "version": 1,
      "bindings": [
        ["control": "w", "action": "accelerate"],
        ["control": "s", "action": "brake"],
        ["control": "a", "action": "steer_left"],
        ["control": "d", "action": "steer_right"],
      ],
    ]
    try Self.writeJSON(diff, to: url)
  }

  private func changed() {
    markCustom()
    save()
  }

  private func save() {
    defaults.set(profile.rawValue, forKey: "game.profile")
    defaults.set(quality.rawValue, forKey: "game.quality")
    defaults.set(displayMode.rawValue, forKey: "game.displayMode")
    defaults.set(ambientOcclusion, forKey: "game.ambientOcclusion")
    defaults.set(depthOfField, forKey: "game.depthOfField")
    defaults.set(motionBlur, forKey: "game.motionBlur")
    defaults.set(screenSpaceShadows, forKey: "game.screenSpaceShadows")
    defaults.set(mirrors, forKey: "game.mirrors")
    defaults.set(reflections, forKey: "game.reflections")
    defaults.set(grassDensity, forKey: "game.grassDensity")
    defaults.set(trafficOnLoad, forKey: "game.trafficOnLoad")
    defaults.set(trafficCars, forKey: "game.trafficCars")
    defaults.set(parkedCars, forKey: "game.parkedCars")
    defaults.set(wasdSteering, forKey: "game.wasdSteering")
  }

  private static func readJSON(_ url: URL) throws -> [String: Any] {
    var data = try Data(contentsOf: url)
    // BeamNG writes some files with a UTF-8 byte order mark.
    if data.starts(with: [0xEF, 0xBB, 0xBF]) { data.removeFirst(3) }
    return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
  }

  private static func writeJSON(_ object: [String: Any], to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url, options: .atomic)
  }
}
