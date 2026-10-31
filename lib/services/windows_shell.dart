import 'dart:async';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import 'audio_player_service.dart';
import 'download_service.dart';

/// What the taskbar button shows for the current book.
enum TaskbarPlayback { none, playing, paused }

/// Limits taskbar updates: a state change goes out at once, progress at most
/// once a second and only after it moved at least 0.5%.
class TaskbarProgressThrottle {
  TaskbarProgressThrottle({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  static const minInterval = Duration(seconds: 1);
  static const minStep = 0.005;

  final DateTime Function() _clock;
  TaskbarPlayback? _state;
  double _progress = 0;
  DateTime? _sentAt;

  bool shouldSend(TaskbarPlayback state, double progress) {
    final now = _clock();
    final stateChanged = state != _state;
    final moved = (progress - _progress).abs() >= minStep;
    final due = _sentAt == null || now.difference(_sentAt!) >= minInterval;
    if (!stateChanged && !(moved && due)) return false;
    _state = state;
    _progress = progress;
    _sentAt = now;
    return true;
  }
}

/// The Windows settings the runner keeps (registry, applied at start-up).
class WindowsShellSettings {
  const WindowsShellSettings({
    this.closeToTray = false,
    this.startMinimized = false,
    this.startWithWindows = false,
    this.startWithWindowsThisCopy = false,
    this.startWithWindowsCommand = '',
    this.startupDisabledBySystem = false,
    this.alwaysOnTop = false,
    this.keepAwake = true,
    this.fullScreen = false,
    this.exePath = '',
  });

  factory WindowsShellSettings.fromMap(Map<Object?, Object?> map) {
    bool flag(String key, bool fallback) =>
        map[key] is bool ? map[key]! as bool : fallback;
    String text(String key) => map[key] is String ? map[key]! as String : '';
    return WindowsShellSettings(
      closeToTray: flag('closeToTray', false),
      startMinimized: flag('startMinimized', false),
      startWithWindows: flag('startWithWindows', false),
      startWithWindowsThisCopy: flag('startWithWindowsThisCopy', false),
      startWithWindowsCommand: text('startWithWindowsCommand'),
      startupDisabledBySystem: flag('startupDisabledBySystem', false),
      alwaysOnTop: flag('alwaysOnTop', false),
      keepAwake: flag('keepAwake', true),
      fullScreen: flag('fullScreen', false),
      exePath: text('exePath'),
    );
  }

  final bool closeToTray;
  final bool startMinimized;

  /// A Windows startup entry exists (maybe for another copy of the app).
  final bool startWithWindows;
  final bool startWithWindowsThisCopy;

  /// The registered startup command, shown so portable copies see the path.
  final String startWithWindowsCommand;

  /// Switched off in Task Manager's Startup apps page.
  final bool startupDisabledBySystem;
  final bool alwaysOnTop;

  /// Keep the PC from sleeping while playing or downloading.
  final bool keepAwake;
  final bool fullScreen;
  final String exePath;
}

/// What the shell needs from playback; the app's player by default, a fake in
/// tests.
abstract class WindowsShellPlayback implements Listenable {
  bool get hasBook;
  bool get isPlaying;

  /// Position in the whole book, 0..1.
  double get progress;
  Future<void> playPause();
  Future<void> rewind();
  Future<void> forward();

  /// Saves the position before the app quits (bounded by the caller).
  Future<void> saveForExit();
}

abstract class WindowsShellDownloads implements Listenable {
  bool get busy;
}

/// Windows desktop integration (fork-owned). The runner side is
/// windows/runner/windows_shell.cpp over the `absorb/windows_shell` channel:
/// saving progress before quitting, tray, start with Windows, always on top,
/// keeping the PC awake while playing or downloading, taskbar buttons and
/// progress, and full screen. Everything is a no-op off Windows and on web.
/// It only listens to the player; it never rebuilds UI.
class WindowsShell {
  WindowsShell._()
      : _channel = const MethodChannel('absorb/windows_shell'),
        _enabled = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows,
        _playbackOverride = null,
        _downloadsOverride = null,
        _throttle = TaskbarProgressThrottle();

  /// A shell with its own playback and download sources: tests and the
  /// runner probe (tool/windows_shell_probe.dart).
  WindowsShell.withSources({
    required MethodChannel channel,
    required WindowsShellPlayback playback,
    required WindowsShellDownloads downloads,
    DateTime Function()? clock,
  })  : _channel = channel,
        _enabled = true,
        _playbackOverride = playback,
        _downloadsOverride = downloads,
        _throttle = TaskbarProgressThrottle(clock: clock);

  static final WindowsShell instance = WindowsShell._();

  /// How long saving before quit may take; the runner gives up after 4 s.
  static const exitSaveTimeout = Duration(milliseconds: 3000);

  final MethodChannel _channel;
  final bool _enabled;
  final WindowsShellPlayback? _playbackOverride;
  final WindowsShellDownloads? _downloadsOverride;
  final TaskbarProgressThrottle _throttle;

  late final WindowsShellPlayback _playback =
      _playbackOverride ?? _AppPlayback();
  late final WindowsShellDownloads _downloads =
      _downloadsOverride ?? _AppDownloads();

  /// Latest settings from the runner, for the settings tiles.
  final ValueNotifier<WindowsShellSettings?> settings = ValueNotifier(null);

  bool get isSupported => _enabled;

  bool _started = false;
  Timer? _progressTimer;
  Timer? _busyCheck;
  bool? _busySent;

  Future<void> start() async {
    if (!_enabled || _started) return;
    _started = true;
    _channel.setMethodCallHandler(_onNativeCall);
    _playback.addListener(_syncPlayback);
    _downloads.addListener(_scheduleBusyCheck);
    if (_playbackOverride == null) {
      PlayerSettings.settingsChanged.addListener(_onSettingsChanged);
    }
    _syncPlayback();
    _checkBusy();
    await Future.wait([_pushStrings(), refresh()]);
  }

  @visibleForTesting
  void stop() {
    _progressTimer?.cancel();
    _busyCheck?.cancel();
    _playback.removeListener(_syncPlayback);
    _downloads.removeListener(_scheduleBusyCheck);
    if (_playbackOverride == null) {
      PlayerSettings.settingsChanged.removeListener(_onSettingsChanged);
    }
    _channel.setMethodCallHandler(null);
    _started = false;
  }

  Future<WindowsShellSettings?> refresh() => _settingsCall('getState');

  Future<WindowsShellSettings?> setCloseToTray(bool enabled) =>
      _settingsCall('setCloseToTray', enabled);

  Future<WindowsShellSettings?> setStartMinimized(bool enabled) =>
      _settingsCall('setStartMinimized', enabled);

  Future<WindowsShellSettings?> setStartWithWindows(bool enabled) =>
      _settingsCall('setStartWithWindows', enabled);

  Future<WindowsShellSettings?> setAlwaysOnTop(bool enabled) =>
      _settingsCall('setAlwaysOnTop', enabled);

  Future<WindowsShellSettings?> setKeepAwake(bool enabled) =>
      _settingsCall('setKeepAwake', enabled);

  /// F11: borderless full screen on the window's monitor and back.
  Future<void> toggleFullScreen() async {
    if (!_enabled) return;
    try {
      await _channel.invokeMethod<bool>('toggleFullScreen');
    } catch (e) {
      debugPrint('[WindowsShell] toggleFullScreen failed: $e');
    }
  }

  Future<WindowsShellSettings?> _settingsCall(String method,
      [bool? enabled]) async {
    if (!_enabled) return null;
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        method,
        enabled == null ? null : {'enabled': enabled},
      );
      if (result == null) return settings.value;
      final next = WindowsShellSettings.fromMap(result);
      settings.value = next;
      return next;
    } on MissingPluginException {
      return null;
    } catch (e) {
      debugPrint('[WindowsShell] $method failed: $e');
      rethrow;
    }
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'action':
        await _runAction(call.arguments as String?);
        return null;
      case 'prepareToExit':
        await prepareToExit();
        return true;
    }
    throw MissingPluginException('WindowsShell: ${call.method}');
  }

  Future<void> _runAction(String? action) async {
    if (!_playback.hasBook) return;
    switch (action) {
      case 'playPause':
        await _playback.playPause();
      case 'rewind':
        await _playback.rewind();
      case 'forward':
        await _playback.forward();
    }
  }

  /// Called by the runner when the user quits: save the position while the
  /// window is already gone. Pausing saves locally first, then syncs.
  @visibleForTesting
  Future<void> prepareToExit() async {
    _progressTimer?.cancel();
    if (_playback.hasBook && _playback.isPlaying) {
      try {
        await _playback.saveForExit().timeout(exitSaveTimeout);
      } catch (e) {
        debugPrint('[WindowsShell] Saving before quit: $e');
      }
    }
    // Let writes started just before (preferences, logs) reach the disk.
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  void _onSettingsChanged() => unawaited(_pushStrings());

  // ── Taskbar and tray playback state ────────────────────────────────

  void _syncPlayback() {
    final state = !_playback.hasBook
        ? TaskbarPlayback.none
        : _playback.isPlaying
            ? TaskbarPlayback.playing
            : TaskbarPlayback.paused;
    final progress =
        state == TaskbarPlayback.none ? 0.0 : _playback.progress.clamp(0.0, 1.0);
    if (_throttle.shouldSend(state, progress)) {
      _invoke('setPlayback', {'state': state.name, 'progress': progress});
    }
    // Progress moves without notifications while playing: poll gently then.
    if (state == TaskbarPlayback.playing) {
      _progressTimer ??=
          Timer.periodic(TaskbarProgressThrottle.minInterval, (_) => _syncPlayback());
    } else {
      _progressTimer?.cancel();
      _progressTimer = null;
    }
    _sendBusy();
  }

  // ── Keep awake: playing or downloading ─────────────────────────────

  void _scheduleBusyCheck() {
    // Download progress notifies often; look at most once a second.
    _busyCheck ??= Timer(const Duration(seconds: 1), () {
      _busyCheck = null;
      _checkBusy();
    });
  }

  bool _downloading = false;

  void _checkBusy() {
    _downloading = _downloads.busy;
    _sendBusy();
  }

  void _sendBusy() {
    final busy = _playback.isPlaying || _downloading;
    if (busy == _busySent) return;
    _busySent = busy;
    _invoke('setBusy', {'busy': busy});
  }

  // ── Labels for the tray menu and taskbar buttons ───────────────────

  Future<void> _pushStrings() async {
    AppLocalizations l;
    try {
      final saved =
          _playbackOverride == null ? await PlayerSettings.getLanguage() : '';
      final locale = saved.isNotEmpty
          ? Locale(saved)
          : PlatformDispatcher.instance.locale;
      l = lookupAppLocalizations(locale);
    } catch (_) {
      l = lookupAppLocalizations(const Locale('en'));
    }
    await _invoke('setStrings', {
      'show': l.windowsTrayShow,
      'play': l.windowsTaskbarPlay,
      'pause': l.windowsTaskbarPause,
      'quit': l.windowsTrayQuit,
      'rewind': l.windowsTaskbarRewind,
      'forward': l.windowsTaskbarForward,
    });
  }

  Future<void> _invoke(String method, Object? arguments) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Older runner without the shell channel.
    } catch (e) {
      debugPrint('[WindowsShell] $method failed: $e');
    }
  }
}

