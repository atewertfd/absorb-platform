// Overflow sweep: pumps the real screens, sheets and dialogs with fake data
// full of deliberately long strings, at phone, tablet and desktop window
// sizes, text scales and both brightnesses, and fails on any layout error
// (RenderFlex overflow, unbounded constraints, a box that never laid out...).
//
// Text is measured with Roboto from the Flutter SDK's own font cache instead
// of the square test font, so a failure here is a real overflow, not an
// artifact of placeholder glyph widths. No server is contacted: the API
// client is an in-memory MockClient serving fixtures.
import 'dart:convert';
import 'dart:io';

import 'package:absorb/l10n/app_localizations.dart';
import 'package:absorb/main.dart' show rootNavigatorKey;
import 'package:absorb/providers/auth_provider.dart';
import 'package:absorb/providers/library_provider.dart';
import 'package:absorb/screens/absorbing_screen.dart';
import 'package:absorb/screens/achievements_screen.dart';
import 'package:absorb/screens/bookmarks_screen.dart';
import 'package:absorb/screens/downloads_screen.dart';
import 'package:absorb/screens/app_shell.dart';
import 'package:absorb/screens/home_screen.dart';
import 'package:absorb/screens/library_screen.dart';
import 'package:absorb/screens/settings_screen.dart';
import 'package:absorb/screens/stats_screen.dart';
import 'package:absorb/services/api_service.dart';
import 'package:absorb/services/wording.dart';
import 'package:absorb/services/whats_new_notes.dart';
import 'package:absorb/ui_themes/frosted.dart';
import 'package:absorb/ui_themes/ui_theme.dart';
import 'package:absorb/ui_themes/ui_theme_picker.dart';
import 'package:absorb/widgets/absorbing_card.dart';
import 'package:absorb/widgets/book_detail_sheet.dart';
import 'package:absorb/widgets/collapsible_section.dart';
import 'package:absorb/widgets/welcome_sheet.dart';
import 'package:absorb/widgets/whats_new_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Window sizes, scales, brightness ─────────────────────────────────────

class _Combo {
  const _Combo(this.size, this.scale, this.brightness);
  final Size size;
  final double scale;
  final Brightness brightness;

  @override
  String toString() =>
      '${size.width.toInt()}x${size.height.toInt()} '
      '@${scale}x ${brightness.name}';
}

const _phoneSmall = Size(360, 640);
const _phone = Size(390, 844);
const _tablet = Size(768, 1024);
const _laptopSmall = Size(1024, 640);
const _laptop = Size(1280, 800);
const _desktop = Size(1920, 1080);

/// Every size at 1.0 and 1.3, light and dark alternating so both show up
/// without doubling the run; 2.0 on the small phone.
List<_Combo> _fullMatrix() => [
  for (final (i, size) in const [
    _phoneSmall,
    _phone,
    _tablet,
    _laptopSmall,
    _laptop,
    _desktop,
  ].indexed) ...[
    _Combo(size, 1.0, i.isEven ? Brightness.light : Brightness.dark),
    _Combo(size, 1.3, i.isEven ? Brightness.dark : Brightness.light),
  ],
  const _Combo(_phoneSmall, 2.0, Brightness.light),
];

/// For dialogs and sheets whose layout only depends on the shortest side.
List<_Combo> _compactMatrix() => const [
  _Combo(_phoneSmall, 1.0, Brightness.light),
  _Combo(_phoneSmall, 1.3, Brightness.dark),
  _Combo(_phoneSmall, 2.0, Brightness.light),
  _Combo(_phone, 1.3, Brightness.light),
  _Combo(_tablet, 1.3, Brightness.dark),
  _Combo(_laptopSmall, 1.0, Brightness.dark),
  _Combo(_laptopSmall, 1.3, Brightness.light),
  _Combo(_desktop, 1.0, Brightness.light),
];

// ── Fixture data ─────────────────────────────────────────────────────────

/// `--dart-define=SWEEP_VERBOSE=true` prints each combo's time and every
/// error in full.
const _verbose = bool.fromEnvironment('SWEEP_VERBOSE');

const _libId = 'lib-1';
final _noSpaces = 'Unbelievablyuninterruptedtitlewithoutanyspaces' * 3;
const _withSpaces =
    'The Extraordinarily Long and Winding Chronicle of a Reluctant '
    'Cartographer Who Mapped Every Forgotten Road in the Northern Kingdoms';
