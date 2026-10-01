# Export import verification — 2026-10-01

## Implemented flow

Manage → Upload → **Import Libation exports** provides a one-book file handoff through the existing Audiobookshelf uploader. Select compatible audio plus a cover, review/edit title, author, series and destination, then explicitly select Upload. Selecting files does not upload them. The export picker excludes configuration/metadata sidecars and unsupported protected extensions by filename extension; it does not inspect or certify file contents. The general upload picker retains its existing broader file support.

One primary audio file plus a cover now prefills the title from the audio filename. Multiple chapter files require the user to enter the book title. Folder scanning, automatic multi-book grouping, batch queues, true upload resuming and server-index confirmation are not implemented.

This does not implement direct Audible login/library import; see [the separate feasibility record](AUDIBLE-INTEGRATION.md).

## Automated evidence

At this checkpoint, analysis completed without issues and the full default suite passed 28 tests (the optional screenshot capture is skipped by default and also passed when explicitly enabled). The JavaScript web release build succeeded; its WebAssembly dry-run warnings do not establish Wasm support.

`test/admin_upload_screen_test.dart` checks:

- Export-file filtering, title prefilling, no upload before confirmation, and the selected request's library/folder/files.
- Existing-destination rejection without sending an upload or discarding selection.
- A thrown path check releases busy state and allows another attempt.
- Thrown upload errors retain reusable files or request reselection of potentially consumed stream-only files.
- Duplicate callback activation during a pending path check is rejected; editing is disabled.
- A 400×800 logical-pixel window at 180% text scale completes the flow without layout overflow.

`test/media_upload_api_test.dart` checks the actual multipart request with an injected HTTP client:

- File paths, in-memory bytes, and streams all contribute to byte progress. Native file/byte lengths, rather than stale picker sizes, determine the total.
- HTTP 401, 403 and 500 are reported without automatically replaying a possibly consumed upload.
- Unreadable inputs are rejected before a request is sent.

These are fake-server/fixture tests. No real library, user credentials or user media are touched. They do not prove server indexing, proxy limits, large-file behavior, or end-to-end upload against a real Audiobookshelf installation. Progress measures payload consumed by the HTTP transport, not server indexing or durable storage.

## Visual evidence

The optional screenshot test uses the production dark theme without mounting the account/authentication services. It loads Flutter's Roboto and icon fonts, with Roboto substituted for the monospace path label in this test only. Desktop (1100×900) and narrow (400×800) renders were inspected. These are Flutter-rendered widget fixtures, not screenshots of an authenticated live server session.

To reproduce (replace the font directory for your Flutter SDK):

```powershell
flutter test --no-pub --dart-define=IMPORT_SCREENSHOTS=true --dart-define=FLUTTER_TEST_FONTS=C:/path/to/flutter/bin/cache/artifacts/material_fonts test/admin_upload_screen_test.dart
```

Outputs: `build/verification/import-desktop-details.png`, `import-desktop-files.png`, and `import-narrow.png`. Normal test runs skip this opt-in image capture; functional layout tests still run.
