import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// In-app release notes ("What's new"): fetching a fork release's notes from
/// GitHub, caching them for offline reopening, and parsing their Markdown into
/// a small model the What's new sheet renders.

/// The fork's GitHub repo. Same repo as [UpdateCheckerService] uses.
const whatsNewRepo = 'atewertfd/absorb-plus';

/// The release page for [tag], for "Full notes on GitHub".
Uri whatsNewReleasePage(String tag) =>
    Uri.parse('https://github.com/$whatsNewRepo/releases/tag/$tag');

/// The releases list, when there's no usable tag.
final Uri whatsNewReleasesPage =
    Uri.parse('https://github.com/$whatsNewRepo/releases');

// ------------------------------------------------------------------ model

enum WhatsNewKind { newStuff, fixed, faster, other }

/// A run of inline text with its Markdown styling.
@immutable
class WhatsNewSpan {
  const WhatsNewSpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.code = false,
    this.link,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool code;

  /// Only http(s) links are kept; anything else stays plain text.
  final Uri? link;

  @override
  String toString() =>
      'WhatsNewSpan("$text"${bold ? ', bold' : ''}${italic ? ', italic' : ''}'
      '${code ? ', code' : ''}${link != null ? ', $link' : ''})';
}

/// One bullet (or loose paragraph) of a section. [depth] > 0 for bullets
/// nested under another bullet.
@immutable
class WhatsNewItem {
  const WhatsNewItem(this.text, {this.depth = 0});

  /// Still holds inline Markdown; see [parseWhatsNewInline].
  final String text;
  final int depth;
}

@immutable
class WhatsNewSection {
  const WhatsNewSection(this.title, this.kind, this.items);

  /// Plain text (inline Markdown removed).
  final String title;
  final WhatsNewKind kind;
  final List<WhatsNewItem> items;
}

@immutable
class WhatsNewNotes {
  const WhatsNewNotes({this.title, this.intro = const [], this.sections = const []});

  /// `Beta 11` from a `## Beta 11` heading or the release name; null if
  /// neither has one (the sheet then shows the version).
  final String? title;

  /// Paragraphs before the first section, still holding inline Markdown.
  final List<String> intro;
  final List<WhatsNewSection> sections;

  bool get isEmpty => intro.isEmpty && sections.isEmpty;
}

// ----------------------------------------------------------------- parser

final _heading = RegExp(r'^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$');
final _bullet = RegExp(r'^(\s*)(?:[-*+]|\d{1,3}[.)])\s+(.*)$');
final _betaInName = RegExp(r'\bBeta\s+\d+\b', caseSensitive: false);
final _newWords = RegExp(r'\b(new|looks?|features?)\b', caseSensitive: false);
final _fixWords = RegExp(r'\bfix', caseSensitive: false);
final _fasterWords =
    RegExp(r'\b(faster|smoother|lighter|performance)\b', caseSensitive: false);
final _downloadWords = RegExp(r'download', caseSensitive: false);

/// The section kind for a `###` title, by keyword.
WhatsNewKind whatsNewKindFor(String title) {
  if (_newWords.hasMatch(title)) return WhatsNewKind.newStuff;
  if (_fixWords.hasMatch(title)) return WhatsNewKind.fixed;
  if (_fasterWords.hasMatch(title)) return WhatsNewKind.faster;
  return WhatsNewKind.other;
}

/// Parses a fork release body. Never throws: anything it can't structure
/// ends up as intro text.
WhatsNewNotes parseWhatsNewNotes(String body, {String? releaseName}) {
  try {
    return _parse(body, releaseName);
  } catch (e) {
    debugPrint('[WhatsNew] Could not parse release notes: $e');
    final text = body.trim();
    return WhatsNewNotes(
      title: _titleFromName(releaseName),
      intro: text.isEmpty ? const [] : [text],
    );
  }
}

String? _titleFromName(String? name) {
  final n = name?.trim();
  if (n == null || n.isEmpty) return null;
  return _betaInName.firstMatch(n)?.group(0) ?? n;
}