const _seriesName =
    'The Unnecessarily Elaborate Saga of the Northern Kingdoms and Their '
    'Many Feuding Houses';
const _authors = [
  'Bartholomew Montgomery-Fitzwilliam',
  'Anastasia Konstantinovna Rimsky-Korsakova',
  'Jean-Baptiste Emmanuel Zorg de la Fontaine',
  'Maximilian Alexander von Hohenzollern-Sigmaringen',
];
const _narrators = [
  'Wolfgang Amadeus Schwarzenegger-Leutheusser',
  'Persephone Evangeline Worthington-Smythe',
  'Rumpelstiltskin Gesamtausgabe Vorleser',
];
const _chapterTitle =
    'Chapter Forty-Two: In Which the Cartographer Discovers That the Road '
    'Was Never There at All';

Map<String, dynamic> _book(int i) {
  final title = i.isEven ? _withSpaces : _noSpaces;
  final chapters = [
    for (var c = 0; c < 8; c++)
      {
        'id': c,
        'start': c * 600.0,
        'end': (c + 1) * 600.0,
        'title': '$_chapterTitle $c',
      },
  ];
  return {
    'id': 'li-$i',
    'ino': '$i',
    'libraryId': _libId,
    'folderId': 'f1',
    'path': '/audiobooks/$title',
    'mediaType': 'book',
    'addedAt': 1700000000000 + i,
    'updatedAt': 1700000000000 + i,
    'isMissing': false,
    'isInvalid': false,
    'numFiles': 3,
    'size': 123456789,
    'media': {
      'id': 'm-$i',
      'coverPath': null,
      'tags': ['Überlange-Schlagwort-Sammlung', 'Another tag that goes on'],
      'numTracks': 3,
      'numAudioFiles': 3,
      'numChapters': chapters.length,
      'duration': 4800.0 + i,
      'size': 123456789,
      'chapters': chapters,
      'audioFiles': const [],
      'tracks': const [],
      'ebookFile': null,
      'ebookFormat': null,
      'metadata': {
        'title': '$title $i',
        'titleIgnorePrefix': '$title $i',
        'subtitle':
            'A Subtitle That Also Refuses To Be Short Under Any Circumstances',
        'authorName': _authors.join(', '),
        'authorNameLF': _authors.join(', '),
        'authors': [
          for (final (n, a) in _authors.indexed) {'id': 'au-$n', 'name': a},
        ],
        'narratorName': _narrators.join(', '),
        'narrators': _narrators,
        'seriesName': '$_seriesName #12.5',
        'series': [
          {'id': 'se-1', 'name': _seriesName, 'sequence': '12.5'},
        ],
        'genres': ['Historische Abenteuerliteratur', 'Speculative Fiction'],
        'publishedYear': '2021',
        'publisher': 'Hyperextended Publishing House of Very Long Names Ltd.',
        'description': '<p>$_withSpaces. ${_withSpaces * 3}</p>',
        'language': 'English',
        'explicit': false,
        'abridged': false,
        'isbn': '9780000000000',
        'asin': 'B000000000',
      },
    },
    'userMediaProgress': {
      'id': 'p-$i',
      'libraryItemId': 'li-$i',
      'duration': 4800.0,
      'progress': 0.42,
      'currentTime': 2016.0,
      'isFinished': false,
      'lastUpdate': 1700000000000,
      'startedAt': 1690000000000,
    },
  };
}

final _books = [for (var i = 0; i < 8; i++) _book(i)];

Map<String, dynamic> _seriesEntity() => {
  'id': 'se-1',
  'name': _seriesName,
  'nameIgnorePrefix': _seriesName,
  'addedAt': 1700000000000,
  'books': _books.take(4).toList(),
  'type': 'series',
};

Map<String, dynamic> _authorEntity(int n) => {
  'id': 'au-$n',
  'name': _authors[n % _authors.length],
  'numBooks': 12,
  'imagePath': null,
  'addedAt': 1700000000000,
  'updatedAt': 1700000000000,
};

