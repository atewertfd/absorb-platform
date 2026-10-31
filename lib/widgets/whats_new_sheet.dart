import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../build_info.dart';
import '../l10n/app_localizations.dart';
import '../services/player_settings.dart';
import '../services/whats_new_notes.dart';
import '../ui_themes/frosted.dart';
import 'whats_new_prompt.dart';

/// "What's new" inside the app: the release notes of the installed build,
/// as a bottom sheet on phones and a centered dialog on wide windows.
class WhatsNewSheet extends StatefulWidget {
  const WhatsNewSheet({
    super.key,
    required this.version,
    required this.build,
    this.previous,
    this.wide = false,
  });

  /// `1.12.1`, as PackageInfo reports it.
  final String version;

  /// `318`; null when the platform didn't report one.
  final int? build;

  /// The build this one updated from, when known.
  final WhatsNewPrevious? previous;

  /// Dialog layout: buttons side by side, sections in two columns.
  final bool wide;

  /// Narrower windows get the bottom sheet.
  static const wideBreakpoint = 720.0;
  static const _dialogWidth = 640.0;

  @visibleForTesting
  static WhatsNewNotesService Function() notesService = WhatsNewNotesService.new;

  @visibleForTesting
  static Future<bool> Function(Uri url) openExternal =
      (url) => launchUrl(url, mode: LaunchMode.externalApplication);

  /// Opens the notes for [version]+[build].
  static Future<void> show(
    BuildContext context, {
    required String version,
    required int? build,
    WhatsNewPrevious? previous,
  }) {
    final size = MediaQuery.sizeOf(context);
    if (size.width >= wideBreakpoint) {
      return showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
            ),
            child: SizedBox(
              width: _dialogWidth,
              child: FrostedSurface(
                child: WhatsNewSheet(
                  version: version,
                  build: build,
                  previous: previous,
                  wide: true,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      clipBehavior: Clip.antiAlias,
      constraints: BoxConstraints(maxHeight: size.height * 0.86),
      builder: (_) => WhatsNewSheet(
        version: version,
        build: build,
        previous: previous,
      ),
    );
  }

  /// Settings → "See what's new": the notes of the build that's running.
  static Future<void> showForInstalledVersion(BuildContext context) async {
    final info = await PackageInfo.fromPlatform();
    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return;
    await show(
      context,
      version: info.version,
      build: int.tryParse(info.buildNumber),
      previous: WhatsNewHistory.previous(prefs),
    );
  }

  @override
  State<WhatsNewSheet> createState() => _WhatsNewSheetState();
}

class _WhatsNewSheetState extends State<WhatsNewSheet> {
  late final WhatsNewNotesService _service = WhatsNewSheet.notesService();
  WhatsNewLoadResult? _result;
  bool _keepShowing = true;

  String get _tag => widget.build == null
      ? 'v${widget.version}'
      : whatsNewReleaseTag(widget.version, widget.build!);

  Uri get _page => widget.build == null
      ? whatsNewReleasesPage
      : whatsNewReleasePage(_tag);

  @override
  void initState() {
    super.initState();
    _service.load(_tag).then((r) {
      if (mounted) setState(() => _result = r);
    });
    WhatsNewPrompt.isEnabled().then((on) {
      if (mounted) setState(() => _keepShowing = on);
    });
  }

  void _open(Uri url) => WhatsNewSheet.openExternal(url);

  String _fallbackName(AppLocalizations l) {
    final beta = betaNumberFor(widget.version);
    return beta == null ? widget.version : l.betaLabel(beta);
  }

  String? _previousName(AppLocalizations l) {
    final p = widget.previous;
    if (p == null) return null;
    if (p.beta != null) return l.betaLabel(p.beta!);
    if (p.version != null) return p.version;
    if (p.build != null) return l.whatsNewBuildLabel(p.build!);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final notes = _result?.notes;
    final hPad = widget.wide ? 24.0 : 20.0;

    final Widget body;
    if (_result == null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              semanticsLabel: l.whatsNewLoading,
            ),
          ),
        ),
      );
    } else if (notes == null) {
      body = _LoadFailed(onOpen: () => _open(_page));
    } else {
      body = _NotesBody(
        notes: notes,
        wide: widget.wide,
        onOpen: _open,
        fullNotes: () => _open(_page),
      );
    }

    final header = Padding(
      padding: EdgeInsets.fromLTRB(hPad, widget.wide ? 24 : 0, hPad, 12),
      child: _Header(
        title: l.whatsNewSheetTitle(notes?.title ?? _fallbackName(l)),
        versionLabel: widget.build == null
            ? widget.version
            : '${widget.version}+${widget.build}',
        previous: _previousName(l),
      ),
    );
    final bodyPadding = EdgeInsets.fromLTRB(hPad, 4, hPad, 16);
    final footer = _Footer(
      wide: widget.wide,
      padding: hPad,
      // The prompt never runs on web, so its switch would do nothing.
      keepShowing: kIsWeb ? null : _keepShowing,
      onKeepShowing: (v) {
        setState(() => _keepShowing = v);
        WhatsNewPrompt.setEnabled(v);
      },
    );
    final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;

    return LayoutBuilder(builder: (context, c) {
      // Very large text or a short window: header and footer alone could
      // fill the space, so everything scrolls together instead.
      if (textScale > 1.3 || !c.hasBoundedHeight || c.maxHeight < 420) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [header, Padding(padding: bodyPadding, child: body), footer],
          ),
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Flexible(
            child: SingleChildScrollView(padding: bodyPadding, child: body),
          ),
          footer,
        ],
      );
    });
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.versionLabel, this.previous});

  final String title;
  final String versionLabel;
  final String? previous;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l = AppLocalizations.of(context)!;
    final eink = PlayerSettings.einkMode;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            'assets/icon/app_icon.png',
            width: 44,
            height: 44,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => const SizedBox.square(dimension: 44),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: eink ? null : cs.secondaryContainer,
                      border: eink ? Border.all(color: cs.outline) : null,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      versionLabel,
                      style: tt.labelMedium?.copyWith(
                        color: eink ? cs.onSurface : cs.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (previous != null)
                    Text(
                      l.whatsNewUpdatedFrom(previous!),
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded, size: 32, color: cs.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(l.whatsNewLoadFailed,
              textAlign: TextAlign.center, style: tt.titleSmall),
          const SizedBox(height: 4),
          Text(l.whatsNewLoadFailedHint,
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(l.whatsNewOpenGitHub),
          ),
        ],
      ),
    );
  }
}

