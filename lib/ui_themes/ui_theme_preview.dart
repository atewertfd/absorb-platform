import 'package:flutter/material.dart';

import 'ui_theme.dart';

/// A small live phone mock of a look, drawn by the app with that look's
/// tokens and a color scheme: header, two covers, a panel and a nav bar. No
/// images, no blur (cheap enough for several on screen at once).
class UiThemePreview extends StatelessWidget {
  const UiThemePreview({
    super.key,
    required this.look,
    required this.scheme,
    required this.glow,
    this.flat = false,
  });

  /// The look to draw.
  final AbsorbLook look;

  /// The colors to draw it in (neutral surfaces, chosen accent).
  final ColorScheme scheme;

  /// The user's glow alpha, used when [look] has none.
  final double glow;

  /// Flat background: no glow in any look (as in the app).
  final bool flat;

  /// The canvas the mock is drawn on before scaling to fit.
  static const Size canvas = Size(120, 214);

  @override
  Widget build(BuildContext context) {
    final cs = scheme;
    final dark = cs.brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF0E0E0E) : const Color(0xFFF6F6F6);
    final glowAlpha = flat ? 0.0 : (look.glowStrength ?? glow);
    final boost = look.cornerRadiusBoost / 2;
    final panelFill = look.panelFill() ?? cs.surfaceContainerHigh;
    final edge = look.frostedPanels
        ? Border.all(color: look.panelEdge(cs.brightness))
        : null;
    final navBase = dark ? const Color(0xFF0E0E0E) : cs.surface;
    final navFill = look.frostedNavBar
        ? Color.alphaBlend(
            look.panelFill() ?? Colors.transparent,
            Color.alphaBlend(
              navBase.withValues(alpha: look.sheetFillAlpha ?? 1),
              bg,
            ),
          )
        : navBase;

    Widget bar(double width, Color color) => Container(
      width: width,
      height: 5,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );

    Widget cover(Color a, Color b) => Expanded(
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [a, Color.lerp(b, Colors.black, 0.45)!],
            ),
          ),
          alignment: Alignment.topRight,
          padding: const EdgeInsets.all(3),
          child: look.showExtraCoverBadges
              ? Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                )
              : null,
        ),
      ),
    );

    final mock = SizedBox.fromSize(
      size: canvas,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          gradient: glowAlpha <= 0
              ? null
              : LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.55],
                  colors: [
                    Color.alphaBlend(
                      cs.primary.withValues(alpha: glowAlpha),
                      bg,
                    ),
                    bg,
                  ],
                ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 0),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  bar(40, cs.onSurface.withValues(alpha: 0.75)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 0),
              child: Row(
                children: [
                  cover(cs.primary, cs.tertiary),
                  const SizedBox(width: 8),
                  cover(cs.secondary, cs.primary),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 0),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: panelFill,
                  borderRadius: BorderRadius.circular(8 + boost),
                  border: edge,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(56, cs.onSurface.withValues(alpha: 0.7)),
                    const SizedBox(height: 5),
                    bar(36, cs.onSurfaceVariant.withValues(alpha: 0.5)),
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: 0.4,
                        minHeight: 3,
                        color: cs.primary,
                        backgroundColor: cs.onSurface.withValues(alpha: 0.1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            Container(
              height: 26,
              decoration: BoxDecoration(
                color: navFill,
                border: look.frostedNavBar
                    ? Border(
                        top: BorderSide(color: look.panelEdge(cs.brightness)),
                      )
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (var i = 0; i < 4; i++)
                    Container(
                      width: i == 0 ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == 0
                            ? cs.primary.withValues(alpha: 0.85)
                            : cs.onSurfaceVariant.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FittedBox(fit: BoxFit.contain, child: mock),
      ),
    );
  }
}
