import 'package:absorb/l10n/app_localizations.dart';
import 'package:absorb/providers/auth_provider.dart';
import 'package:absorb/providers/library_provider.dart';
import 'package:absorb/screens/settings_screen.dart';
import 'package:absorb/widgets/welcome_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The Windows Settings section (keyboard shortcuts, update checks and the
// runner's switches) must be part of the Settings page itself. It used to sit
// inside the download-location sheet, where nobody could reach it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('absorb/windows_shell');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SharedPreferences.setMockInitialValues({WelcomeSheet.prefKey: true});
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getState') {
        return <String, Object?>{'closeToTray': false, 'keepAwake': true};
      }
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

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
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('Windows Settings is a section of the Settings page on Windows',
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
      (tester) async {
    await pumpSettings(tester);
    final title = find.text('Windows Settings');
    await tester.scrollUntilVisible(title, 400,
        scrollable: find.byType(Scrollable).first);
    expect(title, findsOneWidget);

    await tester.tap(title);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Keyboard shortcuts'), findsOneWidget);
    expect(find.text('Automatic update checks'), findsOneWidget);
    expect(find.text('Close to tray'), findsOneWidget);
    expect(find.text('Keep PC awake while playing or downloading'),
        findsOneWidget);
  });

  testWidgets('no Windows section on Android', (tester) async {
    await pumpSettings(tester);
    expect(find.text('Windows Settings', skipOffstage: false), findsNothing);
  });
}
