# Conservative Memory Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce cross-platform decoded-image memory conservatively without changing playback or navigation behavior.

**Architecture:** Add a small shared memory-policy utility that configures Flutter's global `ImageCache` at startup. Extend the existing stable network-cover widget with a bounded decoded width while preserving caller-provided sizes.

**Tech Stack:** Dart, Flutter `ImageCache`, `cached_network_image`, Flutter unit/widget tests.

**Spec:** `docs/superpowers/specs/2026-10-28-memory-optimization-design.md`

## Global Constraints

- Use a 64 MiB decoded-image byte ceiling and a 500-entry ceiling.
- Use the existing 1024-pixel maximum for the stable cover widget's decoded width.
- Do not change audio, networking, downloads, navigation, or platform controls.
- Do not touch unrelated user working-tree files.

## Review Focus

- Existing callers that provide a smaller cover decode size must keep that smaller value; test the default and override behavior in the stable cover widget.
- Startup must configure the cache before `runApp()` without requiring a platform channel; test the policy in isolation.
- The cache policy must not clear live images or alter audio resources; review the startup integration for scope.
- A very large source image must be bounded before decode; test the stable cover default.
- The full suite and release Windows build must remain green after the shared startup change.

---

### Task 1: Add the shared image-cache memory policy

**Files:**
- Create: `lib/utils/memory_policy.dart`
- Modify: `lib/main.dart` near `WidgetsFlutterBinding.ensureInitialized()`
- Test: `test/memory_policy_test.dart`

**Interfaces:**
- Produces `configureImageCache(ImageCache cache)` for startup use.
- Produces `kAbsorbImageCacheMaximumBytes` and `kAbsorbImageCacheMaximumEntries` constants for tests and documentation.

- [ ] **Step 1: Write the failing tests**

  Add tests that assert the constants are 64 MiB and 500, and that
  `configureImageCache` applies both limits to a fresh `ImageCache`.

- [ ] **Step 2: Run the focused test and verify it fails**

  Run `flutter test test/memory_policy_test.dart`.
  Expected: FAIL because `lib/utils/memory_policy.dart` does not exist.

- [ ] **Step 3: Implement the minimal policy**

  Define the constants and set `cache.maximumSizeBytes` and
  `cache.maximumSize` without clearing live images or adding platform-channel
  dependencies.

- [ ] **Step 4: Integrate startup configuration**

  Import the utility and call `configureImageCache(PaintingBinding.instance.imageCache)`
  immediately after `WidgetsFlutterBinding.ensureInitialized()` and before
  `runApp()`.

- [ ] **Step 5: Run the focused test and verify it passes**

  Run `flutter test test/memory_policy_test.dart`.
  Expected: PASS.

- [ ] **Step 6: Commit**

  Commit as `perf: bound decoded image cache memory`.

### Task 2: Bound the stable high-traffic cover widget

**Files:**
- Modify: `lib/widgets/stable_cached_network_image.dart`
- Test: `test/stable_cached_network_image_test.dart`

**Interfaces:**
- Keeps the existing `StableCachedNetworkImage` constructor behavior.
- Adds optional `memCacheWidth` and `memCacheHeight` overrides.
- Defaults `memCacheWidth` to the existing `maxCoverDecodeWidth` when omitted.

- [ ] **Step 1: Write the failing tests**

  Assert that a default `StableCachedNetworkImage` exposes a 1024-pixel
  `memCacheWidth`, and that a caller-provided smaller width is preserved.

- [ ] **Step 2: Run the focused test and verify it fails**

  Run `flutter test test/stable_cached_network_image_test.dart`.
  Expected: FAIL because the widget currently does not expose a bounded default.

- [ ] **Step 3: Implement the minimal widget change**

  Add the optional parameters and pass them to `CachedNetworkImage`, using the
  existing `maxCoverDecodeWidth` only when no caller value was supplied.

- [ ] **Step 4: Run the focused test and verify it passes**

  Run `flutter test test/stable_cached_network_image_test.dart`.
  Expected: PASS.

- [ ] **Step 5: Commit**

  Commit as `perf: bound stable cover image decoding`.

### Task 3: Whole-project verification

**Files:**
- No production files planned.

- [ ] **Step 1: Run formatting and analysis**

  Run `flutter format --output=none lib test` and
  `flutter analyze --no-fatal-infos`.

- [ ] **Step 2: Run the complete test suite**

  Run `flutter test`.
  Expected: all tests pass.

- [ ] **Step 3: Build the Windows release**

  Run `flutter build windows --release --dart-define=GITHUB_BUILD=true`.
  Expected: exit code 0 and a valid Windows bundle.

- [ ] **Step 4: Review the diff and commit verification notes**

  Confirm only the planned files changed and record the verification results
  in the implementation summary.
