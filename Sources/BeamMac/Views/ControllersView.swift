import SwiftUI

struct ControllersView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let monitor = model.controllers

    Group {
      if monitor.controllers.isEmpty {
        ContentUnavailableView {
          Label("Kein Controller verbunden", systemImage: "gamecontroller")
        } description: {
          Text("PS4-Controller koppeln: PS- und Share-Taste gedrückt halten, bis die Leiste schnell blinkt. Dann in den Bluetooth-Einstellungen auf „Verbinden“ klicken.")
        } actions: {
          Button("Bluetooth-Einstellungen öffnen") {
            if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
              NSWorkspace.shared.open(url)
            }
          }
        }
      } else {
        Form {
          ForEach(monitor.controllers) { controller in
            Section { ControllerRow(controller: controller) }
          }

          Section {
            InputTest(input: monitor.input)
          } header: {
            Text("Test")
          } footer: {
            Text("BeamNG erkennt den Controller selbst. Belegung und Empfindlichkeit stellst du im Spiel unter Optionen > Bedienelemente ein. Steht der Mac im Game Mode, fragt macOS Bluetooth-Controller doppelt so oft ab.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .formStyle(.grouped)
      }
    }
    .navigationTitle("Controller")
  }
}

private struct ControllerRow: View {
  @Environment(AppModel.self) private var model
  let controller: ControllerInfo

  var body: some View {
    @Bindable var monitor = model.controllers

    LabeledContent {
      if let battery = controller.battery {
        Label(
          "\(Int((battery * 100).rounded())) %",
          systemImage: controller.charging ? "battery.100.bolt" : batterySymbol(battery))
          .monospacedDigit()
          .foregroundStyle(battery < 0.2 && !controller.charging ? .orange : .secondary)
      }
    } label: {
      Label {
        Text(controller.name)
        if !controller.name.localizedCaseInsensitiveContains(controller.category) {
          Text(controller.category)
        }
      } icon: {
        Image(systemName: controller.isPlayStation ? "playstation.logo" : "gamecontroller.fill")
      }
    }

    if controller.hasLight {
      LabeledContent {
        ColorPicker("Lichtleiste", selection: $monitor.lightColor, supportsOpacity: false)
          .labelsHidden()
      } label: {
        Text("Lichtleiste")
        Text("BeamMac setzt die Farbe bei jedem Verbinden.")
      }
    }
  }

  private func batterySymbol(_ level: Float) -> String {
    switch level {
    case ..<0.2: "battery.0"
    case ..<0.45: "battery.25"
    case ..<0.7: "battery.50"
    case ..<0.9: "battery.75"
    default: "battery.100"
    }
  }
}

private struct InputTest: View {
  let input: ControllerInput

  var body: some View {
    HStack(spacing: Theme.s5) {
      StickView(title: "Links", position: input.leftStick)
      StickView(title: "Rechts", position: input.rightStick)
      TriggerView(title: "L2", value: input.leftTrigger)
      TriggerView(title: "R2", value: input.rightTrigger)
      VStack(alignment: .leading, spacing: Theme.s1) {
        Text("Tasten")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(input.pressed.isEmpty ? "–" : input.pressed.joined(separator: " "))
          .font(.body.monospaced())
          .lineLimit(2)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, Theme.s2)
    .accessibilityElement(children: .combine)
  }
}

private struct StickView: View {
  let title: String
  let position: CGPoint
  private let size: CGFloat = 64

  var body: some View {
    VStack(spacing: Theme.s1) {
      ZStack {
        Circle().strokeBorder(.secondary.opacity(0.4), lineWidth: 1)
        Circle()
          .fill(Color.accentColor)
          .frame(width: 12, height: 12)
          .offset(x: position.x * (size / 2 - 6), y: -position.y * (size / 2 - 6))
      }
      .frame(width: size, height: size)
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}

private struct TriggerView: View {
  let title: String
  let value: Float

  var body: some View {
    VStack(spacing: Theme.s1) {
      ZStack(alignment: .bottom) {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .strokeBorder(.secondary.opacity(0.4), lineWidth: 1)
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(Color.accentColor)
          .frame(height: 64 * CGFloat(value))
      }
      .frame(width: 18, height: 64)
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}
