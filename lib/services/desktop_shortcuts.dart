import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SingleActivator;

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
}

class DesktopShortcutDefinition {
  final DesktopShortcutAction action;
  final LogicalKeyboardKey key;
  final String label;
  final bool control;
  final bool shift;
  final bool alt;

  const DesktopShortcutDefinition({
    required this.action,
    required this.key,
    required this.label,
    this.control = false,
    this.shift = false,
    this.alt = false,
  });

  SingleActivator get activator => SingleActivator(
        key,
        control: control,
        shift: shift,
        alt: alt,
      );
}

const desktopShortcutDefinitions = <DesktopShortcutDefinition>[
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
  return desktopShortcutDefinitions.firstWhere((shortcut) => shortcut.action == action);
}
