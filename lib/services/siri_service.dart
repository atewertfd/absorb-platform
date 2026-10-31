/// Siri is not part of Absorb Plus: Apple platforms were removed from the fork
/// (see tool/fork-removed-paths.txt, which also drops upstream's
/// siri_matcher.dart). Upstream's version only did anything on iOS, so this
/// no-op behaves the same everywhere Absorb Plus runs. It keeps upstream's
/// call sites (main.dart, library_provider.dart, _lp_core.dart,
/// settings_screen.dart) compiling unchanged, so upstream merges stay clean.
///
/// tool/fork-overrides.txt keeps this version whenever upstream edits the
/// original Siri implementation.
class SiriService {
  static final SiriService _instance = SiriService._();
  factory SiriService() => _instance;
  SiriService._();

  /// Set by LibraryProvider; never read here.
  static Iterable<Map<String, dynamic>> Function()? libraryItems;

  Future<void> init() async {}

  void scheduleCatalogUpdate({Duration delay = const Duration(seconds: 5)}) {}

  Future<String> authorizationStatus() async => 'unsupported';

  Future<String> requestAuthorization() async => 'unsupported';

  Future<void> openSystemSettings() async {}
}
