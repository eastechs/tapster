import AppKit
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
  case system, light, dark

  var id: String { rawValue }
  var name: String { rawValue.capitalized }

  @MainActor func apply() {
    let name: NSAppearance.Name?
    switch self {
    case .system: name = nil
    case .light: name = .aqua
    case .dark: name = .darkAqua
    }
    guard NSApp.appearance?.name != name else { return }
    NSApp.appearance = name.flatMap { NSAppearance(named: $0) }
  }
}

enum AppAccent: String, CaseIterable, Identifiable {
  case blue, purple, pink, red, orange, yellow, green, graphite

  var id: String { rawValue }
  var name: String { rawValue.capitalized }

  var nsColor: NSColor {
    switch self {
    case .blue: .systemBlue
    case .purple: .systemPurple
    case .pink: .systemPink
    case .red: .systemRed
    case .orange: .systemOrange
    case .yellow: .systemYellow
    case .green: .systemGreen
    case .graphite: .systemGray
    }
  }

  var color: Color { Color(nsColor: nsColor) }
}

@MainActor enum ThemedAppIcon {
  private static var appliedAccent: AppAccent?

  static func apply(_ accent: AppAccent) {
    guard appliedAccent != accent else { return }
    if accent == .blue {
      // Restore the installed layered icon, including its native renditions.
      NSApp.applicationIconImage = nil
    } else {
      guard let artwork = NSImage(named: "ThemeIcon-\(accent.rawValue)") else { return }
      // Icon Composer exports are full bleed. Match the installed macOS icon's
      // 80% artwork footprint so changing colors never enlarges the Dock icon.
      let size = NSSize(width: 1024, height: 1024)
      let icon = NSImage(size: size, flipped: false) { bounds in
        artwork.draw(in: bounds.insetBy(dx: bounds.width * 0.1, dy: bounds.height * 0.1))
        return true
      }
      NSApp.applicationIconImage = icon
    }
    appliedAccent = accent
  }
}

private struct AppAccentKey: EnvironmentKey {
  static let defaultValue = AppAccent.blue
}

extension EnvironmentValues {
  var textendAccent: AppAccent {
    get { self[AppAccentKey.self] }
    set { self[AppAccentKey.self] = newValue }
  }
}

private struct AppTheme: ViewModifier {
  @AppStorage("textendAccent") private var accent = AppAccent.blue
  @AppStorage("textendAppearance") private var appearance = AppAppearance.system

  func body(content: Content) -> some View {
    content
      .environment(\.textendAccent, accent)
      .tint(accent.color)
      .accentColor(accent.color)
      .onChange(of: accent) { _, value in ThemedAppIcon.apply(value) }
      .onChange(of: appearance, initial: true) { _, value in value.apply() }
  }
}

extension View {
  /// Each AppKit hosting root observes the same preference without replacing its content.
  func textendTheme() -> some View { modifier(AppTheme()) }

  func textendSelection(_ isSelected: Bool) -> some View {
    modifier(ThemedListSelection(isSelected: isSelected))
  }
}

private struct ThemedListSelection: ViewModifier {
  var isSelected: Bool
  @Environment(\.textendAccent) private var accent
  @Environment(\.controlActiveState) private var activeState

  private var foreground: Color {
    guard isSelected else { return .primary }
    guard activeState != .inactive else { return Color(nsColor: .unemphasizedSelectedTextColor) }
    return [.yellow, .green, .orange, .graphite].contains(accent) ? .black : .white
  }

  func body(content: Content) -> some View {
    content
      .background(ThemedSelectionBridge())
      .foregroundStyle(foreground)
      .listItemTint(.fixed(isSelected ? foreground : accent.color))
      .labelStyle(ThemedSelectionLabelStyle(color: isSelected ? foreground : accent.color))
      .listRowBackground(
        isSelected
          ? RoundedRectangle(cornerRadius: 6)
            .fill(
              activeState == .inactive
                ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : accent.color
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
          : nil)
  }
}

private struct ThemedSelectionLabelStyle: LabelStyle {
  var color: Color

  func makeBody(configuration: Configuration) -> some View {
    Label {
      configuration.title
    } icon: {
      configuration.icon.foregroundStyle(color)
    }
    .labelStyle(.titleAndIcon)
  }
}

struct AccentColorPicker: View {
  @AppStorage("textendAccent") private var accent = AppAccent.blue

  var body: some View {
    HStack {
      Picker("Accent color", selection: $accent) {
        ForEach(AppAccent.allCases) { color in
          Text(color.name).tag(color)
        }
      }
      .pickerStyle(.menu)
      Circle().fill(accent.color).frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }
  }
}

struct AppearanceSettingsView: View {
  @AppStorage("textendAppearance") private var appearance = AppAppearance.system

  var body: some View {
    Form {
      Section {
        Picker("Appearance", selection: $appearance) {
          ForEach(AppAppearance.allCases) { choice in
            Text(choice.name).tag(choice)
          }
        }
        .pickerStyle(.menu)
        AccentColorPicker()
      } header: {
        Text("Appearance")
      } footer: {
        Text(
          "System follows your Mac’s Light or Dark appearance. Accent color also changes the running app’s Dock icon. Finder keeps the installed blue icon. Window controls and system menus use your macOS accent color."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}
