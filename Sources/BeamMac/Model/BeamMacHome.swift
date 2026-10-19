import Foundation

/// The checkout that holds bin/, engines/ and data/. The app only drives the
/// scripts there, so the terminal and the app always do the same thing.
struct BeamMacHome: Equatable {
  let root: URL

  static func resolve() -> BeamMacHome? {
    let candidates = [
      UserDefaults.standard.string(forKey: "beamMacRoot"),
      Bundle.main.object(forInfoDictionaryKey: "BeamMacRoot") as? String,
    ]
    for case let path? in candidates {
      let home = BeamMacHome(root: URL(fileURLWithPath: path, isDirectory: true))
      if home.isValid { return home }
    }
    return nil
  }

  var isValid: Bool { FileManager.default.fileExists(atPath: script("beamng").path) }

  func script(_ name: String) -> URL { root.appending(path: "bin/\(name)") }

  var data: URL { root.appending(path: "data") }
  var prefix: URL { data.appending(path: "prefix") }
  var logs: URL { data.appending(path: "logs") }
  var shaderCache: URL { data.appending(path: "shader-cache") }
  var dxmtConfig: URL { data.appending(path: "dxmt.conf") }
  var steamDirectory: URL { prefix.appending(path: "drive_c/Program Files (x86)/Steam") }
  var gameDirectory: URL { steamDirectory.appending(path: "steamapps/common/BeamNG.drive") }

  var engineInstalled: Bool { exists("engines/wine/wswine.bundle/bin/wine") }
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
