import 'dart:io';

import 'package:absorb/l10n/app_localizations.dart';
import 'package:absorb/providers/auth_provider.dart';
import 'package:absorb/providers/library_provider.dart';
import 'package:absorb/screens/settings_screen.dart';
import 'package:absorb/utils/fork_branding.dart';
import 'package:absorb/utils/fork_platform.dart';
import 'package:absorb/widgets/support_actions.dart';
import 'package:absorb/widgets/welcome_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Owner decision (2026-10-30): support rows go to the Absorb Plus GitHub
// issues, upstream's Discord is hidden, and "Send logs" saves a file on
// desktop. Nothing here contacts a real server or browser.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const shell = MethodChannel('absorb/windows_shell');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final defaultLauncher = ForkPlatform.launcher;
  final defaultLogsDir = SupportActions.logsDirectory;
  final defaultPicker = SupportActions.pickSavePath;
  late List<Uri> opened;

  setUp(() {
    SharedPreferences.setMockInitialValues({WelcomeSheet.prefKey: true});
    messenger.setMockMethodCallHandler(shell, (call) async {
      if (call.method == 'getState') {
        return <String, Object?>{'closeToTray': false, 'keepAwake': false};
      }
      return null;
    });
    opened = [];
    ForkPlatform.launcher = (uri) async {
      opened.add(uri);
      return true;
    };
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(shell, null);
    ForkPlatform.launcher = defaultLauncher;
    SupportActions.logsDirectory = defaultLogsDir;
    SupportActions.pickSavePath = defaultPicker;
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
        ChangeNotifierProvider<LibraryProvider>(
            create: (_) => LibraryProvider()),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsScreen(),
      ),
    ));
    await settle(tester);
  }

  Future<void> openSection(WidgetTester tester, String title) async {
    final header = find.text(title);
    await tester.scrollUntilVisible(header, 400,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(header);
    await settle(tester);
  }

  testWidgets('Contact opens the Absorb Plus issues; Discord is hidden',
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
      (tester) async {
    await pumpSettings(tester);
    await openSection(tester, 'Issues & Support');

    expect(find.text('Join Discord', skipOffstage: false), findsNothing);
    final contact = find.text('Contact');
    await tester.scrollUntilVisible(contact, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(contact);
    await tester.pump();
    expect(opened.single.toString(), ForkBranding.issuesUrl);
    expect(ForkBranding.issuesUrl, contains('atewertfd/absorb-plus'));
  });

  testWidgets('Transcription settings are hidden on Windows',
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
      (tester) async {
    await pumpSettings(tester);
    await openSection(tester, 'Advanced');
    expect(find.text('Transcription', skipOffstage: false), findsNothing);
  });

  testWidgets('Transcription settings stay on Android', (tester) async {
    await pumpSettings(tester);
    await openSection(tester, 'Advanced');
    expect(find.text('Transcription', skipOffstage: false), findsOneWidget);
  });

  Future<BuildContext> pumpHost(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(builder: (c) {
          ctx = c;
          return const OpenLogsFolderTile();
        }),
      ),
    ));
    return ctx;
  }

  testWidgets('Send logs saves the log file on desktop',
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('absorb_support_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/absorb_logs.txt')
        .writeAsStringSync('[2026-10-30] [Player] started\n');
    final target = '${dir.path}/saved.txt';
    String? askedName;
    SupportActions.logsDirectory = () async => dir;
    SupportActions.pickSavePath = (title, name) async {
      askedName = name;
      return target;
    };

    expect(SupportActions.savesLogsToFile, isTrue);
    final ctx = await pumpHost(tester);
    await tester.runAsync(() => SupportActions.sendLogs(ctx));
    await tester.pump();

    final saved = File(target).readAsStringSync();
    expect(askedName, startsWith('absorb-plus-logs-'));
    expect(saved, contains('Absorb Plus log report'));
    expect(saved, contains(ForkBranding.issuesUrl));
    expect(saved, contains('[Player] started'));
    expect(saved, isNot(contains('barnabashq')));
    expect(find.textContaining('Logs saved to'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('cancelling the save dialog writes nothing',
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('absorb_support_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    SupportActions.logsDirectory = () async => dir;
    SupportActions.pickSavePath = (_, __) async => null;
    final ctx = await pumpHost(tester);
    await tester.runAsync(() => SupportActions.sendLogs(ctx));
    await tester.pump();
    expect(dir.listSync(), isEmpty);
    expect(find.textContaining('Logs saved'), findsNothing);
  });

  testWidgets('Open logs folder opens the log directory',
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('absorb_support_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    SupportActions.logsDirectory = () async => dir;
    await pumpHost(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('Open logs folder'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(opened.single, Uri.directory(dir.path));
  });

  test('Android shares instead of saving', () {
    expect(SupportActions.savesLogsToFile, isFalse);
  });
}
