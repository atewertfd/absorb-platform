import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// The "Import Libation exports" guide on the upload screen: how-to text,
/// file/folder pickers, scan progress, new-download and duplicate notices,
/// and (on desktop) the optional Libation launcher and output-folder buttons.
///
/// Pure UI: every action is a callback owned by the upload screen.
class LibationImportCard extends StatelessWidget {
  static const guideKey = Key('libationImportGuide');
  static const reviewNewKey = Key('libationImportReviewNew');
  static const filesKey = Key('libationImportFiles');
  static const folderKey = Key('libationImportFolder');
  static const scanProgressKey = Key('libationImportScanProgress');
  static const duplicateWarningKey = Key('libationImportDuplicateWarning');
  static const launchKey = Key('libationImportLaunch');
  static const setAppKey = Key('libationImportSetApp');
  static const scanOutputFolderKey = Key('libationImportScanOutputFolder');
  static const setOutputFolderKey = Key('libationImportSetOutputFolder');

  final bool initiallyExpanded;
  final bool busy;
  final bool scanning;
  final int newExportCount;
  final String? duplicateTitle;
  final bool showDesktopControls;
  final VoidCallback onChooseFiles;
  final VoidCallback onChooseFolder;
  final VoidCallback onReviewNew;
  final VoidCallback onLaunch;
  final VoidCallback onSetApp;
  final VoidCallback onScanOutputFolder;
  final VoidCallback onSetOutputFolder;

  const LibationImportCard({
    super.key,
    required this.initiallyExpanded,
    required this.busy,
    required this.scanning,
    required this.newExportCount,
    required this.duplicateTitle,
    required this.showDesktopControls,
    required this.onChooseFiles,
    required this.onChooseFolder,
    required this.onReviewNew,
    required this.onLaunch,
    required this.onSetApp,
    required this.onScanOutputFolder,
    required this.onSetOutputFolder,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l = AppLocalizations.of(context)!;
    return ExpansionTile(
      key: guideKey,
      initiallyExpanded: initiallyExpanded,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(top: 8),
      shape: const Border(),
      collapsedShape: const Border(),
      leading: Icon(Icons.drive_folder_upload_outlined, color: cs.primary),
      title: Text(
        l.libationImportTitle,
        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        newExportCount > 0
            ? l.libationImportNewReady(newExportCount)
            : l.libationImportSubtitle,
        style: tt.bodySmall?.copyWith(
          color: newExportCount > 0 ? cs.primary : cs.onSurfaceVariant,
        ),
      ),
      children: [
        if (newExportCount > 0) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              key: reviewNewKey,
              onPressed: busy ? null : onReviewNew,
              icon: const Icon(Icons.new_releases_outlined, size: 18),
              label: Text(l.libationImportReviewNew),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(l.libationImportSteps, style: tt.bodyMedium),
        const SizedBox(height: 12),
        Text(
          l.libationImportPrivacy,
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: filesKey,
                onPressed: busy ? null : onChooseFiles,
                icon: const Icon(Icons.audio_file_outlined, size: 18),
                label: Text(l.libationImportChooseFiles),
              ),
              OutlinedButton.icon(
                key: folderKey,
                onPressed: busy ? null : onChooseFolder,
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: Text(l.libationImportChooseFolder),
              ),
            ],
          ),
        ),
        if (scanning) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(key: scanProgressKey),
        ],
        if (duplicateTitle != null) ...[
          const SizedBox(height: 12),
          Row(
            key: duplicateWarningKey,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, size: 18, color: cs.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.libationImportAlreadyInLibrary(duplicateTitle!),
                  style: tt.bodySmall?.copyWith(color: cs.error),
                ),
              ),
            ],
          ),
        ],
        if (showDesktopControls) ...[
          const SizedBox(height: 12),
          Text(
            l.libationImportDesktopHint,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: launchKey,
                  onPressed: busy ? null : onLaunch,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(l.libationImportLaunchApp),
                ),
                OutlinedButton.icon(
                  key: setAppKey,
                  onPressed: busy ? null : onSetApp,
                  icon: const Icon(
                    Icons.settings_applications_outlined,
                    size: 18,
                  ),
                  label: Text(l.libationImportSetApp),
                ),
                OutlinedButton.icon(
                  key: scanOutputFolderKey,
                  onPressed: busy ? null : onScanOutputFolder,
                  icon: const Icon(Icons.library_music_outlined, size: 18),
                  label: Text(l.libationImportScanOutputFolder),
                ),
                OutlinedButton.icon(
                  key: setOutputFolderKey,
                  onPressed: busy ? null : onSetOutputFolder,
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  label: Text(l.libationImportSetOutputFolder),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
