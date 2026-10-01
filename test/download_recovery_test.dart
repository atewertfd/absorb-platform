import 'dart:convert';

import 'package:absorb/services/api_service.dart';
import 'package:absorb/services/download_service.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> failDownload(DownloadService service) async {
    await service.debugSeedPendingDownload(
      itemId: 'retry-regression-book',
      trackCount: 1,
      libraryId: 'library-fiction',
    );
    await service.debugHandleTaskStatus(
      itemId: 'retry-regression-book',
      trackIndex: 0,
      status: TaskStatus.notFound,
    );
  }

  test(
    'failed task retains its library in the persisted retry record',
    () async {
      final deletedRecords = <String>[];
      final service = DownloadService.forTesting(
        initialize: () async {},
        cancelTasks: (_) async {},
        deleteTaskRecord: (id) async => deletedRecords.add(id),
      );
      addTearDown(service.dispose);

      await failDownload(service);

      expect(service.activeDownloads, isEmpty);
      expect(service.downloadedItems, isEmpty);
      expect(service.failedDownloads.single.libraryId, 'library-fiction');
      expect(
        service.failedDownloads.single.failureReason,
        DownloadFailureReason.missingFile,
      );
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString('downloads')!) as Map;
      expect(saved['retry-regression-book']['libraryId'], 'library-fiction');
      expect(saved['retry-regression-book']['failureReason'], 'missingFile');
      expect(
        saved['retry-regression-book']['status'],
        DownloadStatus.error.index,
      );
      expect(prefs.getString('pending_downloads'), isNull);
      expect(deletedRecords, ['retry-regression-book::0']);

      await service.dismissFailedDownload('retry-regression-book');
      expect(service.failedDownloads, isEmpty);
      expect(jsonDecode(prefs.getString('downloads')!), isEmpty);
    },
  );

  for (final failure in [
    (
      'ENOSPC: no space left on device',
      DownloadFailureReason.insufficientSpace,
    ),
    ('Disk full', DownloadFailureReason.insufficientSpace),
    ('Permission denied', DownloadFailureReason.permissionDenied),
  ]) {
    test('persists actionable failure for ${failure.$1}', () async {
      final service = DownloadService.forTesting(
        initialize: () async {},
        cancelTasks: (_) async {},
        deleteTaskRecord: (_) async {},
      );
      addTearDown(service.dispose);
      await service.debugSeedPendingDownload(
        itemId: 'storage-regression-book',
        trackCount: 1,
      );
      await service.debugHandleTaskStatus(
        itemId: 'storage-regression-book',
        trackIndex: 0,
        status: TaskStatus.failed,
        exception: TaskFileSystemException(
          '${failure.$1}: private/path/audio.mp3',
        ),
      );

      final prefs = await SharedPreferences.getInstance();
      final serialized = prefs.getString('downloads')!;
      final restored = DownloadInfo.fromJson(
        (jsonDecode(serialized)
                as Map<String, dynamic>)['storage-regression-book']
            as Map<String, dynamic>,
      );
      expect(restored.failureReason, failure.$2);
      expect(restored.status, DownloadStatus.error);
      expect(service.activeDownloads, isEmpty);
      expect(serialized, isNot(contains('private/path')));
    });
  }

  test(
    'rejected retry preserves the failure and reports the startup error',
    () async {
      final service = DownloadService.forTesting(
        initialize: () async => throw StateError('Downloader unavailable'),
        cancelTasks: (_) async {},
        deleteTaskRecord: (_) async {},
      );
      addTearDown(service.dispose);
      await failDownload(service);
      final prefs = await SharedPreferences.getInstance();
      final savedBefore = prefs.getString('downloads');
      final api = ApiService(
        baseUrl: 'https://audiobookshelf.example',
        token: 'test-token',
        httpClient: MockClient(
          (_) async => throw StateError('Unexpected request'),
        ),
      );

      final error = await service.retryDownload(
        api: api,
        itemId: 'retry-regression-book',
      );

      expect(error, isNotNull);
      expect(service.failedDownloads.single.itemId, 'retry-regression-book');
      expect(prefs.getString('downloads'), savedBefore);
    },
  );
}
