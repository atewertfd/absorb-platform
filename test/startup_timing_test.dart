import 'package:absorb/services/startup_timing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('describe lists the time before main, then each step since main', () {
    expect(
      StartupTiming.describe(
        preMainMs: 850,
        marks: {'first frame': 420, 'signed in': 900, 'home': 1650},
      ),
      '[Startup] launch→main 850ms, main→first frame 420ms, '
      '→signed in 900ms, →home 1650ms (since main)',
    );
  });

  test('describe leaves out the time before main when unknown', () {
    expect(
      StartupTiming.describe(marks: {'home': 1200}),
      '[Startup] →home 1200ms (since main)',
    );
  });

  test('marks before main or after the report are ignored', () async {
    StartupTiming.reset();
    StartupTiming.mark('signed in');
    StartupTiming.markMain();
    StartupTiming.mark('signed in');
    await StartupTiming.markHomeReady();
    StartupTiming.mark('late');
    StartupTiming.reset();
  });
}