final _sections = <Map<String, dynamic>>[
  {
    'id': 'continue-listening',
    'label': 'Continue Listening',
    'labelStringKey': 'LabelContinueListening',
    'type': 'book',
    'entities': _books.take(4).toList(),
    'total': 4,
  },
  {
    'id': 'continue-series',
    'label': 'Continue Series',
    'labelStringKey': 'LabelContinueSeries',
    'type': 'book',
    'entities': _books.skip(4).toList(),
    'total': 4,
  },
  {
    'id': 'recently-added',
    'label': 'Recently Added',
    'labelStringKey': 'LabelRecentlyAdded',
    'type': 'book',
    'entities': _books,
    'total': _books.length,
  },
  {
    'id': 'recent-series',
    'label': 'Recent Series',
    'labelStringKey': 'LabelRecentSeries',
    'type': 'series',
    'entities': [_seriesEntity()],
    'total': 1,
  },
  {
    'id': 'newest-authors',
    'label': 'Newest Authors',
    'labelStringKey': 'LabelNewestAuthors',
    'type': 'authors',
    'entities': [for (var n = 0; n < 4; n++) _authorEntity(n)],
    'total': 4,
  },
];

final _library = <String, dynamic>{
  'id': _libId,
  'name': 'Hörbücher und Hörspiele der gesamten Familie (Archiv)',
  'mediaType': 'book',
  'icon': 'audiobookshelf',
  'displayOrder': 1,
  'settings': {},
};

