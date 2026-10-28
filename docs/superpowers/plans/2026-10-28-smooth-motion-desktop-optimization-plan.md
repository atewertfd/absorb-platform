# Smooth Motion and Desktop Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Absorb Plus feel consistently animated and responsive on desktop input without changing its visual design, playback behavior, or mobile/e-ink safeguards.

**Architecture:** Add a small pure motion-policy utility, a testable wheel-target accumulator, and a coalescing desktop-wheel driver. Wire the shared motion durations into the app shell and desktop-supported route/theme transitions, then make only evidence-backed repaint/listener optimizations in those shared paths.

**Tech Stack:** Flutter/Dart, Material 3, `flutter_test`, existing `AnimationController`, `ScrollPosition`, `PointerSignalEvent`, and current Provider architecture. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-28-smooth-motion-desktop-optimization-design.md`

## Global Constraints

- Preserve current colors, layout, controls, accessibility semantics, and playback/download/server behavior.
- Apply shared transitions on Windows, Linux, macOS, and web while preserving current Android/iOS behavior.
- Keep e-ink mode and `snappyTransitionsNotifier` immediate; honor reduced-motion signals before normal motion.
- Preserve nested scroll target discovery and existing Space/Left/Right playback shortcuts.
- Keep wheel scrolling local to `DesktopWheelScrollRegion`; do not replace global scroll physics.
- Do not add a third-party animation package.
- Do not touch unrelated uncommitted release/server-discovery changes.

## Review Focus

- A burst of wheel events must coalesce into one smooth target, not restart visible jumps on every event. Test in Task 2.
- Wheel targets must clamp at scroll extents and rebase when a position detaches. Test in Task 2.
- E-ink, explicit snappy mode, and reduced-motion must never leave a running animation ticker. Test in Task 1 and Task 3.
- Existing desktop keyboard playback shortcuts must remain unchanged while platform scroll actions continue to work. Test in Task 3.
- Large cover/player surfaces must not repaint the entire shell on unrelated nav or scroll updates. Test/inspect in Task 4.

---

### Task 1: Add the shared motion policy

**Files:**
- Create: `lib/utils/app_motion.dart`
- Create: `test/app_motion_test.dart`

**Interfaces:**
- Produces `enum AppMotionMode { normal, reduced, instant }`.
- Produces `AppMotion.resolveMode({required bool eInk, required bool snappy, required bool reduceMotion})`.
- Produces `AppMotion.duration(Duration normal, AppMotionMode mode)`.
- Produces named const durations/curves for micro, state, navigation, and modal motion.

- [ ] **Step 1: Write failing pure tests**

  Add tests proving instant mode wins over reduced mode, reduced mode returns zero duration, normal mode preserves the requested duration, and the named duration constants are ordered from micro to modal.

- [ ] **Step 2: Run the focused test and verify it fails**

  Run: `flutter test test/app_motion_test.dart`

  Expected: FAIL because `app_motion.dart` and the policy API do not exist.

- [ ] **Step 3: Implement the minimal policy**

  Add only the enum, pure resolver, duration helper, and const timing tokens. Keep the default curve `Curves.easeOutCubic` and use `Curves.easeInOutCubic` for navigation.

- [ ] **Step 4: Run the focused test and verify it passes**

  Run: `flutter test test/app_motion_test.dart`

  Expected: PASS with no analyzer errors.

- [ ] **Step 5: Commit**

  `git add lib/utils/app_motion.dart test/app_motion_test.dart && git commit -m "feat: add shared motion policy"`

### Task 2: Replace desktop wheel jumps with coalesced smooth scrolling

**Files:**
- Create: `lib/utils/wheel_scroll_accumulator.dart`
- Create: `test/wheel_scroll_accumulator_test.dart`
- Modify: `lib/widgets/desktop_wheel_scroll_region.dart`

**Interfaces:**
- Produces `WheelScrollAccumulator({required double initialTarget})`.
- Produces `double add({required double delta, required double min, required double max})`.
- Produces `void rebase(double pixels)` and `double get target`.

- [ ] **Step 1: Write failing accumulator tests**

  Cover accumulating multiple positive/negative deltas, clamping at both extents, and rebasing after an external/user scroll.

- [ ] **Step 2: Run the focused test and verify it fails**

  Run: `flutter test test/wheel_scroll_accumulator_test.dart`

  Expected: FAIL because the accumulator does not exist.

- [ ] **Step 3: Implement the accumulator**

  Store only the pending target and clamp every update to the supplied scroll extents. Do not add acceleration or platform-specific multipliers.

- [ ] **Step 4: Run the focused test and verify it passes**

  Run: `flutter test test/wheel_scroll_accumulator_test.dart`

  Expected: PASS.

- [ ] **Step 5: Add a coalescing driver to the wheel region**

  In `desktop_wheel_scroll_region.dart`, keep the existing discovered-scrollable selection and pointer-signal resolver. Replace `target.position.pointerScroll(target.delta)` with one driver per active `ScrollPosition` that uses `ScrollPosition.animateTo` with the shared state duration and `Curves.easeOutCubic`; new signals update the accumulator while the driver is in flight. Rebase or dispose drivers when a position detaches, a user drag takes over, or the widget disposes. Use `AppMotionMode` so e-ink/reduced-motion can bypass animation.

- [ ] **Step 6: Run the focused tests and static analysis**

  Run: `flutter test test/wheel_scroll_accumulator_test.dart` and `dart analyze lib/widgets/desktop_wheel_scroll_region.dart lib/utils/wheel_scroll_accumulator.dart`.

  Expected: PASS with no analyzer errors.

- [ ] **Step 7: Commit**

  `git add lib/widgets/desktop_wheel_scroll_region.dart lib/utils/wheel_scroll_accumulator.dart test/wheel_scroll_accumulator_test.dart && git commit -m "fix: smooth desktop wheel scrolling"`

### Task 3: Apply the shared policy to shell and route transitions

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/screens/app_shell.dart`
- Modify: `test/widget_test.dart` or create `test/transition_policy_test.dart` if the existing shell test is too broad.

