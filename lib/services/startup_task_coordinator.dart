import 'dart:async';

typedef StartupTask = Future<void> Function();
typedef StartupTaskErrorHandler =
    void Function(Object error, StackTrace stackTrace);

/// Separates startup work that must finish from optional work that can settle
/// after the first authenticated frame is available.
abstract final class StartupTaskCoordinator {
  static Future<void> runCritical(Iterable<StartupTask> tasks) async {
    for (final task in tasks) {
      await task();
    }
  }

  static void startBackground(
    Iterable<StartupTask> tasks, {
    required StartupTaskErrorHandler onError,
  }) {
    for (final task in tasks) {
      unawaited(Future<void>.microtask(() => _runBackground(task, onError)));
    }
  }

  static Future<void> _runBackground(
    StartupTask task,
    StartupTaskErrorHandler onError,
  ) async {
    try {
      await task();
    } catch (error, stackTrace) {
      onError(error, stackTrace);
    }
  }
}