Map<String, dynamic> _stats() {
  final now = DateTime.now();
  String day(int back) {
    final d = now.subtract(Duration(days: back));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  return {
    'totalTime': 987654.0,
    'items': {
      for (final b in _books)
        b['id']: {
          'id': b['id'],
          'timeListening': 12345.0,
          'mediaMetadata': (b['media'] as Map)['metadata'],
        },
    },
    'days': {for (var i = 0; i < 60; i++) day(i): 3600.0 + i * 120},
    'dayOfWeek': {
      'Monday': 36000.0,
      'Tuesday': 7200.0,
      'Wednesday': 18000.0,
      'Thursday': 3600.0,
      'Friday': 50000.0,
      'Saturday': 99999.0,
      'Sunday': 12000.0,
    },
    'today': 4567.0,
    'recentSessions': [for (var i = 0; i < 5; i++) _session(i)],
  };
}

Map<String, dynamic> _session(int i) {
  final b = _books[i % _books.length];
  return {
    'id': 'ses-$i',
    'userId': 'u1',
    'libraryId': _libId,
    'libraryItemId': b['id'],
    'mediaType': 'book',
    'mediaMetadata': (b['media'] as Map)['metadata'],
    'displayTitle': ((b['media'] as Map)['metadata'] as Map)['title'],
    'displayAuthor': _authors.join(', '),
    'duration': 4800.0,
    'playMethod': 0,
    'mediaPlayer': 'Absorb Plus with an unusually long player name',
    'deviceInfo': {
      'deviceName': 'Extremely Long Device Name Belonging To Somebody',
      'clientName': 'Absorb Plus',
      'osName': 'Windows',
    },
    'timeListening': 3600.0 + i,
    'startTime': 0.0,
    'currentTime': 3600.0,
    'startedAt': DateTime.now().millisecondsSinceEpoch - i * 86400000,
    'updatedAt': DateTime.now().millisecondsSinceEpoch - i * 86400000 + 3600000,
    'date': '2026-10-${(28 - i).toString().padLeft(2, '0')}',
    'dayOfWeek': 'Wednesday',
  };
}

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<http.Response> _fakeServer(http.Request request) async {
  final path = request.url.path;
  if (path.startsWith('/api/items/')) {
    final id = path.split('/')[3];
    return _json(
      _books.firstWhere((b) => b['id'] == id, orElse: () => _books.first),
    );
  }
  if (path == '/api/libraries/$_libId/items') {
    return _json({
      'results': _books,
      'total': _books.length,
      'limit': 50,
      'page': 0,
    });
  }
  if (path == '/api/libraries/$_libId/series') {
    return _json({
      'results': [_seriesEntity()],
      'total': 1,
      'limit': 50,
      'page': 0,
    });
  }
  if (path == '/api/libraries/$_libId/authors') {
    return _json({
      'authors': [for (var n = 0; n < 8; n++) _authorEntity(n)],
      'total': 8,
    });
  }
  if (path == '/api/me/listening-stats') return _json(_stats());
  if (path == '/api/me/listening-sessions') {
    return _json({
      'sessions': [for (var i = 0; i < 10; i++) _session(i)],
      'total': 10,
      'numPages': 1,
      'page': 0,
      'itemsPerPage': 20,
    });
  }
  if (path == '/api/libraries/$_libId' &&
      request.url.queryParameters['include'] == 'filterdata') {
    return _json({
      ..._library,
      'filterdata': {
        'authors': [for (var n = 0; n < 4; n++) _authorEntity(n)],
        'genres': ['Historische Abenteuerliteratur', 'Speculative Fiction'],
        'tags': ['Überlange-Schlagwort-Sammlung'],
        'series': [_seriesEntity()],
        'narrators': _narrators,
        'languages': ['English'],
        'publishers': [
          'Hyperextended Publishing House of Very Long Names Ltd.',
        ],
      },
    });
  }
  if (path == '/api/libraries/$_libId/narrators') {
    return _json({
      'narrators': [
        for (final n in _narrators) {'id': n, 'name': n, 'numBooks': 1234},
      ],
    });
  }
  if (path == '/api/libraries/$_libId/playlists') {
    return _json({
      'results': [
        {
          'id': 'pl-1',
          'name': 'My playlist: $_withSpaces',
          'libraryId': _libId,
          'items': [
            for (final b in _books.take(3))
              {'libraryItemId': b['id'], 'libraryItem': b},
          ],
        },
      ],
      'total': 1,
    });
  }
  if (path == '/api/libraries/$_libId/collections') {
    return _json({
      'results': [
        {
          'id': 'co-1',
          'name': 'Collection: $_noSpaces',
          'libraryId': _libId,
          'books': _books.take(4).toList(),
        },
      ],
      'total': 1,
    });
  }
  if (path == '/api/libraries')
    return _json({
      'libraries': [_library],
    });
  return http.Response('{}', 404);
}

// ── Fakes ────────────────────────────────────────────────────────────────

class _FakeAuth extends AuthProvider {
  final ApiService _api = ApiService(
    baseUrl: 'http://abs.test',
    token: 'test-token',
    httpClient: MockClient(_fakeServer),
    networkRetryDelay: Duration.zero,
    refreshRetryDelay: Duration.zero,
  );

  @override
  ApiService? get apiService => _api;
  @override
  bool get isAuthenticated => true;
  @override
  bool get isLoading => false;
  @override
  String? get serverUrl => 'http://abs.test';
  @override
  String? get activeServerUrl => 'http://abs.test';
  @override
  String? get username => 'maximilian.alexander.von.hohenzollern';
  @override
  String? get userId => 'u1';
  @override
  bool get isAdmin => true;
  @override
  Map<String, dynamic>? get userJson => {
    'id': 'u1',
    'username': username,
    'type': 'admin',
    'permissions': {
      'update': true,
      'download': true,
      'accessExplicitContent': true,
    },
  };
}

class _FakeLibrary extends LibraryProvider {
  _FakeLibrary({this.absorbing = true});

  final bool absorbing;

  @override
  List<dynamic> get libraries => [_library];
  @override
  String? get selectedLibraryId => _libId;
  @override
  Map<String, dynamic>? get selectedLibrary => _library;
  @override
  List<dynamic> get personalizedSections => _sections;
  @override
  List<Map<String, dynamic>> getOrderedHomeSections() => _sections;
  @override
  List<String> get absorbingBookIds => absorbing
      ? [for (final b in _books.take(3)) b['id'] as String]
      : const [];
  @override
  Map<String, Map<String, dynamic>> get absorbingItemCache => {
    if (absorbing)
      for (final b in _books.take(3)) b['id'] as String: b,
  };
  @override
  bool get isLoading => false;
  @override
  bool get isOffline => false;
  @override
  Future<void> loadLibraries() async {}
  @override
  Future<void> loadPersonalizedView({bool force = false}) async {}
  @override
  Future<void> refresh() async {}
}

// ── Harness ──────────────────────────────────────────────────────────────

Future<void> _loadRealFonts() async {
  final dir = _materialFontsDir();
  if (dir == null) return;
  Future<ByteData> bytes(String name) async =>
      ByteData.sublistView(File('${dir.path}/$name').readAsBytesSync());
  final roboto = FontLoader('Roboto');
  for (final f in const [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-light.ttf',
    'roboto-black.ttf',
    'roboto-italic.ttf',
  ]) {
    roboto.addFont(bytes(f));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(bytes('materialicons-regular.otf'));
  await icons.load();
}

/// `<flutter>/bin/cache/artifacts/material_fonts`, found from FLUTTER_ROOT
/// or from the flutter_tester binary's own location.
Directory? _materialFontsDir() {
  final candidates = <String>[];
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) candidates.add('$root/bin/cache/artifacts/material_fonts');
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    candidates.add('${dir.path}/artifacts/material_fonts');
    dir = dir.parent;
  }
  for (final c in candidates) {
    final d = Directory(c);
    if (File('${d.path}/roboto-regular.ttf').existsSync()) return d;
  }
  return null;
}

