import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../widgets/theme_presets.dart';
import 'ui_theme.dart';
import 'ui_theme_appearance.dart';
import 'ui_theme_preview.dart';

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

/// What the picker returns when finished with Done.
@immutable
class UiThemePickerResult {
  const UiThemePickerResult(this.theme, this.color);

  final AppUiTheme theme;
  final AppColorChoice color;
}

abstract final class UiThemePicker {
  /// Opens the two-step picker (look, then color) with the current settings
  /// selected. Returns the choices made with Done, or null when dismissed.
  static Future<UiThemePickerResult?> show(
    BuildContext context, {
    UiThemeAppearance appearance = const AppUiThemeAppearance(),
  }) {
    return showDialog<UiThemePickerResult>(
      context: context,
      builder: (_) => UiThemePickerDialog(
        initial: currentUiTheme,
        appearance: appearance,
      ),
    );
  }

  /// Asks once per device, after the main screen is up. Finishing saves the
  /// look and color; dismissing keeps both but still counts as chosen, so
  /// the question doesn't come back every launch.
  static Future<void> showIfUnchosen(
    BuildContext context, {
    Duration delay = const Duration(milliseconds: 600),
    UiThemeAppearance appearance = const AppUiThemeAppearance(),
  }) async {
    if (!await UiThemeStore.needsChoice()) return;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (!context.mounted) return;
    final picked = await show(context, appearance: appearance);
    await UiThemeStore.choose(picked?.theme ?? currentUiTheme);
    if (picked != null) await _saveColor(picked.color, appearance);
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
    if (picked.theme != uiThemeNotifier.value) {
      await UiThemeStore.choose(picked.theme);
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
    this.appearance = const AppUiThemeAppearance(),
  });

  final AppUiTheme initial;
  final UiThemeAppearance appearance;

  @override
  State<UiThemePickerDialog> createState() => _UiThemePickerDialogState();
}

class _UiThemePickerDialogState extends State<UiThemePickerDialog> {
  late AppUiTheme _theme = widget.initial;
  late AppColorChoice _color = widget.appearance.currentColor;
  bool _colorStep = false;

  late final List<ThemePreset> _presets = [
    for (final id in kUiThemePickerPresetIds)
      ...kThemePresets.where((p) => p.id == id),
  ];

  /// The preset swatches, plus the user's own manual color when it isn't one.
  List<Color> get _swatches {
    final colors = [for (final p in _presets) p.color];
    final own = widget.appearance.currentColor.seed;
    if (own != null &&
        !colors.any((c) => c.toARGB32() == own.toARGB32())) {
      colors.insert(0, own);
    }
    return colors;
  }

  ColorScheme _scheme(BuildContext context) {
    final base = Theme.of(context).colorScheme;
    return previewScheme(base, _color.seed ?? widget.appearance.coverSeed);
  }

  Widget _preview(BuildContext context, AppUiTheme theme) {
    final brightness = Theme.of(context).brightness;
    return UiThemePreview(
      look: theme.lookFor(brightness),
      scheme: _scheme(context),
      glow: widget.appearance.userGlow,
      flat: widget.appearance.flat,
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
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              intro,
              const SizedBox(height: 16),
              if (_colorStep) ..._colorStepChildren(context, l) else ...[
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
                  UiThemePickerResult(_theme, _color),
                ),
                child: Text(l.done),
              ),
            ]
          : [
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
      Center(
        child: SizedBox(
          key: const ValueKey('ui-color-preview'),
          width: 120,
          child: _preview(context, _theme),
        ),
      ),
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
                  color: ThemeData.estimateBrightnessForColor(color) ==
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

/// The Settings > Appearance row: the active look's name, tap to change it.
/// [onChanged] runs after the picker saved a change, so Settings can reload
/// the color controls it shows.
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
    return ValueListenableBuilder<AppUiTheme?>(
      valueListenable: uiThemeNotifier,
      builder: (context, theme, _) => InkWell(
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
    );
  }
}
