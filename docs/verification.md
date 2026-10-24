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

## Spotlight duplicates and About attribution (2026-10-24)

- Spotlight indexed the Debug app, the Release test build, and the exported validation app. Unregistered the two test copies and moved their generated folders into `build/retired-builds.noindex/`, preserving the files. After indexing caught up, `mdfind` returned only the Debug app for Textend's bundle identifier.
- Future release archives and exports now stage under `build/releases.noindex/` to avoid adding duplicate app results. The development app path and saved library remain unchanged.
- Added `Built by Dave Sebek. Copyright Eastechs 2026` through the native About panel's `NSHumanReadableCopyright` metadata. Verified the built plist and visually inspected the full text in the running About panel. Expansion remains active and the four saved snippets are present.
- Focused review-loop passed its first iteration: reviewed the metadata and staging-path changes against existing conventions, validated the plist and whitespace, built the app, and passed all 14 release guard tests. No release was published.

## Accent color setting (2026-10-24)

- Added a native accent picker under Settings → General → Appearance with eight Apple system colors, persisted with AppStorage. Each independent SwiftUI hosting root observes the preference, including the toolbar content. Theme updates preserve view identity, pane geometry, and drafts.
- Template placeholder attributes refresh when the accent changes without replacing the text. Custom input focus borders and native sidebar icons use the same preference. macOS still controls native selection highlights, Settings toolbar icons, and system focus rings; the Settings footer explains this boundary.
- Inspected Blue, Purple, and Green in the running app, immediate control/icon/placeholder updates, a purple search focus border, template typing and Undo, and persistence of Purple across relaunch. Restored Blue and left the final Settings screen open. The original four snippets remain, expansion is active, and the delay remains 500 ms. Dark appearance was not visually checked.
- Review-loop was clean on its second pass after adding explicit native sidebar item tinting. Reviewed preference propagation through AppKit hosts, editor highlighting and undo behavior, accessibility labels, and existing native layout conventions. `script/check.sh` passed all 43 tests, formatting, shell syntax, whitespace, and the Debug build. No commit or publication was performed.

## In-app Help and appearance override (2026-10-24)

- Help → Textend Help opens a single native, searchable offline guide with eight topics. Search covers article text and examples; Command-F targets Help search when that window is active. Reviewed the content against the actual settings, resolver, and library commands.
- Moved the accent picker into a dedicated Settings → Appearance tab alongside System, Light, and Dark. The persisted override uses `NSApplication.appearance` and is restored before app launch finishes, covering SwiftUI and AppKit windows without changing macOS settings.
- Inspected Help, Settings, and the library in the running app. Verified Help menu opening, article filtering, Command-F, empty results, Dark rendering, explicit Light rendering, and Dark persistence after relaunch. Restored System appearance and Blue accent. Help remains open for review.
- Review-loop finished clean on pass two after aligning Help sidebar tinting with the library and removing a redundant Help shortcut. Checked the full diff, native view conventions, preference propagation, document accuracy, and search edge cases. `script/check.sh` passed 29 Swift tests, 14 release tests, formatting, shell syntax, whitespace, and the Debug build. The initial sandboxed run could not write the Swift cache; rerunning with approved cache access passed. No commit or release publication was performed.

## Theme-colored list selections (2026-10-24)

- Fixed blue list selections remaining under the Graphite accent. Library rows, collection filters, and Help topics now share theme-colored backgrounds with readable foregrounds. The native List still owns selection, keyboard navigation, and accessibility selection state.
- SwiftUI row backgrounds alone did not suppress the focused AppKit highlight. Added a narrow bridge that finds the containing `NSTableView` through public view types and disables its default selection paint. No delegate replacement, private API, global appearance mutation, or replacement selection model is involved.
- Inspected focused library and sidebar selections in Dark with Graphite, including Tab and arrow-key navigation. Inspected Help selection in Light, with readable selected icons and text. Restored Dave's Dark appearance and retained Graphite throughout. The four saved snippets remain unchanged.
- Review-loop passed on its third iteration after correcting the focused native highlight and selected icon contrast. Reviewed the complete diff, representable lifecycle, selection bindings, existing view conventions, and updated documentation. The two focused layout tests, strict Swift formatting, whitespace checks, and the Debug build passed. No commit was made.

## First notarized release and Spaces publication (2026-10-24)

