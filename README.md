# Tapster

A native macOS snippet manager and text expander built with SwiftUI, AppKit, and SwiftData. Requires macOS 14 or later and Xcode to build.

## Run

Open `Tapster.xcodeproj`, select the Tapster scheme, and run, or use:

```sh
./script/build_and_run.sh
```

The Codex Run action uses the same script. It supports `--build-only`, `--verify`, `--debug`, `--logs`, and `--telemetry`.

Local builds use an existing Apple Development identity when available, otherwise ad-hoc signing. Set `TAPSTER_SIGNING_IDENTITY` to select an identity explicitly. The application is built at `build/Build/Products/Debug/Tapster.app`. Local development signing does not produce a notarized release.

## Snippets

Create a snippet with a name, template, and optional keyword. Insert Clipboard or Date & Time placeholders from the editor menu, or type a placeholder such as `{commit_message}` and select its source below the editor. Use `{{` and `}}` for literal braces.

Save before trying a keyword. Templates insert literal text; Tapster never executes commands or sends Return to submit them. Copy Expanded Text resolves a draft using the current clipboard, while the preview uses the editable sample clipboard value.

Enable expansion in Settings and allow Accessibility when macOS asks. Accessibility covers both keyboard monitoring and insertion for Tapster's active event tap; a separate Input Monitoring grant is not needed. The menu bar can pause or resume expansion, and closing the library window keeps Tapster running. Launch at login is optional.

If an older development build was authorized before changing its signing identity, macOS may still show Tapster enabled while rejecting the current app. Remove the old Tapster entry from Accessibility, add the current `build/Build/Products/Debug/Tapster.app`, and enable it again. The build script uses the available Apple Development identity to preserve identity across rebuilds.

For overlapping keywords such as `gc` and `gco`, Tapster waits 250 ms after an ambiguous exact match. Tune this under Settings → General → Expansion, from 100 to 1,000 ms. Unambiguous matches expand immediately. Continuing into an incomplete or unrelated keyword cancels the pending shorter match and retains typed text.

Protected input is excluded. Composition input methods and editors that do not expose enough accessible caret information are not supported for automatic expansion. The Settings test field uses the same expansion path while the snippet editor stays excluded.

Use File → Export Backup to save a versioned JSON backup. Import adds a validated backup atomically and rejects conflicting identifiers or exact duplicate keywords. Deleting a collection retains its snippets.

## Tests

```sh
swift test
```

Run `./script/check.sh` for formatting checks, tests, and an Xcode build in one command.

Tests cover matching and debounce, template resolution, persistence/imports, unsaved drafts, focus cancellation, and clipboard preservation. Insertion tests capture generated events without posting them to the computer. Cross-app acceptance still requires real typing in target applications.

The selected [design](docs/design/tapster-native-macos.png) and [implementation plan](docs/implementation-plan.md) are included in `docs/`.
