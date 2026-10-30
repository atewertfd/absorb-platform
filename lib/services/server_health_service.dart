import 'api_service.dart';

/// The result of a safe, read-only compatibility probe.
class ServerHealthSnapshot {
  final bool reachable;
  final bool authenticated;
  final String? serverVersion;
  final Duration? latency;
  final String? detail;
  final DateTime checkedAt;

  const ServerHealthSnapshot({
    required this.reachable,
    required this.authenticated,
    required this.serverVersion,
    required this.latency,
    required this.detail,
    required this.checkedAt,
  });

  bool get healthy => reachable && authenticated;
}

/// Runs the smallest useful set of diagnostics without changing server data.
///
/// This deliberately uses /ping, /status, and the authenticated libraries
/// endpoint only. It is suitable for users diagnosing proxies, TLS, old
/// Audiobookshelf servers, and expired sessions from inside the app.
class ServerHealthService {
  Future<ServerHealthSnapshot> check({
    required String serverUrl,
    required ApiService? api,
    Map<String, String> customHeaders = const {},
  }) async {
    final started = DateTime.now();
    final ping = await ApiService.pingServerDetailed(
      serverUrl,
      customHeaders: customHeaders,
    );
    final latency = ping.ok ? DateTime.now().difference(started) : null;
    if (!ping.ok) {
      return ServerHealthSnapshot(
        reachable: false,
        authenticated: false,
        serverVersion: null,
        latency: latency,
        detail: ping.detail,
        checkedAt: DateTime.now(),
      );
    }

    final version = await ApiService.getServerVersion(
      serverUrl,
      customHeaders: customHeaders,
    );
    if (api == null) {
      return ServerHealthSnapshot(
        reachable: true,
        authenticated: false,
        serverVersion: version,
        latency: latency,
        detail:
            'The server is reachable, but this session is not authenticated.',
        checkedAt: DateTime.now(),
      );
    }

    try {
      final user = await api.getMe();
      if (user == null) {
        return ServerHealthSnapshot(
          reachable: true,
          authenticated: false,
          serverVersion: version,
          latency: latency,
          // getMe() also returns null on timeouts and network errors.
          detail: 'The server is reachable, but the session could not be '
              'confirmed (rejected, expired, or the request failed).',
          checkedAt: DateTime.now(),
        );
      }
      final libraries = await api.getLibraries();
      return ServerHealthSnapshot(
        reachable: true,
        authenticated: true,
        serverVersion: version,
        latency: latency,
        // getLibraries() returns [] on failure too, so zero is not proof.
        detail: libraries.isEmpty
            ? 'Signed in, but no libraries came back (none shared with this '
                'account, or the request failed).'
            : '${libraries.length} libraries visible to this account.',
        checkedAt: DateTime.now(),
      );
    } catch (error) {
      return ServerHealthSnapshot(
        reachable: true,
        authenticated: false,
        serverVersion: version,
        latency: latency,
        detail: 'The session check failed: $error',
        checkedAt: DateTime.now(),
      );
    }
  }
}
