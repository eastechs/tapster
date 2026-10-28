# Quick Access, app-specific collections, and Compositions

## Behavior

Quick Access uses one nonactivating native panel. Its local configurable shortcut
defaults to Command-Shift-Space. Return inserts; Command-Return copies; Escape
cancels. It snapshots the destination and clipboard at opening, resolves dates at
confirmation, and inserts through the shared serialized insertion service.
Unknown or changed destinations support copying only. Automatic matching pauses
while the panel is open without changing the saved expansion preference.

Collections default to All Apps. Selected Apps stores bundle IDs and syncs them.
An app-specific keyword takes precedence over a global keyword; equally scoped
conflicts suppress expansion only in overlapping apps. Local saves/imports reject
new conflicts; remote conflicts preserve records and enabled preferences.

The sidebar separates All Snippets from Compositions, with independent counts,
search labels, and restored selection. Favorites and collections can include
both types. Creating an item opens its primary section; opening a source from a
Composition reveals that source in a matching section.

Compositions reference snippets by ID plus literal blocks with stable IDs and
separators. Default separator is New Line. Nested Compositions are rejected.
Sources resolve independently against one clipboard and clock snapshot. Combined
output permits at most one cursor. Source changes are live; missing/invalid
sources block the entire result. Enabled preferences govern automatic triggers,
not use as source text. Effective app scope intersects the Composition's collection
and all source collections. Copying remains available when content is valid.

## Implementation

The immutable ExpansionLibrary supplies validation, resolution, app eligibility,
search, conflict reporting, and matching candidates. SnippetRecord is the shared
editor/index value; its optional blocks distinguish Compositions. CompositionRecord
encodes separate backup metadata/blocks and SavedComposition stores them in a
separate CloudKit entity. Engine callbacks receive saved value snapshots and never
access SwiftData. Native views retain the existing split-view composition.

Schema V3 preserves frozen V1/V2 models, migrates existing records, and creates a
pre-v3 SQLite backup. JSON V2 includes scopes and Compositions; V1 imports remain
supported. Recovery retains unreadable raw data. Collection/draft edits preserve
remote changes to untouched fields; the ordered blocks are one editable field.

KeyboardShortcuts 3.1.0 supplies the shortcut recorder/registration. Its MIT license
is bundled. Signing identity/profile overrides now use app-specific build settings
so they do not leak into SwiftPM resource bundles. Debug builds use the active
architecture; Release retains universal architecture settings.

## Acceptance checklist

- [x] In the signed 0.3.0 preview, insert the test Composition into Notes with Quick Access/Return and exclude it from TextEdit Current App results (Dave verified 2026-10-28).
- [ ] Inspect palette, recorder, collection picker and Composition blocks in Light/Dark and theme colors.
- [ ] Verify separate Snippets/Compositions lists, counts, creation routing, source navigation, and restored sidebar selection.
- [ ] Verify keyboard navigation, drag/reorder, VoiceOver labels, and native menu actions.
- [ ] Click control padding and edges, including the New menu and full Composition source rows.
- [ ] Confirm Dock policy stays unchanged and repeated palette use creates no tabs or extra library windows.
- [ ] Verify Return and selection replacement in TextEdit, Notes, Safari, Terminal, and an Electron editor.
- [ ] Verify clipboard/file paths, multiline output, caret position, changed targets, secure input, excluded apps and permission loss.
- [ ] Verify shortcut changes/clear/reset and relaunch; native conflict warning.
- [x] Initialize and inspect the additive V3 development CloudKit schema (Console diff reviewed from Dave's screenshot on 2026-10-28).
- [x] On two updated Macs, verify restrictions, Compositions, source edits/deletions, offline edits and draft conflicts (2026-10-28).
- [x] Verify recovery when a missing source arrives later (delete/restore across Macs); initial partial source/collection arrival is covered separately by automated tests.
- [x] Validate and promote the reviewed schema to production (Dave confirmed deployment on 2026-10-28).
- [x] Verify production-signed upload of Compositions and collection app restrictions (2026-10-28).
- [x] Verify their download on the second updated Mac (Dave confirmed both records and the TextEdit restriction on 2026-10-28).
- [x] Verify reverse edits from the second updated Mac (source, Composition block data, and collection restriction received on 2026-10-28).

No installed-app replacement, release publication, commit, or push is included in
implementation. Automated checks and builds do not establish native or CloudKit
acceptance.
