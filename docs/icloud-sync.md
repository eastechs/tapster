# Textend iCloud sync

Sync is opt-in. SwiftData mirrors saved snippets and collections into the user's
private `iCloud.chat.eastechs.tapster` database. Preferences, permissions and launch
settings remain local. The app remains unsandboxed for text expansion.

## Signing and environments

Keep bundle `chat.eastechs.tapster` and team `VK288Z42NG`. The App ID must have
CloudKit and Push Notifications enabled and be associated with the container.
Install these profiles into Xcode's provisioning profile directory:

- `Textend CloudKit Development`: Apple Development certificate, development APS,
  development CloudKit entitlement, and every test Mac registered in the profile.
- `Textend CloudKit Developer ID`: Developer ID Application certificate, production
  APS and CloudKit entitlement, valid for all devices.

`script/provisioning.py development` or `release` validates profile identity,
container, services, environment, expiration and the matching local signing key.
Builds fail if provisioning is missing. Profiles and private keys stay outside Git.
After downloading a renewed profile, install it with:

```sh
python3 script/provisioning.py development --install ~/Downloads/Textend_CloudKit_Development.provisionprofile
```

Use `release` with the Developer ID profile. The installer validates the profile,
installs it atomically, and moves superseded Textend profiles to
`TextendRetiredProfiles` beside their existing profile folder. Other apps' profiles
remain untouched. This prevents duplicate-profile build failures while retaining
recoverable old copies.
The local release script embeds and validates the production profile and signed
entitlements before notarization. Sparkle and Spaces publication are unchanged.

Debug builds use `Application Support/chat.eastechs.tapster/Development`. Release
builds retain `Application Support/chat.eastechs.tapster`. Development and
production CloudKit data are separate. A Release build launched with
`--sync-preview` uses `ProductionPreview` below the release support directory,
starts with expansion paused, and disables Sparkle. Use that mode for signed
production access checks without opening the installed app's library. It still
connects to the account's production CloudKit database when explicitly enabled.
Do not copy a development database into
the release directory or run two builds against the same store.

Use `./script/build_and_run.sh --preview` for a development library with expansion
initially paused. Quit that preview before rebuilding. It does not replace the
installed release. Fresh libraries are empty; File > Add Example Snippets is
explicit and available only when the library is empty.

## Migration, account binding and recovery

Schema V2 removes uniqueness constraints and gives CloudKit-compatible defaults.
Migration preserves logical IDs, timestamps and placeholder data. Before opening
an existing database, SQLite's online backup creates a consistent
`*.store.pre-v2.sqlite` file, including committed WAL contents. Backup failure
stops opening the library. Retain that backup until the migration is accepted.

`SyncConfiguration.json` binds a library to a hashed CloudKit account identity.
Enabling or disabling sync persists only after the restart confirmation and draft
Save/Discard/Cancel flow. Disabling retains the downloaded local library and does
not delete cloud records. A different account receives a separate store after
explicit enablement, without importing the previous account's library.

An observed account change suspends the current store and expansion index,
preserves the last observed library in a private `*.recovery.json` file, and
requires restart. That recovery is opened locally before sync can be enabled
again. A failed recovery write blocks the automatic restart action and asks for a
backup. Do not remove old account stores or recovery files automatically.
Ordinary connection failures keep local editing available while Apple's framework
handles retries. Account unavailability alone is not treated as an account change.

Public JSON backup format remains version 1. It is a user backup/interchange
format, not the synchronization transport. Recovery snapshots also retain raw
invalid placeholder payloads so an account change cannot silently discard them.

## Merge and expansion

CloudKit handles saved-record conflicts. Logical duplicate IDs are reconciled to
the smallest persisted row identifier, using the newest timestamp and then row
identifier to choose values. Duplicate nonempty keywords disable expansion for
all affected snippets while leaving their enabled preferences intact. Manual
copying remains available for valid templates. New local saves and imports still
reject duplicate keywords.

Remote imports, app activation and wake refresh saved records and the expansion
index. Clean editors reload; dirty editors preserve their draft. Saving applies
only fields changed from the original baseline. Remote deletion offers Save as
New or Discard. Missing collections never hide snippets. Invalid records remain
visible with an explanation and are excluded from expansion.

The Settings activity describes observed transfers. A successful transfer does
not prove that another Mac received it. No global "fully synced" promise is made.

## Development schema and acceptance

Quit the development preview, then run:

```sh
./script/build_and_run.sh --initialize-cloudkit-schema
```

This opens a provisioned Debug app and initializes the schema from V2 through
Apple's `NSPersistentCloudKitContainer.initializeCloudKitSchema` API using a
separate development initialization store. It is not compiled into Release.
Inspect the schema in Apple's CloudKit Console before promoting it to production.
Do not deploy a partially reviewed schema. Production deployment and a signed
production-access test are release gates, independent of development success.

Automated checks:

```sh
./script/check.sh
```

Two-Mac acceptance requires development provisioning for both Macs and the same
iCloud account. Use disposable test snippets in the development environment:

1. Enable on both Macs. Confirm initial upload/download without duplicate examples.
2. Edit each direction; verify the other Mac and expansion of the changed keyword.
3. Edit offline, reconnect and confirm transfer.
4. Edit the same snippet simultaneously, including dirty drafts with different fields.
5. Create a keyword conflict on separate offline Macs; reconnect and verify both
   snippets are retained and excluded from expansion until one keyword changes.
6. Delete a remotely edited snippet; verify Save as New and Discard.
7. Add, rename and delete collections; snippets must remain visible.
8. Disable, edit locally, restart and re-enable; verify retained records.
9. Verify sleep/wake, relaunch, keyboard navigation, both appearances and theme colors.
10. Separately verify production schema, Developer ID entitlement access and the
    existing update workflow before publishing a release.

See `docs/verification.md` for completed checks and outstanding acceptance gates.
