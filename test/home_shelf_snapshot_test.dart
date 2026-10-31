import 'dart:io';

import 'package:absorb/services/home_shelf_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late HomeShelfSnapshot snapshots;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('home_snapshot_test');
    snapshots = HomeShelfSnapshot(baseDirectory: () async => dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  final shelves = [
    {
      'id': 'continue-listening',
      'entities': [
        {'id': 'li-1', 'updatedAt': 5},
      ],
    },
  ];

  test('saved shelves come back for the same account and library', () async {
    await snapshots.save('server_a', 'lib-1', shelves);
    expect(await snapshots.load('server_a', 'lib-1'), shelves);
  });

  test('another account or library sees nothing', () async {
    await snapshots.save('server_a', 'lib-1', shelves);
    expect(await snapshots.load('server_b', 'lib-1'), isNull);
    expect(await snapshots.load('server_a', 'lib-2'), isNull);
  });

  test('a stale or broken snapshot is ignored', () async {
    await snapshots.save('server_a', 'lib-1', shelves);
    final file = dir
        .listSync(recursive: true)
        .whereType<File>()
        .single;
    file.setLastModifiedSync(DateTime.now()
        .subtract(HomeShelfSnapshot.maxAge + const Duration(hours: 1)));
    expect(await snapshots.load('server_a', 'lib-1'), isNull);

    file.writeAsStringSync('{not json');
    expect(await snapshots.load('server_a', 'lib-1'), isNull);
  });
}
