import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/library_provider.dart';
import '../widgets/theme_presets.dart';
import 'ui_theme.dart';
import 'ui_theme_appearance.dart';
import 'ui_theme_preview.dart';
import 'ui_theme_try.dart';

/// The display name of a look.
String uiThemeName(AppLocalizations l, AppUiTheme theme) => switch (theme) {
  AppUiTheme.plus => l.uiThemePlusName,
  AppUiTheme.classic => l.uiThemeClassicName,
  AppUiTheme.frosted => l.uiThemeFrostedName,
};

/// The one-line description of a look.
String uiThemeDescription(AppLocalizations l, AppUiTheme theme) =>
    switch (theme) {
      AppUiTheme.plus => l.uiThemePlusDescription,
      AppUiTheme.classic => l.uiThemeClassicDescription,
      AppUiTheme.frosted => l.uiThemeFrostedDescription,
    };

/// The fixed colors offered in the picker's color step: a spread of the
/// Settings presets (the full list and the custom wheel stay in Settings).
const List<String> kUiThemePickerPresetIds = [
  'tincture',
  'soak',
  'wavelength',
  'chlorophyll',
  'eventHorizon',
  'saturate',
];

/// The display name of a glass strength.
String glassStrengthName(AppLocalizations l, GlassStrength glass) =>
    switch (glass) {
      GlassStrength.light => l.uiThemeGlassLight,
      GlassStrength.medium => l.uiThemeGlassMedium,
      GlassStrength.strong => l.uiThemeGlassStrong,
    };

/// What the picker returns when finished with Done (or "Try it").
@immutable
class UiThemePickerResult {
  const UiThemePickerResult(
    this.theme,
    this.color, {
    this.glass = kDefaultGlassStrength,
    this.tryLive = false,
  });

  final AppUiTheme theme;
  final AppColorChoice color;

  /// Frosted's glass strength as left in the picker.
  final GlassStrength glass;

  /// The dialog closed to try [theme] live in the app ("Try it").
  final bool tryLive;
}

abstract final class UiThemePicker {
  /// Opens the two-step picker (look, then color) with the current settings
  /// selected. Returns the choices made with Done, or null when dismissed.
  ///
  /// "Try it" closes the picker and shows the highlighted look (and glass
  /// strength) app-wide without saving it ([UiThemeTryOut]). Keep saves it
  /// and returns it here with the color picked so far; Go back restores the
  /// saved look and reopens the picker on the tried look, glass and color.
  /// A preview ended any other way (e.g. a newer "Try it") returns null.
  static Future<UiThemePickerResult?> show(
    BuildContext context, {
    UiThemeAppearance appearance = const AppUiThemeAppearance(),
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    var initial = currentUiTheme;
    var initialGlass = currentGlassStrength;
    var initialColor = appearance.currentColor;
    while (true) {
      final host = context.mounted
          ? context
          : (navigator.mounted ? navigator.context : null);
      if (host == null) return null;
      final picked = await showDialog<UiThemePickerResult>(
        context: host,
        builder: (_) => UiThemePickerDialog(
          initial: initial,
          initialGlass: initialGlass,
          initialColor: initialColor,
          appearance: appearance,
        ),
      );
      if (picked == null || !picked.tryLive) return picked;
      switch (await UiThemeTryOut.start(picked.theme, glass: picked.glass)) {
        case UiThemeTryOutOutcome.kept:
          return UiThemePickerResult(
            picked.theme,
            picked.color,
            glass: picked.glass,
          );
        case UiThemeTryOutOutcome.wentBack:
          initial = picked.theme;
          initialGlass = picked.glass;
          initialColor = picked.color;
        case UiThemeTryOutOutcome.ended:
          return null;
      }
    }
  }

  /// Asks once per device, after the main screen is up. Finishing saves the
  /// look, glass and color; dismissing keeps all of them but still counts as
  /// chosen, so the question doesn't come back every launch. Being dismissed
  /// never ends a live preview another picker started meanwhile.
  static Future<void> showIfUnchosen(
    BuildContext context, {
    Duration delay = const Duration(milliseconds: 600),
    UiThemeAppearance appearance = const AppUiThemeAppearance(),
  }) async {
    if (!await UiThemeStore.needsChoice()) return;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (!context.mounted) return;
    final picked = await show(context, appearance: appearance);
    if (picked == null) {
      await UiThemeStore.markChosen();
      return;
    }
    await UiThemeStore.choose(picked.theme, glass: picked.glass);
    await _saveColor(picked.color, appearance);
  }

  /// Opens the picker from Settings; dismissing changes nothing. [onChanged]
  /// runs after a change was saved (Settings reloads its color controls).
  static Future<void> changeFromSettings(
    BuildContext context, {
    UiThemeAppearance appearance = const AppUiThemeAppearance(),
    VoidCallback? onChanged,
  }) async {
    final picked = await show(context, appearance: appearance);
    if (picked == null) return;
    // A look still being tried elsewhere ends here too (choose clears it).
    if (picked.theme != uiThemeNotifier.value ||
        picked.glass != savedGlassStrength ||
        uiThemePreviewNotifier.value != null) {
      await UiThemeStore.choose(picked.theme, glass: picked.glass);
    }
    await _saveColor(picked.color, appearance);
    onChanged?.call();
  }

  static Future<void> _saveColor(
    AppColorChoice color,
    UiThemeAppearance appearance,
  ) async {
    if (color != appearance.currentColor) await appearance.saveColor(color);
  }
}

class UiThemePickerDialog extends StatefulWidget {
  const UiThemePickerDialog({
    super.key,
    required this.initial,
    this.initialGlass,
    this.initialColor,
    this.appearance = const AppUiThemeAppearance(),
  });

