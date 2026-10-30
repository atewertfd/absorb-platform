import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'ui_theme.dart';

/// The display name of a look.
String uiThemeName(AppLocalizations l, AppUiTheme theme) => switch (theme) {
  AppUiTheme.plus => l.uiThemePlusName,
  AppUiTheme.classic => l.uiThemeClassicName,
};

/// The one-line description of a look.
String uiThemeDescription(AppLocalizations l, AppUiTheme theme) =>
    switch (theme) {
      AppUiTheme.plus => l.uiThemePlusDescription,
      AppUiTheme.classic => l.uiThemeClassicDescription,
    };

abstract final class UiThemePicker {
  /// Opens the picker with [currentUiTheme] selected. Returns the look picked
  /// with Continue, or null when the dialog was dismissed.
  static Future<AppUiTheme?> show(BuildContext context) {
    return showDialog<AppUiTheme>(
      context: context,
      builder: (_) => UiThemePickerDialog(initial: currentUiTheme),
    );
  }

  /// Asks once per device, after the main screen is up. Picking a look saves
  /// it; dismissing keeps the current look but still counts as chosen, so the
  /// question doesn't come back every launch.
  static Future<void> showIfUnchosen(
    BuildContext context, {
    Duration delay = const Duration(milliseconds: 600),
  }) async {
    if (!await UiThemeStore.needsChoice()) return;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (!context.mounted) return;
    final picked = await show(context);
    await UiThemeStore.choose(picked ?? currentUiTheme);
  }

  /// Opens the picker from Settings; dismissing changes nothing.
  static Future<void> changeFromSettings(BuildContext context) async {
    final picked = await show(context);
    if (picked != null && picked != uiThemeNotifier.value) {
      await UiThemeStore.choose(picked);
    }
  }
}

class UiThemePickerDialog extends StatefulWidget {
  const UiThemePickerDialog({super.key, required this.initial});

  final AppUiTheme initial;

  @override
  State<UiThemePickerDialog> createState() => _UiThemePickerDialogState();
}

class _UiThemePickerDialogState extends State<UiThemePickerDialog> {
  late AppUiTheme _selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return AlertDialog(
      icon: Icon(Icons.style_outlined, color: cs.primary),
      title: Text(l.uiThemePickerTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.uiThemePickerIntro,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              for (final theme in AppUiTheme.values) ...[
                _UiThemeOption(
                  name: uiThemeName(l, theme),
                  description: uiThemeDescription(l, theme),
                  selected: theme == _selected,
                  onTap: () => setState(() => _selected = theme),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: Text(l.uiThemeContinue),
        ),
      ],
    );
  }
}

class _UiThemeOption extends StatelessWidget {
  const _UiThemeOption({
    required this.name,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(
        color: selected ? cs.primary : cs.outlineVariant,
        width: selected ? 2 : 1,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected
            ? cs.primaryContainer.withValues(alpha: 0.35)
            : Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: tt.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
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

/// The Settings > Appearance row: the active look's name, tap to change it.
class UiThemeSettingsTile extends StatelessWidget {
  const UiThemeSettingsTile({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ValueListenableBuilder<AppUiTheme?>(
      valueListenable: uiThemeNotifier,
      builder: (context, theme, _) => InkWell(
        onTap: () => UiThemePicker.changeFromSettings(context),
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
