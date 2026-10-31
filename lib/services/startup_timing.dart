import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/web_safe_platform.dart';

/// One log line per launch saying where startup time went:
///
/// `[Startup] launch→main 850ms, main→first frame 420ms, →signed in 900ms,
/// →home 1650ms (since main)`
///
/// "launch→main" (Windows only) is the time before any Dart code runs:
/// loading the exe, its DLLs and the Flutter engine. The other steps count
/// from the start of `main()`. The line is written once home first has
/// content, when the log file is open (it opens after the first frame).
class StartupTiming {
  StartupTiming._();

  static final Stopwatch _sinceMain = Stopwatch();
  static final Map<String, int> _marks = {};
  static Future<int?>? _preMain;
  static bool _reported = false;

  /// First thing in `main()`.
  static void markMain() {
    _sinceMain.start();
  }

  /// Records [step] the first time it happens (later calls are ignored).
  static void mark(String step) {
    if (_reported || !_sinceMain.isRunning) return;
    _marks.putIfAbsent(step, () => _sinceMain.elapsedMilliseconds);
  }

  /// After the first frame: also asks Windows how old the process is, which
  /// gives the time spent before `main()`.
  static void markFirstFrame() {
    mark('first frame');
    if (!Platform.isWindows || _preMain != null) return;
    final sinceMain = _sinceMain.elapsedMilliseconds;
    _preMain = const MethodChannel('absorb/windows_shell')
        .invokeMethod<int>('processAgeMs')
        .then<int?>((age) => age == null || age < 0 ? null : age - sinceMain)
        .catchError((Object _) => null);
  }

  /// Home has its first content: writes the line and stops recording.
  static Future<void> markHomeReady() async {
    if (_reported || !_sinceMain.isRunning) return;
    mark('home');
    _reported = true;
    final preMain = await (_preMain ?? Future<int?>.value());
    debugPrint(describe(preMainMs: preMain, marks: _marks));
  }

  @visibleForTesting
  static String describe({int? preMainMs, required Map<String, int> marks}) {
    final parts = <String>[
      if (preMainMs != null) 'launch→main ${preMainMs}ms',
      for (final e in marks.entries)
        e.key == 'first frame'
            ? 'main→first frame ${e.value}ms'
            : '→${e.key} ${e.value}ms',
    ];
    return '[Startup] ${parts.join(', ')} (since main)';
  }

  @visibleForTesting
  static void reset() {
    _sinceMain
      ..stop()
      ..reset();
    _marks.clear();
    _preMain = null;
    _reported = false;
  }
}
