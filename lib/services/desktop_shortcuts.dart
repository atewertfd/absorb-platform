import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../utils/fork_platform.dart';

/// Actions exposed by the desktop shell. Keeping these in one table means the
/// actual bindings and the accessibility help UI cannot drift apart.
enum DesktopShortcutAction {
  playPause,
  rewind,
  forward,
  slower,
  faster,
  normalSpeed,
  search,
  library,
  nowPlaying,
  fullScreen,
}

class DesktopShortcutDefinition {
  final DesktopShortcutAction action;
  final LogicalKeyboardKey key;
  final String label;
  final bool control;
  final bool shift;
  final bool alt;

  /// Works wherever focus is (function keys never type text).
  final bool global;

  const DesktopShortcutDefinition({
    required this.action,
    required this.key,
    required this.label,
    this.control = false,
    this.shift = false,
    this.alt = false,
    this.global = false,
  });

  /// No modifier: a key that also types text (Space, arrows, brackets).
  bool get isPlainKey => !global && !control && !shift && !alt;

  SingleActivator get activator => SingleActivator(
        key,
        control: control,
        shift: shift,
        alt: alt,
      );
}

/// The shortcuts for this platform; F11 full screen is Windows-only.
List<DesktopShortcutDefinition> get desktopShortcutDefinitions => [
      ..._sharedShortcutDefinitions,
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows)
        _fullScreenShortcut,
    ];

const _fullScreenShortcut = DesktopShortcutDefinition(
  action: DesktopShortcutAction.fullScreen,
  key: LogicalKeyboardKey.f11,
  label: 'F11',
  global: true,
);

const _sharedShortcutDefinitions = <DesktopShortcutDefinition>[
  DesktopShortcutDefinition(
    action: DesktopShortcutAction.playPause,
    key: LogicalKeyboardKey.space,
    label: 'Space',
  ),
  DesktopShortcutDefinition(
    action: DesktopShortcutAction.rewind,
    key: LogicalKeyboardKey.arrowLeft,
    label: 'Left Arrow',
  ),
  DesktopShortcutDefinition(
    action: DesktopShortcutAction.forward,
    key: LogicalKeyboardKey.arrowRight,
    label: 'Right Arrow',
  ),
  DesktopShortcutDefinition(
    action: DesktopShortcutAction.slower,
    key: LogicalKeyboardKey.bracketLeft,
    label: '[',
  ),
  DesktopShortcutDefinition(
    action: DesktopShortcutAction.faster,
    key: LogicalKeyboardKey.bracketRight,
    label: ']',
  ),
  DesktopShortcutDefinition(
    action: DesktopShortcutAction.normalSpeed,
    key: LogicalKeyboardKey.backslash,
    label: '\\',
  ),
  DesktopShortcutDefinition(
    action: DesktopShortcutAction.search,
    key: LogicalKeyboardKey.keyF,
    label: 'Ctrl+F',
    control: true,
  ),
  DesktopShortcutDefinition(
    action: DesktopShortcutAction.library,
    key: LogicalKeyboardKey.keyL,
    label: 'Ctrl+L',
    control: true,
  ),
  DesktopShortcutDefinition(
    action: DesktopShortcutAction.nowPlaying,
    key: LogicalKeyboardKey.keyN,
    label: 'Ctrl+N',
    control: true,
  ),
];

DesktopShortcutDefinition desktopShortcutFor(DesktopShortcutAction action) {
  if (action == DesktopShortcutAction.fullScreen) return _fullScreenShortcut;
  return _sharedShortcutDefinitions
      .firstWhere((shortcut) => shortcut.action == action);
}

/// Window navigation on the native desktop builds: closing the full-screen
/// player, going back, refreshing and switching Absorbing cards. Kept apart
/// from [DesktopShortcutAction] because Settings switches over that enum.
enum DesktopNavigationAction {
  closePlayer,
  back,
  refresh,
  previousCard,
  nextCard,
}

/// When a navigation shortcut may fire, given where keyboard focus is.
enum DesktopShortcutFocusRule {
  /// Wherever focus is (Esc, F5, Alt+Left never type text).
  anywhere,

  /// Not while typing (Ctrl+arrows move by word in a text field).
  notTyping,

  /// Like Space and the arrows: only while nothing more specific has focus.
  plainKey,
}

class DesktopNavigationShortcut {
  final DesktopNavigationAction action;
  final SingleActivator activator;
  final String label;
  final DesktopShortcutFocusRule focusRule;

