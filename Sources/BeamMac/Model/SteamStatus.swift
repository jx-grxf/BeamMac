import Foundation

/// A download or install Steam runs for BeamNG. Steam keeps the counters in the
/// app manifest current while it works, so they double as progress.
struct GameTransfer: Equatable {
  var downloaded: Int64
  var toDownload: Int64
  var staged: Int64
  var toStage: Int64
  var paused: Bool

  /// Steam downloads compressed chunks first and then writes the files; the
  /// second phase can take as long as the first on a large update.
  var isDownloading: Bool { downloaded < toDownload }

  var fraction: Double {
    if isDownloading { return toDownload > 0 ? Double(downloaded) / Double(toDownload) : 0 }
    return toStage > 0 ? Double(staged) / Double(toStage) : 1
  }
}

enum SteamManifest {
  // EAppState bits from Steam's appmanifest.
  private static let updateRequired = 2
  private static let updateRunning = 256
  private static let updatePaused = 512
  private static let updateStarted = 1024

  static func transfer(at url: URL) -> GameTransfer? {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    let values = keyValues(text)
    let flags = Int(values["StateFlags"] ?? "") ?? 0
    guard flags & (updateRequired | updateRunning | updatePaused | updateStarted) != 0 else { return nil }
    let transfer = GameTransfer(
      downloaded: Int64(values["BytesDownloaded"] ?? "") ?? 0,
      toDownload: Int64(values["BytesToDownload"] ?? "") ?? 0,
      staged: Int64(values["BytesStaged"] ?? "") ?? 0,
      toStage: Int64(values["BytesToStage"] ?? "") ?? 0,
      paused: flags & updatePaused != 0)
    // UpdateRequired alone, before Steam has sized the update, carries no numbers yet.
    guard transfer.toDownload > 0 || transfer.toStage > 0 else { return nil }
    return transfer
  }

  /// Top-level `"key" "value"` pairs of a VDF file; nested blocks are not needed here.
  private static func keyValues(_ text: String) -> [String: String] {
    var result: [String: String] = [:]
    for line in text.split(separator: "\n") {
      let parts = line.split(separator: "\"", omittingEmptySubsequences: false)
      // \t"Key"\t\t"Value" splits into ["\t", "Key", "\t\t", "Value", ""].
      guard parts.count >= 5 else { continue }
      let key = String(parts[1])
      if result[key] == nil { result[key] = String(parts[3]) }
    }
    return result
  }
}

enum SteamBootstrap {
  /// True while the bootstrapper of the latest Steam start still checks for a
  /// client update. Under Wine that check can sit in a 60 s timeout.
  static func isChecking(log url: URL) -> Bool {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
    defer { try? handle.close() }
    let size = (try? handle.seekToEnd()) ?? 0
    try? handle.seek(toOffset: size > 16_384 ? size - 16_384 : 0)
    guard let data = try? handle.readToEnd() else { return false }
    let text = String(decoding: data, as: UTF8.self)
    guard let start = text.range(of: "Startup - Steam Client launched", options: .backwards) else { return false }
    let run = text[start.upperBound...]
    return run.contains("Checking for available updates") && !run.contains("Verification complete")
  }
}

/// One `ps` call per refresh instead of a pgrep per process. Wine shows Windows
/// processes by their C:\ path, so the game and launcher only count while our
/// own wineserver runs; that keeps CrossOver or Whisky installs out.
struct ProcessSnapshot {
  var steam = false
  var game = false
  var launcher: pid_t?

  static func capture(home: BeamMacHome) -> ProcessSnapshot {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-axww", "-o", "pid=,command="]
    let pipe = Pipe()
    process.standardOutput = pipe
    do {
      try process.run()
    } catch {
      return ProcessSnapshot()
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    let engines = home.root.appending(path: "engines").path
    let steamExe = home.steamDirectory.appending(path: "steam.exe").path
    var snapshot = ProcessSnapshot()
    var ownServer = false
    var game = false
    var launcher: pid_t?
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
      let trimmed = line.drop { $0 == " " }
      guard let space = trimmed.firstIndex(of: " ") else { continue }
      let command = trimmed[space...]
      if command.contains(engines) && command.contains("wineserver") { ownServer = true }
      if command.contains(steamExe) { snapshot.steam = true }
      if command.localizedCaseInsensitiveContains("BeamNG.drive.x64.exe") {
        game = true
      } else if command.localizedCaseInsensitiveContains("\\BeamNG.drive.exe") {
        launcher = pid_t(trimmed[..<space])
      }
    }
    if ownServer {
      snapshot.game = game
      snapshot.launcher = launcher
    }
    return snapshot
  }
}
