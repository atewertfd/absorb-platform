import 'package:absorb/utils/wheel_scroll_accumulator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accumulates wheel deltas from the current target', () {
    final accumulator = WheelScrollAccumulator(initialTarget: 100);

    expect(
      accumulator.add(delta: 24, min: 0, max: 500),
      124,
    );
    expect(
      accumulator.add(delta: 36, min: 0, max: 500),
      160,
    );
  });

  test('clamps accumulated targets to both scroll extents', () {
    final accumulator = WheelScrollAccumulator(initialTarget: 100);

    expect(
      accumulator.add(delta: -250, min: 0, max: 500),
      0,
    );
    expect(
      accumulator.add(delta: 700, min: 0, max: 500),
      500,
    );
  });

  test('rebases after an external or user scroll', () {
    final accumulator = WheelScrollAccumulator(initialTarget: 100);
    accumulator.add(delta: 50, min: 0, max: 500);

    accumulator.rebase(20);

    expect(accumulator.target, 20);
    expect(
      accumulator.add(delta: 10, min: 0, max: 500),
      30,
    );
  });
}
