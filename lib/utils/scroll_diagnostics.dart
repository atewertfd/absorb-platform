import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Opt-in scroll diagnostics for desktop builds: set the environment variable
/// ABSORB_SCROLL_DIAG=1 before starting the app. Records raw wheel events and
/// per-frame timings to %TEMP%\absorb-scroll-diag.txt so choppy scrolling can
/// be told apart: low frame rate, slow frames, or coarse wheel input.
/// Does nothing (and costs nothing) when the variable is not set.
void installScrollDiagnostics({bool Function()? smoothingEnabled}) {
  if (kIsWeb || !(Platform.isWindows || Platform.isLinux)) return;
  if (Platform.environment['ABSORB_SCROLL_DIAG'] != '1') return;

  final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}absorb-scroll-diag.txt');
  file.writeAsStringSync('');
  // Appended synchronously twice a second so nothing is lost when the app
  // is closed.
  final sink = StringBuffer();
  Timer.periodic(const Duration(milliseconds: 500), (_) {
    if (sink.isEmpty) return;
    file.writeAsStringSync(sink.toString(), mode: FileMode.append);
    sink.clear();
  });
  final clock = Stopwatch()..start();
  final dispatcher = ui.PlatformDispatcher.instance;
  for (final display in dispatcher.displays) {
    sink.writeln('display id=${display.id} refreshRate=${display.refreshRate} '
        'dpr=${display.devicePixelRatio} size=${display.size}');
  }

  final original = dispatcher.onPointerDataPacket;
  if (original != null) {
    dispatcher.onPointerDataPacket = (packet) {
      for (final d in packet.data) {
        if (d.signalKind == ui.PointerSignalKind.scroll ||
            d.change == ui.PointerChange.panZoomUpdate) {
          sink.writeln('wheel t=${clock.elapsedMicroseconds} kind=${d.kind.name} '
              'signal=${d.signalKind?.name} change=${d.change.name} '
              'dx=${d.scrollDeltaX} dy=${d.scrollDeltaY} panDy=${d.panDeltaY} '
              'smoothing=${smoothingEnabled?.call()}');
        }
      }
      original(packet);
    };
  }

  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      sink.writeln('frame vsync=${t.timestampInMicroseconds(ui.FramePhase.vsyncStart)} '
          'build=${t.buildDuration.inMicroseconds} '
          'raster=${t.rasterDuration.inMicroseconds} '
          'total=${t.totalSpan.inMicroseconds}');
    }
  });
}
