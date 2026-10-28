import Foundation

struct HelpTopic: Identifiable {
  struct Section: Identifiable {
    var title: String
    var body: String
    var example: String? = nil
    var id: String { title }
  }

  var id: String
  var title: String
  var symbol: String
  var summary: String
  var sections: [Section]
  var searchText: String {
    ([title, summary] + sections.flatMap { [$0.title, $0.body, $0.example ?? ""] })
      .joined(separator: "\n")
  }

  static let all: [HelpTopic] = [
    HelpTopic(
      id: "quick-access", title: "Quick Access", symbol: "magnifyingglass",
      summary: "Find and insert saved snippets and Compositions without opening the library.",
      sections: [
        Section(
          title: "Open and configure",
          body:
            "Press ⇧⌘Space, or choose Quick Access from Textend’s menu bar menu. Change, clear, or restore the shortcut in Settings → General → Quick Access. The shortcut stays on this Mac. The recorder warns about known conflicts, but cannot detect every shortcut used by another app."
        ),
        Section(
          title: "Choose and insert",
          body:
            "Search names, keywords, collection names, and content. Favorites appear first. Use arrow keys to choose, Return to insert, Command-Return to copy, and Escape to close. Current App shows eligible items; All Snippets also lets you browse and copy items restricted to other apps."
        ),
        Section(
          title: "Destination and clipboard",
          body:
            "Quick Access captures the original field, selection, and clipboard when opened. Insertion replaces that selection or uses its caret. If Textend cannot verify the field or Accessibility permission is unavailable, use Copy. Moving to another app cancels the palette. Excluded apps and secure fields cannot receive insertions. Date values resolve when you confirm; copying never positions the caret."
        ),
        Section(
          title: "Paused or manual-only items",
          body:
            "Quick Access can insert valid items with no keyword, with automatic expansion disabled, or while global automatic expansion is paused. App restrictions still apply. Textend does not execute commands or press Return to submit inserted text."
        ),
      ]),
    HelpTopic(
      id: "app-collections", title: "App-Specific Collections", symbol: "app.badge",
      summary: "Make a collection available in selected applications.",
      sections: [
        Section(
          title: "Choose applications",
          body:
            "Create or edit a collection and choose All Apps or Selected Apps. Add one or more applications. Every member inherits these restrictions. Missing apps on another Mac retain their restrictions. Uncollected items are global."
        ),
        Section(
          title: "Keyword precedence",
          body:
            "An enabled, valid app-specific item overrides a global item with the same keyword in its selected apps. Disjoint app scopes may reuse keywords. Two app-specific items with overlapping scopes conflict in those apps, with no global fallback. Local edits reject new conflicts; remote conflicts pause affected expansions until resolved."
        ),
        Section(
          title: "Sync and deletion",
          body:
            "Restrictions sync through iCloud. Update every synced Mac before using them because older Textend versions cannot enforce restrictions. Deleting a restricted collection retains its items and makes them global; new conflicts pause automatic expansion. A missing collection blocks insertion until it arrives, while valid content can still be copied."
        ),
      ]),
    HelpTopic(
      id: "compositions", title: "Compositions", symbol: "square.stack",
      summary: "Arrange live snippets and literal text into one expansion.",
      sections: [
        Section(
          title: "Create a Composition",
          body:
            "Browse Compositions in their sidebar section below All Snippets. Choose New Composition from File or the toolbar’s New menu. Add snippets using the searchable picker, or add literal text. Reorder blocks by dragging their handles or using Move Up and Move Down. Choose None, Space, New Line, or Blank Line between blocks. New Line is the default."
        ),
        Section(
          title: "Live sources",
          body:
            "Source edits automatically update every Composition that references them. Disabled source keywords do not disable their reusable content. Compositions cannot contain other Compositions. Deleting a source leaves a broken reference; remove the block or replace it by adding a different snippet. No partial expansion is inserted."
        ),
        Section(
          title: "Placeholders and cursor",
          body:
            "Each source uses its own placeholder mappings with one clipboard snapshot and date/time for the entire result. Literal blocks are inserted exactly as written, including braces. Only one cursor marker is allowed across all source occurrences. The preview uses sample clipboard text; Copy Expanded Text uses your current clipboard."
        ),
        Section(
          title: "Availability and sync",
          body:
            "A Composition is available only in apps permitted by its own collection and every source snippet. Its editor shows the resulting availability. Conflicting restrictions prevent insertion, but valid content remains copyable. Compositions, order, separators, and source references sync. Older Textend versions do not display Compositions."
        ),
        Section(
          title: "Backups",
          body:
            "Version 2 backups include Compositions and their referenced snippets, plus collection app restrictions. Textend still imports version 1 backups. Older versions reject the newer backup format instead of silently removing features."
        ),
      ]),
    HelpTopic(
      id: "icloud", title: "iCloud Sync", symbol: "icloud",
      summary: "Sync your saved library between Macs using your iCloud account.",
      sections: [
        Section(
          title: "Enable sync",
          body:
            "Open Settings → iCloud and enable Sync snippets with iCloud. Your saved local library joins this account’s library after restarting. Resolve any unsaved draft when asked. A fresh library starts empty; File → Add Example Snippets adds starter examples if you want them."
        ),
        Section(
          title: "What syncs",
          body:
            "Saved snippets, Compositions, collection app restrictions, favorites, enabled states, and placeholder mappings sync. Appearance, expansion delay, excluded applications, permissions, clipboard contents, and unsaved drafts stay on each Mac."
        ),
        Section(
          title: "Offline and activity",
          body:
            "Keep editing your local library while offline. iCloud transfers changes when available, so delivery can take time. Last successful transfer reports an observed import or export; it does not mean every Mac has received the changes. Check iCloud Account refreshes account availability, not the transfer schedule."
        ),
        Section(
          title: "Conflicts",
          body:
            "CloudKit merges saved edits automatically. Concurrent edits to the same field may overwrite one another. Duplicate keywords within overlapping scopes pause affected automatic expansions until you rename or clear a keyword. You can still copy a valid snippet manually. If a saved snippet changes while you have a draft, saving applies your changed fields while retaining remote changes to untouched fields. A remotely deleted draft can be saved as a new snippet."
        ),
        Section(
          title: "Turn off or change accounts",
          body:
            "Turning sync off requires a restart and keeps the downloaded library on this Mac without deleting cloud data. An iCloud account change pauses library editing and expansion until restart. Textend preserves a local copy; enabling another account opens a separate library and does not upload the previous account’s snippets. Export a backup if you deliberately want to transfer snippets between accounts."
        ),
        Section(
          title: "Backups",
          body:
            "Use File → Export Backup for a portable JSON copy. Sync is not a substitute for a backup because deletions also sync. Before the V3 migration, Textend creates a local SQLite backup beside its library."
        ),
      ]),
    HelpTopic(
      id: "start", title: "Getting Started", symbol: "sparkles",
      summary: "Turn short keywords into the text you use every day.",
      sections: [
        Section(
          title: "Create your first snippet",
          body:
            "Choose File → New Snippet (⌘N). Give it a name, enter a keyword such as :hello, and write your text in Template. Keep Expansion enabled, then save with ⌘S.",
          example: "Name: Greeting\nKeyword: :hello\nTemplate: Hello! Thanks for getting in touch."),
        Section(
          title: "Enable expansion",
          body:
            "Open Settings → General and enable text expansion. Allow Textend in System Settings → Privacy & Security → Accessibility when prompted. You can still manage and copy snippets without this permission."
        ),
        Section(
          title: "Try it",
          body:
            "Type your saved keyword in Settings → General → Try Expansion, or in a supported text field such as a TextEdit document. The library editor itself is excluded. Textend inserts text without pressing Return or executing commands."
        ),
        Section(
          title: "Keep Textend available",
          body:
            "Closing the library leaves Textend running in the menu bar. Use its menu to open the library, access Settings, pause expansion, or quit. In Settings → General → App Behavior, turn off Show Textend in the Dock, then quit and reopen Textend. The Dock icon stays hidden even while windows are open. Changing the setting does not hide windows or interrupt editing; it takes effect on the next launch. The preference is remembered on this Mac. Launch at login is optional in the same section."
        ),
      ]),
    HelpTopic(
      id: "keywords", title: "Keywords & Timing", symbol: "keyboard",
      summary: "Control when a keyword expands and how overlapping keywords behave.",
      sections: [
        Section(
          title: "Choose a keyword",
          body:
            "Keywords are case-sensitive and match at a word start, not inside a longer word. Exact duplicate keywords cannot be saved. Leave the keyword empty if you only want to copy the snippet manually."
        ),
        Section(
          title: "Overlapping keywords",
          body:
            "If you have gc and gco, typing gc starts a short delay. Type o before the delay ends to expand gco instead. Pausing too long expands gc first. A keyword with no longer alternatives expands immediately."
        ),
        Section(
          title: "Tune the delay",
          body:
            "Settings → General → Ambiguous keyword delay accepts 100 to 1,000 milliseconds in 50 ms steps. The default is 250 ms. Increase it if a shorter keyword expands before you finish typing a longer one."
        ),
        Section(
          title: "Cancel a pending match",
          body:
            "Backspace, moving the caret, switching fields or apps, shortcuts, and pausing expansion cancel a pending match. Typing an incomplete or unrelated continuation leaves the typed text unchanged instead of expanding a shorter prefix."
        ),
      ]),
    HelpTopic(
      id: "placeholders", title: "Placeholders", symbol: "curlybraces",
      summary: "Add clipboard text, dates, and a caret position to a template.",
      sections: [
        Section(
          title: "Insert a value",
          body:
            "Use Insert Placeholder to choose Clipboard or Date & Time and give the placeholder a name. You can also type {name} and choose its source below the template. Names start with a letter or underscore and contain letters, numbers, or underscores. Repeated names share one source."
        ),
        Section(
          title: "Use the clipboard",
          body:
            "Copy text or files before expanding. Copied files use their full paths; multiple paths are separated by newlines. Text and paths are inserted literally, without adding quotes or escaping. Image pixels alone have no file path, so save and copy the image file first. If the clipboard has neither text nor file references, Textend leaves the keyword unchanged.",
          example:
            "Template: git commit {commit_message}\nSource: commit_message → Clipboard\nClipboard: Fix login redirect\nResult: git commit Fix login redirect"
        ),
        Section(
          title: "Place the caret",
          body:
            "Choose Insert Placeholder → Cursor Position, or type {cursor} where you want to continue typing. Use one marker per template; it needs no source mapping and is removed from the inserted text. Without a marker, the caret stays at the end, including after trailing spaces. Write {{cursor}} to insert the literal text {cursor}. Copy Expanded Text removes the marker but cannot reposition the caret when you paste manually. If you type or move focus before placement finishes, Textend cancels the pending move. Editors that alter pasted text, such as adding indentation, may require you to position the caret manually.",
          example:
            "Template: git commit -m \"{cursor}\"\nAfter expansion: git commit -m \"│\"\n│ shows the caret; it is not inserted."
        ),
        Section(
          title: "Format a date",
          body:
            "Date & Time uses your current time zone. Enter a format and check the live example. yyyy-MM-dd produces a date such as 2026-10-24; HH:mm adds 24-hour time."
        ),
        Section(
          title: "Literal braces and preview",
          body:
            "Write {{ and }} for literal braces. Fix unmatched braces and missing sources before saving. The Preview panel uses sample clipboard text; Copy Expanded Text uses your actual clipboard. Textend does not add quotes, command flags, or escaping."
        ),
      ]),
    HelpTopic(
      id: "organize", title: "Organize Snippets", symbol: "folder",
      summary: "Use collections, favorites, and search to find your snippets.",
      sections: [
        Section(
          title: "Collections",
          body:
            "Click New Collection at the bottom of the sidebar or use ⇧⌘N. Assign a snippet using its Collection menu. Control-click a collection to rename or delete it. Deleting a collection keeps its snippets in All Snippets."
        ),
        Section(
          title: "Favorites and search",
          body:
            "Use the star beside a snippet’s title to mark it as a favorite, then save. Favorites appear in the sidebar filter. Search matches snippet names, keywords, and templates. Press ⌘F in the library to focus search."
        ),
        Section(
          title: "Save your changes",
          body:
            "Changes stay in a draft until you save. Switching away from an edited snippet offers Save, Discard, or Cancel. Control-click a snippet for actions such as Duplicate, Move to Collection, or Delete. A duplicate starts without a keyword to avoid conflicts."
        ),
      ]),
    HelpTopic(
      id: "appearance", title: "Appearance", symbol: "circle.lefthalf.filled",
      summary: "Choose how Textend looks without changing your Mac’s settings.",
      sections: [
        Section(
          title: "System, Light, or Dark",
          body:
            "Open Settings → Appearance. System follows your Mac’s appearance; Light and Dark keep Textend in that mode. The choice applies to the library, Settings, Help, and app panels, and is remembered when you reopen Textend."
        ),
        Section(
          title: "Accent color",
          body:
            "Choose Blue, Purple, Pink, Red, Orange, Yellow, Green, or Graphite. Controls, sidebar icons, list selections, input borders, placeholder highlights, and the running app’s Dock icon update immediately. Finder and Spotlight keep the installed blue icon; the menu-bar mark stays monochrome. Window controls and system menus continue to use your macOS accent color."
        ),
      ]),
    HelpTopic(
      id: "backups", title: "Backups & Updates", symbol: "externaldrive",
      summary: "Keep a copy of your library and manage app updates.",
      sections: [
        Section(
          title: "Export a backup",
          body:
            "Choose File → Export Backup to save your library as a JSON file. Store it somewhere you can find again. Textend keeps a local library. Optional iCloud sync is available in Settings → iCloud; backups remain useful when sync is enabled."
        ),
        Section(
          title: "Import a backup",
          body:
            "Choose File → Import Backup. Import adds the contents to your existing library. Conflicting identifiers or exact duplicate keywords reject the whole import, so a rejected backup does not partially change your library."
        ),
        Section(
          title: "Check for updates",
          body:
            "Use Textend → Check for Updates or the menu bar command. Settings → Updates controls automatic checks and installation. Development builds disable updates. An update that needs to restart Textend asks you to resolve unsaved snippet changes first."
        ),
      ]),
    HelpTopic(
      id: "troubleshooting", title: "Troubleshooting", symbol: "wrench.and.screwdriver",
      summary: "Start here if a saved keyword does not expand.",
      sections: [
        Section(
          title: "Check the basics",
          body:
            "Make sure Textend is running, expansion is active, the snippet is saved and enabled, and its keyword matches exactly. If it uses Clipboard, copy some text first. Try the same keyword in Settings → General → Try Expansion."
        ),
        Section(
          title: "Check permissions",
          body:
            "Settings → Permissions shows Accessibility status and opens the corresponding system settings. If a replaced or differently signed app appears enabled but still cannot expand, remove its old Accessibility entry and add the current Textend app again."
        ),
        Section(
          title: "Check the target app",
          body:
            "Look under Settings → Excluded Apps. Password fields and Secure Input are not expanded. Composition input methods and some editors cannot be tracked reliably, so expansion pauses there. Test in a plain TextEdit document to narrow down an app-specific issue."
        ),
        Section(
          title: "A shorter keyword expands too soon",
          body:
            "Increase the ambiguous keyword delay in Settings → General, or use keywords that do not share a prefix. The delay only applies when a saved, enabled longer keyword exists."
        ),
      ]),
    HelpTopic(
      id: "shortcuts", title: "Keyboard Shortcuts", symbol: "command",
      summary: "Common actions are available from the keyboard.",
      sections: [
        Section(
          title: "Library",
          body:
            "⌘N  New snippet\n⇧⌘N  New collection\n⌘S  Save snippet\n⌘D  Duplicate snippet\n⌘F  Find snippet"
        ),
        Section(
          title: "App and editing",
          body:
            "⌘,  Settings\n⌘F  Search Help while this window is active\n⌘Z  Undo\n⇧⌘Z  Redo\n⌘Q  Quit Textend"
        ),
      ]),
  ]
}
