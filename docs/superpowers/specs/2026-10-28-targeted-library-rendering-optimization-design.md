# Targeted Library Rendering Optimization

## Intent

Reduce avoidable Windows desktop CPU and image-memory work while preserving the current UI, scrolling behavior, cover treatment, and download badges.

## Goals

- Prevent `BookCard` and `GridBookTile` from rebuilding when a provider notification does not change the item's rendered state.
- Decode reusable card covers near their display size instead of full source resolution.
- Keep visual quality bounded by a conservative maximum decode size.
- Add pure tests for selector equality and decode sizing.

## Non-goals

- No global Flutter cache rewrite.
- No changes to native scrolling or pointer handling.
- No removal of existing motion or cover effects.
- No claim of a fixed percentage RAM reduction without runtime profiling.

## Approach

Use a small immutable per-item snapshot with value equality for `context.select`, plus a pure display-size decode helper used by reusable card images. Keep the existing provider and download service APIs intact so update, playback, and offline behavior do not change.

## Constraints

- Preserve the user's unrelated `lib/utils/server_url.dart` changes.
- Keep cover decoding at least 64 physical pixels and at most 1024 physical pixels on the largest displayed dimension.
- Existing tests and the Windows release build must continue to pass.
