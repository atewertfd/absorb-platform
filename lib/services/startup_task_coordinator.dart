import 'dart:async';

typedef StartupTask = Future<void> Function();
typedef StartupTaskErrorHandler =
    void Function(Object error, StackTrace stackTrace);

/// Starts optional startup work that can settle after the first authenticated
/// frame is available; work that must finish is simply awaited in main.dart.
abstract final class StartupTaskCoordinator {
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
