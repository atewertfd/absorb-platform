import 'dart:io' show File;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../providers/library_provider.dart';
import '../widgets/absorb_page_header.dart';
import '../widgets/absorb_wave_icon.dart';
import '../widgets/absorbing_shared.dart' show CoverPlaceholder;
import '../widgets/collapsible_section.dart';
import '../widgets/cover_decode.dart';
import 'frosted.dart';
import 'ui_theme.dart';
import 'ui_theme_hooks.dart';

/// One of the user's books shown in a look preview.
@immutable
class UiThemePreviewCover {
  const UiThemePreviewCover({this.url, this.title, this.author});

  /// The cover the app shows for the book (network URL or local file path),
  /// or null for the app's generated placeholder.
  final String? url;
  final String? title;
  final String? author;
}

/// The covers a preview shows: the user's own books from [lib] (Continue
/// Listening first, then the other Home shelves), with the same cover URLs
/// and headers the Home screen uses, so they come from the image cache.
/// Empty when the library hasn't loaded (offline, signed out, tests).
({List<UiThemePreviewCover> covers, Map<String, String> headers})
previewCoversFrom(LibraryProvider? lib, {int max = 24}) {
  if (lib == null) return (covers: const [], headers: const {});
  final books = previewBooks(lib.personalizedSections, max: max);
  return (
    covers: [
      for (final b in books)
        UiThemePreviewCover(
          url: lib.getCoverUrl(b.id),
          title: b.title,
          author: b.author,
        ),
    ],
    headers: lib.mediaHeaders,
  );
}

/// Up to [max] distinct books from Home's personalized [sections] (the
/// server's shelf list), Continue Listening first. Non-book entities (series,
/// authors) are skipped.
List<({String id, String? title, String? author})> previewBooks(
  List<dynamic> sections, {
  int max = 12,
}) {
  final ordered = [
    ...sections.where((s) => s is Map && s['id'] == 'continue-listening'),
    ...sections.where((s) => s is Map && s['id'] != 'continue-listening'),
  ];
  final seen = <String>{};
  final books = <({String id, String? title, String? author})>[];
  for (final section in ordered) {
    final entities = (section as Map)['entities'];
    if (entities is! List) continue;
    for (final entity in entities) {
      if (books.length >= max) return books;
      if (entity is! Map) continue;
      final id = entity['id'];
      final media = entity['media'];
      if (id is! String || media is! Map || !seen.add(id)) continue;
      final metadata = media['metadata'];
      books.add((
        id: id,
        title: metadata is Map ? metadata['title'] as String? : null,
        author: metadata is Map ? metadata['authorName'] as String? : null,
      ));
    }
  }
  return books;
}

/// A scaled-down rendering of the app in a look: the real page header, the
/// screens' background glow, a shelf of the user's own covers, a real
/// settings section and the real nav bar, all built from the app's own
/// widgets under the theme the app would have in that look.
///
/// It is laid out at a virtual screen with the current window's aspect ratio
/// (wide window: wide preview; phone: tall) and scaled to fit its width.
/// Non-interactive, no providers, no timers; covers come from the image
/// cache the Home screen already fills.
class UiThemePreview extends StatelessWidget {
  const UiThemePreview({
    super.key,
    required this.look,
    required this.scheme,
    required this.glow,
    this.flat = false,
    this.covers = const [],
    this.coverHeaders = const {},
  });

  /// The look to show.
  final AbsorbLook look;

  /// The colors to show it in (the app's neutral surfaces, chosen accent).
  final ColorScheme scheme;

  /// The user's glow alpha, used when [look] has none.
  final double glow;

  /// Flat background: no glow in any look (as in the app).
  final bool flat;

  /// The user's books for the cover shelf; placeholders fill the rest.
  final List<UiThemePreviewCover> covers;

  /// HTTP headers for the cover URLs (the app's media headers).
  final Map<String, String> coverHeaders;

  /// The virtual screen a preview is laid out at for a [window] size: the
  /// window itself, at least 320 wide, with an aspect ratio kept between
  /// 9:21 and 21:9.
  static Size virtualSizeFor(Size window) {
    if (window.width <= 0 || window.height <= 0) return const Size(390, 844);
    final aspect = (window.width / window.height).clamp(9 / 21, 21 / 9);
    final width = window.width < 320 ? 320.0 : window.width;
    return Size(width, width / aspect);
  }

  /// Themes already built per app base theme, by look and scheme, so
  /// rebuilding a preview doesn't redo [themeForLook].
  static final Expando<Map<(AbsorbLook, ColorScheme), ThemeData>> _themes =
      Expando();

  static ThemeData _themeFor(ThemeData base, AbsorbLook look, ColorScheme cs) {
    final cache = _themes[base] ??= {};
    if (cache.length > 12) cache.clear();
    return cache[(look, cs)] ??= themeForLook(base, look, scheme: cs);
  }

