import AppKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
  static let quickAccess = Self(
    "quickAccess", initial: .init(.space, modifiers: [.command, .shift]))
}

private final class QuickAccessPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

@MainActor @Observable final class QuickAccessController: NSObject, NSWindowDelegate {
  let state: AppState
  var query = ""
  var allApps = false
  var selectedID: UUID?
  var message: String?
  private(set) var clipboard: String?
  private(set) var bundleID: String?
  private(set) var presentation = 0
  private var target: FocusService.Snapshot?
  private var panel: NSPanel?
  private var keyMonitor: Any?
  private var outsideMonitor: Any?
  private var activationObserver: NSObjectProtocol?
  private var isInserting = false
  private var generation = 0

  init(state: AppState) {
    self.state = state
    super.init()
    KeyboardShortcuts.onKeyUp(for: .quickAccess) { [weak self] in self?.toggle() }
  }

  var results: [SnippetRecord] {
    state.store.library.search(query, bundleID: bundleID, allApps: allApps)
  }
  var selected: SnippetRecord? { results.first { $0.id == selectedID } ?? results.first }
  var insertionAvailable: Bool {
    guard target != nil, let selected else { return false }
    return !state.engine.excludedBundleIDs.contains(bundleID ?? "")
      && state.store.library.allows(selected, in: bundleID)
      && (try? state.store.library.validateContent(selected)) != nil
  }
  var preview: String {
    guard let selected else { return "No matching snippets or Compositions." }
    do { return try state.store.library.resolve(selected, clipboard: clipboard).text } catch {
      return error.localizedDescription
    }
  }

  func toggle() {
    if panel?.isVisible == true {
      dismiss()
      return
    }
    guard !isInserting, !state.expansionSetup.isPresented else { return }
    target = state.engine.captureInsertionTarget()
    bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    clipboard = TextInsertionService.clipboardText(from: .general)
    query = ""
    allApps = false
    selectedID = nil
    message = nil
    present()
  }

  private func present() {
    state.engine.setPaletteOpen(true)
    if panel == nil {
      let panel = QuickAccessPanel(
        contentRect: NSRect(x: 0, y: 0, width: 620, height: 440),
        styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered,
        defer: false)
      panel.title = "Quick Access"
      panel.titleVisibility = .hidden
      panel.titlebarAppearsTransparent = true
      panel.isFloatingPanel = true
      panel.level = .floating
      panel.hidesOnDeactivate = false
      panel.isReleasedWhenClosed = false
      panel.tabbingMode = .disallowed
      panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
      let content = NSHostingView(rootView: QuickAccessView(controller: self).textendTheme())
      // Let the panel own its size, without adding the hidden title bar to SwiftUI's ideal size.
      content.sizingOptions = []
      panel.contentView = content
      panel.delegate = self
      self.panel = panel
    }
    if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
      ?? NSScreen.main
    {
      let frame = screen.visibleFrame
      panel?.setFrameOrigin(NSPoint(x: frame.midX - 310, y: frame.midY - 180))
    }
    presentation += 1
    panel?.makeKeyAndOrderFront(nil)
    installMonitors()
  }

  private func installMonitors() {
    removeMonitors()
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [
      .keyDown, .leftMouseDown, .rightMouseDown,
    ]) { [weak self] event in
      guard let self else { return event }
      guard event.window === self.panel else {
        self.dismiss()
        return event
      }
      guard event.type == .keyDown else { return event }
      switch event.keyCode {
      case 53:
        self.dismiss()
        return nil
      case 125:
        self.moveSelection(1)
        return nil
      case 126:
        self.moveSelection(-1)
        return nil
      case 36, 76:
        self.confirm(copy: event.modifierFlags.contains(.command))
        return nil
      default: return event
      }
    }
    outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown])
    { [weak self] _ in
      self?.dismiss()
    }
    activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.dismiss() }
    }
  }

  private func removeMonitors() {
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    keyMonitor = nil
    if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
    outsideMonitor = nil
    if let activationObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
    }
    activationObserver = nil
  }

  func windowDidResignKey(_ notification: Notification) {
    if !isInserting { dismiss() }
  }

  func dismiss() {
    generation += 1
    removeMonitors()
    panel?.orderOut(nil)
    state.engine.setPaletteOpen(false)
    target = nil
    clipboard = nil
  }

  func moveSelection(_ delta: Int) {
    let items = results
    guard !items.isEmpty else { return }
    let index = items.firstIndex { $0.id == selected?.id } ?? 0
    selectedID = items[min(items.count - 1, max(0, index + delta))].id
  }

  func confirm(copy: Bool) {
    guard let selected, !isInserting else { return }
    do {
      let value = try state.store.library.resolve(selected, clipboard: clipboard)
      if copy {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(value.text, forType: .string) else {
          throw TemplateError.invalid("Couldn’t copy the expanded text.")
        }
        dismiss()
        return
      }
      guard insertionAvailable, let target else {
        throw TemplateError.invalid(
          "Insertion is unavailable here. Use Copy, or open Quick Access from an allowed text field with Accessibility permission."
        )
      }
      let revision = state.store.revision
      let request = generation
      isInserting = true
      removeMonitors()
      panel?.orderOut(nil)
      // Let the nonactivating panel release keyboard focus. Never activate a different app.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
        guard let self else { return }
        self.isInserting = false
        guard self.generation == request else { return }
        do {
          guard self.state.store.revision == revision else {
            throw TemplateError.invalid(
              "The library changed. Review the updated preview and try again.")
          }
          self.state.engine.setPaletteOpen(false)
          try self.state.engine.insertManually(value, itemID: selected.id, target: target)
          self.target = nil
          self.clipboard = nil
        } catch {
          self.message = error.localizedDescription
          self.present()
        }
      }
    } catch { message = error.localizedDescription }
  }
}

