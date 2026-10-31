import 'dart:io';

import 'package:absorb/l10n/app_localizations.dart';
import 'package:absorb/services/desktop_download_folder.dart';
import 'package:absorb/services/download_service.dart';
import 'package:absorb/utils/fork_platform.dart';
import 'package:absorb/widgets/desktop_download_folder_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Windows/Linux download folder: a plain folder the user picks, checked for
// write access. Only new downloads use it; nothing existing is moved.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l = lookupAppLocalizations(const Locale('en'));
  final defaultPicker = DesktopDownloadFolder.picker;
  final defaultLauncher = ForkPlatform.launcher;
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory tmp;
  late Directory docs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('absorb_dl_folder_');
    docs = Directory('${tmp.path}${Platform.pathSeparator}docs')..createSync();
    messenger.setMockMethodCallHandler(pathChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') return docs.path;
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    DesktopDownloadFolder.picker = defaultPicker;
    ForkPlatform.launcher = defaultLauncher;
    messenger.setMockMethodCallHandler(pathChannel, null);
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  DownloadService newService() {
    final s = DownloadService.forTesting(
      initialize: () async {},
      cancelTasks: (_) async {},
      deleteTaskRecord: (_) async {},
    );
    addTearDown(s.dispose);
    return s;
  }

  group('activeRoot', () {
    test('is used only on Windows and Linux', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(DesktopDownloadFolder.activeRoot(tmp.path), tmp.path);
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(DesktopDownloadFolder.activeRoot(tmp.path), tmp.path);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(DesktopDownloadFolder.activeRoot(tmp.path), isNull);
    });

    test('falls back to the default when nothing is picked or it is gone', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(DesktopDownloadFolder.activeRoot(null), isNull);
      expect(DesktopDownloadFolder.activeRoot('  '), isNull);
      expect(DesktopDownloadFolder.activeRoot('${tmp.path}/unplugged'), isNull);
    });
  });

  group('bookDirPath', () {
    test('puts a book under Author/Title in the picked folder', () {
      expect(
        DesktopDownloadFolder.bookDirPath(tmp.path, 'Ann/Book', 'id-1'),
        '${tmp.path}/Ann/Book',
      );
    });

    test('an empty folder of the same name is reused', () {
      Directory('${tmp.path}/Ann/Book').createSync(recursive: true);
      expect(
        DesktopDownloadFolder.bookDirPath(tmp.path, 'Ann/Book', 'id-1'),
        '${tmp.path}/Ann/Book',
      );
    });

    test('never shares a folder that already holds the user\'s own files', () {
      final own = Directory('${tmp.path}/Ann/Book')
        ..createSync(recursive: true);
      File('${own.path}/mine.m4b').writeAsStringSync('x');
      expect(
        DesktopDownloadFolder.bookDirPath(
          tmp.path,
          'Ann/Book',
          'abcdef-0123456789',
        ),
        '${tmp.path}/Ann/Book (23456789)',
      );
    });
  });

  test('isRoot ignores slashes, trailing separators and (on Windows) case', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(DesktopDownloadFolder.isRoot(r'D:\Books\', 'd:/books'), isTrue);
    expect(DesktopDownloadFolder.isRoot(r'D:\Books\Ann', r'D:\Books'), isFalse);
    expect(DesktopDownloadFolder.isRoot(r'D:\Books', null), isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(
      DesktopDownloadFolder.isRoot('/home/a/Books', '/home/a/books'),
      isFalse,
    );
  });

  test('displayPath uses backslashes on Windows only', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(
      DesktopDownloadFolder.displayPath('C:\\Users\\a/downloads'),
      r'C:\Users\a\downloads',
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(
      DesktopDownloadFolder.displayPath('/home/a/downloads'),
      '/home/a/downloads',
    );
  });

  test('isOnMissingDrive spots an unplugged Windows drive only', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    bool onlyC(String root) => root.toUpperCase() == r'C:\';
    expect(
      DesktopDownloadFolder.isOnMissingDrive(r'E:\Books\a.mp3', exists: onlyC),
      isTrue,
    );
    expect(
      DesktopDownloadFolder.isOnMissingDrive('C:/Users/a/b.mp3', exists: onlyC),
      isFalse,
    );
    expect(
      DesktopDownloadFolder.isOnMissingDrive(
        r'\\nas\share\a.mp3',
        exists: onlyC,
      ),
      isFalse,
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(
      DesktopDownloadFolder.isOnMissingDrive(r'E:\Books\a.mp3', exists: onlyC),
      isFalse,
    );
  });

  test('isWritable accepts a real folder and leaves nothing behind', () async {
    expect(await DesktopDownloadFolder.isWritable(tmp.path), isTrue);
    expect(
      tmp.listSync().map((e) => e.path),
      isNot(anyElement(contains('.absorb_write_test'))),
    );
    expect(
      await DesktopDownloadFolder.isWritable('${tmp.path}/missing'),
      isFalse,
    );
  });

  test('open hands the folder to the system as a directory URI', () async {
    Uri? opened;
    ForkPlatform.launcher = (uri) async {
      opened = uri;
      return true;
    };
    expect(await DesktopDownloadFolder.open(tmp.path), isTrue);
    expect(opened, Uri.directory(tmp.path));
  });

  group('DownloadService', () {
    test('saves and clears the picked folder', () async {
      final s = newService();
      await s.setDesktopDownloadDir(tmp.path);
      expect(s.desktopDownloadDir, tmp.path);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(DesktopDownloadFolder.prefKey), tmp.path);

      await s.setDesktopDownloadDir(null);
      expect(s.desktopDownloadDir, isNull);
      expect(prefs.getString(DesktopDownloadFolder.prefKey), isNull);
    });

    test(
      'the label on Windows is the real folder, not "App Internal Storage"',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        final s = newService();
        expect(
          await s.downloadLocationLabel,
          DesktopDownloadFolder.displayPath('${docs.path}/downloads'),
        );
        await s.setDesktopDownloadDir(tmp.path);
        expect(
          await s.downloadLocationLabel,
          DesktopDownloadFolder.displayPath(tmp.path),
        );
      },
    );

    test('Android keeps its label', () async {
      final s = newService();
      expect(await s.downloadLocationLabel, 'App Internal Storage (Default)');
    });
  });

  group('sheet', () {
    Future<void> pumpSheet(
      WidgetTester tester,
      DownloadService s,
      List<String> labels,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DesktopDownloadFolderSheet(
              service: s,
              onLabelChanged: labels.add,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    // The sheet does real file IO (the write check), so the tap and its
    // follow-up run on the real clock, then the frame is pumped.
    Future<void> tapAndWait(WidgetTester tester, String text) async {
      await tester.runAsync(() async {
        await tester.tap(find.text(text));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();
    }

    Future<void> expireToasts(WidgetTester tester) =>
        tester.pump(const Duration(seconds: 5));

    testWidgets(
      'choosing a writable folder saves it and shows the path',
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
      (tester) async {
        final s = newService();
        final labels = <String>[];
        DesktopDownloadFolder.picker =
            ({String? title, String? initialDirectory}) async => tmp.path;
        await pumpSheet(tester, s, labels);
        expect(find.text(l.desktopDownloadFolderDefault), findsOneWidget);
        expect(find.text(l.desktopDownloadFolderOpen), findsOneWidget);
        expect(find.text(l.resetToDefault), findsNothing);

        await tapAndWait(tester, l.chooseFolder);
        await expireToasts(tester);

        expect(s.desktopDownloadDir, tmp.path);
        final shown = DesktopDownloadFolder.displayPath(tmp.path);
        expect(labels, [shown]);
        expect(find.text(shown), findsOneWidget);
        expect(find.text(l.desktopDownloadFolderDefault), findsNothing);
        expect(find.text(l.resetToDefault), findsOneWidget);

        await tapAndWait(tester, l.resetToDefault);
        await expireToasts(tester);
        expect(s.desktopDownloadDir, isNull);
        expect(find.text(l.desktopDownloadFolderDefault), findsOneWidget);
      },
    );

    testWidgets(
      'a folder that cannot be written to is not saved',
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
      (tester) async {
        final s = newService();
        final labels = <String>[];
        DesktopDownloadFolder.picker =
            ({String? title, String? initialDirectory}) async =>
                '${tmp.path}/does-not-exist';
        await pumpSheet(tester, s, labels);
        await tapAndWait(tester, l.chooseFolder);
        expect(find.text(l.desktopDownloadFolderNotWritable), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        expect(s.desktopDownloadDir, isNull);
        expect(labels, isEmpty);
      },
    );

    testWidgets(
      'a cancelled or failed picker changes nothing',
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
      (tester) async {
        final s = newService();
        final labels = <String>[];
        DesktopDownloadFolder.picker =
            ({String? title, String? initialDirectory}) async => null;
        await pumpSheet(tester, s, labels);
        expect(find.text(l.desktopDownloadFolderOpenLinux), findsOneWidget);
        await tapAndWait(tester, l.chooseFolder);
        await expireToasts(tester);
        expect(s.desktopDownloadDir, isNull);

        DesktopDownloadFolder.picker =
            ({String? title, String? initialDirectory}) async =>
                throw Exception('no zenity');
        await tester.tap(find.text(l.chooseFolder));
        await tester.pump();
        await tester.pump();
        expect(find.text(l.desktopDownloadFolderPickFailed), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        expect(s.desktopDownloadDir, isNull);
        expect(labels, isEmpty);
      },
    );
  });
}
