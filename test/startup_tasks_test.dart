import 'dart:async';

import 'package:absorb/services/startup_task_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('critical tasks run in order and complete before readiness', () async {
    final events = <String>[];

    await StartupTaskCoordinator.runCritical([
      () async => events.add('first'),
      () async => events.add('second'),
    ]);

    expect(events, ['first', 'second']);
  });

  test(
    'background tasks start without blocking the caller and contain errors',
    () async {
      final gate = Completer<void>();
      final errors = <Object>[];
      var started = false;

      StartupTaskCoordinator.startBackground([
        () async {
          started = true;
          await gate.future;
          throw StateError('optional task failed');
        },
      ], onError: (error, _) => errors.add(error));

      expect(started, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(started, isTrue);

      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
    },
  );
}
