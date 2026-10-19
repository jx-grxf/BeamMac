import SwiftUI
import UniformTypeIdentifiers

struct ModsView: View {
  @Environment(AppModel.self) private var model
  @State private var selection = Set<Mod.ID>()
  @State private var importing = false
  @State private var dropTargeted = false

  var body: some View {
    let library = model.mods

    Group {
      if library.folder == nil {
        ContentUnavailableView {
          Label("Noch kein Mod-Ordner", systemImage: "shippingbox")
        } description: {
          Text("BeamNG legt ihn beim ersten Start an. Danach erscheinen hier alle Mods als ZIP-Dateien.")
        }
      } else if library.mods.isEmpty {
        ContentUnavailableView {
          Label("Keine Mods", systemImage: "shippingbox")
        } description: {
          Text("ZIP-Dateien hierher ziehen oder über „Mod hinzufügen“ auswählen.")
        }
      } else {
        List(library.mods, selection: $selection) { mod in
          ModRow(mod: mod)
            .contextMenu {
              Button("Im Finder zeigen") { model.reveal(mod.url) }
              Button("In den Papierkorb", role: .destructive) { trash(ids: [mod.id]) }
            }
        }
        .onDeleteCommand { trash(ids: selection) }
      }
    }
    .overlay {
      if dropTargeted {
        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
          .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
          .padding(Theme.s3)
          .allowsHitTesting(false)
      }
    }
    .dropDestination(for: URL.self) { urls, _ in
      guard let home = model.home, library.folder != nil else { return false }
      Task { await library.add(urls, home: home) }
      return urls.contains { $0.pathExtension.lowercased() == "zip" }
    } isTargeted: { dropTargeted = $0 }
    .safeAreaInset(edge: .bottom) { footer(library) }
    .navigationTitle("Mods")
    .toolbar {
      ToolbarItemGroup {
        Button {
          importing = true
        } label: {
          Label("Mod hinzufügen", systemImage: "plus")
        }
        .help("ZIP-Datei in den Mod-Ordner kopieren")
        .disabled(library.folder == nil)

        Button {
          if let folder = library.folder { model.reveal(folder) }
        } label: {
          Label("Ordner öffnen", systemImage: "folder")
        }
        .help("Mod-Ordner im Finder zeigen")
        .disabled(library.folder == nil)
      }
    }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.zip], allowsMultipleSelection: true) { result in
      guard let home = model.home, case .success(let urls) = result else { return }
      Task { await library.add(urls, home: home) }
    }
    .task(id: model.home) {
      guard let home = model.home else { return }
      await library.reload(home: home)
    }
  }

  @ViewBuilder
  private func footer(_ library: ModLibrary) -> some View {
    if library.folder != nil {
      HStack {
        if let error = library.lastError {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .lineLimit(1)
        } else {
          let total = library.mods.reduce(Int64(0)) { $0 + $1.size }
          Text("\(library.mods.count) Mods · \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
      .font(.caption)
      .padding(.horizontal, Theme.s4)
      .padding(.vertical, Theme.s2)
      .background(.bar)
    }
  }

  private func trash(ids: Set<Mod.ID>) {
    guard let home = model.home else { return }
    let mods = model.mods.mods.filter { ids.contains($0.id) }
    selection.subtract(ids)
    Task { await model.mods.trash(mods, home: home) }
  }
}

private struct ModRow: View {
  let mod: Mod

  var body: some View {
    HStack(spacing: Theme.s3) {
      Image(systemName: "shippingbox.fill")
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text(mod.name)
        Text(mod.modified, format: .dateTime.day().month().year())
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Text(ByteCountFormatter.string(fromByteCount: mod.size, countStyle: .file))
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 2)
  }
}
