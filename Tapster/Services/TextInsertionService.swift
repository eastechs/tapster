import AppKit
import CoreGraphics

@MainActor final class TextInsertionService: ExpansionClipboard, ExpansionInsertion {
  static let eventMarker: Int64 = 0x54_4150_5354_4552
  private let focus: any ExpansionFocus
  private let pasteboard: NSPasteboard
  private let postEvent: @MainActor (CGEvent) -> Void
  private let secureInput: @MainActor () -> Bool
  private(set) var isBusy = false
  private var restoreWork: DispatchWorkItem?
  private var savedClipboard: [[NSPasteboard.PasteboardType: Data]]?
  private var ownChangeCount: Int?

  init(
    focus: any ExpansionFocus, pasteboard: NSPasteboard = .general,
    secureInput: @escaping @MainActor () -> Bool = { FocusService.secureInputEnabled },
    postEvent: @escaping @MainActor (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) }
  ) {
    self.focus = focus
    self.pasteboard = pasteboard
    self.secureInput = secureInput
    self.postEvent = postEvent
  }
  func readText() -> String? { pasteboard.string(forType: .string) }

  func replace(keyword: String, with text: String, target: ExpansionTarget) throws {
    guard !isBusy, focus.currentTarget() == target, !secureInput() else {
      throw TemplateError.invalid(
        "Expansion cancelled because the target changed or another expansion is finishing.")
    }
    // Prepare every event and clipboard representation before deleting the keyword.
    let usesPasteboard =
      text.count > 200 || text.contains("\n") || text.contains("\r") || text.contains("\t")
    var events: [CGEvent] = []
    for _ in keyword {
      events += try keyEvents(51)
    }
    if usesPasteboard {
      events += try keyEvents(9, flags: .maskCommand)
    } else {
      // Keep surrogate pairs and composed characters together in each Unicode event.
      for character in text {
        let units = Array(String(character).utf16)
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        else {
          throw TemplateError.invalid("macOS could not create insertion events.")
        }
        down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        events += [down, up]
      }
    }
    guard focus.currentTarget() == target, !secureInput() else {
      throw TemplateError.invalid("Expansion cancelled because focus changed.")
    }
    if usesPasteboard {
      savedClipboard =
        try pasteboard.pasteboardItems?.map { item in
          var representations: [NSPasteboard.PasteboardType: Data] = [:]
          for type in item.types {
            guard let data = item.data(forType: type) else {
              throw TemplateError.invalid(
                "The clipboard could not be preserved. Your keyword was left unchanged.")
            }
            representations[type] = data
          }
          return representations
        } ?? []
      pasteboard.clearContents()
      guard pasteboard.setString(text, forType: .string) else {
        ownChangeCount = pasteboard.changeCount
        restoreClipboard()
        throw TemplateError.invalid("The expansion could not be written to the clipboard.")
      }
      ownChangeCount = pasteboard.changeCount
    }
    guard focus.currentTarget() == target, !secureInput() else {
      restoreClipboard()
      throw TemplateError.invalid("Expansion cancelled because focus changed.")
    }
    isBusy = true
    for event in events {
      event.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker)
      postEvent(event)
    }
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.restoreClipboard()
      self.isBusy = false
    }
    restoreWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + (usesPasteboard ? 0.3 : 0.04), execute: work)
  }

  func finish() {
    restoreWork?.cancel()
    restoreWork = nil
    restoreClipboard()
    isBusy = false
  }

  private func restoreClipboard() {
    defer {
      savedClipboard = nil
      ownChangeCount = nil
    }
    guard let savedClipboard, ownChangeCount == pasteboard.changeCount else { return }
    let items = savedClipboard.map { representations in
      let item = NSPasteboardItem()
      for (type, data) in representations { item.setData(data, forType: type) }
      return item
    }
    pasteboard.clearContents()
    if !items.isEmpty { pasteboard.writeObjects(items) }
  }

  private func keyEvents(_ key: CGKeyCode, flags: CGEventFlags = []) throws -> [CGEvent] {
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true),
      let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)
    else {
      throw TemplateError.invalid("macOS could not create insertion events.")
    }
    down.flags = flags
    up.flags = flags
    return [down, up]
  }
}
