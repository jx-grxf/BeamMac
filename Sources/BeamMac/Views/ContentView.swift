import SwiftUI

enum Page: String, CaseIterable, Identifiable {
  case drive
  case game
  case mods
  case maintenance

  var id: String { rawValue }

  var title: String {
    switch self {
    case .drive: "Fahren"
    case .game: "Spiel"
    case .mods: "Mods"
    case .maintenance: "Wartung"
    }
  }

  var symbol: String {
    switch self {
    case .drive: "car.fill"
    case .game: "slider.horizontal.3"
    case .mods: "shippingbox.fill"
    case .maintenance: "wrench.and.screwdriver.fill"
    }
  }
}

struct ContentView: View {
  @Environment(AppModel.self) private var model
  @State private var page: Page? = .drive

  var body: some View {
    if model.home == nil {
      MissingHomeView()
    } else {
      NavigationSplitView {
        List(Page.allCases, selection: $page) { page in
          Label(page.title, systemImage: page.symbol).tag(page)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 200)
        .toolbar(removing: .sidebarToggle)
      } detail: {
        switch page ?? .drive {
        case .drive: DriveView()
        case .game: GameView()
        case .mods: ModsView()
        case .maintenance: MaintenanceView()
        }
      }
      .toolbar {
        ToolbarItem(placement: .status) { BusyIndicator() }
      }
    }
  }
}

private struct BusyIndicator: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    if let title = model.runner.runningTitle {
      HStack(spacing: Theme.s2) {
        ProgressView().controlSize(.small)
        Text(title).font(.caption).foregroundStyle(.secondary)
      }
    } else if let failure = model.runner.lastFailure {
      Label(failure, systemImage: "exclamationmark.triangle.fill")
        .font(.caption)
        .foregroundStyle(.orange)
        .lineLimit(1)
    }
  }
}

private struct MissingHomeView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    ContentUnavailableView {
      Label("Projektordner fehlt", systemImage: "folder.badge.questionmark")
    } description: {
      Text("BeamMac braucht den Ordner mit bin/, engines/ und data/. Wähle den BeamMac-Checkout aus.")
    } actions: {
      Button("Ordner auswählen …") { model.chooseHome() }
        .buttonStyle(.borderedProminent)
    }
  }
}
