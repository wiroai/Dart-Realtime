/// The `mm:ss` reading every on-screen clock shows.
extension DurationClockLabel on Duration {
  String get clockLabel {
    final minutes = inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