- Prepared Textend 0.1.0, build 2, from `e222d9d54a67b3032cbcecbcd70674fcf48a8c37`. All 43 pre-release checks passed. The universal app is signed with Developer ID team `VK288Z42NG`; Apple accepted submission `533720ae-7bed-41d2-b472-b28ba7060da7` and its ticket was stapled.
- Extracted the final ZIP and verified both architectures, bundle metadata, nested signatures, stapled ticket, and Gatekeeper acceptance as Notarized Developer ID. Verified manifest hashes and Sparkle signatures for the ZIP and XML feed. Local release files are in `dist/0.1.0-2/`.
- First publication exposed an AWS CLI error when reading an absent Spaces object: `argument of type 'NoneType' is not a container or iterable`. The script now checks existence with HEAD before downloading an existing feed; permission/network/read failures still stop publication. Added regression checks for a missing feed and a failed download of an existing feed.
- Published `macos/Textend-0.1.0-2.zip` to `textend-releases`, verified its SHA-256 through `cdn.usetextend.com`, then published and verified the exact signed `macos/appcast.xml`. Upload credentials and public CDN delivery are now verified. No keys, manifests, or Apple logs were uploaded.
- The focused review-loop passed its first formal iteration: reviewed the publication diff and guard behavior, checked sibling test conventions, passed all 16 release tests, Python compilation, and whitespace checks. The signed app itself is unchanged. An actual upgrade between two released versions, including unsaved drafts and retained Accessibility permission, remains untested. Publication-tool changes and this note are uncommitted.

## Installed Sparkle update test (2026-10-24)

- Installed the signed, notarized 0.1.0 build 2 release at `/Applications/Textend.app`. Previously, no app was installed in either Applications folder. Dave granted Accessibility to this release identity; the app then showed Expansion active. Enabled automatic update checks through Sparkle's consent prompt, leaving automatic download/install off.
- Prepared signed, notarized 0.1.1 build 3 from `495bab63158d82971f32a3694b8314951ce3af14`, with no application-code or library-format changes. Apple accepted submission `b7646c66-45cd-43a2-86c6-09c34cc7b5ec`. Published the ZIP and signed feed through the existing local script, which verified CDN delivery before completing. The ZIP SHA-256 is `37a52ef3ba26012a7db83f90ac52136ca7e733fb4d98bf87a99cf0743b37643c`.
- The installed 0.1.0 app found 0.1.1 through Check for Updates, displayed its release notes, downloaded it, and reached Ready to Install. With a temporary unsaved name edit, Install and Relaunch presented Save/Discard/Cancel. Cancel retained the draft and left 0.1.0 installed. Retrying and choosing Discard Changes discarded only that temporary edit, installed the update, and relaunched Textend without a manual launch.
- Verified `/Applications/Textend.app` is now 0.1.1 build 3 and the new process runs from that path. Deep strict code-signature verification, Gatekeeper assessment as Notarized Developer ID, and stapler validation all passed. A second Check for Updates reported 0.1.1 is the newest version.
- All four saved snippets and both collections remain present, the temporary name edit is gone, and Save is disabled for the clean draft. Expansion remains active without another Accessibility grant. This establishes the actual download, installation, relaunch, draft cancellation, and permission-retention path. Cross-app physical typing and the Save branch of the update prompt were not retested. The installed release is left running; no development build was launched.

## iCloud sync implementation, October 24, 2026

Status: implemented locally, acceptance still in progress. No feature commit,
release publication, or replacement of `/Applications/Textend.app` was performed.

- Registered Textend's App ID with iCloud and Push Notifications under team
  `VK288Z42NG`, registered `iCloud.chat.eastechs.tapster`, and associated it.
- Generated both named CloudKit profiles. Installed and validated the development
  profile, including this Mac. The Developer ID profile was subsequently installed
  and validated; see the production verification below.
- The provisioned development app builds and launches. Its isolated library was
  initially empty. The real account check reports Signed in.
- Ran the development-only CloudKit schema initializer. The app subsequently
  opened normally, and observed CloudKit import/export events produced successful
  transfer timestamps. Created `CloudKit Development Check` / `;cloudcheck` with
  disposable test text in the development library. Export completion was observed
  in Core Data logs. This does not establish receipt on another Mac.
