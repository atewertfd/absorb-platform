import 'package:absorb/providers/auth_provider.dart';
import 'package:absorb/providers/library_provider.dart';
import 'package:absorb/services/download_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a disposed LibraryProvider stops listening to downloads', () async {
    SharedPreferences.setMockInitialValues({});
    final downloads = DownloadService();
    // ignore: invalid_use_of_protected_member
    final before = downloads.hasListeners;

    final lib = LibraryProvider()..updateAuth(AuthProvider());
    // ignore: invalid_use_of_protected_member
    expect(downloads.hasListeners, isTrue);

    lib.dispose();
    // ignore: invalid_use_of_protected_member
    expect(downloads.hasListeners, before,
        reason: 'dispose() must remove the DownloadService listener');
  });
}
