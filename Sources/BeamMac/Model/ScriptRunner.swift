import Foundation
import Observation

/// Where a script is, read from its "[n/total] title" lines and curl's progress bar.
struct ScriptProgress: Equatable {
  var step: Int
  var total: Int
  var title: String
  var percent: Double?

  var fraction: Double {
    let within = (percent ?? 0) / 100
    return min(1, (Double(step - 1) + within) / Double(max(total, 1)))
  }
}

@MainActor
@Observable
final class ScriptRunner {
  private(set) var lines: [String] = []
  private(set) var runningTitle: String?
  private(set) var lastFailure: String?
  private(set) var progress: ScriptProgress?
  /// The script's latest "==>" line, e.g. "Warte, bis Steam angemeldet ist".
  private(set) var status: String?
  /// The text of the script's last "Fehler:" line, from die in lib/common.sh.
  private var scriptError: String?
  /// Output after the last newline; pipes hand over arbitrary chunks.
  private var partialLine = ""

  var isBusy: Bool { runningTitle != nil }

  private static let ansi = try! Regex(#"\u{1B}\[[0-9;]*m"#)
  private static let stepLine = try! Regex(#"\[(\d+)/(\d+)\] (.+)$"#)
  private static let logLine = try! Regex(#"^==> (.+)$"#)
  private static let errorLine = try! Regex(#"^Fehler: (.+)$"#)
  private static let curlBar = try! Regex(#"^[#\s]*(\d{1,3}[.,]\d)%\s*$"#)
  private static let maxLines = 1500

  @discardableResult
  func run(_ title: String, script: URL, arguments: [String] = [], home: URL? = nil) async -> Bool {
    runningTitle = title
    lastFailure = nil
    progress = nil
    status = nil
    scriptError = nil
    appendLines("$ \(script.lastPathComponent) \(arguments.joined(separator: " "))")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [script.path] + arguments
    process.currentDirectoryURL = script.deletingLastPathComponent().deletingLastPathComponent()
    if let home {
      var environment = ProcessInfo.processInfo.environment
      environment["BEAMMAC_HOME"] = home.path
      process.environment = environment
    }
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
      Task { @MainActor in self?.append(text) }
    }

    let status: Int32 = await withCheckedContinuation { continuation in
      process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
      do {
        try process.run()
      } catch {
        process.terminationHandler = nil
        continuation.resume(returning: -1)
      }
    }
    pipe.fileHandleForReading.readabilityHandler = nil
    flushPartialLine()

    runningTitle = nil
    progress = nil
    self.status = nil
    if status != 0 {
      lastFailure = scriptError ?? "\(title) ist mit Code \(status) abgebrochen."
      appendLines("Abbruch mit Code \(status)")
    }
    return status == 0
  }

  func clear() { lines.removeAll() }

  func report(_ failure: String) {
    lastFailure = failure
    appendLines(failure)
  }

  /// Starts a program that keeps running on its own, such as winecfg, without
  /// marking BeamMac as busy.
  func launch(script: URL, arguments: [String] = [], home: URL) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [script.path] + arguments
    var environment = ProcessInfo.processInfo.environment
    environment["BEAMMAC_HOME"] = home.path
    process.environment = environment
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      report("\(script.lastPathComponent) konnte nicht gestartet werden: \(error.localizedDescription)")
    }
  }

  private func flushPartialLine() {
    guard !partialLine.isEmpty else { return }
    let rest = partialLine
    partialLine = ""
    appendLines(rest)
  }

  private func append(_ text: String) {
    let combined = partialLine + text
    if let lastNewline = combined.lastIndex(of: "\n") {
      partialLine = String(combined[combined.index(after: lastNewline)...])
      appendLines(String(combined[..<lastNewline]))
    } else {
      partialLine = combined
    }
  }

  private func appendLines(_ text: String) {
    let cleaned = text.replacing(Self.ansi, with: "")
    for line in cleaned.split(separator: "\n", omittingEmptySubsequences: true) {
      // curl redraws its progress bar with carriage returns; keep only the last state.
      let visible = line.split(separator: "\r").last.map(String.init) ?? ""
      if let bar = visible.firstMatch(of: Self.curlBar) {
        let value = Double(String(bar.output[1].substring ?? "").replacingOccurrences(of: ",", with: "."))
        progress?.percent = value
        continue
      }
      if let match = visible.firstMatch(of: Self.stepLine),
        let step = Int(String(match.output[1].substring ?? "")),
        let total = Int(String(match.output[2].substring ?? ""))
      {
        progress = ScriptProgress(step: step, total: total, title: String(match.output[3].substring ?? ""))
      } else if let match = visible.firstMatch(of: Self.logLine) {
        let text = String(match.output[1].substring ?? "")
        // Skip the log file paths; details in parentheses are for the terminal.
        if !text.hasPrefix("Log:") {
          status = text.components(separatedBy: " (").first
        }
      } else if let match = visible.firstMatch(of: Self.errorLine) {
        scriptError = String(match.output[1].substring ?? "")
      }
      if !visible.trimmingCharacters(in: .whitespaces).isEmpty { lines.append(visible) }
    }
    if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
  }
}
