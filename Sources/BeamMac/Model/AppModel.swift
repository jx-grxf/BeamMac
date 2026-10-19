import AppKit
import Observation

@MainActor
@Observable
final class AppModel {
  private(set) var home: BeamMacHome? = BeamMacHome.resolve()
  let settings = LaunchSettings()
  let game = GameSettings()
  let runner = ScriptRunner()
  let mods = ModLibrary()

  private(set) var steamRunning = false
  private(set) var gameRunning = false
  private(set) var engineInstalled = false
  private(set) var steamInstalled = false
  private(set) var gameInstalled = false
  private(set) var lowPowerMode = false
  private(set) var shaderCacheSize: Int64 = 0

  var isSetUp: Bool { engineInstalled && steamInstalled }

  private var polling: Task<Void, Never>?

  func startPolling() {
    guard polling == nil else { return }
    polling = Task { [weak self] in
      while !Task.isCancelled {
        await self?.refresh()
        try? await Task.sleep(for: .seconds(3))
      }
    }
  }

  func refresh() async {
    lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    guard let home else { return }
    let state = await Task.detached {
      (
        steam: Self.isRunning("steam.exe"),
        game: Self.isRunning("BeamNG.drive.x64.exe"),
        engine: home.engineInstalled,
        steamInstalled: home.steamInstalled,
        gameInstalled: home.gameInstalled,
        cache: home.shaderCache.directorySize()
      )
    }.value
    steamRunning = state.steam
    gameRunning = state.game
    engineInstalled = state.engine
    steamInstalled = state.steamInstalled
    gameInstalled = state.gameInstalled
    shaderCacheSize = state.cache
  }

  func drive() async {
    guard let home else { return }
    do {
      try settings.writeDXMTConfig(to: home.dxmtConfig)
    } catch {
      runner.report("DXMT-Einstellungen konnten nicht gespeichert werden: \(error.localizedDescription)")
      return
    }
    do {
      try game.write(to: home.userFolder(), gameDirectory: home.gameDirectory, launch: settings)
    } catch {
      runner.report("Spiel-Einstellungen konnten nicht gespeichert werden: \(error.localizedDescription)")
      return
    }
    await runner.run("BeamNG wird gestartet", script: home.script("beamng"), arguments: settings.arguments)
    await refresh()
  }

  func openSteam() async {
    guard let home else { return }
    try? settings.writeDXMTConfig(to: home.dxmtConfig)
    await runner.run("Steam wird gestartet", script: home.script("beamng"), arguments: settings.arguments + ["--steam-only"])
    await refresh()
  }

  func stopAll() async {
    guard let home else { return }
    await runner.run("Wird beendet", script: home.script("stop"))
    await refresh()
  }

  func runSetup() async {
    guard let home else { return }
    if steamRunning { await stopAll() }
    await runner.run("Setup läuft", script: home.script("setup"))
    await refresh()
  }

  func openWineConfiguration() async {
    guard let home else { return }
    await runner.run("Wine-Konfiguration offen", script: home.script("wine"), arguments: ["winecfg"])
  }

  func clearShaderCache() async {
    guard let home else { return }
    try? FileManager.default.removeItem(at: home.shaderCache)
    await refresh()
  }

  func chooseHome() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.message = "Ordner mit bin/beamng auswählen"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let candidate = BeamMacHome(root: url)
    guard candidate.isValid else {
      runner.report("In \(url.path) fehlt bin/beamng.")
      return
    }
    UserDefaults.standard.set(url.path, forKey: "beamMacRoot")
    home = candidate
    Task { await refresh() }
  }

  func reveal(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  nonisolated private static func isRunning(_ pattern: String) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    process.arguments = ["-qif", pattern]
    do {
      try process.run()
      process.waitUntilExit()
      return process.terminationStatus == 0
    } catch {
      return false
    }
  }
}
