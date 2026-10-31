import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../services/desktop_shortcuts.dart';
import '../utils/fork_platform.dart';
import 'expanded_card.dart';

/// Intent for one of the [DesktopShortcutAction]s (playback, search...).
class DesktopShortcutIntent extends Intent {
  const DesktopShortcutIntent(this.action);
  final DesktopShortcutAction action;
}

/// Intent for one of the [DesktopNavigationAction]s (Esc, back, F5...).
class DesktopNavigationIntent extends Intent {
  const DesktopNavigationIntent(this.action);
  final DesktopNavigationAction action;
}

/// What the app shell does for the shortcuts that need it. The shell
/// registers these in [DesktopShortcutScope.handlers] while it is mounted.
class DesktopShortcutHandlers {
  const DesktopShortcutHandlers({
    required this.canRun,
    required this.run,
    required this.canSwitchCard,
    required this.switchCard,
  });

  /// Whether [run] would do something for this action right now.
  final bool Function(DesktopShortcutAction action) canRun;
  final void Function(DesktopShortcutAction action) run;

  /// Whether the Absorbing cards are on screen and can be switched.
  final bool Function() canSwitchCard;

  /// Moves the Absorbing carousel by one card ([delta] is -1 or 1).
  final void Function(int delta) switchCard;
}

/// The app's desktop keyboard and mouse shortcuts, installed above the
/// navigator (in `MaterialApp.builder`) so they also work while the
/// full-screen player, a reader or another page is open:
/// - the [desktopShortcutDefinitions] (Space, arrows, speed, Ctrl+F...),
///   run by the shell through [handlers];
/// - Esc closes the full-screen player;
/// - Alt+Left and the mouse back button close the top page or sheet;
/// - F5 and Ctrl+R refresh the visible pull-to-refresh list;
/// - Ctrl+Left/Right and Page Up/Down switch Absorbing cards.
/// The navigation ones exist only on the native desktop builds.
class DesktopShortcutScope extends StatelessWidget {
  const DesktopShortcutScope({super.key, required this.child});

  final Widget child;

  /// Set by the app shell while it is mounted; null before sign-in.
  static DesktopShortcutHandlers? handlers;

  @override
  Widget build(BuildContext context) {
    final navigation = desktopNavigationShortcuts;
    Widget result = Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        for (final shortcut in desktopShortcutDefinitions)
          shortcut.activator: DesktopShortcutIntent(shortcut.action),
        for (final shortcut in navigation)
          shortcut.activator: DesktopNavigationIntent(shortcut.action),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DesktopShortcutIntent: _AppShortcutAction(),
          if (navigation.isNotEmpty)
            DesktopNavigationIntent: _NavigationAction(context),
        },
        child: child,
      ),
    );
    if (ForkPlatform.isDesktop) {
      result = Listener(
        onPointerDown: (event) {
          if (event.kind == PointerDeviceKind.mouse &&
              event.buttons & kBackMouseButton != 0) {
            final nav = _backNavigator(context);
            if (nav != null) nav.maybePop();
          }
        },
        child: result,
      );
    }
    return result;
  }
}

class _AppShortcutAction extends DesktopShortcutCallbackAction {
  _AppShortcutAction()
      : super(
          actionOf: (intent) =>
              intent is DesktopShortcutIntent ? intent.action : null,
          onInvoke: (intent) {
            if (intent is DesktopShortcutIntent) {
              DesktopShortcutScope.handlers?.run(intent.action);
            }
            return null;
          },
        );

  @override
  bool isEnabled(Intent intent) {
    final handlers = DesktopShortcutScope.handlers;
    if (handlers == null || intent is! DesktopShortcutIntent) return false;
    return super.isEnabled(intent) && handlers.canRun(intent.action);
  }
}

class _NavigationAction extends Action<DesktopNavigationIntent> {
  _NavigationAction(this.scopeContext);

  final BuildContext scopeContext;

  // Found by isEnabled, used by invoke for the same key press.
  RefreshIndicatorState? _refresh;

  @override
  bool isEnabled(DesktopNavigationIntent intent) {
    final shortcut = desktopNavigationShortcuts
        .where((s) => s.action == intent.action)
        .toList();
    if (shortcut.isEmpty) return false;
    // Any binding's rule is fine: the key that fired is one of them, and the
    // rules for one action differ only for Page Up/Down (plain key).
    final allowed = intent.action == DesktopNavigationAction.previousCard ||
            intent.action == DesktopNavigationAction.nextCard
        ? _cardKeyAllowed()
        : shortcut.first.allowedByFocus;
    if (!allowed) return false;
    switch (intent.action) {
      case DesktopNavigationAction.closePlayer:
        final nav = _rootNavigator(scopeContext);
        return nav != null && topRouteOf(nav) is ExpandedCardRoute;
      case DesktopNavigationAction.back:
        return _backNavigator(scopeContext) != null;
      case DesktopNavigationAction.refresh:
        final root = FocusManager.instance.primaryFocus?.nearestScope?.context;
        _refresh = root == null ? null : findVisibleRefreshIndicator(root);
        return _refresh != null;
      case DesktopNavigationAction.previousCard:
      case DesktopNavigationAction.nextCard:
        return DesktopShortcutScope.handlers?.canSwitchCard() ?? false;
    }
  }

