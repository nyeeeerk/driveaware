/// Exponential Moving Average (EMA) filter.
///
/// Useful for smoothing noisy signals (e.g. drowsiness scores, brightness).
/// Lower [alpha] = more smoothing / slower reaction.
/// Higher [alpha] = less smoothing / faster reaction.
class EMA {
  final double alpha;
  double _value = 0.0;
  bool _initialized = false;

  EMA({this.alpha = 0.15});

  double update(double x) {
    _value = _initialized ? alpha * x + (1 - alpha) * _value : x;
    _initialized = true;
    return _value;
  }

  double get value => _value;

  void reset() {
    _value = 0.0;
    _initialized = false;
  }
}