class _Failure {
  /// Described right away: the element tree is gone by report time.
  _Failure(this.screen, this.combo, FlutterErrorDetails details)
    : text = details.toString(),
      summary = _firstLine(details.exceptionAsString());
  final String screen;
  final String combo;
  final String text;
  final String summary;

  static String _firstLine(String s) {
    final line = s.split('\n').first;
    return line.length > 160 ? '${line.substring(0, 160)}...' : line;
  }

  /// The app widget that caused it, from widget creation tracking.
  String get where {
    for (final m in RegExp(r'/lib/([\w/]+\.dart):(\d+)').allMatches(text)) {
      if (m.group(1)!.startsWith('src/')) continue; // a package's own code
      return 'lib/${m.group(1)}:${m.group(2)}';
    }
    return '?';
  }
}

class _Sweep {
  final failures = <_Failure>[];

  /// The sweep running now, so the scroll helpers can check text on every
  /// screenful, not only the last.
  static _Sweep? _current;
  void Function(FlutterErrorDetails)? _record;

  /// Text cut off without any error: a paragraph laid out shorter than its
  /// own lines (a fixed-height box around text that grew with the text
  /// size). Ellipsis on the last allowed line is fine; half a line is not.
  static void checkClippedText(WidgetTester tester) {
    final record = _current?._record;
    if (record == null) return;
    void visit(RenderObject o) {
      if (o is RenderParagraph && o.attached && o.hasSize && o.size.width > 0) {
        final needed = o.getMinIntrinsicHeight(o.size.width);
        if (needed - o.size.height > 2) {
          final text = o.text.toPlainText();
          record(
            FlutterErrorDetails(
              exception: FlutterError(
                'Text clipped vertically: needs ${needed.toStringAsFixed(1)} '
                'px, box is ${o.size.height.toStringAsFixed(1)} px: '
                '"${text.length > 50 ? '${text.substring(0, 50)}...' : text}"',
              ),
              informationCollector: () => [
                if (o.debugCreator != null)
                  DiagnosticsDebugCreator(o.debugCreator!),
              ],
            ),
          );
        }
      }
      o.visitChildren(visit);
    }

    for (final view in tester.binding.renderViews) {
      visit(view);
    }
  }

  /// Runs [body] for every combo, collecting layout errors instead of
  /// stopping at the first.
  Future<void> run(
    WidgetTester tester,
    String screen,
    List<_Combo> combos,
    Future<void> Function(_Combo combo) body,
  ) async {
    for (final combo in combos) {
      tester.view.physicalSize = combo.size;
      tester.view.devicePixelRatio = 1;
      final previous = FlutterError.onError;
      void record(FlutterErrorDetails e) =>
          failures.add(_Failure(screen, '$combo', e));
      FlutterError.onError = record;
      _record = record;
      _current = this;
      final watch = Stopwatch()..start();
      try {
        await body(combo);
        checkClippedText(tester);
      } catch (e, s) {
        record(FlutterErrorDetails(exception: e, stack: s));
      } finally {
        FlutterError.onError = previous;
        _current = null;
        _record = null;
      }
      final pending = tester.takeException();
      if (pending != null) record(FlutterErrorDetails(exception: pending));
      if (_verbose)
        debugPrint('[sweep] $screen $combo ${watch.elapsedMilliseconds}ms');
      // Tear down between combos so state never leaks.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    }
    tester.view.reset();
  }

  void expectClean() {
    if (failures.isEmpty) return;
    final byCause = <String, List<_Failure>>{};
    for (final f in failures) {
      final cause = f.summary
          .replaceAll(RegExp(r'by [\d.]+ pixels'), 'by N pixels')
          .replaceAll(RegExp(r'needs .* px:'), 'needs more height:');
      byCause.putIfAbsent('${f.where} | $cause', () => []).add(f);
    }
    final report = StringBuffer(
      'Layout errors (${byCause.length} distinct):\n',
    );
    for (final e in byCause.entries) {
      report.writeln('- ${e.key}');
      final screens = {for (final f in e.value) '${f.screen} ${f.combo}'};
      report.writeln(
        '    in: ${screens.take(6).join('; ')}'
        '${screens.length > 6 ? ' (+${screens.length - 6})' : ''}',
      );
    }
    if (_verbose) {
      for (final f in byCause.values) {
        debugPrint('==== ${f.first.screen} ${f.first.combo}\n${f.first.text}');
      }
    }
    fail(report.toString());
  }
}

Widget _app(
  _Combo combo,
  Widget home, {
  required AuthProvider auth,
  required LibraryProvider library,
}) {
  ThemeData theme(Brightness b) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7C6FBF),
      brightness: b,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      extensions: [absorbLookFor(b)],
    );
  }

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<LibraryProvider>.value(value: library),
    ],
    child: UiThemeScope(
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        themeMode: combo.brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        theme: theme(Brightness.light),
        darkTheme: theme(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(combo.scale)),
          child: absorbLookBuilder(context, child),
        ),
        home: home,
      ),
    ),
  );
}

