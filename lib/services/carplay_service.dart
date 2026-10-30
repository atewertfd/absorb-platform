/// CarPlay is not part of Absorb Plus: Apple platforms were removed from the
/// fork (see tool/fork-removed-paths.txt). This no-op keeps upstream's call
/// sites (main.dart, auth_provider.dart, library_provider.dart, _lp_core.dart,
/// app_shell.dart) compiling unchanged, so upstream merges stay clean.
///
/// tool/fork-overrides.txt keeps this version whenever upstream edits the
/// original CarPlay implementation.
class CarPlayService {
  static final CarPlayService _instance = CarPlayService._();
  factory CarPlayService() => _instance;
  CarPlayService._();

  void init() {}

  void dispose() {}

  Future<void> clearAndRefresh() async {}

  Future<void> refreshTemplates() async {}
}