WhatsNewNotes _parse(String body, String? releaseName) {
  final lines = body.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  String? title;
  final intro = <String>[];
  final sections = <WhatsNewSection>[];

  // The section being filled; null while still in the intro.
  String? sectionTitle;
  List<WhatsNewItem>? items;
  final para = <String>[]; // loose lines of the current paragraph
  var lastWasBullet = false; // a following plain line continues the bullet

  void flushPara() {
    if (para.isEmpty) return;
    final text = para.join(' ');
    para.clear();
    if (items == null) {
      intro.add(text);
    } else {
      items!.add(WhatsNewItem(text));
    }
  }

  void closeSection() {
    flushPara();
    final t = sectionTitle, list = items;
    if (t != null && list != null && list.isNotEmpty && !_downloadWords.hasMatch(t)) {
      sections.add(WhatsNewSection(t, whatsNewKindFor(t), List.unmodifiable(list)));
    }
    sectionTitle = null;
    items = null;
  }

  for (final raw in lines) {
    final line = raw.trimRight();
    final trimmed = line.trim();
    if (trimmed == '---') break; // footer: source commit, checksums
    if (trimmed.isEmpty) {
      flushPara();
      lastWasBullet = false;
      continue;
    }
    if (trimmed.startsWith('<!--') && trimmed.endsWith('-->')) continue;

    final h = _heading.firstMatch(line);
    if (h != null) {
      final level = h.group(1)!.length;
      final text = whatsNewPlainText(h.group(2)!).trim();
      lastWasBullet = false;
      if (level <= 2 && title == null && items == null) {
        flushPara();
        if (text.isNotEmpty) title = text;
        continue;
      }
      closeSection();
      if (text.isEmpty) continue;
      sectionTitle = text;
      items = <WhatsNewItem>[];
      continue;
    }

    final b = _bullet.firstMatch(line);
    if (b != null) {
      flushPara();
      final indent = b.group(1)!.replaceAll('\t', '    ').length;
      final text = b.group(2)!.trim();
      if (text.isEmpty) continue;
      if (items == null) {
        intro.add(text); // a list before any section reads as intro lines
      } else {
        items!.add(WhatsNewItem(text, depth: indent >= 2 ? 1 : 0));
      }
      lastWasBullet = true;
      continue;
    }

    // A plain line right under a bullet continues that bullet.
    if (lastWasBullet) {
      if (items != null && items!.isNotEmpty) {
        final last = items!.removeLast();
        items!.add(WhatsNewItem('${last.text} $trimmed', depth: last.depth));
        continue;
      }
      if (items == null && intro.isNotEmpty) {
        intro.add('${intro.removeLast()} $trimmed');
        continue;
      }
    }
    para.add(trimmed);
  }
  closeSection();

  return WhatsNewNotes(
    title: title != null && _betaInName.hasMatch(title)
        ? title
        : (_titleFromName(releaseName) ?? title),
    intro: List.unmodifiable(intro),
    sections: List.unmodifiable(sections),
  );
}

// Order matters: code first (its content is literal), then links, bold,
// italic, bare URLs.
final _inline = RegExp(
  r'`([^`]+)`'
  r'|!?\[([^\]]+)\]\(\s*([^)\s]+)\s*\)'
  r'|\*\*(.+?)\*\*|__(.+?)__'
  r'|(?<![*\w])\*(?![\s*])([^*]+?)\*(?!\*)'
  r'|(https?://[^\s<>()\[\]]+)',
);

/// Splits a line of release-note Markdown into styled runs.
List<WhatsNewSpan> parseWhatsNewInline(String text) {
  try {
    final out = <WhatsNewSpan>[];
    _inlineInto(out, text, bold: false, italic: false);
    return out;
  } catch (_) {
    return [WhatsNewSpan(text)];
  }
}

/// [text] with its inline Markdown removed.
String whatsNewPlainText(String text) =>
    parseWhatsNewInline(text).map((s) => s.text).join();

Uri? _safeLink(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) return null;
  return uri;
}

void _inlineInto(List<WhatsNewSpan> out, String text,
    {required bool bold, required bool italic}) {
  var pos = 0;
  void plain(String s) {
    if (s.isNotEmpty) out.add(WhatsNewSpan(s, bold: bold, italic: italic));
  }

  for (final m in _inline.allMatches(text)) {
    plain(text.substring(pos, m.start));
    pos = m.end;
    if (m.group(1) != null) {
      out.add(WhatsNewSpan(m.group(1)!, bold: bold, italic: italic, code: true));
    } else if (m.group(2) != null) {
      final label = whatsNewPlainText(m.group(2)!);
      out.add(WhatsNewSpan(label,
          bold: bold, italic: italic, link: _safeLink(m.group(3)!)));
    } else if (m.group(4) != null || m.group(5) != null) {
      _inlineInto(out, m.group(4) ?? m.group(5)!, bold: true, italic: italic);
    } else if (m.group(6) != null) {
      _inlineInto(out, m.group(6)!, bold: bold, italic: true);
    } else {
      // Bare URL: sentence punctuation after it isn't part of it.
      var url = m.group(7)!;
      final tail = RegExp(r'[.,;:!?]+$').firstMatch(url);
      final rest = tail == null ? '' : tail.group(0)!;
      url = url.substring(0, url.length - rest.length);
      out.add(WhatsNewSpan(url, bold: bold, italic: italic, link: _safeLink(url)));
      plain(rest);
    }
  }
  plain(text.substring(pos));
}

// --------------------------------------------------------- fetch + cache

/// A release's notes as GitHub returns them.
@immutable
class WhatsNewRelease {
  const WhatsNewRelease(this.body, {this.name});

  final String body;
  final String? name;
}

/// Returns the release for a tag, null when there is none (404), or throws
/// when GitHub can't be reached.
typedef WhatsNewFetcher = Future<WhatsNewRelease?> Function(String tag);

enum WhatsNewSource { network, cache }

@immutable
class WhatsNewLoadResult {
  const WhatsNewLoadResult(this.notes, this.source);
  const WhatsNewLoadResult.failed()
      : notes = null,
        source = null;

  final WhatsNewNotes? notes;
  final WhatsNewSource? source;

