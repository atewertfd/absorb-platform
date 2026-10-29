import 'package:flutter_test/flutter_test.dart';

import 'package:absorb/widgets/nav_hold_options.dart';

void main() {
  test('ReadMeABook shortcuts stay out of the navigation hold menu', () {
    final available = navHoldAllIds(
      isAdmin: true,
      libraryIds: const ['library'],
      rmabConfigured: true,
      rmabWeb: true,
    );
    final defaults = navHoldDefaultMenu(
      isAdmin: true,
      rmabConfigured: true,
      rmabWeb: true,
    );

    for (final id in const ['rmabSearch', 'rmabRequests', 'rmabWeb']) {
      expect(available, isNot(contains(id)));
      expect(defaults, isNot(contains(id)));
    }
  });
}
