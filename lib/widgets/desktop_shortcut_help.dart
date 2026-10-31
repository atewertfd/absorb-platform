import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/desktop_shortcuts.dart';
import '../utils/fork_platform.dart';

/// One row of the keyboard-shortcuts help: what it does and its keys.
class DesktopShortcutHelpEntry {
  const DesktopShortcutHelpEntry(this.description, this.keys);
  final String description;
  final String keys;
}

String desktopShortcutDescription(
  AppLocalizations l,
  DesktopShortcutAction action,
) =>
    switch (action) {
      DesktopShortcutAction.playPause => l.desktopShortcutPlayPause,
      DesktopShortcutAction.rewind => l.desktopShortcutRewind,
      DesktopShortcutAction.forward => l.desktopShortcutForward,
      DesktopShortcutAction.slower => l.desktopShortcutSlower,
      DesktopShortcutAction.faster => l.desktopShortcutFaster,
      DesktopShortcutAction.normalSpeed => l.desktopShortcutNormalSpeed,
      DesktopShortcutAction.search => l.desktopShortcutSearch,
      DesktopShortcutAction.library => l.desktopShortcutLibrary,
      DesktopShortcutAction.nowPlaying => l.desktopShortcutNowPlaying,
      DesktopShortcutAction.fullScreen => l.desktopShortcutFullScreen,
    };

String desktopNavigationDescription(
  AppLocalizations l,
  DesktopNavigationAction action,
) =>
    switch (action) {
      DesktopNavigationAction.closePlayer => l.desktopShortcutClosePlayer,
      DesktopNavigationAction.back => l.desktopShortcutBack,
      DesktopNavigationAction.refresh => l.desktopShortcutRefresh,
      DesktopNavigationAction.previousCard => l.desktopShortcutPreviousCard,
      DesktopNavigationAction.nextCard => l.desktopShortcutNextCard,
    };

/// Every shortcut this platform has, in table order. Keys bound to the same
/// action share a row ("F5 / Ctrl+R"); mouse extras come last.
List<DesktopShortcutHelpEntry> desktopShortcutHelpEntries(AppLocalizations l) {
  final entries = <DesktopShortcutHelpEntry>[
    for (final shortcut in desktopShortcutDefinitions)
      DesktopShortcutHelpEntry(
        desktopShortcutDescription(l, shortcut.action),
        shortcut.label,
      ),
  ];
  final navigation = desktopNavigationShortcuts;
  final keysByAction = <DesktopNavigationAction, List<String>>{};
  for (final shortcut in navigation) {
    keysByAction.putIfAbsent(shortcut.action, () => []).add(shortcut.label);
  }
  if (keysByAction.containsKey(DesktopNavigationAction.back)) {
    keysByAction[DesktopNavigationAction.back]!.add(l.desktopShortcutMouseBack);
  }
  for (final MapEntry(key: action, value: keys) in keysByAction.entries) {
    entries.add(DesktopShortcutHelpEntry(
      desktopNavigationDescription(l, action),
      keys.join(' / '),
    ));
  }
  if (ForkPlatform.isDesktop) {
    entries.add(DesktopShortcutHelpEntry(
      l.desktopShortcutContextMenu,
      l.desktopShortcutRightClick,
    ));
    entries.add(DesktopShortcutHelpEntry(
      l.desktopShortcutDragShelves,
      l.desktopShortcutMouseDrag,
    ));
  }
  return entries;
}

/// The rows of the keyboard-shortcuts dialog, ready to drop into it.
class DesktopShortcutHelpList extends StatelessWidget {
  const DesktopShortcutHelpList({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final keyStyle = TextStyle(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w700,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in desktopShortcutHelpEntries(l))
          Semantics(
            label: '${entry.description}, ${entry.keys}',
            child: ListTile(
              dense: true,
              title: Text(entry.description),
              trailing: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(entry.keys,
                    style: keyStyle, textAlign: TextAlign.end),
              ),
            ),
          ),
      ],
    );
  }
}
