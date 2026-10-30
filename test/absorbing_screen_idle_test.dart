import 'package:absorb/l10n/app_localizations.dart';
import 'package:absorb/providers/auth_provider.dart';
import 'package:absorb/providers/library_provider.dart';
import 'package:absorb/screens/absorbing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // The screen used to reload its queue setting in build() and call setState
  // every time, so it rebuilt and redrew forever (64+ fps on an idle screen).
  testWidgets('the Absorbing screen settles instead of rebuilding forever',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProxyProvider<AuthProvider, LibraryProvider>(
            create: (_) => LibraryProvider(),
            update: (_, auth, library) => library!..updateAuth(auth),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AbsorbingScreen(),
        ),
      ),
    );

    // Give the async settings loads time to finish, frame by frame.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: 'an idle Absorbing screen must stop asking for frames');
  });
}
