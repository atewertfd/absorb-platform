import 'package:absorb/utils/app_motion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('instant overrides reduced motion and normal motion', () {
    expect(
      AppMotion.resolveMode(
        eInk: true,
        snappy: false,
        reduceMotion: false,
      ),
      AppMotionMode.instant,
    );
    expect(
      AppMotion.resolveMode(
        eInk: false,
        snappy: true,
        reduceMotion: true,
      ),
      AppMotionMode.instant,
    );
  });

  test('reduced motion removes duration without changing the requested value', () {
    const requested = Duration(milliseconds: 180);
    expect(
      AppMotion.duration(requested, AppMotionMode.reduced),
      Duration.zero,
    );
    expect(
      AppMotion.duration(requested, AppMotionMode.instant),
      Duration.zero,
    );
    expect(
      AppMotion.duration(requested, AppMotionMode.normal),
      requested,
    );
  });
}
