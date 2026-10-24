# Local verification

Date: October 23, 2026.

- Xcode macOS build passes with no compiler warnings.
- All 27 Swift tests pass, covering debounce, resolution, persistence, atomic imports, draft binding lifetime, focus cancellation, generated-event tagging, and clipboard preservation.
- Swift formatting lint, shell syntax checks, project validation, and git whitespace checks pass.
- The local Apple Development signature verifies. This is a development build, not a notarized release.
- The running native three-column window, Git Commit preview, and Settings were inspected. The delay control and native expansion test field render correctly.
- Review-loop is clean on its third review pass. Earlier passes corrected draft discard behavior, caret validation, Shift handling, the Settings label/focus behavior, and dedicated application storage. Earlier development data is retained through migration.
- Permission flow correction: removed the separate Input Monitoring request. [Apple DTS confirms](https://developer.apple.com/forums/thread/828052) that Accessibility provides both event listening and posting. Tapster uses an active event tap and still checks Accessibility and posting access before starting it.
- The current development signature verifies. Tapster-specific macOS permission logs identified a stale Accessibility approval for the original ad-hoc build. Dave re-added Tapster, and the running app now reports Expansion active, including after the latest rebuild.
- The rebuilt permission screen and its Open Accessibility button were inspected. The button opens the correct privacy pane, labeled Device Control and Data Access on this Mac. No permission switch was changed by the agent.
- Editor crash correction: the supplied report and local reports trapped in `BindingOperations.ForceUnwrapping.get(base:)`. Command-clicking the selected snippet reproduced it. Replaced the optional draft binding with a binding scoped to the snippet identity that remains readable during editor teardown and rejects writes after selection changes. Three regression tests cover clearing/deleting a draft, switching snippets, live edits, and discarding into an empty collection.
- The rebuilt app survived the same deselection, selecting another snippet, focusing both name and template fields, switching collections, and creating/editing/discarding a temporary unsaved draft while expansion was active. No new crash report appeared during these checks. All 27 tests, formatting, build, and the first focused crash-fix review-loop pass are clean.
- Live debounce check: with the saved delay at 500 ms, physical typing produced three longer-keyword matches 147, 269, and 161 ms after the shorter match; each cancelled the shorter expansion and expanded the longer keyword. Pausing on the shorter keyword expanded it after approximately 503 ms. The earlier report of immediate expansion was not reproduced after relaunch; no behavioral fix or root cause is claimed. The temporary timing diagnostics were removed after verification at Dave's request.

## Native UI polish

- Followed Apple's [button](https://developer.apple.com/design/human-interface-guidelines/buttons), [toolbar](https://developer.apple.com/design/human-interface-guidelines/toolbars), and [layout](https://developer.apple.com/design/human-interface-guidelines/layout) guidance using native SwiftUI controls, system text styles, and semantic colors.
- Increased Save's label padding, moved New Snippet to the toolbar, aligned editor labels and pickers, reduced excess template height, and standardized section spacing and sheet fields. Keyword badges remain compact, and favorite indicators no longer indent the row text.
- Set the native list minimum row height to prevent newly inserted draft rows from clipping. Drafts and saved snippets share one row renderer. Draft lookup is evaluated once per view update.
- Inspected the running library at normal and minimum window sizes, scrolling, date mappings, the placeholder sheet, new draft rows, and enabled/disabled Save states. Discarded all temporary drafts. Inspected all three Settings tabs; the delay field and stepper are now separately exposed in the accessibility tree. The saved delay remains 500 ms.
- UI automation timed out once while switching windows. A process sample showed the app idle in its normal event loop, with no new crash report. Automation resumed after relaunch. This does not establish the cause of the timeout.
- The Xcode build, all 27 regression tests, formatting, and whitespace checks pass. The final review-loop covered draft identity, row rendering, responsive controls, accessibility labels, and consistency with sibling views. No expansion engine or persistence behavior changed.
- Light appearance was inspected. Dark appearance and a full VoiceOver session remain unverified in this pass.
- Dave reviewed the polish pass and reports a modest improvement with visible issues still remaining. He authorized committing this state; visual acceptance is not complete.

## Editor and preview layout

- The list header shows the active filter or collection and the visible snippet count, including search results and unsaved new snippets. Singular and plural counts are handled separately.
- Favorite moved beside the snippet title. Expansion is a native switch below Collection. Preview now occupies a separate, resizable right panel. Text inputs and the template share an 8-point rounded border; text fields have additional internal padding and a visible focus outline.
- New Collection is visible at the bottom of the sidebar and opens the existing creation sheet. Confirmed that blank names disable Save, entering a name enables it, and Cancel leaves the library unchanged. The File menu shortcut remains available.
- Inspected wide and compact windows in Light appearance, collection/filter selection, search counts, Command-F focus, clipboard/date/multiline previews, and favorite/expansion draft changes. Reversed temporary toggle changes and cancelled the collection test; all four original snippets remain intact.
- Xcode build, all 27 regression tests, formatting, and whitespace checks pass. Review-loop completed on its second pass after correcting the singular count. Reviewed draft binding lifetime, shared input styling, panel sizing, and existing collection actions. Dark appearance and full VoiceOver use were not checked in this pass.

## Sidebar collapse and layout stability

- Replaced geometry-driven SwiftUI toolbar sizing with an `NSSplitViewController` and native tracking separators. SwiftUI continues to render the library and editor content. Native holding priorities keep list and preview widths stable while the editor absorbs sidebar collapse and window resizing.
- Split containers now survive snippet changes and empty selections. The editor stays left-aligned; keyword help reserves two lines, and placeholder help stays below its menu so those controls do not jump between horizontal and vertical arrangements.
- Inspected normal and compact windows, repeated sidebar collapse/expand cycles, switching and clearing selections, temporary drafts, Settings, and the New Collection sheet. Six repeated toggles at each window size returned consistent pane widths and kept New/Save visible without toolbar overflow. The preview and header stayed aligned with their panes.
- Review corrected Save toolbar validation for clean and invalid drafts, and an accessibility value that retained the previous snippet's preview. Verified disabled Save for clean/invalid drafts, enabled Save after a valid edit, and updated preview accessibility values after selection changes. Temporary edits were reversed or discarded.
- The final focused review-loop is clean on its second pass. The Xcode build, all 27 regression tests, Swift formatting, shell syntax, and whitespace checks pass. Reviewed native controller lifetimes, toolbar validation, draft bindings, stable view identity, and sibling-view conventions. No expansion engine or storage behavior changed.
- These checks inspect layout and interaction results, not measured animation frame rates. Automated divider drags did not change widths, so physical divider dragging remains unverified. Dark appearance and a full VoiceOver session remain unverified. The app is left running at its previous window size with all four saved snippets intact and the delay still at 500 ms.

## Divider drag containment correction

- Dave's physical drag check exposed an inset content area that the earlier toggle checks did not cover. The split controller was directly exposed to SwiftUI sizing without an independently pinned container.
- Added a plain AppKit parent with required constraints on all four child edges. The representable accepts the window's finite proposed size, and the outer SwiftUI frame fills available width and height. Native pane constraints now operate within that allocated area.
- Added two layout regression tests: lower-priority internal width pressure cannot inset the child at several outer widths, and actual `NSSplitView.setPosition` changes plus collapse/reveal preserve the split view's outer bounds. These run in a separate local test module with no external dependency.
- Xcode build, all 29 tests, Swift formatting, and whitespace checks pass. The focused review-loop passed its first complete pass, including controller containment, constraint priorities, sizing proposals, lifecycle forwarding, and existing draft behavior.
- Inspected the rebuilt library, four collapse/reveal transitions, selection changes, toolbar alignment, and preview values. Automated mouse dragging did not move a divider. Dave subsequently tested the physical drag, confirmed that the fix resolved the inset-content issue, and authorized committing the UI changes. All four saved snippets are unchanged.

## Remaining acceptance

Dave reports that the app is mostly working after the permission and editor crash fixes. Complete cross-app acceptance is still unverified. Other target applications, alternate layouts, composition, sleep/wake, and Dark appearance have not received physical acceptance checks. Automated insertion tests capture events rather than posting them to other applications.

Tapster is left running with its original four saved snippets and Expansion active. No signed release or notarized distribution has been produced.

Run `./script/check.sh` to repeat formatting, tests, and the Xcode build. The Codex Run action launches through `./script/build_and_run.sh`.

## Textend rename and X2 icon (2026-10-23)

- Created the X2 Continuous mark as two vector ribbon layers, assembled in Icon Composer, and saved the editable `Tapster/Resources/Textend.icon` document. Exported the 1024-pixel PNG with Icon Composer's renderer; `script/export_icon.sh` reproduces it. Default, Dark, and TintedDark renders were visually inspected.
- Renamed the built product, app/window/menu labels, Settings copy, and backup filename to Textend. Retained the existing bundle identifier, Swift module, persistence schema, store location, and preference keys.
- `script/check.sh` passed: formatting, shell syntax, whitespace, 29 tests (27 core and 2 layout), and the development-signed Xcode build. Verified the bundle's Textend metadata, compiled `Assets.car` and compatibility `Textend.icns`, and signature with `codesign --verify --strict`.
- Inspected the running Textend app: all four existing snippets and both collections were present, expansion was active, the delay remained 500 ms, and launch at login remained off. Cross-app typing and older macOS runtime compatibility were not re-tested for this branding change.
- Review-loop iteration 2 was clean after correcting Package.swift line wrapping. Reviewed the rename, stable identity, build/run paths, export script, and icon source consistency. No commit or release was produced.

## Sparkle and local release tooling (2026-10-23)

- Integrated pinned Sparkle 2.10.0, native update commands and Settings, signed feeds, and verification before extraction. Debug builds do not start Sparkle. The public feed is configured as `https://cdn.usetextend.com/macos/appcast.xml`; the private update-signing key remains in the local Keychain.
- `script/check.sh` passed: 29 Swift tests, 14 offline publication guard tests, Swift formatting, shell syntax, whitespace, and the Debug build. Guard tests cover publication order, tampering, existing versions, permission failures, partial-upload retries, monotonic build numbers, and stale CDN feeds.
- Built and exported a universal Developer ID archive locally. Verified bundle metadata, both CPU architectures, the deep strict code signature, and matching release-team signatures with timestamps for Textend and every Sparkle helper. Generated a real test appcast and verified both the feed and archive Ed25519 signatures using Sparkle's tools. These artifacts are local validation builds, not notarized releases.
- Inspected Release Settings: both automatic-update options, the enabled manual-check command, and readable native layout. Sparkle's native automatic-check consent dialog appeared; it was left unanswered by quitting the test build. Inspected Debug Settings and confirmed the controls are disabled with the development-build explanation. Restored the Debug app with expansion active and all four saved snippets intact.
- Review-loop completed a clean first formal pass covering the full diff and new files, tests, formatting, updater lifecycle, unsaved-draft delegate, signing, upload ordering, failure handling, credential boundaries, and sibling conventions. Earlier integration checks corrected custom Info.plist values that Xcode did not emit through generated-key build settings.
- Notarization, Spaces upload, CDN delivery, and an actual update between two released versions remain unverified. No files were published, and no commit was made. Hosting and notarization credentials still require local configuration as described in `docs/releases.md`.

## Release hosting configuration (2026-10-24)

- Configured the ignored local release settings and tracked example for `textend-releases` in `atl1`, the `macos` prefix, and the `textend-notary` Keychain profile. The public feed remains `https://cdn.usetextend.com/macos/appcast.xml`.
- Authenticated the notarization profile with a read-only history request. HTTPS requests to the appcast path on both the Spaces CDN and custom domain returned HTTP 403. This confirms TLS connectivity, not public object access or successful update delivery.
- The local AWS CLI reports that `textend-spaces` is not configured. Upload credentials remain the next setup step. No notarization submission, upload, or publication was performed.
- Focused review-loop passed its first iteration: reviewed configuration and documentation, validated the local configuration and Git ignore rule, and reran all 14 release guard tests plus whitespace checks. Application code is unchanged from the previous verified build.
- After Dave saved the Spaces credentials, authenticated bucket access and listing of `macos/` succeeded. The prefix was empty, and the origin appcast was absent. Both public appcast URLs still returned HTTP 403. Read access is verified; upload permissions and actual update delivery remain untested. No objects were uploaded.
