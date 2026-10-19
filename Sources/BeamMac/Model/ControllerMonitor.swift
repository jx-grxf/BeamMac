import AppKit
import GameController
import Observation
import SwiftUI

/// A connected controller as macOS sees it. BeamNG reads the same device
/// through Wine's HID bus; this side only shows state and sets the light bar.
struct ControllerInfo: Identifiable, Equatable {
  let id: ObjectIdentifier
  var name: String
  var category: String
  var battery: Float?
  var charging: Bool
  var hasLight: Bool

  var isPlayStation: Bool {
    category.localizedCaseInsensitiveContains("DualShock") || category.localizedCaseInsensitiveContains("DualSense")
  }
}

/// Live input of the controller shown in the test view.
struct ControllerInput: Equatable {
  var leftStick = CGPoint.zero
  var rightStick = CGPoint.zero
  var leftTrigger: Float = 0
  var rightTrigger: Float = 0
  var pressed: [String] = []
}

@MainActor
@Observable
final class ControllerMonitor {
  private(set) var controllers: [ControllerInfo] = []
  private(set) var input = ControllerInput()

  var lightColor: Color {
    didSet {
      saveLightColor()
      applyLight()
    }
  }

  private var observers: [NSObjectProtocol] = []
  private var batteryTimer: Timer?

  init() {
    let saved = UserDefaults.standard.array(forKey: "controller.lightColor") as? [Double]
    if let saved, saved.count == 3 {
      lightColor = Color(red: saved[0], green: saved[1], blue: saved[2])
    } else {
      // The crash-marker yellow of the app icon.
      lightColor = Theme.crashYellow
    }
  }

  func start() {
    guard observers.isEmpty else { return }
    // The test view should keep moving while the game or Steam is in front.
    GCController.shouldMonitorBackgroundEvents = true
    let center = NotificationCenter.default
    for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
      observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.reload() }
      })
    }
    GCController.startWirelessControllerDiscovery {}
    // GameController has no notification for battery changes.
    batteryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.reload() }
    }
    reload()
  }

  private func reload() {
    let all = GCController.controllers()
    controllers = all.map { controller in
      ControllerInfo(
        id: ObjectIdentifier(controller),
        name: controller.vendorName ?? "Controller",
        category: controller.productCategory,
        battery: controller.battery.map { $0.batteryLevel },
        charging: controller.battery?.batteryState == .charging,
        hasLight: controller.light != nil)
    }
    applyLight()
    watchInput(of: all.first)
  }

  private func applyLight() {
    guard let rgb = NSColor(lightColor).usingColorSpace(.sRGB) else { return }
    for controller in GCController.controllers() {
      controller.light?.color = GCColor(
        red: Float(rgb.redComponent), green: Float(rgb.greenComponent), blue: Float(rgb.blueComponent))
    }
  }

  private func saveLightColor() {
    guard let rgb = NSColor(lightColor).usingColorSpace(.sRGB) else { return }
    UserDefaults.standard.set(
      [Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent)], forKey: "controller.lightColor")
  }

  private func watchInput(of controller: GCController?) {
    guard let pad = controller?.extendedGamepad else {
      input = ControllerInput()
      return
    }
    // The handler runs on the controller's handler queue, which is main by default.
    pad.valueChangedHandler = { [weak self] pad, _ in
      MainActor.assumeIsolated { self?.read(pad) }
    }
    read(pad)
  }

  private func read(_ pad: GCExtendedGamepad) {
    var state = ControllerInput()
    state.leftStick = CGPoint(x: CGFloat(pad.leftThumbstick.xAxis.value), y: CGFloat(pad.leftThumbstick.yAxis.value))
    state.rightStick = CGPoint(x: CGFloat(pad.rightThumbstick.xAxis.value), y: CGFloat(pad.rightThumbstick.yAxis.value))
    state.leftTrigger = pad.leftTrigger.value
    state.rightTrigger = pad.rightTrigger.value
    let buttons: [(GCControllerButtonInput?, String)] = [
      // localizedName gives "Cross", "Circle" … on a PlayStation pad.
      (pad.buttonA, "A"), (pad.buttonB, "B"), (pad.buttonX, "X"), (pad.buttonY, "Y"),
      (pad.leftShoulder, "L1"), (pad.rightShoulder, "R1"),
      (pad.dpad.up, "↑"), (pad.dpad.down, "↓"), (pad.dpad.left, "←"), (pad.dpad.right, "→"),
      (pad.leftThumbstickButton, "L3"), (pad.rightThumbstickButton, "R3"),
      (pad.buttonOptions, "Share"), (pad.buttonMenu, "Options"), (pad.buttonHome, "PS"),
    ]
    state.pressed = buttons.compactMap { button, label in
      guard let button, button.isPressed else { return nil }
      return button.localizedName ?? label
    }
    input = state
  }
}
