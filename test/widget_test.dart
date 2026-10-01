import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:absorb/main.dart';
import 'package:absorb/providers/auth_provider.dart';
import 'package:absorb/providers/library_provider.dart';

void main() {
  testWidgets('Absorb Plus application shell builds', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProxyProvider<AuthProvider, LibraryProvider>(
            create: (_) => LibraryProvider(),
            update: (_, auth, library) => library!..updateAuth(auth),
          ),
        ],
        child: const AbsorbApp(),
      ),
    );

    await tester.pump();
    expect(find.byType(AbsorbApp), findsOneWidget);
  });
}
