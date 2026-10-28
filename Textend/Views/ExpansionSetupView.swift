import SwiftUI

struct ExpansionSetupView: View {
  var setup: ExpansionSetup

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Label("Set Up Text Expansion", systemImage: "keyboard")
        .font(.title2.bold())
      Text(
        "\(BuildIdentity.displayName) needs Accessibility permission to recognize your keywords and insert snippets in other apps."
      )
      VStack(alignment: .leading, spacing: 12) {
        Text("1. Open Accessibility Settings below.")
        Text(
          "2. Turn on \(BuildIdentity.displayName) in the list. macOS may ask you to unlock settings."
        )
        Text("3. Return here to enable expansion.")
      }
      Text(
        "Textend does not store your typing history. Protected input fields are never expanded."
      )
      .font(.callout).foregroundStyle(.secondary)
      Divider()
      if setup.engine.hasRequiredPermissions {
        Label(
          "Accessibility is enabled. You’re ready to turn on expansion.",
          systemImage: "checkmark.circle.fill"
        )
        .foregroundStyle(.green)
      } else {
        VStack(alignment: .leading, spacing: 10) {
          Label("Waiting for Accessibility permission", systemImage: "lock")
            .foregroundStyle(.secondary)
          Button("Open Accessibility Settings…", action: setup.engine.openAccessibilitySettings)
          Text(
            "If \(BuildIdentity.displayName) isn’t listed, click + and select this app. We’ll check for permission automatically while this window is open."
          )
          .font(.caption).foregroundStyle(.secondary)
        }
      }
      HStack {
        Button("Set Up Later", action: setup.finish)
        Spacer()
        Button("Enable Expansion") { setup.enableExpansion() }
          .keyboardShortcut(.defaultAction)
          .disabled(!setup.engine.hasRequiredPermissions)
      }
      Text(
        "You can set this up later in Settings → Permissions. Snippets can still be copied manually."
      )
      .font(.caption).foregroundStyle(.secondary)
    }
    .padding(28)
    .frame(width: 520)
    .fixedSize(horizontal: false, vertical: true)
    .interactiveDismissDisabled()
    .onAppear { setup.engine.refresh() }
  }
}