  final AppUiTheme initial;

  /// The glass strength selected at first; the active one when null.
  final GlassStrength? initialGlass;

  /// The color selected at first; the current setting when null.
  final AppColorChoice? initialColor;
  final UiThemeAppearance appearance;

  @override
  State<UiThemePickerDialog> createState() => _UiThemePickerDialogState();
}

class _UiThemePickerDialogState extends State<UiThemePickerDialog> {
  late AppUiTheme _theme = widget.initial;
  late GlassStrength _glass = widget.initialGlass ?? currentGlassStrength;
  late AppColorChoice _color =
      widget.initialColor ?? widget.appearance.currentColor;
  bool _colorStep = false;

  late final List<ThemePreset> _presets = [
    for (final id in kUiThemePickerPresetIds)
      ...kThemePresets.where((p) => p.id == id),
  ];

  /// The preset swatches, plus the user's own manual color when it isn't one.
  List<Color> get _swatches {
    final colors = [for (final p in _presets) p.color];
    final own = widget.appearance.currentColor.seed;
    if (own != null && !colors.any((c) => c.toARGB32() == own.toARGB32())) {
      colors.insert(0, own);
    }
    return colors;
  }

  /// The user's own books for the previews, read once (no listening).
  late final ({List<UiThemePreviewCover> covers, Map<String, String> headers})
  _covers = previewCoversFrom(
    Provider.of<LibraryProvider?>(context, listen: false),
  );

  /// The last preview scheme, kept while the base scheme and seed stay the
  /// same ([ColorScheme.fromSeed] is not cheap).
  ({ColorScheme base, int seed, ColorScheme scheme})? _schemeMemo;

  ColorScheme _scheme(BuildContext context) {
    final base = Theme.of(context).colorScheme;
    final seed = (_color.seed ?? widget.appearance.coverSeed).toARGB32();
    final memo = _schemeMemo;
    if (memo != null && memo.seed == seed && identical(memo.base, base)) {
      return memo.scheme;
    }
    final scheme = previewScheme(base, Color(seed));
    _schemeMemo = (base: base, seed: seed, scheme: scheme);
    return scheme;
  }

  /// Built previews by look and scheme. Reusing the same widget lets Flutter
  /// skip rebuilding a preview whose look didn't change (e.g. the other
  /// cards when one is tapped).
  final Map<(AbsorbLook, ColorScheme), Widget> _previews = {};

  Widget _preview(BuildContext context, AppUiTheme theme) {
    final look = theme.lookFor(
      Theme.of(context).brightness,
      eink: widget.appearance.eink,
      glass: _glass,
    );
    final scheme = _scheme(context);
    if (_previews.length > 12) _previews.clear();
    return _previews[(look, scheme)] ??= UiThemePreview(
      look: look,
      scheme: scheme,
      glow: widget.appearance.userGlow,
      flat: widget.appearance.flat,
      covers: _covers.covers,
      coverHeaders: _covers.headers,
    );
  }

  /// Rough height of everything in the dialog besides its previews and
  /// choices (icon, title, intro, description, buttons, padding, insets).
  /// Measured at about 410 at phone width and 345 in the wide dialog, where
  /// the intro and description wrap to fewer lines.
  double _dialogChrome(BuildContext context) =>
      _dialogWidth(context) > 440 ? 360 : 410;

