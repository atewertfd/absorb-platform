# Export import verification — 2026-10-29

## Implemented flow

Settings → Advanced → **Import Libation exports** (and Manage → Upload → **Import Libation exports**) provides a one-book handoff through the Audiobookshelf uploader:

1. Choose compatible exported audio plus a cover (either by picking individual files or by choosing an exported book folder / Libation output directory), or optionally launch a user-selected Libation desktop executable first.
2. When a multi-book Libation output directory is scanned, choose which exported book folder to load into the form.
3. Review/edit title, author, series, library, and destination folder. Selecting files or scanning a folder does not upload them.
4. Explicitly select **Upload**.
5. After a successful upload, the UI checks the destination for up to about 6.5 seconds, reports whether Audiobookshelf has exposed it yet (or is still indexing), and triggers a library refresh.

Safety and boundary guarantees:
- The export picker and directory scanner exclude account/configuration files (`.json`, `.db`, etc.) and unsupported protected extensions (`.aax`, `.aaxc`, `.voucher`, etc.) by filename extension without reading file contents during selection.
- Absorb Plus does not sign in to Audible, read Libation credentials or account databases, or convert protected media; see [the separate feasibility record](AUDIBLE-INTEGRATION.md).
- Non-admin accounts and accounts without Audiobookshelf upload permission receive a clear permission banner and explicit HTTP 401/403 permission error message.

## Automated evidence

Analysis (`flutter analyze --no-fatal-infos`) completes without issues.

`test/admin_upload_screen_test.dart` checks:

- Export-file filtering, title prefilling, no upload before confirmation, and the selected request's library/folder/files.
- Existing-destination rejection without sending an upload or discarding selection.
- A thrown path check releases busy state and allows another attempt.
- Thrown upload errors retain reusable files or request reselection of potentially consumed stream-only files.
- Duplicate callback activation during a pending path check is rejected; editing is disabled.
- A 400×800 logical-pixel window at 180% text scale completes the flow without layout overflow.
- Non-admin accounts lacking upload permission (`canUpload: false`) display a permission banner and block upload with a clear permission message.
- Server HTTP 403 responses during path checking or upload surface the clear upload-permission message.
- Opening the upload screen before `LibraryProvider` is populated loads libraries from `ApiService`.
- Folder import and multi-book Libation output folder scanning list discovered books, populate title/author/files for the chosen book, require explicit upload confirmation, and invoke the post-upload refresh callback.
- The optional desktop Libation launcher prompts for a user-selected executable when unconfigured and launches it only on explicit user action.

`test/media_upload_api_test.dart` checks the multipart upload and Libation helper utilities:

- File paths, in-memory bytes, and streams all contribute to byte progress. Native file/byte lengths, rather than stale picker sizes, determine the total.
- HTTP 401, 403 and 500 are reported with status codes and `isPermissionDenied` flags without automatically replaying a possibly consumed upload.
- `checkUploadPathExists` flags HTTP 403 as permission denied.
- Unreadable inputs are rejected before a request is sent.
- `scanLibationExportDirectory` discovers single-file and multi-chapter exported books across author subfolders, strips trailing `[ASIN]` tags, and skips `.json` and `.aax` files.
- `launchLibationExecutable` rejects empty paths, non-existent files, and non-executable/config extensions.

These are fake-server/fixture tests. No real library, user credentials or user media are touched.

## Visual evidence

The optional screenshot test uses the production dark theme without mounting the account/authentication services. It loads Flutter's Roboto and icon fonts, with Roboto substituted for the monospace path label in this test only. Desktop (1100×900) and narrow (400×800) renders were inspected. These are Flutter-rendered widget fixtures, not screenshots of an authenticated live server session.

To reproduce (replace the font directory for your Flutter SDK):

```powershell
flutter test --no-pub --dart-define=IMPORT_SCREENSHOTS=true --dart-define=FLUTTER_TEST_FONTS=C:/path/to/flutter/bin/cache/artifacts/material_fonts test/admin_upload_screen_test.dart
```

Outputs: `build/verification/import-desktop-details.png`, `import-desktop-files.png`, and `import-narrow.png`. Normal test runs skip this opt-in image capture; functional layout tests still run.
