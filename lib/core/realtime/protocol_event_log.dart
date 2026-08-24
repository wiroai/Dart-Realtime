/// Bounded history of realtime protocol events surfaced in the debug panel.
///
/// Only the newest [maximumEvents] entries are retained so that a long running
/// session cannot grow view state without bound.
final class ProtocolEventLog {
  ProtocolEventLog({this.maximumEvents = 40})
    : assert(maximumEvents > 0, 'maximumEvents must be positive');

  final int maximumEvents;

  List<String> _events = const [];

  /// The retained events, oldest first.
  List<String> get events => _events;

  /// Appends [event], dropping the oldest entries past [maximumEvents], and
  /// returns the resulting history.
  List<String> add(String event) {
    final retained = _events.length >= maximumEvents
        ? _events.sublist(_events.length - maximumEvents + 1)
        : _events;
    return _events = [...retained, event];
  }

  void clear() {
    _events = const [];
  }
}
