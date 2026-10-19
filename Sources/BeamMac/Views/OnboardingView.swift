import SwiftUI

/// First run: checks the Mac, installs Wine and Steam, waits for the Steam login
/// and hands the game install to Steam. Each step reads its state from the model,
/// so the list stays right when the user does a step outside the app.
struct OnboardingView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var appeared = false

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.s5) {
      header
      VStack(spacing: Theme.s2) {
        ForEach(Array(OnboardingStep.allCases.enumerated()), id: \.element) { index, step in
          StepRow(step: step)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 8)
            .animation(
              reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8).delay(Double(index) * 0.08),
              value: appeared)
        }
      }
      footer
    }
    .padding(Theme.s6)
    .frame(width: 560)
    .fixedSize(horizontal: false, vertical: true)
    .background(WindowSizer(compact: true))
    .onAppear { appeared = true }
  }

  private var header: some View {
    HStack(spacing: Theme.s4) {
      CrashMarker(size: 56)
      VStack(alignment: .leading, spacing: Theme.s1) {
        Text("BeamMac einrichten")
          .font(.title2.weight(.semibold))
        Text("Danach meldest du dich nur noch bei Steam an.")
          .foregroundStyle(.secondary)
      }
    }
  }

  private var footer: some View {
    HStack {
      Spacer()
      Button("Später") { model.onboardingSkipped = true }
        .buttonStyle(.link)
        .help("Zur App wechseln. Das Einrichten geht jederzeit unter Wartung weiter.")
    }
  }
}

enum OnboardingStep: CaseIterable {
  case mac
  case install
  case login
  case game
}

private struct StepRow: View {
  @Environment(AppModel.self) private var model
  let step: OnboardingStep

  private enum State { case done, current, waiting, blocked }

  var body: some View {
    let state = self.state
    HStack(alignment: .top, spacing: Theme.s3) {
      Image(systemName: symbol(for: state))
        .font(.title3)
        .foregroundStyle(tint(for: state))
        .symbolRenderingMode(.hierarchical)
        .frame(width: 24)
      VStack(alignment: .leading, spacing: Theme.s1) {
        Text(title)
          .font(.headline)
          .foregroundStyle(state == .waiting ? .secondary : .primary)
        Text(caption)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        if state == .current { progress }
      }
      Spacer(minLength: Theme.s3)
      if state == .current || state == .blocked { action }
    }
    .padding(Theme.s4)
    .background(
      state == .current ? AnyShapeStyle(.primary.opacity(0.05)) : AnyShapeStyle(.clear),
      in: .rect(cornerRadius: Theme.rowRadius, style: .continuous))
  }

  private var state: State {
    switch step {
    case .mac:
      if !model.rosettaInstalled { return .blocked }
      return .done
    case .install:
      if model.isSetUp { return .done }
      return model.rosettaInstalled ? .current : .waiting
    case .login:
      if model.steamLoggedIn { return .done }
      return model.isSetUp ? .current : .waiting
    case .game:
      if model.gameInstalled && model.transfer == nil { return .done }
      return model.isSetUp && model.steamLoggedIn ? .current : .waiting
    }
  }

  private var title: String {
    switch step {
    case .mac: "Dieser Mac"
    case .install: "Wine, DXMT und Steam installieren"
    case .login: "Bei Steam anmelden"
    case .game: "BeamNG.drive installieren"
    }
  }

  private var caption: String {
    switch step {
    case .mac:
      let space = model.freeSpace.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
      let rosetta = model.rosettaInstalled ? "Rosetta ist installiert." : "Rosetta fehlt. Wine braucht es für Steam und das Spiel."
      guard let space else { return rosetta }
      let enough = (model.freeSpace ?? 0) >= AppModel.requiredSpace
      return rosetta + " \(space) frei" + (enough ? "." : ", BeamNG braucht rund 70 GB.")
    case .install:
      return "Lädt rund 265 MB: Wine 10 von Sikarugir, DXMT, Apples D3DMetal aus dem Game Porting Toolkit und Steam für Windows. Nichts davon landet in /Programme."
    case .login:
      return "Steam öffnet sich. Nach der Anmeldung geht es hier von selbst weiter."
    case .game:
      return "Rund 55 GB. Steam fragt einmal nach dem Speicherort, der Vorschlag passt."
    }
  }

  @ViewBuilder
  private var progress: some View {
    switch step {
    case .install:
      if let progress = model.runner.progress {
        VStack(alignment: .leading, spacing: 2) {
          ProgressView(value: progress.fraction)
          Text("\(progress.step) von \(progress.total): \(progress.title)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.top, Theme.s1)
      }
    case .game:
      if let transfer = model.transfer {
        VStack(alignment: .leading, spacing: 2) {
          ProgressView(value: transfer.fraction)
          Text(transfer.isDownloading
            ? "\(ByteCountFormatter.string(fromByteCount: transfer.downloaded, countStyle: .file)) von \(ByteCountFormatter.string(fromByteCount: transfer.toDownload, countStyle: .file))"
            : "Wird installiert")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.top, Theme.s1)
      }
    default:
      EmptyView()
    }
  }

  @ViewBuilder
  private var action: some View {
    let busy = model.runner.isBusy
    switch step {
    case .mac:
      Button("Rosetta installieren") { Task { await model.installRosetta() } }
    case .install:
      Button("Installieren") { Task { await model.runSetup() } }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(busy)
    case .login:
      Button(model.steamRunning ? "Steam zeigen" : "Steam öffnen") { Task { await model.openSteam() } }
        .disabled(busy)
    case .game:
      if model.transfer == nil {
        Button("Installieren") { Task { await model.installGame() } }
          .buttonStyle(.borderedProminent)
          .disabled(busy)
      }
    }
  }

  private func symbol(for state: State) -> String {
    switch state {
    case .done: "checkmark.circle.fill"
    case .current: "arrow.right.circle.fill"
    case .waiting: "circle"
    case .blocked: "exclamationmark.triangle.fill"
    }
  }

  private func tint(for state: State) -> Color {
    switch state {
    case .done: .green
    case .current: .accentColor
    case .waiting: .secondary
    case .blocked: .orange
    }
  }
}
