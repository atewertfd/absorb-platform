/// Keeps the destination of a burst of wheel input ahead of the current
/// position so a smooth driver can consume the burst as one motion.
class WheelScrollAccumulator {
  WheelScrollAccumulator({required double initialTarget})
    : _target = initialTarget;

  double _target;

  double get target => _target;

  double add({
    required double delta,
    required double min,
    required double max,
  }) {
    _target = (_target + delta).clamp(min, max).toDouble();
    return _target;
  }

  void rebase(double pixels) => _target = pixels;
}
