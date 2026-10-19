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

      Section {
        VStack(alignment: .leading, spacing: Theme.s2) {
          Picker("Profil", selection: profile) {
            ForEach(Profile.allCases) { Text($0.title).tag($0) }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          Text(model.game.profile.caption)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } header: {
        Text("Profil")
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

      Section("Anzeige") {
        Toggle(isOn: $settings.metalHUD) {
          Text("Metal-HUD")
          Text("Zeigt FPS, Frame-Zeit und GPU-Speicher oben rechts im Spiel.")
        }
        .toggleStyle(.switch)
      }

      Section {
        Text("Änderungen gelten beim nächsten Start. BeamMac schreibt sie dann ins Spiel und startet Steam neu.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Fahren")
  }

  private var profile: Binding<Profile> {
    Binding(
      get: { model.game.profile },
      set: { model.game.apply($0, launch: model.settings) }
    )
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
      } else if !model.gameRunning && !model.launcherRunning && model.launchStarted == nil {
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
    if model.launcherRunning { return ("Im Launcher auf Launch klicken", "hand.tap.fill", .orange) }
    if let title = model.runner.runningTitle { return (title, "hourglass", .secondary) }
    if model.launchStarted != nil { return ("Steam bereitet BeamNG vor", "hourglass", .secondary) }
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
