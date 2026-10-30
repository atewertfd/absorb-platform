import 'dart:async';

import 'package:absorb/l10n/app_localizations.dart';
import 'package:absorb/services/update_checker_service.dart';
import 'package:absorb/widgets/update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final opened = <Uri>[];
  late Completer<ApkInstallResult> install;
  var cancels = 0;

  setUp(() {
    opened.clear();
    cancels = 0;
    UpdateDialog.installApk = (info, {required onProgress}) => install.future;
    UpdateDialog.cancelApk = () {
      cancels++;
      // What a closed HTTP client used to produce.
      install.complete(
        const ApkInstallResult(ApkInstallStatus.downloadFailed, 'closed'),
      );
    };
    UpdateDialog.openExternal = (url) async {
      opened.add(url);
      return true;
    };
  });

  final originalInstall = UpdateDialog.installApk;
  final originalCancel = UpdateDialog.cancelApk;
  final originalOpen = UpdateDialog.openExternal;
  tearDown(() {
    UpdateDialog.installApk = originalInstall;
    UpdateDialog.cancelApk = originalCancel;
    UpdateDialog.openExternal = originalOpen;
  });

  final info = UpdateInfo(
    latestVersion: 'v1.12.1-311',
    currentVersion: '1.12.1+309',
    downloadUrl: 'https://example.invalid/absorb-1.12.1-311-android-universal.apk',
    isDirectApk: true,
  );

  /// Opens a "Settings" page over home, then the update prompt from it.
  Future<void> openPromptFromSettings(WidgetTester tester) async {
    // Created inside the test body so its callbacks run on the fake clock.
    install = Completer<ApkInstallResult>();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (home) => TextButton(
            onPressed: () => Navigator.of(home).push(
              MaterialPageRoute<void>(
                builder: (settings) => Scaffold(
                  body: TextButton(
                    onPressed: () => UpdateDialog.show(settings, info),
                    child: const Text('check'),
                  ),
                ),
              ),
            ),
            child: const Text('open settings'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('check'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Downloading update...'), findsOneWidget);
  }

  testWidgets('Cancel closes only the progress dialog and opens no browser',
      (tester) async {
    await openPromptFromSettings(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(cancels, 1);
    expect(opened, isEmpty);
    expect(find.text('Downloading update...'), findsNothing);
    // The page the prompt was opened from is still there.
    expect(find.text('check'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a finished install closes the progress dialog, not the page',
      (tester) async {
    await openPromptFromSettings(tester);

    install.complete(const ApkInstallResult(ApkInstallStatus.ok));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Downloading update...'), findsNothing);
    expect(find.text('check'), findsOneWidget);
    expect(opened, isEmpty);
  });

  testWidgets('a real download failure still falls back to the browser',
      (tester) async {
    await openPromptFromSettings(tester);

    install.complete(
      const ApkInstallResult(ApkInstallStatus.downloadFailed, 'HTTP 404'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Downloading update...'), findsNothing);
    expect(find.text('check'), findsOneWidget);
    expect(opened, [Uri.parse(info.downloadUrl)]);
    await tester.pump(const Duration(seconds: 5));
  });
}
