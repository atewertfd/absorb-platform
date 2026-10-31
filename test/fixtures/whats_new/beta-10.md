## Beta 10

Pre-release for testing. The app shows **1.11.1+300 (Beta 10)** in Settings so you can confirm which build is running.

### Libation import (Settings → Advanced → Import Libation exports)
- Use Libation first to download the audiobook (Libation is a separate app you install and sign in to yourself), then import its exported files here.
- Choose an exported book folder, or scan your Libation output folder. Books are listed newest download first, with their date, so the one you just downloaded is at the top.
- Optional on desktop: set your Libation app to launch it from here, and remember your output folder.
- Scanning shows progress and blocks Upload until it finishes; a failed scan shows an error instead of hanging.
- Switching between scanned books no longer keeps the previous book's author; an author you typed is kept.
- Titles from a single file drop Libation's trailing `[ASIN]` tag.
- Accounts without Audiobookshelf upload permission see a clear message instead of a generic failure.
- Nothing is uploaded until you press Upload. Absorb Plus does not sign in to Audible or Libation, read their account files, or convert protected files.

### ReadMeABook
- ReadMeABook import lives in Settings → Advanced and is shown before setup; it was removed from the admin dashboard.

### Updates
- The beta update check now offers the highest published version rather than whichever release GitHub lists first.
- On Windows it waits until a release's installer is attached, so it never offers a release whose installer is still building.

### Performance (no visual changes)
- Lower memory: bounded decoded-image cache and cover decoding, smaller blur-only cover decodes, and non-visible images trimmed when the app is in the background.
- Lower CPU: animations on hidden screens are paused, and download-progress updates only rebuild the progress row.
- Original cover rendering restored (visual rollback).

### Downloads
- **Windows:** `Absorb-1.11.1-Setup.exe` installs or updates in place and keeps your settings and data. `Absorb-1.11.1-300-windows-portable.zip` runs from any folder.
- **Browser:** the web build is live at https://atewertfd.github.io/absorb-platform/ ; `absorb-1.11.1-300-web.zip` is the same build to self-host.
- **Linux:** `.tar.gz` and `.deb`. **Android:** APKs (signed with a CI key, not a Play Store key).

The Windows installer updates an existing Absorb Plus installation in place and preserves its user data.

Not yet verified against a live Audiobookshelf server or a real Libation library; automated tests use fixtures only.

---
Source commit: e6dbb6ec9152a531bd1d8d6603f7a61398a0fb48
SHA-256 checksums are included for the Android, Linux and web files.

