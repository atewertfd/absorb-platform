# Conservative Cross-Platform Memory Optimization Design

## Intent

Reduce retained decoded-image memory across Android, Windows, Linux, iOS, and
web without changing playback behavior or making the app more fragile. The
first pass targets image memory because covers are common, cross-platform, and
already rendered through Flutter's shared image cache.

## Goals

- Put a bounded upper limit on decoded-image cache entries and bytes.
- Keep existing cover quality and layout behavior within the app's current
  1024-pixel decode ceiling.
- Apply the policy consistently at startup on every supported Flutter target.
- Preserve current audio, network, download, navigation, and platform-control
  behavior.
- Add tests that pin the policy and the high-traffic stable cover widget.

## Non-goals

- Replacing libmpv, ExoPlayer, Media3, GStreamer, or another audio backend.
- Changing audio buffer sizes, playback speed behavior, network caching, or
  offline storage.
- Rewriting Flutter widgets or changing the UI design.
- Aggressively clearing live images during normal navigation.

## Anti-goals

- Do not reduce image quality below the existing cover decode ceiling.
- Do not trade lower RAM for increased CPU churn or visible cover flashing.
- Do not remove assets or plugins solely because they appear large on disk.

## Approaches considered

1. **Conservative shared image-cache policy (chosen).** Bound decoded-image
   count and bytes and cap the stable cover widget's decode width. This touches
   shared Flutter behavior and has a small, reversible surface area.
2. **Platform-specific audio backend replacement.** Could reduce a portion of
   desktop memory, but would affect streaming, seeking, high-speed playback,
   and compatibility. It is too risky for this first stable pass.
3. **Broad lifecycle and service refactor.** Could find additional savings, but
   it is difficult to prove and risks background playback, notifications,
   Android Auto, and navigation regressions. It should follow profiling and
   targeted regression tests rather than precede them.

## Design decisions

- Use a 64 MiB decoded-image byte ceiling and a 500-entry ceiling. The byte
  ceiling is the primary control; the entry ceiling prevents many tiny images
  from retaining unbounded metadata.
- Use the existing 1024-pixel maximum for the stable cover widget's decoded
  width. Callers that already provide a smaller decode size keep that value.
- Configure the cache after `WidgetsFlutterBinding.ensureInitialized()` and
  before `runApp()`.
- Leave live images and all audio resources untouched in this pass.

## Success criteria

- The full Flutter test suite remains green.
- New tests fail before the implementation and pass afterward.
- A release Windows build succeeds.
- No changes are made to the user's unrelated working-tree files.
- The patch is documented as a first conservative pass; measured RAM change
  must be validated on release builds before further tuning.
