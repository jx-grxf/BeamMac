import SwiftUI

@main
struct BeamMacApp: App {
  @State private var model = AppModel()

  var body: some Scene {
    WindowGroup("BeamMac") {
      ContentView()
        .environment(model)
        .frame(minWidth: 760, minHeight: 520)
        .task { model.startPolling() }
    }
    .defaultSize(width: 900, height: 720)
    .windowToolbarStyle(.unified)
    .commands {
      CommandGroup(replacing: .newItem) {}
      CommandMenu("Spiel") {
        Button("Fahren") { Task { await model.drive() } }
          .keyboardShortcut("r")
          .disabled(!model.gameInstalled || model.runner.isBusy)
        Button("Steam öffnen") { Task { await model.openSteam() } }
          .keyboardShortcut("s", modifiers: [.command, .shift])
          .disabled(!model.isSetUp || model.runner.isBusy)
        Divider()
        Button("Alles beenden") { Task { await model.stopAll() } }
          .keyboardShortcut("q", modifiers: [.command, .option])
          .disabled(!model.steamRunning)
      }
    }
  }
}