class _NotesBody extends StatelessWidget {
  const _NotesBody({
    required this.notes,
    required this.wide,
    required this.onOpen,
    required this.fullNotes,
  });

  final WhatsNewNotes notes;
  final bool wide;
  final void Function(Uri) onOpen;
  final VoidCallback fullNotes;

  /// Splits [sections] over two columns of similar height, keeping order.
  static (List<WhatsNewSection>, List<WhatsNewSection>) _balance(
      List<WhatsNewSection> sections) {
    final left = <WhatsNewSection>[], right = <WhatsNewSection>[];
    var lw = 0.0, rw = 0.0;
    for (final s in sections) {
      final w = s.items.length + 1.5; // the heading counts too
      if (lw <= rw) {
        left.add(s);
        lw += w;
      } else {
        right.add(s);
        rw += w;
      }
    }
    return (left, right);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l = AppLocalizations.of(context)!;
    final body = tt.bodyMedium?.copyWith(height: 1.4);

    Widget sectionList(List<WhatsNewSection> list) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final s in list) _Section(section: s, onOpen: onOpen),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notes.intro.isNotEmpty) ...[
          _Highlight(text: notes.intro.first, onOpen: onOpen),
          const SizedBox(height: 12),
        ],
        for (final p in notes.intro.skip(1))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _RichLine(text: p, style: body, onOpen: onOpen),
          ),
        if (notes.sections.isNotEmpty)
          LayoutBuilder(builder: (context, c) {
            if (!wide || notes.sections.length < 2 || c.maxWidth < 520) {
              return sectionList(notes.sections);
            }
            final (left, right) = _balance(notes.sections);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: sectionList(left)),
                const SizedBox(width: 16),
                Expanded(child: sectionList(right)),
              ],
            );
          }),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: fullNotes,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(l.whatsNewFullNotes)),
                const SizedBox(width: 6),
                Icon(Icons.open_in_new_rounded,
                    size: 16,
                    color: PlayerSettings.einkMode ? cs.onSurface : null),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Highlight extends StatelessWidget {
  const _Highlight({required this.text, required this.onOpen});

  final String text;
  final void Function(Uri) onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final eink = PlayerSettings.einkMode;
    final dark = cs.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: eink
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  cs.primary.withValues(alpha: 0.16),
                  cs.tertiary.withValues(alpha: 0.10),
                ],
              ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: eink
              ? cs.outline
              : Colors.white.withValues(alpha: dark ? 0.10 : 0.55),
        ),
      ),
      child: _RichLine(
        text: text,
        style: tt.bodyMedium?.copyWith(height: 1.45, color: cs.onSurface),
        onOpen: onOpen,
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.section, required this.onOpen});

  final WhatsNewSection section;
  final void Function(Uri) onOpen;

  static (Color, IconData) _style(WhatsNewKind kind, ColorScheme cs) {
    final dark = cs.brightness == Brightness.dark;
    return switch (kind) {
      WhatsNewKind.newStuff => (cs.primary, Icons.auto_awesome_rounded),
      // A fixed warm tone: the scheme has no reliably warm role, and the
      // "fixed" heading should read as such in every accent.
      WhatsNewKind.fixed => (
          dark ? const Color(0xFFFFB86B) : const Color(0xFFB45309),
          Icons.build_rounded,
        ),
      WhatsNewKind.faster => (cs.secondary, Icons.bolt_rounded),
      WhatsNewKind.other => (cs.onSurfaceVariant, Icons.label_outline_rounded),
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final eink = PlayerSettings.einkMode;
    var (accent, icon) = _style(section.kind, cs);
    if (eink) accent = cs.onSurface;
    final body = tt.bodyMedium?.copyWith(height: 1.4);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: eink ? null : accent.withValues(alpha: 0.16),
                      border: eink ? Border.all(color: cs.outline) : null,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(icon, size: 14, color: accent),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    section.title.toUpperCase(),
                    style: tt.labelMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final item in section.items)
            Container(
              margin: EdgeInsetsDirectional.only(
                  bottom: 6, start: math.min(item.depth, 2) * 16.0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: eink
                    ? null
                    : cs.surfaceContainerHighest.withValues(alpha: 0.6),
                border: Border.all(
                  color: eink
                      ? cs.outline
                      : cs.outlineVariant.withValues(alpha: 0.35),
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _RichLine(text: item.text, style: body, onOpen: onOpen),
            ),
        ],
      ),
    );
  }
}

