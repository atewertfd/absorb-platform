import 'package:absorb/services/download_service.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DownloadService service;
  const book = 'telemetry-fixture';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service = DownloadService.forTesting(
      initialize: () async {},
      cancelTasks: (_) async {},
      deleteTaskRecord: (_) async {},
    );
    await service.debugSeedPendingDownload(itemId: book, trackCount: 2);
  });
  tearDown(() => service.dispose());

  void progress(int track, double fraction, int bytes, double speed) {
    service.debugHandleTaskProgress(
      itemId: book,
      trackIndex: track,
      progress: fraction,
      expectedBytes: bytes,
      speedMegabytesPerSecond: speed,
    );
  }

  test(
    'unequal chapter sizes use byte-weighted progress and combined speed',
    () {
      progress(0, .5, 10000000, 1);
      progress(1, .1, 90000000, 2);
      final info = service.getInfo(book);
      expect(info.bytesDone, 14000000);
      expect(info.bytesTotal, 100000000);
      expect(info.progress, closeTo(.14, .00001));
      expect(info.speedBytesPerSecond, 3000000);
      expect(info.etaSeconds, 29);
    },
  );

  test(
    'completed tracks stop inflating speed and ETA updates immediately',
    () async {
      progress(0, .5, 10000000, 1);
      progress(1, .1, 90000000, 2);
      await service.debugHandleTaskStatus(
        itemId: book,
        trackIndex: 0,
        status: TaskStatus.complete,
      );
      final info = service.getInfo(book);
      expect(info.bytesDone, 19000000);
      expect(info.progress, .19);
      expect(info.speedBytesPerSecond, 2000000);
      expect(info.etaSeconds, 41);
      // A delayed worker progress event cannot undo a completed chapter.
      progress(0, .6, 10000000, 9);
      expect(service.getInfo(book).bytesDone, 19000000);
      expect(service.getInfo(book).speedBytesPerSecond, 2000000);
    },
  );

  test('paused or retrying tracks discard stale transfer estimates', () async {
    progress(0, .5, 10000000, 1);
    progress(1, .1, 90000000, 2);
    await service.debugHandleTaskStatus(
      itemId: book,
      trackIndex: 0,
      status: TaskStatus.paused,
    );
    await service.debugHandleTaskStatus(
      itemId: book,
      trackIndex: 1,
      status: TaskStatus.waitingToRetry,
    );
    expect(service.getInfo(book).speedBytesPerSecond, isNull);
    expect(service.getInfo(book).etaSeconds, isNull);
    expect(service.getInfo(book).bytesDone, 14000000);
    progress(0, .5, 10000000, 9); // Late pre-pause progress must not restore speed.
    expect(service.getInfo(book).speedBytesPerSecond, isNull);
  });

  test(
    'unknown or invalid speed removes old estimates rather than retaining them',
    () {
      progress(0, .5, 10000000, 1);
      progress(1, .1, 90000000, 2);
      progress(0, .6, 10000000, -1);
      progress(1, .2, 90000000, double.infinity);
      expect(service.getInfo(book).speedBytesPerSecond, isNull);
      expect(service.getInfo(book).etaSeconds, isNull);
    },
  );

  test(
    'unknown size uses track progress but does not invent byte totals or ETA',
    () {
      progress(0, .5, 10000000, 1);
      progress(1, .1, -1, 2);
      final info = service.getInfo(book);
      expect(info.progress, closeTo(.3, .00001));
      expect(info.bytesDone, isNull);
      expect(info.bytesTotal, isNull);
      expect(info.etaSeconds, isNull);
    },
  );

  test('invalid track indexes cannot contaminate aggregates', () async {
    progress(0, .5, 10000000, 1);
    progress(1, .1, 90000000, 2);
    progress(2, .9, 999999999, 100);
    await service.debugHandleTaskStatus(
      itemId: book,
      trackIndex: -1,
      status: TaskStatus.complete,
    );
    expect(service.getInfo(book).bytesTotal, 100000000);
    expect(service.getInfo(book).speedBytesPerSecond, 3000000);
  });
}
