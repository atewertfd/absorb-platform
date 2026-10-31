import '../utils/web_safe_platform.dart'; // web-safe Platform

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'api_service.dart';
import 'book_track_resolver.dart';

/// Outcome of a clip export. [tempPath] is a freshly written .m4a in the temp
/// dir that the caller should hand to a save/share sheet and then delete.
/// [clamped] is true when the requested length ran past the end of the track
/// the bookmark sits in and we shortened it (cross-file stitching isn't done).
class ClipExportResult {
  ClipExportResult({
    required this.tempPath,
    required this.durationSeconds,
    required this.clamped,
  });
  final String tempPath;
  final double durationSeconds;
  final bool clamped;
}

class ClipExportException implements Exception {
  ClipExportException(this.message, {this.code});
  final String message;
  /// Optional machine-readable reason so the UI can react specially (e.g.
  /// 'needs_download' -> offer to download the book on iOS).
  final String? code;
  @override
  String toString() => 'ClipExportException: $message';
}

/// Extracts a short audio clip starting at a bookmark and encodes it to .m4a
/// (AAC) via native code (Android MediaCodec + MediaMuxer, iOS
/// AVAssetExportSession). Downloaded books export from the local file on both
/// platforms. Streamed books: Android's native side range-requests just the
/// window from the URL; iOS can't export from a remote URL, so a streamed book
/// must be downloaded first ([ClipExportException] code 'needs_download').
class ClipExportService {
  static const _channel = MethodChannel('com.absorb.clip');

  /// Build a clip for [itemId] starting at [startSeconds] (global book
  /// position) running [requestedDuration] seconds. Throws
  /// [ClipExportException] on any failure so the UI can react.
  Future<ClipExportResult> exportClip({
    required String itemId,
    required double startSeconds,
    required double requestedDuration,
    ApiService? api,
  }) async {
    final tracks = await BookTrackResolver.resolve(itemId, api);
    if (tracks == null || tracks.isEmpty) {
      throw ClipExportException('no audio resolved for $itemId');
    }
    final hit = BookTrackResolver.mapGlobal(tracks, startSeconds);
    final track = hit.track;

    // iOS can't extract a clip from a remote URL (neither AVAssetExportSession
    // nor AVAssetReader handle it). Rather than silently download a whole file,
    // ask the user to download the book first.
    if (!track.local && Platform.isIOS) {
      throw ClipExportException('book must be downloaded', code: 'needs_download');
    }

    // Don't run past the end of this track - cross-file stitching is a v1
    // limitation, so shorten and tell the user.
    var duration = requestedDuration;
    var clamped = false;
    if (track.duration > 0) {
      final available = track.duration - hit.localOffset;
      if (available > 1 && duration > available) {
        duration = available;
        clamped = true;
      }
    }
    if (duration < 1) duration = requestedDuration;

    final tmp = await getTemporaryDirectory();
    final outPath =
        '${tmp.path}/absorb_clip_${DateTime.now().millisecondsSinceEpoch}.m4a';

    var ok = false;
    try {
      ok = await _channel.invokeMethod<bool>('exportClip', {
            'source': track.source,
            'isLocal': track.local,
            'headers': track.local ? null : api?.mediaHeaders,
            'startSeconds': hit.localOffset,
            'durationSeconds': duration,
            'outPath': outPath,
          }) ??
          false;
    } on PlatformException catch (e) {
      debugPrint('[ClipExport] native error: ${e.code} ${e.message}');
      throw ClipExportException(e.message ?? e.code);
    }
    if (!ok) throw ClipExportException('native export returned false');

    return ClipExportResult(
      tempPath: outPath,
      durationSeconds: duration,
      clamped: clamped,
    );
  }
}
