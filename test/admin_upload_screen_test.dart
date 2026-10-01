import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:absorb/l10n/app_localizations.dart';
import 'package:absorb/main.dart';
import 'package:absorb/screens/admin_upload_screen.dart';
import 'package:absorb/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _libraries = [
  {
    'id': 'books',
    'name': 'Audiobooks',
    'mediaType': 'book',
    'folders': [
      {'id': 'folder', 'fullPath': '/fixture-audiobooks'},
    ],
  },
];

MediaUploadFile _file(String name) =>
    MediaUploadFile(name: name, size: 3, bytes: Uint8List.fromList([1, 2, 3]));

Future<void> _render(
  WidgetTester tester, {
  required List<MediaUploadFile> files,
  required MediaUploader uploader,
  UploadPathChecker? pathChecker,
  Size size = const Size(1100, 900),
  double textScale = 1,
  ThemeData? theme,
  GlobalKey? captureKey,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: theme ?? ThemeData(useMaterial3: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: AdminUploadScreen(
          libraries: _libraries,
          filePicker: () async => files,
          pathChecker:
              pathChecker ??
              (_, _) async => const UploadPathCheckResult(success: true),
          uploader: uploader,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Key key) async {
  final target = find.byKey(key);
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pump();
}

Future<void> _clearToasts(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

String _title(WidgetTester tester) => tester
    .widget<TextFormField>(find.byKey(AdminUploadScreen.titleFieldKey))
    .controller!
    .text;

void main() {
  testWidgets('capture import screen with the production dark theme', (
    tester,
  ) async {
    const fontDir = String.fromEnvironment('FLUTTER_TEST_FONTS');
    await tester.runAsync(() async {
      final roboto = FontLoader('Roboto');
      for (final name in ['regular', 'medium', 'bold']) {
        roboto.addFont(
          File(
            '$fontDir/roboto-$name.ttf',
          ).readAsBytes().then(ByteData.sublistView),
        );
      }
      await roboto.load();
      final monospace = FontLoader('monospace')
        ..addFont(
          File(
            '$fontDir/roboto-regular.ttf',
          ).readAsBytes().then(ByteData.sublistView),
        );
      await monospace.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File(
            '$fontDir/materialicons-regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        );
      await icons.load();
    });
    late ThemeData theme;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          // Build the production theme without mounting AuthGate or starting
          // application services. This fixture never reads accounts or settings.
          final builder = const AbsorbApp().build(context) as ListenableBuilder;
          final app = builder.builder(context, null) as MaterialApp;
          theme = app.darkTheme!;
          return const SizedBox();
        },
      ),
    );
    await tester.pumpWidget(const SizedBox());
    final captureKey = GlobalKey();
    await _render(
      tester,
      files: [_file('The Example Book.m4b'), _file('cover.jpg')],
      uploader: (_, {onProgress}) async =>
          const MediaUploadResult(success: true),
      theme: theme,
      captureKey: captureKey,
    );
    await _tap(tester, AdminUploadScreen.libationGuideKey);
    await _tap(tester, AdminUploadScreen.libationFilesKey);
    await _clearToasts(tester);
    Future<void> capture(String name, Key target) async {
      await tester.ensureVisible(find.byKey(target));
      await tester.pumpAndSettle();
      final boundary =
          captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = File('build/verification/$name.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull);
    }

    await capture('import-desktop-details', AdminUploadScreen.libraryFieldKey);
    await capture('import-desktop-files', AdminUploadScreen.submitKey);
    await tester.binding.setSurfaceSize(const Size(400, 800));
    await tester.pumpAndSettle();
    await capture('import-narrow', AdminUploadScreen.libationGuideKey);
  }, skip: !const bool.fromEnvironment('IMPORT_SCREENSHOTS'));

  testWidgets(
    'export selection filters sidecars and requires explicit upload',
    (tester) async {
      final requests = <MediaUploadRequest>[];
      await _render(
        tester,
        files: [
          _file('A Book.m4b'),
          _file('cover.jpg'),
          _file('AccountsSettings.json'),
          _file('protected.aax'),
        ],
        uploader: (request, {onProgress}) async {
          requests.add(request);
          return const MediaUploadResult(success: true);
        },
      );
      await _tap(tester, AdminUploadScreen.libationGuideKey);
      await _tap(tester, AdminUploadScreen.libationFilesKey);
      expect(requests, isEmpty);
      expect(_title(tester), 'A Book');
      expect(find.text('A Book.m4b'), findsOneWidget);
      expect(find.text('cover.jpg'), findsOneWidget);
      expect(find.text('AccountsSettings.json'), findsNothing);
      expect(find.text('protected.aax'), findsNothing);
      await _clearToasts(tester);
      await _tap(tester, AdminUploadScreen.submitKey);
      expect(requests, hasLength(1));
      expect(requests.single.libraryId, 'books');
      expect(requests.single.folderId, 'folder');
      expect(requests.single.title, 'A Book');
      expect(requests.single.files.map((f) => f.name), [
        'A Book.m4b',
        'cover.jpg',
      ]);
      expect(_title(tester), isEmpty);
      await _clearToasts(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'existing destination prevents upload and retains selected files',
    (tester) async {
      var uploads = 0;
      await _render(
        tester,
        files: [_file('A Book.m4b')],
        pathChecker: (directory, folder) async {
          expect(directory, 'A Book');
          expect(folder, '/fixture-audiobooks');
          return const UploadPathCheckResult(success: true, exists: true);
        },
        uploader: (_, {onProgress}) async {
          uploads++;
          return const MediaUploadResult(success: true);
        },
      );
      await _tap(tester, AdminUploadScreen.chooseFilesKey);
      await _tap(tester, AdminUploadScreen.submitKey);
      expect(uploads, 0);
      expect(find.text('A Book.m4b'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(AdminUploadScreen.submitKey))
            .onPressed,
        isNotNull,
      );
      await _clearToasts(tester);
    },
  );

  testWidgets('thrown path check releases busy state and permits retry', (
    tester,
  ) async {
    var checks = 0;
    var uploads = 0;
    await _render(
      tester,
      files: [_file('A Book.m4b')],
      pathChecker: (_, _) async {
        if (++checks == 1) throw StateError('fixture failure');
        return const UploadPathCheckResult(success: true);
      },
      uploader: (_, {onProgress}) async {
        uploads++;
        return const MediaUploadResult(success: true);
      },
    );
    await _tap(tester, AdminUploadScreen.chooseFilesKey);
    await _tap(tester, AdminUploadScreen.submitKey);
    expect(find.text('A Book.m4b'), findsOneWidget);
    await _clearToasts(tester);
    await _tap(tester, AdminUploadScreen.submitKey);
    expect(checks, 2);
    expect(uploads, 1);
    await _clearToasts(tester);
    expect(tester.takeException(), isNull);
  });

  for (final streamOnly in [false, true]) {
    testWidgets('thrown upload handles reselection (streamOnly=$streamOnly)', (
      tester,
    ) async {
      await _render(
        tester,
        files: [
          if (streamOnly)
            MediaUploadFile(
              name: 'A Book.m4b',
              size: 3,
              readStream: Stream.value([1, 2, 3]),
            )
          else
            _file('A Book.m4b'),
        ],
        uploader: (_, {onProgress}) async =>
            throw StateError('fixture failure'),
      );
      await _tap(tester, AdminUploadScreen.chooseFilesKey);
      await _tap(tester, AdminUploadScreen.submitKey);
      expect(
        find.text('A Book.m4b'),
        streamOnly ? findsNothing : findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(AdminUploadScreen.submitKey))
            .onPressed,
        isNotNull,
      );
      await _clearToasts(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'pending path validation blocks duplicate submissions and editing',
    (tester) async {
      final check = Completer<UploadPathCheckResult>();
      var checks = 0;
      var uploads = 0;
      await _render(
        tester,
        files: [_file('A Book.m4b')],
        pathChecker: (_, _) {
          checks++;
          return check.future;
        },
        uploader: (_, {onProgress}) async {
          uploads++;
          return const MediaUploadResult(success: true);
        },
      );
      await _tap(tester, AdminUploadScreen.chooseFilesKey);
      await tester.ensureVisible(find.byKey(AdminUploadScreen.submitKey));
      await tester.pumpAndSettle();
      final submit = tester
          .widget<FilledButton>(find.byKey(AdminUploadScreen.submitKey))
          .onPressed!;
      submit();
      submit(); // Exercise stale callbacks before Flutter has rebuilt.
      await tester.pump();
      expect(checks, 1);
      expect(uploads, 0);
      expect(
        tester
            .widget<FilledButton>(find.byKey(AdminUploadScreen.submitKey))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(AdminUploadScreen.titleFieldKey))
            .enabled,
        isFalse,
      );
      check.complete(const UploadPathCheckResult(success: true));
      await tester.pump();
      expect(uploads, 1);
      await _clearToasts(tester);
    },
  );

  testWidgets('import remains usable in a narrow window with large text', (
    tester,
  ) async {
    await _render(
      tester,
      size: const Size(400, 800),
      textScale: 1.8,
      files: [_file('A Book.m4b')],
      uploader: (_, {onProgress}) async =>
          const MediaUploadResult(success: true),
    );
    await _tap(tester, AdminUploadScreen.libationGuideKey);
    await _tap(tester, AdminUploadScreen.libationFilesKey);
    expect(_title(tester), 'A Book');
    expect(tester.takeException(), isNull);
    await _tap(tester, AdminUploadScreen.submitKey);
    await _clearToasts(tester);
    expect(tester.takeException(), isNull);
  });
}
