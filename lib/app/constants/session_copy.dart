/// The strings every session-driven screen says the same way.
///
/// Each feature keeps its own copy file for the words only it needs, but
/// the lifecycle vocabulary — connecting, finishing, cancel — reads the
/// same on every tab, so it is written once here and referenced there.
abstract final class SessionCopy {
  static const String connecting = 'Connecting…';
  static const String finishing = 'Finishing…';
  static const String cancel = 'Cancel';
}
