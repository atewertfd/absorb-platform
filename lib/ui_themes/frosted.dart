import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'ui_theme.dart';

/// The Frosted look's theme-level pieces: [frostedThemeData] (cards, sheets,
/// dialogs, nav bar colors), [absorbLookBuilder] (applies it app-wide), and
/// the two blur wrappers used by single hooks ([FrostedNavBar],
/// [FrostedSurface]).
///
/// Performance rules: blur only behind a few large surfaces (nav bar, desktop
/// dialogs), never per list item, and never on web (tint only there: web
/// backdrop blur is expensive and inconsistent across renderers).

/// Test override for [frostBlurSupported]'s web check.
@visibleForTesting
bool? debugFrostIsWebOverride;

/// Whether a real backdrop blur may be used on this platform.
bool frostBlurSupported() => !(debugFrostIsWebOverride ?? kIsWeb);

/// [base] with the look's surface tokens applied. Returns [base] unchanged
/// when the look keeps upstream's surfaces (Absorb Plus, Classic, e-ink).
///
/// Only theme defaults change, so widgets that pass their own colors keep
/// them. Menus, popups, snack bars and the ColorScheme surfaces stay opaque:
/// they are drawn over arbitrary content with no barrier or blur behind.
ThemeData frostedThemeData(ThemeData base) {
  final look = base.extension<AbsorbLook>();
  if (look == null || !look.changesSurfaces) return base;
  final cs = base.colorScheme;
  final edge = BorderSide(color: look.panelEdge(cs.brightness));
  final boost = look.cornerRadiusBoost;
  final sheetAlpha = look.sheetFillAlpha;
  var data = base;

  final panel = look.panelFill();
  if (panel != null) {
    data = data.copyWith(
      cardTheme: base.cardTheme.copyWith(
        color: panel,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16 + boost),
          side: edge,
        ),
      ),
    );
  }

  if (look.frostedSheets && sheetAlpha != null) {
    final sheetBase =
        base.bottomSheetTheme.backgroundColor ?? cs.surfaceContainerLow;
    final sheet = sheetBase.withValues(alpha: sheetAlpha);
    data = data.copyWith(
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: sheet,
        modalBackgroundColor: sheet,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24 + boost)),
          side: edge,
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: (base.dialogTheme.backgroundColor ??
                cs.surfaceContainerHigh)
            .withValues(alpha: sheetAlpha),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28 + boost),
          side: edge,
        ),
      ),
    );
  }

  if (look.frostedNavBar && sheetAlpha != null) {
    final navBase =
        base.navigationBarTheme.backgroundColor ?? base.scaffoldBackgroundColor;
    // The bar sits outside the page, over the plain scaffold, so give it the
    // accent tint the screens get instead of a see-through it can't have.
    final accentTint = look.backdropTint;
    final tinted = (accentTint > 0
            ? Color.alphaBlend(
                base.colorScheme.primary.withValues(alpha: accentTint),
                navBase,
              )
            : navBase)
        .withValues(alpha: sheetAlpha);
    data = data.copyWith(
      navigationBarTheme: base.navigationBarTheme.copyWith(
        backgroundColor: panel == null ? tinted : Color.alphaBlend(panel, tinted),
      ),
    );
  }
  return data;
}

/// `MaterialApp.builder` hook: applies [frostedThemeData] above the navigator
/// so every route, dialog and sheet sees it. The tree shape never changes
/// with the look (no navigator remount when switching looks).
Widget absorbLookBuilder(BuildContext context, Widget? child) => Theme(
  data: frostedThemeData(Theme.of(context)),
  child: child ?? const SizedBox.shrink(),
);

/// Wraps the bottom nav bar: in Frosted, a light top edge over the bar's
/// translucent tint (the color comes from [frostedThemeData]); otherwise it
/// paints nothing extra. No blur: pages don't extend under the bar, so there
/// is nothing behind it to frost, and blurring it every frame would cost
/// rendering time for no visible change.
class FrostedNavBar extends StatelessWidget {
  const FrostedNavBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final look = AbsorbLook.of(context);
    final frosted = look.frostedNavBar;
    // Same widget shape in every look, so switching never remounts the bar.
    return DecoratedBox(
      decoration: frosted
          ? BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: look.panelEdge(Theme.of(context).brightness),
                ),
              ),
            )
          : const BoxDecoration(),
      child: child,
    );
  }
}

/// A backdrop blur for content inside an already clipped, translucent
/// surface (e.g. a [Dialog] with `clipBehavior` set). Blurs only in looks
/// with frosted sheets, and never on web.
class FrostedSurface extends StatelessWidget {
  const FrostedSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final look = AbsorbLook.of(context);
    final sigma = look.panelBlurSigma;
    return BackdropFilter(
      enabled: look.frostedSheets && sigma > 0 && frostBlurSupported(),
      filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    );
  }
}

/// A sheet or dialog background: translucent in looks with frosted sheets
/// (pair it with [FrostedSurface] inside a clipped surface), else [opaque].
Color lookSheetColor(BuildContext context, Color opaque) {
  final look = AbsorbLook.of(context);
  final alpha = look.sheetFillAlpha;
  if (!look.frostedSheets || alpha == null) return opaque;
  return opaque.withValues(alpha: alpha * opaque.a);
}
