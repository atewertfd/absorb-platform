import 'models/whisper_model.dart';

export 'models/_models.dart';

/// Web placeholder for the native whisper.cpp bridge.
///
/// The real implementation uses dart:ffi and is selected on native targets.
/// Transcription is intentionally unavailable in the web port until a
/// browser-compatible speech engine is added.
class Whisper {
  const Whisper({required this.model, this.modelDir});

  final WhisperModel model;
  final String? modelDir;

  static const bool usesCompatEngine = false;

  Never _unsupported() => throw UnsupportedError(
        'On-device Whisper transcription is not available in the web port.',
      );

  Future<({Object response, String? language})> transcribe({
    required Object transcribeRequest,
    required String modelPath,
  }) async => _unsupported();

  Future<String?> getVersion() async => _unsupported();
  Future<void> abort() async => _unsupported();
  Future<void> dispose() async => _unsupported();
}