/// A line of release-note Markdown as rich text; links open externally.
class _RichLine extends StatefulWidget {
  const _RichLine({required this.text, required this.onOpen, this.style});

  final String text;
  final TextStyle? style;
  final void Function(Uri) onOpen;

  @override
  State<_RichLine> createState() => _RichLineState();
}

class _RichLineState extends State<_RichLine> {
  late List<WhatsNewSpan> _spans;
  final _recognizers = <int, TapGestureRecognizer>{};

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(_RichLine old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _parse();
  }

  void _parse() {
    _disposeRecognizers();
    _spans = parseWhatsNewInline(widget.text);
    for (var i = 0; i < _spans.length; i++) {
      final link = _spans[i].link;
      if (link != null) {
        _recognizers[i] = TapGestureRecognizer()..onTap = () => widget.onOpen(link);
      }
    }
  }

  void _disposeRecognizers() {
    for (final r in _recognizers.values) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final eink = PlayerSettings.einkMode;
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < _spans.length; i++)
            TextSpan(
              text: _spans[i].text,
              recognizer: _recognizers[i],
              style: TextStyle(
                fontWeight: _spans[i].bold ? FontWeight.w700 : null,
                fontStyle: _spans[i].italic ? FontStyle.italic : null,
                fontFamily: _spans[i].code ? 'monospace' : null,
                fontFamilyFallback: _spans[i].code
                    ? const ['Consolas', 'Menlo', 'Roboto Mono', 'monospace']
                    : null,
                backgroundColor: _spans[i].code
                    ? cs.onSurface.withValues(alpha: 0.08)
                    : null,
                color: _spans[i].link != null && !eink ? cs.primary : null,
                decoration:
                    _spans[i].link != null ? TextDecoration.underline : null,
              ),
            ),
        ],
      ),
      style: widget.style,
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.wide,
    required this.padding,
    required this.keepShowing,
    required this.onKeepShowing,
  });

  final bool wide;
  final double padding;

  /// Null hides the switch.
  final bool? keepShowing;
  final ValueChanged<bool> onKeepShowing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    final toggle = keepShowing == null
        ? null
        : SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.whatsNewKeepShowing),
            // Only worth the space once it's off.
            subtitle: keepShowing! ? null : Text(l.whatsNewKeepShowingHint),
            value: keepShowing!,
            onChanged: onKeepShowing,
          );
    final ok = FilledButton(
      autofocus: true,
      onPressed: () => Navigator.of(context).pop(),
      child: Text(l.gotIt),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(padding, 6, padding, 14),
          child: wide
              ? Row(
                  children: [
                    if (toggle != null) Expanded(child: toggle) else const Spacer(),
                    const SizedBox(width: 16),
                    ok,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ?toggle,
                    const SizedBox(height: 6),
                    ok,
                  ],
                ),
        ),
      ),
    );
  }
}
