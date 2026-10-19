import Foundation
import Observation

@MainActor
@Observable
final class ScriptRunner {
  private(set) var lines: [String] = []
  private(set) var runningTitle: String?
  private(set) var lastFailure: String?

  var isBusy: Bool { runningTitle != nil }

  private static let ansi = try! Regex(#"\u{1B}\[[0-9;]*m"#)
  private static let maxLines = 1500

  @discardableResult
  func run(_ title: String, script: URL, arguments: [String] = []) async -> Bool {
    runningTitle = title
    lastFailure = nil
    append("$ \(script.lastPathComponent) \(arguments.joined(separator: " "))")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [script.path] + arguments
    process.currentDirectoryURL = script.deletingLastPathComponent().deletingLastPathComponent()
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

    runningTitle = nil
    if status != 0 {
      lastFailure = "\(title) ist mit Code \(status) abgebrochen."
      append("Abbruch mit Code \(status)")
    }
    return status == 0
  }

  func clear() { lines.removeAll() }

  func report(_ failure: String) {
    lastFailure = failure
    append(failure)
  }

  private func append(_ text: String) {
    let cleaned = text.replacing(Self.ansi, with: "")
    for line in cleaned.split(separator: "\n", omittingEmptySubsequences: true) {
      // curl redraws its progress bar with carriage returns; keep only the last state.
      let visible = line.split(separator: "\r").last.map(String.init) ?? ""
      if !visible.trimmingCharacters(in: .whitespaces).isEmpty { lines.append(visible) }
    }
    if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
  }
}
