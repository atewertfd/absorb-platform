# Targeted Library Rendering Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce unnecessary library-card rebuilds and oversized cover bitmap decodes without changing the UI.

**Architecture:** Add a pure immutable render snapshot used with Provider's `context.select`, and a pure decode-width helper used by reusable cover widgets. Keep service state and scrolling behavior unchanged.

**Tech Stack:** Flutter, Dart, Provider, cached_network_image, Flutter widget tests.

**Spec:** `docs/superpowers/specs/2026-10-28-targeted-library-rendering-optimization-design.md`

## Global Constraints

- Preserve existing UI, scrolling, offline behavior, and user-owned changes.
- Decode between 64 and 1024 physical pixels on the largest displayed dimension.
- Verify with focused tests, the full Flutter test suite, analyzer, and Windows release build.

## Review Focus

- Same rendered values must not produce a changed selector snapshot — `library_item_snapshot_test.dart`.
- Changed progress/download state must produce a different snapshot — `library_item_snapshot_test.dart`.
- Tiny, large, and unbounded layouts must receive safe decode widths — `cover_decode_test.dart`.
- Existing cover and grid behavior must remain covered by the full test suite.
- Windows release compilation must still succeed.

### Task 1: Snapshot and decode contracts

**Files:**
- Create: `lib/widgets/library_item_snapshot.dart`
- Create: `lib/widgets/cover_decode.dart`
- Test: `test/library_item_snapshot_test.dart`
- Test: `test/cover_decode_test.dart`

- [ ] Write focused tests.
- [ ] Run them and confirm they fail because the new contracts are missing.
- [ ] Implement the minimal immutable snapshot and bounded decode helper.
- [ ] Run focused tests and confirm they pass.
- [ ] Commit the contracts.

### Task 2: Use snapshots in library cards

**Files:**
- Modify: `lib/widgets/book_card.dart`
- Modify: `lib/widgets/library_grid_tiles.dart`

- [ ] Replace broad `LibraryProvider` watches with per-item `context.select` snapshots.
- [ ] Preserve the existing download listener in grid tiles for correctness of download badges.
- [ ] Add display-sized decode hints to the reusable book-card cover, including the small blur layer.
- [ ] Run card/grid focused tests and the snapshot tests.
- [ ] Commit the wiring.

### Task 3: Verify and review

- [ ] Run `flutter test`.
- [ ] Run `flutter analyze`.
- [ ] Run `flutter build windows --release --no-pub --dart-define=GITHUB_BUILD=true`.
- [ ] Run `git diff --check` and confirm `lib/utils/server_url.dart` remains untouched.
- [ ] Record that runtime RSS reduction still needs before/after profiling.
