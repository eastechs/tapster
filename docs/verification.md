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

## Remaining acceptance

Dave reports that the app is mostly working after the permission and editor crash fixes. Complete cross-app acceptance is still unverified. Other target applications, alternate layouts, composition, sleep/wake, and Dark appearance have not received physical acceptance checks. Automated insertion tests capture events rather than posting them to other applications.

Tapster is left running with its original four saved snippets and Expansion active. No signed release or notarized distribution has been produced.

Run `./script/check.sh` to repeat formatting, tests, and the Xcode build. The Codex Run action launches through `./script/build_and_run.sh`.