  const DesktopNavigationShortcut({
    required this.action,
    required this.activator,
    required this.label,
    this.focusRule = DesktopShortcutFocusRule.anywhere,
  });

  /// Whether focus allows this shortcut right now.
  bool get allowedByFocus => switch (focusRule) {
        DesktopShortcutFocusRule.anywhere => true,
        DesktopShortcutFocusRule.notTyping => !isTypingInTextField(),
        DesktopShortcutFocusRule.plainKey =>
          !isTypingInTextField() && nothingMoreSpecificHasFocus(),
      };
}

/// The navigation shortcuts; none on Android or web (the browser owns F5
/// and Alt+Left there). The mouse back button also goes back.
List<DesktopNavigationShortcut> get desktopNavigationShortcuts =>
    ForkPlatform.isDesktop ? _navigationShortcuts : const [];

const _navigationShortcuts = <DesktopNavigationShortcut>[
  DesktopNavigationShortcut(
    action: DesktopNavigationAction.closePlayer,
    activator: SingleActivator(LogicalKeyboardKey.escape),
    label: 'Esc',
  ),
  DesktopNavigationShortcut(
    action: DesktopNavigationAction.back,
    activator: SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true),
    label: 'Alt+Left',
  ),
  DesktopNavigationShortcut(
    action: DesktopNavigationAction.refresh,
    activator: SingleActivator(LogicalKeyboardKey.f5),
    label: 'F5',
  ),
  DesktopNavigationShortcut(
    action: DesktopNavigationAction.refresh,
    activator: SingleActivator(LogicalKeyboardKey.keyR, control: true),
    label: 'Ctrl+R',
  ),
  DesktopNavigationShortcut(
    action: DesktopNavigationAction.previousCard,
    activator: SingleActivator(LogicalKeyboardKey.arrowLeft, control: true),
    label: 'Ctrl+Left',
    focusRule: DesktopShortcutFocusRule.notTyping,
  ),
  DesktopNavigationShortcut(
    action: DesktopNavigationAction.nextCard,
    activator: SingleActivator(LogicalKeyboardKey.arrowRight, control: true),
    label: 'Ctrl+Right',
    focusRule: DesktopShortcutFocusRule.notTyping,
  ),
  DesktopNavigationShortcut(
    action: DesktopNavigationAction.previousCard,
    activator: SingleActivator(LogicalKeyboardKey.pageUp),
    label: 'Page Up',
    focusRule: DesktopShortcutFocusRule.plainKey,
  ),
  DesktopNavigationShortcut(
    action: DesktopNavigationAction.nextCard,
    activator: SingleActivator(LogicalKeyboardKey.pageDown),
    label: 'Page Down',
    focusRule: DesktopShortcutFocusRule.plainKey,
  ),
];

/// Whether keyboard focus is in a text field (search box, settings field).
bool isTypingInTextField() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.widget is EditableText ||
      context.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// The app shell's own focus node (one shell for the app's lifetime). Plain-key
/// shortcuts only fire while it holds focus, i.e. nothing more specific does.
final FocusNode desktopShellFocusNode =
    FocusNode(debugLabel: 'Desktop shortcuts shell');

/// True while the shell holds focus, or a page, sheet or the full-screen
/// player is open with nothing inside it focused (its route's focus scope is
/// the primary focus). A focused button, slider or text field returns false.
bool nothingMoreSpecificHasFocus() {
  final focus = FocusManager.instance.primaryFocus;
  return focus == desktopShellFocusNode || focus is FocusScopeNode;
}

/// Runs desktop shortcuts. Plain-key ones (Space, arrows, brackets) only run
/// on desktop while nothing more specific has focus (the shell, or an open
/// page or player with nothing in it focused): a focused button keeps Space,
/// a text field keeps typing, and D-pad arrows keep moving focus. A disabled
/// action lets the key through. Ctrl shortcuts always work.
class DesktopShortcutCallbackAction extends CallbackAction<Intent> {
  DesktopShortcutCallbackAction({
    required this.actionOf,
    required super.onInvoke,
  });

  final DesktopShortcutAction? Function(Intent intent) actionOf;

  @override
  bool isEnabled(Intent intent) {
    final action = actionOf(intent);
    if (action == null) return true;
    if (!desktopShortcutFor(action).isPlainKey) return true;
    final desktop = defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;
    return desktop && !isTypingInTextField() && nothingMoreSpecificHasFocus();
  }
}
