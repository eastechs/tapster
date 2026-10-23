# Tapster native macOS plan

Status: implemented as a native Xcode app, with automated tests and local UI verification in progress. Physical cross-app acceptance is being tested by Dave in TextEdit. Signed release packaging and notarization remain a separate release step.

Selected design: [Option 1](design/tapster-native-macos.png). This image defines the three-column composition and hierarchy. Actual controls, spacing, typography, selection, materials, and window behavior will follow macOS conventions.

## Product

Tapster manages text snippets and expands their keywords in the focused application while Tapster is running. A snippet has a name, optional keyword, template, and named dynamic placeholders. The first release covers plain text, clipboard values, and date/time values.

Example: name `Git Commit`, keyword `gc`, template `git commit {commit_message}`, with `commit_message` mapped to Clipboard. If the clipboard contains `Fix login redirect`, expansion inserts `git commit Fix login redirect`. Templates are literal: Tapster does not add quotes, flags, escaping, or execute commands. A runnable Git example can instead use `git commit -m "{commit_message}"`, with the user responsible for the template and its values.

## Native foundation

- Swift application in an Xcode macOS app project. Proposed deployment target: macOS 14 or later, using the installed stable SDK. System materials adapt to the OS and Light/Dark appearance.
- SwiftUI for scenes, split navigation, lists, forms, menus, sheets, toolbars, and settings. SF Symbols and system typography; monospaced system font for template text and keywords.
- AppKit only where needed: an `NSTextView` template editor, pasteboard access, application lifecycle, and focus coordination. Core Graphics handles event monitoring and generated keyboard events.
- SwiftData for local persistence, with explicit versioned schema and migration strategy. UserDefaults for preferences. No account or server is needed for this scope.
- Proposed initial distribution: Developer ID signed and notarized app, distributed directly. Validate permission and packaging behavior in the first milestone before making a distribution commitment.

## Screen and component mapping

| Surface | Native implementation | Behavior |
| --- | --- | --- |
| Main window | `WindowGroup`, `NavigationSplitView` with three columns | Restore window and selection state; resizable columns; standard titlebar and traffic lights |
| Collections | Sidebar-style `List`, `Section`, `Label` | All Snippets, Favorites, user collections; native selection and contextual menus |
| Snippet list | Selectable `List` and native search | Search names, keywords, and template text; short preview and keyword aligned within each row |
| Editor fields | `Form`, `TextField`, `Picker`, `Button` | Name, keyword, collection, explicit Save, inline validation |
| Template editor | `NSViewRepresentable` wrapping `NSScrollView` and `NSTextView` | Native selection, undo, copy/paste, keyboard navigation, and placeholder highlighting |
| Insert placeholder | Native `Menu` or anchored popover | Insert Clipboard or Date & Time at the caret; name and configure the placeholder |
| Placeholder mappings | Lightweight rows with `TextField` and `Picker` | Map each unique name to its source; repeated names resolve consistently |
| Preview | Read-only selectable text plus editable sample input | Resolve using sample clipboard data; do not read the real clipboard continuously |
| Menu bar companion | `MenuBarExtra` | Open Tapster, Pause/Resume Expansion, Settings, Quit |
| Settings | Dedicated `Settings` scene with native forms | Expansion delay, test field, launch at login, permission status, excluded apps |
| Commands | Native application menus and `Commands` | New, Save, Duplicate, Delete, Find, Settings, Undo/Redo |

The editor stores plain text as the source of truth. Highlight `{commit_message}` using text attributes, preserving its literal syntax. Do not build a custom text editing engine or use text attachments for tokens in the initial release.

Start around 1180 × 780 points with approximately 190-point sidebar, 280-point list, and remaining editor width. Treat these as initial proportions, then verify minimum usable widths. At narrow sizes, allow the collection sidebar to collapse and let the editor scroll vertically. Preserve native source-list density rather than recreating the mockup pixel for pixel.

## Editing and data

- `Snippet`: stable ID, name, keyword, template, collection ID, favorite/enabled state, placeholder definitions, timestamps.
- `Collection`: stable ID, name, sort order. Deleting a collection retains its snippets in All Snippets.
- `PlaceholderDefinition`: stable ID, name, source type, date/time format where applicable.
- Edit a draft rather than the live persisted model. Save validates and commits atomically, then refreshes the engine's immutable snippet index. Switching away from an unsaved draft offers Save, Discard, or Cancel.
- Validate empty names, exact duplicate keywords, malformed placeholders, and missing mappings. Empty keyword is allowed for manually copied snippets. Prefix overlaps are allowed.
- One resolver powers preview and actual expansion. It accepts injected clipboard text and a clock for deterministic tests. Resolve replacements once; inserted clipboard text is never parsed as another template.
- Support repeated placeholders and a documented way to escape literal braces. Empty/non-text clipboard leaves the keyword unchanged and reports a concise status instead of deleting it.
- Standard create, rename, duplicate, favorite, move, and delete flows. Include versioned JSON export/import through native file panels for backup and transfer; validate imports before writing.

## Expansion behavior

First-release rule: case-sensitive expansion when a keyword finishes at a known word start. Unambiguous keywords expand immediately; overlapping exact matches use the debounce below. No Enter or extra shortcut is required. Clear context when focus or app changes, the mouse moves the caret, navigation shortcuts are used, or input becomes uncertain. Do not match inside a longer word or trigger recursively on generated output.

Allow `gc` and `gco` together. When `gc` matches, wait 250 ms for more typing. Quickly completing `gco` selects the longer match. Incomplete or unrelated continuation cancels the shorter match without replacing text underneath the additional characters. Nested prefixes apply the same rule. A pause longer than the delay can expand the shorter keyword before the longer keyword is finished.