  /// The Glass row shown under the look cards for Frosted (gap included).
  /// Reserved for every look, so the large preview keeps its size when
  /// another look is highlighted.
  static const double _glassRowHeight = 44;

  /// The width the dialog's content asks for: wider for landscape previews so
  /// they stay legible.
  double _dialogWidth(BuildContext context) {
    final window = MediaQuery.sizeOf(context);
    final wide = UiThemePreview.virtualSizeFor(window).aspectRatio > 1;
    return wide ? (window.width - 160).clamp(440.0, 760.0) : 440;
  }

  /// The height of a look card at the dialog's actual width.
  double _cardHeight(BuildContext context) {
    final window = MediaQuery.sizeOf(context);
    // AlertDialog insets (40 a side) and content padding (24 a side).
    final width = math.min(_dialogWidth(context), window.width - 128);
    final cards = AppUiTheme.values.length;
    final cardWidth = (width - 10 * (cards - 1)) / cards;
    final aspect = UiThemePreview.virtualSizeFor(window).aspectRatio;
    // Padding, gap and a name that may wrap to two lines on narrow cards.
    return (cardWidth - 16) / aspect + 66;
  }

  /// The highlighted look, large, in the room the window has left once
  /// [reserved] (the step's other content) and the dialog fit: at most 40% of
  /// the window's height. Null (no large preview) when less than [minHeight]
  /// is left, unless [always], which shows it at [minHeight] instead.
  Widget? _largePreview(
    BuildContext context,
    Key key, {
    required double reserved,
    double minHeight = 140,
    bool always = false,
  }) {
    final windowHeight = MediaQuery.sizeOf(context).height;
    final room = math.min(
      windowHeight - reserved - _dialogChrome(context),
      windowHeight * 0.4,
    );
    if (room < minHeight && !always) return null;
    return Center(
      child: ConstrainedBox(
        key: key,
        constraints: BoxConstraints(maxHeight: math.max(room, minHeight)),
        child: _preview(context, _theme),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final intro = Text(
      _colorStep ? l.uiThemeColorIntro : l.uiThemePickerIntro,
      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
    );
    return AlertDialog(
      icon: Icon(
        _colorStep ? Icons.palette_outlined : Icons.style_outlined,
        color: cs.primary,
      ),
      title: Text(_colorStep ? l.uiThemeColorTitle : l.uiThemePickerTitle),
      content: SizedBox(
        width: _dialogWidth(context),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              intro,
              const SizedBox(height: 16),
              if (_colorStep)
                ..._colorStepChildren(context, l)
              else ...[
                if (_largePreview(
                      context,
                      const ValueKey('ui-look-preview'),
                      reserved: _cardHeight(context) + 14 + _glassRowHeight,
                    )
                    case final large?) ...[
                  large,
                  const SizedBox(height: 14),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final theme in AppUiTheme.values) ...[
                      if (theme != AppUiTheme.values.first)
                        const SizedBox(width: 10),
                      Expanded(
                        child: _LookOption(
                          key: ValueKey('ui-look-${theme.id}'),
                          name: uiThemeName(l, theme),
                          preview: _preview(context, theme),
                          selected: theme == _theme,
                          onTap: () => setState(() => _theme = theme),
                        ),
                      ),
                    ],
                  ],
                ),
                if (_theme == AppUiTheme.frosted) ...[
                  const SizedBox(height: 12),
                  GlassStrengthControl(
                    key: const ValueKey('ui-picker-glass'),
                    value: _glass,
                    onChanged: (glass) => setState(() => _glass = glass),
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  uiThemeDescription(l, _theme),
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: _colorStep
          ? [
              TextButton(
                onPressed: () => setState(() => _colorStep = false),
                child: Text(l.uiThemeBack),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  UiThemePickerResult(_theme, _color, glass: _glass),
                ),
                child: Text(l.done),
              ),
            ]
          : [
              TextButton.icon(
                key: const ValueKey('ui-try-it'),
                onPressed: () => Navigator.pop(
                  context,
                  UiThemePickerResult(
                    _theme,
                    _color,
                    glass: _glass,
                    tryLive: true,
                  ),
                ),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: Text(l.uiThemeTryIt),
              ),
              FilledButton(
                onPressed: () => setState(() => _colorStep = true),
                child: Text(l.uiThemeContinue),
              ),
            ],
    );
  }

  List<Widget> _colorStepChildren(BuildContext context, AppLocalizations l) {
    final cs = Theme.of(context).colorScheme;
    return [
      // The color chips take about 130 px; the preview is always shown here.
      _largePreview(
        context,
        const ValueKey('ui-color-preview'),
        reserved: 130,
        always: true,
      )!,
      const SizedBox(height: 16),
      Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          ChoiceChip(
            key: const ValueKey('ui-color-cover'),
            avatar: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: Text(l.uiThemeColorFromCover),
            selected: _color.fromCover,
            onSelected: (_) =>
                setState(() => _color = const AppColorChoice.fromCover()),
          ),
          for (final color in _swatches)
            _ColorSwatch(
              key: ValueKey('ui-color-${color.toARGB32()}'),
              color: color,
              label: _presets
                  .where((p) => p.color.toARGB32() == color.toARGB32())
                  .map((p) => p.name)
                  .firstOrNull,
              selected: _color.seed?.toARGB32() == color.toARGB32(),
              outline: cs.outlineVariant,
              ring: cs.onSurface,
              onTap: () => setState(() => _color = AppColorChoice.fixed(color)),
            ),
        ],
      ),
    ];
  }
}

class _LookOption extends StatelessWidget {
  const _LookOption({
    super.key,
    required this.name,
    required this.preview,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final Widget preview;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected
            ? cs.primaryContainer.withValues(alpha: 0.35)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: Column(
              children: [
                preview,
                const SizedBox(height: 8),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: tt.titleSmall?.copyWith(
                    color: selected ? cs.primary : cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    super.key,
    required this.color,
    required this.label,
    required this.selected,
    required this.outline,
    required this.ring,
    required this.onTap,
  });

  final Color color;
  final String? label;
  final bool selected;
  final Color outline;
  final Color ring;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final swatch = Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? ring : outline,
              width: selected ? 3 : 1,
            ),
          ),
          child: selected
              ? Icon(
                  Icons.check_rounded,
                  size: 18,
                  color:
                      ThemeData.estimateBrightnessForColor(color) ==
                          Brightness.dark
                      ? Colors.white
                      : Colors.black,
                )
              : null,
        ),
      ),
    );
    return label == null ? swatch : Tooltip(message: label, child: swatch);
  }
}

