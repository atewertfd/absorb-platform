import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:absorb/l10n/app_localizations.dart';
import 'package:absorb/main.dart';
import 'package:absorb/screens/admin_upload_screen.dart';
import 'package:absorb/services/api_service.dart';
import 'package:absorb/services/libation_import_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

MediaUploadFile _file(String name, {String? path}) => MediaUploadFile(
  name: name,
  size: 3,
  path: path,
  bytes: Uint8List.fromList([1, 2, 3]),
);

Future<void> _render(
  WidgetTester tester, {
  List<dynamic> libraries = _libraries,
  required List<MediaUploadFile> files,
  required MediaUploader uploader,
  UploadPathChecker? pathChecker,
  ApiService? apiService,
  bool canUpload = true,
  bool initialLibationExpanded = false,
  VoidCallback? onUploadComplete,
  UploadDirectoryPicker? directoryPicker,
  UploadExecutablePicker? executablePicker,
  LibationDirectoryScanner? directoryScanner,
  LibationExecutableLauncher? executableLauncher,
  bool? showDesktopLibationControls,
  LibrarySearcher? librarySearcher,
  DateTime Function()? clock,
  Map<String, Object> prefs = const <String, Object>{},
  Size size = const Size(1100, 900),
  double textScale = 1,
  ThemeData? theme,
  GlobalKey? captureKey,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
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
          libraries: libraries,
          apiService: apiService,
          canUpload: canUpload,
          initialLibationExpanded: initialLibationExpanded,
          onUploadComplete: onUploadComplete,
          filePicker: () async => files,
          directoryPicker: directoryPicker,
          executablePicker: executablePicker,
          directoryScanner: directoryScanner,
          executableLauncher: executableLauncher,
          showDesktopLibationControls: showDesktopLibationControls,
          librarySearcher: librarySearcher,
          clock: clock,
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

String _author(WidgetTester tester) => tester
    .widget<TextFormField>(find.byKey(AdminUploadScreen.authorFieldKey))
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
    'existing destination asks first; cancel keeps files, Add files uploads',
    (tester) async {
      var uploads = 0;
      await _render(
        tester,
        files: [_file('A Book.m4b')],
        pathChecker: (directory, folder) async {
          expect(directory, 'A Book');
          expect(folder, '/fixture-audiobooks');
          return const UploadPathCheckResult(
            success: true,
            exists: true,
            libraryItemTitle: 'A Book',
          );
        },
        uploader: (_, {onProgress}) async {
          uploads++;
          return const MediaUploadResult(success: true);
        },
      );
      await _tap(tester, AdminUploadScreen.chooseFilesKey);
      await _tap(tester, AdminUploadScreen.submitKey);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Folder already exists'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(uploads, 0);
      expect(find.text('A Book.m4b'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(AdminUploadScreen.submitKey))
            .onPressed,
        isNotNull,
      );

      await _tap(tester, AdminUploadScreen.submitKey);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Add files'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(uploads, 1);
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

  testWidgets(
    'non-admin without upload permission sees banner and clear error on submit',
    (tester) async {
      var uploads = 0;
      await _render(
        tester,
        canUpload: false,
        initialLibationExpanded: true,
        files: [_file('A Book.m4b')],
        uploader: (_, {onProgress}) async {
          uploads++;
          return const MediaUploadResult(success: true);
        },
      );
      expect(find.byKey(AdminUploadScreen.permissionBannerKey), findsOneWidget);
      expect(
        find.textContaining('does not have upload permission'),
        findsOneWidget,
      );
      await _tap(tester, AdminUploadScreen.libationFilesKey);
      await _tap(tester, AdminUploadScreen.submitKey);
      expect(uploads, 0);
      await _clearToasts(tester);
    },
  );

  testWidgets(
    'HTTP 403 permission failure on path check or upload shows clear permission message',
    (tester) async {
      var pathForbidden = true;
      await _render(
        tester,
        initialLibationExpanded: true,
        files: [_file('A Book.m4b')],
        pathChecker: (_, _) async => pathForbidden
            ? const UploadPathCheckResult(
                success: false,
                statusCode: 403,
                error: 'Forbidden',
              )
            : const UploadPathCheckResult(success: true, statusCode: 200),
        uploader: (_, {onProgress}) async => const MediaUploadResult(
          success: false,
          statusCode: 403,
          error: 'Forbidden',
        ),
      );
      await _tap(tester, AdminUploadScreen.libationFilesKey);
      await _tap(tester, AdminUploadScreen.submitKey);
      expect(
        find.textContaining('does not have upload permission'),
        findsOneWidget,
      );
      await _clearToasts(tester);

      pathForbidden = false;
      await _tap(tester, AdminUploadScreen.submitKey);
      expect(
        find.textContaining('does not have upload permission'),
        findsOneWidget,
      );
      await _clearToasts(tester);
    },
  );

  testWidgets(
    'loads libraries from ApiService when opened before LibraryProvider is populated',
    (tester) async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/libraries') {
          return http.Response(jsonEncode({'libraries': _libraries}), 200);
        }
        return http.Response('{}', 200);
      });
      addTearDown(client.close);
      final api = ApiService(
        baseUrl: 'https://example.invalid',
        token: 'fake',
        httpClient: client,
      );
      await _render(
        tester,
        libraries: const [],
        apiService: api,
        initialLibationExpanded: true,
        files: [_file('A Book.m4b')],
        uploader: (_, {onProgress}) async =>
            const MediaUploadResult(success: true),
      );
      expect(find.byKey(AdminUploadScreen.libraryFieldKey), findsOneWidget);
      expect(find.text('Audiobooks'), findsOneWidget);
    },
  );

  testWidgets(
    'folder import and multi-book output scan populate details and require explicit upload',
    (tester) async {
      final uploaded = <MediaUploadRequest>[];
      var completedCalls = 0;
      await _render(
        tester,
        initialLibationExpanded: true,
        showDesktopLibationControls: true,
        files: const [],
        onUploadComplete: () => completedCalls++,
        directoryPicker: () async => '/exports/LibationBooks',
        directoryScanner: (dir) async {
          expect(dir, '/exports/LibationBooks');
          return [
            LibationBookCandidate(
              directoryPath: '/exports/LibationBooks/Author One/Book Alpha',
              title: 'Book Alpha',
              author: 'Author One',
              files: [_file('01.mp3'), _file('02.mp3'), _file('cover.jpg')],
              skippedFilesCount: 1,
            ),
            LibationBookCandidate(
              directoryPath: '/exports/LibationBooks/Author Two/Book Beta',
              title: 'Book Beta',
              author: 'Author Two',
              files: [_file('Book Beta.m4b')],
            ),
          ];
        },
        uploader: (request, {onProgress}) async {
          uploaded.add(request);
          return const MediaUploadResult(success: true, statusCode: 200);
        },
      );

      await _tap(tester, AdminUploadScreen.libationFolderKey);
      await tester.pumpAndSettle();
      expect(find.text('Choose exported audiobook'), findsOneWidget);
      expect(find.text('Book Alpha'), findsOneWidget);
      expect(find.text('Book Beta'), findsOneWidget);

      await tester.tap(find.text('Book Alpha'));
      await tester.pumpAndSettle();
      await _clearToasts(tester);

      expect(uploaded, isEmpty);
      expect(_title(tester), 'Book Alpha');
      expect(_author(tester), 'Author One');
      expect(find.text('01.mp3'), findsOneWidget);
      expect(find.text('02.mp3'), findsOneWidget);
      expect(find.text('cover.jpg'), findsOneWidget);

      await _tap(tester, AdminUploadScreen.submitKey);
      expect(uploaded, hasLength(1));
      expect(uploaded.single.title, 'Book Alpha');
      expect(uploaded.single.author, 'Author One');
      expect(completedCalls, 1);
      await _clearToasts(tester);
    },
  );

  testWidgets(
    'choosing another scanned book replaces the auto-filled author only',
    (tester) async {
      final candidates = [
        LibationBookCandidate(
          directoryPath: '/exports/Author One/Book Alpha',
          title: 'Book Alpha',
          author: 'Author One',
          files: [_file('Book Alpha.m4b')],
        ),
        LibationBookCandidate(
          directoryPath: '/exports/Book Beta',
          title: 'Book Beta',
          files: [_file('Book Beta.m4b')],
        ),
      ];
      await _render(
        tester,
        initialLibationExpanded: true,
        files: const [],
        directoryPicker: () async => '/exports',
        directoryScanner: (_) async => candidates,
        uploader: (_, {onProgress}) async =>
            const MediaUploadResult(success: true),
      );

      Future<void> choose(String title) async {
        await _tap(tester, AdminUploadScreen.libationFolderKey);
        await tester.pumpAndSettle();
        await tester.tap(find.text(title).last);
        await tester.pumpAndSettle();
      }

      await choose('Book Alpha');
      expect(_author(tester), 'Author One');

      await choose('Book Beta');
      expect(_title(tester), 'Book Beta');
      expect(_author(tester), isEmpty);

      await tester.enterText(
        find.byKey(AdminUploadScreen.authorFieldKey),
        'Typed Author',
      );
      await choose('Book Alpha');
      expect(_title(tester), 'Book Alpha');
      expect(_author(tester), 'Typed Author');
      await _clearToasts(tester);
    },
  );

  testWidgets('a failing folder scan reports an error and stays usable', (
    tester,
  ) async {
    final scan = Completer<List<LibationBookCandidate>>();
    await _render(
      tester,
      initialLibationExpanded: true,
      files: const [],
      directoryPicker: () async => '/exports',
      directoryScanner: (_) => scan.future,
      uploader: (_, {onProgress}) async =>
          const MediaUploadResult(success: true),
    );

    await _tap(tester, AdminUploadScreen.libationFolderKey);
    await tester.pump();
    expect(
      find.byKey(AdminUploadScreen.libationScanProgressKey),
      findsOneWidget,
    );
    ButtonStyleButton button(Key key) =>
        tester.widget<ButtonStyleButton>(find.byKey(key));
    expect(button(AdminUploadScreen.libationFolderKey).onPressed, isNull);
    expect(button(AdminUploadScreen.submitKey).onPressed, isNull);

    scan.completeError(const FileSystemException('denied'));
    await tester.pumpAndSettle();
    expect(find.byKey(AdminUploadScreen.libationScanProgressKey), findsNothing);
    expect(find.text("Couldn't open the selected files."), findsWidgets);
    expect(button(AdminUploadScreen.libationFolderKey).onPressed, isNotNull);
    await _clearToasts(tester);
  });

  testWidgets(
    'explicit Libation launcher configures and launches user-selected executable',
    (tester) async {
      final launched = <String>[];
      await _render(
        tester,
        initialLibationExpanded: true,
        showDesktopLibationControls: true,
        files: const [],
        executablePicker: () async => r'C:\Libation\Libation.exe',
        executableLauncher: (path) async {
          launched.add(path);
          return true;
        },
        uploader: (_, {onProgress}) async =>
            const MediaUploadResult(success: true),
      );
      expect(launched, isEmpty);
      await _tap(tester, AdminUploadScreen.libationLaunchKey);
      await tester.pumpAndSettle();
      expect(launched, [r'C:\Libation\Libation.exe']);
    },
  );

  group('Libation download tracking', () {
    final now = DateTime(2026, 10, 29, 12);
    LibationBookCandidate book(String title, DateTime modified) =>
        LibationBookCandidate(
          directoryPath: '/out/$title [B0${title.length}ABCDEFG]',
          title: title,
          files: [_file('$title.m4b')],
          modified: modified,
        );

    testWidgets(
      'offers new downloads, tags them in the picker, and records the upload',
      (tester) async {
        final scans = <String>[];
        final candidates = [
          book('Fresh Book', now.subtract(const Duration(hours: 2))),
          book('Old Book', now.subtract(const Duration(days: 40))),
          book('Uploaded Book', now.subtract(const Duration(hours: 5))),
        ];
        final uploaded = <MediaUploadRequest>[];
        await _render(
          tester,
          showDesktopLibationControls: true,
          files: const [],
          clock: () => now,
          prefs: {
            kLibationOutputFolderPref: '/out',
            kLibationImportedFoldersPref: [
              libationFolderKey(candidates[2].directoryPath),
            ],
          },
          directoryScanner: (dir) async {
            scans.add(dir);
            return candidates;
          },
          uploader: (request, {onProgress}) async {
            uploaded.add(request);
            return const MediaUploadResult(success: true, statusCode: 200);
          },
        );

        // Only the recent, not-yet-imported export counts as new, and the
        // collapsed card's subtitle says so.
        expect(scans, ['/out']);
        expect(
          find.text('1 new Libation download ready to import'),
          findsOneWidget,
        );

        await tester.tap(find.byKey(AdminUploadScreen.libationGuideKey));
        await tester.pumpAndSettle();
        await _tap(tester, AdminUploadScreen.libationReviewNewKey);
        await tester.pumpAndSettle();
        expect(find.textContaining('New · '), findsOneWidget);
        expect(find.textContaining('Imported · '), findsOneWidget);

        await tester.tap(find.text('Fresh Book'));
        await tester.pumpAndSettle();
        await _clearToasts(tester);
        expect(
          find.text('1 new Libation download ready to import'),
          findsNothing,
        );
        expect(uploaded, isEmpty);

        await _tap(tester, AdminUploadScreen.submitKey);
        await tester.pumpAndSettle();
        expect(uploaded.single.title, 'Fresh Book');
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getStringList(kLibationImportedFoldersPref),
          contains(libationFolderKey(candidates[0].directoryPath)),
        );
        expect(prefs.getInt(kLibationLastSeenExportPref), isNotNull);
        await _clearToasts(tester);
      },
    );

    testWidgets('picker search filters a long export list', (tester) async {
      final candidates = [
        for (var i = 0; i < 10; i++)
          book('Book $i', now.subtract(Duration(days: i))),
        book('Project Hail Mary', now.subtract(const Duration(days: 20))),
      ];
      await _render(
        tester,
        initialLibationExpanded: true,
        files: const [],
        clock: () => now,
        directoryPicker: () async => '/out',
        directoryScanner: (_) async => candidates,
        uploader: (_, {onProgress}) async =>
            const MediaUploadResult(success: true),
      );
      await _tap(tester, AdminUploadScreen.libationFolderKey);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(AdminUploadScreen.libationPickerSearchKey),
        'hail',
      );
      await tester.pumpAndSettle();
      expect(find.text('Project Hail Mary'), findsOneWidget);
      expect(find.text('Book 1'), findsNothing);

      await tester.enterText(
        find.byKey(AdminUploadScreen.libationPickerSearchKey),
        'zzz',
      );
      await tester.pumpAndSettle();
      expect(find.text('No exported books match your search.'), findsOneWidget);
    });

    testWidgets('warns without blocking when the library has the book', (
      tester,
    ) async {
      final searches = <String>[];
      final uploaded = <MediaUploadRequest>[];
      await _render(
        tester,
        initialLibationExpanded: true,
        files: const [],
        directoryPicker: () async => '/out/Project Hail Mary [B08G9PRS1K]',
        directoryScanner: (_) async => [
          LibationBookCandidate(
            directoryPath: '/out/Project Hail Mary [B08G9PRS1K]',
            title: 'Project Hail Mary',
            files: [_file('Project Hail Mary [B08G9PRS1K].m4b')],
          ),
        ],
        librarySearcher: (libraryId, query) async {
          searches.add('$libraryId:$query');
          return {
            'book': [
              {
                'libraryItem': {
                  'media': {
                    'metadata': {
                      'title': 'Project Hail Mary: A Novel',
                      'asin': 'B08G9PRS1K',
                    },
                  },
                },
              },
            ],
          };
        },
        uploader: (request, {onProgress}) async {
          uploaded.add(request);
          return const MediaUploadResult(success: true);
        },
      );

      await _tap(tester, AdminUploadScreen.libationFolderKey);
      await tester.pumpAndSettle();
      expect(searches, ['books:Project Hail Mary']);
      expect(
        find.byKey(AdminUploadScreen.libationDuplicateWarningKey),
        findsOneWidget,
      );
      expect(
        find.textContaining('"Project Hail Mary: A Novel" is already'),
        findsOneWidget,
      );

      await _tap(tester, AdminUploadScreen.submitKey);
      await tester.pumpAndSettle();
      expect(uploaded, hasLength(1));
      expect(
        find.byKey(AdminUploadScreen.libationDuplicateWarningKey),
        findsNothing,
      );
      await _clearToasts(tester);
    });
  });
}
