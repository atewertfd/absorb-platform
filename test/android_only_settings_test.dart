import 'package:absorb/l10n/app_localizations.dart';
import 'package:absorb/providers/auth_provider.dart';
import 'package:absorb/providers/library_provider.dart';
import 'package:absorb/screens/settings_screen.dart';
import 'package:absorb/screens/settings_search_index.dart';
import 'package:absorb/widgets/sleep_timer_sheet.dart';
import 'package:absorb/widgets/welcome_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Settings that only work on a phone (Android Auto, rotation lock, shake,
// the headphone wind-down button, the media notification, Android
// permissions) are hidden off Android, in Settings and in its search.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l = lookupAppLocalizations(const Locale('en'));
  const shell = MethodChannel('absorb/windows_shell');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SharedPreferences.setMockInitialValues({WelcomeSheet.prefKey: true});
    messenger.setMockMethodCallHandler(shell, (call) async {
      if (call.method == 'getState') {
        return <String, Object?>{'closeToTray': false, 'keepAwake': true};
      }
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(shell, null));

  Future<List<SettingSearchEntry>> searchEntries(WidgetTester tester) async {
    late List<SettingSearchEntry> entries;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            entries = settingsSearchEntries(context);
            return const SizedBox();
          },
        ),
      ),
    );
    return entries;
  }

  final phoneOnlyTitles = [
    l.chapterProgressInNotification,
    l.lockSeekBar,
    l.shakeDuringSleepTimer,
    l.shakeSensitivity,
    l.buttonDuringSleepTimer,
    l.sleepAddAmount,
    l.keepScreenOnCarMode,
    l.carBookOrder,
    l.notifications,
    'Lock rotation',
  ];

  testWidgets(
    'search leaves out phone-only settings on Windows',
    variant: const TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
    (tester) async {
      final entries = await searchEntries(tester);
      final titles = entries.map((e) => e.title).toSet();
      for (final t in phoneOnlyTitles) {
        expect(titles, isNot(contains(t)), reason: t);
      }
      expect(entries.where((e) => e.sectionId == 'Car'), isEmpty);
      expect(entries.where((e) => e.sectionId == 'Permissions'), isEmpty);
      // Still offered: these work on the desktop.
      expect(titles, contains(l.keepScreenOnPlayer));
      expect(titles, contains(l.nowPlayingText));
      expect(titles, contains(l.resetTimerOnPause));
    },
  );

  testWidgets('search keeps every phone setting on Android', (tester) async {
    final titles = (await searchEntries(tester)).map((e) => e.title).toSet();
    for (final t in phoneOnlyTitles) {
      expect(titles, contains(t), reason: t);
    }
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
          ChangeNotifierProvider<LibraryProvider>(
            create: (_) => LibraryProvider(),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets(
    'no Android Auto or Permissions section on Windows',
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    (tester) async {
      await pumpSettings(tester);
      expect(find.text(l.sectionCar, skipOffstage: false), findsNothing);
      expect(
        find.text(l.sectionPermissions, skipOffstage: false),
        findsNothing,
      );
      expect(
        find.text(l.sectionSleepTimer, skipOffstage: false),
        findsOneWidget,
      );
    },
  );

  testWidgets('Android keeps the Android Auto and Permissions sections', (
    tester,
  ) async {
    await pumpSettings(tester);
    expect(find.text(l.sectionCar, skipOffstage: false), findsOneWidget);
    expect(
      find.text(l.sectionPermissions, skipOffstage: false),
      findsOneWidget,
    );
  });

  Future<void> pumpSleepSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: SleepTimerSheet(accent: Colors.teal),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets(
    'sleep timer sheet has no shake toggle on Windows',
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    (tester) async {
      await pumpSleepSheet(tester);
      expect(
        find.text(l.sleepTimerSheetShake, skipOffstage: false),
        findsNothing,
      );
    },
  );

  testWidgets('sleep timer sheet keeps the shake toggle on Android', (
    tester,
  ) async {
    await pumpSleepSheet(tester);
    expect(
      find.text(l.sleepTimerSheetShake, skipOffstage: false),
      findsOneWidget,
    );
  });
}