/// "Glass" with a Light / Medium / Strong choice, for Frosted.
class GlassStrengthControl extends StatelessWidget {
  const GlassStrengthControl({
    super.key,
    required this.value,
    required this.onChanged,
    this.labelStyle,
  });

  final GlassStrength value;
  final ValueChanged<GlassStrength> onChanged;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Text(l.uiThemeGlass, style: labelStyle ?? tt.titleSmall),
        const SizedBox(width: 12),
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: SegmentedButton<GlassStrength>(
                expandedInsets: EdgeInsets.zero,
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                segments: [
                  for (final glass in GlassStrength.values)
                    ButtonSegment(
                      value: glass,
                      // Scales down instead of wrapping in a narrow dialog.
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          glassStrengthName(l, glass),
                          key: ValueKey('ui-glass-${glass.id}'),
                          maxLines: 1,
                        ),
                      ),
                    ),
                ],
                selected: {value},
                onSelectionChanged: (s) => onChanged(s.single),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The Settings > Appearance row: the active look's name, tap to change it.
/// In Frosted it also offers the glass strength, applied and saved right
/// away. [onChanged] runs after the picker saved a change, so Settings can
/// reload the color controls it shows.
class UiThemeSettingsTile extends StatelessWidget {
  const UiThemeSettingsTile({
    super.key,
    this.onChanged,
    this.appearance = const AppUiThemeAppearance(),
  });

  final VoidCallback? onChanged;
  final UiThemeAppearance appearance;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // uiThemeNotifier also notifies on saved glass changes.
    return ValueListenableBuilder<AppUiTheme?>(
      valueListenable: uiThemeNotifier,
      builder: (context, theme, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => UiThemePicker.changeFromSettings(
              context,
              appearance: appearance,
              onChanged: onChanged,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  Expanded(child: Text(l.uiThemeLabel, style: tt.titleSmall)),
                  Text(
                    uiThemeName(l, theme ?? kDefaultUiTheme),
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
          if (theme == AppUiTheme.frosted)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: GlassStrengthControl(
                key: const ValueKey('ui-settings-glass'),
                value: savedGlassStrength,
                onChanged: (glass) {
                  UiThemeStore.chooseGlass(glass).catchError((Object e) {
                    debugPrint('[UiTheme] saving glass failed: $e');
                  });
                },
              ),
            ),
        ],
      ),
    );
  }
}
