import 'package:absorb/services/desktop_shortcuts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop shortcuts expose playback and navigation actions', () {
    expect(
      desktopShortcutDefinitions.map((shortcut) => shortcut.action),
      containsAll(<DesktopShortcutAction>[
        DesktopShortcutAction.playPause,
        DesktopShortcutAction.rewind,
        DesktopShortcutAction.forward,
        DesktopShortcutAction.slower,
        DesktopShortcutAction.faster,
        DesktopShortcutAction.normalSpeed,
        DesktopShortcutAction.search,
        DesktopShortcutAction.library,
        DesktopShortcutAction.nowPlaying,
      ]),
    );
  });

  test('speed shortcuts use unmodified bracket keys', () {
    final slower = desktopShortcutFor(DesktopShortcutAction.slower);
    final faster = desktopShortcutFor(DesktopShortcutAction.faster);
    final normal = desktopShortcutFor(DesktopShortcutAction.normalSpeed);

    expect(slower.key, LogicalKeyboardKey.bracketLeft);
    expect(faster.key, LogicalKeyboardKey.bracketRight);
    expect(normal.key, LogicalKeyboardKey.backslash);
    expect(slower.control, isFalse);
    expect(faster.control, isFalse);
    expect(normal.control, isFalse);
  });

  test('shortcut labels are stable and readable', () {
    expect(desktopShortcutFor(DesktopShortcutAction.playPause).label, 'Space');
    expect(desktopShortcutFor(DesktopShortcutAction.rewind).label, 'Left Arrow');
    expect(desktopShortcutFor(DesktopShortcutAction.search).label, 'Ctrl+F');
  });
}
