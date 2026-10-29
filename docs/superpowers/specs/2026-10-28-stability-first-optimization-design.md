# Stability-First Cross-Platform Optimization Design

## Intent

Reduce avoidable image-memory retention and background resource use across
Windows, Linux, Android, and web without changing playback semantics, server
behavior, or the visual design.

## Goals

- Decode blurred cover backgrounds at a small, explicit size rather than
  retaining a second full-resolution bitmap.
- Bound remaining high-traffic cover widgets using the existing display-sized
  decode policy where the layout provides reliable constraints.
- Evict non-live decoded images when the app is backgrounded, while leaving
  live images and all audio resources untouched.
- Preserve current playback, seeking, downloads, scrolling, and navigation.
- Verify the safe changes with focused tests, the complete test suite, static
  analysis, and a Windows release build.

## Non-goals for this pass

- Replacing just_audio, libmpv/media_kit, ExoPlayer, or another audio backend.
- Changing audio buffers, codecs, server MIME negotiation, or transcoding.
- Rewriting IndexedStack/tab ownership or removing keep-alive state without a
  screen-specific regression test.
- Moving large JSON parsing to isolates without measured UI-thread evidence.
- Aggressively disposing the primary player or changing background playback.

## Design decisions

1. Use the existing `coverDecodeWidth` limits for foreground covers and a
   shared 32-pixel policy for blur-only backgrounds.
2. Put image-cache trimming in the existing app-shell lifecycle path so the
   operation is deduplicated by the existing background guard.
3. Call `ImageCache.clear()` only. Flutter keeps live images available, and no
   `clearLiveImages()` call is added to desktop, Android, Linux, or web.
4. Keep audio initialization and position streams unchanged until a separate
   profile demonstrates a safe, testable improvement.

## Success criteria

- Focused image and lifecycle tests pass.
- Full Flutter tests and analysis pass.
- Windows release build passes.
- The patch has no production changes in audio, networking, downloads, or
  navigation.
- Any out-of-scope candidates are documented rather than guessed into the
  codebase.

## User revision

The user later requested that visual rendering remain exactly as before. The
blur-only decode-size changes from the initial implementation were therefore
reverted. The shared cache limits and background non-live-cache trim remain,
because they do not alter cover composition or image quality during normal
foreground use.