**Interfaces:**
- Consumes `AppMotion` and `AppMotionMode` from Task 1.
- Produces desktop page transitions using the existing Material transition builders, with shared durations/curves where the Flutter API permits.

- [ ] **Step 1: Add a failing widget test for platform transition coverage**

  Test the transition-selection helper or policy boundary directly, asserting that Windows/Linux/macOS/web select the animated builder in normal mode and that e-ink/snappy mode selects the instant builder.

- [ ] **Step 2: Run the focused test and verify it fails**

  Run: `flutter test test/transition_policy_test.dart` (or the updated focused test path).

  Expected: FAIL because the shared selection helper does not yet exist or does not cover desktop.

- [ ] **Step 3: Implement transition wiring**

  Use `AppMotion` for `_fadeController` and `_navBarAnimController` durations. Extend the existing page-transition configuration to desktop/web without altering mobile behavior. Keep the instant transition path for e-ink/snappy mode and avoid adding an always-running animation.

- [ ] **Step 4: Run focused tests and format**

  Run: `flutter test test/transition_policy_test.dart` and `dart format lib/main.dart lib/screens/app_shell.dart test/transition_policy_test.dart`.

  Expected: PASS and no formatting changes left.

- [ ] **Step 5: Commit**

  `git add lib/main.dart lib/screens/app_shell.dart test/transition_policy_test.dart test/widget_test.dart && git commit -m "feat: standardize desktop transitions"`

### Task 4: Apply the evidence-backed performance cleanup

**Files:**
- Modify: `lib/widgets/desktop_wheel_scroll_region.dart`
- Modify: `lib/screens/app_shell.dart`
- Modify: only the specific high-cost widget files identified by the focused inspection, such as `lib/widgets/absorbing_card.dart` or `lib/widgets/expanded_card.dart`.

**Interfaces:**
- Consumes the shared motion policy and wheel driver.
- Produces no new public feature API; changes are limited to narrower rebuild/listen scopes and repaint boundaries where justified.

- [ ] **Step 1: Write a regression test or focused assertion for each identified hotspot**

  Pin the concrete behavior before changing it—for example, a scroll update must not rebuild unrelated shell navigation, and playback-position updates must continue to update the player controls.

- [ ] **Step 2: Run the focused tests and inspect the failure or baseline**

  Run the relevant test path and record the current result before the optimization.

- [ ] **Step 3: Implement the smallest optimization**

  Remove redundant notifier writes, narrow broad `setState`/listener scopes, or add a `RepaintBoundary` around a proven expensive cover/player region. Do not change data refresh cadence, cache policy, or audio service behavior.

- [ ] **Step 4: Run focused tests and compare behavior**

  Run the focused tests again and inspect the widget tree for preserved semantics and playback controls.

- [ ] **Step 5: Commit**

  `git add <only-reviewed-hotspot-files> && git commit -m "perf: reduce desktop UI rebuild work"`

### Task 5: Full verification and release notes

**Files:**
- Modify: `docs/superpowers/specs/2026-10-28-smooth-motion-desktop-optimization-design.md` only if implementation findings require a correction.
- Modify: `README.md` or the relevant changelog/release notes if this repository’s release process requires a user-facing entry.

- [ ] **Step 1: Format all changed Dart files**

  Run: `dart format <changed Dart files>`.

- [ ] **Step 2: Run static analysis**

  Run: `dart analyze`.

  Expected: exit 0 with no new errors.

- [ ] **Step 3: Run the full Flutter test suite**

  Run: `flutter test`.

  Expected: all tests pass. Existing unrelated failures must be recorded by name rather than hidden.

- [ ] **Step 4: Run a Windows release build when Flutter is available**

  Run: `flutter build windows --release --no-pub`.

  Expected: exit 0. If Flutter is unavailable in the environment, report that limitation explicitly and do not claim the build passed.

- [ ] **Step 5: Review the diff and repository status**

  Run: `git diff --check`, `git status --short`, and inspect the final diff for unrelated changes.

- [ ] **Step 6: Commit the verified integration**

  `git add <verified feature files> && git commit -m "feat: smooth desktop motion and optimize UI responsiveness"`
