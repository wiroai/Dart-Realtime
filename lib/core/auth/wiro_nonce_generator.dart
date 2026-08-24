typedef WiroNonceGenerator = String Function();

final class MonotonicWiroNonceGenerator {
  MonotonicWiroNonceGenerator({
    int Function()? microsecondsSinceEpoch,
  }) : _microsecondsSinceEpoch =
           microsecondsSinceEpoch ??
           (() => DateTime.now().microsecondsSinceEpoch);

  final int Function() _microsecondsSinceEpoch;
  int _lastValue = 0;

  String call() {
    final timestamp = _microsecondsSinceEpoch();
    _lastValue = timestamp > _lastValue ? timestamp : _lastValue + 1;
    return _lastValue.toString();
  }
}
