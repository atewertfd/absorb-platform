import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/fork_platform.dart';

/// Absorb Plus desktop mouse and keyboard extras for upstream's touch-first
/// widgets. Everything here is a no-op off the native desktop builds
/// ([ForkPlatform.isDesktop]), so Android and touch stay exactly as upstream.
///
/// - [desktopSecondaryTap]: right-click runs whatever long-press runs.
/// - [DesktopGestureDetector] / [DesktopInkWell]: drop-in replacements that
///   do that for you, for call sites whose long-press is a long expression.
/// - [desktopMouseDragBehavior]: lets a mouse drag a horizontal shelf.
/// - [DesktopPressTarget]: hand cursor, keyboard focus, tooltip and
///   right-click for upstream's `Pressable` card buttons.

/// [onLongPress] on desktop (for `onSecondaryTap`), null elsewhere.
VoidCallback? desktopSecondaryTap(VoidCallback? onLongPress) =>
    ForkPlatform.isDesktop ? onLongPress : null;

/// A scroll behavior that also lets the mouse drag, for horizontal shelves
/// and carousels (a mouse wheel only scrolls vertically). Null off desktop,
/// which keeps the scrollable's own default. [scrollbars] mirrors the
/// default of the scrollable it goes on (PageView hides them).
ScrollBehavior? desktopMouseDragBehavior(
  BuildContext context, {
  bool scrollbars = true,
}) {
  if (!ForkPlatform.isDesktop) return null;
  final base = ScrollConfiguration.of(context);
  return base.copyWith(
    scrollbars: scrollbars,
    dragDevices: {...base.dragDevices, PointerDeviceKind.mouse},
  );
}

/// Wraps a horizontal shelf so a mouse can drag it ([desktopMouseDragBehavior]),
/// for scrollables without a `scrollBehavior` parameter (ListView).
class DesktopMouseDrag extends StatelessWidget {
  const DesktopMouseDrag({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final behavior = desktopMouseDragBehavior(context);
    if (behavior == null) return child;
    return ScrollConfiguration(behavior: behavior, child: child);
  }
}

/// A [GestureDetector] whose [onLongPress] also runs on right-click on
/// desktop. Takes the parameters the upstream call sites use.
class DesktopGestureDetector extends GestureDetector {
  DesktopGestureDetector({
    super.key,
    super.child,
    super.behavior,
    super.onTap,
    super.onTapDown,
    super.onTapUp,
    super.onTapCancel,
    super.onLongPress,
  }) : super(onSecondaryTap: desktopSecondaryTap(onLongPress));
}

/// An [InkWell] whose [onLongPress] also runs on right-click on desktop.
class DesktopInkWell extends InkWell {
  DesktopInkWell({
    super.key,
    super.child,
    super.onTap,
    super.borderRadius,
    super.customBorder,
    super.onLongPress,
  }) : super(onSecondaryTap: desktopSecondaryTap(onLongPress));
}

class _OpenMenuIntent extends Intent {
  const _OpenMenuIntent();
}

/// Desktop affordances for a press-to-act widget: hand cursor, keyboard
/// focus (Tab to it, Enter or Space presses it, the Menu key or Shift+F10
/// runs [onLongPress]), a focus ring in keyboard mode, a hover [tooltip],
/// and right-click for [onLongPress]. Clicking does not take focus, so Space
/// keeps playing and pausing. Off desktop it returns [child] untouched.
class DesktopPressTarget extends StatefulWidget {
  const DesktopPressTarget({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.tooltip,
    this.borderRadius = 12,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? tooltip;
  final double borderRadius;

  @override
  State<DesktopPressTarget> createState() => _DesktopPressTargetState();
}

class _DesktopPressTargetState extends State<DesktopPressTarget> {
  bool _focusRing = false;

  static const _shortcuts = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.contextMenu): _OpenMenuIntent(),
    SingleActivator(LogicalKeyboardKey.f10, shift: true): _OpenMenuIntent(),
  };

  @override
  Widget build(BuildContext context) {
    if (!ForkPlatform.isDesktop) return widget.child;
    final enabled = widget.onTap != null || widget.onLongPress != null;
    Widget result = FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      shortcuts: _shortcuts,
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
        _OpenMenuIntent: CallbackAction<_OpenMenuIntent>(
          onInvoke: (_) {
            widget.onLongPress?.call();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (show) {
        if (show != _focusRing) setState(() => _focusRing = show);
      },
      // Same tree with the ring on or off, so the child never remounts.
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: _focusRing
            ? BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(widget.borderRadius),
              )
            : const BoxDecoration(),
        child: widget.child,
      ),
    );
    final tooltip = widget.tooltip;
    if (tooltip != null && tooltip.isNotEmpty) {
      // Manual: shows on mouse hover only, so a touchscreen long-press keeps
      // going to the button.
      result = Tooltip(
        message: tooltip,
        triggerMode: TooltipTriggerMode.manual,
        child: result,
      );
    }
    return result;
  }
}