/// Lets async loads land and animations finish without waiting on spinners.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The main vertical scrollable: the tallest one on screen.
ScrollableState? _mainScrollable(WidgetTester tester) {
  ScrollableState? main;
  var best = 0.0;
  for (final e in find.byType(Scrollable).evaluate()) {
    final s = e.widget as Scrollable;
    if (s.axisDirection != AxisDirection.down) continue;
    final box = e.renderObject as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) continue;
    if (box.size.height > best) {
      best = box.size.height;
      main = (e as StatefulElement).state as ScrollableState;
    }
  }
  return main;
}

/// Scrolls the main list down most of a screen; false at the bottom.
Future<bool> _scrollStep(WidgetTester tester) async {
  final main = _mainScrollable(tester);
  if (main == null) return false;
  final p = main.position;
  if (p.pixels >= p.maxScrollExtent) return false;
  p.jumpTo(
    (p.pixels + p.viewportDimension * 0.8).clamp(0.0, p.maxScrollExtent),
  );
  await tester.pump(const Duration(milliseconds: 100));
  _Sweep.checkClippedText(tester);
  return true;
}

Future<void> _scrollAll(WidgetTester tester) async {
  for (var i = 0; i < 40 && await _scrollStep(tester); i++) {}
}

/// Opens every CollapsibleSection once, top to bottom, and scrolls through
/// its content. Settings is an accordion (opening one closes the last), so
/// each section is brought to the top, opened, then read to its end.
/// Returns the titles opened.
Future<Set<String>> _openEverySection(WidgetTester tester) async {
  final titles = [
    for (final e
        in find.byType(CollapsibleSection, skipOffstage: false).evaluate())
      (e.widget as CollapsibleSection).title,
  ];
  final opened = <String>{};
  for (final title in titles) {
    // Not skipping offstage: while the screen scrolls itself after an
    // open, a section can sit outside the viewport for a moment.
    final section = find.byWidgetPredicate(
      (w) => w is CollapsibleSection && w.title == title,
      skipOffstage: false,
    );
    if (section.evaluate().isEmpty) continue;
    final tile = find.descendant(
      of: section,
      matching: find.byType(ExpansionTile, skipOffstage: false),
      skipOffstage: false,
    );
    // Opened through its controller, like a tap on the header would, so a
    // tap can never land on something else and open another page.
    tester.widget<ExpansionTile>(tile.first).controller!.expand();
    // Expand, then the screen's own delayed scroll to the section (350 ms
    // later, 250 ms long).
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 300));
    opened.add(title);
    // Read it from its top: the section above just closed.
    await Scrollable.ensureVisible(tester.element(section.first));
    await tester.pump();
    _Sweep.checkClippedText(tester);
    final height = tester.getSize(section.first).height;
    final view = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    for (var d = view * 0.8; d < height; d += view * 0.8) {
      if (!await _scrollStep(tester)) break;
    }
  }
  return opened;
}

