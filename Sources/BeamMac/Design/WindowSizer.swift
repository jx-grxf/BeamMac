import AppKit
import SwiftUI

/// The onboarding sits in a window sized to its content; the main window comes
/// back at its usual size afterwards. SwiftUI restores the last frame of a
/// WindowGroup, so the size has to be set on the NSWindow itself.
struct WindowSizer: NSViewRepresentable {
  var compact: Bool

  static let mainSize = CGSize(width: 900, height: 720)

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async { resize(view.window, fitting: view) }
    return view
  }

  func updateNSView(_ view: NSView, context: Context) {}

  private func resize(_ window: NSWindow?, fitting view: NSView) {
    guard let window else { return }
    if compact {
      guard let content = window.contentView else { return }
      let size = content.fittingSize
      guard size.width > 0, size.height > 0 else { return }
      window.setContentSize(size)
      window.styleMask.remove(.resizable)
      window.center()
    } else {
      window.styleMask.insert(.resizable)
      let current = window.contentLayoutRect.size
      if current.width < Self.mainSize.width || current.height < Self.mainSize.height {
        window.setContentSize(Self.mainSize)
        window.center()
      }
    }
  }
}
