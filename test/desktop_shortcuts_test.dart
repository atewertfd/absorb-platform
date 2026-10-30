import 'package:absorb/services/desktop_shortcuts.dart';
import 'package:flutter/material.dart';
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

  group('while typing in a text field', () {
    late List<DesktopShortcutAction> fired;
    late TextEditingController text;
    late FocusNode fieldFocus;
    late FocusNode buttonFocus;
    late int buttonPresses;

    Future<void> pump(WidgetTester tester) async {
      fired = [];
      text = TextEditingController();
      fieldFocus = FocusNode();
      buttonFocus = FocusNode();
      buttonPresses = 0;
      addTearDown(buttonFocus.dispose);
      addTearDown(text.dispose);
      addTearDown(fieldFocus.dispose);
      await tester.pumpWidget(MaterialApp(
        // Same order as AppShell: Shortcuts > Actions > Focus(autofocus).
        home: Shortcuts(
            shortcuts: {
              for (final s in desktopShortcutDefinitions)
                s.activator: _TestIntent(s.action),
            },
            child: Actions(
              actions: {
                _TestIntent: DesktopShortcutCallbackAction(
                  actionOf: (i) => i is _TestIntent ? i.action : null,
                  onInvoke: (i) {
                    fired.add((i as _TestIntent).action);
                    return null;
                  },
                ),
              },
              child: Focus(
                focusNode: desktopShellFocusNode,
                child: Material(
                  child: Column(children: [
                    TextField(controller: text, focusNode: fieldFocus),
                    ElevatedButton(
                      focusNode: buttonFocus,
                      onPressed: () => buttonPresses++,
                      child: const Text('button'),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ));
    }

    final windows = TargetPlatformVariant.only(TargetPlatform.windows);

    testWidgets('Space and arrows go to the text, not to playback',
        variant: windows, (tester) async {
      await pump(tester);
      fieldFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
      expect(fired, isEmpty);
    });

    testWidgets('Ctrl shortcuts still work in a text field', variant: windows,
        (tester) async {
      await pump(tester);
      fieldFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(fired, [DesktopShortcutAction.search]);
    });

    testWidgets('with only the shell focused, Space plays or pauses',
        variant: windows, (tester) async {
      await pump(tester);
      desktopShellFocusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(fired, [DesktopShortcutAction.playPause]);
    });

    testWidgets('a focused button keeps Space for itself', variant: windows,
        (tester) async {
      await pump(tester);
      buttonFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(fired, isEmpty);
      expect(buttonPresses, 1);
    });

    testWidgets('on Android, plain keys never trigger shortcuts',
        (tester) async {
      await pump(tester);
      desktopShellFocusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(fired, isEmpty);
    });
  });
}

class _TestIntent extends Intent {
  const _TestIntent(this.action);
  final DesktopShortcutAction action;
}
