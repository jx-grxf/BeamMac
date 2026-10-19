import Foundation

/// Where BeamMac keeps its scripts and its data. The app only drives the
/// scripts, so the terminal and the app always do the same thing.
struct BeamMacHome: Equatable {
  /// bin/, lib/ and config/: inside the app bundle, or a checkout in development.
  let scripts: URL
  /// engines/, downloads/ and data/, handed to the scripts as BEAMMAC_HOME.
  let root: URL

  static let defaultRoot = URL.applicationSupportDirectory.appending(path: "BeamMac", directoryHint: .isDirectory)

  static func resolve() -> BeamMacHome? {
    let defaults = UserDefaults.standard
    let checkout = (Bundle.main.object(forInfoDictionaryKey: "BeamMacRoot") as? String)
      .map { URL(fileURLWithPath: $0, isDirectory: true) }
    let bundled = Bundle.main.resourceURL?.appending(path: "BeamMac", directoryHint: .isDirectory)
    guard let scripts = [bundled, checkout].compactMap({ $0 }).first(where: Self.hasScripts) else { return nil }

    // A checkout that already holds a prefix keeps its data where it is.
    let legacy = [defaults.string(forKey: "beamMacRoot"), checkout?.path]
      .compactMap { $0 }
      .map { URL(fileURLWithPath: $0, isDirectory: true) }
      .first { FileManager.default.fileExists(atPath: $0.appending(path: "data/prefix").path) }
    let root = defaults.string(forKey: "dataRoot").map { URL(fileURLWithPath: $0, isDirectory: true) }
      ?? legacy ?? defaultRoot
    return BeamMacHome(scripts: scripts, root: root)
  }

  private static func hasScripts(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.appending(path: "bin/beamng").path)
  }

  func script(_ name: String) -> URL { scripts.appending(path: "bin/\(name)") }

  var data: URL { root.appending(path: "data") }
  var prefix: URL { data.appending(path: "prefix") }
  var logs: URL { data.appending(path: "logs") }
  var shaderCache: URL { data.appending(path: "shader-cache") }
  var dxmtConfig: URL { data.appending(path: "dxmt.conf") }
  var steamDirectory: URL { prefix.appending(path: "drive_c/Program Files (x86)/Steam") }
  var gameDirectory: URL { steamDirectory.appending(path: "steamapps/common/BeamNG.drive") }
  var appManifest: URL { steamDirectory.appending(path: "steamapps/appmanifest_284160.acf") }
  var bootstrapLog: URL { steamDirectory.appending(path: "logs/bootstrap_log.txt") }

  /// Steam writes an account here after the first successful login.
  var steamLoggedIn: Bool {
    let url = steamDirectory.appending(path: "config/loginusers.vdf")
    return (try? String(contentsOf: url, encoding: .utf8))?.contains("\"AccountName\"") == true
  }

  /// Free space on the disk that holds (or will hold) the library.
  var freeSpace: Int64? {
    var url = root
    while !FileManager.default.fileExists(atPath: url.path), url.pathComponents.count > 1 {
      url = url.deletingLastPathComponent()
    }
    let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return values?.volumeAvailableCapacityForImportantUsage
  }

  var engineInstalled: Bool { exists("engines/BeamNG.app/Contents/MacOS/wine") }
  var steamInstalled: Bool { FileManager.default.fileExists(atPath: steamDirectory.appending(path: "steam.exe").path) }
  var gameInstalled: Bool {
    FileManager.default.fileExists(atPath: gameDirectory.appending(path: "Bin64/BeamNG.drive.x64.exe").path)
  }

  /// BeamNG has moved its user folder between releases, so look for the
  /// newest `mods` directory below any BeamNG folder in Local AppData.
  func modsDirectory() -> URL? {
    let users = prefix.appending(path: "drive_c/users")
    let fm = FileManager.default
    guard let people = try? fm.contentsOfDirectory(at: users, includingPropertiesForKeys: nil) else { return nil }
    var found: [(URL, Date)] = []
    for person in people {
      let local = person.appending(path: "AppData/Local")
      guard let walker = fm.enumerator(
        at: local, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
        options: [.skipsHiddenFiles])
      else { continue }
      for case let url as URL in walker {
        if walker.level > 5 { walker.skipDescendants(); continue }
        guard url.lastPathComponent == "mods", url.path.localizedCaseInsensitiveContains("beamng") else { continue }
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        found.append((url, date))
        walker.skipDescendants()
      }
    }
    return found.max { $0.1 < $1.1 }?.0
  }

  /// BeamNG's user folder (settings, mods, vehicles). Falls back to the default
  /// location before the first start, when there is no mods folder to find yet.
  func userFolder() -> URL {
    if let mods = modsDirectory() { return mods.deletingLastPathComponent() }
    return prefix.appending(path: "drive_c/users/\(NSUserName())/AppData/Local/BeamNG/BeamNG.drive/current")
  }

  private func exists(_ relative: String) -> Bool {
    FileManager.default.fileExists(atPath: root.appending(path: relative).path)
  }
}

extension URL {
  func directorySize() -> Int64 {
    guard let walker = FileManager.default.enumerator(
      at: self, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
    else { return 0 }
    var total: Int64 = 0
    for case let url as URL in walker {
      total += Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
    }
    return total
  }
}
