# Stability-First Cross-Platform Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce avoidable image and background memory costs while preserving playback and UI stability.

**Architecture:** Extend the existing cover decode policy with an explicit blur-only size and apply it at duplicate-cover call sites. Add one lifecycle-safe image-cache trim hook to the existing `AppShell` background path. Leave audio and server behavior unchanged until measured evidence justifies a separate plan.

**Tech Stack:** Dart, Flutter `ImageCache`, `cached_network_image`, Flutter tests, Windows release build.

**Spec:** `docs/superpowers/specs/2026-10-28-stability-first-optimization-design.md`

**Revision:** The user requested preservation of the original visual
rendering. Task 1's blur decode edits were reverted after verification; the
cache-policy task remains active.

## Global Constraints

- Stability and playback correctness take priority over measured RAM reduction.
- Do not change audio engines, audio buffers, position semantics, networking, downloads, navigation, or server behavior.
- Preserve caller-provided foreground image sizes; only blur-only layers use the 32-pixel policy.
- Background trimming must not call `clearLiveImages()` on non-iOS platforms.
- Do not touch unrelated user working-tree files.

## Review Focus

- Blur layers must not become blank or alter the foreground cover layout.
- Backgrounding must not stop playback or discard live image objects needed on return.
- Existing smaller foreground decode widths must remain unchanged.
- Local-file and network-cover paths must receive equivalent treatment.
- Release builds must still compile all supported desktop plugin registrations.

---

### Task 1: Make blur-only cover decoding explicit

**Files:**
- Modify: `lib/widgets/cover_decode.dart`
- Modify: `lib/widgets/book_card.dart`, `lib/screens/home_screen.dart`, `lib/widgets/home_section.dart`, `lib/widgets/absorbing_card.dart`, `lib/widgets/expanded_card.dart`, `lib/widgets/book_detail_sheet.dart`
- Test: `test/cover_decode_test.dart`

**Interfaces:**
- Produces `blurCoverDecodeWidth`, a shared 32-pixel decode width for blur-only layers.
- Existing `coverDecodeWidth` behavior remains unchanged.

- [ ] **Step 1: Write the failing test**

  Add an assertion that `blurCoverDecodeWidth` is 32.

- [ ] **Step 2: Run the focused test and verify it fails**

  Run `flutter test test/cover_decode_test.dart` and confirm the missing
  constant causes the expected failure.

- [ ] **Step 3: Implement the minimal policy and update duplicate layers**

  Define the constant and pass it as `cacheWidth` for local blur images and
  `memCacheWidth` for network blur images in the listed widgets. Keep the
  foreground image's existing decode size or behavior unchanged.

- [ ] **Step 4: Run the focused test and verify it passes**

  Run `flutter test test/cover_decode_test.dart`.

- [ ] **Step 5: Commit**

  Commit as `perf: shrink blur-only cover decodes`.

### Task 2: Trim non-live image cache entries on background

**Files:**
- Modify: `lib/utils/memory_policy.dart`
- Modify: `lib/screens/app_shell.dart`
- Test: `test/memory_policy_test.dart`

**Interfaces:**
- Produces `trimDecodedImageCacheForBackground(ImageCache cache)`.

- [ ] **Step 1: Write the failing test**

  Add a recording `ImageCache` test double and assert that the helper calls
  `clear()` exactly once without calling `clearLiveImages()`.

- [ ] **Step 2: Run the focused test and verify it fails**

  Run `flutter test test/memory_policy_test.dart` and confirm the missing
  helper causes the expected failure.

- [ ] **Step 3: Implement and integrate the helper**

  Add the helper with no platform channel or audio dependency. Invoke it once
  from `_handleAppBackgrounded()` after the existing guard flips true.

- [ ] **Step 4: Run the focused test and verify it passes**

  Run `flutter test test/memory_policy_test.dart`.

- [ ] **Step 5: Commit**

  Commit as `perf: trim non-live images on background`.

### Task 3: Whole-project verification and scope audit

**Files:**
- No additional production files planned.
- Update the implementation ledger with verification and deferred-risk notes.

- [ ] **Step 1: Run focused tests**

  Run the two focused test files and read their complete output.

- [ ] **Step 2: Run the complete suite and analysis**

  Run `flutter test` and `flutter analyze --no-fatal-infos`.

- [ ] **Step 3: Build the Windows release**

  Run `flutter build windows --release --no-pub
  --dart-define=GITHUB_BUILD=true`.

- [ ] **Step 4: Audit deferred candidates**

  Confirm no changes were made to audio initialization, position-stream
  mapping, MIME negotiation, JSON parsing, tab ownership, or auxiliary-player
  lifecycle unless a later testable task is opened.

- [ ] **Step 5: Commit verification notes**

  Record exact command results and any deferred items in the ledger.
