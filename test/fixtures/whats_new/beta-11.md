## Beta 11

The biggest Absorb Plus update so far: pick how the app looks, smoother and lighter on Windows, a long list of crash and reliability fixes, and everything new from upstream Absorb.

### New: choose your look
- **Three looks:** Absorb Plus (today's look), Classic (the look of the first Windows version) and Frosted (soft frosted-glass panels with your cover colors glowing through).
- **Glass strength** for Frosted: Light, Medium or Strong.
- Asked once on first launch, and any time in **Settings > Appearance > UI theme**.
- **Real previews:** each choice shows the actual app shrunk down, with your own covers, shaped like your screen.
- **Try it:** see a look across the whole app before deciding, then Keep or Go back. Nothing is saved until you keep it.
- Pick an accent color in the same place.

### Smoother and lighter
- Smooth mouse-wheel scrolling on Windows and Linux.
- Upstream's original animation timings are back.
- The Absorbing screen no longer redraws non-stop while idle (it was redrawing up to 64 times a second).
- The chapter-name marquee only scrolls while playing.
- Fewer needless library rebuilds and progress-bar repaints.

### Fixes
- Pausing one book no longer cancels the next book's sleep timer or closes its session.
- Multi-disc books (CD1/01.mp3, CD2/01.mp3) no longer overwrite their own tracks when downloading.
- Offline listening time is kept until the server accepts it, instead of being dropped when the server is unreachable.
- An "end of chapter" sleep timer turns off when you switch books.
- Seeking back to the start in a book's last seconds no longer marks it finished.
- A downloaded book's listening session can't end up on another account after switching.
- Stopping a podcast episode saves its position under the right episode.
- Frosted: search bars and the Server Admin tile are glass too.
- 11 places where the app could crash after leaving a screen mid-load.
- Leaked timers and listeners after signing out.
- Desktop keyboard shortcuts no longer eat what you type.
- Server health check never sticks on "Checking", and doesn't over-report failures.
- Updater: cancel works, portable copies are handled, and it says when it couldn't reach GitHub.
- Libation import: one book's details no longer leak into the next upload.
- Failures in sync, downloads and sign-in now show up in the log (when logging is on), so problems are easier to track down. Tokens and passwords are never logged.
- The upstream author's "Support the Dev" card is hidden.

### From upstream Absorb
- BookOrbit: stats with Year in Review, notifications, achievements, admin tools, Book Dock, book requests, magic-link sign-in, faster narrated-book downloads.
- Reader: Slide, Curl and Ripple page turns, an editable tap grid, paragraph spacing, a Translate button, scroll mode, and settings grouped into sections.
- EPUB3 narration with read-along, and streaming narrated EPUBs without downloading first.
- Playback: the sleep-timer rewind sticks, paused books don't jump back, finished books don't restart in the car, and big downloads don't knock Absorb offline.
- Choose what the media controls show on each line.
- Every genre and tag on the book page, a left-aligned text option, an Authentication admin page, and many more fixes.
