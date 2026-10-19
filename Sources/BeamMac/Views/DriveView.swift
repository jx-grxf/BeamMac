import AppKit
import SwiftUI

struct DriveView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var settings = model.settings

    Form {
      Section { HeroRow() }

      if model.lowPowerMode {
        Section {
          Label {
            VStack(alignment: .leading, spacing: 2) {
              Text("Stromsparmodus ist an")
              Text("macOS drosselt CPU und GPU. Unter Systemeinstellungen > Batterie auf „Automatisch“ oder „Hohe Leistung“ stellen.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          } icon: {
            Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
              .foregroundStyle(.orange)
          }
        }
      }

      Section("Grafik-Backend") {
        VStack(alignment: .leading, spacing: Theme.s2) {
          Picker("Backend", selection: $settings.backend) {
            ForEach(Backend.allCases) { Text($0.title).tag($0) }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          Text(settings.backend.caption)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Section {
        Toggle(isOn: $settings.metalFX) {
          Text("MetalFX-Hochskalierung")
          Text("BeamNG rendert kleiner, MetalFX rechnet das Bild auf die volle Bildschirmauflösung hoch.")
        }
        .toggleStyle(.switch)

        if settings.metalFX {
          LabeledContent {
            HStack(spacing: Theme.s3) {
              Slider(value: $settings.upscale, in: 1.0...2.0, step: 0.25)
                .frame(maxWidth: 220)
              Text(String(format: "%.2f×", settings.upscale))
                .font(.body.monospacedDigit())
                .frame(width: 52, alignment: .trailing)
            }
          } label: {
            Text("Faktor")
            Text(renderHint(upscale: settings.upscale))
          }
        }

        Picker(selection: $settings.frameLimit) {
          ForEach(LaunchSettings.frameLimits, id: \.self) { limit in
            Text(limit == 0 ? "Aus" : "\(limit) fps").tag(limit)
          }
        } label: {
          Text("Bildraten-Limit")
          Text("Metal taktet die Bilder gleichmäßig. 60 fps sind auf dem M5 Pro der sichere Wert.")
        }
      } header: {
        Text("Bild")
      } footer: {
        if settings.backend != .dxmt {
          Text("MetalFX und das Limit wirken nur mit DXMT.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .disabled(settings.backend != .dxmt)

      Section("Anzeige") {
        Toggle(isOn: $settings.metalHUD) {
          Text("Metal-HUD")
          Text("Zeigt FPS, Frame-Zeit und GPU-Speicher oben rechts im Spiel.")
        }
        .toggleStyle(.switch)
      }

      Section {
        Text("Änderungen gelten beim nächsten Start. BeamMac startet Steam dafür neu.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Fahren")
  }

  private func renderHint(upscale: Double) -> String {
    guard let screen = NSScreen.main else { return "" }
    let scale = screen.backingScaleFactor
    let width = Int((screen.frame.width * scale / upscale).rounded())
    let height = Int((screen.frame.height * scale / upscale).rounded())
    return "In BeamNG \(width) × \(height) einstellen."
  }
}

private struct HeroRow: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    HStack(spacing: Theme.s4) {
      CrashMarker(size: 52)
      VStack(alignment: .leading, spacing: Theme.s1) {
        Text("BeamNG.drive")
          .font(.title2.weight(.semibold))
        StatusLabel()
      }
      Spacer(minLength: Theme.s4)
      actions
    }
    .padding(.vertical, Theme.s2)
  }

  @ViewBuilder
  private var actions: some View {
    let busy = model.runner.isBusy
    HStack(spacing: Theme.s2) {
      if model.steamRunning {
        Button("Beenden") { Task { await model.stopAll() } }
          .disabled(busy)
      } else if model.isSetUp {
        Button("Steam") { Task { await model.openSteam() } }
          .disabled(busy)
      }

      if !model.isSetUp {
        Button("Einrichten") { Task { await model.runSetup() } }
          .buttonStyle(DriveButtonStyle())
          .disabled(busy)
      } else if !model.gameInstalled {
        if !model.steamRunning {
          Button("In Steam installieren") { Task { await model.openSteam() } }
            .buttonStyle(DriveButtonStyle())
            .disabled(busy)
        }
      } else if !model.gameRunning {
        Button("Fahren") { Task { await model.drive() } }
          .buttonStyle(DriveButtonStyle())
          .disabled(busy)
      }
    }
    .controlSize(.large)
  }
}

private struct StatusLabel: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let (text, symbol, tint) = state
    Label(text, systemImage: symbol)
      .font(.callout)
      .foregroundStyle(tint)
      .symbolRenderingMode(.hierarchical)
  }

  private var state: (String, String, Color) {
    if model.gameRunning { return ("BeamNG läuft", "play.circle.fill", .green) }
    if !model.isSetUp { return ("Noch nicht eingerichtet", "exclamationmark.triangle.fill", .orange) }
    if !model.gameInstalled {
      return model.steamRunning
        ? ("Steam läuft. BeamNG dort installieren.", "arrow.down.circle.fill", .secondary)
        : ("BeamNG ist noch nicht installiert", "arrow.down.circle", .secondary)
    }
    if model.steamRunning { return ("Steam läuft", "circle.fill", .secondary) }
    return ("Bereit", "checkmark.circle.fill", .green)
  }
}

private struct DriveButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body.weight(.semibold))
      .foregroundStyle(Theme.crashBlack)
      .padding(.horizontal, Theme.s4)
      .padding(.vertical, 5)
      .background(Theme.crashYellow, in: .rect(cornerRadius: Theme.buttonRadius, style: .continuous))
      .opacity(isEnabled ? 1 : 0.45)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
      .animation(Theme.hover, value: configuration.isPressed)
  }
}
