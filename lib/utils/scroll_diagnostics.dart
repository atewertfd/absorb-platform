import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';


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

  // Once a second, record who asked for a rebuild (the setState caller), so a
  // screen that never stops redrawing can be traced to its source.
  final owner = WidgetsBinding.instance.buildOwner;
  final originalScheduled = owner?.onBuildScheduled;
  var builds = 0;
  var lastSample = -1;
  owner?.onBuildScheduled = () {
    builds++;
    final second = clock.elapsedMilliseconds ~/ 1000;
    if (second != lastSample) {
      lastSample = second;
      final frames = StackTrace.current
          .toString()
          .split('\n')
          .skip(1)
          .take(30)
          .map((l) => l.replaceFirst(RegExp(r'^#\d+\s+'), '').trim())
          .join(' <- ');
      sink.writeln('rebuild t=${clock.elapsedMicroseconds} '
          'scheduledSoFar=$builds by: $frames');
    }
    originalScheduled?.call();
  };

  // Debug builds only: count every widget rebuilt per second, with the widgets
  // that created it, to find what keeps an idle screen redrawing.
  if (kDebugMode) {
    final perSecond = <String, int>{};
    // From 15 s in, capture a few scheduleBuildFor stacks (who marked a
    // widget dirty) into the log.
    var captured = 0;
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (clock.elapsedMilliseconds > 15000 && captured < 400) {
        captured++;
        sink.writeln('stack $message');
      }
      originalDebugPrint(message, wrapWidth: wrapWidth);
    };
    Timer(const Duration(seconds: 15), () => debugPrintScheduleBuildForStacks = true);
    Timer(const Duration(seconds: 17), () => debugPrintScheduleBuildForStacks = false);

    // The shallowest element rebuilt in a frame is where that frame's
    // rebuild started; count those, with enough ancestors to name the owner.
    Element? frameTop;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (frameTop == null || element.depth < frameTop!.depth) {
        frameTop = element;
      }
    };
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      final top = frameTop;
      frameTop = null;
      if (top == null) return;
      final key = top.debugGetCreatorChain(10);
      perSecond[key] = (perSecond[key] ?? 0) + 1;
    });
    Timer.periodic(const Duration(seconds: 1), (_) {
      final top = perSecond.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in top.take(8)) {
        sink.writeln('rebuilt t=${clock.elapsedMilliseconds ~/ 1000}s '
            'x${e.value}: ${e.key}');
      }
      perSecond.clear();
    });
  }

  // Tickers already queued for the next frame: >0 on an idle screen means an
  // animation is running; 0 means a timer or stream keeps calling setState.
  SchedulerBinding.instance.addPersistentFrameCallback((_) {
    sink.writeln('drawn t=${clock.elapsedMicroseconds} '
        'tickers=${SchedulerBinding.instance.transientCallbackCount}');
  });
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      sink.writeln('frame vsync=${t.timestampInMicroseconds(ui.FramePhase.vsyncStart)} '
          'build=${t.buildDuration.inMicroseconds} '
          'raster=${t.rasterDuration.inMicroseconds} '
          'total=${t.totalSpan.inMicroseconds}');
    }
  });
}
