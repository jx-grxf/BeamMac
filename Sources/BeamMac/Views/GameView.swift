import SwiftUI

struct GameView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var launch = model.settings
    @Bindable var game = model.game
    let size = GameSettings.screenSize

    Form {
      Section {
        Toggle(isOn: $launch.metalFX) {
          Text("MetalFX-Hochskalierung")
          Text(metalFXCaption(size))
        }
        .toggleStyle(.switch)
        .disabled(launch.backend != .dxmt)

        Picker(selection: frameLimit) {
          ForEach(LaunchSettings.frameLimits, id: \.self) { limit in
            Text(limit == 0 ? "Aus" : "\(limit) fps").tag(limit)
          }
        } label: {
          Text("Bildraten-Limit")
          Text("120 fps halbieren die Verzögerung pro Bild, brauchen aber Frame-Zeiten unter 8 ms.")
        }

        Picker(selection: $game.displayMode) {
          ForEach(DisplayMode.allCases) { Text($0.title).tag($0) }
        } label: {
          Text("Anzeigemodus")
          Text("Randlos füllt den Bildschirm in \(size.width) × \(size.height). Vollbild kann den Game Mode von macOS auslösen.")
        }
      } header: {
        Text("Bild")
      } footer: {
        if launch.backend != .dxmt {
          Text("MetalFX gibt es nur mit DXMT.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Section("Details") {
        Picker(selection: $game.quality) {
          ForEach(QualityLevel.allCases) { Text($0.title).tag($0) }
        } label: {
          Text("Grafikstufe")
          Text("BeamNGs eigene Voreinstellung für Modelle, Gelände, Texturen, Licht und Schatten.")
        }

        LabeledContent {
          HStack(spacing: Theme.s3) {
            Slider(value: $game.grassDensity, in: 0...1, step: 0.25)
              .frame(maxWidth: 220)
            Text("\(Int((game.grassDensity * 100).rounded())) %")
              .font(.body.monospacedDigit())
              .frame(width: 52, alignment: .trailing)
          }
        } label: {
          Text("Grasdichte")
          Text("Gras kostet auf offenen Karten viel Leistung.")
        }
      }

      Section("Effekte") {
        effectToggle("Umgebungsverdeckung (SSAO)", "Dunkelt Ecken und Kontaktstellen ab.", isOn: $game.ambientOcclusion)
        effectToggle("Schatten im Bildraum", "Feine Kontaktschatten an Autos und Objekten.", isOn: $game.screenSpaceShadows)
        effectToggle("Tiefenunschärfe", "Zeichnet entfernte Bereiche in Menüs und Kameras weich.", isOn: $game.depthOfField)
        effectToggle("Bewegungsunschärfe", "Verwischt schnelle Bewegungen. Macht Ruckler schwerer zu sehen, das Bild aber unschärfer.", isOn: $game.motionBlur)
        effectToggle("Rückspiegel", "Spiegel zeigen das Bild hinter dir. Kostet einen zweiten Renderdurchgang.", isOn: $game.mirrors)
        effectToggle("Spiegelungen in Echtzeit", "Lack und Glas spiegeln die Umgebung live.", isOn: $game.reflections)
      }

      Section {
        Toggle(isOn: $game.trafficOnLoad) {
          Text("Verkehr beim Kartenstart")
          Text("Sonst startest du Verkehr im Pausemenü.")
        }
        .toggleStyle(.switch)

        Stepper(value: $game.trafficCars, in: GameSettings.trafficRange) {
          Text("KI-Autos")
          Text("\(game.trafficCars) fahrende Autos. Jedes rechnet volle Physik auf der CPU.")
        }

        Stepper(value: $game.parkedCars, in: GameSettings.parkedRange) {
          Text("Geparkte Autos")
          Text(game.parkedCars == 0 ? "Keine" : "\(game.parkedCars) am Straßenrand")
        }
      } header: {
        Text("Verkehr")
      }

      Section("Steuerung") {
        Toggle(isOn: $game.wasdSteering) {
          Text("Mit WASD fahren")
          Text("W Gas, S Bremse, A und D lenken. Die Pfeiltasten gehen weiter.")
        }
        .toggleStyle(.switch)
      }

      Section {
        Text("BeamMac schreibt diese Werte bei jedem Start ins Spiel. Was du im Spielmenü an denselben Stellen änderst, gilt bis zum nächsten Start aus BeamMac.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Spiel")
  }

  private var frameLimit: Binding<Int> {
    Binding(
      get: { model.settings.frameLimit },
      set: {
        model.settings.frameLimit = $0
        model.game.markCustom()
      }
    )
  }

  private func effectToggle(_ title: String, _ caption: String, isOn: Binding<Bool>) -> some View {
    Toggle(isOn: isOn) {
      Text(title)
      Text(caption)
    }
    .toggleStyle(.switch)
  }

  private func metalFXCaption(_ size: (width: Int, height: Int)) -> String {
    let scale = LaunchSettings.upscale
    let width = Int((Double(size.width) * scale).rounded())
    let height = Int((Double(size.height) * scale).rounded())
    return "BeamNG rendert in \(size.width) × \(size.height), MetalFX rechnet auf \(width) × \(height) hoch."
  }
}
