import 'dart:ui' show SemanticsFlag;

import 'package:absorb/widgets/accessible_header_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Tab reaches header actions and Enter/Space activate only the focused control',
    (tester) async {
      var queueOpens = 0;
      var refreshes = 0;
      var globalPlayToggles = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.space): _PlayIntent(),
            },
            child: Actions(
              actions: {
                _PlayIntent: CallbackAction<_PlayIntent>(
                  onInvoke: (_) {
                    globalPlayToggles++;
                    return null;
                  },
                ),
              },
              child: Scaffold(
                body: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AccessibleHeaderAction(
                        label: 'Manage queue',
                        onPressed: () => queueOpens++,
                        child: const Icon(Icons.reorder),
                      ),
                      const AccessibleHeaderAction(
                        label: 'Busy',
                        onPressed: null,
                        child: Icon(Icons.stop),
                      ),
                      AccessibleHeaderAction(
                        label: 'Refresh',
                        onPressed: () => refreshes++,
                        child: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(queueOpens, 2);
      expect(refreshes, 0);
      expect(globalPlayToggles, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(refreshes, 1);
      expect(queueOpens, 2);
    },
  );

  testWidgets('exposes one labelled button and disables pointer activation', (
    tester,
  ) async {
      final semantics = tester.ensureSemantics();
    var presses = 0;
    Future<void> render(bool enabled) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AccessibleHeaderAction(
              label: 'Manage queue',
              onPressed: enabled ? () => presses++ : null,
              child: const Text('Manage queue'),
            ),
          ),
        ),
      ),
    );

    await render(true);
    final label = find.bySemanticsLabel('Manage queue');
    expect(label, findsOneWidget);
    final data = tester.getSemantics(label).getSemanticsData();
    expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(data.hasFlag(SemanticsFlag.isEnabled), isTrue);
    await tester.tap(find.byType(AccessibleHeaderAction));
    expect(presses, 1);

    await render(false);
    expect(
      tester
          .getSemantics(label)
          .getSemanticsData()
          .hasFlag(SemanticsFlag.isEnabled),
      isFalse,
    );
    await tester.tap(find.byType(AccessibleHeaderAction));
    expect(presses, 1);
      expect(tester.takeException(), isNull);
      semantics.dispose();
  });
}

class _PlayIntent extends Intent {
  const _PlayIntent();
}
