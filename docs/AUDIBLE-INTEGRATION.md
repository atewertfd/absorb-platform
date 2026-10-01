# Direct Audible integration: requested, not implemented

Research checkpoint: 2026-10-01. This is a feasibility record, not an announcement of working Audible support.

## Required experience

Inside Absorb Plus, choose Connect Audible, authenticate with the provider, browse the account's library, select books, and import supported media into Audiobookshelf without installing a separate Libation application. Other software integrations are deferred. The existing file-export importer does **not** satisfy this requirement.

## Evidence and unresolved constraints

- [AudibleApi](https://github.com/rmcrackan/AudibleApi) is a C# library explicitly intended for integration into other software. Its README describes the Audible API as undocumented. That is an available technical starting point, not evidence of an official third-party integration contract or guaranteed stability.
- Its [current license file](https://github.com/rmcrackan/AudibleApi/blob/master/LICENSE) is AGPL-3.0. [Libation](https://github.com/rmcrackan/Libation) is GPL-3.0. Before bundling code, pin an audited version, review the actual dependency licenses and distribution obligations, and preserve notices and corresponding source. No AudibleApi or Libation code has been bundled at this checkpoint.
- Libation's own README describes downloading **and DRM removal**. Reproducing that entire pipeline would conflict with this project's current no-DRM-bypass requirement. Login or library browsing alone would not make protected media usable by Audiobookshelf. A permitted, compatible-media route must be established before promising direct book import.
- Amazon's [Login with Amazon authorization documentation](https://developer.amazon.com/docs/login-with-amazon/authorization-grants.html) describes access to customer profiles. This does not establish access to Audible purchases or audiobook downloads. Do not build a profile-login button and advertise it as Audible library integration.
- Desktop reuse of a C# component would need a packaged helper/runtime or a reviewed native bridge. Static GitHub Pages cannot execute that desktop helper. Web support must be investigated separately; do not add an unrequested credential-handling cloud service or disable browser protections.

## Proposed implementation gates

1. Establish a supported authentication and content-access route that meets the no-bypass constraint; review the exact licensed components before adoption.
2. Prototype provider login with credentials entered only on the provider's own page. Validate callback destinations and state, handle cancellation/expiry, redact all auth material from diagnostics, and require no browser-password or Libation-account-file access.
3. Keep session tokens in memory under the current no-credential-storage constraint. Persistent sign-in would require an explicit design decision about secure token storage; do not silently write tokens to preferences or JSON files.
4. Implement a read-only library browser with paging, region selection, retry, and clear disconnected/expired-session states. Use the existing Absorb UI components and accessibility conventions.
5. Enable import only for a verified supported media route. Show unavailable titles honestly; do not disguise export-file selection as account import or implement protected-content conversion under the current constraint.
6. Require an explicit review of book selection and Audiobookshelf destination, duplicate protection, and per-book outcome tracking before a server write. Verify uncertain results before retrying to prevent duplicates.
7. Test the real login/library/import flow with the user entering their credentials. A mock library or successful compilation does not establish that Audible works.

No login prompt, background downloader, account discovery, or credential collection has been added. The full requested feature remains open while these gates are unresolved.