class _AppPlayback extends ChangeNotifier implements WindowsShellPlayback {
  _AppPlayback() {
    _player.addListener(notifyListeners);
  }

  final AudioPlayerService _player = AudioPlayerService();

  @override
  bool get hasBook => _player.hasBook;

  @override
  bool get isPlaying => _player.isPlaying;

  @override
  double get progress {
    final total = _player.totalDuration > 0
        ? _player.totalDuration
        : _player.duration.inMilliseconds / 1000.0;
    if (total <= 0) return 0;
    return _player.position.inMilliseconds / 1000.0 / total;
  }

  // Same as the desktop Space shortcut and the media keys.
  @override
  Future<void> playPause() =>
      _player.isPlaying ? _player.pause() : _player.play(fromUi: true);

  @override
  Future<void> rewind() async => AudioPlayerService.handler?.rewind();

  @override
  Future<void> forward() async => AudioPlayerService.handler?.fastForward();

  @override
  Future<void> saveForExit() => _player.pause();
}

class _AppDownloads extends ChangeNotifier implements WindowsShellDownloads {
  _AppDownloads() {
    _service.addListener(notifyListeners);
  }

  final DownloadService _service = DownloadService();

  @override
  bool get busy =>
      _service.activeDownloads.isNotEmpty ||
      _service.queuedDownloads.isNotEmpty;
}
