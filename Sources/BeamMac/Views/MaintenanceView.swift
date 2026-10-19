import SwiftUI

struct MaintenanceView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let busy = model.runner.isBusy

    Form {
      Section {
        InstallRow(title: "Wine-Engine mit DXMT und D3DMetal", installed: model.engineInstalled)
        InstallRow(title: "Steam (Windows)", installed: model.steamInstalled)
        InstallRow(title: "BeamNG.drive", installed: model.gameInstalled)
        if model.onboardingSkipped && !(model.isSetUp && model.gameInstalled) {
          LabeledContent {
            Button("Einrichten …") { model.onboardingSkipped = false }
          } label: {
            Text("Einrichtung fortsetzen")
            Text("Führt durch die fehlenden Schritte bis zum ersten Start.")
          }
        }
        LabeledContent {
          Button("Setup ausführen") { Task { await model.runSetup() } }
            .disabled(busy)
        } label: {
          Text("Setup erneut ausführen")
          Text("Lädt fehlende Teile nach und setzt die Wine-Einstellungen neu. Steam wird dafür beendet.")
        }
      } header: {
        Text("Installation")
      }

      Section("Speicher") {
        LabeledContent {
          HStack(spacing: Theme.s3) {
            Text(ByteCountFormatter.string(fromByteCount: model.shaderCacheSize, countStyle: .file))
              .monospacedDigit()
              .foregroundStyle(.secondary)
            Button("Leeren") { Task { await model.clearShaderCache() } }
              .disabled(model.gameRunning || model.shaderCacheSize == 0)
              .help(model.gameRunning ? "Erst BeamNG beenden" : "")
          }
        } label: {
          Text("Shader-Cache")
          Text("Kompilierte Metal-Shader. Nach dem Leeren ruckelt das Spiel beim ersten Laden wieder kurz.")
        }
        if let home = model.home {
          LabeledContent("Daten") {
            Button("Im Finder zeigen") { model.reveal(home.data) }
          }
          LabeledContent("Spielordner") {
            Button("Im Finder zeigen") { model.reveal(home.gameDirectory) }
              .disabled(!model.gameInstalled)
          }
        }
      }

      Section("Werkzeuge") {
        @Bindable var model = model
        Toggle(isOn: $model.prestartSteam) {
          Text("Steam beim Öffnen vorstarten")
          Text("Steam braucht unter Wine rund eine Minute bis zur Anmeldung. So ist es fertig, bevor du auf Fahren klickst.")
        }
        .toggleStyle(.switch)
        LabeledContent {
          Button("Aktualisieren") { Task { await model.updateSteam() } }
            .disabled(busy || model.transfer != nil)
        } label: {
          Text("Steam aktualisieren")
          Text("Steam sucht nur einmal pro Woche selbst nach Updates, weil die Suche unter Wine jeden Start um eine Minute verzögert.")
        }
        LabeledContent {
          Button("Öffnen") { Task { await model.openWineConfiguration() } }
            .disabled(busy)
        } label: {
          Text("Wine-Konfiguration")
          Text("winecfg für den BeamMac-Prefix, etwa für Audio oder die Windows-Version.")
        }
        LabeledContent {
          Button("Beenden") { Task { await model.stopAll() } }
            .disabled(!model.steamRunning || busy)
        } label: {
          Text("Alles beenden")
          Text("Beendet BeamNG, Steam und den wineserver.")
        }
      }

      Section {
        LogView(lines: model.runner.lines)
          .frame(height: 220)
      } header: {
        HStack {
          Text("Protokoll")
          Spacer()
          if let home = model.home {
            Button("Steam-Log") { model.reveal(home.logs.appending(path: "steam.log")) }
              .buttonStyle(.link)
          }
          Button("Leeren") { model.runner.clear() }
            .buttonStyle(.link)
            .disabled(model.runner.lines.isEmpty)
        }
      }

      if let home = model.home {
        Section("Speicherort") {
          LabeledContent {
            Button("Ändern …") { model.chooseDataRoot() }
              .disabled(model.steamRunning)
          } label: {
            Text("Wine, Steam und BeamNG")
            Text(home.root.path)
              .font(.caption.monospaced())
              .textSelection(.enabled)
          }
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Wartung")
  }
}

private struct InstallRow: View {
  let title: String
  let installed: Bool

  var body: some View {
    LabeledContent(title) {
      Label(installed ? "Installiert" : "Fehlt",
            systemImage: installed ? "checkmark.circle.fill" : "xmark.circle.fill")
        .foregroundStyle(installed ? .green : .secondary)
        .symbolRenderingMode(.hierarchical)
    }
  }
}

private struct LogView: View {
  let lines: [String]

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 1) {
          if lines.isEmpty {
            Text("Noch keine Ausgabe.")
              .foregroundStyle(.secondary)
          }
          ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
            Text(line)
              .frame(maxWidth: .infinity, alignment: .leading)
              .id(index)
          }
        }
        .font(.caption.monospaced())
        .textSelection(.enabled)
        .padding(Theme.s2)
      }
      .onChange(of: lines.count) { _, count in
        proxy.scrollTo(count - 1, anchor: .bottom)
      }
    }
  }
}
