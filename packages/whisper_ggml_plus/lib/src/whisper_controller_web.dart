import 'package:flutter/foundation.dart';
import 'package:whisper_ggml_plus/src/models/whisper_model.dart';

import 'models/whisper_result.dart';
import 'whisper_audio_convert.dart';

/// Web-safe placeholder for the native whisper.cpp controller.
///
/// Keeping this API available lets the main application compile and run on
/// GitHub Pages. The UI can still use the rest of Absorb; only optional
/// on-device transcription is unavailable on web.
class WhisperController {
  static WhisperAudioConverter? _audioConverter;

  static void registerAudioConverter(WhisperAudioConverter converter) {
    _audioConverter = converter;
    debugPrint('Whisper audio conversion is unavailable on web.');
  }

  Future<void> initModel(WhisperModel model) async {}

  Future<TranscribeResult?> transcribe({
    required WhisperModel model,
    required String audioPath,
    String lang = 'en',
    bool diarize = false,
    bool withTimestamps = true,
    bool splitOnWord = false,
    bool convert = true,
    int threads = 6,
    bool isTranslate = false,
    bool speedUp = false,
    bool noFallback = false,
    Object? vadMode,
    String? vadModelPath,
  }) async {
    throw UnsupportedError(
      'On-device Whisper transcription is not available in the web port.',
    );
  }

  static Future<String> getModelDir() async => '';

  Future<String> getPath(WhisperModel model) async => '';

  Future<String> downloadModel(WhisperModel model) async =>
      throw UnsupportedError(
        'Whisper models are not available in the web port.',
      );

  Future<void> dispose({WhisperModel model = WhisperModel.base}) async {}
}