private struct QuickAccessView: View {
  @Bindable var controller: QuickAccessController
  @FocusState private var searchFocused: Bool
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField("Search snippets and Compositions", text: $controller.query)
          .textFieldStyle(.plain).font(.title3).focused($searchFocused)
          .accessibilityLabel("Search snippets and Compositions")
        Button {
          controller.dismiss()
        } label: {
          Image(systemName: "xmark.circle.fill").controlHitArea()
        }
        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Close Quick Access")
      }.padding(.horizontal, 16).padding(.vertical, 12)
      HStack {
        Picker("Show", selection: $controller.allApps) {
          Text("Current App").tag(false)
          Text("All Snippets").tag(true)
        }.pickerStyle(.segmented).frame(width: 250)
        Spacer()
        Text(controller.bundleID.map(ApplicationLabel.name) ?? "Copy only").font(.caption)
          .foregroundStyle(.secondary)
      }.padding(.horizontal, 16).padding(.bottom, 12)
      Divider()
      ScrollViewReader { proxy in
        List(
          controller.results,
          selection: Binding(
            get: { controller.selected?.id }, set: { controller.selectedID = $0 }
          )
        ) { item in
          HStack(spacing: 12) {
            Image(systemName: item.isComposition ? "square.stack" : "doc.text")
            VStack(alignment: .leading, spacing: 3) {
              Text(item.name).fontWeight(.medium).lineLimit(1)
              HStack {
                Text(
                  controller.state.store.collections.first { $0.id == item.collectionID }?.name
                    ?? "No collection")
                if controller.state.store.library.scope(of: item) != nil {
                  Image(systemName: "app.badge")
                }
              }.font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if item.isFavorite { Image(systemName: "star.fill").font(.caption) }
            Text(item.keyword).font(.system(.caption, design: .monospaced))
              .lineLimit(1).frame(maxWidth: 120, alignment: .trailing)
          }.padding(.vertical, 4).tag(item.id).id(item.id)
            .textendSelection(controller.selected?.id == item.id)
        }.listStyle(.inset)
          .onChange(of: controller.selectedID) { _, id in if let id { proxy.scrollTo(id) } }
      }
      Divider()
      Text(controller.preview).font(.system(.callout, design: .monospaced)).lineLimit(4)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 12)
      if let message = controller.message {
        Text(message).font(.caption).foregroundStyle(.orange).padding(.horizontal, 16).padding(
          .bottom, 8)
      }
      HStack {
        Text("esc Close").font(.caption).foregroundStyle(.secondary).fixedSize()
        Spacer(minLength: 12)
        if !controller.insertionAvailable, controller.selected != nil {
          Text("Open Quick Access from an allowed text field to insert.")
            .font(.caption).foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
        }
        Button("Copy ⌘↩") { controller.confirm(copy: true) }
          .disabled(controller.selected == nil).fixedSize()
        Button("Insert ↩") { controller.confirm(copy: false) }.disabled(
          !controller.insertionAvailable
        ).fixedSize()
      }.padding(.horizontal, 16).padding(.bottom, 12)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .ignoresSafeArea(.container, edges: .top)
    .background(.regularMaterial)
    .onAppear { searchFocused = true }
    .onChange(of: controller.presentation) { _, _ in searchFocused = true }
    .onChange(of: controller.query) { _, _ in controller.selectedID = nil }
    .onChange(of: controller.allApps) { _, _ in controller.selectedID = nil }
  }
}
