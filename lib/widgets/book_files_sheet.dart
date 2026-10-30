import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/bookorbit_mapper.dart';
import '../services/ebook_cache.dart';
import '../services/narrated_books.dart';
import '../utils/duration_format.dart';
import 'adaptive_modal.dart';
import 'overlay_toast.dart';

enum _FileKind { audio, ebook, other }

class _FileEntry {
  final _FileKind kind;
  final String name;
  final String? path;
  final String? format;
  final String? codec;
  final int? bitRate;
  final int? channels;
  final String? channelLayout;
  final double? duration;
  final int? size;
  final bool readAlong;
  final String? role;

  const _FileEntry({
    required this.kind,
    required this.name,
    this.path,
    this.format,
    this.codec,
    this.bitRate,
    this.channels,
    this.channelLayout,
    this.duration,
    this.size,
    this.readAlong = false,
    this.role,
  });
}

/// A book's files with what the server knows about each: format, codec,
/// bitrate, channels, length and size. BookOrbit keeps no codec or bitrate,
/// so its rows carry format, size and length.
Future<void> showBookFilesSheet(BuildContext context, Map<String, dynamic> item) {
  final entries = _entriesFor(item);
  return showAdaptiveSheetDialog<void>(
    context: context,
    initialChildSize: 0.6,
    minChildSize: 0.4,
    builder: (ctx, scroll) => _BookFilesBody(
      entries: entries,
      bookOrbit: item['bookOrbit'] is Map,
      scroll: scroll,
    ),
  );
}

List<_FileEntry> _entriesFor(Map<String, dynamic> item) {
  final bookOrbit = item['bookOrbit'];
  if (bookOrbit is Map && bookOrbit['files'] is List) {
    return [
      for (final f in (bookOrbit['files'] as List).whereType<Map>()) _bookOrbitEntry(f),
    ];
  }
  final media = item['media'] as Map<String, dynamic>? ?? const {};
  final entries = <_FileEntry>[];
  final seen = <String>{};
  for (final af in (media['audioFiles'] as List<dynamic>? ?? const []).whereType<Map>()) {
    final meta = af['metadata'] as Map? ?? const {};
    seen.add('${af['ino']}');
    entries.add(_FileEntry(
      kind: _FileKind.audio,
      name: '${meta['filename'] ?? af['ino'] ?? ''}',
      path: meta['relPath'] as String? ?? meta['path'] as String?,
      format: (af['format'] as String?) ?? _extOf(meta),
      codec: af['codec'] as String?,
      bitRate: (af['bitRate'] as num?)?.toInt(),
      channels: (af['channels'] as num?)?.toInt(),
      channelLayout: af['channelLayout'] as String?,
      duration: (af['duration'] as num?)?.toDouble(),
      size: (meta['size'] as num?)?.toInt(),
    ));
  }
  final ebook = media['ebookFile'] as Map?;
  if (ebook != null) {
    final meta = ebook['metadata'] as Map? ?? const {};
    seen.add('${ebook['ino']}');
    final id = item['id'];
    entries.add(_FileEntry(
      kind: _FileKind.ebook,
      name: '${meta['filename'] ?? ''}',
      path: meta['relPath'] as String? ?? meta['path'] as String?,
      format: (ebook['ebookFormat'] as String?) ?? _extOf(meta),
      size: (meta['size'] as num?)?.toInt(),
      readAlong: id is String && NarratedBooks.contains(id),
    ));
  }
  for (final lf in (item['libraryFiles'] as List<dynamic>? ?? const []).whereType<Map>()) {
    if (seen.contains('${lf['ino']}')) continue;
    final meta = lf['metadata'] as Map? ?? const {};
    final type = lf['fileType'] as String?;
    if (type == 'audio') continue;
    entries.add(_FileEntry(
      kind: type == 'ebook' ? _FileKind.ebook : _FileKind.other,
      name: '${meta['filename'] ?? ''}',
      path: meta['relPath'] as String? ?? meta['path'] as String?,
      format: _extOf(meta),
      size: (meta['size'] as num?)?.toInt(),
      role: type,
    ));
  }
  return entries;
}

_FileEntry _bookOrbitEntry(Map f) {
  final format = (f['format'] as String?)?.toLowerCase();
  final role = f['role'] as String?;
  final content = role == 'primary' || role == 'content';
  final kind = !content
      ? _FileKind.other
      : BookOrbitMapper.isAudioFormat(format)
          ? _FileKind.audio
          : allEbookFormats.contains(format)
              ? _FileKind.ebook
              : _FileKind.other;
  return _FileEntry(
    kind: kind,
    name: '${f['filename'] ?? ''}',
    path: f['path'] as String?,
    format: format,
    duration: (f['duration'] as num?)?.toDouble(),
    size: (f['size'] as num?)?.toInt(),
    readAlong: f['readAlong'] == true,
    role: content ? null : role,
  );
}

String? _extOf(Map meta) {
  final ext = (meta['ext'] as String?) ?? '';
  final clean = ext.startsWith('.') ? ext.substring(1) : ext;
  return clean.isEmpty ? null : clean;
}

String _size(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1048576) return '${(bytes / 1024).round()} KB';
  if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
}