Settings → General → Expansion exposes the ambiguous keyword delay as a native numeric field and stepper: 250 ms default, 100–1,000 ms range, 50 ms steps, persisted with `@AppStorage`. Changes cancel pending expansion. Timers carry generation identifiers so stale callbacks cannot act on newer input. Backspace, caret/focus changes, shortcuts, pause, permission loss, and snippet-index changes invalidate pending matches.

1. A bounded in-memory matcher observes the relevant keyboard events while enabled. Store only the short context needed for matching; never persist typing history.
2. On a match, snapshot the clipboard value and resolve the complete template before removing any typed characters.
3. Verify the target application and focus still match the captured context. Cancel on uncertainty, permission loss, secure input, or an excluded application.
4. Replace the keyword without activating Tapster. Use Unicode events for short single-line text, and pasteboard insertion for multiline/tab-containing text or replacements longer than 200 characters. Verify both paths against real apps before claiming compatibility.
5. Tag synthetic events to prevent loops. Keep event callbacks short, serialize replacements, and handle event-tap timeout/disable recovery without swallowing normal typing.
6. If pasteboard insertion is needed, capture supported original representations before writing. Restore only if the pasteboard still contains Tapster's own write; never overwrite a newer user copy. Paste consumption timing is app-dependent and must be validated, not assumed.

Request Accessibility access when the user enables expansion. Check the event monitoring/posting permissions required by the selected strategy on supported OS versions; do not blindly request additional access. Snippet management remains usable without expansion permission. Status distinguishes active, paused, permission required, and secure input unavailable.

Protected input and some custom editors cannot be promised to work. Secure Event Input must be respected. Composition input, dead keys, alternate layouts, rapid focus changes, and nonstandard editors are acceptance-test cases; pause matching when composition cannot be tracked reliably. Exclude Tapster's own editor except for an explicit test field.

Closing the main window leaves expansion running via the menu bar. Quit stops it. Launch at login is opt-in using `SMAppService.mainApp`.

## Existing implementation research

The workspace was empty when planning began. [Espanso](https://github.com/espanso/espanso) is an existing Rust text expansion engine, published under GPL-3.0, with [documented dynamic variables and injection strategies](https://espanso.org/docs/matches/basics/). Reusing it remains a candidate, but would introduce an external engine, process/configuration integration, and a licensing decision.

Selected approach: use Apple's existing UI, text editing, persistence, event, and pasteboard APIs, with a small Tapster-specific matching/resolution layer. No separate engine process, configuration format, or external package is required. Espanso internals have not been copied or ported.

## Implementation sequence

1. **Expansion feasibility.** Create a minimal native app with stable bundle identity. Exercise permission grant/revocation, immediate `gc` expansion with clipboard input, focus changes, secure input, generated-event filtering, and clipboard preservation. Test TextEdit, Notes, Safari text fields, Terminal with secure input off/on, and an Electron editor. Record failures and select the expansion backend before substantial UI work.
2. **Native library.** Build the three-column window and settings/menu bar scenes. Add persistence, collections, CRUD, search, favorites, commands, draft saving, and empty/error states. Establish the project-local build/run script and Codex Run configuration.
3. **Template editing.** Add the narrow `NSTextView` bridge, placeholder insertion/mappings, validation, and shared preview resolver. Verify native text editing and undo behavior.
4. **Integrate expansion.** Connect saved snippets to the engine, add permission onboarding, pause/resume, excluded apps, launch at login, and status reporting. Add import/export.
5. **Acceptance and packaging.** Run focused automated tests, physical typing checks, native UI review, and the required review-loop. Produce a signed/notarized build when release work is authorized and signing is available.

## Verification

- Matcher: boundaries, overlapping prefixes, adjustable debounce, stale callbacks, incomplete matches, backspace, modifier shortcuts, context reset, generated-event suppression, and rapid consecutive expansions.
- Resolver: multiple/repeated variables, escaped braces, malformed syntax, Unicode/multiline values, empty clipboard, and deterministic date/time output.
- Store: save/cancel behavior, relaunch persistence, import validation, migration, and deleted-collection handling.
- Integration: permission denial/revocation, sleep/wake, event tap recovery, app switching during expansion, clipboard changes during insertion, and menu-bar-only operation.
- UI: actual window resizing and column collapse, Light/Dark mode, keyboard navigation, VoiceOver labels, undo, native menus, and unsaved drafts. Compare the whole composition with option 1, not merely whether controls fit.
- Live typing tests must confirm output lands in the original app without executing a command or submitting a form. Automated tests alone do not establish cross-app acceptance.

At the UI milestone, ask whether Dave wants to verify the app himself or wants an agent-run preview. Any question needed to proceed stays pending until answered.

## Later scope

Prompt-on-expansion fields, rich text/images, snippet chaining, sync, alternate trigger modes, and automatic updates can follow after the core workflow is reliable. They are not part of the initial implementation plan.

## Platform references

- [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview) and [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra): native layout and menu bar scenes.
- [CGEvent](https://developer.apple.com/documentation/coregraphics/cgevent) and [Accessibility trust](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions): event APIs and permission checks.
- [Secure Event Input](https://developer.apple.com/library/archive/technotes/tn2150/_index.html): Apple's archived explanation of protected input and event interception; validate behavior on the target OS.
- [SwiftData ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer): persistent store and schema management.
- [SMAppService registration](https://developer.apple.com/documentation/servicemanagement/smappservice/register()): launch-at-login registration.
