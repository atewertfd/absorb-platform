import 'dart:io';

import 'package:just_audio_media_kit/just_audio_media_kit.dart';

bool _initialized = false;

/// Register the native playback backend before constructing an AudioPlayer.
/// SMTC (Windows) and MPRIS (Linux) register through Flutter's plugin loader.
void initializeDesktopAudio() {
  if (_initialized || (!Platform.isWindows && !Platform.isLinux)) return;
  JustAudioMediaKit.title = 'Absorb Plus';
  JustAudioMediaKit.ensureInitialized(windows: true, linux: true);
  _initialized = true;
}