class _BookFilesBody extends StatelessWidget {
  final List<_FileEntry> entries;
  final bool bookOrbit;
  final ScrollController scroll;

  const _BookFilesBody({required this.entries, required this.bookOrbit, required this.scroll});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final totalSize = entries.fold<int>(0, (sum, e) => sum + (e.size ?? 0));
    final audio = entries.where((e) => e.kind == _FileKind.audio).toList();
    final ebooks = entries.where((e) => e.kind == _FileKind.ebook).toList();
    final other = entries.where((e) => e.kind == _FileKind.other).toList();

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.24),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Text(l.fileInfoTitle, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          [l.fileInfoFileCount(entries.length), if (totalSize > 0) _size(totalSize)].join(' · '),
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        if (entries.isEmpty) ...[
          const SizedBox(height: 24),
          Text(l.fileInfoNone, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        ],
        if (audio.isNotEmpty) ..._section(context, l.fileInfoAudio, audio, shared: _sharedSpecs(context, audio)),
        if (audio.isNotEmpty && bookOrbit)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(l.fileInfoBookOrbitNote, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
        if (ebooks.isNotEmpty) ..._section(context, l.fileInfoEbook, ebooks),
        if (other.isNotEmpty) ..._section(context, l.fileInfoOther, other),
      ],
    );
  }

  /// Specs every audio file shares, shown once above the list instead of on
  /// each of a few dozen tracks.
  List<String> _sharedSpecs(BuildContext context, List<_FileEntry> audio) {
    if (audio.length < 2) return const [];
    final first = _specs(context, audio.first, withLength: false);
    return [
      for (final spec in first)
        if (audio.every((e) => _specs(context, e, withLength: false).contains(spec))) spec,
    ];
  }

  List<String> _specs(BuildContext context, _FileEntry e, {bool withLength = true}) {
    final l = AppLocalizations.of(context)!;
    final codec = e.codec?.toUpperCase();
    final format = e.format?.toUpperCase();
    final layout = e.channelLayout?.trim();
    return [
      if (format != null && format.isNotEmpty) format,
      if (codec != null && codec.isNotEmpty && codec != format) codec,
      if ((e.bitRate ?? 0) > 0) l.kbpsValue((e.bitRate! / 1000).round()),
      if (layout != null && layout.isNotEmpty)
        layout[0].toUpperCase() + layout.substring(1)
      else if ((e.channels ?? 0) > 0)
        l.fileInfoChannels(e.channels!),
      if (withLength && (e.duration ?? 0) > 0) formatHm(e.duration!),
      if (withLength && (e.size ?? 0) > 0) _size(e.size!),
    ];
  }

  List<Widget> _section(BuildContext context, String title, List<_FileEntry> files, {List<String> shared = const []}) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return [
      const SizedBox(height: 20),
      Row(children: [
        Text(title, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        if (files.length > 1) ...[
          const SizedBox(width: 8),
          Text('${files.length}', style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ]),
      if (shared.isNotEmpty) ...[
        const SizedBox(height: 8),
        _SpecWrap(specs: shared),
      ],
      const SizedBox(height: 8),
      for (final f in files) _FileTile(entry: f, specs: _specs(context, f).where((s) => !shared.contains(s)).toList()),
    ];
  }
}

class _SpecWrap extends StatelessWidget {
  final List<String> specs;
  final bool readAlong;
  const _SpecWrap({required this.specs, this.readAlong = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l = AppLocalizations.of(context)!;
    Widget chip(Widget child) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(6),
          ),
          child: child,
        );
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final s in specs) chip(Text(s, style: tt.labelSmall)),
      if (readAlong)
        chip(Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.headphones_rounded, size: 12, color: cs.primary),
          const SizedBox(width: 4),
          Text(l.readAlong, style: tt.labelSmall?.copyWith(color: cs.primary)),
        ])),
    ]);
  }
}

class _FileTile extends StatelessWidget {
  final _FileEntry entry;
  final List<String> specs;
  const _FileTile({required this.entry, required this.specs});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l = AppLocalizations.of(context)!;
    final icon = switch (entry.kind) {
      _FileKind.audio => Icons.audio_file_rounded,
      _FileKind.ebook => Icons.menu_book_rounded,
      _FileKind.other => entry.role == 'cover' || entry.role == 'image' ? Icons.image_rounded : Icons.insert_drive_file_rounded,
    };
    final path = entry.path;
    final roleLabel = switch (entry.role) {
      'cover' => l.fileInfoCover,
      'metadata' => l.fileInfoMetadata,
      'supplement' => l.fileInfoSupplement,
      _ => null,
    };
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onLongPress: path == null || path.isEmpty
          ? null
          : () async {
              await Clipboard.setData(ClipboardData(text: path));
              if (context.mounted) {
                showOverlayToast(context, l.fileInfoPathCopied, icon: Icons.content_copy_rounded);
              }
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 20, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.name.isEmpty ? '-' : entry.name,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
              if (path != null && path.isNotEmpty && path != entry.name) ...[
                const SizedBox(height: 2),
                Text(path,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              if (specs.isNotEmpty || entry.readAlong || roleLabel != null) ...[
                const SizedBox(height: 6),
                _SpecWrap(specs: [?roleLabel, ...specs], readAlong: entry.readAlong),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