  @override
  Object? invoke(DesktopNavigationIntent intent) {
    switch (intent.action) {
      case DesktopNavigationAction.closePlayer:
        _rootNavigator(scopeContext)?.maybePop();
      case DesktopNavigationAction.back:
        _backNavigator(scopeContext)?.maybePop();
      case DesktopNavigationAction.refresh:
        final refresh = _refresh;
        _refresh = null;
        if (refresh != null && refresh.mounted) refresh.show();
      case DesktopNavigationAction.previousCard:
        DesktopShortcutScope.handlers?.switchCard(-1);
      case DesktopNavigationAction.nextCard:
        DesktopShortcutScope.handlers?.switchCard(1);
    }
    return null;
  }
}

/// Ctrl+arrows only need "not typing"; Page Up/Down are plain keys. The
/// intent doesn't say which key fired, so check the keyboard.
bool _cardKeyAllowed() {
  if (isTypingInTextField()) return false;
  if (HardwareKeyboard.instance.isControlPressed) return true;
  return nothingMoreSpecificHasFocus();
}

/// The top route of [nav] (popUntil stops at once, popping nothing).
Route<dynamic>? topRouteOf(NavigatorState nav) {
  Route<dynamic>? top;
  nav.popUntil((route) {
    top = route;
    return true;
  });
  return top;
}

NavigatorState? _rootNavigator(BuildContext scopeContext) {
  final focusContext = FocusManager.instance.primaryFocus?.context;
  final nav = focusContext == null
      ? null
      : Navigator.maybeOf(focusContext, rootNavigator: true);
  return nav ?? _firstNavigatorBelow(scopeContext);
}

/// The navigator to go back in: the innermost one around keyboard focus
/// that has something to close, else the root one. Null when only the
/// first page is open, so back never reaches the shell's "press back to
/// exit" handling.
NavigatorState? _backNavigator(BuildContext scopeContext) {
  final focusContext = FocusManager.instance.primaryFocus?.context;
  final inner =
      focusContext == null ? null : Navigator.maybeOf(focusContext);
  if (inner != null && inner.canPop()) return inner;
  final root = _rootNavigator(scopeContext);
  if (root != null && root.canPop()) return root;
  return null;
}

/// When focus is outside every navigator: the navigator under the scope.
NavigatorState? _firstNavigatorBelow(BuildContext context) {
  NavigatorState? found;
  void visit(Element element) {
    if (found != null) return;
    if (element is StatefulElement && element.state is NavigatorState) {
      found = element.state as NavigatorState;
      return;
    }
    element.visitChildElements(visit);
  }

  context.visitChildElements(visit);
  return found;
}

/// The first [RefreshIndicator] under [root] that is actually on screen:
/// painted (not a hidden tab of an IndexedStack, an offstage page or a
/// kept-alive page scrolled away) and inside the window. F5 calls its
/// `show()`, which runs the same refresh as pulling it down.
RefreshIndicatorState? findVisibleRefreshIndicator(BuildContext root) {
  RefreshIndicatorState? found;
  void visit(Element element) {
    if (found != null) return;
    if (element is StatefulElement &&
        element.state is RefreshIndicatorState &&
        _isOnScreen(element.renderObject)) {
      found = element.state as RefreshIndicatorState;
      return;
    }
    element.visitChildElements(visit);
  }

  if (root is Element) visit(root);
  return found;
}

bool _isOnScreen(RenderObject? object) {
  if (object is! RenderBox || !object.attached || !object.hasSize) {
    return false;
  }
  if (object.size.isEmpty) return false;
  RenderObject child = object;
  RenderObject? parent = object.parent;
  while (parent != null) {
    if (!parent.paintsChild(child)) return false;
    if (parent is RenderIndexedStack && !_isShownChild(parent, child)) {
      return false;
    }
    child = parent;
    parent = parent.parent;
  }
  final rect = MatrixUtils.transformRect(
    object.getTransformTo(null),
    Offset.zero & object.size,
  );
  if (child is RenderView) {
    return rect.overlaps(Offset.zero & child.size);
  }
  return !rect.isEmpty;
}

bool _isShownChild(RenderIndexedStack stack, RenderObject child) {
  var i = 0;
  var current = stack.firstChild;
  while (current != null && !identical(current, child)) {
    current = stack.childAfter(current);
    i++;
  }
  return current != null && i == stack.index;
}
