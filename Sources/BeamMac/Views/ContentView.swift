import SwiftUI

enum Page: String, CaseIterable, Identifiable {
  case drive
  case game
  case mods
  case controllers
  case maintenance

  var id: String { rawValue }

  var title: String {
    switch self {
    case .drive: "Fahren"
    case .game: "Spiel"
    case .mods: "Mods"
    case .controllers: "Controller"
    case .maintenance: "Wartung"
    }
  }

  var symbol: String {
    switch self {
    case .drive: "car.fill"
    case .game: "slider.horizontal.3"
    case .mods: "shippingbox.fill"
    case .controllers: "gamecontroller.fill"
    case .maintenance: "wrench.and.screwdriver.fill"
    }
  }
}

struct ContentView: View {
  @Environment(AppModel.self) private var model
  @AppStorage("page") private var page: Page = .drive

  var body: some View {
    if model.home == nil {
      MissingHomeView()
        .frame(width: 520, height: 360)
    } else if model.showOnboarding {
      OnboardingView()
    } else {
      NavigationSplitView {
        List(Page.allCases, selection: selection) { page in
          Label(page.title, systemImage: page.symbol).tag(page)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 200)
        .toolbar(removing: .sidebarToggle)
      } detail: {
        switch page {
        case .drive: DriveView()
        case .game: GameView()
        case .mods: ModsView()
        case .controllers: ControllersView()
        case .maintenance: MaintenanceView()
        }
      }
      .toolbar {
        ToolbarItem(placement: .status) { BusyIndicator() }
      }
      .frame(minWidth: 760, minHeight: 520)
      .background(WindowSizer(compact: false))
    }
  }
}

extension ContentView {
  /// List selection is optional; an empty click keeps the current page.
  private var selection: Binding<Page?> {
    Binding(get: { page }, set: { if let new = $0 { page = new } })
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
      Label("BeamMac ist unvollständig", systemImage: "exclamationmark.triangle")
    } description: {
      Text("Im App-Paket fehlen die Skripte. BeamMac neu laden und in den Programme-Ordner ziehen.")
    }
  }
}