- Native Settings inspection covered Light and Dark appearances, a green accent,
  enable/disable confirmation, unsaved draft Save/Discard/Cancel presentation,
  cancelling restart, discarding a temporary draft, and disabling/re-enabling with
  restart. The saved test snippet survived both restarts. Appearance preferences
  were restored to System and Blue after inspection.
- One inspection attempt reopened the preview while the restart helper also
  launched it. Stopped only those development processes. The restart helper now
  uses normal application reopening, and the preview script refuses to rebuild
  an already running preview. Subsequent restarts each produced one process with
  `--sync-preview`, keeping expansion initially paused.
- Final `./script/check.sh` passes: 35 Swift tests, 16 release guard tests, 3
  provisioning tests, strict Swift formatting, shell syntax, whitespace checks,
  and the provisioned Xcode development build.
- New tests cover real V1 SQLite migration and reopening its V1 backup; clean and
  dirty editor refresh; field-level saves; remote deletion and Save as New;
  duplicate logical identities; invalid placeholder preservation; duplicate
  keyword suppression and correction; partial collection arrival; recovery
  snapshots; account isolation; restart cancellation/rollback; offline editing;
  and recovery write failure. Remote changes use separate local model contexts
  and injected account providers, so these are not two-device CloudKit tests.
- Review-loop pass 1 corrected existing conflicts blocking unrelated edits,
  validation against stale draft fields, transfer errors being cleared by account
  refresh, recovery failures permitting restart, and duplicate preview launching.
  Pass 2 found no further code defects in the reviewed local scope; its automated
  checks pass. Plan acceptance remains open at the gates below.

Acceptance gates at this initial checkpoint (subsequent results are recorded below):

- Complete the two-Mac matrix in `docs/icloud-sync.md`, including real offline/concurrent edits,
  deletions, conflicts, collection changes, relaunch, and remote expansion.
- Inspect native conflict/deletion/error states from those real sync scenarios.
  Actual account switching and sleep/wake transfer behavior are not yet verified.
- A signed/notarized public release still requires subsequent authorization.


### Production provisioning and CloudKit access

- Installed and validated `Textend CloudKit Developer ID` profile
  `62cdebfb-e76e-4c63-b9fe-1dbd9fd6d283`. It matches the existing Developer ID
  Application certificate and has production CloudKit and APNs entitlements.
- Reviewed CloudKit Console's schema diff against V2: `CD_SavedSnippet`,
  `CD_SavedCollection`, their fields and the framework-generated indexes. Deployed
  the schema and observed Apple's “Changes Deployed” confirmation. No user library
  was uploaded by schema deployment. Apple describes this separation in its
  [schema deployment guidance](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema).
- Archived and exported an internal 0.1.2 (4) verification build under
  `build/releases.noindex/cloudkit-verification/`. Deep/strict signature verification
  passes. The app contains arm64 and x86_64, the matching embedded profile,
  Production CloudKit, production APNs, and no debugger entitlement.
- Launched with `--sync-preview`. Release previews now use the separate
  `ProductionPreview` library and keep Sparkle disabled. The library began empty;
  `/Applications/Textend.app` and its ordinary library were not replaced or opened
  by this preview.
- The production-signed app reported Signed in. Enabled sync through Settings and
  its restart flow, created `CloudKit Production Check` / `;productioncheck`, and
  observed a completed production transfer at 2:47 PM on October 24. Both the
  rendered Settings status and Core Data export logs confirm completion.
- That test record remains in Dave's private production CloudKit database for the
  two-Mac check. The separate development fixture remains in development.
- This internal artifact is not notarized or published. No Sparkle feed or Spaces
  object was changed. Real second-Mac receipt and the remaining matrix still need
  verification before release acceptance.
- Follow-up review-loop for production preview isolation found no additional
  defects. `./script/check.sh` remains green (35 Swift tests, 19 Python guard tests,
  formatting, shell syntax, whitespace, and signed Debug build). The native
  Updates tab confirms Sparkle is disabled in the production verification preview.
  Closed the verification app after checks. Overall acceptance remains pending
  the second Mac and real multi-device scenarios listed above.


### Mac Studio preparation

