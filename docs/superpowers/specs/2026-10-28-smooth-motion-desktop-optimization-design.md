# Smooth Motion and Desktop Performance Design

## Intent

Make Absorb Plus feel consistent and responsive when used with a Windows mouse and keyboard, without replacing its current visual style. The most visible defect is desktop wheel scrolling: `DesktopWheelScrollRegion` sends each wheel tick directly to `ScrollPosition.pointerScroll`, which produces a snap instead of the eased motion users already get from sliders and animated controls.

The change will establish a small shared motion policy, use it for the app's existing route/navigation transitions, and make desktop wheel input coalesce into smooth scroll targets. A focused performance pass will reduce avoidable rebuild and paint work around the desktop interaction paths without changing server, playback, download, or data behavior.

## Goals

- Make mouse-wheel and trackpad scrolling ease toward the intended position instead of jumping one event at a time.
- Give navigation, route, sheet, selection, and visibility changes a consistent, restrained motion language.
- Preserve the current colors, layout, controls, touch behavior, keyboard shortcuts, and accessibility semantics.
- Respect reduced-motion requests and the existing e-ink/snappy-transition modes by bypassing or minimizing animation.
- Keep animations cheap: no perpetual animations added to content lists, no unnecessary opacity/blur effects, and no animation that blocks playback or input.
- Improve desktop responsiveness by coalescing high-frequency wheel events and avoiding redundant animation-controller/value-notifier writes.

## Non-goals and anti-goals

- Do not redesign the UI or move controls between panels.
- Do not add a new animation dependency.
- Do not change audio timing, seek semantics, download behavior, server synchronization, or storage.
- Do not force one scroll physics model onto touch, mobile, e-ink, or nested picker/carousel controls.
- Do not animate every widget indiscriminately; animated content must remain readable and responsive.

## Constraints

- Follow existing Flutter and Material 3 patterns in this repository.
- Keep the e-ink path animation-free and keep `snappyTransitionsNotifier` as an immediate-transition escape hatch.
- Keep desktop-wheel behavior local to `DesktopWheelScrollRegion`; global scroll physics are too risky because the app contains nested sheets, carousels, reorderable lists, and reader views.
- Do not introduce a third-party motion package.
- Existing uncommitted release/server-discovery changes are outside this feature and must remain untouched.

## Decisions settled during review

- The desktop input scope includes mouse wheels, precision touchpads, and the
  platform's existing keyboard scroll actions. App-specific playback shortcuts
  such as Space, Left, and Right keep their current meanings.
- Shared transitions apply to Windows, Linux, macOS, and web. Existing mobile
  transitions remain compatible with the current Android/iOS behavior.
- The motion priority is: e-ink and the explicit snappy-transition setting
  first, then the OS/app reduced-motion signal, then the normal motion policy.
- Nested scroll target discovery must remain unchanged. Sheets, carousels,
  reorderable lists, and reader views keep their current ownership of wheel
  input.
- Stable 60 FPS during Windows wheel scrolling is the baseline. Higher refresh
  rates should not be artificially capped, but no expensive effects will be
  introduced solely to chase a 120/144 Hz target.
- “Everything animated” means shared/high-traffic transitions follow one
  policy. Existing animation sites will be audited and migrated where they
  duplicate timing or create visible discontinuities; the implementation will
  not blindly wrap every widget in an implicit animation.

## Approaches considered

### A. Shared motion policy plus targeted desktop input smoothing — selected

Add a small `AppMotion`/motion-policy utility for durations and curves, update the route transition theme for supported desktop targets, and replace direct wheel jumps with a coalescing smooth-scroll driver. Apply the policy only to shared shell/navigation and the existing reusable surfaces that already animate. This fixes the reported problem with a small surface area and gives future UI work one place to follow.

### B. Global custom scroll physics

Replace the app-wide scroll behavior or physics so all scrollables animate automatically. This is less code, but it risks breaking drag gestures, nested modal scrolling, reader pagination, reorderable lists, and platform-native touch behavior. It also would not solve route and sheet transitions.

### C. Rewrite every screen independently

Add bespoke animations to every screen and control. This offers maximum local control but would duplicate timing/curve decisions, increase rebuild and ticker cost, and make the app less consistent over time. It is not appropriate for the stability and performance goals.

## Selected design

### Motion policy

Create `lib/utils/app_motion.dart` with named, const durations and curves for micro-interactions, content/state changes, navigation, and modal transitions. The utility will expose a reduced-motion-aware duration helper so shared widgets can opt into an immediate result without each widget duplicating the check. The existing e-ink and snappy-transition notifiers remain the authoritative app-specific overrides.

### Desktop wheel scrolling

Refactor `lib/widgets/desktop_wheel_scroll_region.dart` so each target scroll position has one coalescing driver. A wheel event extends a clamped target; the driver eases toward that target over a short duration. New events update the target instead of starting competing jumps. The driver stops and rebases when the scrollable detaches, reaches an extent, a user drag takes over, or the widget is disposed. The existing scrollable discovery and pointer-signal resolver remain in place.

### Shared transitions

Use the motion policy for the shell's tab fade and desktop-supported page transitions. Keep the current instant path for e-ink/snappy mode. Do not add animation to data fetching or audio playback state itself. Reuse existing `AnimatedSize`, `AnimatedSwitcher`, `AnimatedOpacity`, and `SizeTransition` sites where they already exist rather than wrapping the entire widget tree in a broad implicit animation.

### Performance pass

Measure and change only concrete hotspots found in the shared paths: redundant notifier writes during scroll/nav reveal, unnecessary rebuilds caused by broad listeners, and expensive repaint regions around large cover/player surfaces. Add `RepaintBoundary` or narrower listen scopes only where the existing widget tree proves they help. Avoid speculative caching or lifecycle changes.

### Verification

- Add unit/widget tests for motion-policy reduced-motion decisions and wheel-target accumulation/clamping.
- Add widget coverage that confirms the wheel region settles to the accumulated target rather than applying one jump per event.
- Run formatting, static analysis, the full Flutter test suite, and a Windows release build when the local Flutter toolchain is available.
- Record any environment limitation instead of claiming a build that was not run.
