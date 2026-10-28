import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ApplicationLabel: View {
  var bundleID: String
  var body: some View {
    HStack(spacing: 8) {
      if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(
          width: 20, height: 20)
      } else {
        Image(systemName: "app.dashed")
      }
      Text(Self.name(bundleID)).lineLimit(1).help(bundleID)
    }
  }
  static func availability(_ item: SnippetRecord, in library: ExpansionLibrary) -> String {
    guard let scope = library.scope(of: item) else { return "All apps" }
    return scope.isEmpty
      ? "Unavailable: check collections and source snippets."
      : scope.sorted().map(name).joined(separator: ", ")
  }
  static func name(_ id: String) -> String {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
      return id
    }
    return url.deletingPathExtension().lastPathComponent
  }
  static func choose(_ completion: @escaping ([String]) -> Void) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.applicationBundle]
    panel.allowsMultipleSelection = true
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.begin { response in
      guard response == .OK else { return }
      completion(panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier })
    }
  }
}