- Completed Apple's annual device-list confirmation retaining all three existing
  devices. Registered Dave's Mac Studio and regenerated `Textend CloudKit
  Development` with both the MacBook Pro and Mac Studio selected.
- Installed refreshed development profile `5d7734ec-eb13-46b2-8349-7b9420ac73f3`
  from the user-supplied download and confirmed both registered Macs are included.
  The older profile is retained beside Xcode's profile directory.
- Incremental Xcode build replaced the embedded profile without refreshing its
  resource signature. Deep/strict verification caught it. A clean build corrected
  the signature; both architectures and the two-device embedded profile verify.
- Packaged the development app with a preview launcher and first-sync instructions
  at `build/releases.noindex/two-mac-development/Textend-iCloud-Test.zip`.
  The launcher requires other Textend instances to be quit and passes
  `--sync-preview`. It uses the isolated development library, initially pauses
  expansion, and leaves the installed release untouched.
- Dave confirmed on October 24 that initial sync succeeded on Mac Studio after
  opening the test package. This is user-reported second-Mac receipt, following
  the first Mac's observed development export. The package is
  development-signed and is not notarized or publicly distributed.
- The Studio edit initially did not arrive; Dave reported that the sync switch
  might not have been enabled and requested another check. Subsequently verified
  `Updated from mac studio` in this Mac's saved SQLite record, snippet list,
  clean editor, and preview without relaunching the development app. This confirms
  a real Studio-to-MacBook edit and live clean-editor refresh.
- Saved `Updated from MacBook Pro` through the native editor for the return-direction
  check. Dave confirmed it appeared on the Studio without restarting Textend.
  Real saved edits and clean-editor refresh are now verified in both directions,
  with Studio observations reported by Dave. Concurrent edits, conflicts, and
  the remaining two-Mac matrix are still pending.
- Dave saved an edit while the Studio was offline, reconnected, and later reported
  that it synced. This Mac initially retained the previous value with no recent
  import activity. After relaunching only the development preview, verified
  `Saved offline mac studio` in the saved SQLite record, list, editor, and preview.
  Offline preservation and subsequent cloud delivery are confirmed. Automatic
  receiver delivery after reconnect was not demonstrated in this run; relaunch
  was part of the observation, so this is not a clean pass for that behavior.
- Concurrent draft check: left `CloudKit Draft Check` as an unsaved name here
  while Dave saved `Studio's concurrent edit` as the template on Studio. CloudKit
  logs show a push-triggered import completing at 3:39:41 PM. Without restarting,
  the saved list updated, the local draft remained intact, and the editor displayed
  its changed-on-another-Mac notice. Saving retained both the locally edited name
  and the remotely edited template, verified in the native UI and SQLite record.
  This confirms live import and field-level draft merging for different fields;
  the same-field check is recorded below, and the earlier reconnect delay remains
  a separate observation.
- Remote deletion check: Dave deleted the test snippet on Studio while this Mac
  held an unsaved template. The deletion arrived without restarting. The sidebar
  showed zero saved snippets, while the editor retained the full draft and showed
  “Deleted on another Mac” with Save as New Snippet and Discard Draft actions.
  Choosing Save as New Snippet persisted exactly one record containing
  `Preserved draft after remote deletion`, verified in the UI and SQLite. The
  Discard action was visible but was not exercised in this live two-Mac check.
- Duplicate-keyword check: Dave created `Studio Conflict` offline while this Mac
  saved `MacBook Conflict`, both using `;syncconflict`. After reconnecting, Dave
  confirmed both records and conflict warnings on Studio. Both enabled switches
  remain on by design: the stored preference is preserved while conflicts are
  excluded from the expansion index. Re-ran the focused
  `testRemoteChangesRefreshDraftAndSuppressDuplicateKeywords` test successfully;
  it verifies exclusion, manual-copy eligibility, and restoration after renaming.
  Dave then confirmed real typing on Studio with global expansion resumed:
  `;cloudcheck` expands while `;syncconflict` stays literal. This verifies expansion
  of a remotely received snippet and actual conflict suppression, rather than a
  result caused by globally paused expansion. Dave then changed Studio Conflict's
  keyword to `;studioconflict` and confirmed the warnings cleared and both keywords
  expanded without changing their enabled switches. Live conflict resolution and
  automatic restoration of expansion are confirmed on Studio.
