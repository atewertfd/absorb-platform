/// Absorb Plus switches for upstream screens, kept here so the upstream files
/// only gain a one-line check.
abstract final class ForkBranding {
  /// The upstream author's "Support the Dev" (Buy Me a Coffee) card. Absorb
  /// Plus is a separate build, so it doesn't ask for donations on their
  /// behalf; the original project is still credited in the README.
  static const bool showUpstreamSupportCard = false;

  /// Where "Bugs & feature requests" and "Contact" go (owner decision,
  /// 2026-10-30): Absorb Plus reports must not reach the upstream developer,
  /// who doesn't ship this build.
  static const String issuesUrl =
      'https://github.com/atewertfd/absorb-platform/issues';

  /// Upstream's Discord is for the original Absorb, so it's hidden.
  static const bool showUpstreamDiscord = false;

  /// The app name used in log reports.
  static const String appName = 'Absorb Plus';
}