void main() {
  // Measuring with the square test font would chase false overflows, so
  // without the SDK's Roboto (run `flutter precache` once) the sweep is
  // skipped with a reason instead of failing.
  if (_materialFontsDir() == null) {
    test(
      'overflow sweep',
      () {},
      skip:
          'Flutter material fonts not found (looked under FLUTTER_ROOT and '
          'next to ${Platform.resolvedExecutable}); run `flutter precache`.',
    );
    return;
  }
  late _Sweep sweep;

  setUpAll(() async {
    await _loadRealFonts();
    // Real glyph widths, or the sweep would chase square test-font text.
    final narrow = TextPainter(
      text: const TextSpan(
        text: 'iiii',
        style: TextStyle(fontFamily: 'Roboto'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final wide = TextPainter(
      text: const TextSpan(
        text: 'MMMM',
        style: TextStyle(fontFamily: 'Roboto'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    expect(
      narrow.width,
      lessThan(wide.width * 0.6),
      reason: 'Roboto from the Flutter SDK cache did not load',
    );
  });

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Absorb Plus',
      packageName: 'absorb',
      version: '1.12.1',
      buildNumber: '318',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({WelcomeSheet.prefKey: true});
    classicWordingNotifier.value = false;
    lookDetailsNotifier.value = LookDetails.standard;
    uiThemeNotifier.value = null;
    uiThemePreviewNotifier.value = null;
    sweep = _Sweep();
  });

  tearDown(() {
    classicWordingNotifier.value = false;
  });

  Future<void> pumpScreen(
    WidgetTester tester,
    _Combo combo,
    Widget screen, {
    LibraryProvider? library,
    bool welcomeSeen = true,
  }) async {
    // Fresh settings each time: screens persist things like the open tab.
    // Launch prompts already seen, so they don't cover the screen.
    SharedPreferences.setMockInitialValues({
      WelcomeSheet.prefKey: welcomeSeen,
      UiThemeStore.prefKey: (uiThemeNotifier.value ?? AppUiTheme.plus).id,
      'whats_new_last_build': 318,
    });
    final auth = _FakeAuth();
    final lib = library ?? _FakeLibrary();
    await tester.pumpWidget(_app(combo, screen, auth: auth, library: lib));
    await _settle(tester);
  }

  testWidgets('App shell: nav bar and tabs', (tester) async {
    for (final plain in [false, true]) {
      classicWordingNotifier.value = plain;
      await sweep.run(tester, 'App shell plain=$plain', _fullMatrix(), (
        c,
      ) async {
        await pumpScreen(tester, c, const AppShell());
        expect(find.textContaining('Cartographer'), findsWidgets);
        expect(find.text(plain ? 'Now Playing' : 'Absorbing'), findsWidgets);
      });
    }
    sweep.expectClean();
  });

  testWidgets('Home', (tester) async {
    for (final plain in [false, true]) {
      classicWordingNotifier.value = plain;
      await sweep.run(tester, 'Home plain=$plain', _fullMatrix(), (c) async {
        await pumpScreen(tester, c, const HomeScreen());
        expect(find.textContaining('Cartographer'), findsWidgets);
        await _scrollAll(tester);
      });
    }
    sweep.expectClean();
  });

  testWidgets('Absorbing with cards', (tester) async {
    for (final plain in [false, true]) {
      classicWordingNotifier.value = plain;
      await sweep.run(tester, 'Absorbing plain=$plain', _fullMatrix(), (
        c,
      ) async {
        await pumpScreen(tester, c, AbsorbingScreen(key: GlobalKey()));
        expect(find.byType(AbsorbingCard), findsWidgets);
      });
    }
    sweep.expectClean();
  });

  testWidgets('Absorbing empty', (tester) async {
    await sweep.run(tester, 'Absorbing empty', _fullMatrix(), (c) async {
      await pumpScreen(
        tester,
        c,
        AbsorbingScreen(key: GlobalKey()),
        library: _FakeLibrary(absorbing: false),
      );
    });
    sweep.expectClean();
  });

  testWidgets('Library', (tester) async {
    await sweep.run(tester, 'Library', _fullMatrix(), (c) async {
      final key = GlobalKey<LibraryScreenState>();
      await pumpScreen(tester, c, LibraryScreen(key: key));
      expect(find.textContaining('Cartographer'), findsWidgets);
      await _scrollAll(tester);
      // The other tabs: series, authors, narrators (a list), lists.
      final l = await AppLocalizations.delegate.load(const Locale('en'));
      for (final (tab, shows) in [
        (l.libraryTabSeries, _seriesName),
        (l.libraryTabAuthors, _authors[1]),
        (l.libraryTabNarrators, _narrators[0]),
        ('Lists', 'My playlist'),
      ]) {
        key.currentState!.resetReveal(); // the tab pill hides on scroll
        await _settle(tester);
        final label = find.text(tab);
        if (label.evaluate().isEmpty) {
          fail('Library tab "$tab" not found');
        }
        await tester.tap(label.last, warnIfMissed: false);
        await _settle(tester);
        expect(find.textContaining(shows), findsWidgets, reason: tab);
        await _scrollAll(tester);
      }
    });
    sweep.expectClean();
  });

  testWidgets('Stats', (tester) async {
    await sweep.run(tester, 'Stats', _fullMatrix(), (c) async {
      await pumpScreen(tester, c, const StatsScreen());
      await _scrollAll(tester);
      expect(find.textContaining('Cartographer'), findsWidgets);
    });
    sweep.expectClean();
  });

  testWidgets('Settings, every section open', (tester) async {
    for (final plain in [false, true]) {
      classicWordingNotifier.value = plain;
      // The plain pass also runs Frosted: its glass control shows in the
      // look tile and its surfaces wrap every panel.
      uiThemeNotifier.value = plain ? AppUiTheme.frosted : null;
      await sweep.run(tester, 'Settings plain=$plain', _fullMatrix(), (
        c,
      ) async {
        await pumpScreen(tester, c, const SettingsScreen());
        final opened = await _openEverySection(tester);
        expect(opened.length, greaterThanOrEqualTo(10), reason: '$opened');
      });
    }
    sweep.expectClean();
  });

  testWidgets('Downloads, Bookmarks, Achievements', (tester) async {
    for (final (name, screen) in const [
      ('Downloads', DownloadsScreen()),
      ('Bookmarks', BookmarksScreen()),
      ('Achievements', AchievementsScreen()),
    ]) {
      await sweep.run(tester, name, _compactMatrix(), (c) async {
        await pumpScreen(tester, c, screen);
        await _scrollAll(tester);
      });
    }
    sweep.expectClean();
  });

  testWidgets('Look picker, both steps', (tester) async {
    await sweep.run(tester, 'Look picker', _compactMatrix(), (c) async {
      late BuildContext home;
      await pumpScreen(
        tester,
        c,
        Scaffold(
          body: Builder(
            builder: (context) {
              home = context;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      UiThemePicker.show(home);
      await _settle(tester);
      await _scrollAll(tester);
      final next = find.byKey(const ValueKey('ui-next'));
      if (next.evaluate().isNotEmpty) {
        await tester.tap(next);
        await _settle(tester);
        await _scrollAll(tester);
      }
    });
    sweep.expectClean();
  });

  testWidgets("What's new", (tester) async {
    final notes = File('test/fixtures/whats_new/beta-11.md').readAsStringSync();
    final originalService = WhatsNewSheet.notesService;
    WhatsNewSheet.notesService = () => WhatsNewNotesService(
      fetch: (_) async =>
          WhatsNewRelease(notes, name: 'Absorb Plus 1.12.1-318 (Beta 11)'),
    );
    addTearDown(() => WhatsNewSheet.notesService = originalService);
    await sweep.run(tester, "What's new", _compactMatrix(), (c) async {
      late BuildContext home;
      await pumpScreen(
        tester,
        c,
        Scaffold(
          body: Builder(
            builder: (context) {
              home = context;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      WhatsNewSheet.show(
        home,
        version: '1.12.1',
        build: 318,
        previous: const WhatsNewPrevious(
          version: '1.11.1',
          build: 300,
          beta: 10,
        ),
      );
      await _settle(tester);
      await _scrollAll(tester);
    });
    sweep.expectClean();
  });

  testWidgets('Welcome', (tester) async {
    await sweep.run(tester, 'Welcome', _compactMatrix(), (c) async {
      late BuildContext home;
      await pumpScreen(
        tester,
        c,
        welcomeSeen: false,
        Scaffold(
          body: Builder(
            builder: (context) {
              home = context;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      WelcomeSheet.showIfNeeded(home);
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      await _scrollAll(tester);
    });
    sweep.expectClean();
  });

  testWidgets('Book detail sheet, long metadata', (tester) async {
    await sweep.run(tester, 'Book detail', _fullMatrix(), (c) async {
      late BuildContext home;
      await pumpScreen(
        tester,
        c,
        Scaffold(
          body: Builder(
            builder: (context) {
              home = context;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      showBookDetailSheet(home, 'li-1');
      await _settle(tester);
      expect(find.textContaining(_noSpaces.substring(0, 30)), findsWidgets);
      await _scrollAll(tester);
    });
    sweep.expectClean();
  });
}