- Collection/favorite check: created `Sync Collection`, assigned MacBook Conflict,
  and favorited it here. Dave confirmed the collection, membership, and star on
  Studio and renamed the collection there. `Studio Collection` arrived here
  without relaunching, including the editor's collection picker. Deleting that
  test collection here retained all three snippets and MacBook Conflict's favorite
  state, with its collection set to None. Dave reported the collection initially
  remained on Studio, then disappeared after a delay while sync stayed enabled.
  Collection deletion delivery is confirmed; this test did not establish an
  exact latency or an immediate-delivery guarantee.
- Disable/re-enable check: Dave disabled sync on Studio, restarted, made a local
  edit, re-enabled sync, and restarted again. He confirmed all three snippets
  remained. This Mac received the edit without restarting: the `;studioconflict`
  snippet's name became `Saved with sync off`, while its template remained
  `Studio conflict test`. The requested edit targeted the template, but the actual
  name edit still verifies local editing and subsequent upload across the mode
  transition. The library retained three snippets with no duplicate examples.
- Same-field draft check: held an unsaved `MacBook same-field edit` template here
  while Dave saved `Studio same-field edit` on Studio. After a delivery delay,
  the incoming version appeared in the saved list and the changed-elsewhere banner
  appeared without replacing the local draft. Explicitly saving here kept the
  locally edited template. Verified one `;cloudcheck` record and three total
  snippets in SQLite. This tests overlapping drafts followed by an explicit save,
  not two disconnected devices racing to upload saved versions.
- Sleep/wake check: after Dave confirmed Studio was asleep with Textend
  running, saved `Received after Studio wakes` as the `;cloudcheck` template here.
  CloudKit logs show the modify-records/export completion at 4:28:16 PM, and the
  rendered Settings view shows a successful transfer at 4:28 PM. Dave then confirmed
  the template updated after waking Studio without restarting Textend, and
  `;cloudcheck` expanded to the new text in TextEdit. The accessibility tree retained an older time;
  the rendered view was checked to avoid treating that stale value as app state.
- Added `provisioning.py --install` to validate and install downloaded profiles,
  preserving superseded copies outside Xcode's search path. Focused review-loop
  passed after covering same-file reinstallation; 5 provisioning and 16 release
  guard tests pass. Tests confirm other apps' profiles remain untouched and wrong
  profile names are rejected before writing.

- Follow-up review-loop corrected the retired-profile archive location: it is now
  beside the provisioning directory so Xcode does not try to parse it. Pass 2 found
  no further defects in this installer/package scope. Five provisioning tests,
  16 release guard tests, launcher syntax, and whitespace checks pass. The extracted
  ZIP app also passes deep/strict signature verification. Overall sync acceptance
  still requires the two-Mac scenarios above.

### Final iCloud verification checkpoint

- Two-Mac observations cover initial delivery, live edits both ways, offline edit
  preservation and eventual delivery, clean/dirty editor refresh, field-level
  saves, remote deletion recovery, duplicate-keyword suppression and resolution,
  collection changes, favorites, disable/re-enable with local edits, restart,
  sleep/wake, and expansion using remotely changed text. Studio observations were
  reported by Dave; this Mac's results were inspected through native UI and,
  where relevant, read-only queries of the isolated test store.
- Delivery sometimes took several minutes. In the first offline-reconnect check,
  this Mac received the edit after its test preview was relaunched. That run
  does not establish automatic receiver delivery without relaunch. Subsequent
  live imports, conflict delivery after reconnect, and sleep/wake succeeded, but
  do not retroactively remove that limitation.
- Actual system iCloud account switching was not performed. Account isolation,
  recovery, and failure behavior are covered by injected-provider tests. Same-field
  testing covered overlapping drafts with a later explicit save, not simultaneous
  disconnected uploads. Discard after remote deletion was not exercised natively.
- Final review-loop completed a clean pass over the cumulative implementation,
  persistence/account boundaries, UI integration, signing/release changes, test
  coverage, and these evidence limits. `./script/check.sh` passes 37 Swift tests
  (35 core and 2 layout) plus 21 Python tests (16 release and 5 provisioning),
  strict Swift formatting, shell syntax, whitespace checks, and the provisioned
  development build. Both the final Debug app and the previously verified
  production artifact pass deep/strict signature verification.
- Closed only the local development preview after testing. Three disposable
  snippets remain in the private development library. The production verification
  fixture remains separate. No source commit, public release, Spaces/feed change,
  or replacement of the installed 0.1.1 app was performed for this implementation.
