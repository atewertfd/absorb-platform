import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/libation_import_helper.dart';

/// Key of the search field shown when more than 8 exports are listed.
const libationPickerSearchKey = Key('libationImportPickerSearch');

/// Bottom sheet listing scanned Libation exports, newest first, tagged New or
/// Imported. Resolves to the chosen book, or null when dismissed.
Future<LibationBookCandidate?> showLibationBookPicker(
  BuildContext context,
  List<LibationBookCandidate> candidates, {
  Set<String> importedFolders = const <String>{},
  Set<String> newFolders = const <String>{},
  required String Function(int bytes) formatBytes,
}) {
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;
  final l = AppLocalizations.of(context)!;
  final imported = importedFolders;
  final showSearch = candidates.length > 8;
  var query = '';
  return showModalBottomSheet<LibationBookCandidate>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surfaceContainerHigh,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final needle = query.trim().toLowerCase();
          final visible = needle.isEmpty
              ? candidates
              : candidates
                    .where(
                      (candidate) =>
                          candidate.title.toLowerCase().contains(needle) ||
                          (candidate.author ?? '').toLowerCase().contains(
                            needle,
                          ),
                    )
                    .toList();
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l.libationImportSelectBookTitle,
                                  style: tt.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  l.libationImportSelectBookSubtitle,
                                  style: tt.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: MaterialLocalizations.of(
                              sheetContext,
                            ).closeButtonTooltip,
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    if (showSearch)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: TextField(
                          key: libationPickerSearchKey,
                          decoration: InputDecoration(
                            hintText: l.libationImportSearchHint,
                            prefixIcon: const Icon(Icons.search_rounded),
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (value) =>
                              setSheetState(() => query = value),
                        ),
                      ),
                    const Divider(height: 1),
                    if (visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          l.libationImportNoSearchMatches,
                          textAlign: TextAlign.center,
                          style: tt.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => const Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                          ),
                          itemBuilder: (itemContext, index) {
                            final candidate = visible[index];
                            final key = libationFolderKey(
                              candidate.directoryPath,
                            );
                            final modified = candidate.modified;
                            final details = <String>[
                              if (imported.contains(key))
                                l.libationImportTagImported
                              else if (newFolders.contains(key))
                                l.libationImportTagNew,
                              if (candidate.author != null &&
                                  candidate.author!.isNotEmpty)
                                candidate.author!,
                              if (modified != null)
                                MaterialLocalizations.of(
                                  itemContext,
                                ).formatShortDate(modified.toLocal()),
                              l.adminUploadSelectedFiles(
                                candidate.files.length,
                              ),
                              formatBytes(candidate.totalBytes),
                            ].join(' · ');
                            return ListTile(
                              leading: Icon(
                                Icons.audio_file_rounded,
                                color: cs.primary,
                              ),
                              title: Text(
                                candidate.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                details,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tt.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              onTap: () =>
                                  Navigator.pop(sheetContext, candidate),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
