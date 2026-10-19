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
  let controllers = ControllerMonitor()

  private(set) var steamRunning = false
  private(set) var gameRunning = false
  private(set) var launcherRunning = false
  /// Set while Steam prepares the game. Steam gives no signal for that phase,
  /// so the status falls back to "Steam läuft" after a few minutes.
  private(set) var launchStarted: Date?
  private(set) var engineInstalled = false
  private(set) var steamInstalled = false
  private(set) var gameInstalled = false
  private(set) var lowPowerMode = false
  private(set) var shaderCacheSize: Int64 = 0
  /// A BeamNG download or install Steam is running.
  private(set) var transfer: GameTransfer?
  private(set) var steamBootstrapping = false
  private(set) var steamLoggedIn = false
  private(set) var rosettaInstalled = FileManager.default.fileExists(atPath: AppModel.rosettaRuntime)
  private(set) var freeSpace: Int64?
  var onboardingSkipped = UserDefaults.standard.bool(forKey: "onboardingSkipped") {
    didSet { UserDefaults.standard.set(onboardingSkipped, forKey: "onboardingSkipped") }
  }

  nonisolated static let rosettaRuntime = "/Library/Apple/usr/libexec/oah/libRosettaRuntime"
  /// The game alone is about 55 GB; the rest covers Wine, Steam and updates.
  static let requiredSpace: Int64 = 70_000_000_000

  /// Steam needs about a minute under Wine before it can start the game.
  var prestartSteam = UserDefaults.standard.object(forKey: "prestartSteam") as? Bool ?? true {
    didSet { UserDefaults.standard.set(prestartSteam, forKey: "prestartSteam") }
  }

  var showOnboarding: Bool { !onboardingSkipped && !(isSetUp && gameInstalled) }
  private var cacheMeasured: Date?

  var isSetUp: Bool { engineInstalled && steamInstalled }

  private var polling: Task<Void, Never>?

  func startPolling() {
    guard polling == nil else { return }
    controllers.start()
    polling = Task { [weak self] in
      await self?.refresh()
      await self?.startSteamInBackground()
      while !Task.isCancelled {
        await self?.refresh()
        try? await Task.sleep(for: .seconds(3))
      }
    }
  }

  func refresh() async {
    lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    guard let home else { return }
    let measureCache = cacheMeasured.map { -$0.timeIntervalSinceNow > 30 } ?? true
    let state = await Task.detached {
      let processes = ProcessSnapshot.capture(home: home)
      return (
        processes: processes,
        transfer: processes.steam ? SteamManifest.transfer(at: home.appManifest) : nil,
        bootstrapping: processes.steam && SteamBootstrap.isChecking(log: home.bootstrapLog),
        engine: home.engineInstalled,
        steamInstalled: home.steamInstalled,
        gameInstalled: home.gameInstalled,
        loggedIn: home.steamLoggedIn,
        rosetta: FileManager.default.fileExists(atPath: AppModel.rosettaRuntime),
        freeSpace: home.freeSpace,
        cache: measureCache ? home.shaderCache.directorySize() : nil
      )
    }.value
    steamRunning = state.processes.steam
    if let pid = state.processes.launcher, !launcherRunning {
      // The launcher opens behind BeamMac; Wine windows have no bundle ID,
      // so activate the process that owns it.
      NSRunningApplication(processIdentifier: pid)?.activate()
    }
    launcherRunning = state.processes.launcher != nil
    gameRunning = state.processes.game
    transfer = state.transfer
    steamBootstrapping = state.bootstrapping
    // An update keeps the launch pending; Steam starts the game once it is done.
    if gameRunning || !steamRunning
      || (transfer == nil && launchStarted.map({ -$0.timeIntervalSinceNow > 300 }) == true)
    {
      launchStarted = nil
    }
    engineInstalled = state.engine
    steamInstalled = state.steamInstalled
    gameInstalled = state.gameInstalled
    steamLoggedIn = state.loggedIn
    rosettaInstalled = state.rosetta
    freeSpace = state.freeSpace
    if let cache = state.cache {
      shaderCacheSize = cache
      cacheMeasured = .now
    }
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
    // The script restarts Steam and returns once it runs; the game follows later.
    if await runner.run("BeamNG wird gestartet", script: home.script("beamng"), arguments: settings.arguments, home: home.root) {
      launchStarted = .now
    }
    await refresh()
  }

  private func startSteamInBackground() async {
    guard prestartSteam, let home, isSetUp, gameInstalled, !steamRunning, !runner.isBusy else { return }
    try? settings.writeDXMTConfig(to: home.dxmtConfig)
    await runner.run("Steam startet im Hintergrund", script: home.script("beamng"), arguments: settings.arguments + ["--background"], home: home.root)
    await refresh()
  }

  func openSteam() async {
    guard let home else { return }
    try? settings.writeDXMTConfig(to: home.dxmtConfig)
    await runner.run("Steam wird gestartet", script: home.script("beamng"), arguments: settings.arguments + ["--steam-only"], home: home.root)
    await refresh()
  }

  /// Steam skips its own update check at startup (see lib/common.sh); this
  /// restarts it once with the check on.
  func updateSteam() async {
    guard let home else { return }
    await runner.run("Steam wird aktualisiert", script: home.script("beamng"), arguments: settings.arguments + ["--steam-only", "--update-steam"], home: home.root)
    await refresh()
  }

  /// Steam shows its own install dialog and asks for the library once.
  func installGame() async {
    guard let home else { return }
    await runner.run("BeamNG wird installiert", script: home.script("beamng"), arguments: settings.arguments + ["--install-game"], home: home.root)
    await refresh()
  }

  /// softwareupdate needs an administrator; macOS asks for the password itself.
  func installRosetta() async {
    let script = "do shell script \"/usr/sbin/softwareupdate --install-rosetta --agree-to-license\" with administrator privileges"
    let ok = await Task.detached {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
      process.arguments = ["-e", script]
      guard (try? process.run()) != nil else { return false }
      process.waitUntilExit()
      return process.terminationStatus == 0
    }.value
    if !ok { runner.report("Rosetta wurde nicht installiert.") }
    await refresh()
  }

  func stopAll() async {
    guard let home else { return }
    await runner.run("Wird beendet", script: home.script("stop"), home: home.root)
    await refresh()
  }

  func runSetup() async {
    guard let home else { return }
    if steamRunning { await stopAll() }
    await runner.run("Setup läuft", script: home.script("setup"), home: home.root)
    await refresh()
  }

  func openWineConfiguration() async {
    guard let home else { return }
    runner.launch(script: home.script("wine"), arguments: ["winecfg"], home: home.root)
  }

  func clearShaderCache() async {
    guard let home else { return }
    try? FileManager.default.removeItem(at: home.shaderCache)
    cacheMeasured = nil
    await refresh()
  }

  /// The game alone needs 60 GB or more, so the library may live on another disk.
  func chooseDataRoot() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.message = "Ordner für Wine, Steam und BeamNG auswählen"
    guard panel.runModal() == .OK, let url = panel.url, let current = home else { return }
    UserDefaults.standard.set(url.path, forKey: "dataRoot")
    home = BeamMacHome(scripts: current.scripts, root: url)
    Task { await refresh() }
  }

  func reveal(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }
}