  bool get failed => notes == null;
}

class WhatsNewNotesService {
  WhatsNewNotesService({WhatsNewFetcher? fetch, http.Client? client})
      : _fetch = fetch ?? _githubFetcher(client);

  /// Device-wide: the notes don't depend on the account.
  static const cacheKey = 'fork_whats_new_notes_cache';

  /// Releases kept in the cache, newest first.
  static const cacheLimit = 5;

  final WhatsNewFetcher _fetch;

  static WhatsNewFetcher _githubFetcher(http.Client? client) => (tag) async {
        final uri = Uri.parse(
            'https://api.github.com/repos/$whatsNewRepo/releases/tags/${Uri.encodeComponent(tag)}');
        const headers = {'Accept': 'application/vnd.github.v3+json'};
        final response = await (client != null
                ? client.get(uri, headers: headers)
                : http.get(uri, headers: headers))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 404) return null;
        if (response.statusCode != 200) {
          throw http.ClientException('GitHub returned ${response.statusCode}', uri);
        }
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return WhatsNewRelease(
          json['body'] as String? ?? '',
          name: json['name'] as String?,
        );
      };

  /// The notes for [tag]: fresh from GitHub when it answers, else the last
  /// copy fetched on this device, else [WhatsNewLoadResult.failed].
  Future<WhatsNewLoadResult> load(String tag) async {
    try {
      final release = await _fetch(tag);
      if (release != null) {
        await _store(tag, release);
        return WhatsNewLoadResult(
          parseWhatsNewNotes(release.body, releaseName: release.name),
          WhatsNewSource.network,
        );
      }
      debugPrint('[WhatsNew] No release for $tag');
    } catch (e) {
      debugPrint('[WhatsNew] Could not fetch notes for $tag: $e');
    }
    final cached = await cachedRelease(tag);
    if (cached == null) return const WhatsNewLoadResult.failed();
    return WhatsNewLoadResult(
      parseWhatsNewNotes(cached.body, releaseName: cached.name),
      WhatsNewSource.cache,
    );
  }

  static Future<List<Map<String, dynamic>>> _readCache(SharedPreferences prefs) async {
    final raw = prefs.getString(cacheKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>().toList();
    } catch (_) {
      return [];
    }
  }

  /// The cached release for [tag], if any.
  static Future<WhatsNewRelease?> cachedRelease(String tag) async {
    final prefs = await SharedPreferences.getInstance();
    for (final e in await _readCache(prefs)) {
      if (e['tag'] == tag && e['body'] is String) {
        return WhatsNewRelease(e['body'] as String, name: e['name'] as String?);
      }
    }
    return null;
  }

  static Future<void> _store(String tag, WhatsNewRelease release) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = (await _readCache(prefs))..removeWhere((e) => e['tag'] == tag);
      list.insert(0, {'tag': tag, 'body': release.body, 'name': release.name});
      await prefs.setString(cacheKey, jsonEncode(list.take(cacheLimit).toList()));
    } catch (e) {
      debugPrint('[WhatsNew] Could not cache notes: $e');
    }
  }
}

// ------------------------------------------------------ installed history

/// The build that was installed before this one, for "Updated from Beta 10".
@immutable
class WhatsNewPrevious {
  const WhatsNewPrevious({this.version, this.build, this.beta});

  final String? version;
  final int? build;
  final int? beta;
}

/// Remembers the installed build so the sheet can say what it updated from.
/// Device-wide, like the prompt's own last-build key.
class WhatsNewHistory {
  static const installedKey = 'fork_whats_new_installed';
  static const previousKey = 'fork_whats_new_previous';

  static Map<String, dynamic>? _read(SharedPreferences prefs, String key) {
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static WhatsNewPrevious? _from(Map<String, dynamic>? m) {
    if (m == null) return null;
    final p = WhatsNewPrevious(
      version: m['version'] as String?,
      build: (m['build'] as num?)?.toInt(),
      beta: (m['beta'] as num?)?.toInt(),
    );
    return p.version == null && p.build == null ? null : p;
  }

  /// Records [version]+[build] (beta [beta], null for a stable build) as
  /// installed. When the build changed, the old one becomes the previous
  /// build; [lastBuild] (the prompt's older record) fills in on the first
  /// launch after this history existed.
  static Future<WhatsNewPrevious?> record(
    SharedPreferences prefs, {
    required String version,
    required int build,
    int? beta,
    int? lastBuild,
  }) async {
    final installed = _read(prefs, installedKey);
    final installedBuild = (installed?['build'] as num?)?.toInt();
    if (installed != null && installedBuild != build) {
      await prefs.setString(previousKey, jsonEncode(installed));
    } else if (installed == null && lastBuild != null && lastBuild != build) {
      await prefs.setString(previousKey, jsonEncode({'build': lastBuild}));
    }
    if (installedBuild != build) {
      await prefs.setString(
          installedKey, jsonEncode({'version': version, 'build': build, 'beta': beta}));
    }
    return previous(prefs);
  }

  static WhatsNewPrevious? previous(SharedPreferences prefs) =>
      _from(_read(prefs, previousKey));
}
