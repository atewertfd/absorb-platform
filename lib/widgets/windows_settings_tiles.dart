import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/windows_shell.dart';

/// Windows-only switches kept by the runner (fork-owned): close to tray,
/// start with Windows, start minimized, always on top and keep awake. Sits in
/// Settings → Windows Settings.
class WindowsSettingsTiles extends StatefulWidget {
  const WindowsSettingsTiles({super.key, this.shell});

  /// Injected in tests; the app uses [WindowsShell.instance].
  final WindowsShell? shell;

  /// Whether Settings shows the Windows section at all.
  static bool get isAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  State<WindowsSettingsTiles> createState() => _WindowsSettingsTilesState();
}

class _WindowsSettingsTilesState extends State<WindowsSettingsTiles> {
  WindowsShell get _shell => widget.shell ?? WindowsShell.instance;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _shell.refresh().catchError((Object _) => null);
  }

  Future<void> _change(
    Future<WindowsShellSettings?> Function() action,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.windowsSettingFailed),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final small = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: cs.onSurfaceVariant);
    return ValueListenableBuilder<WindowsShellSettings?>(
      valueListenable: _shell.settings,
      builder: (context, settings, _) {
        // Until the runner answers (or on an older runner) nothing to show.
        if (settings == null) return const SizedBox.shrink();
        final enabled = !_busy;
        String startSubtitle = l.windowsStartWithWindowsSubtitle;
        if (settings.startWithWindows) {
          startSubtitle = settings.startWithWindowsThisCopy
              ? l.windowsStartWithWindowsRegistered(
                  settings.startWithWindowsCommand)
              : l.windowsStartWithWindowsOtherCopy(
                  settings.startWithWindowsCommand);
          if (settings.startupDisabledBySystem) {
            startSubtitle += '\n${l.windowsStartupDisabledBySystem}';
          }
        }
        final startsWithWindows =
            settings.startWithWindows && settings.startWithWindowsThisCopy;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              title: Text(l.windowsCloseToTray),
              subtitle: Text(l.windowsCloseToTraySubtitle, style: small),
              value: settings.closeToTray,
              onChanged: enabled
                  ? (v) => _change(() => _shell.setCloseToTray(v))
                  : null,
            ),
            SwitchListTile(
              title: Text(l.windowsStartWithWindows),
              subtitle: Text(startSubtitle, style: small),
              value: startsWithWindows,
              onChanged: enabled
                  ? (v) => _change(() => _shell.setStartWithWindows(v))
                  : null,
            ),
            SwitchListTile(
              title: Text(l.windowsStartMinimized),
              subtitle: Text(l.windowsStartMinimizedSubtitle, style: small),
              value: settings.startMinimized,
              onChanged: enabled && startsWithWindows
                  ? (v) => _change(() => _shell.setStartMinimized(v))
                  : null,
            ),
            SwitchListTile(
              title: Text(l.windowsAlwaysOnTop),
              subtitle: Text(l.windowsAlwaysOnTopSubtitle, style: small),
              value: settings.alwaysOnTop,
              onChanged: enabled
                  ? (v) => _change(() => _shell.setAlwaysOnTop(v))
                  : null,
            ),
            SwitchListTile(
              title: Text(l.windowsKeepAwake),
              subtitle: Text(l.windowsKeepAwakeSubtitle, style: small),
              value: settings.keepAwake,
              onChanged: enabled
                  ? (v) => _change(() => _shell.setKeepAwake(v))
                  : null,
            ),
          ],
        );
      },
    );
  }
}
