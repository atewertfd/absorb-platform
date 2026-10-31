import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/desktop_download_folder.dart';
import '../services/download_service.dart';
import '../utils/fork_platform.dart';
import 'overlay_toast.dart';

/// Download location sheet for Windows and Linux (Absorb Plus).
///
/// The Android sheet in Settings uses the system folder picker (SAF), which
/// doesn't exist on desktop and failed with "Cannot write to folder". This one
/// picks a plain folder, checks it can be written to, shows the real path and
/// can open it in Explorer. Only new downloads use a newly picked folder;
/// existing downloads stay where they are.
class DesktopDownloadFolderSheet extends StatefulWidget {
  const DesktopDownloadFolderSheet({
    super.key,
    required this.service,
    required this.onLabelChanged,
  });

  final DownloadService service;

  /// Called with the new location label after the folder changes.
  final ValueChanged<String> onLabelChanged;

  static Future<void> show(
    BuildContext context, {
    required ValueChanged<String> onLabelChanged,
    DownloadService? service,
  }) {
    final cs = Theme.of(context).colorScheme;
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: cs.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DesktopDownloadFolderSheet(
        service: service ?? DownloadService(),
        onLabelChanged: onLabelChanged,
      ),
    );
  }

  @override
  State<DesktopDownloadFolderSheet> createState() =>
      _DesktopDownloadFolderSheetState();
}

class _DesktopDownloadFolderSheetState
    extends State<DesktopDownloadFolderSheet> {
  String? _path; // shown path; null while loading
  bool _busy = false;

  DownloadService get _dl => widget.service;
  bool get _isCustom =>
      DesktopDownloadFolder.activeRoot(_dl.desktopDownloadDir) != null;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final label = await _dl.downloadLocationLabel;
    if (!mounted) return;
    setState(() => _path = label);
  }

  Future<void> _choose() async {
    final l = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      String? picked;
      try {
        picked = await DesktopDownloadFolder.pick(
          title: l.chooseDownloadFolder,
          initialDirectory: _dl.desktopDownloadDir,
        );
      } catch (e) {
        debugPrint('[DesktopDownloadFolderSheet] folder picker failed: $e');
        if (mounted) {
          showOverlayToast(
            context,
            l.desktopDownloadFolderPickFailed,
            icon: Icons.error_outline_rounded,
          );
        }
        return;
      }
      if (picked == null || picked.trim().isEmpty || !mounted) return;
      if (!await DesktopDownloadFolder.isWritable(picked)) {
        if (mounted) {
          showOverlayToast(
            context,
            l.desktopDownloadFolderNotWritable,
            icon: Icons.error_outline_rounded,
          );
        }
        return;
      }
      await _dl.setDesktopDownloadDir(picked);
      final label = await _dl.downloadLocationLabel;
      widget.onLabelChanged(label);
      if (!mounted) return;
      setState(() => _path = label);
      showOverlayToast(
        context,
        l.downloadLocationSetTo(label),
        icon: Icons.folder_outlined,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final l = AppLocalizations.of(context)!;
    await _dl.setDesktopDownloadDir(null);
    final label = await _dl.downloadLocationLabel;
    widget.onLabelChanged(label);
    if (!mounted) return;
    setState(() => _path = label);
    showOverlayToast(
      context,
      l.resetToDefaultStorage,
      icon: Icons.restart_alt_rounded,
    );
  }

  Future<void> _open() async {
    final l = AppLocalizations.of(context)!;
    final folder =
        DesktopDownloadFolder.activeRoot(_dl.desktopDownloadDir) ??
        await _dl.defaultDesktopDownloadDir;
    final ok = await DesktopDownloadFolder.open(folder);
    if (!ok && mounted) {
      showOverlayToast(
        context,
        l.desktopDownloadFolderOpenFailed,
        icon: Icons.error_outline_rounded,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hasExistingDownloads = _dl.downloadedItems.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l.downloadLocationSheetTitle,
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              l.downloadLocationSheetSubtitle,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.folder_rounded, color: cs.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.currentLocation,
                          style: tt.labelSmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        SelectableText(
                          _path ?? '',
                          key: const ValueKey('desktop-download-path'),
                          style: tt.bodySmall?.copyWith(color: cs.onSurface),
                        ),
                        if (_path != null && !_isCustom) ...[
                          const SizedBox(height: 2),
                          Text(
                            l.desktopDownloadFolderDefault,
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (hasExistingDownloads)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.error.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: cs.error,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l.existingDownloadsWarning,
                          style: tt.bodySmall?.copyWith(
                            color: cs.error.withValues(alpha: 0.8),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.folder_open_rounded),
                label: Text(l.chooseFolder),
                onPressed: _busy ? null : _choose,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(
                  ForkPlatform.isWindows
                      ? l.desktopDownloadFolderOpen
                      : l.desktopDownloadFolderOpenLinux,
                ),
                onPressed: _path == null ? null : _open,
              ),
            ),
            if (_isCustom) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: Text(l.resetToDefault),
                  onPressed: _busy ? null : _reset,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
