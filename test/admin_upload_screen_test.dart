import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:absorb/l10n/app_localizations.dart';
import 'package:absorb/screens/admin_upload_screen.dart';
import 'package:absorb/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

MediaUploadFile _file(String name) => MediaUploadFile(
  name: name,
  size: 3,
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
  VoidCallback? onUploadComplete,
  Size size = const Size(1100, 900),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: ThemeData(useMaterial3: true),
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
        onUploadComplete: onUploadComplete,
        filePicker: () async => files,
        pathChecker:
            pathChecker ??
            (_, _) async => const UploadPathCheckResult(success: true),
        uploader: uploader,
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
  testWidgets(
    'unsupported files are skipped and nothing uploads before Upload',
    (tester) async {
      final requests = <MediaUploadRequest>[];
      var completedCalls = 0;
      await _render(
        tester,
        files: [
          _file('A Book.m4b'),
          _file('cover.jpg'),
          _file('protected.aax'),
        ],
        onUploadComplete: () => completedCalls++,
        uploader: (request, {onProgress}) async {
          requests.add(request);
          return const MediaUploadResult(success: true);
        },
      );
      await _tap(tester, AdminUploadScreen.chooseFilesKey);
      expect(requests, isEmpty);
      expect(find.text('A Book.m4b'), findsOneWidget);
      expect(find.text('cover.jpg'), findsOneWidget);
      expect(find.text('protected.aax'), findsNothing);
      await _clearToasts(tester);
      await tester.enterText(
        find.byKey(AdminUploadScreen.titleFieldKey),
        'A Book',
      );
      await _tap(tester, AdminUploadScreen.submitKey);
      expect(requests, hasLength(1));
      expect(requests.single.libraryId, 'books');
      expect(requests.single.folderId, 'folder');
      expect(requests.single.title, 'A Book');
      expect(requests.single.files.map((f) => f.name), [
        'A Book.m4b',
        'cover.jpg',
      ]);
      expect(completedCalls, 1);
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

  testWidgets('upload remains usable in a narrow window with large text', (
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
    await _tap(tester, AdminUploadScreen.chooseFilesKey);
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
      await _tap(tester, AdminUploadScreen.chooseFilesKey);
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
      await _tap(tester, AdminUploadScreen.chooseFilesKey);
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
        files: [_file('A Book.m4b')],
        uploader: (_, {onProgress}) async =>
            const MediaUploadResult(success: true),
      );
      expect(find.byKey(AdminUploadScreen.libraryFieldKey), findsOneWidget);
      expect(find.text('Audiobooks'), findsOneWidget);
    },
  );

  testWidgets(
    'adding to an existing book keeps its title and author when files are chosen',
    (tester) async {
      final existingItem = {
        'id': 'existing-1',
        'folderId': 'folder',
        'relPath': 'Existing Author/Existing Book',
        'media': {
          'metadata': {
            'title': 'Existing Book',
            'authorName': 'Existing Author',
          },
        },
      };
      final client = MockClient((request) async {
        final path = request.url.path;
        if (path == '/api/libraries/books/items') {
          return http.Response(
            jsonEncode({
              'results': [existingItem],
              'total': 1,
            }),
            200,
          );
        }
        if (path == '/api/items/existing-1') {
          return http.Response(jsonEncode(existingItem), 200);
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
        apiService: api,
        files: [_file('part 1.mp3'), _file('part 2.mp3')],
        uploader: (_, {onProgress}) async =>
            const MediaUploadResult(success: true),
      );

      await tester.tap(find.text('Add to an existing book'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search this library'),
        'Existing',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Existing Book'));
      await tester.pumpAndSettle();
      expect(find.text('Adding files to "Existing Book"'), findsOneWidget);
      expect(_title(tester), 'Existing Book');
      expect(_author(tester), 'Existing Author');

      await _tap(tester, AdminUploadScreen.chooseFilesKey);
      await tester.pumpAndSettle();
      expect(find.text('part 1.mp3'), findsOneWidget);
      expect(find.text('part 2.mp3'), findsOneWidget);
      expect(_title(tester), 'Existing Book');
      expect(_author(tester), 'Existing Author');
      expect(find.text('Adding files to "Existing Book"'), findsOneWidget);
      await _clearToasts(tester);
    },
  );
}