  @override
  Widget build(BuildContext context) {
    final virtual = virtualSizeFor(MediaQuery.sizeOf(context));
    final themed = _themeFor(appBaseTheme(context), look, scheme);
    final media = MediaQuery.of(context).copyWith(
      size: virtual,
      padding: EdgeInsets.zero,
      viewPadding: EdgeInsets.zero,
      viewInsets: EdgeInsets.zero,
    );
    // A picture of the app: no semantics, taps or keyboard focus inside.
    return ExcludeSemantics(
      child: IgnorePointer(
        child: ExcludeFocus(
          child: RepaintBoundary(
            child: AspectRatio(
              key: const ValueKey('ui-preview-frame'),
              aspectRatio: virtual.aspectRatio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.topCenter,
                  child: SizedBox.fromSize(
                    size: virtual,
                    child: MediaQuery(
                      data: media,
                      child: Theme(
                        data: themed,
                        child: _PreviewScreen(
                          glow: glow,
                          flat: flat,
                          covers: covers,
                          coverHeaders: coverHeaders,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The app's Home screen in miniature, built under the preview theme.
class _PreviewScreen extends StatelessWidget {
  const _PreviewScreen({
    required this.glow,
    required this.flat,
    required this.covers,
    required this.coverHeaders,
  });

  final double glow;
  final bool flat;
  final List<UiThemePreviewCover> covers;
  final Map<String, String> coverHeaders;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final width = MediaQuery.sizeOf(context).width;
    // The same background the Home screen paints (home_screen.dart).
    final scaffoldBg = theme.scaffoldBackgroundColor;
    final lowerFade = Color.lerp(cs.surface, scaffoldBg, 0.55) ?? scaffoldBg;
    final coverSize = width < 600 ? 120.0 : 150.0;
    const gap = 12.0;
    final slots = ((width - 40 + gap) / (coverSize + gap)).floor().clamp(1, 12);

    /// A Home shelf: [title], then covers [first].. (placeholders past the
    /// user's books).
    List<Widget> shelf(String title, int first) => [
      const SizedBox(height: 20),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text(
          title,
          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: coverSize,
        child: Row(
          children: [
            const SizedBox(width: 20),
            for (var i = first; i < first + slots; i++) ...[
              if (i > first) const SizedBox(width: gap),
              SizedBox.square(
                dimension: coverSize,
                child: _PreviewCover(
                  cover: i < covers.length ? covers[i] : null,
                  headers: coverHeaders,
                  // Home's decode size for a cover this big, so the
                  // image cache entries are shared.
                  decodeWidth: coverDecodeWidth(
                    width: coverSize,
                    height: coverSize,
                    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ];

    return Material(
      color: scaffoldBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: flat
                  ? const BoxDecoration()
                  : BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.22, 0.72, 1.0],
                        colors: lookBackdrop(context, [
                          cs.primary.withValues(alpha: lookGlow(context, glow)),
                          cs.surface,
                          lowerFade,
                          scaffoldBg,
                        ]),
                      ),
                    ),
              // Built whole (no lazy list) and clipped: what doesn't fit the
              // virtual screen is simply below the fold, as in the app.
              child: SingleChildScrollView(
                primary: false,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AbsorbPageHeader(
                      title: l.homeTitle,
                      actions: [
                        Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
                        Icon(Icons.tune_rounded, color: cs.onSurfaceVariant),
                      ],
                    ),
                    ...shelf(l.continueListening, 0),
                    const SizedBox(height: 20),
                    // Panels right under the first shelf, so even a short,
                    // wide window shows the look's cards.
                    CollapsibleSection(
                      icon: Icons.palette_outlined,
                      title: l.sectionAppearance,
                      cs: cs,
                      children: const [],
                    ),
                    CollapsibleSection(
                      icon: Icons.play_circle_outline_rounded,
                      title: l.appShellAbsorbingTab,
                      cs: cs,
                      children: const [],
                    ),
                    ...shelf(l.recentlyAdded, slots),
                  ],
                ),
              ),
            ),
          ),
          FrostedNavBar(
            child: NavigationBar(
              selectedIndex: 0,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home_rounded),
                  label: l.appShellHomeTab,
                  tooltip: '',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.library_books_outlined),
                  label: l.appShellLibraryTab,
                  tooltip: '',
                ),
                NavigationDestination(
                  icon: AbsorbWaveIcon(color: cs.onSurfaceVariant),
                  label: l.appShellAbsorbingTab,
                  tooltip: '',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.bar_chart_rounded),
                  label: l.appShellStatsTab,
                  tooltip: '',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.settings_outlined),
                  label: l.appShellSettingsTab,
                  tooltip: '',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One shelf cover: the user's cover from the app's image cache, or the
/// app's generated placeholder.
class _PreviewCover extends StatelessWidget {
  const _PreviewCover({
    required this.cover,
    required this.headers,
    required this.decodeWidth,
  });

  final UiThemePreviewCover? cover;
  final Map<String, String> headers;
  final int decodeWidth;

  @override
  Widget build(BuildContext context) {
    final url = cover?.url;
    final placeholder = CoverPlaceholder(
      title: cover?.title,
      author: cover?.author,
    );
    final Widget image;
    if (url == null || url.isEmpty) {
      image = placeholder;
    } else if (url.startsWith('/')) {
      image = kIsWeb
          ? placeholder
          : Image.file(
              File(url),
              fit: BoxFit.cover,
              cacheWidth: decodeWidth,
              errorBuilder: (_, _, _) => placeholder,
            );
    } else {
      image = CachedNetworkImage(
        imageUrl: url,
        httpHeaders: headers,
        fit: BoxFit.cover,
        memCacheWidth: decodeWidth,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholderFadeInDuration: Duration.zero,
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => placeholder,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(lookRadius(context, 8)),
      child: image,
    );
  }
}
