import Foundation
import Observation

struct Mod: Identifiable, Hashable {
  let url: URL
  let size: Int64
  let modified: Date

  var id: URL { url }
  var name: String { url.deletingPathExtension().lastPathComponent }
}

@MainActor
@Observable
final class ModLibrary {
  private(set) var folder: URL?
  private(set) var mods: [Mod] = []
  private(set) var lastError: String?

  func reload(home: BeamMacHome) async {
    let found = await Task.detached { () -> (URL?, [Mod]) in
      guard let folder = home.modsDirectory() else { return (nil, []) }
      let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
      let files = (try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
      let mods = files
        .filter { $0.pathExtension.lowercased() == "zip" }
        .map { (url: URL) -> Mod in
          let values = try? url.resourceValues(forKeys: Set(keys))
          return Mod(url: url, size: Int64(values?.fileSize ?? 0), modified: values?.contentModificationDate ?? .distantPast)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
      return (folder, mods)
    }.value
    folder = found.0
    mods = found.1
  }

  func add(_ urls: [URL], home: BeamMacHome) async {
    guard let folder else { return }
    lastError = nil
    for source in urls where source.pathExtension.lowercased() == "zip" {
      let target = folder.appending(path: source.lastPathComponent)
      do {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        if FileManager.default.fileExists(atPath: target.path) {
          try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: source, to: target)
      } catch {
        lastError = "\(source.lastPathComponent) konnte nicht kopiert werden: \(error.localizedDescription)"
      }
    }
    await reload(home: home)
  }

  func trash(_ mods: [Mod], home: BeamMacHome) async {
    lastError = nil
    for mod in mods {
      do {
        try FileManager.default.trashItem(at: mod.url, resultingItemURL: nil)
      } catch {
        lastError = "\(mod.name) konnte nicht gelöscht werden: \(error.localizedDescription)"
      }
    }
    await reload(home: home)
  }
}
