import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/server_health_service.dart';

class ServerHealthScreen extends StatefulWidget {
  const ServerHealthScreen({super.key});

  @override
  State<ServerHealthScreen> createState() => _ServerHealthScreenState();
}

class _ServerHealthScreenState extends State<ServerHealthScreen> {
  ServerHealthSnapshot? _snapshot;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runCheck());
  }

  Future<void> _runCheck() async {
    final auth = context.read<AuthProvider>();
    final url = auth.activeServerUrl;
    if (url == null || url.isEmpty) return;
    setState(() => _running = true);
    final snapshot = await ServerHealthService().check(
      serverUrl: url,
      api: auth.apiService,
      customHeaders: auth.customHeaders,
    );
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    final snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('Server health')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Audiobookshelf compatibility',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'A read-only check for connectivity, server version, and this account session. It does not modify your library.',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    auth.activeServerUrl ?? 'No server selected',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),
                  if (_running)
                    const Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('Checking server…'),
                      ],
                    )
                  else if (snapshot == null)
                    const Text('No check has been completed yet.')
                  else ...[
                    _HealthRow(
                      label: 'Connectivity',
                      value: snapshot.reachable ? 'OK' : 'Failed',
                      ok: snapshot.reachable,
                    ),
                    _HealthRow(
                      label: 'Account session',
                      value: snapshot.authenticated
                          ? 'Authenticated'
                          : 'Needs attention',
                      ok: snapshot.authenticated,
                    ),
                    _HealthRow(
                      label: 'Server version',
                      value: snapshot.serverVersion ?? 'Unknown',
                      ok: snapshot.serverVersion != null,
                    ),
                    _HealthRow(
                      label: 'Latency',
                      value: snapshot.latency == null
                          ? 'Unavailable'
                          : '${snapshot.latency!.inMilliseconds} ms',
                      ok: snapshot.latency != null,
                    ),
                    if (snapshot.detail != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        snapshot.detail!,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _running ? null : _runCheck,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Run check again'),
          ),
        ],
      ),
    );
  }
}

class _HealthRow extends StatelessWidget {
  final String label;
  final String value;
  final bool ok;

  const _HealthRow({
    required this.label,
    required this.value,
    required this.ok,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.warning_rounded,
            size: 18,
            color: ok ? colors.primary : colors.error,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
