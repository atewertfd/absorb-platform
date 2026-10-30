import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'ui_theme.dart';
import 'ui_theme_picker.dart' show uiThemeName;

/// "Try it": a look applied to the whole running app without saving it,
/// through [uiThemePreviewNotifier]. A small bar ([UiThemeTryOutLayer]) lets
/// the user keep it or go back while they move around the real app.

/// How a live preview ended.
enum UiThemeTryOutOutcome {
  /// The previewed look was saved ("Keep").
  kept,

  /// The preview was dropped and the saved look is back ("Go back").
  wentBack,

  /// Something else ended it, e.g. a look was saved from the picker again.
  ended,
}

abstract final class UiThemeTryOut {
  static Completer<UiThemeTryOutOutcome>? _session;
  static UiThemeTryOutOutcome? _pendingOutcome;

  /// Set while [keep] is saving, so a Go back tap in that moment can't
  /// report "went back" for a look that is being saved.
  static bool _keeping = false;

  /// The look being previewed, or null.
  static AppUiTheme? get previewing => uiThemePreviewNotifier.value;

  /// Shows [theme] (with Frosted's [glass] strength) app-wide without saving
  /// it. Completes when the preview ends: [keep], [goBack], or any saved
  /// look ([UiThemeStore.choose]). Starting another preview ends this one as
  /// [UiThemeTryOutOutcome.ended], leaving the new preview up.
  static Future<UiThemeTryOutOutcome> start(
    AppUiTheme theme, {
    GlassStrength? glass,
  }) {
    _finish(UiThemeTryOutOutcome.ended);
    final session = Completer<UiThemeTryOutOutcome>();
    _session = session;
    // Before listening: only the look clearing ends a session.
    glassStrengthPreviewNotifier.value = glass ?? savedGlassStrength;
    uiThemePreviewNotifier.addListener(_onPreviewChanged);
    uiThemePreviewNotifier.value = theme;
    return session.future;
  }

  /// Saves the previewed look and glass the same way the picker does,
  /// ending the preview. If saving fails, the preview ends and the saved
  /// look comes back.
  static Future<void> keep() async {
    final theme = previewing;
    if (theme == null || _keeping) return;
    final glass = glassStrengthPreviewNotifier.value;
    _keeping = true;
    _pendingOutcome = UiThemeTryOutOutcome.kept;
    try {
      await UiThemeStore.choose(theme, glass: glass);
      // choose() already cleared the preview; this is a safety net.
      if (_session != null) end(UiThemeTryOutOutcome.kept);
    } catch (e) {
      debugPrint('[UiTheme] keeping $theme failed: $e');
      end(UiThemeTryOutOutcome.ended);
    } finally {
      _keeping = false;
    }
  }

  /// Drops the preview; the saved look comes back. Ignored while [keep] is
  /// saving.
  static void goBack() {
    if (_keeping) return;
    end(UiThemeTryOutOutcome.wentBack);
  }

  /// Clears the preview and completes the session with [outcome].
  static void end(UiThemeTryOutOutcome outcome) {
    _pendingOutcome = outcome;
    uiThemePreviewNotifier.value = null;
    glassStrengthPreviewNotifier.value = null;
    _finish(outcome);
  }

  static void _onPreviewChanged() {
    if (uiThemePreviewNotifier.value != null) return;
    _finish(_pendingOutcome ?? UiThemeTryOutOutcome.ended);
  }

  static void _finish(UiThemeTryOutOutcome outcome) {
    uiThemePreviewNotifier.removeListener(_onPreviewChanged);
    _pendingOutcome = null;
    final session = _session;
    _session = null;
    if (session != null && !session.isCompleted) session.complete(outcome);
  }
}

/// Stacks the preview bar over [child] (the navigator) while a look is being
/// tried. Always the same tree shape, so the navigator is never remounted.
class UiThemeTryOutLayer extends StatelessWidget {
  const UiThemeTryOutLayer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        ValueListenableBuilder<AppUiTheme?>(
          valueListenable: uiThemePreviewNotifier,
          builder: (context, theme, _) => theme == null
              ? const SizedBox.shrink()
              : UiThemeTryOutBar(theme: theme),
        ),
      ],
    );
  }
}

/// The floating "Previewing <look>" bar with Keep and Go back. It sits just
/// above the bottom nav bar (never over its taps), centered and compact, in
/// the inverse colors so it reads in every look, including e-ink.
class UiThemeTryOutBar extends StatelessWidget {
  const UiThemeTryOutBar({super.key, required this.theme});

  final AppUiTheme theme;

  /// Material 3's nav bar height: the bar floats above it.
  static const double navBarHeight = 80;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final bottom = MediaQuery.paddingOf(context).bottom + navBarHeight + 12;
    return Positioned(
      left: 12,
      right: 12,
      bottom: bottom,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Material(
            key: const ValueKey('ui-try-bar'),
            color: cs.inverseSurface,
            elevation: 6,
            shadowColor: Colors.black54,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.visibility_outlined,
                    size: 18,
                    color: cs.onInverseSurface,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l.uiThemePreviewing(uiThemeName(l, theme)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onInverseSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: UiThemeTryOut.goBack,
                    style: TextButton.styleFrom(
                      foregroundColor: cs.onInverseSurface,
                    ),
                    child: Text(l.uiThemeGoBack),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: UiThemeTryOut.keep,
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.inversePrimary,
                      foregroundColor: cs.inverseSurface,
                    ),
                    child: Text(l.uiThemeKeep),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
